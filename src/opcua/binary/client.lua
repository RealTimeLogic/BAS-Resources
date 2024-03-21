local ua = require("opcua.api")
local compat = require("opcua.compat")
local MessageEncoder = require("opcua.binary.chunks_encode")
local MessageDecoder = require("opcua.binary.chunks_decode")
local newClientSock = require("opcua.socket_rtl").newClientSock
local securePolicy = require("opcua.binary.crypto.policy")

local fmt = string.format

local traceD = ua.trace.dbg
local traceI = ua.trace.inf
local traceE = ua.trace.err

local BadCommunicationError = ua.StatusCode.BadCommunicationError
local BadNotConnected = ua.StatusCode.BadNotConnected
local BadSecureChannelIdInvalid = ua.StatusCode.BadSecureChannelIdInvalid


local C={} -- OpcUa Client
C.__index=C


local function readLoop(self, endpointUrl, transportProfile, connectCallback, messageCallback)
  local dbgOn = self.config.logging.binary.dbgOn
  if self:connectServer(endpointUrl, transportProfile, connectCallback) ~= nil then
    return
  end

  while self.dec do
    if dbgOn then traceD("binary | cosocket: waiting for next response") end
    local err, result = pcall(self.dec.message, self.dec)
    if err == true then
      if dbgOn then traceD("binary | cosocket: new message decoded") end
      err = nil
    else
      if dbgOn then traceD(fmt("binary | cosocket: reeive error '%s'", result)) end
      err = result
      result = nil
    end

    if result == nil and err == nil then
      if dbgOn then traceD("binary | cosocket: internal error. Message nul and error nil") end
      err = BadCommunicationError
    end

    if err == BadCommunicationError then
      self.sock = nil
      if dbgOn then traceD(fmt("binary | cosocket: Calling connect callback with error '%s'", err)) end
      connectCallback(err)
      break
    else
      if dbgOn then traceD("binary | cosocket: Calling message callback") end
      messageCallback(result, err) -- result is a message
    end
  end

  if dbgOn then traceD("binary | cosocket: exited") end
end

local function processConnect(err, callback)
  if callback then
    callback(err)
  end
  return err
end

function C:connectServer(endpointUrl, transportProfile, connectCallback)
  assert(transportProfile == ua.Types.TranportProfileUri.TcpBinary)

  local config = self.config
  local sock
  local infOn = self.config.logging.binary.infOn
  local errOn = self.config.logging.binary.errOn

  -- coRun method passes default callback in other
  -- cases callback must be defined by user
  if compat.socket.getsock() and not connectCallback then
    error("OPCUA: can't connect in cosocket context")
  end


  if infOn then traceI("binary | Connecting to endpoint: "..endpointUrl) end
  local url,err = ua.parseUrl(endpointUrl)
  if err then
    return processConnect(err, connectCallback)
  end
  if url.scheme ~= "opc.tcp" then
    err = "Unknown protocol scheme '"..url.scheme.. "'"
    return processConnect(err, connectCallback)
  end

  if self.sock == nil then
    if infOn then traceI("binary | conecting to host '"..url.host.."' port '"..url.port.."'") end
    sock, err = compat.socket.connect(url.host, url.port, {timeout=20000})
    if infOn then traceI(fmt("binary | sock='%s' err='%s'", sock, err)) end
    if err ~= nil then
      if errOn then traceE("binary | tcp error: "..err) end
      processConnect(err, connectCallback)
      return err
    end
    sock:queuelen(0)

    if self.sock == nil then
      if infOn then traceI(fmt("binary | connected: %s", sock)) end
      self.sock = newClientSock(sock, config)
      self.sock:setTimeout(config.socketTimeout)
    else
      self.sock.sock = sock
    end
  end

  if self.dec == nil then
    local hasChunks = true
    self.enc = MessageEncoder.new(config, self.security, self.sock, hasChunks, self.model)
    self.dec = MessageDecoder.new(config, self.security, self.sock, hasChunks, self.model)
  end

  local hello = {
    ProtocolVersion = 0,
    ReceiveBufferSize = self.config.bufSize,
    SendBufferSize = self.config.bufSize,
    MaxMessageSize = self.config.bufSize,
    MaxChunkCount = 0,
    EndpointUrl = endpointUrl
  }
  if infOn then traceI("binary | saying hello to server") end
  self.enc:hello(hello)

  local ack = self.dec:acknowledge()
  self.dec:setBufferSize(ack.SendBufferSize)
  self.enc:setBufferSize(ack.ReceiveBufferSize)

  if infOn then
    traceI("binary | Acknowledged: ProtocolVersion='"..ack.ProtocolVersion.."' ReceiveBufferSize='"..ack.ReceiveBufferSize..
       "' SendBufferSize='"..ack.SendBufferSize.."' MaxMessageSize: '"..ack.MaxMessageSize..
       "' MaxChunkCount: '"..ack.MaxChunkCount.."'")
  end

  return processConnect(nil, connectCallback)
