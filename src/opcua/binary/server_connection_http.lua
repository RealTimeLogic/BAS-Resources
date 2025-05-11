local BinaryMessageEncoder = require("opcua.binary.chunks_encode")
local BinaryMessageDecoder = require("opcua.binary.chunks_decode")
local JsonMessageEncoder = require("opcua.json.chunks_encode")
local JsonMessageDecoder = require("opcua.json.chunks_decode")
local securePolicy = require("opcua.binary.crypto.policy")
local Msg = require("opcua.binary.message_id")
local ua = require("opcua.api")
local compat = require("opcua.compat")

local s = ua.StatusCode
local fmt = string.format
local traceD = ua.trace.dbg
local traceE = ua.trace.err
local traceI = ua.trace.inf


local S = {}
S.__index = S

function S:processData(securityPolicyUri)
  local dbgOn = self.trace.dbgOn
  local errOn = self.trace.errOn
  if dbgOn then traceD(fmt("%s Decoding new message", self.logId)) end

  local msg = self.decoder:message()
  if dbgOn then traceD(fmt("%s Processing message ID: %s", self.logId, msg.TypeId)) end

  local i = msg.TypeId
  if i == Msg.FIND_SERVERS_REQUEST then
    return self:processRequest(nil, msg, Msg.FIND_SERVERS_RESPONSE, self.services.findServers, "FindServers")
  elseif i == Msg.GET_ENDPOINTS_REQUEST then
    return self:processRequest(nil, msg, Msg.GET_ENDPOINTS_RESPONSE, self.services.getEndpoints, "GetEndpoints")
  elseif i == Msg.CREATE_SESSION_REQUEST then
    local channel = {
      getLocalPolicy = function()
        local policy = self.security(securityPolicyUri)
        if securityPolicyUri ~= ua.Types.SecurityPolicy.None then
          policy:setSecureMode(ua.Types.MessageSecurityMode.Sign)
        end
        return policy
      end
    }
    self:processRequest(channel, msg, Msg.CREATE_SESSION_RESPONSE, self.services.createSession, "CreateSession")
  elseif i == Msg.ACTIVATE_SESSION_REQUEST then
    self:processRequest(nil, msg, Msg.ACTIVATE_SESSION_RESPONSE, self.services.activateSession, "ActivateSession")
  elseif i == Msg.CLOSE_SESSION_REQUEST then
    self:processRequest(nil, msg, Msg.CLOSE_SESSION_RESPONSE, self.services.closeSession, "CloseSession")
  elseif i == Msg.BROWSE_REQUEST then
    self:processRequest(nil, msg, Msg.BROWSE_RESPONSE,       self.services.browse, "Browse")
  elseif i == Msg.READ_REQUEST then
    self:processRequest(nil, msg, Msg.READ_RESPONSE,       self.services.read, "Read")
  elseif i == Msg.WRITE_REQUEST then
    self:processRequest(nil, msg, Msg.WRITE_RESPONSE,       self.services.write, "Write")
  elseif i == Msg.CREATE_SUBSCRIPTION_REQUEST then
    self:processRequest(nil, msg, Msg.CREATE_SUBSCRIPTION_RESPONSE, self.services.createSubscription, "CreateSubscription")
  elseif i == Msg.TRANSLATE_BROWSE_PATHS_TO_NODE_IdS_REQUEST then
    self:processRequest(nil, msg, Msg.TRANSLATE_BROWSE_PATHS_TO_NODE_IdS_RESPONSE, self.services.translateBrowsePaths, "TranslateBrowsePathsToNodeIds")
  elseif i == Msg.ADD_NODES_REQUEST then
    self:processRequest(nil, msg, Msg.ADD_NODES_RESPONSE, self.services.addNodes, "AddNodes")
  else
    -- TODO NEED REMOVE EXTRA DATA OF NOT IMPLEMENTED REQUEST BODY
    if errOn then traceE(fmt("%s Invalid message ID: %d", self.logId, i)) end
    self:responseServiceFault(msg, s.BadNotImplemented)
  end
end

function S:processRequest(channel, msg, type, service, reqName)
  local dbgOn = self.trace.dbgOn
  local errOn = self.trace.errOn

  local request = msg.Body
  -- Decode request
  if dbgOn then traceD(fmt("%s Processing %s request handle %d", self.logId, reqName, request.RequestHeader.RequestHandle)) end

  local suc, result = pcall(service, self.services, request, channel)

  -- Encode response
  if suc then
    if dbgOn then traceD(fmt("%s Encoding %s response", self.logId, reqName)) end
    local response = self.encoder:createResponse(type, self:fillResponseParams(msg, 0), result)
    if dbgOn then ua.Tools.printTable(fmt("%s | response", self.logId), response, traceD) end

    self.encoder:message(response)
    return result
  else
    if errOn then traceE(fmt("%s Failed call %s: %s", self.logId, reqName, result)) end
    if dbgOn then traceD(fmt("%s Encoding %s service fault: %s", self.logId, reqName, result)) end
    self:responseServiceFault(msg, result)
  end
end

function S.fillResponseParams(_, msg, statusCode)
  return {
    RequestId = msg.RequestId,
    RequestHandle = msg.Body.RequestHeader.RequestHandle,
    RequestCreatedAt = compat.gettime(),
    ServiceResult = statusCode or s.Good
  }
end

