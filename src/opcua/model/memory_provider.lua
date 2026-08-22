-- Writable in-memory address-space provider.
--
-- The composite address space uses one instance as a delta layer over one or
-- more readonly packed providers. It stores added nodes and changes to node
-- attributes, references, and arbitrary node members, while preserving the
-- same lookup interface exposed by packed providers. Value attributes may be
-- stored as binary-encoded DataValues to reduce Lua table overhead.
--
-- JSON_NULL is a tombstone that hides a readonly node or entry. RESET removes
-- a writable attribute delta so the corresponding readonly value is visible
-- again. Values returned to callers are copied to keep stored deltas isolated
-- from later mutations.

local BinaryDecoder = require("opcua.binary.decoder")
local BinaryEncoder = require("opcua.binary.encoder")
local compat = require("opcua.compat")
local const = require("opcua.const")
local ModelEncoding = require("opcua.model.encoding")
local Queue = require("opcua.binary.queue")
local StatusCode = require("opcua.status_codes")
local tools = require("opcua.tools")

local BadEncodingError = StatusCode.BadEncodingError
local BadOutOfMemory = StatusCode.BadOutOfMemory
local AttributeId = const.AttributeId
local Good = StatusCode.Good
local BUFFER_SIZE = 256

local Node = {}
Node.__index = Node

local Provider = {}
Provider.__index = Provider

local JSON_NULL = compat.jsonNull
local RESET = {}

local function referenceKey(referenceTypeId, targetNodeId, isForward)
  return #referenceTypeId .. ":" .. referenceTypeId ..
    #targetNodeId .. ":" .. targetNodeId ..
    (isForward and "1" or "0")
end

-- Node methods.

-- Read an attribute through this stored node view.
function Node:getAttribute(attributeId)
  return self._Provider:getAttribute(self._NodeId, attributeId)
end

-- Iterate over attribute deltas through this stored node view.
function Node:iterateAttributes()
  return self._Provider:iterateAttributes(self._NodeId)
end

-- Read an arbitrary node member stored outside Attrs and Refs.
function Node:getMetadata(key)
  return self._Provider:getMetadata(self._NodeId, key)
end

-- Return resolved datatype information for this node when a model is attached.
function Node:getTypeInfo()
  return self._Provider:getTypeInfo(self._NodeId)
end

-- Iterate over the complete datatype field hierarchy used by encoders.
-- Without a model, fall back to the locally stored DataTypeDefinition.
function Node:iterateFields()
  local info = self:getTypeInfo()
  if info ~= nil then
    return info:iterateFields()
  end

  -- A standalone provider has no composite address space from which TypeInfo
  -- can be resolved. It can still expose a locally stored raw definition.
  local found, definition =
    self:getAttribute(AttributeId.DataTypeDefinition)
  if not found or definition == nil then
    return nil, 0
  end

  local index = 0
  return function()
    index = index + 1
    local field = definition[index]
    if field ~= nil then
      return index, field
    end
  end, #definition
end

-- Iterate over arbitrary node members stored outside Attrs and Refs.
function Node:iterateMetadata()
  return self._Provider:iterateMetadata(self._NodeId)
end

-- Look up one reference delta by its complete identity.
-- Returns false when absent, true and nil when deleted, or true and a copy.
function Node:getReference(referenceTypeId, targetNodeId, isForward)
  local refs = self.Refs or {}
  local key = referenceKey(
    referenceTypeId, targetNodeId, isForward)
  if refs[key] == JSON_NULL then
    return true, nil
  end
  for _, ref in ipairs(refs) do
    if ref.type == referenceTypeId and ref.target == targetNodeId and
       ref.isForward == isForward then
      return true, tools.copy(ref)
    end
  end
  return false, nil
end

-- Iterate over added references and reference tombstones.
-- Tombstones use their stable reference key and return nil as the value.
function Node:iterateReferences()
  local refs = self.Refs or {}
  local index = 0
  local key
  return function()
    index = index + 1
    local ref = refs[index]
    if ref ~= nil then
      return index, tools.copy(ref)
    end

    while true do
      key, ref = next(refs, key)
      if key == nil then
        return
      end
      if type(key) == "string" then
        if ref == JSON_NULL then
          return key, nil
        end
        return key, tools.copy(ref)
      end
    end
  end
end

-- Return this node's directly stored DataTypeDefinition, without inheritance.
function Node:getDefinition()
  local found, value =
    self:getAttribute(AttributeId.DataTypeDefinition)
  return found and value or nil
end

