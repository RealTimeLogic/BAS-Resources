local socket = require("socket")

local encoder = require("opcua.binary.chunks_encode")
local decoder = require("opcua.binary.chunks_decode")
local securePolicy = require("opcua.binary.crypto.policy")
local Msg = require("opcua.binary.message_id")
local ua = require("opcua.api")

local s = ua.StatusCode
local trace = ua.trace
local fmt = string.format
local traceD = ua.trace.dbg
local traceE = ua.trace.err
local traceI = ua.trace.inf


local S = {}
S.__index = S

local tokenNum = 1
local function genNextToken()
  tokenNum = tokenNum + 1
  return tokenNum
end

local channelsNum = os.time()

local State = {
  New = 0,    -- just accepted connection.
  Hello = 1,  -- client received acknowledge on hello message.
  Open = 2,   -- client opened secure channel and can send messages.
  Closed = 4, -- client caused error and connection was closed.
}

function S:processData()
  local dbgOn = self.trace.dbgOn
  local errOn = self.trace.errOn

  if self.state == State.New then
    if dbgOn then traceD(fmt("%s Processing HEL", self.logId)) end
    self:processHello()
  elseif self.state == State.Hello then
    self:processOpenSecureChannel()
  elseif self.state == State.Open then
    self:processMessage()
  elseif self.state == State.Closed then
    error(s.BadSecureChannelClosed)
  else
    if errOn then traceE(fmt("%s Unknown message", self.logId)) end
    error(s.BadTcpMessageTypeInvalid)
  end

  if dbgOn then traceD(fmt("%s data processed", self.logId)) end
end

function S:processHello()
  local dbgOn = self.trace.dbgOn
  local infOn = self.trace.infOn

  if dbgOn then traceD(fmt("%s decoding hello message", self.logId)) end
  local hello = self.decoder:hello()
  if infOn then traceI(fmt("%s Received Hello: EndpointUrl='%s' SendBufferSize=%d, ReceiveBufferSize=%d", self.logId, hello.endpointUrl, hello.sendBufferSize, hello.receiveBufferSize)) end

  -- Endpoint URLs are used in proxy servers
  if hello.endpointUrl ~= nil and self.services.hello ~= nil then
    if dbgOn then traceD(fmt("%s Pass HEL to Services", self.logId)) end
    self.services:hello(hello.endpointUrl)
  end

  local bufSize = math.min(self.config.bufSize, hello.receiveBufferSize)
  local messageSize = 1 << 20 -- 1MB
  local maxChunkCount = messageSize / bufSize

  self.decoder:setBuferSize(bufSize)

  local ack = {
    protocolVersion = 0,
    receiveBufferSize = bufSize,
    sendBufferSize = bufSize,
    maxMessageSize = messageSize,
    maxChunkCount = maxChunkCount
  }

  if infOn then
    traceI(fmt("%s Acknowledge: ReceiveBufferSize=%d, SendBufferSize=%d, MaxMessageSize=%d, MaxChunkCount=%d",
        self.logId, ack.receiveBufferSize, ack.sendBufferSize, ack.maxMessageSize, ack.maxChunkCount))
  end

  self.encoder:acknowledge(ack)
  self.encoder:setChannelId(0)
  self.state = State.Hello
  if infOn then traceI(fmt("%s Connection Acknowledged", self.logId)) end
end


