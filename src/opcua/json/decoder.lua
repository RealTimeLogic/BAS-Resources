local tools = require("opcua.binary.tools")
local compat = require("opcua.compat")
local n = require("opcua.node_id")
local s = require("opcua.status_codes")

local tins = table.insert

local BadDecodingError = s.BadDecodingError

local dec = {}
dec.__index = dec

function dec.bit()
  error(BadDecodingError)
end

function dec:boolean()
  local val = self:stackLastValue()
  if type(val) ~= "boolean" then
    error(BadDecodingError)
  end
  return val == true
end

function dec:stackLastValue()
  local val = self:stackLast()
  if type(val) == "table" and val.pos then
    local pos <const> = val.pos
    if pos == nil or pos > #val then
      error(BadDecodingError)
    end
    val.pos = pos + 1
    val = val[pos]
  end

  if type(val) == "boolean" then
    return val
  end

  return val ~= ba.json.null and val or nil
end

function dec:int8()
  local val = self:stackLastValue()
  if type(val) ~= "number" or (val < -128 or val > 127)  then
    error(BadDecodingError)
  end
  return val
end

function dec:uint8()
  local val = self:stackLastValue()
  if (type(val) ~= "number" or val < 0 or val > 255) then
    error(BadDecodingError)
  end
  return val
end

function dec:int16()
  local val = self:stackLastValue()
  if (type(val) ~= "number" or val < -32768 or val > 32767) then
    error(BadDecodingError)
  end
  return val
end

function dec:uint16()
  local val = self:stackLastValue()
  if (type(val) ~= "number" or val < 0 or val > 65535) then
    error(BadDecodingError)
  end
  return val
end

function dec:int32()
  local val = self:stackLastValue()
  if (type(val) ~= "number" or val < -2147483648 or val > 2147483647) then
    error(BadDecodingError)
  end
  return val
end

function dec:uint32()
  local val = self:stackLastValue()
  if (type(val) ~= "number" or val < 0 or val > 4294967295) then
    error(BadDecodingError)
  end
  return val
end

function dec:int64()
  local val = self:stackLastValue()
  if (type(val) ~= "number" or val < math.mininteger or val > math.maxinteger) then
    error(BadDecodingError)
  end
  return val
end

function dec:uint64()
  local val = self:stackLastValue()
  if (type(val) ~= "number" or val < 0 or val > math.maxinteger) then
    error(BadDecodingError)
  end
  return val
end

function dec:float()
  local val = self:stackLastValue()
  if type(val) ~= "number" then
    error(BadDecodingError)
  end
  return val
end

dec.double = dec.float

function dec:dateTime()
  local str = self:stackLastValue()
  if type(str) ~= "string" then
    error(BadDecodingError)
  end

  if str == "0001-01-01T00:00:00Z" then
    return nil
  end

  local year, month, day, hour, min, sec, msec = str:match("(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)Z")
  if not year then
    year, month, day, hour, min, sec, msec = str:match("(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+).(%d+)Z")
  end

  local date = {
    year = year,
    month = month,
    day = day,
    hour = hour,
    min = min,
    sec = sec,
  }

  sec = ba.datetime(date):ticks()
  msec = msec and (tonumber("0."..msec)) or 0
  return sec + msec
end

function dec:string()
  local val = self:stackLastValue()
  if val ~= nil and type(val) ~= "string" then
    error(BadDecodingError)
  end
  return val
end

function dec:byteString()
  local val = self:string()
  return val and compat.b64decode(val)
end


dec.char = dec.uint8
dec.byte = dec.uint8
dec.sbyte = dec.int8
dec.statusCode = dec.uint32


function dec:guid()
  local str = self:string()
  if not tools.guidValid(str) then
    error(s.BadDecodingError)
  end

  return str
end

function dec:localizedText()
  local lt
  if self:stackLastValue() then
    self:beginObject()
    lt = {}
    self:beginField("Locale")
    if self:stackLastValue() then
      lt.Locale = self:string()
    end
    self:endField("Locale")

    self:beginField("Text")
    if self:stackLastValue() then
      lt.Text = self:string()
    end
    self:endField("Text")
    self:endObject()
  end

  return lt
