local ua = require("opcua.api")
local Q = require("opcua.binary.queue")
local Binary = require("opcua.binary.encode_types")
local s = require("opcua.status_codes")
local MessageId = require("opcua.binary.message_id")

local tools = ua.Tools
local fmt = string.format
local traceD = ua.trace.dbg
local traceI = ua.trace.inf
local traceE = ua.trace.err

local ch ={}
ch.__index = ch

local HeaderSize = 8
local SecureHeaderSize = 12

local BadInternalError = s.BadInternalError
local BadSecureChannelIdInvalid = s.BadSecureChannelIdInvalid
local BadTcpMessageTypeInvalid = 0x807E0000
local BadNotSupported = 0x803D0000

local function makeEmptyAdditionalHeader()
  local hdr = {}
  hdr.binaryBody = 0
  hdr.xmlBody = 0
  hdr.typeId = {id=0}
  return hdr
end


function ch:hello(hello)
  local infOn = self.logging.infOn

  if infOn then traceI(fmt("binary | sending hello")) end

  self:begin("HEL")
  self.encoder:hello(hello)
  self:finish()

  if infOn then traceI(fmt("binary | hello sent")) end
end

function ch:acknowledge(ack)
  local infOn = self.logging.infOn
  if infOn then traceI(fmt("binary | sending acknowledge")) end

  self:begin("ACK")
  self.encoder:acknowledge(ack)
  self:finish()

  if infOn then traceI(fmt("binary | acknowledge sent")) end
end

function ch.createRequest(_,type, requestParams, request)
  if not request then
    request = {}
  end

  request.type = type
  request.requestId = requestParams.requestId
  request.requestHeader = {
      authenticationToken = requestParams.sessionAuthToken,
      timestamp = requestParams.requestCreatedAt,
      requestHandle = requestParams.requestHandle,
      returnDiagnostics = 0,
      auditEntryId = nil,
      timeoutHint = requestParams.requestTimeout,
      additionalHeader = makeEmptyAdditionalHeader()
    }
  return request
end

function ch.createResponse(_, type, responseParams, response)
  if not response then
    response = {}
  end

  response.type = type
  response.requestId = responseParams.requestId
  response.responseHeader = {
    timestamp = responseParams.requestCreatedAt,
    requestHandle = responseParams.requestHandle,
    serviceResult = responseParams.serviceResult,
    serviceDiagnostics = {},
    stringTable = {},
    additionalHeader = makeEmptyAdditionalHeader()
  }

  return response
end

local enc = {
[MessageId.SERVICE_FAULT] = Binary.Encoder.serviceFault,
[MessageId.OPEN_SECURE_CHANNEL_REQUEST] = Binary.Encoder.openSecureChannelRequest,
[MessageId.OPEN_SECURE_CHANNEL_RESPONSE] = Binary.Encoder.openSecureChannelResponse,
[MessageId.CLOSE_SECURE_CHANNEL_REQUEST] = Binary.Encoder.closeSecureChannelRequest,
[MessageId.FIND_SERVERS_REQUEST] = Binary.Encoder.findServersRequest,
[MessageId.FIND_SERVERS_RESPONSE] = Binary.Encoder.findServersResponse,
[MessageId.GET_ENDPOINTS_REQUEST] = Binary.Encoder.getEndpointsRequest,
[MessageId.GET_ENDPOINTS_RESPONSE] = Binary.Encoder.getEndpointsResponse,
[MessageId.CREATE_SESSION_REQUEST] = Binary.Encoder.createSessionRequest,
[MessageId.CREATE_SESSION_RESPONSE] = Binary.Encoder.createSessionResponse,
[MessageId.ACTIVATE_SESSION_REQUEST] = Binary.Encoder.activateSessionRequest,
[MessageId.ACTIVATE_SESSION_RESPONSE] = Binary.Encoder.activateSessionResponse,
[MessageId.CLOSE_SESSION_REQUEST] = Binary.Encoder.closeSessionRequest,
[MessageId.CLOSE_SESSION_RESPONSE] = Binary.Encoder.closeSessionResponse,
[MessageId.CREATE_SUBSCRIPTION_REQUEST] = Binary.Encoder.createSubscriptionRequest,
[MessageId.CREATE_SUBSCRIPTION_RESPONSE] = Binary.Encoder.createSubscriptionResponse,
[MessageId.TRANSLATE_BROWSE_PATHS_TO_NODE_IdS_REQUEST] = Binary.Encoder.translateBrowsePathsToNodeIdsRequest,
[MessageId.TRANSLATE_BROWSE_PATHS_TO_NODE_IdS_RESPONSE] = Binary.Encoder.translateBrowsePathsToNodeIdsResponse,
[MessageId.BROWSE_REQUEST] = Binary.Encoder.browseRequest,
[MessageId.BROWSE_RESPONSE] = Binary.Encoder.browseResponse,
[MessageId.READ_REQUEST] = Binary.Encoder.readRequest,
[MessageId.READ_RESPONSE] = Binary.Encoder.readResponse,
[MessageId.WRITE_REQUEST] = Binary.Encoder.writeRequest,
[MessageId.WRITE_RESPONSE] = Binary.Encoder.writeResponse,
[MessageId.ADD_NODES_REQUEST] = Binary.Encoder.addNodesRequest,
[MessageId.ADD_NODES_RESPONSE] = Binary.Encoder.addNodesResponse,
}

