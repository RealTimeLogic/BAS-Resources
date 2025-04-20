local compat = require("opcua.compat")
local n = require("opcua.node_id")
local s = require("opcua.status_codes")
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
    locale = self:string()
  end
  if textSpecified ~= 0 then
    text = self:string()
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
  local vt = self:bit(6)

  local hasDimensions = self:bit(1)
  local isArray = self:bit(1) == 1
  if isArray then
    arrLen = self:int32()
  end

  if vt == 1 then
    decFunc = self.boolean
  elseif vt == 2 then
    decFunc = self.sbyte
  elseif vt == 3 then
    decFunc = self.byte
  elseif vt == 4 then
    decFunc = self.int16
  elseif vt == 5 then
    decFunc = self.uint16
  elseif vt == 6 then
    decFunc = self.int32
  elseif vt == 7 then
    decFunc = self.uint32
  elseif vt == 8 then
    decFunc = self.int64
  elseif vt == 9 then
    decFunc = self.uint64
  elseif vt == 10 then
    decFunc = self.float
  elseif vt == 11 then
    decFunc = self.double
  elseif vt == 12 then
    decFunc = self.string
  elseif vt == 13 then
    decFunc = self.dateTime
  elseif vt == 14 then
    decFunc = self.guid
  elseif vt == 15 then
    decFunc = self.byteString
  elseif vt == 16 then
    decFunc = self.xmlElement
  elseif vt == 17 then
    decFunc = self.nodeId
  elseif vt == 18 then
    decFunc = self.expandedNodeId
  elseif vt == 19 then
    decFunc = self.statusCode
  elseif vt == 20 then
    decFunc = self.qualifiedName
  elseif vt == 21 then
    decFunc = self.localizedText
  elseif vt == 22 then
    decFunc = self.extensionObject
  elseif vt == 23 then
    decFunc = self.dataValue
  elseif vt == 24 then
    decFunc = self.variant
  elseif vt == 25 then
    decFunc = self.diagnosticInfo
  elseif vt ~= 0 then
    error(s.BadDecodingError)
  end

  local val
  if decFunc then
    if isArray == false then
      val = decFunc(self, model)
    else
      val = {}
      for _=1,arrLen do
        local curVal = decFunc(self, model)
        tins(val, curVal)
      end
    end
  end

  if hasDimensions == 1 then
    local dimLen = self:int32()
    local dims = {}
    for _=1,dimLen do
      local dim = self:int32()
      tins(dims, dim)
    end
    v.ArrayDimensions = dims
  end

  v.Type = vt
  v.IsArray = isArray
  v.Value = val

  return v
end

function dec:extensionObject(decoder)
  local typeId = self:expandedNodeId()
  local extObject, encF
  if decoder then
    extObject, encF = decoder:getExtObject(typeId)
  end

  local dataTypeId = extObject and extObject.dataTypeId or typeId
  local v = {
    TypeId = dataTypeId
  }

  local binaryBody = self:bit()
  self:bit(7)
  if binaryBody ~= 0 then
    if encF then
      self:uint32()
      v.Body = decoder:Decode(dataTypeId)
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
    SecurityPolicyUri = self:string(),
    SenderCertificate = self:byteString(),
    ReceiverCertificateThumbprint = self:byteString()
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
    EndpointUrl = self:string()
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
    Reason = self:string()
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
    additionalInfo = self:string()
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
  local data1 = self:uint32()
  local data2 = self:uint16()
  local data3 = self:uint16()
  local data4 = self:byte()
  local data5 = self:byte()
  local data6 = self:byte()
  local data7 = self:byte()
  local data8 = self:byte()
  local data9 = self:byte()
  local data10 = self:byte()
  local data11 = self:byte()

  return string.format("%08x-%04x-%04x-%02x%02x-%02x%02x%02x%02x%02x%02x",
    data1, data2, data3, data4, data5, data6, data7, data8, data9, data10, data11)
end

dec.xmlElement = dec.string

function dec:qualifiedName()
  local ns
  local name
  ns = self:uint16()
  name = self:string()
  return {
    ns = ns,
    Name = name,
  }
end

function dec:dataValue(model)
  local valueSpecified = self:bit()
  local statusCodeSpecified = self:bit()
  local sourceTimestampSpecified = self:bit()
  local serverTimestampSpecified = self:bit()
  local sourcePicosecondsSpecified = self:bit()
  local serverPicosecondsSpecified = self:bit()
  self:bit(2)

  local data = {}
  if valueSpecified ~= 0 then
    data = self:variant(model)
  end
  if statusCodeSpecified ~= 0 then
    data.StatusCode = self:statusCode()
  end
  if sourceTimestampSpecified ~= 0 then
    data.SourceTimestamp = self:dateTime()
  end
  if serverTimestampSpecified ~= 0 then
    data.ServerTimestamp = self:dateTime()
  end
  if sourcePicosecondsSpecified ~= 0 then
    data.SourcePicoseconds = self:uint16()
  end
  if serverPicosecondsSpecified ~= 0 then
    data.ServerPicoseconds = self:uint16()
  end

  return data
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
