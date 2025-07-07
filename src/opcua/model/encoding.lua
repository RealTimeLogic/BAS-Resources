local tins = table.insert
local fmt = string.format

local dbg = false


local Encoder <const> = {
  bit = function(s, v, n) s.Serializer:bit(v, n) end,
  boolean = function(s, v)  s.Serializer:boolean(v) end,
  int8 = function(s, v) s.Serializer:int8(v) end,
  uint8 = function(s, v) s.Serializer:uint8(v) end,
  byte = function(s, v) s.Serializer:byte(v) end,
  int16 = function(s, v) s.Serializer:int16(v) end,
  uint16 = function(s, v) s.Serializer:uint16(v) end,
  int32 = function(s, v)  s.Serializer:int32(v) end,
  uint32 = function(s, v) s.Serializer:uint32(v) end,
  int64 = function(s, v) s.Serializer:int64(v) end,
  uint64 = function(s, v) s.Serializer:uint64(v) end,
  float = function(s, v) s.Serializer:float(v) end,
  double = function(s, v) s.Serializer:double(v) end,
  dateTime = function(s, v) s.Serializer:dateTime(v) end,
  string = function(s, v) s.Serializer:string(v) end,
  guid = function(s, v) s.Serializer:guid(v) end,
  byteString = function(s, v) s.Serializer:byteString(v) end,
  xmlElement = function(s, v) s.Serializer:xmlElement(v) end,
  nodeId = function(s, v) s.Serializer:nodeId(v) end,
  expandedNodeId = function(s, v) s.Serializer:expandedNodeId(v) end,
  statusCode = function(s, v) s.Serializer:statusCode(v) end,
  qualifiedName = function(s, v) s.Serializer:qualifiedName(v) end,
  localizedText = function(s, v) s.Serializer:localizedText(v) end,
  variant = function(s, v) s.Serializer:variant(v, s) end,
  dataValue = function(s, v) s.Serializer:dataValue(v, s) end,
  diagnosticInfo = function(s, v) s.Serializer:diagnosticInfo(v) end,
  extensionObject = function(s, v) return s.Serializer:extensionObject(v, s) end,
  array = function(s, v) return s.Serializer:array(v, s) end,

  beginField = function(s, name) return s.Serializer:beginField(name) end,
  endField = function(s, name) return s.Serializer:endField(name) end,
  beginObject = function(s) return s.Serializer:beginObject() end,
  endObject = function(s) return s.Serializer:endObject() end,
  beginArray = function(s, size) return s.Serializer:beginArray(size) end,
  endArray = function(s, sz) return s.Serializer:endArray(sz) end,

  hello = function(s, v) return s.Serializer:hello(v) end,
  acknowledge = function(s, v) return s.Serializer:acknowledge(v) end
}

local Decoder <const> = {
  bit = function(s, n) return s.Deserializer:bit(n) end,
  boolean = function(s) return s.Deserializer:boolean() end,
  int8 = function(s) return s.Deserializer:int8() end,
  uint8 = function(s) return s.Deserializer:uint8() end,
  byte = function(s) return s.Deserializer:byte() end,
  int16 = function(s) return s.Deserializer:int16() end,
  uint16 = function(s) return s.Deserializer:uint16() end,
  int32 = function(s)  return s.Deserializer:int32() end,
  uint32 = function(s) return s.Deserializer:uint32() end,
  int64 = function(s) return s.Deserializer:int64() end,
  uint64 = function(s) return s.Deserializer:uint64() end,
  float = function(s) return s.Deserializer:float() end,
  double = function(s) return s.Deserializer:double() end,
  dateTime = function(s) return s.Deserializer:dateTime() end,
  string = function(s) return s.Deserializer:string() end,
  guid = function(s) return s.Deserializer:guid() end,
  byteString = function(s) return s.Deserializer:byteString() end,
  xmlElement = function(s) return s.Deserializer:xmlElement() end,
  nodeId = function(s) return s.Deserializer:nodeId() end,
  expandedNodeId = function(s) return s.Deserializer:expandedNodeId() end,
  statusCode = function(s) return s.Deserializer:statusCode() end,
  qualifiedName = function(s) return s.Deserializer:qualifiedName() end,
  localizedText = function(s) return s.Deserializer:localizedText() end,
  variant = function(s) return s.Deserializer:variant(s) end,
  dataValue = function(s) return s.Deserializer:dataValue(s) end,
  extensionObject = function(s) return s.Deserializer:extensionObject(s) end,
  diagnosticInfo = function(s) return s.Deserializer:diagnosticInfo() end,
  array = function(s, n) return s.Deserializer:array(n) end,

  beginField = function(s, name) return s.Deserializer:beginField(name) end,
  endField = function(s, name) return s.Deserializer:endField(name) end,
  beginObject = function(s) return s.Deserializer:beginObject() end,
  endObject = function(s) return s.Deserializer:endObject() end,
  beginArray = function(s) return s.Deserializer:beginArray() end,
  endArray = function(s) return s.Deserializer:endArray() end,
  stackLast = function(s) return s.Deserializer:stackLast() end,

  hello = function(s) return s.Deserializer:hello() end,
  acknowledge = function(s) return s.Deserializer:acknowledge() end
}

