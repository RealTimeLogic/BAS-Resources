-- this is a simple address space implementation
-- it is used to store the nodeset and to get nodes by id

-- Format: map of nodeId -> node
-- Node has two fields: Attrs and Refs

-- Attrs is an maps of: {key = attributeId, value = value}
--    key->attributeId is an integer value fromom AttributeId and value depends on attribute value
--    nodeCallback->field is a function that is called when
--        for Variable to read/write Value attribute
--        for Method to execute actual function to be called by client
--    definition: list of fields of a structure:
--        {Name: string, DataType: NodeId, Rank = -1, Value: raw value depends on DataType},

-- Refs is an array of: {type = referenceType, target = nodeId, isForward = boolean}
--    type is a NodeID of the reference type
--    target is a NodeID of the target node
--    isForward is a boolean

local const = require("opcua.const")
local compat = require("opcua.compat")
local memoryProvider = require("opcua.model.memory_provider")
local typeInfo = require("opcua.model.type_info")
local tools = require("opcua.tools")
local StatusCode = require("opcua.status_codes")

local AttributeId = const.AttributeId
local VariantType = const.VariantType
local NodeClass = const.NodeClass
local ValueRank = const.ValueRank
local HierarchicalReferences = "i=33"
local HasSubtype = "i=45"

local BadAttributeIdInvalid = StatusCode.BadAttributeIdInvalid
local BadNodeAttributesInvalid = StatusCode.BadNodeAttributesInvalid
local BadNodeIdInvalid = StatusCode.BadNodeIdInvalid
local BadInternalError = StatusCode.BadInternalError
local BadNodeClassInvalid = StatusCode.BadNodeClassInvalid
local BadNoMatch = StatusCode.BadNoMatch
local BadNodeIdExists = StatusCode.BadNodeIdExists
local BadNodeIdUnknown = StatusCode.BadNodeIdUnknown
local Good = StatusCode.Good

local JSON_NULL = compat.jsonNull
local RESET = memoryProvider.RESET

local attrNames <const> = {}
for id, name in pairs(AttributeId) do
  attrNames[id] = name
end

local commonMask <const> =
  (1 << AttributeId.NodeId) |
  (1 << AttributeId.NodeClass) |
  (1 << AttributeId.BrowseName) |
  (1 << AttributeId.DisplayName) |
  (1 << AttributeId.Description) |
  (1 << AttributeId.WriteMask) |
  (1 << AttributeId.UserWriteMask) |
  (1 << AttributeId.RolePermissions) |
  (1 << AttributeId.UserRolePermissions) |
  (1 << AttributeId.AccessRestrictions)

local variableMask <const> =
  commonMask |
  (1 << AttributeId.Value) |
  (1 << AttributeId.DataType) |
  (1 << AttributeId.Rank) |
  (1 << AttributeId.ArrayDimensions) |
  (1 << AttributeId.AccessLevel) |
  (1 << AttributeId.UserAccessLevel) |
  (1 << AttributeId.MinimumSamplingInterval) |
  (1 << AttributeId.Historizing) |
  (1 << AttributeId.AccessLevelEx)

local variableTypeMask <const> =
  commonMask |
  (1 << AttributeId.Value) |
  (1 << AttributeId.DataType) |
  (1 << AttributeId.Rank) |
  (1 << AttributeId.ArrayDimensions) |
  (1 << AttributeId.IsAbstract)

local dataTypeMask <const> =
  commonMask |
  (1 << AttributeId.IsAbstract) |
  (1 << AttributeId.DataTypeDefinition)

local objectMask <const> =
  commonMask |
  (1 << AttributeId.EventNotifier)

local objectTypeMask <const> =
  commonMask |
  (1 << AttributeId.IsAbstract)

local referenceTypeMask <const> =
  commonMask |
  (1 << AttributeId.IsAbstract) |
  (1 << AttributeId.Symmetric) |
  (1 << AttributeId.InverseName)

local methodTypeMask <const> =
  commonMask |
  (1 << AttributeId.Executable) |
  (1 << AttributeId.UserExecutable)

local viewMask <const> =
  commonMask |
  (1 << AttributeId.ContainsNoLoops) |
  (1 << AttributeId.EventNotifier)

local nodeClassMask <const> = {
  [NodeClass.Variable]      = variableMask,
  [NodeClass.VariableType]  = variableTypeMask,
  [NodeClass.Object]        = objectMask,
  [NodeClass.ReferenceType] = referenceTypeMask,
  [NodeClass.ObjectType]    = objectTypeMask,
  [NodeClass.Method]        = methodTypeMask,
  [NodeClass.DataType]      = dataTypeMask,
  [NodeClass.View]          = viewMask,
}

local directSupertypeId

local function getAttributeId(key)
  if key == "NodeCallback" then
    return key
  end

  if type(key) == "string" then
    key = attrNames[key]
  end

  if type(key) ~= "number" then
    error(BadAttributeIdInvalid)
  end

  return key
end

