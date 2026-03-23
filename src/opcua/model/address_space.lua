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
  if not tools.dataValueValid(val) then
    dataValue = {Type = expectedType, IsArray=isArray, Value = val}
  end

  if not tools.dataValueValid(dataValue) then
    error(BadNodeAttributesInvalid)
  end

  if dataValue.Type ~= expectedType then
    error(BadNodeAttributesInvalid)
  end
  if attrId == AttributeId.Rank and val < -2 then
    error(BadNodeAttributesInvalid)
  end

  return val
end

local function toDataValue(attrId, val, node)
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
      local baseId = node.BaseId
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
          DefaultEncodingId = node.BinaryId,
          BaseDataType = node.BaseId,
          StructureType = structureType,
          Fields = val
        }
      }
      val = body
    end
  elseif attrId == AttributeId.RolePermissions then
    return { StatusCode = Good }
  elseif attrId == AttributeId.UserRolePermissions then
    return { StatusCode = Good }
  elseif attrId == AttributeId.AccessRestrictions then
    expectedType = VariantType.UInt16
  elseif attrId == AttributeId.AccessLevelEx then
    expectedType = VariantType.UInt32
  else
    return { StatusCode = BadAttributeIdInvalid }
  end

  if not val then
    return { StatusCode = Good }
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

local VAttrs = {}

function VAttrs:__newindex(key, value)
  self.Attrs[key] = value
end

function VAttrs:__index(key)
  local k = getAttributeId(key)
  return toDataValue(k, rawget(self.Attrs, "data")[k], self.Node)
end

local function createVAttrs(attrs, node)
  assert(rawget(attrs, "data"))
  local vAttrs = {
    Attrs = attrs,
    Node = node,
  }
  setmetatable(vAttrs, VAttrs)
  return vAttrs
end

local address_space = {}

local function copyNode(n)
  if not n then
    return
  end

  local attrsData = tools.copy(rawget(n.Attrs, "data") or n.Attrs)

  local node = {
    BaseId = n.BaseId,
    BinaryId = n.BinaryId,
    JsonId = n.JsonId,
    DataTypeId = n.DataTypeId,
    Attrs = createNodeAttrs(attrsData),
    Refs = tools.copy(n.Refs) or {}
  }

  node.VAttrs = createVAttrs(node.Attrs, n)

  return node
end

local function getNode(self, nodeId)
  assert(type(nodeId) == 'string')
  local node = self.n[nodeId]
  if node then
    assert(rawget(node.Attrs, "data"))
    return node
  end

  node = self.ns0[nodeId]
  local nodeCopy = copyNode(node)
  return nodeCopy
end

local function saveNode(self, node)
  assert(self ~= nil)
  assert(rawget(node.Attrs, "data"))
  local id = node.Attrs.NodeId
  self.n[id] = node
end

-- iterator over nodes
function address_space:__pairs()
  assert(self ~= nil)
  local n,nn = pairs(self.n)
  local n0,nn0 = pairs(self.ns0)
  local k = nil
  return function()
    local v
    if n then
      k,v = n(nn,k)
      if k then
        assert(rawget(v.Attrs, "data"))
        return k,v
      end
    end
    n = nil
    nn = nil

    k,v = n0(nn0,k)
    return k, copyNode(v)
  end
end

function address_space:__index(id)
  local node <const> = getNode(self, id)
  return node
end

function address_space:__newindex(id, node)
  if not rawget(node.Attrs, "data") then
    error(BadInternalError)
  end
  if id ~= node.Attrs.NodeId then
    error(BadNodeIdInvalid)
  end
  self.n[id] = node
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

local function save(self)
  for key, node in pairs(self.n) do
    self.ns0[key] = node
  end

  self.n = {}
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

  node.VAttrs = createVAttrs(node.Attrs, node)

  return node
end


local function create(ns)
  assert(ns, "ns is required")
  local space ={
    ns0 = ns, -- base namespace
    n = {},   -- new namespace is editable
    saveNode = saveNode, -- save node to the new address space
    save = save,         -- move nodes from new namespace to the base address space
    resolvePath = resolvePath,
    newNode = newNode
  }
  setmetatable(space, address_space)
  return space
end

return create