-- NOTE: Decoding enum not to strings but to numbers
-- Search function for decoding base type node
function Encoder:encodeEnum(val, dataTypeId)
  if type(val) == "string" then
    local definition = self.model.Nodes[dataTypeId].definition
    for _, field in ipairs(definition) do
      if field.Name == val then
        val = field.Value
        break
      end
    end
  end
  self:uint32(val)
end

function Encoder:encodeStructure(struct, dataTypeId)
  local definition = self.model.Nodes[dataTypeId].definition
  local enc = self
  if not definition then
    return enc:extensionObject(struct, self.model)
  end

  enc:beginObject()
  for _, field in ipairs(definition) do
    local dataType = field.DataType
    local baseId = self.model.ExtObjects[dataType].baseId
    local encF = self[baseId]
    if not encF then
      error("No encoder for type: " .. dataType)
    end
    enc:beginField(field.Name)

    local val = struct[field.Name]
    if field.ValueRank == 1 then
      if dbg then print("encoding array: "..field.Name) end
      local sz = val == nil and -1 or #val
      enc:beginArray(sz)
      for i=1,sz do
        if dbg then print("encoding array element"..tostring(i)) end
        encF(enc, val[i], dataType)
      end
      enc:endArray(sz)
    else
      if dbg then print("encoding field: " .. field.Name) end
      if type(encF) == "string" then
        error("No encoder for node: " .. field.Name)
      end
      encF(enc, val, dataType)
    end
    enc:endField(field.Name)
  end
  enc:endObject()
end

function Decoder:decodeStructure(dataTypeId)
  local struct = {}
  local dec = self
  dec:beginObject()
  local definition = self.model.Nodes[dataTypeId].definition
  if not definition or #definition == 0 then
    struct = dec:extensionObject(self.model)
  else
    for _, field in ipairs(definition) do
      if dbg then print(fmt("decoding field: %s (%s)", field.Name, field.DataType)) end

      -- if field.Name == "AdditionalHeader" then
      --   require("ldbgmon").connect({client=false})
      -- end

      local dataType = field.DataType
      local baseId = self.model.ExtObjects[dataType].baseId
      local decF = self[baseId]
      if not decF then
        error("No decoder for type: " .. dataType)
      end
      dec:beginField(field.Name)
      local val
      if field.ValueRank == 1 then
        if dbg then print("decoding array") end
        local size = dec:beginArray()
        if size > -1 then
          if dbg then print("array size: " .. size) end
          val = {}
          for i = 1, size do
            if dbg then print("decoding array element: " .. i) end
            tins(val, decF(dec, dataType))
          end
        end
        dec:endArray()
      else
        val = decF(dec, dataType)
      end
      struct[field.Name] = val
      dec:endField(field.Name)
    end
  end

  dec:endObject()

  return struct
end


function Encoder:Encode(nodeId, value)
  local baseId = self.model.ExtObjects[nodeId].baseId
  local enc = self[baseId]
  if not enc then
    error("No encoder for node: " .. nodeId)
  end
  enc(self, value, nodeId)
end

function Encoder:BinaryEncode(nodeId, value)
  local baseId = self.model.ExtObjects[nodeId].baseId
  local enc = Encoder[baseId]
  if not enc then
    error("No Binary encoder for node: " .. nodeId)
  end
  enc(self, self.BinarySerializer, value, nodeId)
end

function Encoder.JsonEncode(self, nodeId, value)
  local extObj = self.model.ExtObjects[nodeId]
  if not extObj then
    error("No node: " .. nodeId)
  end
  local baseId = extObj.baseId
  local enc = Encoder[baseId]
  if not enc then
    error("No JSON encoder for node: " .. nodeId)
  end
  enc(self, self.JsonSerializer, value, nodeId)
end

function Decoder:Decode(nodeId)
  local extObj = self.model.ExtObjects[nodeId]
  if not extObj then
    error("No node: " .. nodeId)
  end
  local dec = self[extObj.baseId]
  if not dec then
    error("No decoder for node: " .. nodeId)
  end
  return dec(self, nodeId)
end

