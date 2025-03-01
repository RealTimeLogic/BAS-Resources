local types = require("opcua.types")
local binaryEncoder = require("opcua.binary.encoder")
local binaryDecoder = require("opcua.binary.decoder")
local jsonEncoder = require("opcua.json.encoder")
local jsonDecoder = require("opcua.json.decoder")
local q = require("opcua.binary.queue")

local AttributeId = types.AttributeId
local NodeClass = types.NodeClass

local HasEncoding <const> = "i=38"
local HasSubtype <const> = "i=45"

local tins = table.insert

local dbg = false

local function getBaseDatatype(dataTypeId, nodes, enc)
  if enc[dataTypeId] then
    return dataTypeId
  end

  local curDataTypeId = dataTypeId
  while curDataTypeId do
    local node <const> = nodes[curDataTypeId]
    if not node then
      error("No node for id: " .. dataTypeId)
    end
    curDataTypeId = nil
    for _, ref in pairs(node.refs) do
      -- Find reference to base data type
      if ref.type == HasSubtype and not ref.isForward then

        -- Check if base data type has encoder
        local targetDataTypeId = ref.target
        if enc[targetDataTypeId] then
          return targetDataTypeId
        end

        -- Go up the inheritance tree
        local parentNode <const> = nodes[targetDataTypeId]
        if not parentNode then
          error("No node for id: " .. targetDataTypeId)
        end

        curDataTypeId = targetDataTypeId
      end
    end
  end
  error("Cannof find base datatype" .. dataTypeId)
end

