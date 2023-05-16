local s = require "opcua.status_codes"
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
  if type(v) == 'number' then
    self:uint8(v ~= 0 and 1 or 0)
  elseif type(v) == 'boolean' then
    self:uint8(v and 1 or 0)
  else
    error("invalid boolean type")
  end
end


enc.char = enc.uint8
enc.byte = enc.uint8
enc.sbyte = enc.int8
enc.statusCode = enc.uint32

function enc:array(val)
  if type(val) ~= "string" and type(val) ~= "table" then
    error(BadEncodingError)
  end

  self.data:pushBack(val)
end

enc.str = enc.array
enc.tbl = enc.array


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
  self:tbl(res)
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
