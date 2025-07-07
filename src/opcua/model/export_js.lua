local ua = require("opcua.api")

local function newVariableName(context)
  local count = context.varCount
  count = count + 1
  context.varCount = count
  return "variable_"..count
end

local function getNodeIdUaValue(_, value, _)
  if type(value) == "string" then
    return string.format('new t.Variant(new t.NodeId("%s"))', value)
  elseif type(value[1]) == 'string' then
    local arrValue = "["
    for _, v in ipairs(value) do
      arrValue = arrValue .. string.format('new t.Variant(new t.NodeId("%s")),', v)
    end
    arrValue = arrValue .. "]"

    return arrValue
  else
    error("invalid string value")
  end
end


local function getStringUaValue(_, value, _)
  if type(value) == "string" then
    return string.format('new t.Variant("%s", t.VariantType.String)', value)
  elseif type(value[1]) == 'string' then
    local arrValue = "new t.Variant(["
    for _, v in ipairs(value) do
      arrValue = arrValue .. string.format('"%s",', v)
    end
    arrValue = arrValue .. "], t.VariantType.String)"

    return arrValue
  else
    error("invalid string value")
  end
end

local function getLocalizedTextUaValue(_, value, _)
  if type(value.Text) == "string" then
    return string.format('new t.Variant(new t.LocalizedText("%s"))', value.Text)
  elseif type(value) == 'table' and type(value[1].Text) == "string" then
    local data = "new t.Variant(["
    for _, v in ipairs(value) do
      data = data.. string.format('new t.LocalizedText("%s"),', v.Text)
    end
    data = data .. "])"
    return data
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


local function getQualifiedNameUaValue(_, value, _)
  assert(type(value.Name) == "string")
  return string.format('new t.Variant(new t.QualifiedName(%s, "%s"))', value.ns or 0, value.Name or "")
end


local function getUInt32UaValue(_, value, _)
  assert(type(value) == "number")
  return string.format("new t.Variant(%s, t.VariantType.UInt32)", value)
end

local function getInt32UaValue(_, value, _)
  if type(value) == "number" then
    return string.format('new t.Variant(%s, t.VariantType.Int32)', value)
  elseif type(value[1]) == 'number' then
    local data = "new t.Variant(["
    for _, v in ipairs(value) do
      data = data .. string.format('%s,', v)
    end
    data = data .. "])"
    return data
  else
    error("invalid int32 value")
  end

  assert(type(value) == "number")
end

local function getDoubleUaValue(_, value, _)
  return string.format('new t.Variant(%s, t.VariantType.Double)', value)
end

local function getFloatUaValue(_, value, _)
  return string.format('new t.Variant(%s, t.VariantType.Float)', value)
end


local function getBooleanUaValue(_, value, _)
  return string.format("new t.Variant(%s, t.VariantType.Boolean)", value == true)
end

local function getVariantUaValue(context, value, output)
  local v = value.Value
  local valueData
  if v.Boolean ~= nil then
    -- valueType = "UA_Type_Boolean"
    valueData = getBooleanUaValue(context, v.Boolean, output)
  elseif v.SByte then
    -- valueType = "UA_Type_SByte"
    valueData = getUInt32UaValue(context, v.SByte, output)
  elseif v.Byte then
    -- valueType = "UA_Type_Byte"
    valueData = getUInt32UaValue(context, v.Byte, output)
  elseif v.Int16 then
    -- valueType = "UA_Type_Int16"
    valueData = getInt32UaValue(context, v.Int16, output)
  elseif v.UInt16 then
    -- valueType = "UA_Type_UInt16"
    valueData = getUInt32UaValue(context, v.UInt16, output)
  elseif v.Int32 then
    -- valueType = "UA_Type_Int32"
    valueData = getInt32UaValue(context, v.Int32, output)
  elseif v.UInt32 then
    -- valueType = "UA_Type_UInt32"
    valueData = getUInt32UaValue(context, v.UInt32, output)
  elseif v.Float then
    -- valueType = "UA_Type_Float"
    valueData = getFloatUaValue(context, v.Float, output)
  elseif v.Double then
    -- valueType = "UA_Type_Double"
    valueData = getDoubleUaValue(context, v.Double, output)
  elseif v.String then
    -- valueType = "UA_Type_String"
    valueData = getStringUaValue(context, v.String, output)
  elseif v.ByteString then
    -- valueType = "UA_Type_ByteString"
    valueData = getByteStringUaValue(context, v.ByteString, output)
  elseif v.DateTime then
    -- valueType = "UA_Type_DateTime"
    valueData = getDoubleUaValue(context, v.DateTime, output)
  elseif v.LocalizedText then
    -- valueType = "UA_Type_LocalizedText"
    valueData = getLocalizedTextUaValue(context, v.LocalizedText, output)
  else
    for k, _ in pairs(v) do
      error("invalid variant value: " .. k)
    end

    return "new t.Variant()"
  end

  return valueData
