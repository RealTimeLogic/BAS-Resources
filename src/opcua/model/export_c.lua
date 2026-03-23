local const = require("opcua.const")
local VariantType = const.VariantType

local function newVariableName(context)
  local count = context.varCount
  count = count + 1
  context.varCount = count
  return "variable_"..count
end

local function saveStringVariable(context, str, output)
  local varName = context.stringVars[str]
  if varName then
    return varName
  end

  local count = context.stringVars.count
  count = count + 1
  varName = "str_" .. count
  output(string.format("static const char %s[] = \"%s\";", varName, str))

  context.stringVars[str] = varName
  context.stringVars.count = count
  return varName
end

local function saveNodeIds(self, context, output)
  local i = context.stringVars.count
  for nodeId in pairs(self.Nodes) do
    local varName = "nodeId_" .. i
    context.stringVars[nodeId] = varName
    i = i + 1

    output(string.format("static const char %s[] = \"%s\";", varName, nodeId))

  end
  context.stringVars.count = i
end

local function getStringUaValue(context, value, output)
  if value == nil then
    return string.format("{.str=NULL}")
  elseif type(value) == "string" then
    local varValueName = saveStringVariable(context, value, output)
    return string.format("{.str=%s}", varValueName)
  elseif type(value[1]) == 'string' then
    local valueSize = #value
    local vars = {}
    for _, v in ipairs(value) do
      local varValueName = saveStringVariable(context, v, output)
      table.insert(vars, varValueName)
    end
    local varName = newVariableName(context)
    output(string.format("static const char *%s[] = {", varName))
    for _, v in ipairs(vars) do
      output(string.format("%s,", v))
    end
    output("};")

    return string.format("{.strArr=%s}", varName), valueSize
  else
    error("invalid string value")
  end
end

local function getLocalizedTextUaValue(context, value, output)
  if type(value.Text) == "string" then
    local varValueName = saveStringVariable(context, value.Text, output)
    return string.format("{.str=%s}", varValueName)
  elseif type(value) == 'table' and type(value[1].Text) == "string" then
    local valueSize = #value
    local vars = {}
    for _, v in ipairs(value) do
      local varValueName = saveStringVariable(context, v.Text, output)
      table.insert(vars, varValueName)
    end
    local varName = newVariableName(context)
    output(string.format("static const char *%s[] = {", varName))
    for _, v in ipairs(vars) do
      output(string.format("%s,", v))
    end
    output("};")

    return string.format("{.strArr=%s}", varName), valueSize
  else
    error("invalid string value")
  end
end

