local JsonDecoder = require("opcua.json.decoder")
local Q = require("opcua.binary.queue")
local ua = require("opcua.api")

local traceI = ua.trace.inf
local fmt = string.format

local ch = {}
ch.__index = ch

function ch:setBufferSize(size)
  local infOn = self.logging.infOn
  if infOn then traceI(fmt("json | New buffer size %d", size)) end
  self.data = Q.new(size)
  self.JsonDecoder = JsonDecoder.new(self.data)
  self.m.Deserializer = self.JsonDecoder
end

function ch:message()
  local infOn = self.logging.infOn
  if infOn then traceI("json | Receiving message") end

  local str = self.sock:receive()
  self.data:clear()
  self.data:pushBack(str)
  local msg = self.Model:DecodeExtensionObject()
  if infOn then traceI("json | Message decoded") end
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
  local m = {
    Deserializer = JsonDecoder.new(data)
  }
  setmetatable(m, {__index=model})

  local res = {
    config = config,
    logging = config.logging.binary,

    sock = sock,
    -- buffer for Chunk.
    data = data,
    Model = m,
    JsonDecoder = m.Deserializer,
  }

  setmetatable(res, ch)
  return res
end

return {new=new}
