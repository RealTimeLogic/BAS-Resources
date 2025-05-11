local ua = require("opcua.api")
local Q = require("opcua.binary.queue")

local fmt = string.format
local traceD = ua.trace.dbg
local traceI = ua.trace.inf

local ch ={}
ch.__index = ch

local function makeEmptyAdditionalHeader()
  return {
    TypeId = "i=0"
  }
end

function ch.createRequest(_, type, requestParams, request)
  if not request then
    request = {}
  end

  request.TypeId = type
  request.RequestId = requestParams.RequestId
  request.RequestHeader = {
      AuthenticationToken = requestParams.SessionAuthToken,
      Timestamp = requestParams.RequestCreatedAt,
      RequestHandle = requestParams.RequestHandle,
      ReturnDiagnostics = 0,
      AuditEntryId = nil,
      TimeoutHint = requestParams.RequestTimeout,
      AdditionalHeader = makeEmptyAdditionalHeader()
    }
  return request
end

function ch.createResponse(_, type, responseParams, response)
  if not response then
    response = {}
  end

  response.TypeId = type
  response.RequestId = responseParams.RequestId
  response.ResponseHeader = {
    Timestamp = responseParams.RequestCreatedAt,
    RequestHandle = responseParams.RequestHandle,
    ServiceResult = responseParams.ServiceResult,
    ServiceDiagnostics = {},
    StringTable = {},
    AdditionalHeader = makeEmptyAdditionalHeader()
  }

  return response
end

function ch:message(body)
  local dbgOn = self.logging.dbgOn
  local infOn = self.logging.infOn
  if infOn then traceD(fmt("json | encoding message")) end

  local msg = {
    TypeId = body.TypeId,
    Body = body
  }

  self.data:clear()
  self.Encoder:extensionObject(msg)

  if dbgOn then traceD(fmt("json | encoded data: %s", self.data.Buf)) end

  self.sock:send(self.data.Buf)

  if infOn then traceI(fmt("json | messageId '%s' sent", body.TypeId)) end
end

function ch.sequenceHeader()
end

function ch:setBufferSize(size)
  local infOn = self.logging.infOn
  if infOn then traceI(fmt("json | New buffer size '%d'",size)) end
  self.data = Q.new(size)
  self.Encoder = self.Model:createJsonEncoder(self.data)
end

function ch.setChannelId()
end

function ch.setTokenId()
end

function ch.setupPolicy()
end

function ch.setNonces()
end

function ch.setSecureMode()
end

local function new(config, _, sock, hasChunks, model)
  assert(config ~= nil, "no config")
  assert(sock ~= nil, "no socket")
  assert(model ~= nil, "no model")
  assert(hasChunks == false, "chunks not supported with JSON")

  local m = {}
  setmetatable(m, {__index=model})

  local res = {
    logging = config.logging.binary,

    -- Binary types encoder
    Model = m,

    -- Socket where to flush chunks
    sock = sock,
  }

  setmetatable(res, {__index=ch})

  res:setBufferSize(config.bufSize)

  return res
end

return {new=new}