local function getByteStringUaValue(context, value, output)
  if type(value) == "string" then
    local byteStringData = newVariableName(context)

    output(string.format("static const uint8_t %s[] = {", byteStringData))

    local content = ""
    for i = 1, #value do
      local byte = string.byte(value, i)
      content = content..string.format("0x%.2X,", byte)
      if i%16 == 0 then
        output(content)
        content = ""
      end
    end
    output("};")

    local byteStringVarname = newVariableName(context)
    output(string.format("static const struct UA_ByteString %s = {.data=%s, .size=%d};",
      byteStringVarname, byteStringData, #value))

    return string.format("{.bPtr=&%s}", byteStringVarname)

  -- elseif type(value[1]) == 'string' then
  --   local valueSize = #value
  --   local vars = {}
  --   for _, v in ipairs(value) do
  --     local varValueName = saveStringVariable(context, v, output)
  --     table.insert(vars, varValueName)
  --   end
  --   local varName = newVariableName(context)
  --   output(string.format("static const char *%s[] = {", varName))
  --   for _, v in ipairs(vars) do
  --     output(string.format("%s,", v))
  --   end
  --   output("};")

  --   return string.format("{.strArr=%s}", varName), valueSize
  -- else
  --   error("invalid string value")
  end
end


local function getQualifiedNameUaValue(context, value, output)
  assert(type(value.Name) == "string")
  local varValueName = saveStringVariable(context, value.Name, output)
  return string.format("{.str=%s}", varValueName)
end


local function getUInt32UaValue(_, value, _)
  assert(type(value) == "number")
  return string.format("{.u32=%s}", value)
end

local function getInt32UaValue(context, value, output)
  if type(value) == "number" then
    return string.format("{.i32=%s}", value)
  elseif type(value[1]) == 'number' then
    local valueSize = #value
    local varName = newVariableName(context)
    output(string.format("static const int32_t %s[] = {", varName))
    for _, v in ipairs(value) do
      output(string.format("%s,", v))
    end
    output("};")

    return string.format("{.i32Arr=%s}", varName), valueSize
  else
    error("invalid int32 value")
  end

  assert(type(value) == "number")
end

local function getDoubleUaValue(_, value, _)
  assert(type(value) == "number")
  return string.format("{.d=%s}", value)
end

local function getFloatUaValue(_, value, _)
  assert(type(value) == "number")
  return string.format("{.f=%s}", value)
end


local function getBooleanUaValue(_, value, _)
  assert(type(value) == "boolean", type(value))
  return string.format("{.u8=%s}", value == true and 1 or 0)
end

local function getVariantUaValue(context, value, output)
  local v = value
  local valueData
  local valueSize
  local valueType
  if v == nil then
    return nil
  end
  if v.Type == VariantType.Boolean then
    valueType = "UA_Type_Boolean"
    valueData, valueSize = getBooleanUaValue(context, v.Value, output)
  elseif v.Type == VariantType.SByte then
    valueType = "UA_Type_SByte"
    valueData, valueSize = getUInt32UaValue(context, v.Value, output)
  elseif v.Type == VariantType.Byte then
    valueType = "UA_Type_Byte"
    valueData, valueSize = getUInt32UaValue(context, v.Value, output)
  elseif v.Type == VariantType.Int16 then
    valueType = "UA_Type_Int16"
    valueData, valueSize = getInt32UaValue(context, v.Value, output)
  elseif v.Type == VariantType.UInt16 then
    valueType = "UA_Type_UInt16"
    valueData, valueSize = getUInt32UaValue(context, v.Value, output)
  elseif v.Type == VariantType.Int32 then
    valueType = "UA_Type_Int32"
    valueData, valueSize = getInt32UaValue(context, v.Value, output)
  elseif v.Type == VariantType.UInt32 then
    valueType = "UA_Type_UInt32"
    valueData, valueSize = getUInt32UaValue(context, v.Value, output)
  elseif v.Type == VariantType.Float then
    valueType = "UA_Type_Float"
    valueData, valueSize = getFloatUaValue(context, v.Value, output)
  elseif v.Type == VariantType.Double then
    valueType = "UA_Type_Double"
    valueData, valueSize = getDoubleUaValue(context, v.Value, output)
  elseif v.Type == VariantType.String then
    valueType = "UA_Type_String"
    valueData, valueSize = getStringUaValue(context, v.Value, output)
  elseif v.Type == VariantType.ByteString then
    valueType = "UA_Type_ByteString"
    valueData, valueSize = getByteStringUaValue(context, v.Value, output)
  elseif v.Type == VariantType.DateTime then
    valueType = "UA_Type_DateTime"
    valueData, valueSize = getDoubleUaValue(context, v.Value, output)
  elseif v.Type == VariantType.LocalizedText then
    valueType = "UA_Type_LocalizedText"
    valueData, valueSize = getLocalizedTextUaValue(context, v.Value, output)
  elseif v.Type == VariantType.ExtensionObject then
    return nil
  else
    for k, _ in pairs(v) do
      error("invalid variant value: " .. k)
    end

    return nil
  end

  local variantVarName = newVariableName(context).."_variant"
  output(string.format("static const struct UA_Variant %s = {.dataType=%s, .size=%d, .data=%s};", variantVarName, valueType, valueSize or 0, valueData))
  return string.format("{.vPtr=&%s}", variantVarName)
end

local function getDefinitionValue(context, definition, output)
  local definitionVarName = "NULL"
  local fieldsCode = {}
  if definition then
    for _, field in ipairs(definition) do
      local fieldName = saveStringVariable(context, field.Name, output)
      local dataType = field.DataType and saveStringVariable(context, field.DataType, output) or "NULL"
      local rank = field.ValueRank or -1 -- -1 = scalar
      local enumValue = field.Value or -1 -- enum value, for structure fields this is -1
      table.insert(fieldsCode, string.format("{.name=%s, .typeId=%s, .valueRank=%d, .enumValue=%d},", fieldName, dataType, rank, enumValue))
    end

    definitionVarName = newVariableName(context) .. "_definition"
    local fieldsVarName = definitionVarName .. "_fields"
    output(string.format("static const struct UA_Field %s[] = {", fieldsVarName))
    for _, fieldCode in ipairs(fieldsCode) do
      output(fieldCode)
    end
    output("};")

    output(string.format("static const struct UA_StructDefinition %s = {.size=%s, .fields=%s};", definitionVarName, #definition, fieldsVarName))
  end

  return string.format("{.definitionPtr=&%s}", definitionVarName)
end

local function getAttrValue(context, attrs, attrName, value, func, output)
  if value == nil then
    return
  end

  local uaValue = func(context, value, output)
  if uaValue == nil then
    return
  end
  local attrValue = string.format("{.id=%s, .data=%s},", attrName, uaValue)
  table.insert(attrs, attrValue)
end

local function saveNodes(self, context, output)
  local i = 0

  local nodes = {}

  for nodeId, node in pairs(self.Nodes) do
    local varNameBase = saveStringVariable(context, nodeId, output)

    local attrVars = {}

    getAttrValue(context, attrVars, "UA_AttributeId_NodeId",             node.Attrs[1], getStringUaValue,   output)
    getAttrValue(context, attrVars, "UA_AttributeId_NodeClass",          node.Attrs[2], getUInt32UaValue,   output)
    getAttrValue(context, attrVars, "UA_AttributeId_BrowseName",         node.Attrs[3], getQualifiedNameUaValue, output)
    getAttrValue(context, attrVars, "UA_AttributeId_DisplayName",        node.Attrs[4], getLocalizedTextUaValue, output)
    getAttrValue(context, attrVars, "UA_AttributeId_Description",        node.Attrs[5], getLocalizedTextUaValue, output)
    getAttrValue(context, attrVars, "UA_AttributeId_WriteMask",          node.Attrs[6], getUInt32UaValue,   output)
    getAttrValue(context, attrVars, "UA_AttributeId_UserWriteMask",      node.Attrs[7], getUInt32UaValue,   output)
    getAttrValue(context, attrVars, "UA_AttributeId_IsAbstract",         node.Attrs[8], getBooleanUaValue,  output)
    getAttrValue(context, attrVars, "UA_AttributeId_Symmetric",          node.Attrs[9], getBooleanUaValue,  output)
    getAttrValue(context, attrVars, "UA_AttributeId_InverseName",        node.Attrs[10], getLocalizedTextUaValue,output)
    getAttrValue(context, attrVars, "UA_AttributeId_ContainsNoLoops",    node.Attrs[11], getBooleanUaValue, output)
    getAttrValue(context, attrVars, "UA_AttributeId_EventNotifier",      node.Attrs[12], getUInt32UaValue,  output)
    getAttrValue(context, attrVars, "UA_AttributeId_Value",              node.Attrs[13], getVariantUaValue, output)
    getAttrValue(context, attrVars, "UA_AttributeId_DataType",           node.Attrs[14], getStringUaValue,  output)
    getAttrValue(context, attrVars, "UA_AttributeId_ValueRank",          node.Attrs[15], getUInt32UaValue,  output)
    -- UA_AttributeId_ArrayDimensions = 16,         /* UA_Type_Uint32(array), value.bPtr */
    getAttrValue(context, attrVars, "UA_AttributeId_AccessLevel",             node.Attrs[17], getUInt32UaValue,  output)
    getAttrValue(context, attrVars, "UA_AttributeId_UserAccessLevel",         node.Attrs[18], getUInt32UaValue,  output)
    getAttrValue(context, attrVars, "UA_AttributeId_MinimumSamplingInterval", node.Attrs[19], getDoubleUaValue,  output)
    getAttrValue(context, attrVars, "UA_AttributeId_Historizing",             node.Attrs[20], getBooleanUaValue, output)
    getAttrValue(context, attrVars, "UA_AttributeId_Executable",              node.Attrs[21], getBooleanUaValue, output)
    getAttrValue(context, attrVars, "UA_AttributeId_UserExecutable",          node.Attrs[22], getBooleanUaValue, output)
    getAttrValue(context, attrVars, "UA_AttributeId_DataTypeDefinition",      node.Attrs[23], getDefinitionValue,  output)

    -- UA_AttributeId_RolePermissions = 24,
    -- UA_AttributeId_UserRolePermissions = 25,
    -- UA_AttributeId_AccessRestrictions = 26,
    -- UA_AttributeId_AccessLevelEx = 27

    local attributesVarName = varNameBase .. "_attrs"
    output(string.format("static const struct UA_Attribute %s[] = {", attributesVarName))
      for _, attr in ipairs(attrVars) do
        output(attr)
      end
    output("};")

    local refsVarName = "NULL"
    if node.Refs[1] then
      refsVarName = varNameBase .. "_refs"
      local refsCode = {}
      for _, ref in ipairs(node.Refs) do
        local targetNodeId = saveStringVariable(context, ref.target, output)
        local refId = saveStringVariable(context, ref.type, output)
        local isForward = ref.isForward and 1 or 0
        table.insert(refsCode, string.format("{.nodeid=%s, .refid=%s, .isForward=%d},", targetNodeId, refId, isForward))
      end

      output(string.format("static const struct UA_Reference %s[] = {", refsVarName))
      for _, refCode in ipairs(refsCode) do
        output(refCode)
      end
      output("};")
    end

    table.insert(nodes, {
      nodeId = nodeId,
      attrsSize = #attrVars,
      attrs = attributesVarName,

      refsSize = #node.Refs,
      refs = refsVarName,

      binaryId = node.BinaryId,
      jsonId = node.JsonId,
      baseId = node.BaseId,
      dataTypeId = node.DataTypeId,
    })
  end

  table.sort(nodes, function(a, b) return a.nodeId < b.nodeId end)

  output("static const struct UA_Node nodes[] = {")
  for _, node in ipairs(nodes) do
    local binaryId = "NULL"
    local jsonId = "NULL"
    local baseId = "NULL"
    local dataTypeId = "NULL"
    if node.binaryId then
      binaryId = saveStringVariable(context, node.binaryId, output)
    end
    if node.jsonId then
      jsonId = saveStringVariable(context, node.jsonId, output)
    end
    if node.baseId then
      baseId = saveStringVariable(context, node.baseId, output)
    end
    if node.dataTypeId then
      dataTypeId = saveStringVariable(context, node.dataTypeId, output)
    end

    output(string.format("{.attrsSize=%d, .refsSize=%d, .attrs=%s, .refs=%s, .binaryId=%s, .jsonId=%s, .baseId=%s, .dataTypeId=%s},",
      node.attrsSize, node.refsSize, node.attrs, node.refs, binaryId, jsonId, baseId, dataTypeId))
    i = i + 1
  end
  output("};")

  output("const struct UA_Nodeset nodeset = {")
  output("  .nodes = nodes,")
  output(string.format("  .size = %d,", #nodes))
  output("};")
end

local function export(self, output)
  local context = {
    -- map string -> varNam
    stringVars = {
      count = 0, -- number of string variables
    },

    varCount = 0
  }

  output('#include <stddef.h>')
  output('#ifndef OPCUA_TYPES_H')
  output('#include "opcua_types.h"')
  output('#endif')
  saveNodeIds(self, context, output)
  saveNodes(self, context, output)
end

return export
