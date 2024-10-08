local s = require "opcua.status_codes"
local nodeId = require("opcua.node_id")
local tools = require("opcua.binary.tools")
require "math"

local abs = math.abs
local modf = math.modf
local min = math.min
local max = math.max
local huge = math.huge
local floor = math.floor
local log = math.log
local ldexp = math.ldexp or function(x,e)
  return x * (2 ^ e)
end

local log2 = log(2)
local frexp = math.frexp or function(x)
	if x == 0 then return 0, 0 end
	local e = floor(log(abs(x)) / log2 + 1)
	return x / 2 ^ e, e
end

local BadEncodingError = s.BadEncodingError

local function packFloat(n) -- IEEE754
  local sign = 0
  if n < 0.0 then
    sign = 0x80
    n = -n
  end
  local mant, expo = frexp(n)
  if mant ~= mant then
    return 0x7F << 24 | 0x80 << 16 | 0x00 | 0x00 -- nan
  elseif mant == huge or expo > 0x80 then
    if sign == 0 then
      return 0x7F << 24 | 0x80 << 16 | 0x00 | 0x00 -- inf
    else
      return 0xFF << 24 | 0x80 << 16 | 0x00 | 0x00 -- -inf
    end
  elseif (mant == 0.0 and expo == 0) or expo < -0x7E then
    return sign << 24| 0x00 | 0x00 | 0x00 -- zero
  else
    expo = expo + 0x7E
    mant = floor((mant * 2.0 - 1.0) * ldexp(0.5, 24))
    return (sign + floor(expo / 0x2)) << 24 |
           ((expo % 0x2) * 0x80 + floor(mant / 0x10000)) << 16 |
           (floor(mant / 0x100) % 0x100) << 8 |
           (mant % 0x100)
  end
end


local function packDouble(n)
    local sign = 0
    if n < 0.0 then
        sign = 0x80
        n = -n
    end
    local mant, expo = frexp(n)
    if mant ~= mant then
        return {0xFF << 24 | 0xF8 << 16 | 0x00 | 0x00 , 0x00 | 0x00 | 0x00 | 0x00} -- nan
    elseif mant == huge or expo > 0x400 then
        if sign == 0 then
          return {0x7F << 24 | 0xF0 << 16 | 0x00 | 0x00, 0x00 | 0x00 | 0x00 | 0x00} -- inf
        else
          return {0xFF << 24 | 0xF0 << 16 | 0x00 | 0x00, 0x00 | 0x00 | 0x00 | 0x00} -- -inf
        end
    elseif (mant == 0.0 and expo == 0) or expo < -0x3FE then
        return {sign << 24 | 0x00 | 0x00 | 0x00 , 0x00 | 0x00 | 0x00 | 0x00 }-- zero
    else
        expo = expo + 0x3FE
        mant = floor((mant * 2.0 - 1.0) * ldexp(0.5, 53))
        return {

               ((sign + floor(expo / 0x10)) << 24) |
               (((expo % 0x10) * 0x10 + floor(mant / 0x1000000000000)) << 16) |
               ((floor(mant / 0x10000000000) % 0x100) << 8) |
               ((floor(mant / 0x100000000) % 0x100)),

               ((floor(mant / 0x1000000) % 0x100) << 24) |
               ((floor(mant / 0x10000) % 0x100) << 16) |
               ((floor(mant / 0x100) % 0x100) << 8) |
               (mant % 0x100)
              }
    end
end

local enc={}
enc.__index=enc

function enc:bit(num, size)
  if type(num) == "boolean" then
    num = (num == true and 1 or 0)
  elseif type(num) ~= "number" then
    error(BadEncodingError)
  end

  if size == nil or size == 1 then
    size = 1
    num = (num ~= 0 and 1 or 0)
  end

  if size < 1 then
    error(BadEncodingError)
  end

  for _=1,size do
    if self.bits_count < 0 or self.bits_count > 8 then
      error("Internal error: invalid number of bits: "..tostring(self.bits_count))
    end

    self.bits = self.bits | ((num & 1) << self.bits_count)
    self.bits_count = self.bits_count + 1

    if self.bits_count == 8 then
      self.data:pushBack(self.bits)
      self.bits_count = 0
      self.bits = 0
    end

    num = num >> 1
  end
