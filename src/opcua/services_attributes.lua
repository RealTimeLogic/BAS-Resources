--
-- Functions for creating datavalues
--
local ua = require("opcua.api")
local s = ua.StatusCode

local BadAttributeIdInvalid = s.BadAttributeIdInvalid
local BadTypeMismatch = s.BadTypeMismatch
local BadNodeClassInvalid = s.BadNodeClassInvalid
local BadInternalError = s.BadInternalError

local t = ua.Tools
local AttributeId = ua.AttributeId

local Boolean = "i=1"
local SByte = "i=2"
local Byte = "i=3"
local Int16 = "i=4"
local UInt16 = "i=5"
local Int32 = "i=6"
local UInt32 = "i=7"
local Int64 = "i=8"
local UInt64 = "i=9"
local Float = "i=10"
local Double = "i=11"
local String = "i=12"
local DateTime = "i=13"
local Guid = "i=14"
local ByteString = "i=15"
local XmlElement = "i=16"
local NodeId = "i=17"
local ExpandedNodeId = "i=18"
local StatusCode = "i=19"
local QualifiedName = "i=20"
local LocalizedText = "i=21"
--local Structure = "i=22"
local DataValue = "i=23"
local BaseDataType = "i=24"
local Variant = "i=24"
local DiagnosticInfo = "i=25"
--local Number = "i=26"
--local Integer = "i=27"
local HasSubtype = "i=45"
local ExtensionObject = "i=22"
local UtcTime = "i=294"

local function createBadAttribute()
  return { StatusCode = BadAttributeIdInvalid}
end

local function getValue(attr, dataType)
  if type(attr) == 'table' and attr.Value ~= nil then
    if not t.dataValueValid(attr) then
      error(BadInternalError)
    end
    return attr
  end

  if attr == nil  then
    return createBadAttribute()
  end

  local variant = {}
  if dataType == Boolean then
    variant.Type = ua.VariantType.Boolean
  elseif dataType == SByte then
    variant.Type = ua.VariantType.SByte
  elseif dataType == Byte then
    variant.Type = ua.VariantType.Byte
  elseif dataType == Int16 then
    variant.Type = ua.VariantType.Int16
  elseif dataType == UInt16 then
    variant.Type = ua.VariantType.UInt16
  elseif dataType == Int32 then
    variant.Type = ua.VariantType.Int32
  elseif dataType == UInt32 then
    variant.Type = ua.VariantType.UInt32
  elseif dataType == Int64 then
    variant.Type = ua.VariantType.Int64
  elseif dataType == UInt64 then
    variant.Type = ua.VariantType.UInt64
  elseif dataType == Float then
    variant.Type = ua.VariantType.Float
  elseif dataType == Double then
    variant.Type = ua.VariantType.Double
  elseif dataType == String then
    variant.Type = ua.VariantType.String
  elseif dataType == DateTime or dataType == 294 then
    variant.Type = ua.VariantType.DateTime
  elseif dataType == Guid then
    variant.Type = ua.VariantType.Guid
  elseif dataType == ByteString then
    variant.Type = ua.VariantType.ByteString
  elseif dataType == XmlElement then
    return createBadAttribute()
  elseif dataType == NodeId then
    variant.Type = ua.VariantType.NodeId
  elseif dataType == ExpandedNodeId then
    variant.Type = ua.VariantType.ExpandedNodeId
  elseif dataType == StatusCode then
    variant.Type = ua.VariantType.StatusCode
  elseif dataType == QualifiedName then
    assert(t.qualifiedNameValid(attr))
    variant.Type = ua.VariantType.QualifiedName
    if (attr.ns == nil) then
      attr.ns = 0
    end
  elseif dataType == LocalizedText then
    assert(t.localizedTextValid(attr));
    variant.Type = ua.VariantType.LocalizedText
  elseif dataType == ExtensionObject then
    variant.Type = ua.VariantType.ExtensionObject
  elseif dataType == DataValue then
    return createBadAttribute()
  elseif dataType == Variant then
    return createBadAttribute()
  elseif dataType == DiagnosticInfo then
    return createBadAttribute()
  else
    return {
      StatusCode = BadInternalError
    }
  end

  variant.Value = attr
  variant.StatusCode = 0

  return variant