function Decoder:BinaryDecode(nodeId)
  local baseId = self.ExtObjects[nodeId].baseId
  local dec = self.Decoder[baseId]
  if not dec then
    error("No Binary decoder for node: " .. nodeId)
  end
  return dec(self, self.BinaryDeserializer, nodeId)
end

function Decoder:JsonDecode(nodeId)
  local baseId = self.ExtObjects[nodeId].baseId
  local dec = self.Decoder[baseId]
  if not dec then
    error("No JSON decoder for node: " .. nodeId)
  end
  return dec(self, self.JsonDeserializer, nodeId)
end

function Decoder:getExtObject(nodeId)
  local extObj = self.model.ExtObjects[nodeId]
  local encF = extObj and self[extObj.baseId]
  return extObj, encF
end

function Encoder:getExtObject(nodeId)
  local extObj = self.model.ExtObjects[nodeId]
  local encF = extObj and self[extObj.baseId]
  return extObj, encF
end

Encoder["i=1"] = Encoder.boolean
Encoder["i=2"] = Encoder.int8
Encoder["i=3"] = Encoder.uint8
Encoder["i=4"] = Encoder.uint16
Encoder["i=5"] = Encoder.uint16
Encoder["i=6"] = Encoder.int32
Encoder["i=7"] = Encoder.uint32
Encoder["i=8"] = Encoder.int64
Encoder["i=9"] = Encoder.uint64
Encoder["i=10"] = Encoder.float
Encoder["i=11"] = Encoder.double
Encoder["i=13"] = Encoder.dateTime
Encoder["i=294"] = Encoder.dateTime
Encoder["i=12"] = Encoder.string
Encoder["i=14"] = Encoder.guid
Encoder["i=15"] = Encoder.byteString
Encoder["i=16"] = Encoder.xmlElement
Encoder["i=17"] = Encoder.nodeId
Encoder["i=18"] = Encoder.expandedNodeId
Encoder["i=19"] = Encoder.statusCode
Encoder["i=20"] = Encoder.qualifiedName
Encoder["i=21"] = Encoder.localizedText
Encoder["i=22"] = Encoder.encodeStructure
Encoder["i=23"] = Encoder.dataValue
Encoder["i=24"] = "error" -- BaseDataType
Encoder["i=25"] = Encoder.diagnosticInfo
Encoder["i=26"] = "error" -- Number
Encoder["i=27"] = "error" -- Integer
Encoder["i=28"] = "error" -- UInteger
Encoder["i=29"] = Encoder.encodeEnum

Decoder["i=1"] =   Decoder.boolean
Decoder["i=2"] =   Decoder.int8
Decoder["i=3"] =   Decoder.uint8
Decoder["i=4"] =   Decoder.uint16
Decoder["i=5"] =   Decoder.uint16
Decoder["i=6"] =   Decoder.int32
Decoder["i=7"] =   Decoder.uint32
Decoder["i=8"] =   Decoder.int64
Decoder["i=9"] =   Decoder.uint64
Decoder["i=10"] =  Decoder.float
Decoder["i=11"] =  Decoder.double
Decoder["i=13"] =  Decoder.dateTime
Decoder["i=294"] = Decoder.dateTime
Decoder["i=12"] =  Decoder.string
Decoder["i=14"] =  Decoder.guid
Decoder["i=15"] =  Decoder.byteString
Decoder["i=16"] =  Decoder.xmlElement
Decoder["i=17"] =  Decoder.nodeId
Decoder["i=18"] =  Decoder.expandedNodeId
Decoder["i=19"] =  Decoder.statusCode
Decoder["i=20"] =  Decoder.qualifiedName
Decoder["i=21"] =  Decoder.localizedText
Decoder["i=23"] =  Decoder.dataValue
Decoder["i=22"] =  Decoder.decodeStructure
Decoder["i=24"] = "error" -- BaseDataType
Decoder["i=25"] = Decoder.diagnosticInfo
Decoder["i=26"] = "error" -- Number
Decoder["i=27"] = "error" -- Integer
Decoder["i=28"] = "error" -- UInteger
Decoder["i=29"] = Decoder.uint32 -- Enumeration

return {
  CreateEncoder = function(model, serializer)
    local encoder = {
      model = model,
      Serializer = serializer,
    }

    setmetatable(encoder, {
      __index = Encoder,
      __newindex = function()
        error("Encoder is read-only")
      end
    })
    return encoder
  end,
  CreateDecoder = function(model, deserializer)

    local decoder = {
      model = model,
      Deserializer = deserializer,
    }

    setmetatable(decoder, {
      __index = Decoder,
      __newindex = function()
        error("Decoder is read-only")
      end
    })
    return decoder

  end,
}
