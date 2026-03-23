local openssl = require("openssl")
local socket = require("socket")
local bytearray = require("opcua.table_array")
local lxp = require("lxp")

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


local xml2table = {
  START_ELEMENT = function(context, tagname, attribs)
    local node = { type = "element", tag_name = tagname, attributes = attribs or {} }
    local parent = context.stack[#context.stack]
    
    if parent then
      if not parent.elements then parent.elements = {} end
      table.insert(parent.elements, node)
      parent.elements[tagname] = parent.elements[tagname] or node
      parent[#parent + 1] = node
    else
      table.insert(context.doc, node)
      if not context.doc.elements then context.doc.elements = {} end
      table.insert(context.doc.elements, node)
      context.doc.elements[tagname] = context.doc.elements[tagname] or node
    end
    table.insert(context.stack, node)
  end,

  END_ELEMENT = function(context, tagname)
    local node = context.stack[#context.stack]
    if node and node.text then
      node.text = table.concat(node.text, " ")
    end
    table.remove(context.stack)
    if #context.stack == 0 then
      context.status = "DONE"
    end
  end,

  TEXT = function(context, text)
    if #text == 0 then return end
    local node = context.stack[#context.stack]
    if not node then return end
    if not node.text then node.text = {} end
    table.insert(node.text, text)
  end
}

local xparser = {
  create = function(handler)
    local context = { doc = {}, stack = {} }
    local lHandler = {
      StartElement = function(parser, elementName, attributes)
        if handler.START_ELEMENT then
          return handler.START_ELEMENT(context, elementName, attributes)
        end
      end,
      EndElement = function(parser, tagname)
        if handler.END_ELEMENT then
          return handler.END_ELEMENT(context, tagname)
        end
      end,
      CharacterData = function(parser, data)
        if handler.TEXT then
          return handler.TEXT(context, data)
        end
      end
    }

    local impl = lxp.new(lHandler)
    local parser = {
      parse = function(self, data)
        local ok, msg, line, col, pos
        if data then
          ok, msg, line, col, pos = impl:parse(data)
        else
          ok, msg, line, col, pos = impl:parse()
          impl:close()
        end
        
        if not ok then
          return true, msg, line, col, pos
        end
        
        -- In export tests the parser is called exactly once with the full string, 
        -- so we must send EOF to finish parsing if handler == xml2table and we aren't chunking
        if data and handler == xml2table then
          impl:parse()
          impl:close()
        end
        
        if handler == xml2table then
           return context.status, context.doc, nil
        end
        return nil
      end,
    }

    return parser
  end
}

local function to_timestamp(str)
  local y, m, d, h, min, s, ms, tz_sign, tz_h, tz_m = string.gmatch(str, "(%d+)%-(%d+)%-(%d+)T(%d+):(%d+):(%d+)%.?(%d*)([Z%+%-]?)(%d*):?(%d*)")()
  if not y then
    error("invalid datetime")
  end

  local dt = {
    year = tonumber(y),
    month = tonumber(m),
    day = tonumber(d),
    hour = tonumber(h),
    min = tonumber(min),
    sec = tonumber(s),
  }
  tz_h = tonumber(tz_h)
  tz_m = tonumber(tz_m)

  if #ms > 0 then 
    ms = tonumber("0."..ms)
  else
    ms = 0
  end

  local tOff = os.time({
    year = 1970,
    month = 1,
    day = 1,
    hour = 0,
    min = 0,
    sec = 0,
  })

  local t = os.time(dt) - tOff
  if tz_sign == '+' or tz_sign == '-' then
    t = t + (tz_h * 3600 + tz_m * 60)
  end
  t = t + ms
  return t
end

local function to_datestring(ts)
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
end

local function gettime()
  return socket.gettime()
end

local json = require("cjson")
local jsonNull = json.null

local function parseJson(str)
  local obj = json.decode(str)
  if obj == jsonNull then
    return nil
  end
  return obj
end

local compat = {
  b64decode = b64decode,
  b64encode = b64encode,

  socket = {
    getsock = getsock,
    bind = bind,
    connect = connect,
  },

  xml2table = xml2table,
  to_datestring = to_datestring,
  to_timestamp = to_timestamp,
  gettime = gettime,
  clock = clock,
  sleep = sleep,
  bytearray = bytearray,
  timer = timer,
  xparser = xparser,
  parseJson = parseJson,
  jsonNull = jsonNull,
}

return compat