end

function enc:int8(val)
  if self.bits_count ~= 0 then
      error(BadEncodingError)
  end

  if type(val) ~= "number" or val < -128 or val > 127  then
    error(BadEncodingError)
  end

  self.data:pushBack(val & 0xFF)
end

function enc:uint8(val)
  if self.bits_count ~= 0 then
      error(BadEncodingError)
  end
  if type(val) ~= "number" or val < 0 or val > 255 then
    error(BadEncodingError)
  end

  self.data:pushBack(val & 0xFF)
end


function enc:int16(val)
  if type(val) ~= "number" or val < -32768 or val > 32767 then
    error(BadEncodingError)
  end

  self:uint8(val & 0xFF) -- Low Byte
  self:uint8((val >> 8) & 0xFF) -- hi Byte Byte
end

function enc:uint16(val)
  if type(val) ~= "number" or val < 0 or val > 65535 then
    error(BadEncodingError)
  end
  self:uint8(val & 0xFF) -- Low Byte
  self:uint8((val >> 8) & 0xFF) -- High Byte
end

function enc:int32(val)
  if type(val) ~= "number" or val < -2147483648 or val > 2147483647 then
    error(BadEncodingError)
  end

  self:uint16(val & 0xFFFF) -- Low Word
  self:uint16((val >> 16) & 0xFFFF) -- High Word
end

function enc:uint32(val)
  if type(val) ~= "number" or val < 0 or val > 4294967295 then
    error(BadEncodingError)
  end
  self:uint16(val & 0xFFFF) -- Low Word
  self:uint16((val >> 16) & 0xFFFF) -- High Word
end

function enc:int64(val)
  if type(val) ~= "number" or val < math.mininteger or val > math.maxinteger then
    error(BadEncodingError)
  end
  self:uint32(val & 0xFFFFFFFF) -- Low DWord
  self:uint32((val >> 32) & 0xFFFFFFFF) -- High DWord
end

function enc:uint64(val)
  if type(val) ~= "number" or val < 0 or val > math.maxinteger then
    error(BadEncodingError)
  end

  self:uint32(val & 0xFFFFFFFF) -- Low DWord
  self:uint32((val >> 32) & 0xFFFFFFFF) -- High DWord
end

function enc:float(val)
  if type(val) ~= "number" then
    error(BadEncodingError)
  end
  local hex = packFloat(val)
  self:uint32(hex)
end

function enc:double(val)
  if type(val) ~= "number" then
    error(BadEncodingError)
  end
  local hex = packDouble(val)
  local low = hex[2]
  local hi = hex[1]
  self:uint32(low)
  self:uint32(hi)
end

function enc:boolean(v)
  if type(v) == 'boolean' then
    self:uint8(v and 1 or 0)
  else
    error("invalid boolean type")
  end
end

function enc:array(val)
  if type(val) ~= "string" and type(val) ~= "table" then
    error(BadEncodingError)
  end

  for i = 1, #val do
    self:char(tools.index(val, i))
  end
end

