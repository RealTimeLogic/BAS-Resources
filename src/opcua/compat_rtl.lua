local function bind(host, port)
  return ba.socket.bind(port, host)
end

local function createSocket()
  local sockObj = {
    event = function(self, func, ...)
      return self.sock:event(func, ...)
    end,
    enable = function(self, ...)
      return self.sock:enable(...)
    end,
    disable = function(self)
      return self.sock:disable()
    end,
    accept = function(self)
      local sockObj = createSocket()
      sockObj.sock = self.sock:accept()
      return sockObj
    end,
    read = function(self, timeout, _--[[sz]])
      return self.sock:read(timeout)
    end,
    write = function(self, data)
      return self.sock:write(data)
    end,
    close = function(self)
      return self.sock:close()
    end,
    queuelen = function(self, len)
      return self.sock:queuelen(len)
    end
  }

  return sockObj
end

local function connect(address, port)
  local sockObj = createSocket()
  local err
  sockObj.sock, err = ba.socket.connect(address, port)
  return sockObj, err
end


local function getsock()
  local sock = ba.socket.getsock()
  if not sock then
    return
  end

  local sockObj = createSocket()
  local err
  sockObj.sock, err = ba.socket.getsock()
  return sockObj, err
end


local compat = {
  b64decode = ba.b64decode,
  b64encode = ba.b64encode,

  httpc = require("httpc"),

  socket = {
    getsock = getsock,
    bind = bind,
    connect = connect,
    event = ba.socket.event
  },

  to_timestamp = function(str)
    if type(str) == "number" then
      return str
    end

    local dt = ba.datetime(str or "NOW")
    local secs, ns = dt:ticks()
    local t = secs + ns / 1e9
    return t
  end,

  gettime = function(str)
    if type(str) == "number" then
      return str
    end
    local dt = ba.datetime(str or "NOW"):ticks()
    return dt
  end,

  to_datestring = function(ts)
    local secs = math.floor(ts)
    local ms = math.floor(ts*1e6)
    ms = math.floor(ms - secs * 1e6)
    local dt = os.date("!%Y-%m-%dT%H:%M:%S", secs)
    if ms == 0 then
      return dt .. "Z"
    else
      local digits = 6
      while ms % 10 == 0 do
        ms = math.tointeger(ms / 10)
        digits = digits - 1
      end

      ms = tostring(ms)
      digits = digits - #ms
      local zeroes = string.rep("0", digits)
      return string.format("%s.%s%sZ", dt, zeroes, ms)
    end
  end,

  clock = ba.clock,
  sleep = function(secs) ba.sleep(secs * 1000) end,
  bytearray = ba.bytearray,
  timer = ba.timer,
  thread = ba.thread,
  xparser = xparser,
  xml2table = require("xml2table"),
  parseJson = ba.json.decode,
  jsonNull = ba.json.null,
}

return compat