end

local function getCommonAttribute(attrs, attrId)
  if attrId < 0 or attrId > 27 then
    return createBadAttribute()
  end

  local attr = attrs[attrId]

  if attrId <= AttributeId.DisplayName then
    if attr == nil then
      error(BadInternalError)
    end

    if attrId == AttributeId.NodeId then
      return getValue(attr, NodeId)
    elseif attrId == AttributeId.NodeClass then
      return getValue(attr, Int32)
    elseif attrId == AttributeId.BrowseName then
      return getValue(attr, QualifiedName)
    elseif attrId == AttributeId.DisplayName then
      return getValue(attr, LocalizedText)
    end
  end

  if attrId == AttributeId.WriteMask then
    -- disable changing all attributes
    return getValue(attr or 0, UInt32)
  elseif attrId == AttributeId.UserWriteMask then
    -- disable changing all attributes
    return getValue(attr or 0, UInt32)
  end

  if attrId == AttributeId.Description then
    if attr == nil then
      return {StatusCode = 0}
    end
    return getValue(attr, LocalizedText)
  elseif attrId == AttributeId.RolePermissions then
    return getValue(nil, nil)
  elseif attrId == AttributeId.UserRolePermissions then
    return getValue(nil, nil)
  elseif attrId == AttributeId.AccessRestrictions then
    return getValue(attr, UInt16)
  end

  return createBadAttribute()
end

local function getObjectAttribute(attrs, attrId, nodeset)
  if attrId == AttributeId.EventNotifier then
    return getValue(attrs[attrId] or 0, Byte)
  else
    return getCommonAttribute(attrs, attrId, nodeset)
  end
end

local function getViewAttribute(attrs, attrId, nodeset)
  if attrId == AttributeId.EventNotifier then
    return getValue(attrs[attrId] or 0, Byte)
  elseif attrId == AttributeId.ContainsNoLoops then
    return getValue(attrs[attrId] or false, Boolean)
  else
    return getCommonAttribute(attrs, attrId, nodeset)
  end
end

local function getObjectTypeAttribute(attrs, attrId, nodeset)
  if attrId == AttributeId.IsAbstract then
    return getValue(attrs[attrId] or false, Boolean)
  else
    return getCommonAttribute(attrs, attrId, nodeset)
  end
end


local function getRefTypeAttribute(attrs, attrId, nodeset)
  if attrId == AttributeId.IsAbstract then
    return getValue(attrs[attrId] or false, Boolean)
  elseif attrId == AttributeId.Symmetric then
    return getValue(attrs[attrId] or false, Boolean)
  elseif attrId == AttributeId.InverseName then
    return getValue(attrs[attrId], LocalizedText)
  else
    return getCommonAttribute(attrs, attrId, nodeset)
  end
end

local function getVariableAttribute(attrs, attrId, nodeset)

  local attr = attrs[attrId]

  if attrId == AttributeId.Value then
    if attrs.valueSource ~= nil then
      return getValue(attrs.valueSource(attrs[AttributeId.NodeId]), attrs[AttributeId.DataType])
    else
      if attr == nil then return {StatusCode = 0} end
      return getValue(attrs[attrId], attrs[AttributeId.DataType])
    end
  elseif attrId == AttributeId.DataType then
    if attr == nil then error(BadInternalError) end
    return getValue(attr, NodeId)
  elseif attrId == AttributeId.Rank then
    return getValue(attr or -2, Int32)
  elseif attrId == AttributeId.ArrayDimensions then
    local res = getValue(attr, UInt32)
    if res.Value then
      res.IsArray = true
    end
    return res
  elseif attrId == AttributeId.AccessLevel then
    return getValue(attr or 0, Byte)
  elseif attrId == AttributeId.UserAccessLevel then
    return getValue(attr or 0, Byte)
  elseif attrId == AttributeId.MinimumSamplingInterval then
    return getValue(attr or 0, Double)
  elseif attrId == AttributeId.Historizing then
    return getValue(attr or false, Boolean)
  elseif attrId == AttributeId.AccessLevelEx then
    return getValue(attr, UInt32)
  else
    return getCommonAttribute(attrs, attrId, nodeset)
  end
