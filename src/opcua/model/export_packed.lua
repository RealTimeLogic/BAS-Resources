local const = require("opcua.const")
local exportUtils = require("opcua.model.export_utils")
local NodeId = require("opcua.node_id")
local typeInfoResolver = require("opcua.model.type_info")

local AttributeId = const.AttributeId
local HAS_ENCODING = "i=38"

local MAGIC = "UAPB"
local VERSION = 1
local HEADER_SIZE = 80
local HEADER_FORMAT =
  "<c4I2I2I4I4I4I4I4I4I4I4I4I4I4I4I4I4I4I4I1I1I1I1I1I1I2"
local MAX_DEPTH = 64
local NODE_HAS_FIELDS = 0x80
local NODE_ATTRIBUTE_COUNT = 0x7F

assert(string.packsize(HEADER_FORMAT) == HEADER_SIZE)

local VALUE_FALSE = 1
local VALUE_TRUE = 2
local VALUE_INTEGER = 3
local VALUE_NUMBER = 4
local VALUE_STRING = 5
local VALUE_TABLE = 6

local function selectSize(maxValueCount)
  if maxValueCount <= 0x100 then
    return 1
  elseif maxValueCount <= 0x10000 then
    return 2
  end
  return 4
end

local function selectIntegerWidth(maxValue)
  if maxValue <= 0xFF then
    return 1
  elseif maxValue <= 0xFFFF then
    return 2
  end
  return 4
end

local function packSized(value, width)
  if width == 1 then
    return string.pack("<I1", value)
  elseif width == 2 then
    return string.pack("<I2", value)
  end
  return string.pack("<I4", value)
end

local function copyWithDefault(value, key, default)
  if (type(value) ~= "table" and type(value) ~= "userdata") or
     value[key] ~= nil then
    return value
  end

  local copy = {}
  for field, fieldValue in pairs(value) do
    copy[field] = fieldValue
  end
  copy[key] = default
  return copy
end

local function normalizeAttributeValue(attributeId, value)
  if attributeId == AttributeId.BrowseName then
    -- NamespaceIndex 0 is the OPC UA default. The XML loader may omit it,
    -- while address-space consumers expect the complete QualifiedName.
    return copyWithDefault(value, "ns", 0)
  elseif attributeId == AttributeId.Value then
    -- A missing DataValue StatusCode means Good. Store the explicit value so
    -- all readonly providers expose the same raw attribute representation.
    value = copyWithDefault(value, "StatusCode", 0)
    if (type(value) == "table" or type(value) == "userdata") and
       value.Type ~= nil then
      -- IsArray=false is the complete scalar Variant representation used by
      -- the binary decoder and by the previous native NS0 interface.
      value = copyWithDefault(value, "IsArray", false)
    end
    return value
  end
  return value
end

