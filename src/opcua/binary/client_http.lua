local ua = require("opcua.api")
local compat = require("opcua.compat")
local BinaryMessageEncoder = require("opcua.binary.chunks_encode")
local BinaryMessageDecoder = require("opcua.binary.chunks_decode")
local JsonMessageEncoder = require("opcua.json.chunks_encode")
local JsonMessageDecoder = require("opcua.json.chunks_decode")
local newClientSock = require("opcua.socket_rtl").newClientSock
local securePolicy = require("opcua.binary.crypto.policy")

local fmt = string.format

local traceD = ua.trace.dbg
local traceI = ua.trace.inf
local traceE = ua.trace.err

local BadCommunicationError = ua.StatusCode.BadCommunicationError
local BadNotConnected = ua.StatusCode.BadNotConnected


local C={} -- OpcUa Client
C.__index=C

local function processConnect(err, callback)
  if callback then
    callback(err)
  end
  return err
end

local function createSocket(url, transportProfile, config)
  local infOn = config.logging.socket.infOn
  local errOn = config.logging.socket.errOn
  local dbgOn = config.logging.socket.dbgOn

  local mimetype
  if transportProfile == ua.TranportProfileUri.HttpsBinary then
    mimetype = "application/opcua+uabinary"
    -- mimetype = "application/octet-stream"
  elseif transportProfile == ua.TranportProfileUri.HttpsJson then
    mimetype = "application/opcua+uajson"
    -- mimetype = "application/json"
  else
    error(fmt("Unsupported HTTP transport profile: %s", transportProfile))
  end

  local http = compat.httpc.create()
  http:timeout(20000)

  local out = {
    http = http,
    op = {
      shark = config.shark,
      url = url,
      method = "POST",
      header = {
        ["User-Agent"] = "mako",
        ["Content-Type"] = mimetype,
        ["OPCUA-SecurityPolicy"] = ua.SecurityPolicy.None
      },
      trusted = false
    },

    write = function(self, data)
      if infOn then traceI(fmt("http.client | sending %d bytes", #data)) end

      if dbgOn then ua.Tools.printTable("http.client | header", self.op.header, traceD) end

      self.op.size = #data
      http:request(self.op)
      local ok,err = http:write(tostring(data))
      if not ok then
        if errOn then traceE(fmt("http.client | write error %s", err)) end
        error(BadCommunicationError)
      end
      if infOn then traceI("http.client | data sent") end
      return ok, err
    end,

    read = function(self)
      if infOn then traceI("http.client | receiving response") end
      local status, err = http:status()
      if err then
        if errOn then traceE(fmt("http.client | HTTP error: %s", err)) end
        error(BadCommunicationError)
      end

      if status ~= 200 then
        if errOn then traceE(fmt("http.client | HTTP status %s", status)) end
        error(BadCommunicationError)
      else
        if dbgOn then traceD(fmt("http.client | HTTP status %s", status)) end
      end

      if dbgOn then
        local headers
        headers, err = http:header()
        if err ~= 200 then
          if errOn then traceE(fmt("http.client | header error: %s", err)) end
          error(BadCommunicationError)
        end
        ua.Tools.printTable("http.client | headers", headers, traceD)
      end
      local data
      data,err= self.http:read('a')
      if err then
        if errOn then traceE(fmt("http.client | read error: %s", err)) end
        error(BadCommunicationError)
      end

      if infOn then traceI(fmt("http.client | received %d bytes", #data)) end
      return data
    end,

    close = function(self)
      self.http:close()
      self.http = nil
    end
  }

  return out
end

function C:coRun(endpointUrl, transportProfile, connectCallback, messageCallback)
  self.connectCallback = connectCallback
  self.messageCallback = messageCallback
  self.thread = ba.thread:run(function()
    self:connectServer(endpointUrl, transportProfile, connectCallback)
  end)
end

function C:connectServer(endpointUrl, transportProfile, connectCallback)
  local config = self.config
  local infOn = self.config.logging.binary.infOn
  local errOn = self.config.logging.binary.errOn

  local sock

  if infOn then traceI("binary | Connecting to endpoint: "..endpointUrl) end
  local url,err = ua.parseUrl(endpointUrl)
  if err then
    return processConnect(err, connectCallback)
  end

  if
    url.scheme ~= "opc.http"  and url.scheme ~= "http" and
    url.scheme ~= "opc.https" and url.scheme ~= "https"
  then
    err = "Unknown protocol scheme '"..url.scheme.. "'"
    return processConnect(err, connectCallback)
  end

  if self.sock == nil then
    if infOn then traceI("http.client | conecting to http endpoint '".. endpointUrl.."'") end
    local httpUrl = endpointUrl
    if httpUrl:find("opc.") == 1 then
      httpUrl = string.sub(httpUrl, 5)
    end

    sock, err = createSocket(httpUrl, transportProfile, config)
    if infOn then traceI(fmt("http.client | sock='%s' err='%s'", sock, err)) end
    if err ~= nil then
      if errOn then traceE("http.client | tcp error: "..err) end
      processConnect(err, connectCallback)
      return err
    end

    if self.sock == nil then
      if infOn then traceI(fmt("http.client | connected: %s", sock)) end
      self.sock = newClientSock(sock, config)
      self.sock:setTimeout(config.socketTimeout)
    else
      self.sock.sock = sock
    end
  end

  if self.dec == nil then
    local hasChunks = false
    if transportProfile == ua.TranportProfileUri.HttpsBinary then
      self.enc = BinaryMessageEncoder.new(config, self.security, self.sock, hasChunks, self.model)
      self.dec = BinaryMessageDecoder.new(config, self.security, self.sock, hasChunks, self.model)
    elseif transportProfile == ua.TranportProfileUri.HttpsJson then
      self.enc = JsonMessageEncoder.new(config, self.security, self.sock, hasChunks, self.model)
      self.dec = JsonMessageDecoder.new(config, self.security, self.sock, hasChunks, self.model)
    else
      error("Unsupported HTTP transport profile: "..transportProfile)
    end

    self.enc:setChannelId(0)
    self.enc:setTokenId(0)
    self:setupPolicy(ua.SecurityPolicy.None)
    self:setSecureMode(ua.MessageSecurityMode.None)

    self.enc:setupPolicy(ua.SecurityPolicy.None)
    self.dec:setupPolicy(ua.SecurityPolicy.None)
    self.enc:setSecureMode(ua.MessageSecurityMode.None)
    self.dec:setSecureMode(ua.MessageSecurityMode.None)
  end

  return processConnect(nil, connectCallback)
end

function C:sendMessage(msg, sync)
  if not self.sock then error(BadNotConnected) end

  local c = self
  if not self.thread or sync then
    local result = c.enc:message(msg)
    return result
  end

  ba.thread.run(function()
    local suc, result = pcall(c.enc.message, c.enc, msg)
    if suc then
      suc, result = pcall(c.dec.message, c.dec)
    end

    local err
    if not suc then
      err = result
      result = nil
    end

    if err == BadCommunicationError then
      return processConnect(err, c.connectCallback)
    else
      c.messageCallback(result, err) -- result is a message
    end
  end)
end

function C:recvMessage()
  if not self.sock then error(BadNotConnected) end
  if self.thread then
    error("Invalid usage: async mode")
  end
  return self.dec:message()
end

function C:createRequest(type, request)
  -- if not self.sock then
  --   return nil, BadNotConnected
  -- end
  -- if not self.enc.policy then
  --   return nil, BadSecureChannelIdInvalid
  -- end

  self.requestId = self.requestId + 1
  self.requestHandle = self.requestHandle + 1
  local requestHeader = {
    RequestId = self.requestId,
    RequestHandle = self.requestHandle,
    RequestTimeout = 1000,
    RequestCreatedAt = compat.gettime(),
    SessionAuthToken = self.sessionAuthToken,
  }

  return self.enc:createRequest(type, requestHeader, request)
end

function C:setupPolicy(securityPolicyUri)
  -- It is only required to set up HTTP header
  if self.config.ifOn then
    traceI(fmt("http.client | Set security policy: %s", securityPolicyUri))
  end

  self.sock.sock.op["OPCUA-SecurityPolicy"] = securityPolicyUri
end

function C.setSecureMode()
end

function C.setNonces()
end

function C:disconnect()
  local sock = self.sock
  if not sock then return BadNotConnected end
  self.sock = nil
  if sock then
    sock:shutdown()
    self.enc = nil
    self.dec = nil
  end

  self.thread = nil
end

function C:connected()
  if not self.enc then
    return false
  end
  return true
end

local function new(config, sock, model)
  if config == nil then
    error("empty config")
  end
  if model == nil then
    error("empty model")
  end

  local security = securePolicy(config)

  local cl = {
    config = config,
    security = security;
    requestHandle = 0,
    requestId = 0,
    sessionAuthToken = ua.NodeId.Null,
    sock = sock,
    model = model
  }

  setmetatable(cl, C)
  return cl
end

return {new=new}