local function fromDataValue(attrId, val)
  if attrId == AttributeId.Value then
    if val~= nil and not tools.dataValueValid(val) then
      error(BadNodeAttributesInvalid)
    end
    return val
  end

  local expectedType
  local isArray
  if attrId == AttributeId.NodeId then
    expectedType = VariantType.NodeId
  elseif attrId == AttributeId.NodeClass then
    expectedType = VariantType.Int32
  elseif attrId == AttributeId.BrowseName then
    expectedType = VariantType.QualifiedName
  elseif attrId == AttributeId.DisplayName then
    expectedType = VariantType.LocalizedText
  elseif attrId == AttributeId.Description then
    expectedType = VariantType.LocalizedText
  elseif attrId == AttributeId.WriteMask then
    expectedType = VariantType.UInt32
  elseif attrId == AttributeId.UserWriteMask then
    expectedType = VariantType.UInt32
  elseif attrId == AttributeId.IsAbstract then
    expectedType = VariantType.Boolean
  elseif attrId == AttributeId.Symmetric then
    expectedType = VariantType.Boolean
  elseif attrId == AttributeId.InverseName then
    expectedType = VariantType.LocalizedText
  elseif attrId == AttributeId.ContainsNoLoops then
    expectedType = VariantType.Boolean
  elseif attrId == AttributeId.EventNotifier then
    expectedType = VariantType.Byte
  elseif attrId == AttributeId.Value then
    expectedType = VariantType.DataValue
  elseif attrId == AttributeId.DataType then
    expectedType = VariantType.NodeId
  elseif attrId == AttributeId.Rank then
    expectedType = VariantType.Int32
  elseif attrId == AttributeId.ArrayDimensions then
    if val == nil then
      return nil
    end
    isArray = true
    expectedType = VariantType.UInt32
  elseif attrId == AttributeId.AccessLevel then
    expectedType = VariantType.Byte
  elseif attrId == AttributeId.UserAccessLevel then
    expectedType = VariantType.Byte
  elseif attrId == AttributeId.MinimumSamplingInterval then
    expectedType = VariantType.Double
  elseif attrId == AttributeId.Historizing then
    expectedType = VariantType.Boolean
  elseif attrId == AttributeId.Executable then
    expectedType = VariantType.Boolean
  elseif attrId == AttributeId.UserExecutable then
    expectedType = VariantType.Boolean
  elseif attrId == AttributeId.DataTypeDefinition then
    -- expectedType = VariantType.NodeId
    if type(val) ~= "table" or val[1] == nil then
      error(BadNodeAttributesInvalid)
    end
    for _,field in ipairs(val) do
      if field.Value == nil and not tools.nodeIdValid(field.DataType) then
        error(BadNodeAttributesInvalid)
      end
      if type(field.Name) ~= "string" then
        error(BadNodeAttributesInvalid)
      end
      if field.Value ~= nil and type(field.Value) ~= "number" then
        error(BadNodeAttributesInvalid)
      end
      if field.ValueRank ~= nil and type(field.ValueRank) ~= "number" then
        error(BadNodeAttributesInvalid)
      end
    end
    return val
  elseif attrId == AttributeId.RolePermissions then
    error(BadAttributeIdInvalid)
  elseif attrId == AttributeId.UserRolePermissions then
    error(BadAttributeIdInvalid)
  elseif attrId == AttributeId.AccessRestrictions then
    expectedType = VariantType.UInt16
  elseif attrId == AttributeId.AccessLevelEx then
    expectedType = VariantType.UInt32
  else
    error(BadAttributeIdInvalid)
  end


  local dataValue = val
  if type(val) ~= "table" or val.Type == nil then
    dataValue = {Type = expectedType, IsArray=isArray, Value = val}
  end

  if not tools.dataValueValid(dataValue) then
    error(BadNodeAttributesInvalid)
  end

  if dataValue.Type ~= expectedType then
    error(BadNodeAttributesInvalid)
  end
  if attrId == AttributeId.Rank and val < -3 then
    error(BadNodeAttributesInvalid)
  end

  return val
end

