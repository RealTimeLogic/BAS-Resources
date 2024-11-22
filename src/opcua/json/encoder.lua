local s = require("opcua.status_codes")
local compat = require "opcua.compat"
local n = require("opcua.node_id")
local tools = require("opcua.binary.tools")
local tins = table.insert

local BadEncodingError = s.BadEncodingError

local enc={}
enc.__index=enc

function enc.bit(--[[self, num, size]])
  error("not implemented")
end

function enc:int8(val)
  if self.bits_count ~= 0 then
      error(BadEncodingError)
  end

  if type(val) ~= "number" or val < -128 or val > 127  then
    error(BadEncodingError)
  end
  self:jsPushValue(val)
end

function enc:uint8(val)
  if self.bits_count ~= 0 then
      error(BadEncodingError)
  end
  if type(val) ~= "number" or val < 0 or val > 255 then
    error(BadEncodingError)
  end
  self:jsPushValue(val)
end

function enc:int16(val)
  if type(val) ~= "number" or val < -32768 or val > 32767 then
    error(BadEncodingError)
  end
  self:jsPushValue(val)
end

function enc:uint16(val)
  if type(val) ~= "number" or val < 0 or val > 65535 then
    error(BadEncodingError)
  end
  self:jsPushValue(val)
end

function enc:int32(val)
  if type(val) ~= "number" or val < -2147483648 or val > 2147483647 then
    error(BadEncodingError)
  end

  self:jsPushValue(val)
end

function enc:uint32(val)
  if type(val) ~= "number" or val < 0 or val > 4294967295 then
    error(BadEncodingError)
  end

  self:jsPushValue(val & 0xFFFFFFFF)
end

function enc:int64(val)
  if type(val) ~= "number" or val < math.mininteger or val > math.maxinteger then
    error(BadEncodingError)
  end
  self:jsPushValue(val)
end

function enc:uint64(val)
  if type(val) ~= "number" or val < 0 or val > math.maxinteger then
    error(BadEncodingError)
  end

  self:jsPushValue(val)
end

function enc:float(val)
  if type(val) ~= "number" then
    error(BadEncodingError)
  end

  self:jsPushValue(val)
end

function enc:double(val)
  if type(val) ~= "number" then
    error(BadEncodingError)
  end
  self:jsPushValue(val)
end

function enc:boolean(v)
  if type(v) == 'boolean' then
    self:jsPushValue(v)
  else
    error("invalid boolean type")
  end
end

function enc.array(_, val)
  if type(val) ~= "string" and type(val) ~= "table" then
    error(BadEncodingError)
  end

  -- self:pushValue(v)
end

function enc:string(v)
  if v ~= nil then
    self:jsPushValue(v, true)
  else
    self:jsPushValue("null")
  end
end

enc.char = enc.uint8
enc.byte = enc.uint8
enc.sbyte = enc.int8
enc.statusCode = enc.uint32

function enc:byteString(v)
  if v ~= nil then
    v = type(v) == 'string' and v or tools.makeString(v)
    local b64 = compat.b64encode(v)
    self:jsPushValue(b64, true)
  else
    self:jsPushValue("null")
  end
end

function enc:dateTime(v)
  if v == nil then
    self:string("0001-01-01T00:00:00Z")
    return
  end

  if type(v) ~= "number" then
    error(BadEncodingError)
  end

  local secs = math.floor(v)
  local msecs = math.floor((v - secs)*1000 + 0.5)
  local dt = ba.datetime(secs):date()
  local str
  if msecs == 0 then
    str = string.format("%04d-%02d-%02dT%02d:%02d:%02dZ", dt.year, dt.month, dt.day, dt.hour, dt.min, dt.sec)
  else
    str = string.format("%04d-%02d-%02dT%02d:%02d:%02d.%03dZ", dt.year, dt.month, dt.day, dt.hour, dt.min, dt.sec, msecs)
  end
  self:string(str)
end

function enc:guid(v)
  if not tools.guidValid(v) then
    error(s.BadDecodingError)
  end

  self:string(v)
end

function enc:localizedText(v)
  if v == nil then
    self:jsPushValue("null")
    return
  end

  self:beginObject()

  if v.Locale then
    self:beginField("Locale")
    self:string(v.Locale)
    self:endField("Locale")
  end

  self:beginField("Text")
  self:string(v.Text)
  self:endField("Text")

  self:endObject()
end


function enc:qualifiedName(v)
  self:beginObject()

  self:beginField("Name")
  self:string(v.Name)
  self:endField("Name")

  if v.ns ~= 0 then
    self:beginField("Uri")
    self:uint16(v.ns)
    self:endField("Uri")
  end

  self:endObject()
