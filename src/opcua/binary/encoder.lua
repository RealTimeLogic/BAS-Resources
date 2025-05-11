local s = require "opcua.status_codes"
local types = require "opcua.types"
local nodeId = require("opcua.node_id")
local tools = require("opcua.binary.tools")

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
  if type(val) == "string" then
    self.data:pushBack(val)
  elseif type(val) == "table" then
    for i = 1, #val do
      self:char(val[i])
    end
  else
    error(BadEncodingError)
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
    self:string(v.Locale)
  end
  if v.Text ~= nil then
    self:string(v.Text)
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

  if type(v) == 'table' and v.id ~= nil then
    id = v.id
    if v.ns ~= nil then
      if type(v.ns) == 'number' then
        ns = v.ns
      elseif type(v.ns) == 'string' then
        nsUri = v.ns
      end
    end
    si = v.srv
    idType = v.type
  elseif type(v) == 'string' and not tools.guidValid(v) then
    v = nodeId.fromString(v)
    idType = v.type
    id = v.id
    if type(v.ns) == 'number' then
      ns = v.ns
    elseif type(v.ns) == 'string' then
      nsUri = v.ns
    end
  si = v.srv
  else
    id = v
  end

  if ns < 0 or ns > 0xFF then
    error(s.BadEncodingError)
  end

  if idType == nil or idType == nodeId.Numeric then
    if type(id) == 'number' then
      if id < 0 then
        error(s.BadEncodingError)
      end
      if id <= 0xFF and ns == 0 and nsUri == nil then
        idType = nodeId.TwoByte
      else
        if id <= 0xFFFF then
          idType = nodeId.FourByte
        elseif id <= 0xFFFFFFFF then
          idType = nodeId.Numeric
        else
          error(s.BadEncodingError)
        end
      end
    elseif tools.guidValid(id) then
      idType = nodeId.Guid
    elseif type(id) == 'string' then
      idType = nodeId.String
    elseif type(id) == 'table' then
      idType = nodeId.ByteString
    else
      error(s.BadEncodingError)
    end
  end

  if idType == nodeId.TwoByte then
    idEnc = self.uint8
    nsiEnc = nil
  elseif idType == nodeId.FourByte then
    idEnc = self.uint16
    nsiEnc = self.uint8
  elseif idType == nodeId.Numeric then
    idType = nodeId.Numeric
    idEnc = self.uint32
  elseif idType == nodeId.String then
    idEnc = self.string
  elseif idType == nodeId.Guid then
    idEnc = self.guid
  elseif idType == nodeId.ByteString then
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
  local vt = v.Type

  if vt == types.VariantType.Null then
    self:byte(0)
    return
  elseif vt == types.VariantType.Boolean then
    data = v.Value
    encFunc = self.boolean
  elseif vt == types.VariantType.SByte then
    data = v.Value
    encFunc = self.sbyte
  elseif vt == types.VariantType.Byte then
    data = v.Value
    encFunc = self.byte
  elseif vt == types.VariantType.Int16 then
    data = v.Value
    encFunc = self.int16
  elseif vt == types.VariantType.UInt16 then
    data = v.Value
    encFunc = self.uint16
  elseif vt == types.VariantType.Int32 then
    data = v.Value
    encFunc = self.int32
  elseif vt == types.VariantType.UInt32 then
    data = v.Value
    encFunc = self.uint32
  elseif vt == types.VariantType.Int64 then
    data = v.Value
    encFunc = self.int64
  elseif vt == types.VariantType.UInt64 then
    data = v.Value
    encFunc = self.uint64
  elseif vt == types.VariantType.Float then
    data = v.Value
    encFunc = self.float
  elseif vt == types.VariantType.Double then
    data = v.Value
    encFunc = self.double
  elseif vt == types.VariantType.String then
    data = v.Value
    encFunc = self.string
  elseif vt == types.VariantType.DateTime then
    data = v.Value
    encFunc = self.dateTime
  elseif vt == types.VariantType.Guid then
    data = v.Value
    encFunc = self.guid
  elseif vt == types.VariantType.ByteString then
    data = v.Value
    encFunc = self.byteString
  elseif vt == types.VariantType.XmlElement then
    data = v.Value
    encFunc = self.xmlElement
  elseif vt == types.VariantType.NodeId then
    data = v.Value
    encFunc = self.nodeId
  elseif vt == types.VariantType.ExpandedNodeId then
    data = v.Value
    encFunc = self.expandedNodeId
  elseif vt == types.VariantType.StatusCode then
    data = v.Value
    encFunc = self.statusCode
  elseif vt == types.VariantType.QualifiedName then
    data = v.Value
    encFunc = self.qualifiedName
  elseif vt == types.VariantType.LocalizedText then
    data = v.Value
    encFunc = self.localizedText
  elseif vt == types.VariantType.ExtensionObject then
    data = v.Value
    encFunc = self.extensionObject
  elseif vt == types.VariantType.DataValue then
    data = v.Value
    encFunc = self.dataValue
  elseif vt == types.VariantType.Variant then
    data = v.Value
    encFunc = self.variant
  elseif vt == types.VariantType.DiagnosticInfo then
    data = v.Value
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

  self:bit(vt, 6)
  if v.ArrayDimensions ~= nil then
    self:bit(1, 1)
  else
    self:bit(0, 1)
  end

  if v.IsArray then
    self:bit(1, 1) -- ArrayLengthSpecified =
    self:int32(#data)
    for i =1,#data do
      encFunc(self, data[i], model)
    end
  else
    self:bit(0, 1) -- ArrayLengthSpecified = 0
    encFunc(self, data, model)
  end

  if v.ArrayDimensions ~= nil then
    self:int32(#v.ArrayDimensions)
    for _,dim in ipairs(v.ArrayDimensions) do
      self:int32(dim)
    end
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

function enc:extensionObject(v, encoder)
  local typeId = v.TypeId
  local body = v.Body
  local extObject, encF
  if encoder then
    extObject, encF = encoder:getExtObject(typeId)
  end

  self:expandedNodeId(extObject and extObject.binaryId or typeId)
  self:bit(body ~= nil and 1 or 0, 1)
  self:bit(0, 7)
  if body ~= nil then
    -- Extension object body is encoded as bytestring.
    -- To encode extension object as byte string we should know its size
    -- To calculate size we use a helper class instead buffer.
    -- After calculating size we encode extension object.
    if encF then
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
      local serializer = encoder.Serializer
      encoder.Serializer = extEnc
      local suc, result = pcall(encF, encoder, body, typeId)
      encoder.Serializer = serializer
      if not suc then
        error(result)
      end
      -- serialize size
      self:uint32(extBuf.size)
      -- serialize extension object
      encF(encoder, body, typeId)
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
  self:string(securityPolicyUri)
  self:byteString(senderCertificate)
  self:byteString(receiverCertificateThumbprint)
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
  self:string(val.EndpointUrl)
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
  self:string(val.Reason)
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
    self:string(v.AdditionalInfo)
  end
  if v.InnerStatusCode ~= nil then
    self:statusCode(v.InnerStatusCode)
  end
  if v.InnerDiagnosticInfo ~= nil then
    self:diagnosticInfo(v.InnerDiagnosticInfo)
  end
end

function enc:guid(v)
  assert(type(v) == 'string')

  local d1,d2,d3,d4,d5,d6,d7,d8,d9,d10,d11 =
  string.match(v, "^(%x%x%x%x%x%x%x%x)-(%x%x%x%x)-(%x%x%x%x)-(%x%x)(%x%x)-(%x%x)(%x%x)(%x%x)(%x%x)(%x%x)(%x%x)$")

  if not (d1 and d2 and d3 and d4 and d5 and d6 and d7 and d8 and d9 and d10 and d11) then
    error(s.BadDecodingError)
  end

  self:uint32(tonumber(d1, 16))
  self:uint16(tonumber(d2, 16))
  self:uint16(tonumber(d3, 16))
  self:byte(tonumber(d4, 16))
  self:byte(tonumber(d5, 16))
  self:byte(tonumber(d6, 16))
  self:byte(tonumber(d7, 16))
  self:byte(tonumber(d8, 16))
  self:byte(tonumber(d9, 16))
  self:byte(tonumber(d10, 16))
  self:byte(tonumber(d11, 16))
end

enc.xmlElement = enc.string

function enc:qualifiedName(v)
  self:uint16(v.ns)
  self:string(v.Name)
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
    self:variant(v, model)
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