function ch:message(body)
  local dbgOn = self.logging.dbgOn
  local infOn = self.logging.infOn
  local errOn = self.logging.errOn
  local type = body.type
  if infOn then traceI(fmt("binary | sending message '%s'", type)) end

  local f = enc[type]
  if not f then
    if errOn then traceE(fmt("binary | encoding of type '%s' not supported", type)) end
    error(BadNotSupported)
  end

  if self.channelId == nil then
    if errOn then traceE(fmt("binary | channel Id for message not set", type)) end
    error(BadTcpMessageTypeInvalid)
  end

  if  type == MessageId.OPEN_SECURE_CHANNEL_REQUEST or type == MessageId.OPEN_SECURE_CHANNEL_RESPONSE then
    self:begin("OPN", body.requestId)
  elseif type == MessageId.CLOSE_SECURE_CHANNEL_REQUEST then
    self:begin("CLO", body.requestId)
  else
    self:begin("MSG", body.requestId)
  end
  if dbgOn then traceD(fmt("binary | encoding message")) end
  self.encoder:nodeId(type)
  f(self.encoder, body)
  self:finish()
  if infOn then traceI(fmt("binary | message '%s' sent", type)) end
end

function ch:begin(messageType, requestId)
  assert(requestId == nil or type(requestId) == 'number')
  assert(type(messageType) == 'string')

  if messageType == "MSG" or messageType == "CLO" then
    self.headerSize = SecureHeaderSize + 4 + 8 -- symmetricHeader + sequenceHeader
  elseif messageType == "OPN" then
    local sz = SecureHeaderSize + 4 + #self.policy.uri
    sz = sz + 4 -- certificateLen
    sz = sz + 4 -- remoteThumbprintLen

    sz = sz + self.policy:geLocalCertLen()
    sz = sz + self.policy:getRemoteThumbLen()
    self.headerSize = sz + 8 -- sequenceHeader
  else
    self.headerSize = HeaderSize
  end

  self.messageType = messageType
  self.requestId = requestId
  self.data:clear(self.headerSize + 1)
end

-- Queue interface through which fills up message body
function ch:pushBack(data)
  local tailSize = self.policy and self.policy:tailSize() or 0
  if self.data:tailCapacity() - tailSize <= 0 then
    self:send_chunk("C")
  end

  if type(data) == 'number' then
    self.data:pushBack(data)
  else
    local pos = 1
    local dsize = #data
    while pos <= dsize do
      if pos ~= 1 then
        self:send_chunk("C")
      end

      local tailCap = self.data:tailCapacity() - tailSize
      local leftSize = dsize - (pos - 1)
      if leftSize > tailCap then
        leftSize = tailCap
      end

      for i = 0,(leftSize-1) do
        self.data:pushBack(data[pos+i])
      end

      pos = pos + leftSize
    end
  end
end

function ch:finish()
  self:send_chunk("F")
end

-- function ch:abort()
--   self.data:clear()
--   self:send_chunk("A")
-- end