local function encodeStructure(model, enc, struct, dataTypeId)
  local definition = model.Nodes[dataTypeId].definition
  if not definition then
    return enc:extensionObject(struct, model)
  end

  enc:beginObject()
  for _, field in ipairs(definition) do
    local dataType = field.DataType
    local encF = model.Encoder[dataType]
    if not encF then
      error("No encoder for type: " .. dataType)
    end
    enc:beginField(field.Name)

    local val = struct[field.Name]
    if field.ValueRank == 1 then
      if dbg then print("encoding array: "..field.Name) end
      if val == nil then
        enc:beginArray(-1)
      else
        enc:beginArray(#val)
        for i, el in ipairs(val) do
          if dbg then print("encoding array element"..tostring(i)) end
          encF(model, enc, el, dataType)
        end
      end
      enc:endArray()
    else
      if dbg then print("encoding field: " .. field.Name) end
      encF(model, enc, val, dataType)
    end
    enc:endField(field.Name)
  end
  enc:endObject()
end

local function decodeStructure(model, dec, dataTypeId)
  local struct = {}
  dec:beginObject()
  local definition = model.Nodes[dataTypeId].definition
  if not definition or #definition == 0 then
    struct = dec:extensionObject(model)
  else
    for _, field in ipairs(definition) do
      local dataType = field.DataType
      local decF = model.Decoder[dataType]
      if not decF then
        error("No decoder for type: " .. dataType)
      end
      if dbg then print("decoding field: " .. field.Name) end
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
            tins(val, decF(model, dec, dataType))
          end
        end
        dec:endArray()
      else
        val = decF(model, dec, dataType)
      end
      struct[field.Name] = val
      dec:endField(field.Name)
    end
  end

  dec:endObject()

  return struct
end

-- NOTE: Decoding enumm not to strings but to numbers
-- Search function for decoding base type node
local function encodeEnum(enc, val, fields)
  if type(val) == "string" then
    for _, field in ipairs(fields) do
      if field.Name == val then
        val = field.Value
        break
      end
    end
  end
  enc:uint32(val)
end

local Encoder <const> = {
  boolean = function(_, s, v)  s:boolean(v) end,
  int8 = function(_, s, v) s:int8(v) end,
  uint8 = function(_, s, v) s:uint8(v) end,
  int16 = function(_, s, v) s:int16(v) end,
  uint16 = function(_, s, v) s:uint16(v) end,
  int32 = function(_, s, v)  s:int32(v) end,
  uint32 = function(_, s, v) s:uint32(v) end,
  int64 = function(_, s, v) s:int64(v) end,
  uint64 = function(_, s, v) s:uint64(v) end,
  float = function(_, s, v) s:float(v) end,
  double = function(_, s, v) s:double(v) end,
  dateTime = function(_, s, v) s:dateTime(v) end,
  string = function(_, s, v) s:string(v) end,
  guid = function(_, s, v) s:guid(v) end,
  byteString = function(_, s, v) s:byteString(v) end,
  xmlElement = function(_, s, v) s:xmlElement(v) end,
  nodeId = function(_, s, v) s:nodeId(v) end,
  expandedNodeId = function(_, s, v) s:expandedNodeId(v) end,
  statusCode = function(_, s, v) s:statusCode(v) end,
  qualifiedName = function(_, s, v) s:qualifiedName(v) end,
  localizedText = function(_, s, v) s:localizedText(v) end,
  dataValue = function(self, s, v) s:dataValue(v, self) end,
  diagnosticInfo = function(_, s, v) s:diagnosticInfo(v) end,
  extensionObject = function(self, s, v) return s:extensionObject(v, self) end,
  encodeStructure = encodeStructure,
  encodeEnum = encodeEnum,
}

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
Encoder["i=22"] = encodeStructure
Encoder["i=23"] = Encoder.dataValue
Encoder["i=24"] = "error" -- BaseDataType
Encoder["i=25"] = Encoder.diagnosticInfo
Encoder["i=26"] = "error" -- Number
Encoder["i=27"] = "error" -- Integer
Encoder["i=28"] = "error" -- UInteger
Encoder["i=29"] = encodeEnum

local Decoder <const> = {
  boolean = function(_, s) return s:boolean() end,
  int8 = function(_, s) return s:int8() end,
  uint8 = function(_, s) return s:uint8() end,
  int16 = function(_, s) return s:int16() end,
  uint16 = function(_, s) return s:uint16() end,
  int32 = function(_, s)  return s:int32() end,
  uint32 = function(_, s) return s:uint32() end,
  int64 = function(_, s) return s:int64() end,
  uint64 = function(_, s) return s:uint64() end,
  float = function(_, s) return s:float() end,
  double = function(_, s) return s:double() end,
  dateTime = function(_, s) return s:dateTime() end,
  string = function(_, s) return s:string() end,
  guid = function(_, s) return s:guid() end,
  byteString = function(_, s) return s:byteString() end,
  xmlElement = function(_, s) return s:xmlElement() end,
  nodeId = function(_, s) return s:nodeId() end,
  expandedNodeId = function(_, s) return s:expandedNodeId() end,
  statusCode = function(_, s) return s:statusCode() end,
  qualifiedName = function(_, s) return s:qualifiedName() end,
  localizedText = function(_, s) return s:localizedText() end,
  dataValue = function(self, s) return s:dataValue(self) end,
  diagnosticInfo = function(_, s) return s:diagnosticInfo() end,
  extensionObject = function(self, s) return s:extensionObject(self) end,
  decodeStructure = decodeStructure,
  -- decodeEnum = decodeEnum
}

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
Decoder["i=22"] = decodeStructure
Decoder["i=24"] = "error" -- BaseDataType
Decoder["i=25"] = Decoder.diagnosticInfo
Decoder["i=26"] = "error" -- Number
Decoder["i=27"] = "error" -- Integer
Decoder["i=28"] = "error" -- UInteger
Decoder["i=29"] = Decoder.uint32 -- Enumeration


local Model <const> = {}

function Model.fillEncodingNodes(model)
  for dataTypeId, node in pairs(model.Nodes) do
    if node.attrs[AttributeId.NodeClass] ~= NodeClass.DataType then
      goto continue
    end

    -- Search function for encoding base type node
    local baseId = getBaseDatatype(dataTypeId, model.Nodes, model.Encoder)
    local baseEncF = model.Encoder[baseId]
    if not baseEncF then
      error("No encoder for type: " .. dataTypeId)
    end
    local baseDecF = model.Decoder[baseId]
    if not baseDecF then
      error("No decoder for type: " .. dataTypeId)
    end

    if baseId == "i=29" then
      baseEncF = function(_, enc, val)
        encodeEnum(enc, val, node.definition)
      end
    end

    model.Encoder[dataTypeId] = baseEncF
    model.Decoder[dataTypeId] = baseDecF

    -- Search IDs for encoding extention objects: binary, xml etc.
    -- Each extension object contains body in a some format. Each
    -- structrue has an ID and corresponsing ID for encoding format
    -- For example: ServerStatusDataType has own ID i=862 and following encoders:
    --  * ID i=863 for XML encoding
    --  * ID i=864 for binary encoding
    --  * ID i=15367 for JSON encoding

    for _, ref in pairs(node.refs) do
      if ref.type == HasEncoding and ref.isForward then
        local targetId = ref.target
        local encodingNode = model.Nodes[targetId];
        local encoding = encodingNode.attrs[AttributeId.BrowseName]
        if encoding.Name == "Default Binary" then
          node.binaryId = targetId
          model.ExtObjects[targetId] = {
            DataTypeId = dataTypeId,
            Type = "binary"
          }
        end
        if encoding.Name == "Default JSON" then
          node.jsonId = targetId
          model.ExtObjects[targetId] = {
            DataTypeId = dataTypeId,
            Type = "json"
          }
        end
      end
    end

    ::continue::
  end
end

function Model.Encode(self, nodeId, value)
  local enc = self.Encoder[nodeId]
  if not enc then
    error("No encoder for node: " .. nodeId)
  end
  enc(self, self.Serializer, value, nodeId)
end

function Model.EncodeExtensionObject(self, value)
  self.Serializer:extensionObject(value, self)
end

function Model.DecodeExtensionObject(self)
  return self.Deserializer:extensionObject(self)
end

function Model.BinaryEncode(self, nodeId, value)
  local enc = self.Encoder[nodeId]
  if not enc then
    error("No Binary encoder for node: " .. nodeId)
  end
  enc(self, self.BinarySerializer, value, nodeId)
end

function Model.JsonEncode(self, nodeId, value)
  local enc = self.Encoder[nodeId]
  if not enc then
    error("No JSON encoder for node: " .. nodeId)
  end
  enc(self, self.JsonSerializer, value, nodeId)
end

function Model.Decode(self, nodeId)
  local dec = self.Decoder[nodeId]
  if not dec then
    error("No decoder for node: " .. nodeId)
  end
  return dec(self, self.Deserializer, nodeId)
end

function Model.BinaryDecode(self, nodeId)
  local dec = self.Decoder[nodeId]
  if not dec then
    error("No Binary decoder for node: " .. nodeId)
  end
  return dec(self, self.BinaryDeserializer, nodeId)
end

function Model.JsonDecode(self, nodeId)
  local dec = self.Decoder[nodeId]
  if not dec then
    error("No JSON decoder for node: " .. nodeId)
  end
  return dec(self, self.JsonDeserializer, nodeId)
end

Model.LoadXml = require("opcua.model.load_xml")
Model.ExportC = require("opcua.model.export_c")
Model.Validate = require("opcua.model.validate")

Model.Encoder = {}
setmetatable(Model.Encoder, {__index = Encoder})
Model.Decoder = {}
setmetatable(Model.Decoder, {__index = Decoder})

function Model.SetJsonEncoder(self, size)
  self.data = q.new(size)
  self.Serializer = jsonEncoder.new(self.data)
  self.Deserializer = jsonDecoder.new(self.data)
end

function Model.SetBinaryEncoder(self, size)
  self.data = q.new(size)
  self.Serializer = binaryEncoder.new(self.data)
  self.Deserializer = binaryDecoder.new(self.data)
end

local function createModel()
  local model = {
    Nodes = {},
    ExtObjects = {},
    Models = {},
    NamespaceUris = {},
    Aliases = {},
  }

  setmetatable(model, {__index = Model})

  return model
end

local function getBaseModel()
  local model = createModel()
  local ns0 = require("opcua_ns0")
  model.Nodes = ns0
  model:fillEncodingNodes()

  return model
end

return {
  getBaseModel = getBaseModel,
  createModel = createModel
}