end

local function getVariableTypeAttribute(attrs, attrId, nodeset)
  -- Mandatory
  if attrId == AttributeId.DataType then
    return getValue(attrs[attrId], NodeId)
  elseif attrId == AttributeId.Rank then
    return getValue(attrs[attrId] or -2, Int32)
  elseif attrId == AttributeId.IsAbstract then
    return getValue(attrs[attrId] or false, Boolean)
  -- Optional
  elseif attrId == AttributeId.Value then
    local attr = attrs[attrId]
    if attr == nil then return {StatusCode = 0} end
    return getValue(attr, attrs[AttributeId.DataType])
  elseif attrId == AttributeId.ArrayDimensions then
    local attr = getValue(attrs[attrId], UInt32)
    if attr and attr.Value then
      attr.IsArray = true
    end
    return attr
else
    return getCommonAttribute(attrs, attrId, nodeset)
  end
end

local function getDataTypeAttribute(attrs, attrId, nodeset)
  -- Mandatory
  if attrId == AttributeId.IsAbstract then
    local v = attrs[attrId]
    return getValue(v, Boolean)
  -- Optional
  elseif attrId == AttributeId.DataTypeDefinition then
    return getValue(attrs[attrId], NodeId)
  else
    return getCommonAttribute(attrs, attrId, nodeset)
  end
end

local function getMethodAttribute(attrs, attrId, nodeset)
  -- Mandatory
  if attrId == AttributeId.Executable or attrId == AttributeId.UserExecutable then
    return getValue(attrs[attrId] or false, Boolean)
  else
    return getCommonAttribute(attrs, attrId, nodeset)
  end
end


local function checkDataType(val, dataType, nodeset)
  if val == nil then
    return
  end

  if type(dataType) == 'string' then
    -- if datatype is a node id in string representation
    local tt = ua.NodeId.fromString(dataType).id
    while tt >= AttributeId.Max and nodeset ~= nil do
      local n = nodeset[dataType]
      if n == nil then return s.NodeIdUnknown end
      for _,ref in ipairs(n.refs) do
        if ref.type == HasSubtype and ref.isForward == false then
          dataType = ref.target
          tt = ua.NodeId.fromString(dataType).id
          break
        end
      end
    end
    if dataType == BaseDataType then
      if not t.variantValid(val)  then
        error(BadTypeMismatch)
      end
    end
  end

  if type(dataType) == 'table' and dataType.id ~= nil then
    assert(dataType.ns == nil or dataType.ns == 0, "Supported only builtin variant types from ns=0.")
  end

  if dataType == UtcTime then
    dataType = DateTime
  end

  local vt = t.getVariantTypeId(val)
  local isValid = (dataType == "i=24" or vt == dataType or vt == ExtensionObject) and t.variantValid(val)
  if isValid == false then
    error(BadTypeMismatch)
  end
end


local function checkCommonAttribute(attrId, val, nodeset)
  -- local val = attrs[attrId]
  if attrId == AttributeId.NodeId then
    checkDataType(val, NodeId, nodeset)
  elseif attrId == AttributeId.NodeClass then
    checkDataType(val, Int32, nodeset)
  elseif attrId == AttributeId.BrowseName then
    checkDataType(val, QualifiedName, nodeset)
  elseif attrId == AttributeId.DisplayName then
    checkDataType(val, LocalizedText, nodeset)
  elseif attrId == AttributeId.Description then
    checkDataType(val, LocalizedText, nodeset)
  elseif attrId == AttributeId.WriteMask then
    checkDataType(val, UInt32, nodeset)
  elseif attrId == AttributeId.UserWriteMask then
    checkDataType(val, UInt32, nodeset)
  else
    error(BadAttributeIdInvalid)
  end
