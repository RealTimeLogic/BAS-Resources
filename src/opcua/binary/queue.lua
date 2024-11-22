--
-- autor Alexander Rykovanov
-- email rykovanov.as@gmail.com
--


-- A double sided queue
--
-- Global functions:
--   new(size)
--     size - size of the allocated buffer.
--              Don't change
-- Members:
--   Buf - Preallocated buffer
--   Start - Position of first element
--   Size - Number alive in queue and available for popping.
--
-- Methods
--   pushBack(data) append data to the end
--   pushFront(data) append data to the end
--      parameters:
--         data - array of data to apppend
--      returns:
--         Good if ok
--         BadOutOfMemory if overflows. No data appended.
--
--   popFront(len, tgt) extract data from begining
--   popBack(data) extract data from end
--      parameters:
--         len - number of elements to remove
--         tgt - target array where to copy data
--      returns:
--         Good if ok
--         BadNoData if underflows. Internal state not changed.
--
--   __tostring - concat available elements to string
--
-- Usage
-- > Queue = require("opcua.binary.queue")
-- > q = Queue.new(8)
-- > local err = Good
-- > err = q.pushBack({1,2,3})
-- > if err ~= Good then
-- >   print("pushBack error")
-- >   return
-- > end
-- > suc, code = pcall(q.pushFront, q, {4,5,6})
-- > if not suc then
-- >   print("pushBack error:"..code)
-- >   return
-- > end
-- > str = tostring(q)


local compat = require("opcua.compat")
local st = require ("opcua.status_codes")
local BadOutOfMemory = st.BadOutOfMemory
local BadNoData = st.BadNoData

local lbacreate = compat.bytearray.create
local lbasetsize = compat.bytearray.setsize
local lbasize = compat.bytearray.size

local function qpairs(t)
  local function stateless_iter(tbl, k)
    local buf = tbl.Buf
    if k >= #buf then
      return
    end

    return k + 1,buf[k + 1]
  end

  return stateless_iter, t, 0
end

local Q = {
  -- push data to end of buffer
  -- data - table-array with elements

  pushBack = function(self, data)
    local cap, s, e = lbasize(self.Buf)
    local ix = #self.Buf
    if type(data) == "number" then
      if e + 1 > cap then
        error(BadOutOfMemory)
      end
      lbasetsize(self.Buf, s, e + 1)
      self.Buf[ix + 1] = data
      return
    elseif type(data) == "string" then
      if data == "" then
        return
      end
      local l =  #data
      if (e + l) > cap then
        error(BadOutOfMemory)
      end
      lbasetsize(self.Buf, s, e + l)
      self.Buf[ix + 1] = data
      return
    end

    local l =  #data
    if (e + l) > cap then
      error(BadOutOfMemory)
    end

    lbasetsize(self.Buf, s, e + l)
    for i = 1,#data do
      self.Buf[ix + i] = data[i]
    end
  end,

  -- push data to end of buffer
  -- data - table-array with elements
  pushFront = function(self, data)
    local len = type(data) == 'number' and 1 or #data
    local buf = self.Buf
    local _, sIx, eIx = lbasize(buf)
    if len > sIx then
      error(BadOutOfMemory)
    end

    sIx = sIx - len
    lbasetsize(self.Buf, sIx, eIx)
    self.Buf[1] = data
  end,

  popFront=function(self, len, tgt)
    local buf = self.Buf
    local _, sIx, eIx = lbasize(buf)
    sIx = sIx - 1
    if len > (eIx - sIx) then
      error(BadNoData)
    end

    if tgt ~= nil then
      for i=1,len do
        tgt[i] = buf[i]
      end
    end

    lbasetsize(buf, sIx + 1 + len, eIx)
  end,

  popBack=function(self, len, tgt)
    local buf = self.Buf
    local sz = #buf
    if len > sz then
      error(BadNoData)
    end

    local si = sz - len
    for i=1,len do
      tgt[i] = buf[si + i]
    end
    local _,s,e = lbasize(buf)
    lbasetsize(buf, s, e - len)
  end,

  clear=function(self, zero)
    zero = zero or 1
    lbasetsize(self.Buf, zero, zero - 1)
    self.Zero = zero
  end,

  capacity = function(self)
    return #self.Buf
  end,

  tailCapacity = function(self)
    local size, _, e = lbasize(self.Buf)
    return size - e
  end,

  headerCapacity = function(self)
    local _, s, _ = lbasize(self.Buf)
    return s
  end,

  __tostring = function(self)
    return tostring(self.Buf)
  end,

  __len = function(self)
    return #self.Buf
  end,

  __ipairs = qpairs,
  __pairs = qpairs,
  __newindex = function(self, k, v)
    if k < 1 or k > #self.Buf then
      error("Out of bounds")
    end

    self.Buf[k] = v
  end
}

Q.__index = function(t, k)
  if type(k) == "number" then
    if k < 1 or k > #t.Buf then
      return
    end
    return t.Buf[k]
  end

  return Q[k]
end


return {
  new = function (tailSize, hdrSize)

    local buf
    if type(tailSize) == "userdata" then
      buf = tailSize
      hdrSize = 0
    else
      hdrSize = hdrSize or 0
      buf = lbacreate(hdrSize + tailSize)
      lbasetsize(buf, hdrSize + 1, hdrSize)
    end

    local res = {
      Zero = hdrSize + 1,
      Buf = buf
    }

    setmetatable(res, Q)
    return res
  end
}