function S:processOpenSecureChannel(msg)
  local dbgOn = self.trace.dbgOn
  local errOn = self.trace.errOn
  local infOn = self.trace.infOn
  if dbgOn then traceD(fmt("%s OpenSecureChannel", self.logId)) end
  if not msg then
    msg = self.decoder:message()
  end

  local req = msg.body

  if self.state == State.New then
    if errOn then traceE(fmt("%s Failed to open secure channel: Client didn't send hello", self.logId)) end
    self:responseServiceFault(msg, s.BadRequestTypeInvalid)
    return
  elseif self.state == State.Hello then
    if req.requestType ~= ua.Types.SecurityTokenRequestType.Issue then
      if errOn then traceE(fmt("%s Received request type '%s' instead 'issue(0)'", self.logId, req.requestType)) end
      self:responseServiceFault(msg, s.BadRequestTypeInvalid)
      return
    end
    if infOn then traceI(fmt("%s Issuing new channel token", self.logId)) end
  elseif self.state == State.Open then
    if req.requestType ~= ua.Types.SecurityTokenRequestType.Renew then
      if errOn then traceE(fmt("%s Received request type '%s' instead 'renew(1)'", self.logId, req.requestType)) end
      self:responseServiceFault(msg, s.BadRequestTypeInvalid)
      return
    end
    if infOn then traceI(fmt("%s Renew channel token", self.logId)) end
  elseif self.state == State.Closed then
    if errOn then traceE(fmt("%s Failed to renew closed channel", self.logId)) end
    self:responseServiceFault(msg, s.BadSecureChannelClosed)
    return
  else
    if errOn then traceE(fmt("Internal errror: Secure channel %d is in invalid state: %d", self.logId, self.state)) end
    error(s.BadInternalError)
  end


  self.encoder:setupPolicy(msg.secureHeader.securityPolicyUri, msg.secureHeader.senderCertificate)
  local serverNonce = self.encoder.policy:genNonce()
  local clientNonce = req.clientNonce

  self.encoder:setNonces(serverNonce, clientNonce)
  self.encoder:setSecureMode(msg.body.securityMode)

  self.decoder:setupPolicy(msg.secureHeader.securityPolicyUri, msg.secureHeader.senderCertificate)
  self.decoder:setNonces(clientNonce, serverNonce)
  self.decoder:setSecureMode(msg.body.securityMode)

  if dbgOn then traceD(fmt("%s Pass open secure channel to services", self.logId)) end
  self.services:openSecureChannel(req, self)

  local responseParams = {
    channelId = self.channelId,
    requestId = msg.requestId,
    securityPolicy = msg.secureHeader.securityPolicyUri,
    sertificate = self.config.sertificate,
    sertificateThumbprint = self.encoder.policy:getRemoteThumbprint(),
    requestHandle = req.requestHeader.requestHandle,
    requestCreatedAt = socket.gettime(),
    serviceResult = s.Good,
  }

  local tokenId = genNextToken()
  local createdAt = socket.gettime()
  local lifeTime = req.requestedLifetime -- ms
  if lifeTime <= 1000 then
    lifeTime = 1000
  elseif lifeTime > 300000 then
    lifeTime = 300000
  end

  self.tokens[tokenId] = {
    createdAt = createdAt,
    cifeTime = lifeTime,
    expiresAt = createdAt + lifeTime / 1000
  }

  self.encoder:setChannelId(self.channelId)
  self.encoder:setTokenId(tokenId)

  if dbgOn then traceD(fmt("%s Response for OpenSecureChannel", self.logId)) end


  local response = self.encoder:createResponse(Msg.OPEN_SECURE_CHANNEL_RESPONSE, responseParams)
  response.securityToken = {
    channelId = self.channelId,
    tokenId =   tokenId,
    createdAt = createdAt,
    revisedLifetime = lifeTime,
  }
  response.serverNonce = serverNonce
  response.serverProtocolVersion = 0

  self.encoder:message(response)

  self.state = State.Open
  self:cleanupExpredTokens(createdAt)
  if infOn then traceI(fmt("%s Issued secure channel token %s lifetime %s", self.logId, tokenId, lifeTime)) end
end

function S:processCloseSecureChannel(msg)
  local dbgOn = self.trace.dbgOn
  local errOn = self.trace.errOn
  local infOn = self.trace.infOn

  if infOn then traceI(fmt("%s processing CloseSecureChannel", self.logId)) end
  if self.state ~= State.Open then
    if errOn then traceE(fmt("%s Client didn't open channel", self.logId)) end
  else
    if dbgOn then traceD(fmt("%s Pass close secure channel to services", self.logId)) end
    self.services:closeSecureChannel(msg, self)
  end

  self.state = State.Hello
  if infOn then traceI(fmt("%s Secure channel closed", self.logId)) end
  self:responseServiceFault(msg, s.BadSecureChannelClosed)

  self.encoder:setChannelId(nil)
  self.encoder:setTokenId(nil)
end