end

local function checkObjectAttribute(attrId, val, nodeset)
  if attrId == AttributeId.EventNotifier then
    checkDataType(val, Byte, nodeset)
  else
    checkCommonAttribute(attrId, val, nodeset)
  end
end

--[[
  TODO
local function CheckRefTypeAttribute(attrs, attrId)
  if attrId == AttributeId.IsAbstract then
    checkDataType(attrs[AttributeId.IsAbstract], Boolean)
  elseif attrId == AttributeId.Symmetric then
    checkDataType(attrs[AttributeId.Symmetric], Boolean)
  elseif attrId == AttributeId.InverseName then
    checkDataType(attrs[AttributeId.InverseName], LocalizedText)
  else
    checkCommonAttribute(attrs, attrId, nodeset)
  end
end
--]]

local function checkVariableAttribute(attrs, attrId, val, nodeset)
  if attrId == AttributeId.Value then
    if not t.dataValueValid(val) then
        error(BadAttributeIdInvalid)
    end
    checkDataType(val, attrs[AttributeId.DataType], nodeset)
  elseif attrId == AttributeId.DataType then
    checkDataType(val, NodeId, nodeset)
  elseif attrId == AttributeId.ValueRank then
    checkDataType(val, Int32, nodeset)
  elseif attrId == AttributeId.ArrayDimensions then
    checkDataType(val, UInt32, nodeset)
  elseif attrId == AttributeId.AccessLevel then
    checkDataType(val, Byte, nodeset)
  elseif attrId == AttributeId.UserAccessLevel then
    checkDataType(val, Byte, nodeset)
  elseif attrId == AttributeId.MinimumSamplingInterval then
    checkDataType(val, Double, nodeset)
  elseif attrId == AttributeId.Historizing then
    checkDataType(val, Boolean, nodeset)
  elseif attrId == AttributeId.AccessLevelEx then
    checkDataType(val, UInt32, nodeset)
  else
    checkCommonAttribute(attrId, val, nodeset)
  end
end


return {
  getAttributeValue = function (attrs, attrId)
    local nodeClass = attrs[AttributeId.NodeClass]
    local val
    if type(nodeClass) ~= 'number' or (nodeClass & (nodeClass - 1) ~= 0) then
      error(BadNodeClassInvalid)
    end

    if nodeClass == ua.NodeClass.Object then
      val = getObjectAttribute(attrs, attrId)
    elseif nodeClass == ua.NodeClass.ObjectType then
      val = getObjectTypeAttribute(attrs, attrId)
    elseif nodeClass == ua.NodeClass.ReferenceType then
      val = getRefTypeAttribute(attrs, attrId)
    elseif nodeClass == ua.NodeClass.Variable then
      val = getVariableAttribute(attrs, attrId)
    elseif nodeClass == ua.NodeClass.VariableType then
      val = getVariableTypeAttribute(attrs, attrId)
    elseif nodeClass == ua.NodeClass.DataType then
      val = getDataTypeAttribute(attrs, attrId)
    elseif nodeClass == ua.NodeClass.Method then
      val = getMethodAttribute(attrs, attrId)
    elseif nodeClass == ua.NodeClass.View then
      val = getViewAttribute(attrs, attrId)
    else
      val = getCommonAttribute(attrs, attrId)
    end

    return val
  end,

  checkAttributeValue = function(attrs, attrId, dataValue, nodeset)
    if attrId < 0 or attrId > AttributeId.Max then
      error(BadAttributeIdInvalid)
    end

    local nodeClass = attrs[AttributeId.NodeClass]
    if nodeClass == ua.NodeClass.Variable then
      checkVariableAttribute(attrs, attrId, dataValue, nodeset)
    elseif nodeClass == ua.NodeClass.Object then
      checkObjectAttribute(attrId, dataValue, nodeset)
    end
  end,

  checkDataType = checkDataType,
  createValue = getValue
}