end

local function getAttrValue(context, attrIdx, value, func, output)
  if value == nil then
    return
  end

  local uaValue = func(context, value, output)
  output(string.format("      new ns.Attribute(%s, %s),", attrIdx, uaValue))
end

local function saveAttributes(context, node, output)
  getAttrValue(context, ua.AttributeId.NodeId,            node.attrs[1], getNodeIdUaValue,   output)
  getAttrValue(context, ua.AttributeId.NodeClass,         node.attrs[2], getUInt32UaValue,   output)
  getAttrValue(context, ua.AttributeId.BrowseName,        node.attrs[3], getQualifiedNameUaValue, output)
  getAttrValue(context, ua.AttributeId.DisplayName,       node.attrs[4], getLocalizedTextUaValue, output)
  getAttrValue(context, ua.AttributeId.Description,       node.attrs[5], getLocalizedTextUaValue, output)
  getAttrValue(context, ua.AttributeId.WriteMask,         node.attrs[6], getUInt32UaValue,   output)
  getAttrValue(context, ua.AttributeId.UserWriteMask,     node.attrs[7], getUInt32UaValue,   output)
  getAttrValue(context, ua.AttributeId.IsAbstract,        node.attrs[8], getBooleanUaValue,  output)
  getAttrValue(context, ua.AttributeId.Symmetric,         node.attrs[9], getBooleanUaValue,  output)
  getAttrValue(context, ua.AttributeId.InverseName,       node.attrs[10], getLocalizedTextUaValue,output)
  getAttrValue(context, ua.AttributeId.ContainsNoLoops,   node.attrs[11], getBooleanUaValue, output)
  getAttrValue(context, ua.AttributeId.EventNotifier,     node.attrs[12], getUInt32UaValue,  output)
  getAttrValue(context, ua.AttributeId.Value,             node.attrs[13], getVariantUaValue, output)
  getAttrValue(context, ua.AttributeId.DataType,          node.attrs[14], getNodeIdUaValue,  output)
  getAttrValue(context, ua.AttributeId.Rank,              node.attrs[15], getUInt32UaValue,  output)
  -- UA_AttributeId_ArrayDimensions = 16,         /* UA_Type_Uint32(array), value.bPtr */
  getAttrValue(context, ua.AttributeId.AccessLevel,       node.attrs[17], getUInt32UaValue,  output)
  getAttrValue(context, ua.AttributeId.UserAccessLevel,   node.attrs[18], getUInt32UaValue,  output)
  getAttrValue(context, ua.AttributeId.MinimumSamplingInterval, node.attrs[19], getDoubleUaValue,  output)
  getAttrValue(context, ua.AttributeId.Historizing,       node.attrs[20], getBooleanUaValue, output)
  getAttrValue(context, ua.AttributeId.Executable,        node.attrs[21], getBooleanUaValue, output)
  getAttrValue(context, ua.AttributeId.UserExecutable,    node.attrs[22], getBooleanUaValue, output)
  getAttrValue(context, ua.AttributeId.DataTypeDefinition,node.attrs[23], getNodeIdUaValue,  output)

  -- -- UA_AttributeId_RolePermissions = 24,
  -- -- UA_AttributeId_UserRolePermissions = 25,
  -- -- UA_AttributeId_AccessRestrictions = 26,
  -- -- UA_AttributeId_AccessLevelEx = 27