function S:processMessage()
  local dbgOn = self.trace.dbgOn
  local errOn = self.trace.errOn

  local msg = self.decoder:message()

  if self.state ~= State.Open then
    if errOn then traceE(fmt("%s Secure channel is not in opened state.", self.logId)) end
    error(s.BadTcpMessageTypeInvalid)
  end

  if dbgOn then traceD(fmt("%s Processing message ID: %s", self.logId, msg.requestId)) end

  local i = msg.type
  -- Generating of error response only on encoding/decoding errors
  -- Processing of a valid request can cause only service fault response.
  -- In case of service fault return code will be Good, but response header will contain
  -- corresponding code of service processing error.
  if self.state == State.Open then
    if i == Msg.FIND_SERVERS_REQUEST then
      return self:processRequest(msg, Msg.FIND_SERVERS_RESPONSE, self.services.findServers, "FindServers")
    elseif i == Msg.GET_ENDPOINTS_REQUEST then
      return self:processRequest(msg, Msg.GET_ENDPOINTS_RESPONSE, self.services.getEndpoints, "GetEndpoints")
    elseif i == Msg.CLOSE_SECURE_CHANNEL_REQUEST then
      return self:processCloseSecureChannel(msg)
    elseif i == Msg.OPEN_SECURE_CHANNEL_REQUEST then
      return self:processOpenSecureChannel(msg)
    end

    if self.nonePolicyEnabled == false and self.decoder.q.policy.uri == ua.Types.SecurityPolicy.None then
      error(s.BadSecurityChecksFailed)
    end

    if i == Msg.CREATE_SESSION_REQUEST then
      self:processRequest(msg, Msg.CREATE_SESSION_RESPONSE, self.services.createSession, "CreateSession")
    elseif i == Msg.ACTIVATE_SESSION_REQUEST then
      self:processRequest(msg, Msg.ACTIVATE_SESSION_RESPONSE, self.services.activateSession, "ActivateSession")
    elseif i == Msg.CLOSE_SESSION_REQUEST then
      self:processRequest(msg, Msg.CLOSE_SESSION_RESPONSE, self.services.closeSession, "CloseSession")
    elseif i == Msg.BROWSE_REQUEST then
      self:processRequest(msg, Msg.BROWSE_RESPONSE,       self.services.browse, "Browse")
    elseif i == Msg.READ_REQUEST then
      self:processRequest(msg, Msg.READ_RESPONSE,       self.services.read, "Read")
    elseif i == Msg.WRITE_REQUEST then
      self:processRequest(msg, Msg.WRITE_RESPONSE,       self.services.write, "Write")
    elseif i == Msg.CREATE_SUBSCRIPTION_REQUEST then
      self:processRequest(msg, Msg.CREATE_SUBSCRIPTION_RESPONSE, self.services.createSubscription, "CreateSubscription")
    elseif i == Msg.TRANSLATE_BROWSE_PATHS_TO_NODE_IdS_REQUEST then
      self:processRequest(msg, Msg.TRANSLATE_BROWSE_PATHS_TO_NODE_IdS_RESPONSE, self.services.translateBrowsePaths, "TranslateBrowsePathsToNodeIds")
    elseif i == Msg.ADD_NODES_REQUEST then
      self:processRequest(msg, Msg.ADD_NODES_RESPONSE, self.services.addNodes, "AddNodes")
    else
      -- TODO NEED REMOVE EXTRA DATA OF NOT IMPLEMENTED REQUEST BODY
      if errOn then traceE(fmt("%s Invalid message ID: %d", self.logId, i)) end
      self:responseServiceFault(msg, s.BadNotImplemented)
    end
  else
    if errOn then traceE(fmt("%s Received message for closed secure channel.", self.logId)) end
    error(s.BadSecureChannelClosed)
  end
end