local function sortedKeys(value)
  local keys = {}
  for key in pairs(value) do
    local keyType = type(key)
    if keyType ~= "number" and keyType ~= "string" and
       keyType ~= "boolean" then
      error("unsupported packed table key type: " .. keyType)
    end
    keys[#keys + 1] = key
  end

  table.sort(keys, function(a, b)
    local typeA = type(a)
    local typeB = type(b)
    if typeA ~= typeB then
      return typeA < typeB
    end
    if typeA == "boolean" then
      return a == false and b == true
    end
    return a < b
  end)
  return keys
end

local function collectValueStrings(value, strings, depth)
  if depth > MAX_DEPTH then
    error("packed value nesting exceeds " .. MAX_DEPTH)
  end

  local valueType = type(value)
  if valueType == "string" then
    strings[value] = true
  elseif valueType == "table" or valueType == "userdata" then
    for _, key in ipairs(sortedKeys(value)) do
      collectValueStrings(key, strings, depth + 1)
      collectValueStrings(value[key], strings, depth + 1)
    end
  elseif valueType ~= "number" and valueType ~= "boolean" then
    error("unsupported packed value type: " .. valueType)
  end
end

local TYPE_INFO_FIELDS = {
  BaseId = true,
  BinaryId = true,
  DataTypeId = true,
  JsonId = true,
}

local function collectNodeFields(nodeId, node, typeInfo)
  local fields = {}

  if type(node) == "table" then
    for key, value in pairs(node) do
      if type(key) == "string" and key ~= "Attrs" and key ~= "Refs" and
         key:sub(1, 1) ~= "_" and not TYPE_INFO_FIELDS[key] and
         type(value) ~= "function" then
        fields[#fields + 1] = {Key = key, Value = value}
      end
    end
  end

  if typeInfo ~= nil then
    assert(typeInfo.DataTypeId ~= nil, "TypeInfo.DataTypeId is required")
    fields[#fields + 1] = {
      Key = "DataTypeId",
      Value = typeInfo.DataTypeId,
    }
    if nodeId == typeInfo.DataTypeId then
      for _, key in ipairs({
        "BaseId", "BinaryId", "JsonId",
      }) do
        local value = typeInfo[key]
        if value ~= nil then
          fields[#fields + 1] = {Key = key, Value = value}
        end
      end
    end
  end

  table.sort(fields, function(a, b)
    return a.Key < b.Key
  end)
  return fields
end

local function getTypeInfo(nodes, nodeId)
  if type(nodes.getTypeInfo) == "function" then
    return nodes:getTypeInfo(nodeId)
  end
  return typeInfoResolver.resolve(nodes, nodeId)
end

local function findXmlEncodingNodeIds(nodes)
  local candidates = {}
  local result = {}

  for nodeId, node in pairs(nodes) do
    if type(nodeId) == "string" then
      local browseName = node and node.Attrs[AttributeId.BrowseName]
      if browseName ~= nil and browseName.Name == "Default XML" then
        candidates[nodeId] = true
      end
    end
  end

  for nodeId, node in pairs(nodes) do
    if type(nodeId) == "string" then
      for _, ref in ipairs(node.Refs or {}) do
        if ref.type == HAS_ENCODING then
          if ref.isForward == false and candidates[nodeId] then
            result[nodeId] = true
          elseif ref.isForward == true and candidates[ref.target] then
            result[ref.target] = true
          end
        end
      end
    end
  end
  return result
end

local function normalizeNodes(model, namespaceURIs)
  local nodes = model.Nodes
  local namespaceIndexes =
    exportUtils.namespaceIndexes(model, namespaceURIs)
  local selectedNodeIds = {}
  local xmlEncodingNodeIds = findXmlEncodingNodeIds(nodes)
  for nodeId in pairs(nodes) do
    if type(nodeId) == "string" then
      if not xmlEncodingNodeIds[nodeId] then
        local id = NodeId.fromString(nodeId)
        if namespaceIndexes[id.ns] then
          selectedNodeIds[nodeId] = true
        end
      end
    end
  end

  local result = {}
  for nodeId, node in pairs(nodes) do
    if selectedNodeIds[nodeId] and node ~= nil then
      local attrs = {}
      for attributeId, value in pairs(node.Attrs) do
        if type(attributeId) == "number" then
          attrs[#attrs + 1] = {
            AttributeId = attributeId,
            Value = normalizeAttributeValue(attributeId, value),
          }
        end
      end
      table.sort(attrs, function(a, b)
        return a.AttributeId < b.AttributeId
      end)

      local refs = {}
      for _, ref in ipairs(node.Refs or {}) do
        if not xmlEncodingNodeIds[ref.target] then
          refs[#refs + 1] = {
            Type = assert(ref.type, "reference type is required"),
            Target = assert(ref.target, "reference target is required"),
            IsForward = ref.isForward == true,
            -- A dangling inverse reference attaches this model node to a
            -- parent supplied by an already loaded model. Forward references
            -- may point outside a reduced model but do not create parent
            -- contributions.
            IsExternal =
              not selectedNodeIds[ref.target] and ref.isForward ~= true,
          }
        end
      end
      table.sort(refs, function(a, b)
        if a.Type ~= b.Type then
          return a.Type < b.Type
        end
        if a.Target ~= b.Target then
          return a.Target < b.Target
        end
        return a.IsForward == false and b.IsForward == true
      end)
      result[#result + 1] = {
        NodeId = nodeId,
        Attrs = attrs,
        Refs = refs,
        Fields = collectNodeFields(
          nodeId, node, getTypeInfo(nodes, nodeId)),
      }
    end
  end

  table.sort(result, function(a, b)
    return a.NodeId < b.NodeId
  end)
  return result
end

local function createStringPool(nodes)
  local strings = {}
  local nodeIds = {}
  for _, node in ipairs(nodes) do
    strings[node.NodeId] = true
    nodeIds[node.NodeId] = true
    for _, attribute in ipairs(node.Attrs) do
      collectValueStrings(attribute.Value, strings, 0)
    end
    for _, ref in ipairs(node.Refs) do
      strings[ref.Type] = true
      strings[ref.Target] = true
    end
    for _, field in ipairs(node.Fields) do
      strings[field.Key] = true
      collectValueStrings(field.Value, strings, 0)
    end
  end

  local orderedNodeIds = {}
  local orderedStrings = {}
  for value in pairs(strings) do
    if nodeIds[value] then
      orderedNodeIds[#orderedNodeIds + 1] = value
    else
      orderedStrings[#orderedStrings + 1] = value
    end
  end
  table.sort(orderedNodeIds)
  table.sort(orderedStrings)

  local maxLength = 0
  for _, value in ipairs(orderedNodeIds) do
    maxLength = math.max(maxLength, #value)
  end
  for _, value in ipairs(orderedStrings) do
    maxLength = math.max(maxLength, #value)
  end
  local stringLengthWidth = selectIntegerWidth(maxLength)
  local offsets = {}
  local chunks = {}
  local offset = 0
  local function append(value)
    offsets[value] = offset
    local chunk = packSized(#value, stringLengthWidth) .. value
    chunks[#chunks + 1] = chunk
    offset = offset + #chunk
  end
  for _, value in ipairs(orderedNodeIds) do
    append(value)
  end
  local nodeIdStringSize = offset
  for _, value in ipairs(orderedStrings) do
    append(value)
  end
  return offsets, table.concat(chunks), stringLengthWidth,
    nodeIdStringSize
end

local function encodeValue(
  value, stringOffsets, stringOffsetWidth, depth)
  if depth > MAX_DEPTH then
    error("packed value nesting exceeds " .. MAX_DEPTH)
  end

  local valueType = type(value)
  if valueType == "boolean" then
    return string.char(value and VALUE_TRUE or VALUE_FALSE)
  elseif valueType == "number" then
    if math.type and math.type(value) == "integer" then
      return string.char(VALUE_INTEGER) .. string.pack("<i8", value)
    end
    return string.char(VALUE_NUMBER) .. string.pack("<d", value)
  elseif valueType == "string" then
    return string.char(VALUE_STRING) ..
      packSized(assert(stringOffsets[value]), stringOffsetWidth)
  elseif valueType == "table" or valueType == "userdata" then
    local keys = sortedKeys(value)
    local chunks = {
      string.char(VALUE_TABLE),
      string.pack("<I4", #keys),
    }
    for _, key in ipairs(keys) do
      chunks[#chunks + 1] = encodeValue(
        key, stringOffsets, stringOffsetWidth, depth + 1)
      chunks[#chunks + 1] =
        encodeValue(
          value[key], stringOffsets, stringOffsetWidth, depth + 1)
    end
    return table.concat(chunks)
  end

  error("unsupported packed value type: " .. valueType)
end

local function updateCrc32(crc, data)
  for i = 1, #data do
    crc = crc ~ data:byte(i)
    for _ = 1, 8 do
      local mask = -(crc & 1)
      crc = (crc >> 1) ~ (0xEDB88320 & mask)
    end
  end
  return crc
end

local function exportPacked(self, output, namespaceURIs)
  assert(type(output) == "function", "output must be a function")

  local nodes = normalizeNodes(self, namespaceURIs)
  local stringOffsets, stringPool, stringLengthWidth, nodeIdStringSize =
    createStringPool(nodes)
  local nodeIdOffsetWidth = selectSize(nodeIdStringSize)
  local stringOffsetWidth = selectSize(#stringPool)

  local attributeCount = 0
  local referenceCount = 0
  local fieldCount = 0
  for _, node in ipairs(nodes) do
    attributeCount = attributeCount + #node.Attrs
    referenceCount = referenceCount + #node.Refs
    fieldCount = fieldCount + #node.Fields
  end

  local externalReferenceCount = 0
  for _, node in ipairs(nodes) do
    for _, ref in ipairs(node.Refs) do
      if ref.IsExternal then
        externalReferenceCount = externalReferenceCount + 1
      end
    end
  end

  local indexWidth = selectSize(#nodes)
  local externalReferenceRecordSize = indexWidth + 2

  local values = {}
  local valueSize = 0
  local function appendValue(value)
    local encoded = encodeValue(
      value, stringOffsets, stringOffsetWidth, 0)
    local offset = valueSize
    values[#values + 1] = encoded
    valueSize = valueSize + #encoded
    return offset
  end

  for _, node in ipairs(nodes) do
    for _, attribute in ipairs(node.Attrs) do
      if attribute.AttributeId > 0xFF then
        error("packed AttributeId is out of range: " ..
          attribute.AttributeId)
      end
      attribute.ValueStart = appendValue(attribute.Value)
    end
    for _, field in ipairs(node.Fields) do
      field.ValueStart = appendValue(field.Value)
    end
  end

  local valueOffsetWidth = selectSize(valueSize)

  local nodeBodies = {}
  local nodeBodyOffsets = {}
  local externalReferences = {}
  local nodeBodySize = 0
  for nodeIndex, node in ipairs(nodes) do
    if #node.Attrs > NODE_ATTRIBUTE_COUNT then
      error("packed node contains too many attributes: " .. node.NodeId)
    end
    if #node.Fields > 0xFF then
      error("packed node contains too many fields: " .. node.NodeId)
    end
    if #node.Refs > 0xFFFF then
      error("packed node contains too many references: " .. node.NodeId)
    end

    local hasFields = #node.Fields > 0
    local flagsAndAttributeCount = #node.Attrs
    if hasFields then
      flagsAndAttributeCount = flagsAndAttributeCount | NODE_HAS_FIELDS
    end
    local body = {
      string.char(flagsAndAttributeCount),
    }
    if hasFields then
      body[#body + 1] = string.char(#node.Fields)
    end
    body[#body + 1] = string.pack("<I2", #node.Refs)

    for _, attribute in ipairs(node.Attrs) do
      body[#body + 1] =
        string.char(attribute.AttributeId) ..
        packSized(attribute.ValueStart, valueOffsetWidth)
    end
    for referenceIndex, ref in ipairs(node.Refs) do
      body[#body + 1] =
        packSized(assert(stringOffsets[ref.Type]), stringOffsetWidth) ..
        packSized(assert(stringOffsets[ref.Target]), stringOffsetWidth) ..
        string.char(ref.IsForward and 1 or 0)
      if ref.IsExternal then
        externalReferences[#externalReferences + 1] = {
          NodeIndex = nodeIndex - 1,
          ReferenceIndex = referenceIndex - 1,
        }
      end
    end
    for _, field in ipairs(node.Fields) do
      body[#body + 1] =
        packSized(assert(stringOffsets[field.Key]), stringOffsetWidth) ..
        packSized(field.ValueStart, valueOffsetWidth)
    end

    body = table.concat(body)
    nodeBodyOffsets[#nodeBodyOffsets + 1] = nodeBodySize
    nodeBodies[#nodeBodies + 1] = body
    nodeBodySize = nodeBodySize + #body
  end
  assert(#externalReferences == externalReferenceCount)

  local nodeBodyOffsetWidth = selectSize(nodeBodySize)
  local nodeIdIndexOffset = HEADER_SIZE
  local nodeBodyIndexOffset =
    nodeIdIndexOffset + #nodes * nodeIdOffsetWidth
  local nodeBodyOffset =
    nodeBodyIndexOffset + #nodes * nodeBodyOffsetWidth
  local externalReferenceOffset = nodeBodyOffset + nodeBodySize
  local valueOffset = externalReferenceOffset +
    externalReferenceCount * externalReferenceRecordSize
  local stringOffset = valueOffset + valueSize
  local totalSize = stringOffset + #stringPool

  local nodeIdOffsets = {}
  local packedNodeBodyOffsets = {}
  local externalReferenceRecords = {}
  for nodeIndex, node in ipairs(nodes) do
    nodeIdOffsets[nodeIndex] =
      packSized(assert(stringOffsets[node.NodeId]), nodeIdOffsetWidth)
    packedNodeBodyOffsets[nodeIndex] =
      packSized(nodeBodyOffsets[nodeIndex], nodeBodyOffsetWidth)
  end
  for index, external in ipairs(externalReferences) do
    externalReferenceRecords[index] =
      packSized(external.NodeIndex, indexWidth) ..
      string.pack("<I2", external.ReferenceIndex)
  end

  local function header(checksum)
    return string.pack(
      HEADER_FORMAT,
      MAGIC,
      VERSION,
      HEADER_SIZE,
      totalSize,
      checksum,
      #nodes,
      nodeIdIndexOffset,
      nodeBodyIndexOffset,
      nodeBodyOffset,
      nodeBodySize,
      attributeCount,
      referenceCount,
      externalReferenceCount,
      externalReferenceOffset,
      fieldCount,
      valueOffset,
      valueSize,
      stringOffset,
      #stringPool,
      indexWidth,
      nodeIdOffsetWidth,
      nodeBodyOffsetWidth,
      stringOffsetWidth,
      valueOffsetWidth,
      stringLengthWidth,
      0)
  end

  local sections = {
    nodeIdOffsets,
    packedNodeBodyOffsets,
    nodeBodies,
    externalReferenceRecords,
    values,
    {stringPool},
  }

  -- The CRC field is zero while calculating the checksum. The C reader uses
  -- the same rule, so mounting never requires a temporary copy of the blob.
  local crc = updateCrc32(0xFFFFFFFF, header(0))
  local generatedSize = HEADER_SIZE
  for _, section in ipairs(sections) do
    for _, chunk in ipairs(section) do
      crc = updateCrc32(crc, chunk)
      generatedSize = generatedSize + #chunk
    end
  end
  assert(generatedSize == totalSize)

  output(header((~crc) & 0xFFFFFFFF))
  for _, section in ipairs(sections) do
    for _, chunk in ipairs(section) do
      if #chunk > 0 then
        output(chunk)
      end
    end
  end
end

return exportPacked