end

function enc:nodeId(v)
  self:beginObject()

  local id -- id value
  local ns = 0  -- namespace index
  local nsUri
  local si -- server index

  local idType -- mask of NodeId Type with NodeIdType | HasServiceIndex | HasNamespaceUri
  local idEnc  -- encoding function of Id

  if type(v) == 'string' then
    v = n.fromString(v)
    id = v.id
    idType = v.type
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
  elseif type(v) == 'table' and v.id ~= nil then
    id = v.id
    idType = v.type
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

  if idType == nil then
    if type(id) == 'number' then
      idType = n.Numeric
    elseif type(id) == 'string' and tools.guidValid(id) then
      idType = n.Guid
    elseif type(id) == 'string' then
      idType = n.String
    elseif type(id) == 'table' then
      idType = n.ByteString
    else
      error(s.BadEncodingError)
    end
  end

  -- WTF: binary nodeIDtypes are different from JSON nodeIDtypes
  if idType == n.Numeric or idType == n.TwoByte or idType == n.FourByte then
    idEnc = self.uint32
    idType = 0
  elseif idType == n.String then
    idEnc = self.string
    idType = 1
  elseif idType == n.Guid then
    idEnc = self.guid
    idType = 2
  elseif idType == n.ByteString then
    idEnc = self.byteString
    idType = 3
  else
    error(s.BadEncodingError)
  end

  -- IDtype is skipped for UInt32 IDs
  if idType ~= 0 then
    self:beginField("IdType")
    self:uint8(idType)
    self:endField("IdType")
  end

  -- Node ID value
  self:beginField("Id")
  idEnc(self, id)
  self:endField("Id")

  -- namespace index
  if ns ~= 0 then
    self:beginField("NamespaceIndex")
    self:uint16(ns)
    self:endField("NamespaceIndex")
  end

  -- namespace Uri
  if nsUri ~= nil then
    self:beginField("NamespaceUri")
    self:string(nsUri)
    self:endField("NamespaceUri")
  end

  -- Server Index
  if si ~= nil then
    self:beginField("ServerIndex")
    self:uint32(si)
    self:endField("ServerIndex")
  end

  self:endObject()
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
  self:beginObject()


  self:beginField("Type")
  self:uint16(vt)
  self:endField("Type")

  self:beginField("Body")
  local isArray = type(data) == 'table' and data[1] ~= nil
  if isArray then
    self:beginArray(#data)
    for _,val in ipairs(data) do
      encFunc(self, val, model)
    end
    self:endArray()
  else
    encFunc(self, data, model)
  end
  self:endField("Body")

  -- TODO Dimensions

  self:endObject()
end

function enc:dataValue(v, model)
  self:beginObject()

  if v.Value then
    self:beginField("Value")
    self:variant(v.Value, model)
    self:endField("Value")
  end

  if v.StatusCode then
    self:beginField("StatusCode")
    self:statusCode(v.StatusCode)
    self:endField("StatusCode")
  end

  if v.SourceTimestamp then
    self:beginField("SourceTimestamp")
    self:dateTime(v.SourceTimestamp)
    self:endField("SourceTimestamp")
  end

  if v.SourcePicoseconds then
    self:beginField("SourcePicoseconds")
    self:uint16(v.SourcePicoseconds)
    self:endField("SourcePicoseconds")
  end

  if v.ServerTimestamp then
    self:beginField("ServerTimestamp")
    self:dateTime(v.ServerTimestamp)
    self:endField("ServerTimestamp")
  end

  if v.ServerPicoseconds then
    self:beginField("ServerPicoseconds")
    self:uint16(v.ServerPicoseconds)
    self:endField("ServerPicoseconds")
  end

  self:endObject()
end

function enc:diagnosticInfo(v)
  self:beginObject()

  if v.SymbolicId ~= nil then
    self:beginField("SymbolicId")
    self:int32(v.SymbolicId)
    self:endField("SymbolicId")
  end
  if v.NamespaceURI ~= nil then
    self:beginField("NamespaceURI")
    self:int32(v.NamespaceURI)
    self:endField("NamespaceURI")
  end
  if v.Locale ~= nil then
    self:beginField("Locale")
    self:int32(v.Locale)
    self:endField("Locale")
  end
  if v.LocalizedText ~= nil then
    self:beginField("LocalizedText")
    self:int32(v.LocalizedText)
    self:endField("LocalizedText")
  end
  if v.AdditionalInfo ~= nil then
    self:beginField("AdditionalInfo")
    self:string(v.AdditionalInfo)
    self:endField("AdditionalInfo")
  end
  if v.InnerStatusCode ~= nil then
    self:beginField("InnerStatusCode")
    self:statusCode(v.InnerStatusCode)
    self:endField("InnerStatusCode")
  end
  if v.InnerDiagnosticInfo ~= nil then
    self:beginField("InnerDiagnosticInfo")
    self:diagnosticInfo(v.InnerDiagnosticInfo)
    self:endField("InnerDiagnosticInfo")
  end

  self:endObject()
end

function enc:extensionObject(v, encoder)
  self:beginObject()

  local extObject
  if encoder then
    extObject = encoder:getExtObject(v.TypeId)
  end

  self:beginField("TypeId")
  self:nodeId(extObject and extObject.jsonId or v.TypeId)
  self:endField("TypeId")

  self:beginField("Encoding")
  self:uint32(0)
  self:endField("Encoding")

  if v.Body then
    self:beginField("Body")
    encoder:Encode(v.TypeId, v.Body)
    self:endField("Body")
  end

  self:endObject()
end

function enc:beginObject()
  local last = self:stackLast()
  if last == 'v' then
    self.data:pushBack(",")
  elseif last == 'a' or last == 'f' then
    self:stackPush('v')
  elseif last then
    error(BadEncodingError)
  end

  self:stackPush('o')
  self.data:pushBack("{")
end

function enc:endObject()
  local last <const> = self:stackLast()
  if last ~= nil and last ~= 'o' and last ~= 'f' then
    error(BadEncodingError)
  end
  if last == 'f' then
    self:stackPop('f')
  end

  self:stackPop('o')
  self.data:pushBack("}")
end

function enc:beginArray(sz)
  local last, prev <const> = self:stackLast()
  if last == nil or last == 'f' or last == 'a' or last == 'v' then
    if last == 'v' and prev == 'a' then -- new element of array
      self.data:pushBack(",")
    end
    if sz == nil or sz >= 0 then
      self.data:pushBack("[")
    end
    if last == 'f' or last == 'a' then
      self:stackPush('v')
    end
    self:stackPush('a')
  else
    error(BadEncodingError)
  end
end

function enc:endArray(sz)
  local last <const> = self:stackLast()
  if last ~= 'v' and last ~= 'a' then
    error(BadEncodingError)
  end

  self:stackPopValue()
  self:stackPop('a')
  if sz == nil or sz >= 0 then
    self.data:pushBack("]")
  else
    self.data:pushBack("null")
  end
end

function enc:beginField(name)
  if name == "" or not name then
    error(BadEncodingError)
  end

  local last, prev <const> = self:stackLast()
  if last == 'o' or (last == 'f' and prev == 'o') then
    self:stackPush('f')
    if last == 'f' then
      self.data:pushBack(',')
    end
    self.data:pushBack('"')
    self.data:pushBack(name)
    self.data:pushBack('"')
    self.data:pushBack(":")
  else
    error(BadEncodingError)
  end
end

function enc:endField()
  local last, prev <const> = self:stackLast()
  if last ~= 'v' or prev ~= 'f' then
    error(BadEncodingError)
  end
  self:stackPopValue()
end

function enc:stackLast()
  local f = self.stack
  local len = #f
  return f[len], f[len - 1]
end

function enc:stackPop(v)
  local f = self.stack
  local len = #f
  if f[len] ~= v then
    error(BadEncodingError)
  end
  f[len] = nil
end

function enc:stackPush(v)
  local last <const> = self:stackLast()
  if (v == 'v' and  last == 'v') or (v == 'f' and  last == 'f') then
    return
  end
  tins(self.stack, v)
end

function enc:stackPopValue()
  local f = self.stack
  if f[#f] == 'v' then
    f[#f] = nil
  end
end

function enc:jsPushValue(v, isString)
  local last, prev <const> = self:stackLast()
  if last == 'c' then
    error(BadEncodingError)
  end

  if last == 'o' then
    error(BadEncodingError)
  end

  if last == 'v' then
    if prev == 'f' then
      error(BadEncodingError)
    end
    if prev == 'a' then
      self.data:pushBack(',')
    end
  end

  if last == nil then
    self:stackPush('c')
  else
    self:stackPush('v')
  end

  if isString then
    self.data:pushBack('"')
  end

  if type(v) ~= 'string' then
    v = tostring(v)
  end
  self.data:pushBack(v)

  if isString then
    self.data:pushBack('"')
  end
end

function enc:jsHasField()
  local f = self.stack
  return f[#f] == 'f'
end

function enc.new(q)
  local res = {
    stack = {},
    data = q,
    bits_count = 0,
    bits = 0,
  }
  setmetatable(res, enc)
  return res
end

return enc