function S:processRequest(msg, type, service, reqName)
  local dbgOn = self.trace.dbgOn
  local errOn = self.trace.errOn

  local request = msg.body
  -- Decode request
  if dbgOn then traceD(fmt("%s Processing %s request handle %d", self.logId, reqName, request.requestHeader.requestHandle)) end

  local suc
  local result
  -- check token
  suc, result = pcall(self.setToken, self, msg.secureHeader.tokenId)
  if suc then
    suc, result = pcall(service, self.services, request, self)
  end

  -- Encode response
  if suc then
    if dbgOn then traceD(fmt("%s Encoding %s response", self.logId, reqName)) end
    local response = self.encoder:createResponse(type, self:fillResponseParams(msg, 0), result)
    self.encoder:message(response)
  else
    if errOn then traceE(fmt("%s Failed call %s: %s", self.logId, reqName, result)) end
    if dbgOn then traceD(fmt("%s Encoding %s service fault: %s", self.logId, reqName, result)) end
    self:responseServiceFault(msg, result)
  end
end

function S.fillResponseParams(_, msg, statusCode)
  return {
    requestId = msg.requestId,
    channelTokenId = msg.secureHeader.tokenId,
    channelId = msg.channelId,
    requestHandle = msg.body.requestHeader.requestHandle,
    requestCreatedAt = socket.gettime(),
    serviceResult = statusCode or s.Good
  }
end

function S:responseServiceFault(msg, faultCode)
  if self.trace.E then trace.E(fmt("%s Sending SERVICE_FAULT 0x%x", self.logId, faultCode)) end
  local response = self.encoder:createResponse(Msg.SERVICE_FAULT, self:fillResponseParams(msg, faultCode))
  self.encoder:message(response)
end

function S:setToken(tokenId)
  local errOn = self.trace.errOn
  local time = socket.gettime()
  self:cleanupExpredTokens(time)

  local token = self.tokens[tokenId]
  if token == nil then
    if errOn then traceE(fmt("%s Unknown token %d", self.logId, tokenId)) end
    error(s.BadSecureChannelTokenUnknown)
  end

  if time > token.expiresAt then
    if errOn then traceE(fmt("%s Secure token %d expired.", self.logId, tokenId)) end
    error(s.BadSecurityChecksFailed)
  end

  self.encoder.secureHeader.tokenId = tokenId
  self.logId = fmt("binary | %s:%s", self.channelId, tokenId)
  return s.Good
end


function S:cleanupExpredTokens(time)
  local dbgOn = self.trace.dbgOn
  local infOn = self.trace.infOn

  if dbgOn then traceD(fmt("%s Cleaning up tokens", self.logId)) end

  for id,token in pairs(self.tokens) do
    if time > token.expiresAt then
      if infOn then traceI(fmt("%s expired token %s ", self.logId, id)) end
      self.tokens[id] = nil
    else
      if dbgOn then traceD(fmt("%s token %s: %f secs ", self.logId, id, token.expiresAt - time)) end
    end
  end

  if dbgOn then traceD(fmt("%s Tokens cleaned up", self.logId)) end
end

function S:getLocalPolicy()
  return self.encoder.policy
end


local function newConnection(config, services, sock)
  assert(config ~= nil)
  assert(services ~= nil)
  assert(sock ~= nil)
  assert(config.bufSize >= 8192)

  local securePolicies = {}
  local nonePolicyEnabled = false
  for _,p in ipairs(config.securePolicies) do
    if p.securityPolicyUri == ua.Types.SecurityPolicy.None then
      nonePolicyEnabled = true
    end
    table.insert(securePolicies, p)
  end

  if nonePolicyEnabled == false then
    table.insert(securePolicies,
      {
        securityPolicyUri = ua.Types.SecurityPolicy.None,
        securityMode = {ua.Types.MessageSecurityMode.None}
      }
    )
  end

  local secureConfig = {
    securePolicies = securePolicies,
    certificate = config.certificate,
    key = config.key,
    io = config.io
  }

  local security = securePolicy(secureConfig)

  channelsNum = channelsNum + 1
  local c = {
    channelId = channelsNum,
    sock = sock,
    tokens = {},
    services = services,
    decoder = decoder.new(config, security, sock),
    encoder = encoder.new(config, security, sock),
    state = State.New,
    config = config,
    nonePolicyEnabled = nonePolicyEnabled,
    trace = config.logging.binary,
    logId = fmt("binary | %s:%s", channelsNum, 0)
  }

  setmetatable(c, S)


  return c
end

return {
  new=newConnection,
}