local function toDataValue(attrId, val, node)
  local nodeClass = node.Attrs.NodeClass
  local mask = assert(nodeClassMask[nodeClass], "Invalid NodeClass")
  if (mask & (1 << attrId)) == 0 then
    return { StatusCode = BadAttributeIdInvalid }
  end

  if attrId == AttributeId.Value then
    if not val then
      return { StatusCode = Good }
    end

    if not tools.dataValueValid(val) then
      return { StatusCode = BadAttributeIdInvalid }
    end
    if val.StatusCode == nil then
      val.StatusCode = Good
    end
    return val
  end


  local expectedType
  local isArray
  if attrId == AttributeId.NodeId then
    expectedType = VariantType.NodeId
  elseif attrId == AttributeId.NodeClass then
    expectedType = VariantType.Int32
  elseif attrId == AttributeId.BrowseName then
    expectedType = VariantType.QualifiedName
  elseif attrId == AttributeId.DisplayName then
    expectedType = VariantType.LocalizedText
  elseif attrId == AttributeId.Description then
    expectedType = VariantType.LocalizedText
  elseif attrId == AttributeId.WriteMask then
    expectedType = VariantType.UInt32
  elseif attrId == AttributeId.UserWriteMask then
    expectedType = VariantType.UInt32
  elseif attrId == AttributeId.IsAbstract then
    expectedType = VariantType.Boolean
  elseif attrId == AttributeId.Symmetric then
    expectedType = VariantType.Boolean
  elseif attrId == AttributeId.InverseName then
    expectedType = VariantType.LocalizedText
  elseif attrId == AttributeId.ContainsNoLoops then
    expectedType = VariantType.Boolean
  elseif attrId == AttributeId.EventNotifier then
    expectedType = VariantType.Byte
  elseif attrId == AttributeId.Value then
    expectedType = VariantType.DataValue
  elseif attrId == AttributeId.DataType then
    expectedType = VariantType.NodeId
  elseif attrId == AttributeId.Rank then
    expectedType = VariantType.Int32
  elseif attrId == AttributeId.ArrayDimensions then
    isArray = true
    expectedType = VariantType.UInt32
  elseif attrId == AttributeId.AccessLevel then
    expectedType = VariantType.Byte
  elseif attrId == AttributeId.UserAccessLevel then
    expectedType = VariantType.Byte
  elseif attrId == AttributeId.MinimumSamplingInterval then
    expectedType = VariantType.Double
  elseif attrId == AttributeId.Historizing then
    expectedType = VariantType.Boolean
  elseif attrId == AttributeId.Executable then
    expectedType = VariantType.Boolean
  elseif attrId == AttributeId.UserExecutable then
    expectedType = VariantType.Boolean
  elseif attrId == AttributeId.DataTypeDefinition then
    if val then
      local info = node:getTypeInfo()
      if info == nil then
        return { StatusCode = BadInternalError }
      end
      local baseId = info:getBaseId()
      local typeId
      local structureType
      if baseId == "i=22" then
        typeId = "i=99"
        structureType = 0
      elseif baseId == "i=29" then
        typeId = "i=100"
        structureType = 2
      else
        return { StatusCode = BadInternalError }
      end

      -- expectedType = VariantType.NodeId
      if type(val) ~= "table" or val[1] == nil then
        return { StatusCode = BadAttributeIdInvalid }
      end
      for _,field in ipairs(val) do
        if not tools.nodeIdValid(field.DataType) then
          return { StatusCode = BadAttributeIdInvalid }
        end
        if type(field.Name) ~= "string" then
          return { StatusCode = BadAttributeIdInvalid }
        end
        if field.Description == nil then
          field.Description = { Locale = "", Text = "" }
        end

        if baseId == "i=29" then
          if field.DisplayName == nil then
            field.DisplayName = { Locale = "", Text = field.Name }
          end
          if type(field.Value) ~= "number" then
            return { StatusCode = BadAttributeIdInvalid }
          end
        elseif baseId == "i=22" then
          if field.ValueRank == nil then
            field.ValueRank = ValueRank.Scalar
          elseif type(field.ValueRank) ~= "number" then
            return { StatusCode = BadAttributeIdInvalid }
          end
          if field.IsOptional == nil then
            field.IsOptional = false
          end
          if field.MaxStringLength == nil then
            field.MaxStringLength = 0
          end
        end
      end
      expectedType = VariantType.ExtensionObject
      local body = {
        TypeId = typeId,
        Body = {
          DefaultEncodingId = info:getEncodingNodeId("Binary"),
          BaseDataType = info.BaseDataType or info:getBaseId(),
          StructureType = structureType,
          Fields = val
        }
      }
      val = body
    end

  elseif attrId == AttributeId.AccessRestrictions then
    expectedType = VariantType.UInt16
  elseif attrId == AttributeId.AccessLevelEx then
    expectedType = VariantType.UInt32
  else
    return { StatusCode = BadAttributeIdInvalid }
  end

  if val == nil then
    return { StatusCode = BadAttributeIdInvalid }
  end

  local dataValue = {
    Type = expectedType,
    IsArray=isArray,
    Value = val,
    StatusCode = Good
  }
  return dataValue
end

local nodeAttrs = {}

function nodeAttrs:__newindex(key, value)
  key = getAttributeId(key)
  -- NodeId and NodeClass are not writable - delete node and create new one
  if key == AttributeId.NodeId then
    error(BadNodeIdInvalid)
  end
  if key == AttributeId.NodeClass then
    error(BadInternalError)
  end
  -- a value callback is a special case
  if key == "NodeCallback" then
    if type(value) ~= "function" then
      error(BadAttributeIdInvalid)
    end
  -- other attribute IDs must be number
  -- Attribute ID must be in the set of allowed attributes
  elseif (self.mask & (1 << key)) == 0 then
    error(BadAttributeIdInvalid)
  else
    value = fromDataValue(key, value)
  end


  self.data[key] = value
end

function nodeAttrs:__index(key)
  key = getAttributeId(key)
  return self.data[key]
end

local function createNodeAttrs(data)
  local mask = nodeClassMask[data[AttributeId.NodeClass]]
  if not mask then
    error(BadNodeClassInvalid)
  end

  local attrs = {
    data = data,
    mask = mask,
  }

  setmetatable(attrs, nodeAttrs)
  return attrs
end

local address_space = {}

directSupertypeId = function(node)
  for _, ref in ipairs(node.Refs or {}) do
    if ref.type == HasSubtype and ref.isForward == false then
      return ref.target
    end
  end
  return nil
end

local function referenceKey(referenceTypeId, targetNodeId, isForward)
  return #referenceTypeId .. ":" .. referenceTypeId ..
    #targetNodeId .. ":" .. targetNodeId ..
    (isForward and "1" or "0")
end

local function markDirty(node)
  local space = rawget(node, "_space")
  space.dirtyNodes[node] = true
end

