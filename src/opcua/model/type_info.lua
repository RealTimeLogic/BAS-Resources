local const = require("opcua.const")

local AttributeId = const.AttributeId
local NodeClass = const.NodeClass

local HAS_ENCODING = "i=38"
local HAS_SUBTYPE = "i=45"

-- These are the built-in types for which model.encoding provides a codec.
local CODEC_BASES = {
  ["i=1"] = true,
  ["i=2"] = true,
  ["i=3"] = true,
  ["i=4"] = true,
  ["i=5"] = true,
  ["i=6"] = true,
  ["i=7"] = true,
  ["i=8"] = true,
  ["i=9"] = true,
  ["i=10"] = true,
  ["i=11"] = true,
  ["i=12"] = true,
  ["i=13"] = true,
  ["i=14"] = true,
  ["i=15"] = true,
  ["i=16"] = true,
  ["i=17"] = true,
  ["i=18"] = true,
  ["i=19"] = true,
  ["i=20"] = true,
  ["i=21"] = true,
  ["i=22"] = true,
  ["i=23"] = true,
  ["i=24"] = true,
  ["i=25"] = true,
  ["i=29"] = true,
}

local TypeInfo = {}
TypeInfo.__index = TypeInfo

local function attribute(node, attributeId, name)
  return node.Attrs[name] or node.Attrs[attributeId]
end

local function directParent(node)
  for _, ref in ipairs(node.Refs or {}) do
    if ref.type == HAS_SUBTYPE and ref.isForward == false then
      return ref.target
    end
  end
end

local function encodingKind(node)
  local browseName = node and
    attribute(node, AttributeId.BrowseName, "BrowseName")
  local name = browseName and browseName.Name
  if name == "Default Binary" then
    return "Binary"
  elseif name == "Default JSON" then
    return "Json"
  end
end

local function dataTypeNode(nodes, node)
  if attribute(node, AttributeId.NodeClass, "NodeClass") ==
     NodeClass.DataType then
    return node
  end

  for _, ref in ipairs(node.Refs or {}) do
    if ref.type == HAS_ENCODING and ref.isForward == false then
      return nodes[ref.target]
    end
  end

  -- Accept metadata from an older packed blob while it is being regenerated.
  local dataTypeId = node.DataTypeId
  return dataTypeId and nodes[dataTypeId] or nil
end

local function baseId(nodes, node)
  local visited = {}
  while node do
    local nodeId = attribute(node, AttributeId.NodeId, "NodeId")
    if visited[nodeId] then
      error("cycle in DataType hierarchy at " .. nodeId)
    end
    visited[nodeId] = true

    if CODEC_BASES[nodeId] then
      return nodeId
    end
    local parentId = directParent(node)
    if parentId ~= nil and CODEC_BASES[parentId] then
      return parentId
    end
    node = parentId and nodes[parentId] or nil
  end
end

local function collectEncodingIds(nodes, node)
  local ids = {}
  for _, ref in ipairs(node.Refs or {}) do
    if ref.type == HAS_ENCODING and ref.isForward == true then
      local kind = encodingKind(nodes[ref.target])
      if kind then
        ids[kind] = ref.target
      end
    end
  end

  -- Accept metadata from an older packed blob while it is being regenerated.
  ids.Binary = ids.Binary or node.BinaryId
  ids.Json = ids.Json or node.JsonId
  return ids
end

function TypeInfo:getBaseId()
  return self.BaseId
end

function TypeInfo:getDataTypeNodeId()
  return self.DataTypeId
end

function TypeInfo:getEncodingNodeId(kind)
  if kind == "JSON" or kind == "Default JSON" then
    kind = "Json"
  elseif kind == "Default Binary" then
    kind = "Binary"
  end
  return self.EncodingIds[kind]
end

function TypeInfo:iterateFields()
  local index = 0
  return function()
    index = index + 1
    local field = self.Fields[index]
    if field ~= nil then
      return index, field
    end
  end, #self.Fields
end

local function resolve(nodes, nodeId)
  local node = nodes[nodeId]
  if node == nil then
    return nil
  end

  local dataType = dataTypeNode(nodes, node)
  if dataType == nil then
    return nil
  end

  local fields = {}
  if type(dataType.iterateFields) == "function" then
    local iterator = dataType:iterateFields()
    if iterator then
      for _, field in iterator do
        fields[#fields + 1] = field
      end
    end
  else
    for _, field in ipairs(
      attribute(
        dataType,
        AttributeId.DataTypeDefinition,
        "DataTypeDefinition") or {}) do
      fields[#fields + 1] = field
    end
  end

  local ids = collectEncodingIds(nodes, dataType)
  local info = {
    DataTypeId =
      attribute(dataType, AttributeId.NodeId, "NodeId"),
    BaseDataType = directParent(dataType),
    BaseId = baseId(nodes, dataType),
    BinaryId = ids.Binary,
    JsonId = ids.Json,
    EncodingIds = ids,
    Fields = fields,
  }
  return setmetatable(info, TypeInfo)
end

return {
  resolve = resolve,
}
