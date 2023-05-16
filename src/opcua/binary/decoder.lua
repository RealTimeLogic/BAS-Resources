-- local tools = require("opcua.binary.tools")
local s = require("opcua.status_codes")
local math = require("math")

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
  value = value ~= 0 and 1 or 0
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

function dec:str(size)
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

  local data = ba.bytearray.create(size)
  for i = 1,size do
    data[i] = self:uint8()
  end
  return tostring(data)
end

dec.sbyte = dec.int8
dec.byte = dec.uint8
dec.char = dec.uint8
dec.statusCode = dec.uint32

function dec.new(encoded_data)
    local res = {
    data = encoded_data,
    bitNum = 0,
  }

  setmetatable(res, dec)
  return res
end

return dec