function S:responseServiceFault(msg, faultCode)
  if self.trace.errOn then traceE(fmt("%s Sending SERVICE_FAULT 0x%s", self.logId, faultCode)) end
  local response = self.encoder:createResponse(Msg.SERVICE_FAULT, self:fillResponseParams(msg, faultCode))
  self.encoder:message(response)
end

local function createSocket(config)
  local out = {
    send = function(self, data)
      self.data = tostring(data)
    end,

    receive = function(self)
      local dbgOn = config.logging.socket.infOn
      local errOn = config.logging.socket.errOn
      local data, err = self.readData()
      if err then
        if errOn then traceE(fmt("http.server | Read error %s ", err)) end
        error(s.BadCommunicationError)
      end
      if dbgOn then
        traceD(fmt("http.server | Received %d bytes", #data))
      end

      return data
    end,

    getData = function(self)
      local data = self.data
      self.data = nil
      return data
    end
  }

  return out
end

function S:processHttp(request, response)
  local logging = self.config.logging.socket
  local dbgOn = logging.dbgOn
  local infOn = logging.infOn
  local errOn = logging.errOn

  if infOn then  traceI(fmt("%s HTTP request", self.logId)) end
  if type(request) == "table" and request.request then
    response = request.response
    request = request.request
  end

  local securityPolicyUri = request:header("OPCUA-SecurityPolicy")
  local encoding = request:header("Content-Type")
  local method = request:method()
  if dbgOn then
    traceD(fmt("%s HTTP request Uri='%s' Method='%s' Content-Type='%s' OPCUA-SecurityPolicy='%s'", self.logId, request:url(), method, encoding, securityPolicyUri))
    ua.Tools.printTable(fmt("%s | headers", self.logId), request:header(), traceD)
  end

  response:setheader("Access-Control-Allow-Origin", "*")
  if method == "OPTIONS" then
    response:setheader("Access-Control-Allow-Headers", "OPCUA-SecurityPolicy, Content-Type")
    response:setheader("Access-Control-Allow-Methods", "POST")
    response:setheader("Access-Control-Max-Age`", "3600")
    response:setstatus(204)
    response:flush()
    if infOn then traceI(string.format("%s OPTIONS response sent", self.logId)) end
    return
  end

  if not securityPolicyUri or not encoding or method ~= "POST" then
    if errOn then traceE(string.format("%s Error 405 method '%s' not allowed", self.logId, method)) end
    response:senderror(405) -- Method not allowed
    return
  end

  local hasChunks = false
  local sock = self.sock
  if encoding == "application/octet-stream" or encoding == "application/opcua+uabinary" then
    if dbgOn then traceD(string.format("%s Binary encoding", self.logId)) end

    -- No any security applied to HTTP binary messages since
    -- HTTPS protocol applies own encryption.
    -- The only place where security policy required are
    -- CreateSession/Activate session calls: there are signatures
    -- of nonces calculated to prove certificate owing.
    local enc = BinaryMessageEncoder.new(self.config, self.security, sock, hasChunks, self.model)
    enc:setupPolicy(ua.Types.SecurityPolicy.None)
    enc:setSecureMode(ua.Types.MessageSecurityMode.None)

    local dec = BinaryMessageDecoder.new(self.config, self.security, sock, hasChunks, self.model)
    dec:setupPolicy(ua.Types.SecurityPolicy.None)
    dec:setSecureMode(ua.Types.MessageSecurityMode.None)
    self.encoder = enc
    self.decoder = dec
  elseif encoding == "application/opcua+uajson" then
    if dbgOn then traceD(string.format("%s JSON encoding", self.logId)) end
    sock.json = function()
      local jparser = ba.json.parser()
      for data in request:rawrdr() do
        local ok,t=jparser:parse(data)
        if t then
          return t
        end
        if not ok then
          break
        end
      end
      error(s.BadDecodingError)
    end
    self.encoder = JsonMessageEncoder.new(self.config, self.security, sock, hasChunks, self.model)
    self.decoder = JsonMessageDecoder.new(self.config, self.security, sock, hasChunks, self.model)
  else
    if errOn then traceE(string.format("%s Error 415 unsupported '%s'", self.logId, encoding)) end
    return response:senderror(415) -- Unsupported Media Type
  end

  sock.readData = request:rawrdr()

  if dbgOn then traceD(string.format("%s Processing data", self.logId)) end
  local suc, resp = pcall(self.processData, self, securityPolicyUri)
  if not suc then
    if errOn then traceE(string.format("%s Error %s", self.logId, resp)) end
    response:senderror(500)
    return
  end

  local str = sock:getData()

  if dbgOn then traceD(string.format("%s Sending %d data", self.logId, #str)) end
  response:setstatus(200)
  response:setcontenttype(encoding)
  response:setcontentlength(#str)
  response:send(str)
  response:flush()
  if infOn then traceI(string.format("%s %d bytes sent", self.logId, #str)) end
end

local function newConnection(config, services, model)
  assert(config ~= nil)
  assert(services ~= nil)
  assert(model ~= nil)

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

  local c = {
    sock = createSocket(config),
    security = security,
    services = services,
    config = config,
    nonePolicyEnabled = nonePolicyEnabled,
    trace = config.logging.binary,
    logId = "http.server | ",
    model = model
  }

  setmetatable(c, S)
  return function(req, resp)
    c:processHttp(req, resp)
  end
end

return {
  new=newConnection,
}
