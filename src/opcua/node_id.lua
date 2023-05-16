local fmt = string.format
local sub = string.sub
local match = string.match
local sbyte = string.byte
local schar = string.char
local sfind = string.find

local tins = table.insert
local tconcat = table.concat

local TwoByte = 0
local FourByte = 1
local Numeric = 2
local String = 3
local Guid = 4
local ByteString = 5

local function begins(s, i)
  return sub(s, 1, #i) == i
end

local function hexs(s)
  return tonumber(s, 16)
end

local b64decode = ba.b64decode
local b64encode = ba.b64encode

local function fromString(s)
  assert(type(s) == 'string')
  local ns
  local ident
  local srv
  if begins(s,"svr=") then
    srv,s = match(s, "svr=(%d+);(%g+)")
    srv = tonumber(srv)
    assert(srv ~= nil)
    assert(s ~= nil)
  end

  if begins(s,"ns=") then
    ns,ident = match(s, "ns=(%d+);(%g+)")
    assert(ns ~= nil)
    assert(ident ~= nil)
    ns = tonumber(ns)
  elseif begins(s,"nsu=") then
      ns,ident = match(s, "nsu=(%g+);(%g+)")
      assert(ns ~= nil)
      assert(ident ~= nil)
  else
    ident = s
  end

  if begins(ident, "i=") then
    ident = match(ident, "^i=(%d+)$")
    assert(ident ~= nil)
    ident = tonumber(ident)
  elseif begins(ident, "s=") then
    ident = string.match(ident, "^s=(%g+)$")
    assert(ident ~= nil)
  elseif begins(ident, 'g=') then
    local d1,d2,d3,d4,d5,d6,d7,d8,d9,d10,d11 =
      match(ident, "^g=(%x%x%x%x%x%x%x%x)-(%x%x%x%x)-(%x%x%x%x)-(%x%x)(%x%x)-(%x%x)(%x%x)(%x%x)(%x%x)(%x%x)(%x%x)$")
    assert(d1 and d2 and d3 and d4 and d5 and d6 and d7 and d8 and d9 and d10 and d11)
    ident = {
      data1=hexs(d1),
      data2=hexs(d2),
      data3=hexs(d3),
      data4=hexs(d4),
      data5=hexs(d5),
      data6=hexs(d6),
      data7=hexs(d7),
      data8=hexs(d8),
      data9=hexs(d9),
      data10=hexs(d10),
      data11=hexs(d11),
    }
  elseif begins(ident, 'b=') then
    local str = match(ident, "^b=([A-Za-z0-9+/=]+)$")
    str = b64decode(str)
    local data = {}
    for i = 1,#str do
      local b = sbyte(str, i)
      tins(data, b)
    end
    ident = data
  else
    error("invalid node id string format")
  end

  return {
    ns=ns,
    id=ident,
    srv=srv
  }
end

local function toString(i, ns, srv, nodeIdType)
  if type(i) == 'table' and i.id ~= nil then
    assert(ns == nil and srv == nil)
    ns = i.ns
    srv = i.srv
    i = i.id
  end

  if nodeIdType ~= nil then
    if nodeIdType == TwoByte or nodeIdType == FourByte or nodeIdType == Numeric then
      assert(i >= 0)
      i = fmt("i=%u", i)
    elseif nodeIdType == String then
      i = fmt("s=%s", i)
    elseif nodeIdType == Guid then
      i = fmt('g=%08x-%04x-%04x-%02x%02x-%02x%02x%02x%02x%02x%02x', i.data1, i.data2, i.data3, i.data4, i.data5, i.data6, i.data7, i.data8, i.data9, i.data10, i.data11)
    elseif nodeIdType == ByteString then
      i = fmt('b=%s', b64encode(i))
    end
  else
    if type(i) == "number" then
      assert(i >= 0)
      i = fmt("i=%u", i)
    elseif type(i) == "string" then
      i = fmt("s=%s", i)
    elseif type(i) == "table" then
      if i.data1 ~= nil then
        i = fmt('g=%08x-%04x-%04x-%02x%02x-%02x%02x%02x%02x%02x%02x', i.data1, i.data2, i.data3, i.data4, i.data5, i.data6, i.data7, i.data8, i.data9, i.data10, i.data11)
      else
        local data = {}
        for _, val in pairs(i) do
          local b = schar(val)
          tins(data, b)
        end
        local str = tconcat(data)

        i = fmt('b=%s', b64encode(str))
      end
    end
  end

  if ns ~= nil then
    if type(ns) == 'number' then
      assert(ns >= 0)
      if ns > 0 then
        i = fmt("ns=%u;%s", ns, i)
      end
    else
      assert(type(ns) == 'string')
      i = fmt("nsu=%s;%s", ns, i)
    end
  end

  if srv ~= nil then
    assert(type(srv) == 'number' and srv >=0)
    i = fmt("svr=%u;%s", srv, i)
  end
  return i
end

local function isNull(id)
  if id == nil then
    return true
  end

  if type(id) == 'string' then
    return id == 'i=0'
  end


  assert(type(id) == 'table')
  if id.ns ~= nil and id.ns ~= 0 then
    return false;
  end


  return id.id == nil or
         id.id == 0 or
         id.id == '' or
         id.id == {}
end


local function isValid(id)
  if type(id) == 'string' then
    local ns,ident = match(id, "ns=(%g+);(%g+)$")
    if ns == nil then
      ns,ident = match(id, "nsu=(%g+);(%g+)$")
    end

    if ns == nil then
      ident = id
    end

    if sfind(ident, "^(i=)%d+$") ~= nil then
      return true
    elseif sfind(ident, "^(s=)%g+$") ~= nil then
      return true
    elseif sfind(ident, "^g=%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$") ~= nil then
      return true
    elseif sfind(ident, "^b=([A-Za-z0-9+/=]+)$") ~= nil then
      return true
    end
  end
  return false
end

return {
  TwoByte = 0,
  FourByte = 1,
  Numeric = 2,
  String = 3,
  Guid = 4,
  ByteString = 5,

  NamespaceUriFlag = 0x80,
  ServerIndexFlag = 0x40,

  Null = "i=0",

  toString = toString,
  fromString = fromString,
  isNull = isNull,
  isValid = isValid
}