local function node_getDataValue(self, attrId)
  local value = self.Attrs[attrId]
  if attrId == AttributeId.DataTypeDefinition then
    local fields = self:iterateFields()
    if fields then
      value = {}
      for _, field in fields do
        value[#value + 1] = field
      end
    end
  end
  return toDataValue(attrId, value, self)
end

local lua_node_mt = {
  __index = function(_, key)
    if key == "getDataValue" then
      return node_getDataValue
    end
  end
}

-- Metatable for the copy-on-write node.Attrs view. Reads merge pending
-- _changes, the writable provider, and the readonly base. Writes only update
-- _changes with a prepared value, JSON_NULL, or RESET until saveNodes().
local proxy_attrs_mt = {
  __index = function(t, k)
    if k == "reset" then
      return function(attrs, attributeId)
        attributeId = getAttributeId(attributeId)
        rawget(attrs, "_changes")[attributeId] = RESET
        markDirty(rawget(attrs, "_proxyNode"))
      end
    end

    local proxyNode = rawget(t, "_proxyNode")
    local space = rawget(proxyNode, "_space")
    local nodeId = rawget(proxyNode, "_nodeId")
    if k == "NodeCallback" then
      local callbackChange = rawget(t, "_callbackChange")
      if callbackChange ~= nil then
        return callbackChange ~= JSON_NULL and callbackChange or nil
      end
      local callback = space.callbacks[nodeId]
      if callback ~= nil then
        return callback ~= JSON_NULL and callback or nil
      end
      local base = rawget(proxyNode, "_base")
      local baseAttrs = base and base.Attrs
      return type(baseAttrs) == "table" and baseAttrs.NodeCallback or nil
    end

    local attributeId = getAttributeId(k)
    local change = rawget(t, "_changes")[attributeId]
    if change ~= nil then
      if change == JSON_NULL then
        return nil
      end
      if change ~= RESET then
        return change
      end
    end

    if change ~= RESET then
      local writable = space.provider:getNode(nodeId)
      local found, value = false, nil
      if writable and writable ~= JSON_NULL then
        found, value = writable:getAttribute(attributeId)
      end
      if found then
        if attributeId == AttributeId.Value and type(value) == "table" and
           space.trackMutableReads then
          local entry = tools.copy(value)
          rawget(t, "_changes")[attributeId] = entry
          markDirty(proxyNode)
          return entry
        end
        return value
      end
    end

    local base = rawget(proxyNode, "_base")
    local baseAttrs = base and base.Attrs
    if base and not baseAttrs then
      error("Invalid base node for " .. tostring(nodeId))
    end
    if baseAttrs then
      local value = baseAttrs[attributeId]
      if attributeId == AttributeId.Value and type(value) == "table" and
         space.trackMutableReads then
        local entry = tools.copy(value)
        rawget(t, "_changes")[attributeId] = entry
        markDirty(proxyNode)
        return entry
      end
      return value
    end
    return nil
  end,
  __newindex = function(t, k, v)
    local proxyNode = rawget(t, "_proxyNode")
    if k == "NodeCallback" then
      if v ~= nil and type(v) ~= "function" then
        error(BadAttributeIdInvalid)
      end
      rawset(t, "_callbackChange", v or JSON_NULL)
      markDirty(proxyNode)
      return
    end

    local attrId = getAttributeId(k)
    local nodeClass = proxyNode.Attrs.NodeClass
    local mask = nodeClassMask[nodeClass]
    if not mask or (mask & (1 << attrId)) == 0 then
      error(BadAttributeIdInvalid)
    end
    if attrId == AttributeId.NodeId then
      error(BadNodeIdInvalid)
    end
    if attrId == AttributeId.NodeClass then
      error(BadInternalError)
    end

    local changes = rawget(t, "_changes")
    if v == nil then
      changes[attrId] = JSON_NULL
    else
      local value = fromDataValue(attrId, v)
      changes[attrId] = tools.copy(value)
    end
    markDirty(proxyNode)
  end,
  __pairs = function(t)
    local proxyNode = rawget(t, "_proxyNode")
    local space = rawget(proxyNode, "_space")
    local nodeId = rawget(proxyNode, "_nodeId")
    local merged = {}
    local base = rawget(proxyNode, "_base")

    if base then
      for attributeId, value in pairs(base.Attrs) do
        merged[attributeId] = value
      end
    end
    local writable = space.provider:getNode(nodeId)
    if writable and writable ~= JSON_NULL then
      for attributeId, value in writable:iterateAttributes() do
        merged[attributeId] = value
      end
    end
    for attributeId, value in pairs(rawget(t, "_changes")) do
      if value == JSON_NULL then
        merged[attributeId] = nil
      elseif value == RESET then
        merged[attributeId] = base and base.Attrs[attributeId] or nil
      else
        merged[attributeId] = value
      end
    end
    local callback = t.NodeCallback
    if callback then
      merged.NodeCallback = callback
    end
    return pairs(merged)
  end
}

local nodeMethods = {}
local getTypeInfo

local function iterateNodeReferences(node)
  local iterate = node and node.iterateReferences
  if type(iterate) == "function" then
    return iterate(node)
  end
  return ipairs(node and node.Refs or {})
end

local readonlyNode

local function mergeReferences(space, nodeId)
  local refs = {}
  local indexes = {}

  local function add(ref)
    local key = referenceKey(ref.type, ref.target, ref.isForward)
    local index = indexes[key]
    if index then
      refs[index] = tools.copy(ref)
    else
      refs[#refs + 1] = tools.copy(ref)
      indexes[key] = #refs
    end
  end

  for _, provider in ipairs(space.readonlyProviders) do
    local node = readonlyNode(provider, nodeId)
    if node then
      for _, ref in iterateNodeReferences(node) do
        add(ref)
      end
    end
  end

  local writable = space.provider:getNode(nodeId)
  if writable and writable ~= JSON_NULL then
    for key, ref in writable:iterateReferences() do
      if ref == nil then
        local index = indexes[key]
        if index then
          refs[index] = false
          indexes[key] = nil
        end
      else
        add(ref)
      end
    end
  end

  local merged = {}
  for _, ref in ipairs(refs) do
    if ref and space.provider:getNode(ref.target) ~= JSON_NULL then
      merged[#merged + 1] = ref
    end
  end
  return merged
end

local proxy_node_mt = {
  __index = function(t, key)
    if key == "Attrs" then
      local attrsProxy = rawget(t, "_attrsProxy")
      if not attrsProxy then
        attrsProxy = setmetatable({
          _proxyNode = t,
          _changes = {},
        }, proxy_attrs_mt)
        rawset(t, "_attrsProxy", attrsProxy)
      end
      return attrsProxy
    end
    if nodeMethods[key] then
      return nodeMethods[key]
    end
    if key == "Refs" then
      local refsProxy = rawget(t, "_refsProxy")
      if not refsProxy then
        local space = rawget(t, "_space")
        local nodeId = rawget(t, "_nodeId")
        refsProxy = mergeReferences(space, nodeId)
        rawset(t, "_refsProxy", refsProxy)
      end
      if rawget(t, "_space").trackMutableReads then
        markDirty(t)
      end
      return refsProxy
    end

    local fieldChanges = rawget(t, "_fieldChanges")
    if fieldChanges[key] ~= nil then
      if fieldChanges[key] == JSON_NULL then
        return nil
      end
      return fieldChanges[key]
    end
    local space = rawget(t, "_space")
    local writable = space.provider:getNode(rawget(t, "_nodeId"))
    local found, value = false, nil
    if writable and writable ~= JSON_NULL then
      found, value = writable:getMetadata(key)
    end
    if found then
      return value
    end
    local base = rawget(t, "_base")
    return base and base[key] or nil
  end,
  __newindex = function(t, key, value)
    if key == "Attrs" or key == "Refs" then
      error(BadInternalError)
    end
    rawget(t, "_fieldChanges")[key] =
      value == nil and JSON_NULL or tools.copy(value)
    markDirty(t)
  end,
  __pairs = function(t)
    local merged = {}
    local base = rawget(t, "_base")
    if base then
      for key, value in pairs(base) do
        merged[key] = value
      end
    end
    local space = rawget(t, "_space")
    local nodeId = rawget(t, "_nodeId")
    local writable = space.provider:getNode(nodeId)
    if writable and writable ~= JSON_NULL then
      for key, value in writable:iterateMetadata() do
        merged[key] = value
      end
    end
    for key, value in pairs(rawget(t, "_fieldChanges")) do
      if value == JSON_NULL then
        merged[key] = nil
      else
        merged[key] = value
      end
    end
    merged.Attrs = t.Attrs
    merged.Refs = t.Refs
    return pairs(merged)
  end
}

nodeMethods.getDataValue = node_getDataValue
local function collectDefinitionFields(node)
  local space = rawget(node, "_space")
  local hierarchy = {}
  local visited = {}
  local current = node

  while current do
    local nodeId = current.Attrs.NodeId
    if visited[nodeId] then
      error(BadInternalError)
    end
    visited[nodeId] = true
    hierarchy[#hierarchy + 1] = current

    local parentId = directSupertypeId(current)
    current = parentId and space[parentId] or nil
  end

  local fields = {}
  local fieldIndexes = {}
  local hasDefinition = false
  for hierarchyIndex = #hierarchy, 1, -1 do
    local definition =
      hierarchy[hierarchyIndex].Attrs.DataTypeDefinition
    if definition ~= nil then
      hasDefinition = true
      for _, field in ipairs(definition) do
        local fieldIndex = fieldIndexes[field.Name]
        if fieldIndex then
          fields[fieldIndex] = field
        else
          fields[#fields + 1] = field
          fieldIndexes[field.Name] = #fields
        end
      end
    end
  end
  return hasDefinition and fields or nil
end

nodeMethods.getDefinition = function(node)
  return collectDefinitionFields(node)
end
nodeMethods.getTypeInfo = function(node)
  return getTypeInfo(
    rawget(node, "_space"), rawget(node, "_nodeId"))
end
nodeMethods.iterateFields = function(node)
  local definition = collectDefinitionFields(node)
  if definition == nil then
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
nodeMethods.iterateReferences = function(node)
  return ipairs(node.Refs)
end
nodeMethods.getReference = function(
  node, referenceTypeId, targetNodeId, isForward)
  for _, ref in ipairs(node.Refs) do
    if ref.type == referenceTypeId and ref.target == targetNodeId and
       ref.isForward == isForward then
      return true, tools.copy(ref)
    end
  end
  return false, nil
end

readonlyNode = function(provider, nodeId)
  local getNodeMethod = provider.getNode
  if type(getNodeMethod) == "function" then
    return getNodeMethod(provider, nodeId)
  end
  return provider[nodeId]
end

local function baseNode(self, nodeId)
  for _, provider in ipairs(self.readonlyProviders) do
    local node = readonlyNode(provider, nodeId)
    if node ~= nil then
      return node
    end
  end
  return nil
end

local function makeProxy(self, nodeId, base)
  return setmetatable({
    _space = self,
    _nodeId = nodeId,
    _base = base,
    _fieldChanges = {},
  }, proxy_node_mt)
end

local function getNode(self, nodeId)
  assert(type(nodeId) == "string")
  local writable = self.provider:getNode(nodeId)
  if writable == JSON_NULL then
    return nil
  end

  local base = baseNode(self, nodeId)
  if not base and not writable then
    return nil
  end
  return makeProxy(self, nodeId, base)
end

getTypeInfo = function(self, nodeId)
  local cached = self.typeInfos[nodeId]
  if cached ~= nil then
    return cached
  end

  local info = typeInfo.resolve(self, nodeId)
  if info == nil then
    return nil
  end

  self.typeInfos[nodeId] = info
  self.typeInfos[info.DataTypeId] = info
  if info.BinaryId then
    self.typeInfos[info.BinaryId] = info
  end
  if info.JsonId then
    self.typeInfos[info.JsonId] = info
  end
  return info
end

local function copyWritableReferences(provider, nodeId)
  local refs = {}
  local node = provider:getNode(nodeId)
  if node == nil or node == JSON_NULL then
    return refs
  end

  for key, ref in node:iterateReferences() do
    if type(key) == "number" then
      refs[#refs + 1] = ref
    else
      refs[key] = ref or JSON_NULL
    end
  end
  return refs
end

local function linkExternalReferences(self, providers)
  local additions = {}

  -- Validate and collect every provider contribution before changing the
  -- writable provider. A missing external target therefore leaves the
  -- composite address space unchanged.
  for _, provider in ipairs(providers) do
    local iterate = provider.iterateExternalReferences
    if type(iterate) == "function" then
      for sourceNodeId, ref in iterate(provider) do
        if self[ref.target] == nil then
          error(
            "external reference target does not exist: " .. ref.target)
        end
        local refs = additions[ref.target]
        if refs == nil then
          refs = {}
          additions[ref.target] = refs
        end
        refs[#refs + 1] = {
          type = ref.type,
          target = sourceNodeId,
          isForward = not ref.isForward,
        }
      end
    end
  end

  local batch = {}
  for targetNodeId, contributed in pairs(additions) do
    local refs = copyWritableReferences(self.provider, targetNodeId)
    local present = {}
    for _, ref in ipairs(self[targetNodeId].Refs) do
      present[referenceKey(ref.type, ref.target, ref.isForward)] = true
    end
    for key, ref in pairs(refs) do
      if type(key) == "string" and ref == JSON_NULL then
        present[key] = true
      end
    end

    local changed = false
    for _, ref in ipairs(contributed) do
      local key = referenceKey(ref.type, ref.target, ref.isForward)
      if not present[key] then
        refs[#refs + 1] = ref
        present[key] = true
        changed = true
      end
    end
    if changed then
      batch[#batch + 1] = {
        NodeId = targetNodeId,
        Attributes = {},
        Refs = refs,
      }
    end
  end

  if #batch > 0 then
    self.provider:save(batch)
  end
end

-- iterator over nodes
function address_space:__pairs()
  local seen = {}
  local providerIndex = 1
  local baseIter
  local baseState
  local baseKey
  local overlayKey
  local readingBase = true

  return function()
    while readingBase do
      if baseIter == nil then
        local provider = self.readonlyProviders[providerIndex]
        if provider == nil then
          readingBase = false
          break
        end
        baseIter, baseState, baseKey = pairs(provider)
      end

      while true do
        local _
        baseKey, _ = baseIter(baseState, baseKey)
        if baseKey == nil then
          providerIndex = providerIndex + 1
          baseIter = nil
          break
        end
        if not seen[baseKey] then
          seen[baseKey] = true
          local node = getNode(self, baseKey)
          if node then
            return baseKey, node
          end
        end
      end
    end

    while true do
      local writable
      overlayKey, writable = next(self.provider.nodes, overlayKey)
      if overlayKey == nil then
        return
      end
      if writable ~= JSON_NULL and
         baseNode(self, overlayKey) == nil then
        return overlayKey, getNode(self, overlayKey)
      end
    end
  end
end

local function addReadonlyProvider(self, provider)
  if provider == nil then
    error(BadInternalError)
  end
  local providers = {}
  for index, current in ipairs(self.readonlyProviders) do
    providers[index] = current
  end
  providers[#providers + 1] = provider
  linkExternalReferences(self, providers)
  self.readonlyProviders[#self.readonlyProviders + 1] = provider
  self.typeInfos = {}
end

function address_space:__index(id)
  local node <const> = getNode(self, id)
  return node
end

function address_space:__newindex(id, node)
  if not node.Attrs then
    error(BadInternalError)
  end
  if id ~= node.Attrs.NodeId then
    error(BadNodeIdInvalid)
  end
  self:saveNodes({node})
end

local function getSubtypes(self, parent, cont)
  if parent == nil then
    return cont
  end

  cont[parent.Attrs[AttributeId.NodeId]] = 1

  local nodeClass = parent.Attrs[AttributeId.NodeClass] -- node class of an inspecting type hierarchy
  for _,ref in ipairs(parent.Refs) do
    if ref.isForward == false then
      goto continue
    end

    if ref.type ~= HasSubtype then
      goto continue
    end

    local subtypeId = ref.target
    local subtype = self[subtypeId]
    if subtype == nil then
      error(BadNodeIdUnknown)
    end

    -- Collect only the same node class
    if subtype.Attrs[AttributeId.NodeClass] ~= nodeClass then
      goto continue
    end

    getSubtypes(self, subtype, cont)
    ::continue::
  end

  return cont
end

local function resolvePath(nodes, node, names)
  assert(node, "node is required")

  if type(names) == "string" then
    names = {names}
  else
    assert(type(names) == "table", "names must be a table")
    assert(names[1], "names must not be empty")
  end

  if type(node) == "string" then
    node = nodes[node]
  end

  for _, element in ipairs(names) do

    if type(element) == "string" then
      element = {
        TargetName = {Name=element},
        ReferenceTypeId = HierarchicalReferences,
        IsInverse = false,
        IncludeSubtypes = true,
      }
    elseif type(element) == "table" then
      element.ReferenceTypeId = element.ReferenceTypeId or HierarchicalReferences
      element.IsInverse = element.IsInverse == nil and false or element.IsInverse
      element.IncludeSubtypes = element.IncludeSubtypes == nil and true or element.IncludeSubtypes
    end

    local refTypes = {}
    local refId = element.ReferenceTypeId
    if element.IncludeSubtypes == true then
      getSubtypes(nodes, nodes[refId], refTypes)
    else
      refTypes[refId] = 1
    end

    local nextNode = nil
    for _, ref in ipairs(node.Refs or {}) do
      if ref.isForward == element.IsInverse then
        goto continue
      end

      if refTypes[ref.type] ~= 1 then
        goto continue
      end

      local targetNode = nodes[ref.target]
      if not targetNode then
        break
      end

      local bn = targetNode.Attrs[AttributeId.BrowseName]
      if bn.Name == element.TargetName or bn.Name == element.TargetName.Name then
        nextNode = targetNode
        break
      end

      ::continue::
    end

    if not nextNode then
      error(BadNoMatch)
    end

    node = nextNode
  end

  return node
end

local function attributesIterator(attrs)
  local data = type(attrs) == "table" and rawget(attrs, "data")
  return pairs(data or attrs)
end

local function referenceDelta(space, nodeId, refs)
  local readonly = {}
  for _, provider in ipairs(space.readonlyProviders) do
    local node = readonlyNode(provider, nodeId)
    if node then
      for _, ref in iterateNodeReferences(node) do
        readonly[referenceKey(ref.type, ref.target, ref.isForward)] = true
      end
    end
  end

  local delta = {}
  local present = {}
  for _, ref in ipairs(refs) do
    local key = referenceKey(ref.type, ref.target, ref.isForward)
    if not present[key] then
      present[key] = true
      if not readonly[key] then
        delta[#delta + 1] = tools.copy(ref)
      end
    end
  end
  for key in pairs(readonly) do
    if not present[key] then
      delta[key] = JSON_NULL
    end
  end
  return delta
end

local function prepareNode(self, node)
  if type(node) ~= "table" and type(node) ~= "userdata" then
    error(BadInternalError)
  end
  if not node.Attrs then
    error(BadInternalError)
  end

  local nodeId = node.Attrs.NodeId
  if not tools.nodeIdValid(nodeId) then
    error(BadNodeIdInvalid)
  end

  local ownProxy = type(node) == "table" and rawget(node, "_space") == self
  local change = {
    Node = node,
    NodeId = nodeId,
    Attributes = {},
  }

  if ownProxy then
    local attrs = node.Attrs
    for attributeId, value in pairs(rawget(attrs, "_changes")) do
      if value == JSON_NULL or value == RESET then
        change.Attributes[attributeId] = value
      else
        change.Attributes[attributeId] = tools.copy(value)
      end
    end

    local callbackChange = rawget(attrs, "_callbackChange")
    if callbackChange ~= nil then
      change.Callback = callbackChange
    end

    local refs = rawget(node, "_refsProxy")
    if refs ~= nil then
      change.Refs = referenceDelta(self, nodeId, refs)
    end

    local fields = rawget(node, "_fieldChanges")
    if next(fields) ~= nil then
      change.Fields = {}
      for key, value in pairs(fields) do
        change.Fields[key] = value
      end
    end
  else
    for attributeId, value in attributesIterator(node.Attrs) do
      if attributeId == "NodeCallback" then
        if value ~= nil and type(value) ~= "function" then
          error(BadAttributeIdInvalid)
        end
        change.Callback = value
      else
        local normalizedId = getAttributeId(attributeId)
        value = fromDataValue(normalizedId, value)
        change.Attributes[normalizedId] = tools.copy(value)
      end
    end

    change.Refs = referenceDelta(self, nodeId, node.Refs or {})
    change.Fields = {}
    for key, value in pairs(node) do
      if key ~= "Attrs" and key ~= "Refs" and
         type(key) == "string" and key:sub(1, 1) ~= "_" then
        change.Fields[key] = tools.copy(value)
      end
    end
    if next(change.Fields) == nil then
      change.Fields = nil
    end
  end

  return change
end

local function saveNodes(self, nodes)
  if type(nodes) ~= "table" then
    error(BadInternalError)
  end

  local batch = {}
  local byNodeId = {}
  for _, node in ipairs(nodes) do
    local change = prepareNode(self, node)
    local previous = byNodeId[change.NodeId]
    if previous then
      for attributeId, entry in pairs(change.Attributes) do
        previous.Attributes[attributeId] = entry
      end
      previous.Refs = change.Refs or previous.Refs
      if change.Fields then
        previous.Fields = previous.Fields or {}
        for key, value in pairs(change.Fields) do
          previous.Fields[key] = value
        end
      end
      if change.Callback ~= nil then
        previous.Callback = change.Callback
      end
    else
      byNodeId[change.NodeId] = change
      batch[#batch + 1] = change
    end
  end

  self.provider:save(batch)
  self.typeInfos = {}

  for _, change in ipairs(batch) do
    if change.Callback ~= nil then
      self.callbacks[change.NodeId] = change.Callback
    end

    local node = change.Node
    if type(node) == "table" and rawget(node, "_space") == self then
      local attrs = rawget(node, "_attrsProxy")
      if attrs then
        rawset(attrs, "_changes", {})
        rawset(attrs, "_callbackChange", nil)
      end
      rawset(node, "_fieldChanges", {})
      self.dirtyNodes[node] = nil
    end
  end
end

local function save(self)
  local dirty = {}
  for node in pairs(self.dirtyNodes) do
    dirty[#dirty + 1] = node
  end
  if #dirty > 0 then
    self:saveNodes(dirty)
  end

  local parent = self.base
  if type(parent) == "table" and parent.provider then
    local batch = {}
    for nodeId, writable in pairs(self.provider.nodes) do
      if writable == JSON_NULL then
        parent:deleteNode(nodeId)
      else
        local attributes = {}
        for attributeId, stored in pairs(writable.Attrs) do
          if stored == JSON_NULL then
            attributes[attributeId] = JSON_NULL
          else
            local _, value = writable:getAttribute(attributeId)
            attributes[attributeId] = value
          end
        end
        batch[#batch + 1] = {
          NodeId = nodeId,
          Attributes = attributes,
          Refs = writable.Refs ~= nil and referenceDelta(
            parent, nodeId, self[nodeId].Refs) or nil,
          Fields = writable.Fields,
        }
        local callbackChange = self.callbacks[nodeId]
        if callbackChange ~= nil then
          parent.callbacks[nodeId] = callbackChange
        end
      end
    end
    parent.provider:save(batch)
  else
    for nodeId, writable in pairs(self.provider.nodes) do
      if writable == JSON_NULL then
        parent[nodeId] = nil
      else
        parent[nodeId] = self[nodeId]
      end
    end
  end

  self.provider:reset()
  self.callbacks = {}
end

local function deleteNode(self, nodeId, deleteTargetReferences)
  if self[nodeId] == nil then
    error(BadNodeIdUnknown)
  end

  local nodesToDelete = {[nodeId] = true}
  if deleteTargetReferences then
    local hierarchicalTypes = getSubtypes(
      self, self[HierarchicalReferences], {})
    local queue = {nodeId}
    local queueIndex = 1
    while queue[queueIndex] ~= nil do
      local parentId = queue[queueIndex]
      queueIndex = queueIndex + 1

      for _, ref in ipairs(mergeReferences(self, parentId)) do
        local childId = ref.target
        if ref.isForward and hierarchicalTypes[ref.type] and
          not nodesToDelete[childId]
        then
          local orphaned = true
          for _, childRef in ipairs(mergeReferences(self, childId)) do
            if not childRef.isForward and
              hierarchicalTypes[childRef.type] and
              not nodesToDelete[childRef.target]
            then
              orphaned = false
              break
            end
          end

          if orphaned then
            nodesToDelete[childId] = true
            queue[#queue + 1] = childId
          end
        end
      end
    end

    local referencedNodes = {}
    for deletedNodeId in pairs(nodesToDelete) do
      for _, ref in ipairs(mergeReferences(self, deletedNodeId)) do
        if not nodesToDelete[ref.target] then
          referencedNodes[ref.target] = self[ref.target]
        end
      end
    end

    local modifiedNodes = {}
    for _, referencedNode in pairs(referencedNodes) do
      local refs = referencedNode.Refs
      for index = #refs, 1, -1 do
        if nodesToDelete[refs[index].target] then
          table.remove(refs, index)
        end
      end
      modifiedNodes[#modifiedNodes + 1] = referencedNode
    end
    self:saveNodes(modifiedNodes)
  end

  for deletedNodeId in pairs(nodesToDelete) do
    self.provider:deleteNode(deletedNodeId)
    self.callbacks[deletedNodeId] = JSON_NULL
  end
  self.typeInfos = {}
end

local function resetNode(self, nodeId)
  self.provider:resetNode(nodeId)
  self.typeInfos = {}
  self.callbacks[nodeId] = nil
end

local function setModel(self, model)
  rawset(self, "model", model)
  self.provider:setModel(model)
end

local function writableNodes(self)
  local nodeId
  return function()
    local writable
    while true do
      nodeId, writable = next(self.provider.nodes, nodeId)
      if nodeId == nil then
        return
      end
      if writable ~= JSON_NULL then
        return nodeId, self[nodeId]
      end
    end
  end
end

local function newNode(self, nodeId, patternAttrs, refs)
  if not tools.nodeIdValid(nodeId) then
    error(BadAttributeIdInvalid)
  end
  if nodeId and self[nodeId] ~= nil then
    error(BadNodeIdExists)
  end

  local attrsData = {}
  if type(patternAttrs) == "table" then
    local data = rawget(patternAttrs, "data")
     attrsData = tools.copy(data or patternAttrs)
  else
    attrsData[AttributeId.NodeClass] = patternAttrs
  end

  attrsData[AttributeId.NodeId] = nodeId

  local node = {
    Attrs = createNodeAttrs(attrsData),
    Refs = tools.copy(refs) or {}
  }

  return setmetatable(node, lua_node_mt)
end


local function create(ns, options)
  assert(ns, "ns is required")
  options = options or {}
  local readonlyProviders = options.readonlyProviders
  if readonlyProviders == nil then
    readonlyProviders = {ns}
  elseif type(readonlyProviders) ~= "table" then
    error(BadInternalError)
  else
    local configured = readonlyProviders
    readonlyProviders = {}
    for index, provider in ipairs(configured) do
      readonlyProviders[index] = provider
    end
    if #readonlyProviders == 0 then
      readonlyProviders[1] = ns
    end
  end

  local space ={
    -- Compatibility alias used by existing tests and model code. Lookup and
    -- iteration use the complete ordered readonlyProviders list.
    base = readonlyProviders[1],
    readonlyProviders = readonlyProviders,
    provider = memoryProvider.new({
      encodeValues = options.encodeValues,
    }),
    callbacks = {},
    dirtyNodes = {},
    typeInfos = {},
    trackMutableReads = options.trackMutableReads == true,
    saveNodes = saveNodes,
    save = save,
    deleteNode = deleteNode,
    resetNode = resetNode,
    addReadonlyProvider = addReadonlyProvider,
    getSubtypes = getSubtypes,
    getTypeInfo = getTypeInfo,
    setModel = setModel,
    writableNodes = writableNodes,
    resolvePath = resolvePath,
    newNode = newNode
  }
  setmetatable(space, address_space)
  linkExternalReferences(space, readonlyProviders)
  return space
end

return create
