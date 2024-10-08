local compat = require("opcua.compat")
local n = require("opcua.node_id")
local s = require("opcua.status_codes")
local tools = require "opcua.binary.tools"
local math = require("math")
local tins = table.insert

local floor = math.floor
local ldexp = math.ldexp or function(x,e)
  return x * (2 ^ e)
end

local BadInternalError = s.BadInternalError
local BadDecodingError = s.BadDecodingError
-- local BadNoData = s.BadNoData

local function integer(dec, size, signed)
  if size < 0 or size > 8 or size & (size - 1) ~= 0 then
    error(BadInternalError)
  end

  if dec.bitNum ~= 0 then
    error(BadDecodingError)
  end

  local data = {}
  dec.data:popFront(size, data)

  local val = 0
  for i = 1,size do
    local b = data[i]
    if b < 0 or b > 255 then
      error(BadDecodingError)
    end
    local shift = 8 * (i - 1)
    val = (b << shift) | val
  end

  local sign = (1 << (8 * size - 1))
  local mask = sign-1

  local value
  if signed and (val & sign) ~= 0 then
    value = ((~val) & mask) + 1
    value = -value
  else
    value = val
  end

  return value
end

local dec = {}
dec.__index = dec


function dec:bit(count)
  if count == nil then count = 1 end

  if self.bitNum < 0 or self.bitNum > 7 then
    error(BadInternalError)
  end

  -- well.. array position starts from one in lua :`(
  if (self.bitNum + count > 8) then
    error(BadDecodingError)
  end

  local val = self.b
  if val == nil then
    val = self:uint8()
    self.b = val
  end
  local mask = (0xFF >> (8 - count) )
  local value = val & (mask << self.bitNum)
  value = value >> self.bitNum

  self.bitNum = self.bitNum + count
  if self.bitNum == 8 then
    self.bitNum = 0;
    self.b = nil
  end
  return value
end

function dec:boolean()
  local value = integer(self, 1, false)
  value = value ~= 0 and true or false
  return value
end

function dec:int8()
  return integer(self, 1, true)
end

function dec:uint8()
  return integer(self, 1, false)
end

function dec:int16()
  return integer(self, 2, true)
end

function dec:uint16()
  return integer(self, 2, false)
end

function dec:int32()
  return integer(self, 4, true)
end

function dec:uint32()
  return integer(self, 4, false)
end

function dec:int64()
  return integer(self, 8, true)
end

function dec:uint64()
  return integer(self, 8, false)
end

function dec:float()
  local int = integer(self, 4, false)
  local mantissa = int & 0x007FFFFF
  local exponent = (int >> 23) & 0xFF
  local double = ldexp(1+mantissa/0x800000, exponent-0x7F)
  if (int & 0x80000000) ~= 0 then
    double = -double
  end
  return double
end

function dec:double()
  -- we can't parse integer as with float because lua can't 64-bit integers
  -- parse byte-by-byte
  local b1 = self:uint8()
  local b2 = self:uint8()
  local b3 = self:uint8()
  local b4 = self:uint8()
  local b5 = self:uint8()
  local b6 = self:uint8()
  local b7 = self:uint8()
  local b8 = self:uint8()

  local mantissa = b1 | (b2 << 8) | (b3 << 16) | (b4 << 24) | (b5 << 32) | (b6 << 40) | ((b7 & 0x0F) << 48)
  local exponent = ((b7 &0xFF)>> 4) | ((b8 & 0x7F) << 4)
  local double = ldexp(1+mantissa/(1<<52), exponent-0x3FF)
  if (b8 & 0x80) ~= 0 then
    double = -double
  end
  return double
end

function dec:dateTime()
  local low = self:uint32()
  local hi = self:uint32()

  -- time in UA is 10,000,000 ns and shift from 1601 (FILETIME in MsWin)
  local time = (hi << 32)/1000 + low/1000 -- enough to fit max time and do not lost ms
  time = time/10000 - 11644473600 -- time shift to 1970 in ms

  -- round up to 0.001
  local value = floor(time * 1000 + 0.5) / 1000
  return value
end

function dec:array(size)
  if self.bitNum < 0 or self.bitNum > 7 then
    error(BadInternalError)
  end

  if size == nil then
    error(BadDecodingError)
  end

  -- if #self.data.Buf < size then
  --   error(BadNoData)
  -- end

  if size == 0 then
    return ""
  end

  local data = compat.bytearray.create(size)
  for i = 1,size do
    data[i] = self:uint8()
  end
  return tostring(data)
end

function dec:string()
  local len = self:uint32()
  if len == 0xFFFFFFFF then
    return nil
  end

  if len == 0 then
    return ""
  end
  return self:array(len)
end

dec.char = dec.uint8
dec.byte = dec.uint8
dec.sbyte = dec.int8
dec.statusCode = dec.uint32
dec.charArray = dec.string
dec.byteString = dec.string

local nilFunc = function() end
dec.beginField = nilFunc
dec.endField = nilFunc
dec.beginObject = nilFunc
dec.endObject = nilFunc
dec.beginArray = dec.int32
dec.endArray = nilFunc

function dec:localizedText()
  local localeSpecified
  local textSpecified
  local locale
  local text
  localeSpecified = self:bit()
  textSpecified = self:bit()
  self:bit(6)
  if localeSpecified ~= 0 then
    locale = self:charArray()
  end
  if textSpecified ~= 0 then
    text = self:charArray()
  end
  return {
    Locale = locale,
    Text = text,
  }
end

function dec:nodeId()
  local nodeIdType = self:bit(6)
  if nodeIdType > 5 or nodeIdType < 0  then
    return error(s.BadDecodingError)
  end

  local ns
  local id
  local srv

  local hasSi = self:bit(1)
  local hasNs = self:bit(1)

  if nodeIdType == n.TwoByte then
    if hasNs == 1 then return error(s.BadDecodingError) end
    id = self:uint8()
  elseif nodeIdType == n.FourByte then
    ns = self:uint8()
    id = self:uint16()
  elseif nodeIdType == n.Numeric then
    ns = self:uint16()
    id = self:uint32()
  elseif nodeIdType == n.String then
    ns = self:uint16()
    id = self:string()
  elseif nodeIdType == n.Guid then
    ns = self:uint16()
    id = self:guid()
  elseif nodeIdType == n.ByteString then
    ns = self:uint16()
    id = self:byteString()
  end

  if hasNs == 1 then
    ns = self:string()
  end

  if hasSi == 1 then
    srv = self:uint32()
    if srv == 0 then
      srv = nil
    end
  end

  return n.toString(id,ns,srv, nodeIdType)
end

dec.expandedNodeId = dec.nodeId

function dec:variant(model)
  local v = {}
  local arrLen = 0
  local decFunc
  local vt = self:bit(7)

  local isArray = self:bit(1)
  if isArray ~= 0 then
    arrLen = self:int32()
  end

  if vt == 0 then
    vt = 'Null'
  elseif vt == 1 then
    decFunc = self.boolean
    vt = "Boolean"
  elseif vt == 2 then
    decFunc = self.sbyte
    vt = "SByte"
  elseif vt == 3 then
    decFunc = self.byte
    vt = "Byte"
  elseif vt == 4 then
    decFunc = self.int16
    vt = "Int16"
  elseif vt == 5 then
    decFunc = self.uint16
    vt = "UInt16"
  elseif vt == 6 then
    decFunc = self.int32
    vt = "Int32"
  elseif vt == 7 then
    decFunc = self.uint32
    vt = "UInt32"
  elseif vt == 8 then
    decFunc = self.int64
    vt = "Int64"
  elseif vt == 9 then
    decFunc = self.uint64
    vt = "UInt64"
  elseif vt == 10 then
    decFunc = self.float
    vt = "Float"
  elseif vt == 11 then
    decFunc = self.double
    vt = "Double"
  elseif vt == 12 then
    decFunc = self.string
    vt = "String"
  elseif vt == 13 then
    decFunc = self.dateTime
    vt = "DateTime"
  elseif vt == 14 then
    decFunc = self.guid
    vt = "Guid"
  elseif vt == 15 then
    decFunc = self.byteString
    vt = "ByteString"
  elseif vt == 16 then
    decFunc = self.xmlElement
    vt = "XmlElement"
  elseif vt == 17 then
    decFunc = self.nodeId
    vt = "NodeId"
  elseif vt == 18 then
    decFunc = self.expandedNodeId
    vt = "ExpandedNodeId"
  elseif vt == 19 then
    decFunc = self.statusCode
    vt = "StatusCode"
  elseif vt == 20 then
    decFunc = self.qualifiedName
    vt = "QualifiedName"
  elseif vt == 21 then
    decFunc = self.localizedText
    vt = "LocalizedText"
  elseif vt == 22 then
    decFunc = self.extensionObject
    vt = "ExtensionObject"
  elseif vt == 23 then
    decFunc = self.dataValue
    vt = "DataValue"
  elseif vt == 24 then
    decFunc = self.variant
    vt = "Variant"
  elseif vt == 25 then
    decFunc = self.diagnosticInfo
    vt = "DiagnosticInfo"
  else
    error(s.BadDecodingError)
  end

  local val
  if decFunc then
    if isArray == 0 then
      val = decFunc(self, model)
    else
      val = {}
      for _=1,arrLen do
        local curVal = decFunc(self, model)
        tins(val, curVal)
      end
    end
  end

  v[vt] = val

  return v
end

function dec:extensionObject(model)
  local typeId = self:expandedNodeId()
  local extObject = model and model.ExtObjects[typeId]
  local dataTypeId = extObject and extObject.DataTypeId or typeId
  local v = {
    TypeId = dataTypeId
  }

  local binaryBody = self:bit()
  self:bit(7)
  if binaryBody ~= 0 then
    local f = model and model.Encoder[dataTypeId]
    if f then
      self:uint32()
      v.Body = model:Decode(dataTypeId)
    else
      v.Body = self:byteString()
    end
  end
  return v
end

function dec:messageHeader()
  return {
    Type = self:array(3),
    Chunk = self:array(1),
    MessageSize = self:uint32()
  }
end

function dec:secureMessageHeader()
  return {
    Type = self:array(3),
    Chunk = self:array(1),
    MessageSize = self:uint32(),
    ChannelId = self:uint32()
  }
end

function dec:asymmetricSecurityHeader()
  return {
    SecurityPolicyUri = self:charArray(),
    SenderCertificate = self:charArray(),
    ReceiverCertificateThumbprint = self:charArray()
  }
end

function dec:symmetricSecurityHeader()
  return {
    TokenId = self:uint32()
  }
end

function dec:sequenceHeader()
  return {
    SequenceNumber = self:uint32(),
    RequestId = self:uint32()
  }
end

function dec:hello()
  return {
    ProtocolVersion = self:uint32(),
    ReceiveBufferSize = self:uint32(),
    SendBufferSize = self:uint32(),
    MaxMessageSize = self:uint32(),
    MaxChunkCount = self:uint32(),
    EndpointUrl = self:charArray()
  }
end

function dec:acknowledge()
  return {
    ProtocolVersion = self:uint32(),
    ReceiveBufferSize = self:uint32(),
    SendBufferSize = self:uint32(),
    MaxMessageSize = self:uint32(),
    MaxChunkCount = self:uint32()
  }
end

function dec:error()
  return {
    Error = self:uint32(),
    Reason = self:charArray()
  }
end

function dec:diagnosticInfo()
  local symbolicIdSpecified
  local namespaceURISpecified
  local localizedTextSpecified
  local localeSpecified
  local additionalInfoSpecified
  local innerStatusCodeSpecified
  local innerDiagnosticInfoSpecified
  local symbolicId
  local namespaceURI
  local locale
  local localizedText
  local additionalInfo
  local innerStatusCode
  local innerDiagnosticInfo
  symbolicIdSpecified = self:bit()
  namespaceURISpecified = self:bit()
  localizedTextSpecified = self:bit()
  localeSpecified = self:bit()
  additionalInfoSpecified = self:bit()
  innerStatusCodeSpecified = self:bit()
  innerDiagnosticInfoSpecified = self:bit()
  self:bit(1)
  if symbolicIdSpecified ~= 0 then
    symbolicId = self:int32()
  end
  if namespaceURISpecified ~= 0 then
    namespaceURI = self:int32()
  end
  if localeSpecified ~= 0 then
    locale = self:int32()
  end
  if localizedTextSpecified ~= 0 then
    localizedText = self:int32()
  end
  if additionalInfoSpecified ~= 0 then
    additionalInfo = self:charArray()
  end
  if innerStatusCodeSpecified ~= 0 then
    innerStatusCode = self:statusCode()
  end
  if innerDiagnosticInfoSpecified ~= 0 then
    innerDiagnosticInfo = self:diagnosticInfo()
  end
  return {
    SymbolicId = symbolicId,
    NamespaceURI = namespaceURI,
    Locale = locale,
    LocalizedText = localizedText,
    AdditionalInfo = additionalInfo,
    InnerStatusCode = innerStatusCode,
    InnerDiagnosticInfo = innerDiagnosticInfo,
  }
end

function dec:guid()
  local data1
  local data2
  local data3
  local data4
  local data5
  local data6
  local data7
  local data8
  local data9
  local data10
  local data11
  data1 = self:uint32()
  data2 = self:uint16()
  data3 = self:uint16()
  data4 = self:byte()
  data5 = self:byte()
  data6 = self:byte()
  data7 = self:byte()
  data8 = self:byte()
  data9 = self:byte()
  data10 = self:byte()
  data11 = self:byte()
  return {
    Data1 = data1,
    Data2 = data2,
    Data3 = data3,
    Data4 = data4,
    Data5 = data5,
    Data6 = data6,
    Data7 = data7,
    Data8 = data8,
    Data9 = data9,
    Data10 = data10,
    Data11 = data11,
  }
end

function dec:xmlElement()
  local length
  local value
  length = self:int32()
  if length ~= -1 then
    value = {}
    for _=1,length do
      local tmp
      tmp = self:char()
      tins(value, tmp)
    end
  end
  return {
    Value = tools.makeString(value),
  }
end

function dec:qualifiedName()
  local ns
  local name
  ns = self:uint16()
  name = self:charArray()
  return {
    ns = ns,
    Name = name,
  }
end

function dec:dataValue(model)
  local valueSpecified
  local statusCodeSpecified
  local sourceTimestampSpecified
  local serverTimestampSpecified
  local sourcePicosecondsSpecified
  local serverPicosecondsSpecified
  local value
  local statusCode
  local sourceTimestamp
  local serverTimestamp
  local sourcePicoseconds
  local serverPicoseconds
  valueSpecified = self:bit()
  statusCodeSpecified = self:bit()
  sourceTimestampSpecified = self:bit()
  serverTimestampSpecified = self:bit()
  sourcePicosecondsSpecified = self:bit()
  serverPicosecondsSpecified = self:bit()
  self:bit(2)
  if valueSpecified ~= 0 then
    value = self:variant(model)
  end
  if statusCodeSpecified ~= 0 then
    statusCode = self:statusCode()
  end
  if sourceTimestampSpecified ~= 0 then
    sourceTimestamp = self:dateTime()
  end
  if serverTimestampSpecified ~= 0 then
    serverTimestamp = self:dateTime()
  end
  if sourcePicosecondsSpecified ~= 0 then
    sourcePicoseconds = self:uint16()
  end
  if serverPicosecondsSpecified ~= 0 then
    serverPicoseconds = self:uint16()
  end
  return {
    Value = value,
    StatusCode = statusCode,
    SourceTimestamp = sourceTimestamp,
    ServerTimestamp = serverTimestamp,
    SourcePicoseconds = sourcePicoseconds,
    ServerPicoseconds = serverPicoseconds,
  }
end

function dec.new(encoded_data)
    local res = {
    data = encoded_data,
    bitNum = 0,
  }

  setmetatable(res, dec)
  return res
end

return dec