-- Return the built-in base datatype used to select an encoder codec.
function Node:getBaseId()
  local info = self:getTypeInfo()
  return info and info:getBaseId() or nil
end

-- Return the datatype NodeId represented by this datatype or encoding node.
function Node:getDataTypeNodeId()
  local info = self:getTypeInfo()
  return info and info:getDataTypeNodeId() or nil
end

-- Return this datatype's NodeId for the requested encoding kind.
function Node:getEncodingNodeId(encodingKind)
  local info = self:getTypeInfo()
  return info and info:getEncodingNodeId(encodingKind) or nil
end

-- Provider helpers.

local function copyReferences(refs)
  local copy = {}
  for index, ref in ipairs(refs) do
    copy[index] = tools.copy(ref)
  end
  for key, ref in pairs(refs) do
    if type(key) == "string" then
      copy[key] = ref == JSON_NULL and JSON_NULL or tools.copy(ref)
    end
  end
  return copy
end

local function normalizedDataValue(value)
  if not tools.dataValueValid(value) then
    error(BadEncodingError)
  end

  -- Good is the default StatusCode and is omitted from the binary encoding.
  if value.StatusCode ~= Good then
    return value
  end

  local copy = {}
  for key, field in pairs(value) do
    if key ~= "StatusCode" then
      copy[key] = field
    end
  end
  return copy
end

local function createCodecs(self, bufferSize)
  self.bufferSize = bufferSize
  self.queue = Queue.new(bufferSize)
  self.encoder = BinaryEncoder.new(self.queue)
  self.decoder = BinaryDecoder.new(self.queue)
  if self.model then
    self.encoderContext =
      ModelEncoding.CreateEncoder(self.model, self.encoder, "Binary")
    self.decoderContext =
      ModelEncoding.CreateDecoder(self.model, self.decoder, "Binary")
  end
end

-- Provider methods.

-- Set the composite model used to resolve and encode structured data types.
-- Replacing the model also invalidates every cached TypeInfo.
function Provider:setModel(model)
  self.model = model
  self.typeInfos = {}
  if model then
    self.encoderContext =
      ModelEncoding.CreateEncoder(model, self.encoder, "Binary")
    self.decoderContext =
      ModelEncoding.CreateDecoder(model, self.decoder, "Binary")
  else
    self.encoderContext = nil
    self.decoderContext = nil
  end
end

-- Encode a DataValue for compact storage, growing the shared buffer as needed.
function Provider:encodeDataValue(value)
  value = normalizedDataValue(value)
  while true do
    self.queue:clear()
    self.encoder.bits_count = 0
    self.encoder.bits = 0
    local success, err = pcall(
      self.encoder.dataValue,
      self.encoder,
      value,
      self.encoderContext)
    if success then
      return tostring(self.queue)
    end
    if err ~= BadOutOfMemory then
      error(err, 0)
    end
    createCodecs(self, self.bufferSize * 2)
  end
end

-- Decode a DataValue previously produced by encodeDataValue.
function Provider:decodeDataValue(encoded)
  self.queue:clear()
  self.decoder.bitNum = 0
  self.queue:pushBack(encoded)
  return self.decoder:dataValue(self.decoderContext)
end

-- Return the stored node delta, JSON_NULL for a deleted node, or nil when the
-- provider has no entry for nodeId.
function Provider:getNode(nodeId)
  return self.nodes[nodeId]
end

-- Iterate over all node deltas, including JSON_NULL node tombstones.
function Provider:iterateNodes()
  return next, self.nodes, nil
end

-- Read one attribute delta.
-- Returns false when no delta exists, true and nil for a tombstone, or true
-- and a copy of the stored value.
function Provider:getAttribute(nodeId, attributeId)
  local node = self.nodes[nodeId]
  if node == nil or node == JSON_NULL then
    return false
  end

  local entry = node.Attrs[attributeId]
  if entry == nil then
    return false
  end
  if entry == JSON_NULL then
    return true, nil
  end
  if attributeId == AttributeId.Value then
    return true, type(entry) == "string" and
      self:decodeDataValue(entry) or tools.copy(entry)
  end
  return true, tools.copy(entry)
end

-- Iterate over a node's attribute deltas.
-- A tombstoned attribute is returned as attributeId, nil.
function Provider:iterateAttributes(nodeId)
  local node = self.nodes[nodeId]
  local entries = node ~= JSON_NULL and node and node.Attrs or nil
  if not entries then
    return function() end
  end

  local attributeId
  return function()
    local entry
    attributeId, entry = next(entries, attributeId)
    if attributeId == nil then
      return
    end
    if entry == JSON_NULL then
      return attributeId, nil
    end
    if attributeId == AttributeId.Value then
      return attributeId, type(entry) == "string" and
        self:decodeDataValue(entry) or tools.copy(entry)
    end
    return attributeId, tools.copy(entry)
  end