function ch:send_chunk(chunkType)
  local dbgOn = self.logging.dbgOn
  local errOn = self.logging.errOn
  if dbgOn then traceD(fmt("binary | sending chunk '%s'", chunkType)) end
  if #self.data == 0 then
    if errOn then traceE("binary | Internal error: No data to send") end
    error(BadInternalError)
  end

  if chunkType == "C" and self.messageType ~= "MSG" then
    if errOn then traceE(fmt("binary | %s Internal error: Message type '%s' can't be chunked.",self.channelId, self.messageType)) end
    self.data:clear()
    error(BadInternalError)
  end

  local policy = self.policy
  local headerQ = Q.new(self.headerSize) -- +sequenceHeader
  local header = Binary.Encoder.new(headerQ)
  if self.messageType == "MSG" or self.messageType == "CLO" then
    if self.channelId == nil then error(BadSecureChannelIdInvalid) end
    if self.secureHeader == nil then error(BadSecureChannelIdInvalid) end
    assert(self.requestId ~= 0 and self.requestId ~= nil)
    header:symmetricSecurityHeader(self.secureHeader)
    self:sequenceHeader(header)
    self.data:pushFront(headerQ.Buf)
  elseif self.messageType == "OPN" then
    assert(self.requestId ~= 0 and self.requestId ~= nil)
    assert(policy)
    if policy.uri ~= ua.Types.SecurityPolicy.None then
      header:asymmetricSecurityHeader(policy.uri, policy:getLocalCert(), policy:getRemoteThumbprint())
    else
      header:asymmetricSecurityHeader(policy.uri)
    end
    self:sequenceHeader(header)
    self.data:pushFront(headerQ.Buf)
  end

  headerQ:clear()
  if self.messageType == "MSG" or self.messageType == "OPN" or self.messageType == "CLO" then
    local msgSize
    if self.messageType == "OPN" then
      msgSize = policy:aMessageSize(SecureHeaderSize + #self.data, self.headerSize - 8)
    else
      msgSize = policy:sMessageSize(SecureHeaderSize + #self.data, self.headerSize - 8)
    end
    header:secureMessageHeader(self.messageType, chunkType, msgSize, self.channelId)
  else
    header:messageHeader(self.messageType, chunkType, HeaderSize + #self.data)
  end

  self.data:pushFront(headerQ.Buf)
  if self.messageType == "OPN" then
    policy:asymmetricEncrypt(self.data.Buf, self.headerSize - 8)
  elseif self.messageType == "MSG" or self.messageType == "CLO" then
    policy:symmetricEncrypt(self.data.Buf, self.headerSize - 8)
  end

  if self.logging.dbgOn  then
    traceD(fmt("binary | ------------ SENDING MESSAGE DATA %d BYTES ----------------", #self.data.Buf))
    tools.hexPrint(self.data.Buf, function(msg) traceD("binary | "..msg) end)
    traceD("binary | ---------------------------------------------------------")
  end

  self.sock:send(self.data.Buf)
  self.data:clear(self.headerSize + 1) -- prepare for next chunk
  if dbgOn then traceD(fmt("binary | Chunk '%s' sent sucessfully", chunkType)) end
end

function ch:sequenceHeader(en)
  self.sequenceNumber = self.sequenceNumber + 1
  local sequenceHeader = {
    sequenceNumber = self.sequenceNumber,
    requestId = self.requestId
  }
  en:sequenceHeader(sequenceHeader)
end

function ch:setBuferSize(size)
  local infOn = self.logging.infOn
  if infOn then traceI(fmt("binary | New buffer size '%d'",size)) end
  local old = self.data
  self.data = Q.new(size)
  self.data = old
  self.encoder = Binary.Encoder.new(self)
end

function ch:setChannelId(channelId)
  local infOn = self.logging.infOn
  if infOn then traceI(fmt("binary | New channelId '%s'", channelId)) end
  self.channelId = channelId
end

function ch:setTokenId(tokenId)
  local infOn = self.logging.infOn
  if infOn then traceI(fmt("binary | New token '%s'", tokenId)) end
  self.secureHeader = {tokenId = tokenId}
end

function ch:setupPolicy(uri, remoteCert)
  local policy = self.security(uri)
  policy:setRemoteCertificate(remoteCert)
  self.policy = policy
end

function ch:setNonces(localNonce, remoteNonce)
  self.policy:setNonces(localNonce, remoteNonce)
end

function ch:setSecureMode(secureMode)
  self.policy:setSecureMode(secureMode)
end

local function new(config, security, sock)
  assert(config ~= nil, "no config")
  assert(security ~= nil, "no security")
  assert(sock ~= nil, "no socket")

  local dataQ = Q.new(config.bufSize)
  local res = {
    security = security,
    logging = config.logging.binary,

    requestId = 0,
    sequenceNumber = 0,
    channelId = 0,

    headerSize = 0,

    -- buffer for Chunk.
    data = dataQ,
    -- Binary types encoder
    encoder = Binary.Encoder.new(dataQ),

    -- Socket where to flush chunks
    sock = sock
  }

  res.encoder = Binary.Encoder.new(res)

  setmetatable(res, ch)

  return res
end

return {new=new}