function enc:string(v)
  if v == nil then
    self:int32(-1)
  else
    self:int32(#v)
    self:array(v)
  end
end


enc.char = enc.uint8
enc.byte = enc.uint8
enc.sbyte = enc.int8
enc.statusCode = enc.uint32
enc.charArray = enc.string
enc.byteString = enc.string

local function qwordToArr(v)
  return {
    v & 0xFF,
    (v >> 8) & 0xFF,
    (v >> 16) & 0xFF,
    (v >> 24) & 0xFF,
    (v >> 32) & 0xFF,
    (v >> 40) & 0xFF,
    (v >> 48) & 0xFF,
    (v >> 56) & 0xFF,
  }
end

local function arrMul(a, b, base) -- Operands containing rightmost digits at index 1
  local p = #a
  local q = #b
  local tot = 0
  local product = {}
  for ri = 1,(p + q - 1) do
    for bi = max(1, ri - p + 1),min(ri, q) do
      local ai = ri - bi + 1
      tot = tot + (a[ai] * b[bi])
    end
    product[ri] = tot % base
    tot = floor(tot / base)
  end
  product[p+q] = tot % base                    -- Last digit of the result comes from last carry
  return product
end

local function arrAdd(l, r)                  -- Operands containing rightmost digits at index 1
  local c = 0
  local sum = {}
  for i = 1,8 do
    c = l[i] + r[i] + c
    sum[i] = c % 256
    c = floor(c / 256)
  end
  return sum
end

function enc:dateTime(v)
  if type(v) == "string" then
    v = ba.parsedate(v)
  end

  local shift = 0 -- shift in seconds from year 1601
  if v ~= nil then
    shift = 11644473600 -- shift in seconds from year 1601
  else
    v = 0
  end
  local b,e = modf(v)
  e = floor(e * 10000)
  local ms = floor(e / 10)
  e = e % 10
  if e >= 5 then
    ms = ms + 1
  end

  if ms == 1000 then
    ms = 0
    b = b + 1
  end

  local us = ms * 10000
  local usarr = qwordToArr(us)
  local shiftQ = qwordToArr(shift)
  local secs = qwordToArr(b)
  local secs1 = arrAdd(secs, shiftQ)
  local ten7 = qwordToArr(10000000)
  local tarr = arrMul(secs1, ten7, 256)
  local res = arrAdd(tarr, usarr)
  self:array(res)
end

function enc:localizedText(v)
  self:bit(v.Locale ~= nil and 1 or 0, 1)
  self:bit(v.Text ~= nil and 1 or 0, 1)
  self:bit(0, 6)
  if v.Locale ~= nil then
    self:charArray(v.Locale)
  end
  if v.Text ~= nil then
    self:charArray(v.Text)
  end
end

function enc:nodeId(v)
  local id -- id value
  local ns = 0  -- namespace index
  local nsUri
  local si -- server index

  local idType -- mask of NodeId Type with NodeIdType | HasServiceIndex | HasNamespaceUri
  local idEnc  -- encoding function of Id
  local nsiEnc = self.uint16 -- namespace Index endcoding func

  if type(v) == 'string' then
    v = nodeId.fromString(v)
  end

  if type(v) == 'table' and v.id ~= nil then
    id = v.id
    if v.ns ~= nil then
      if type(v.ns) == 'number' then
        ns = v.ns
      elseif type(v.ns) == 'string' then
        nsUri = v.ns
      end
    end
    if v.srv ~= nil then
      si = v.srv
    end
  else
    id = v
  end

  if ns < 0 or ns > 0xFF then
    error(s.BadEncodingError)
  end

  if type(id) == 'number' then
    if id < 0 then
      error(s.BadEncodingError)
    end
    if id <= 0xFF and ns == 0 and nsUri == nil then
      idType = nodeId.TwoByte
      idEnc = self.uint8
      nsiEnc = nil
    else
      if id <= 0xFFFF then
        idType = nodeId.FourByte
        idEnc = self.uint16
        nsiEnc = self.uint8
      elseif id <= 0xFFFFFFFF then
        idType = nodeId.Numeric
        idEnc = self.uint32
      else
        error(s.BadEncodingError)
      end
    end
  elseif type(id) == 'string' then
    idType = nodeId.String
    idEnc = self.string
  elseif type(id) == 'table' and id.Data1 ~= nil then
    idType = nodeId.Guid
    idEnc = self.guid
  elseif type(id) == 'table' then
    idType = nodeId.ByteString
    idEnc = self.byteString
  else
    error(s.BadEncodingError)
  end

  if si ~= nil then
    if type(si) ~= 'number' or si < 0 then
      error(s.BadEncodingError)
    end
    idType = idType | nodeId.ServerIndexFlag
  end

  if nsUri ~= nil then
    idType = idType | nodeId.NamespaceUriFlag
  end

  -- Node ID fields mask
  self:uint8(idType)

  -- namespace index
  if nsiEnc ~= nil then
    nsiEnc(self, ns)
  end

  -- Node ID value
  idEnc(self, id)

  -- namespace Uri
  if nsUri ~= nil then
    self:string(nsUri)
  end

  -- Server Index
  if si ~= nil then
    self:uint32(si)
  end
end

enc.expandedNodeId = enc.nodeId

function enc:variant(v, model)
  local data
  local encFunc
  local vt

  if v.Boolean ~= nil then
    vt = 1
    data = v.Boolean
    encFunc = self.boolean
  elseif v.SByte ~= nil then
    vt = 2
    data = v.SByte
    encFunc = self.sbyte
  elseif v.Byte ~= nil then
    vt = 3
    data = v.Byte
    encFunc = self.byte
  elseif v.Int16 ~= nil then
    vt = 4
    data = v.Int16
    encFunc = self.int16
  elseif v.UInt16 ~= nil then
    vt = 5
    data = v.UInt16
    encFunc = self.uint16
  elseif v.Int32 ~= nil then
    vt = 6
    data = v.Int32
    encFunc = self.int32
  elseif v.UInt32 ~= nil then
    vt = 7
    data = v.UInt32
    encFunc = self.uint32
  elseif v.Int64 ~= nil then
    vt = 8
    data = v.Int64
    encFunc = self.int64
  elseif v.UInt64 ~= nil then
    vt = 9
    data = v.UInt64
    encFunc = self.uint64
  elseif v.Float ~= nil then
    vt = 10
    data = v.Float
    encFunc = self.float
  elseif v.Double ~= nil then
    vt = 11
    data = v.Double
    encFunc = self.double
  elseif v.String ~= nil then
    vt = 12
    data = v.String
    encFunc = self.string
  elseif v.DateTime ~= nil then
    vt = 13
    data = v.DateTime
    encFunc = self.dateTime
  elseif v.Guid ~= nil then
    vt = 14
    data = v.Guid
    encFunc = self.guid
  elseif v.ByteString ~= nil then
    vt = 15
    data = v.ByteString
    encFunc = self.byteString
  elseif v.XmlElement ~= nil then
    vt = 16
    data = v.XmlElement
    encFunc = self.xmlElement
  elseif v.NodeId ~= nil then
    vt = 17
    data = v.NodeId
    encFunc = self.nodeId
  elseif v.ExpandedNodeId ~= nil then
    vt = 18
    data = v.ExpandedNodeId
    encFunc = self.expandedNodeId
  elseif v.StatusCode ~= nil then
    vt = 19
    data = v.StatusCode
    encFunc = self.statusCode
  elseif v.QualifiedName ~= nil then
    vt = 20
    data = v.QualifiedName
    encFunc = self.qualifiedName
  elseif v.LocalizedText ~= nil then
    vt = 21
    data = v.LocalizedText
    encFunc = self.localizedText
  elseif v.ExtensionObject ~= nil then
    vt = 22
    data = v.ExtensionObject
    encFunc = self.extensionObject
  elseif v.DataValue ~= nil then
    vt = 23
    data = v.DataValue
    encFunc = self.dataValue
  elseif v.Variant ~= nil then
    vt = 24
    data = v.Variant
    encFunc = self.variant
  elseif v.DiagnosticInfo ~= nil then
    vt = 25
    data = v.DiagnosticInfo
    encFunc = self.diagnosticInfo
  else
    for _,_ in pairs(v) do
      error(s.BadEncodingError)
    end
    self:byte(0)
    return
  end

  assert(data ~= nil)
  assert(vt ~= nil)
  assert(encFunc ~= nil)

  self:bit(vt, 7)
  local isArray = type(data) == 'table' and data[1] ~= nil
  if isArray then
    self:bit(1, 1) -- ArrayLengthSpecified = 1
    self:int32(#data)
    for _,val in ipairs(data) do
      encFunc(self, val, model)
    end
  else
    self:bit(0, 1) -- ArrayLengthSpecified = 0
    encFunc(self, data, model)
  end
end

-------------------------------------
----- ExtensionObject ---------------
-------------------------------------

-- Small helper class that calculates size of serialized data.
local function newSizeQ()
  local sizeQ = {
    pushBack = function(self, data)
      local size = type(data) == "number" and 1 or #data
      self.size = self.size + size
    end,

    clear=function(self)
      self.size = 0
    end,
  }

  return sizeQ
end

function enc:extensionObject(v, model)
  local typeId = v.TypeId
  local body = v.Body

  local extObject = model and model.Nodes[typeId]

  self:expandedNodeId(extObject and extObject.binaryId or typeId)
  self:bit(body ~= nil and 1 or 0, 1)
  self:bit(0, 7)
  if body ~= nil then
    local f = model and model.Encoder[typeId]
    -- Extension object body is encoded as bytestring.
    -- To encode extension object as byte string we should know its size
    -- To calculate size we use a helper class instead buffer.
    -- After calculating size we encode extension object.
    if f then
      local extBuf = self.extBuf
      local extEnc = self.extEnc
      if extEnc == nil then
        extBuf = newSizeQ()
        extEnc = enc.new(extBuf)
        self.extEnc = extEnc
        self.extBuf = extBuf
      end
      extBuf:clear()
      -- calculate size of extension object
      f(model, extEnc, body, typeId)
      -- serialize size
      self:uint32(extBuf.size)
      -- serialize extension object
      f(model, self, body, typeId)
    else
      self:byteString(body)
    end
  end
end

--------------------------------------
--- MessageHeader
--------------------------------------
-- headerType - values from HeaderType
-- chunkType - values from ChunkType
-- chunkSize of message chunk
function enc:messageHeader(headerType, chunkType, chunkSize)
  self:array(headerType)
  self:array(chunkType)
  self:uint32(chunkSize)
end

--------------------------------------
--- secureMessageHeader
--------------------------------------
-- headerType - values from HeaderType
-- chunkType - values from ChunkType
-- chunkSize of message chunk
-- channelId of message chunk

function enc:secureMessageHeader(headerType, chunkType, chunkSize, channelId)
  self:array(headerType)
  self:array(chunkType)
  self:uint32(chunkSize)
  self:uint32(channelId)
end

-------------------------------------
--- AsymmetricSecurityHeader
--------------------------------------

function enc:asymmetricSecurityHeader(securityPolicyUri, senderCertificate, receiverCertificateThumbprint)
  self:charArray(securityPolicyUri)
  self:charArray(senderCertificate)
  self:charArray(receiverCertificateThumbprint)
end

--------------------------------------
--- SymmetricSecurityHeader
--------------------------------------

function enc:symmetricSecurityHeader(val)
  self:uint32(val.TokenId)
end

--------------------------------------
--- SequenceHeader
--------------------------------------

function enc:sequenceHeader(val)
  self:uint32(val.SequenceNumber)
  self:uint32(val.RequestId)
end

--------------------------------------
--- MessageFooter
--------------------------------------

function enc:messageFooter(val)
  self:uint8(val.PaddingSize)
  self:array(val.Padding)
  self:uint8(val.ExtraPaddingSize)
  self:array(val.Signature)
end

--------------------------------------
--- Hello message content
--------------------------------------

function enc:hello(val)
  self:uint32(val.ProtocolVersion)
  self:uint32(val.ReceiveBufferSize)
  self:uint32(val.SendBufferSize)
  self:uint32(val.MaxMessageSize)
  self:uint32(val.MaxChunkCount)
  self:charArray(val.EndpointUrl)
end

--------------------------------------
--- Acknowledge message content
--------------------------------------

function enc:acknowledge(val)
  self:uint32(val.ProtocolVersion)
  self:uint32(val.ReceiveBufferSize)
  self:uint32(val.SendBufferSize)
  self:uint32(val.MaxMessageSize)
  self:uint32(val.MaxChunkCount)
end

--------------------------------------
--- Error content
--------------------------------------

function enc:error(val)
  self:uint32(val.Error)
  self:charArray(val.Reason)
end

function enc:diagnosticInfo(v)
  self:bit(v.SymbolicId ~= nil and 1 or 0, 1)
  self:bit(v.NamespaceURI ~= nil and 1 or 0, 1)
  self:bit(v.LocalizedText ~= nil and 1 or 0, 1)
  self:bit(v.Locale ~= nil and 1 or 0, 1)
  self:bit(v.AdditionalInfo ~= nil and 1 or 0, 1)
  self:bit(v.InnerStatusCode ~= nil and 1 or 0, 1)
  self:bit(v.InnerDiagnosticInfo ~= nil and 1 or 0, 1)
  self:bit(0, 1)
  if v.SymbolicId ~= nil then
    self:int32(v.SymbolicId)
  end
  if v.NamespaceURI ~= nil then
    self:int32(v.NamespaceURI)
  end
  if v.Locale ~= nil then
    self:int32(v.Locale)
  end
  if v.LocalizedText ~= nil then
    self:int32(v.LocalizedText)
  end
  if v.AdditionalInfo ~= nil then
    self:charArray(v.AdditionalInfo)
  end
  if v.InnerStatusCode ~= nil then
    self:statusCode(v.InnerStatusCode)
  end
  if v.InnerDiagnosticInfo ~= nil then
    self:diagnosticInfo(v.InnerDiagnosticInfo)
  end
end

function enc:guid(v)
  self:uint32(v.Data1)
  self:uint16(v.Data2)
  self:uint16(v.Data3)
  self:byte(v.Data4)
  self:byte(v.Data5)
  self:byte(v.Data6)
  self:byte(v.Data7)
  self:byte(v.Data8)
  self:byte(v.Data9)
  self:byte(v.Data10)
  self:byte(v.Data11)
end

function enc:xmlElement(v)
  self:int32(v.Value ~= nil and #v.Value or -1)
  if v.Value ~= nil then
    for i = 1, #v.Value do
      self:char(tools.index(v.Value, i))
    end
  end
end

function enc:qualifiedName(v)
  self:uint16(v.ns)
  self:charArray(v.Name)
end

function enc:dataValue(v, model)
  self:bit(v.Value ~= nil and 1 or 0, 1)
  self:bit(v.StatusCode ~= nil and 1 or 0, 1)
  self:bit(v.SourceTimestamp ~= nil and 1 or 0, 1)
  self:bit(v.ServerTimestamp ~= nil and 1 or 0, 1)
  self:bit(v.SourcePicoseconds ~= nil and 1 or 0, 1)
  self:bit(v.ServerPicoseconds ~= nil and 1 or 0, 1)
  self:bit(0, 2)
  if v.Value ~= nil then
    self:variant(v.Value, model)
  end
  if v.StatusCode ~= nil then
    self:statusCode(v.StatusCode)
  end
  if v.SourceTimestamp ~= nil then
    self:dateTime(v.SourceTimestamp)
  end
  if v.ServerTimestamp ~= nil then
    self:dateTime(v.ServerTimestamp)
  end
  if v.SourcePicoseconds ~= nil then
    self:uint16(v.SourcePicoseconds)
  end
  if v.ServerPicoseconds ~= nil then
    self:uint16(v.ServerPicoseconds)
  end
end

local nilFunc = function() end
enc.beginField = nilFunc
enc.endField = nilFunc
enc.beginObject = nilFunc
enc.endObject = nilFunc
enc.endArray = nilFunc

function enc:beginArray(size)
  self:int32(size)
end

function enc.new(q)
  local res = {
    data = q,
    bits_count = 0,
    bits = 0,
  }
  setmetatable(res, enc)
  return res
end

return enc