end

function dec:qualifiedName()
  local name = {}
  self:beginObject()
  self:beginField("Name")
  if self:stackLastValue() then
    name.Name = self:string()
  end
  self:endField("Name")

  self:beginField("Uri")
  if self:stackLastValue() then
    name.ns = self:uint16()
  else
    name.ns = 0
  end
  self:endField("Uri")

  self:endObject()
  return name
end

function dec:nodeId()
  self:beginObject()

  local idType = 0
  -- IDtype is skipped for UInt32 IDs
  if self:stackLastValue()["IdType"] ~= nil then
    self:beginField("IdType")
    idType = self:uint8()
    self:endField("IdType")
  end

  self:beginField("Id")
  local nodeIdType
  if idType == nil then
    local valType = type(self:stackLastValue())
    if valType == "number" then
      idType = 0
    elseif valType == "string" then
      idType = 1
    else
      error(s.BadDecodingError)
    end
  end
  local id
  if idType == 0 then
    id = self:uint32()
    nodeIdType = n.FourByte
  elseif idType == 1 then
    id = self:string()
    nodeIdType = n.String
  elseif idType == 2 then
    id = self:guid()
    nodeIdType = n.Guid
  elseif idType == 3 then
    id = self:byteString()
    nodeIdType = n.ByteString
  else
    error(s.BadDecodingError)
  end
  self:endField("Id")

  local ns = 0
  self:beginField("NamespaceIndex")
  if self:stackLastValue() then
    ns = self:uint16()
  end
  self:endField("NamespaceIndex")

  self:beginField("NamespaceUri")
  if self:stackLastValue() then
    if ns then
      error(s.BadDecodingError)
    end
    ns = self:string()
  end
  self:endField("NamespaceUri")

  local si
  self:beginField("ServerIndex")
  if self:stackLastValue() then
    si = self:uint32()
  end
  self:endField("ServerIndex")

  if ns < 0 or ns > 0xFF then
    error(s.BadDecodingError)
  end

  self:endObject()

  return n.toString(id,ns,si, nodeIdType)
end

dec.expandedNodeId = dec.nodeId

function dec:variant(model)
  local v = {}
  local decFunc

  local last = self:stackLast()
  local vt

  local t = type(last)
  local hasBody = (t == 'table' and last.Body ~= nil)
  if hasBody then
    self:beginObject()
    self:beginField("Type")
    vt = self:int32()
    self:endField("Type")
  else
    local l = last
    if t == 'table' and last[1] then
      t = type(last[1])
      l = last[1]
    end

    if t == 'number' then
      local _,e = math.modf(l)
      if e == 0 then
        vt = 8 -- Int64
      else
        vt = 11 -- Double
      end
    elseif t == 'string' then
      vt = 12
    elseif t == 'boolean' then
      vt = 1
    else -- I don't know how to decode complex structures..
      error(s.BadDecodingError)
    end
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


  if hasBody then
    self:beginField("Body")
    last = self:stackLast()
  end

  local val
  if decFunc then
    if type(last) == 'table' and last[1] ~= nil then
      local arrLen = self:beginArray()

      val = {}
      for _=1,arrLen do
        local curVal = decFunc(self, model)
        tins(val, curVal)
      end

      self:endArray()
    else
      val = decFunc(self, model)
    end
  end

  if hasBody then
    self:endField("Body")
    self:endObject()
  end

  v[vt] = val

  return v
end


function dec:dataValue(model)
  self:beginObject()
  local v = {}

  self:beginField("Value")
  if self:stackLastValue() then
    v.Value = self:variant(model)
  end
  self:endField("Value")

  self:beginField("StatusCode")
  if self:stackLastValue() then
    v.StatusCode = self:statusCode()
  end
  self:endField("StatusCode")

  self:beginField("SourceTimestamp")
  if self:stackLastValue() then
    v.SourceTimestamp = self:dateTime()
  end
  self:endField("SourceTimestamp")

  self:beginField("ServerTimestamp")
  if self:stackLastValue() then
    v.ServerTimestamp = self:dateTime()
  end
  self:endField("ServerTimestamp")

  self:beginField("SourcePicoseconds")
  if self:stackLastValue() then
    v.SourcePicoseconds = self:uint16()
  end
  self:endField("SourcePicoseconds")

  self:beginField("ServerPicoseconds")
  if self:stackLastValue() then
    v.ServerPicoseconds = self:uint16()
  end
  self:endField("ServerPicoseconds")

  self:endObject()

  return v
