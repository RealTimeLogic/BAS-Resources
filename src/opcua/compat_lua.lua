local openssl = require("openssl")
local socket = require("socket")
local bytearray = require("opcua.table_array")

local function createSocket()
  local sockObj = {
    event = function(self, func)
      return func(self)
    end,
    accept = function(self)
      local sockObj = createSocket()
      sockObj.sock = self.sock:accept()
      return sockObj
    end,
    read = function(self, timeout, sz)
      if timeout then
        self.sock:settimeout(timeout / 1000)
      end
      return self.sock:receive(sz)
    end,
    write = function(self, data)
      if type(data) ~= "string" then
        data = tostring(data)
      end
      local sent = 0
      while sent < #data do
        local sz, err = self.sock:send(data, sent)
        if err then
          return false, err
        end
        sent = sent + sz
      end
      return true
    end,
    close = function(self)
      return self.sock:close()
    end,
    queuelen = function()
    end
  }
  return sockObj
end

local function clock()
  return os.time() * 1000
end

local function sleep(secs)
  return socket.sleep(secs)
end

local function bind(address, port)
  local sockObj = createSocket()
  sockObj.sock = socket.bind(address, port)
  return sockObj
end

local function gettime()
  return socket.gettime()
end

local function connect(address, port)
  local sockObj = createSocket()
  local err
  sockObj.sock, err = socket.connect(address, port)
  return sockObj, err
end

local function getsock()
end

local timerClass = {
  set = function()
  end,

  reset = function()
  end,

  cancel = function()
  end
}

local function timer()
  return timerClass
end

local function b64decode(str)
  str = string.gsub(str, "[%c%s]", "") -- remove line breaks
  local b64 = openssl.base64(str, false, true)
  return b64
end

local function b64encode(str)
  return openssl.base64(str, true)
end

local compat = {
  b64decode = b64decode,
  b64encode = b64encode,

  socket = {
    getsock = getsock,
    bind = bind,
    connect = connect,
  },

  gettime = gettime,
  clock = clock,
  sleep = sleep,
  bytearray = bytearray,
  timer = timer,
}

return compat
