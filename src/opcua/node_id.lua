local fmt = string.format
local sub = string.sub
local match = string.match
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

local function isGuid(v)
  return match(v, "^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$")
end
local function isIdGuid(v)
  return match(v, "^g=%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$")
end

local compat = require("opcua.compat")

local b64decode = compat.b64decode
local b64encode = compat.b64encode

local function fromString(s)
  assert(type(s) == 'string')
  local ns = 0
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

  local t
  if begins(ident, "i=") then
    ident = match(ident, "^i=(%d+)$")
    assert(ident ~= nil)
    ident = tonumber(ident)
    t = Numeric
  elseif begins(ident, "s=") then
    ident = string.match(ident, "^s=(%g+)$")
    assert(ident ~= nil)
    t = String
  elseif begins(ident, 'g=') then
    ident = ident:sub(3)
    assert(isGuid(ident))
    t = Guid
  elseif begins(ident, 'b=') then
    local str = match(ident, "^b=([A-Za-z0-9+/=]+)$")
    ident = b64decode(str)
    t = ByteString
  else
    error("invalid node id string format")
  end

  return {
    type=t,
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
    nodeIdType = i.type
    i = i.id
  end

  if nodeIdType ~= nil then
    if nodeIdType == TwoByte or nodeIdType == FourByte or nodeIdType == Numeric then
      assert(i >= 0)
      i = fmt("i=%u", i)
    elseif nodeIdType == String then
      i = fmt("s=%s", i)
    elseif nodeIdType == Guid then
      assert(isGuid(i))
      i = fmt('g=%s', i)
    elseif nodeIdType == ByteString then
      if type(i) == "table" then
        local data = {}
        for _, val in pairs(i) do
          local b = schar(val)
          tins(data, b)
        end
        local str = tconcat(data)
        i = fmt('b=%s', b64encode(str))
      else
        i = fmt('b=%s', b64encode(i))
      end
    end
  else
    if type(i) == "number" then
      assert(i >= 0)
      i = fmt("i=%u", i)
    elseif type(i) == "string" and isGuid(i) then
      i = fmt('g=%s', i)
    elseif type(i) == "string" then
      i = fmt("s=%s", i)
    elseif type(i) == "table" then
      local data = {}
      for _, val in pairs(i) do
        local b = schar(val)
        tins(data, b)
      end
      local str = tconcat(data)
      i = fmt('b=%s', b64encode(str))
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
    elseif isIdGuid(ident) then
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
