local ua = require("opcua.api")
local socket = require("socket")
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


local function readLoop(self, endpointUrl, connectCallback, messageCallback)
  local dbgOn = self.config.logging.binary.dbgOn
  if self:connectServer(endpointUrl, connectCallback) ~= nil then
    return
  end

  while self.dec do
    if dbgOn then traceD("binary | cosocket: waiting for next response") end
    local err, result = pcall(self.dec.message, self.dec)
    if err == true then
      if dbgOn then traceD(fmt("binary | cosocket: decoding error '%s'", result)) end
      err = nil
    else
      if dbgOn then traceD("binary | cosocket: new message decoded") end
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

function C:connectServer(endpointUrl, connectCallback)
  local config = self.config
  local infOn = self.config.logging.binary.infOn
  local errOn = self.config.logging.binary.errOn

  local sock

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
    sock, err = ba.socket.connect(url.host, url.port, {timeout=20000})
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
      -- self.sock:setTimeout(10000)
    else
      self.sock.sock = sock
    end
  end

  if self.dec == nil then
    self.enc = MessageEncoder.new(config, self.security, self.sock)
    self.dec = MessageDecoder.new(config, self.security, self.sock)
  end

  local hello = {
    protocolVersion = 0,
    receiveBufferSize = self.config.bufSize,
    sendBufferSize = self.config.bufSize,
    maxMessageSize = self.config.bufSize,
    maxChunkCount = 0,
    endpointUrl = endpointUrl
  }
  if infOn then traceI("binary | saying hello to server") end
  self.enc:hello(hello)

  local ack = self.dec:acknowledge()
  self.dec:setBuferSize(ack.sendBufferSize)
  self.enc:setBuferSize(ack.receiveBufferSize)

  if infOn then
    traceI("binary | Acknowledged: ProtocolVersion='"..ack.protocolVersion.."' ReceiveBufferSize='"..ack.receiveBufferSize..
       "' SendBufferSize='"..ack.sendBufferSize.."' MaxMessageSize: '"..ack.maxMessageSize..
       "' MaxChunkCount: '"..ack.maxChunkCount.."'")
  end

  return processConnect(nil, connectCallback)
end

function C:coRun(endpointUrl, connectCallback, messageCallback)
  if type(connectCallback) ~= 'function' then error("Callback empty") end
  local c = self
  ba.socket.event(function()
    readLoop(c, endpointUrl, connectCallback, messageCallback)
  end)
end

function C:sendMessage(msg)
  if not self.sock then error(BadNotConnected) end
  self.enc:message(msg)
end

function C:recvMessage()
  if not self.sock then error(BadNotConnected) end
  return self.dec:message()
end

function C:createRequest(type, request)
  if not self.sock then
    return nil, BadNotConnected
  end
  if not self.enc.policy then
    return nil, BadSecureChannelIdInvalid
  end

  self.requestId = self.requestId + 1
  self.requestHandle = self.requestHandle + 1
  local requestHeader = {
    requestId = self.requestId,
    requestHandle = self.requestHandle,
    requestTimeout = 1000,
    requestCreatedAt = socket.gettime(),
    sessionAuthToken = self.sessionAuthToken,
    securityPolicy = self.enc.policy.uri,
    certificate = self.enc.policy:getLocalCert(),
    certificateThumbprint = self.enc.policy:getRemoteThumbprint(),
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

local function new(config, sock)
  if config == nil then
    error("empty config")
  end

  local security = securePolicy(config)

  local cl = {
    config = config,
    security = security;
    requestHandle = 0,
    requestId = 0,
    sessionAuthToken = ua.NodeId.Null,
    sock = sock,
  }

  setmetatable(cl, C)
  return cl
end

return {new=new}