end

local function saveRefs(_, node, output)
  if node.refs[1] then
    for _, ref in ipairs(node.refs) do
      local targetNodeId = ref.target
      local refId = ref.type
      local isForward = ref.isForward and 'true' or 'false'
      output(string.format('      new ns.Reference("%s", "%s", %s),', targetNodeId, refId, isForward))
    end
  end
end


local function saveDefinition(self, _, node, output)
  for _, field in ipairs(node.definition) do
    if field.Value == nil then
      local baseType = self:getBaseDatatype(field.DataType)
      output(string.format('      new ns.StructField("%s", "%s", "%s", %s, %s),',
            field.Name,
            field.DataType,
            baseType,
            field.ValueRank or -1,
            field.ArrayDimensions and ('"'..field.ArrayDimensions..'"') or "null"))
    else
      output(string.format('      new ns.EnumField("%s", %s),',
            field.Name, field.Value))
    end
  end
end

local function saveNodes(self, context, output)
  -- map <nodeId, BinaryNodeId, JsonNodeId> -> jsNodeVarName
  -- Each node has several IDs in common:
  -- 1. NodeId: common node ID
  -- 2. BinaryNodeId: nodeID that represents the node in binary format
  -- 3. JsonNodeId: nodeID that represents the node in JSON format
  -- All these IDs are used in Extension Objects to understand encoding format
  local jsNodes = {}

  local idx = 0

  -- A sorted table of nodeIds to ensure that the output is the same
  -- after each generation
  local nodeIds = {} -- array of nodeIDs
  for nodeId, _ in pairs(self.Nodes) do
    table.insert(nodeIds, nodeId)
  end
  table.sort(nodeIds)

  for _, nodeId in ipairs(nodeIds) do
    local node = self.Nodes[nodeId]
    idx = idx + 1

    if node.attrs[ua.AttributeId.NodeClass] ~= ua.NodeClass.DataType then
      goto continue
    end

    if node.attrs[1] == nil then
      goto continue
    end

    local nodeVarName = "node"..idx
    table.insert(jsNodes, {nodeId, nodeVarName})
    if node.binaryId then
      table.insert(jsNodes, {node.binaryId, nodeVarName})
    end
    if node.jsonId then
      table.insert(jsNodes, {node.jsonId, nodeVarName})
    end

    output(string.format('const %s = {', nodeVarName))

    output(string.format('    Attributes: ['))
    saveAttributes(context, node, output)
    output('    ],')

    output('    References: [')
    saveRefs(context, node, output)
    output('    ],')

    if node.definition then
      output('    Definition: [')
      saveDefinition(self, context, node, output)
      output('    ],')

      if node.binaryId then
        output(string.format('    BinaryId: "%s",', node.binaryId))
      end

      if node.jsonId then
        output(string.format('    JsonId: "%s",', node.jsonId))
      end
    end

    output('}')
    output('')

    ::continue::
  end

  output('const ns0: ns.NodeSet = {')
  table.sort(jsNodes, function(a, b) return a[1] < b[1] end)
  for _,jsnode in ipairs(jsNodes) do
    output(string.format('    "%s": %s,', jsnode[1], jsnode[2]))
  end
  output('}')
end

local function export(self, output)
  local context = {
    -- map string -> varNam
    stringVars = {
      count = 0, -- number of string variables
    },

    varCount = 0
  }

  output('import * as t from "./types"')
  output('import * as ns from "./nodeset"')

  saveNodes(self, context, output)

  output('export default ns0')
end

return export