end

-- Read an arbitrary node-member delta stored outside Attrs and Refs.
-- The return contract is the same found/value pair used by getAttribute.
function Provider:getMetadata(nodeId, key)
  local node = self.nodes[nodeId]
  if node == nil or node == JSON_NULL or node.Fields == nil then
    return false
  end

  local entry = node.Fields[key]
  if entry == nil then
    return false
  end
  if entry == JSON_NULL then
    return true, nil
  end
  return true, tools.copy(entry)
end

-- Resolve and cache datatype information through the attached composite model.
function Provider:getTypeInfo(nodeId)
  local info = self.typeInfos[nodeId]
  if info ~= nil or self.model == nil then
    return info
  end

  info = self.model.Nodes:getTypeInfo(nodeId)
  if info ~= nil then
    self.typeInfos[nodeId] = info
  end
  return info
end

-- Iterate over arbitrary node-member deltas stored outside Attrs and Refs.
-- A tombstoned member is returned as key, nil.
function Provider:iterateMetadata(nodeId)
  local node = self.nodes[nodeId]
  local entries =
    node ~= JSON_NULL and node and node.Fields or nil
  if not entries then
    return function() end
  end

  local key
  return function()
    local entry
    key, entry = next(entries, key)
    if key == nil then
      return
    end
    if entry == JSON_NULL then
      return key, nil
    end
    return key, tools.copy(entry)
  end
end

-- Prepare and apply a batch of node deltas.
-- Values are encoded or copied before any visible node is changed. JSON_NULL
-- creates a tombstone; RESET removes an attribute delta.
function Provider:save(batch)
  local prepared = {}

  -- Prepare the complete batch before publishing any entry. Encoding errors or
  -- copy failures therefore leave the visible provider unchanged.
  for _, change in ipairs(batch) do
    local item = {
      NodeId = change.NodeId,
      Attributes = {},
      Refs = change.Refs ~= nil and copyReferences(change.Refs) or nil,
      Fields = nil,
    }
    for attributeId, value in pairs(change.Attributes) do
      if value == JSON_NULL or value == RESET then
        item.Attributes[attributeId] = value
      elseif attributeId == AttributeId.Value then
        item.Attributes[attributeId] = self.encodeValues and
          self:encodeDataValue(value) or tools.copy(value)
      else
        item.Attributes[attributeId] = tools.copy(value)
      end
    end
    if change.Fields ~= nil then
      item.Fields = {}
      for key, value in pairs(change.Fields) do
        item.Fields[key] =
          value == JSON_NULL and value or tools.copy(value)
      end
    end
    prepared[#prepared + 1] = item
  end

  for _, change in ipairs(prepared) do
    local nodeId = change.NodeId
    local node = self.nodes[nodeId]
    if node == nil or node == JSON_NULL then
      node = setmetatable({
        _Provider = self,
        _NodeId = nodeId,
        Attrs = {},
      }, Node)
      self.nodes[nodeId] = node
    end

    for attributeId, entry in pairs(change.Attributes) do
      if entry == RESET then
        node.Attrs[attributeId] = nil
      else
        node.Attrs[attributeId] = entry
      end
    end

    if change.Refs ~= nil then
      node.Refs = copyReferences(change.Refs)
    end
    if change.Fields ~= nil then
      node.Fields = node.Fields or {}
      for key, entry in pairs(change.Fields) do
        node.Fields[key] = entry
      end
    end
  end
  self.typeInfos = {}
end

-- Hide a node from readonly providers by storing a node tombstone.
function Provider:deleteNode(nodeId)
  self.nodes[nodeId] = JSON_NULL
  self.typeInfos = {}
end

-- Remove the complete writable delta so readonly providers are visible again.
function Provider:resetNode(nodeId)
  self.nodes[nodeId] = nil
  self.typeInfos = {}
end

-- Remove every writable delta and cached TypeInfo from this provider.
function Provider:reset()
  self.nodes = {}
  self.typeInfos = {}
end

local function new()
  local provider = setmetatable({
    encodeValues = true,
    nodes = {},
    typeInfos = {},
    RESET = RESET,
  }, Provider)
  createCodecs(provider, BUFFER_SIZE)
  return provider
end

return {
  new = function(options)
    local provider = new()
    if options and options.encodeValues == false then
      provider.encodeValues = false
    end
    return provider
  end,
  RESET = RESET,
}
