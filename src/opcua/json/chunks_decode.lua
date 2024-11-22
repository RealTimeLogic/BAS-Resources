local Q = require("opcua.binary.queue")
local ua = require("opcua.api")

local traceI = ua.trace.inf
local traceD = ua.trace.dbg
local fmt = string.format

local ch = {}
ch.__index = ch

function ch:setBufferSize(size)
  local infOn = self.logging.infOn
  if infOn then traceI(fmt("json | New buffer size %d", size)) end
  self.data = Q.new(size)
  self.JsonDecoder = self.Model.createJsonDecoder(self.data)
end

function ch:message()
  local dbgOn = self.logging.dbgOn
  local infOn = self.logging.infOn
  if self.sock.json then
    if infOn then traceI(fmt("json | receiving json")) end
    local json = self.sock:json()
    if dbgOn then ua.Tools.printTable("json | received JSON table", json, traceD) end
    self.JsonDecoder.Deserializer.stack = {json}
  else
    if infOn then traceI(fmt("json | receiving string")) end
    local str = self.sock:receive()
    if dbgOn then traceD(fmt("json | received string: %s", str)) end
    self.data:clear()
    self.data:pushBack(str)
  end
  if infOn then traceI("json | decoding message") end
  local msg = self.JsonDecoder:extensionObject()
  if infOn then traceI("json | message decoded") end
  if dbgOn then ua.Tools.printTable("json | message data:", msg, traceD) end
  return msg
end

function ch.setNonces()
end

function ch.setSecureMode()
end

function ch.setupPolicy()
end

local function new(config, security, sock, hasChunks, model)
  assert(config ~= nil, "no config")
  assert(sock ~= nil, "no socket")
  assert(security ~= nil, "no security")
  assert(type(hasChunks) == "boolean", "hasChunks must be boolean")
  assert(model ~= nil, "no model")

  local data = Q.new(config.bufSize)

  local res = {
    config = config,
    logging = config.logging.binary,

    sock = sock,
    -- buffer for Chunk.
    data = data,
    Model = model,
    JsonDecoder = model:createJsonDecoder(data)
  }

  setmetatable(res, ch)
  return res
end

return {new=new}
