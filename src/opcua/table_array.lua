local function LBA_rangeError(msg)
  error(msg or "ByteArray range")
end

local lba = {}

function lba:__index(idx)
  if type(idx) == 'number' then
    if idx < 1 or idx > self.len then LBA_rangeError() end
    return self.array[self.sIx + idx]
  end

  return lba[idx]
end

function lba:__newindex(idx, data)
  assert(type(idx) == 'number')
--  print(string.format("idx=%d data=%s self.len=%d", idx, data, self.len))
  if idx < 1 or idx > self.len then LBA_rangeError() end

  local tp = type(data)
  if tp == 'number' then
    if data < 0 or data >= 256 then
      LBA_rangeError()
    end
    self.array[self.sIx + idx] = data
  elseif tp == 'table' then
    local s
    local e
    if data.__bta == '__bta' then
      if data.len > (self.len - (idx - 1)) then
        LBA_rangeError("ByteArray: range bytearray")
      end

      s = data.sIx
      e = s + data.len
      data = data.array
    else
      s = 0
      e = #data
    end
    for i = s+1,e do
      local v = data[i]
      if idx > self.len or type(v) ~= 'number' or v < 0 or v >= 256 then
        LBA_rangeError()
      end

      self.array[self.sIx + idx] = v
      idx = idx + 1
    end
  elseif tp == 'string' then
    idx = idx - 1
    if (idx + #data) > self.len then
      LBA_rangeError()
    end

    idx = self.sIx + idx
    for i = 1,#data do
      local v = string.byte(data, i)
      if v < 0 or v >= 256 then
        LBA_rangeError()
      end

      self.array[idx + i] = v
    end
  else
    LBA_rangeError(string.format("Cannot convert %s to ByteArray", tp))
  end
end

function lba:__len()
  return self.len
end

local function lbatostring(self, s,e)
  s = s or 1
  e = e or -1

  if s < 0 then s = self.len + s + 1 end
  if e < 0 then e = self.len + e + 1 end

  s = s - 1
  local l = e - s
  if l < 0 then l = 0 end

  if s < 0 or s + l > self.len then
    LBA_rangeError()
  end

  local d = self.array
  local res = {}
  local schar = string.char
  local tins = table.insert
  for i = 1, l do
    local b = schar(d[self.sIx + s + i])
    tins(res, b)
  end

  return table.concat(res)
end


function lba:__tostring()
  local d = self.array
  local res = {}
  local schar = string.char
  local tins = table.insert
  for i = 1, self.len do
    local b = schar(d[self.sIx + i])
    tins(res, b)
  end

  return table.concat(res)
end


local function create(size)
  local arr = {}
  for i = 1,size do
    arr[i] = 0
  end

  local bt = {
    __bta = '__bta',
    array = arr,
    size = size,
    sIx = 0,
    len = size
  }
  setmetatable(bt, lba)
  return bt
end

function lba:get_size()
  return self.size, self.sIx + 1, self.sIx + self.len
end

function lba:set_size(s,e)
  s = s or 1
  e = e or -1

  if s < 0 then s = self.size + s + 1 end
  if e < 0 then e = self.size + e + 1 end

  s = s -1
  local l = e - s;

  if s < 0 or l < 0 or (s + l) > self.size then
    LBA_rangeError()
  end

  self.sIx = s
  self.len = l
end


return {
  create = create,
  tostring = lbatostring,
  size = lba.get_size,
  setsize = lba.set_size
}