end

function dec:diagnosticInfo()
  self:beginObject()

  local v = {}

  self:beginField("SymbolicId")
  if self:stackLastValue() then
    v.SymbolicId = self:int32()
  end
  self:endField("SymbolicId")

  self:beginField("NamespaceURI")
  if self:stackLastValue() then
    v.NamespaceURI = self:int32()
  end
  self:endField("NamespaceURI")

  self:beginField("Locale")
  if self:stackLastValue() then
    v.Locale = self:int32()
  end
  self:endField("Locale")

  self:beginField("LocalizedText")
  if self:stackLastValue() then
    v.LocalizedText = self:int32()
  end
  self:endField("LocalizedText")

  self:beginField("AdditionalInfo")
  if self:stackLastValue() then
    v.AdditionalInfo = self:string()
  end
  self:endField("AdditionalInfo")

  self:beginField("InnerStatusCode")
  if self:stackLastValue() then
    v.InnerStatusCode = self:statusCode()
  end
  self:endField("InnerStatusCode")

  self:beginField("InnerDiagnosticInfo")
  if self:stackLastValue() then
    v.InnerDiagnosticInfo = self:diagnosticInfo()
  end
  self:endField("InnerDiagnosticInfo")

  self:endObject()

  return v
end


function dec:extensionObject(decoder)
  self:beginObject()

  self:beginField("TypeId")
  local encodedId = self:nodeId()
  self:endField("TypeId")

  local extObject = decoder:getExtObject(encodedId)
  local v = {
    TypeId = extObject and extObject.dataTypeId or encodedId
  }

  if extObject then
    if self:stackLast()["Encoding"] ~= ba.json.nullt then
      self:beginField("Encoding")
      local encoding = self:uint32()
      if encoding ~= 0 then
        v.Encoding = encoding
      end
      self:endField("Encoding")
    end

    self:beginField("Body")
    if self:stackLast() ~= ba.json.null then
      v.Body = decoder:Decode(v.TypeId)
    end
    self:endField("Body")
  end

  self:endObject()

  return v
end

function dec:beginField(name)
  local last = self:stackLast()
  local val = last[name]
  if type(val) == 'boolean' then
    self:stackPush(val)
  else
    self:stackPush(val or ba.json.null)
  end
end

function dec:endField()
  self:stackPop()
end

function dec:beginObject()
  if self.stack == nil then
    local data = tostring(self.data)
    self.stack = {ba.json.decode(data)}
  end
  self:stackPush(self:stackLastValue())
end

function dec:endObject()
  self:stackPop()
  if #self.stack == 1 then
    self.stack = nil
  end
end

function dec:beginArray()
  local last = self:stackLast()
  if last == ba.json.null then
    return -1
  end
  if type(last) ~= "table" then
    error(BadDecodingError)
  end
  last.pos = 1
  return #last
end

function dec:endArray()
  local last = self:stackLast()
  if last == ba.json.null then
    return
  end
  if type(last) ~= "table" then
    error(BadDecodingError)
  end
  last.pos = nil
end

function dec:stackPush(v)
  tins(self.stack, v)
end

function dec:stackPop()
  local stack = self.stack
  stack[#stack] = nil
end


function dec:stackLast()
  if self.stack == nil then
    local data = tostring(self.data)
    local err
    data, err = ba.json.decode(data)
    if err then
      error(BadDecodingError)
    end
    self.stack = {data}
  end

  local stack = self.stack
  local len = #stack
  return stack[len], stack[len - 1]
end

function dec.new(str)
  local res = {
    data = str,
  }

  setmetatable(res, dec)
  return res
end

return dec