end

function C:coRun(endpointUrl, transportProfile, connectCallback, messageCallback)
  local infOn = self.config.logging.binary.infOn

  if transportProfile ~= ua.Types.TranportProfileUri.TcpBinary then
    error("Binary client with transport profile '"..tostring(transportProfile).."' not supported")
  end

  local coSock = compat.socket.getsock()
  if coSock == nil and connectCallback == nil then
    error("OPCUA: no connect callback in empty cosocket context")
  end

  if infOn then traceI(fmt("services | Connecting to endpoint '%s' in cosock mode", endpointUrl)) end
  local defCallback
  if connectCallback == nil then
    defCallback = function(resp, e)
      coSock:enable(resp, e)
    end
  else
    if type(connectCallback) ~= 'function' then error("Callback empty") end
  end

  local c = self
  compat.socket.event(function()
    readLoop(c, endpointUrl, transportProfile, connectCallback or defCallback, messageCallback)
  end)

  if defCallback ~= nil then
    if infOn then traceI(fmt("services | waiting for connection", endpointUrl)) end
    return coSock:disable()
  end
end

function C:sendMessage(msg)
  if not self.sock then error(BadNotConnected) end
  self.enc:message(msg)
end

function C:recvMessage()
  if not self.sock then error(BadNotConnected) end
  return self.dec:message()
end

function C:connected()
  return self.enc ~= nil
end

function C:createRequest(type, request)
  if not self:connected() then
    return nil, BadNotConnected
  end
  if not self.enc.policy then
    return nil, BadSecureChannelIdInvalid
  end

  self.requestId = self.requestId + 1
  self.requestHandle = self.requestHandle + 1
  local requestHeader = {
    RequestId = self.requestId,
    RequestHandle = self.requestHandle,
    RequestTimeout = 1000,
    RequestCreatedAt = compat.gettime(),
    SessionAuthToken = self.sessionAuthToken,
    SecurityPolicy = self.enc.policy.uri,
    Certificate = self.enc.policy:getLocalCert(),
    CertificateThumbprint = self.enc.policy:getRemoteThumbprint(),
  }

  return self.enc:createRequest(type, requestHeader, request)
end

function C:disconnect()
  local sock = self.sock
  if not sock then return BadNotConnected end
  self.sock = nil
  if sock then
    sock:shutdown()
    if self.config.cosocketMode == true then
      sock.sock:enable()
    end
    self.enc = nil
    self.dec = nil
  end
end

function C:setupPolicy(securityPolicyUri, remoteCert)
  self.enc:setupPolicy(securityPolicyUri, remoteCert)
  self.dec:setupPolicy(securityPolicyUri, remoteCert)
end

function C:setSecureMode(secureMode)
  self.enc:setSecureMode(secureMode)
  self.dec:setSecureMode(secureMode)
end

function C:setNonces(localNonce, remoteNonce)
  self.enc:setNonces(localNonce, remoteNonce)
  self.dec:setNonces(remoteNonce, localNonce)
end

local function new(config, sock, model)
  if config == nil then
    error("empty config")
  end

  if model == nil then
    error("no model")
  end

  local security = securePolicy(config)

  local cl = {
    config = config,
    security = security;
    requestHandle = 0,
    requestId = 0,
    sessionAuthToken = ua.NodeId.Null,
    sock = sock,
    model = model,
  }

  setmetatable(cl, C)
  return cl
end

return {new=new}
