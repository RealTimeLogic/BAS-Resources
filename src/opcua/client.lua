local ua = require("opcua.api")
local securePolicy = require("opcua.binary.crypto.policy")
local certificate = require("opcua.binary.crypto.certificate")
local Q = require("opcua.binary.queue")
local Binary = require("opcua.binary.encode_types")
local MessageId = require("opcua.binary.message_id")
local tools = ua.Tools

local traceI = ua.trace.inf
local traceD = ua.trace.dbg
local traceE = ua.trace.err
local fmt = string.format

local BadNotConnected = ua.StatusCode.BadNotConnected
local BadIdentityTokenRejected = ua.StatusCode.BadIdentityTokenRejected
local BadIdentityTokenInvalid = ua.StatusCode.BadIdentityTokenInvalid

local C={} -- OpcUa Client
C.__index=C

local function syncExecRequest(self, request)
  local dbgOn = self.config.logging.services.dbgOn
  if dbgOn then ua.Tools.printTable("services | execRequest", request, traceD) end

  local suc, err = pcall(self.services.sendMessage, self.services, request)
  if not suc then
    return self:processResponse(nil, err)
  end

  local resp
  suc, resp = pcall(self.services.recvMessage, self.services)
  if not suc then
    return self:processResponse(nil, resp)
  end

  return self:processResponse(resp)
end

local function coExecRequest(self, request, callback)
  local dbgOn = self.config.logging.services.dbgOn
  if dbgOn then ua.Tools.printTable("services | execRequest", request, traceD) end

  local coSock = ba.socket.getsock()
  local defCallback
  if coSock and callback == nil then
    defCallback = function(m, e)
      coSock:enable(m, e)
    end
  end

  self.requests[request.requestHeader.requestHandle] = callback or defCallback

  local suc, err = pcall(self.services.sendMessage, self.services, request)
  if not suc then
    self.requests[request.requestHeader.requestHandle] = nil
    return self:processResponse(nil, err)
  end

  if coSock and defCallback then
    return coSock:disable()
  end
end

local function coProcessResp(self, resp, err)
  if err then
    -- Error when receiving a message. In our case it is fatal.
    -- pass error to all handlers and disconnect.
    for _, callback in pairs(self.requests) do
      callback(resp, err)
    end
    self.requests = {}
  else
    local callback = self.requests[resp.responseHeader.requestHandle]
    if callback then
      if resp.responseHeader.serviceResult ~= 0 then
        return callback(nil, resp.responseHeader.serviceResult)
      else
        return callback(resp, err)
      end
    else
      error("unknown response handle: "..resp.responseHeader.requestHandle)
    end
  end
end

local function syncProcessResp(_, resp, err)
  if resp and resp.responseHeader.serviceResult ~= 0 then
    return nil, resp.responseHeader.serviceResult
  end

  return resp, err
end

function C:connect(endpointUrl, connectCallback)
  local config = self.config
  local infOn = config.logging.services.infOn
  local services = self.services
  local coSock = ba.socket.getsock()

  self.endpointUrl = endpointUrl

  if config.cosocketMode == true then
    if coSock == nil and connectCallback == nil then
      error("OPCUA: no connect callback in empty cosocket context")
    end

    if infOn then traceI(fmt("services | Connecting to endpoint '%s' in cosock mode", endpointUrl)) end
    local defCallback
    if connectCallback == nil then
      defCallback = function(resp, err)
        coSock:enable(resp, err)
      end
    end

    self.execRequest = coExecRequest
    self.processResp = coProcessResp
    local messageCallback = function(msg, err)
      self:processResponse(msg, err)
    end

    -- check url is valid before entering cosockets: we might hang there
    -- because of parsing URL is perofmed before first network call.
    local _,err = ua.parseUrl(endpointUrl)
    if err then
      (connectCallback or defCallback)(nil, err)
      return err;
    end

    services:coRun(endpointUrl, connectCallback or defCallback, messageCallback)
    if defCallback ~= nil then
      if infOn then traceI(fmt("services | waiting for connection", endpointUrl)) end
      return coSock:disable()
    end
  else
    if coSock then
      error("OPCUA: can't connect in cosocket context")
    end

    if connectCallback then
      error("OPCUA: can't use callbacks in non-cosocket mode")
    end

    if infOn then traceI(fmt("services | Connecting to endpoint '%s' in synchronous mode", endpointUrl)) end
    self.execRequest = syncExecRequest
    self.processResp = syncProcessResp
    return services:connectServer(endpointUrl)
  end
end

function C:disconnect()
  local infOn = self.config.logging.services.infOn

  self.endpointUrl = nil
  self.channelNonce = nil
  self.userIdentityTokens = nil
  self.sessionNonce = nil

  if self.channelTimer then
    if infOn then traceI("services | closing secure channel") end
    self:closeSecureChannel()
  end

  if infOn then traceI("Closing socket") end
  local resp, err = self.services:disconnect()
  if infOn then traceI("Disconnected") end
  return resp, err
end

function C:processResponse(msg, err)
  local infOn = self.config.logging.services.infOn
  local dbgOn = self.config.logging.services.dbgOn

  if dbgOn then
    ua.Tools.printTable("services | processingResponse", msg, traceD)
  end
  local response
  if msg then
    response = msg.body
    if response.responseHeader.serviceResult == 0 then
      if msg.type == MessageId.OPEN_SECURE_CHANNEL_RESPONSE then
        if infOn then traceI("services | received OPEN_SECURE_CHANNEL_RESPONSE") end
        self:processOpenSecureChannelResponse(response)
      elseif msg.type == MessageId.CREATE_SESSION_RESPONSE then
        self:processCreateSessionResponse(response)
      elseif msg.type == MessageId.ACTIVATE_SESSION_RESPONSE then
        self:processActivateSessionResponse(response)
      end
    end
  end

  return self:processResp(response, err)
end

function C:processOpenSecureChannelResponse(response)
  local infOn = self.config.logging.services.infOn

  local serverNonce = response.serverNonce

  self.services.enc:setNonces(self.channelNonce, serverNonce)
  self.services.dec:setNonces(serverNonce, self.channelNonce)

  self.services.dec:setSecureMode(self.securityMode)
  self.services.enc:setSecureMode(self.securityMode)

  self.services.enc:setChannelId(response.securityToken.channelId)
  self.services.enc:setTokenId(response.securityToken.tokenId)
  local timeoutMs = response.securityToken.revisedLifetime
  if infOn then traceI(fmt("services | secure channel token timeout %s", timeoutMs)) end
  timeoutMs = timeoutMs * 3 / 4
  if self.channelTimer == nil then
    self.channelTimer = ba.timer(function()
      if infOn then traceI("services | renewing secure channel token") end
      local _, err = self:renewSecureChannel(timeoutMs, function (_, err)
        if err == nil then
          if infOn then traceI("Secure channel renewed") end
        else
          if infOn then traceI(fmt("Failed to renew secure channel: %s", err)) end
        end
      end)
      return err == nil
    end)
    if infOn then traceI(fmt("services | set timer for renewing secure channel token: %s ms", timeoutMs)) end
    self.channelTimer:set(timeoutMs)
  else
    if infOn then traceI(fmt("services | reset timer for renewing secure channel token: %s ms", timeoutMs)) end
    self.channelTimer:reset(timeoutMs)
  end
end

function C:processCreateSessionResponse(response)
  local infOn = self.config.logging.services.infOn
  if infOn then
    traceI("services | received CREATE_SESSION_RESPONSE SessionId='"..response.sessionId..
          "' MaxRequestMessageSize="..response.maxRequestMessageSize..
          " AuthenticationToken='"..response.authenticationToken..
          "' RevisedSessionTimeout="..response.revisedSessionTimeout)
  end

  self.services.sessionId = response.sessionId
  self.services.sessionAuthToken = response.authenticationToken

  -- search current policy
  for _,endpoint in ipairs(response.serverEndpoints) do
    if endpoint.endpointUrl == self.endpointUrl and
       endpoint.securityPolicyUri == self.services.enc.policy.uri and
       endpoint.securityMode == self.securityMode
    then
      self.session = {
        userIdentityTokens = endpoint.userIdentityTokens,
        serverCertificate = endpoint.serverCertificate,
        nonce = response.serverNonce
      }
      break
    end
  end
end

function C:processActivateSessionResponse(response)
  local infOn = self.config.logging.services.infOn
  if infOn then
    traceI("services | received ACTIVATE_SESSION_RESPONSE")
  end

  if response.responseHeader.serviceResult == 0 then
    self.session.nonce = response.serverNonce
  end
end

function C:openSecureChannel(timeoutMs, securityPolicyUri, securityMode, remoteCert, callback)
  assert(type(securityPolicyUri) == 'string', "invalid policy uri")
  assert(type(securityMode) == 'number', "invalid security mode")

  local infOn = self.config.logging.services.infOn
  if infOn then traceI("services | Opening secure channel") end
  if self.services.enc == nil then return nil, BadNotConnected end

  self.services.enc:setupPolicy(securityPolicyUri, remoteCert)
  self.channelNonce = self.services.enc.policy:genNonce()
  self.securityMode = securityMode

  local request, err = self.services:createRequest(MessageId.OPEN_SECURE_CHANNEL_REQUEST)
  if err then return nil, err end
  request.clientProtocolVersion = 0
  request.requestType = ua.Types.SecurityTokenRequestType.Issue
  request.securityMode = securityMode
  request.clientNonce = self.channelNonce
  request.requestedLifetime = timeoutMs

  return self:execRequest(request, callback)
end

function C:renewSecureChannel(timeoutMs, callback)
  local infOn = self.config.logging.services.infOn
  if infOn then traceI("services | Renew secure channel") end
  if self.services.enc == nil then return nil, BadNotConnected end

  if self.services.enc.policy then
    self.channelNonce = self.services.enc.policy.genNonce()
  end

  local request, err = self.services:createRequest(MessageId.OPEN_SECURE_CHANNEL_REQUEST)
  if err then return nil, err end

  request.clientProtocolVersion = 0
  request.requestType = ua.Types.SecurityTokenRequestType.Renew
  request.securityMode = self.securityMode
  request.clientNonce = self.channelNonce
  request.requestedLifetime = timeoutMs

  return self:execRequest(request, callback)
end

function C:createSession(name, timeoutMs, callback)
  local infOn = self.config.logging.services.infOn

  if infOn then traceI("services | Creating session"..name.." timeout"..timeoutMs) end
  if self.services.enc == nil then return nil, BadNotConnected end

  local nonce
  local cert
  if self.services.enc.policy then
    nonce = self.services.enc.policy:genNonce(32)
    cert = self.services.enc.policy:getLocalCert()
  end

  local sessionParams
  if type(name) == 'string' then
    sessionParams = {
      clientDescription = {
          applicationUri = self.config.applicationUri,
          productUri = self.config.productUri,
          applicationName = {
            text = self.config.applicationName
          },
          applicationType = ua.Types.ApplicationType.Client,
          gatewayServerUri = nil,
          discoveryProfileUri = nil,
          discoveryUrls = {},
        },
      serverUri = nil,
      endpointUrl = self.endpointUrl,
      sessionName = name,
      clientNonce = nonce,
      clientCertificate = cert,
      requestedSessionTimeout = timeoutMs,
      maxResponseMessageSize = 0,
    }
  else
    sessionParams = {
      clientDescription = {
          applicationUri = name.applicationUri,
          productUri = name.productUri,
          applicationName = {
            text = name.applicationName
          },
          applicationType = name.applicationType,
          gatewayServerUri = nil,
          discoveryProfileUri = nil,
          discoveryUrls = {},
        },
      serverUri = name.serverUri,
      endpointUrl = name.endpointUrl,
      sessionName = name.sessionName,
      clientNonce = nonce,
      clientCertificate = cert,
      requestedSessionTimeout = name.sessionTimeout,
      maxResponseMessageSize = 0,
    }

    callback = timeoutMs
  end

  local request, err = self.services:createRequest(MessageId.CREATE_SESSION_REQUEST, sessionParams)
  if err then return nil, err end

  return self:execRequest(request, callback)
end

local function findTokenPolicyType(tokenPolicies, tokenType)
  for _,token in ipairs(tokenPolicies) do
    if token.tokenType == tokenType then
      return token
    end
  end
end

local function findTokenPolicyId(tokenPolicies, policyId)
  for _,token in ipairs(tokenPolicies) do
    if token.policyId == policyId then
      return token
    end
  end
end

local function encrypt(policy, password, nonce)
  if not policy then
    return password
  end

  local len = #password + #nonce
  local d = Q.new(len + 4)
  local decoder = Binary.Encoder.new(d)
  decoder:uint32(len)
  decoder:str(password)
  decoder:str(nonce)

  local data = tostring(d)
  local m,err = ba.crypto.encrypt(data, policy.remote.pem, {nopadding=false})
  if err then
    error(err)
  end
  return m
end

function C:activateSession(params, token, token2, callback)
  local infOn = self.config.logging.services.infOn
  local errOn = self.config.logging.services.errOn
  if infOn then traceI("services | Activating session") end
  if self.services.enc == nil then return nil, BadNotConnected end

  local tokenPolicy
  -- Called with manual parameters
  if type(params) == "table" then
    assert(token2 == nil)
    assert(callback == nil)
    callback = token
  -- Called with only callback
  elseif params == nil or type(params) == "function" then
    assert(token == nil)
    assert(token2 == nil)
    assert(callback == nil)
    callback = params
    params = nil
    tokenPolicy = findTokenPolicyType(self.session.userIdentityTokens, ua.Types.UserTokenType.Anonymous)
  else
    assert(type(params) == "string")
    tokenPolicy = findTokenPolicyId(self.session.userIdentityTokens, params)
    params = nil
  end

  local policy = self.services.enc.policy
  local activateParams = params
  if not activateParams then
    activateParams = {}
  end

  if not activateParams.clientSignature then
    if policy.secureMode == 2 or policy.secureMode == 3 then
      activateParams.clientSignature= {
        algorithm = policy.aSignatureUri,
        signature = policy:asymmetricSign(policy:getRemoteCert(), self.session.nonce)
      }
    elseif policy.secureMode ~= 1 then
      error("Invalid secure mode")
    end
  end

  if not activateParams.userIdentityToken then
    if not tokenPolicy then
      return nil, BadIdentityTokenRejected
    end

    local authPolicy
    if tokenPolicy.securityPolicyUri and tokenPolicy.securityPolicyUri ~= ua.Types.SecurityPolicy.None and self.session.serverCertificate then
      local encryption = securePolicy(self.config)
      authPolicy = encryption(tokenPolicy.securityPolicyUri)
      if tokenPolicy.tokenType == ua.Types.UserTokenType.Certificate then
        authPolicy:setLocalCertificate(token, token2)
      end
      if not self.session.serverCertificate then
        if errOn then traceE("services | Server didn't certificate sent for encrypting token") end
        return nil, BadIdentityTokenInvalid
      end
      authPolicy:setRemoteCertificate(self.session.serverCertificate)
      activateParams.userTokenSignature = {
        algorithm = authPolicy.aSignatureUri,
        signature = authPolicy:asymmetricSign(self.session.serverCertificate, self.session.nonce)
      }
    end

    if tokenPolicy.tokenType == ua.Types.UserTokenType.Anonymous then
      activateParams.userIdentityToken = tools.createAnonymousToken(tokenPolicy.policyId)
    elseif tokenPolicy.tokenType == ua.Types.UserTokenType.UserName then
      if type(token) ~= "string" or type(token2) ~= "string" then
        return nil, BadIdentityTokenInvalid
      end

      if authPolicy then
        token2 = encrypt(authPolicy, token2, self.session.nonce)
      end
      activateParams.userIdentityToken = tools.createUsernameToken(tokenPolicy.policyId, token, token2, authPolicy and authPolicy.aEncryptionAlgorithm)
    elseif tokenPolicy.tokenType == ua.Types.UserTokenType.Certificate then
      activateParams.userIdentityToken = tools.createX509Token(tokenPolicy.policyId, certificate.createCert(token).der)
    elseif tokenPolicy.tokenType == ua.Types.UserTokenType.IssuedToken then
      if authPolicy then
        token = encrypt(authPolicy, token, self.session.nonce)
      end
      activateParams.userIdentityToken = tools.createIssuedToken(tokenPolicy.policyId, token, authPolicy and authPolicy.aEncryptionAlgorithm)
    else
      error("invalid identity token")
    end
  end

  if not activateParams.userTokenSignature then
    activateParams.userTokenSignature = {}
  end
  if not activateParams.clientSignature then
    activateParams.clientSignature = {}
  end
  if not activateParams.locales then
    activateParams.locales = {"en"}
  end

  activateParams.clientSoftwareCertificates = {}

  local request, err = self.services:createRequest(MessageId.ACTIVATE_SESSION_REQUEST, activateParams)
  if err then return nil, err end

  return self:execRequest(request, callback)
end

local function browseParams(nodeId)
  return {
    nodeId = nodeId, -- nodeId we want to browse
    browseDirection = ua.Types.BrowseDirection.Forward,
    referenceTypeId = "i=33", -- HierarchicalReferences,
    nodeClassMask = ua.Types.NodeClass.Unspecified,
    resultMask = ua.Types.BrowseResultMask.All,
    includeSubtypes = true,
  }
end

function C:browse(params, callback)
  local infOn = self.config.logging.services.infOn
  if infOn then traceI("servcies | Browsing nodes") end
  if self.services.enc == nil then return nil, BadNotConnected end

  local request = {
    nodesToBrowse = {}
  }

  -- single node ID
  if type(params) == 'string' then
    request.nodesToBrowse[1] = browseParams(params)
  -- array of nodeIDs
  elseif type(params) == 'table' and params[1] ~= nil then
    for _,nodeId in ipairs(params) do
      table.insert(request.nodesToBrowse, browseParams(nodeId))
    end
  else
    -- manual
    request = params
  end

  if request.view == nil then
    request.view = {
      viewId = ua.NodeId.Null,
      timestamp = nil, -- not specified ~1600 year
      viewVersion = 0
    }
  end
  if request.requestedMaxReferencesPerNode == nil then
    request.requestedMaxReferencesPerNode = 1000
  end

  local err
  request, err = self.services:createRequest(MessageId.BROWSE_REQUEST, request)
  if err then return request, err end

  return self:execRequest(request, callback)
end

local function allAttributes(nodeId, attrs)
  for _,val in pairs(ua.Types.AttributeId) do
    attrs[val] = {nodeId=nodeId, attributeId=val}
  end
end

function C:read(params, callback)
  local infOn = self.config.logging.services.infOn
  if infOn then traceI("services | Reading attributes") end
  if self.services.enc == nil then return nil, BadNotConnected end

  local readParams = {}
  if type(params) == 'string' then
    local attrs = {}
    allAttributes(params, attrs)
    readParams.nodesToRead = attrs
  elseif type(params) == 'table' then
    if type(params[1]) == 'string' then
      local attrs = {}
      for _,nodeId in ipairs(params) do
        allAttributes(nodeId, attrs)
      end
      readParams.nodesToRead = attrs
    else
      readParams = params
    end
  end

  if readParams.maxAge == nil then
    readParams.maxAge = 0
  end

  if readParams.timestampsToReturn == nil then
    readParams.timestampsToReturn = 0
  end

  if readParams.nodesToRead then
    for _,v in pairs(readParams.nodesToRead) do
      if v.indexRange == nil then
        v.indexRange = ""
      end
      if v.dataEncoding == nil then
        v.dataEncoding = {ns=0}
      end
    end
  end

  local request, err = self.services:createRequest(MessageId.READ_REQUEST, readParams)
  if err then return nil, err end

  return self:execRequest(request, callback)
end

function C:write(nodes, callback)
  if self.services.enc == nil then return nil, BadNotConnected end
  local request, err = self.services:createRequest(MessageId.WRITE_REQUEST, nodes)
  if err then return nil, err end
  return self:execRequest(request, callback)
end


function C:addNodes(params, callback)
  if self.services.enc == nil then return nil, BadNotConnected end
  local request, err = self.services:createRequest(MessageId.ADD_NODES_REQUEST, params)
  if err then return nil, err end
  return self:execRequest(request, callback)
end

function C:createSubscription(sub, callback)
  if self.services.enc == nil then return nil, BadNotConnected end
  local request, err = self.services:createRequest(MessageId.CREATE_SUBSCRIPTION_REQUEST, sub)
  if err then return nil, err end
  return self:execRequest(request, callback)
end

function C:translateBrowsePaths(browsePaths, callback)
  if self.services.enc == nil then return nil, BadNotConnected end
  local request, err = self.services:createRequest(MessageId.TRANSLATE_BROWSE_PATHS_TO_NODE_IdS_REQUEST,browsePaths)
  if err then return nil, err end
  return self:execRequest(request, callback)
end

function C:closeSession(callback)
  if self.services.enc == nil then return nil, BadNotConnected end
  local infOn = self.config.logging.services.infOn
  if infOn then traceI("Closing session") end
  local closeSessionParams = {
    deleteSubscriptions = 1
  }

  self.userIdentityTokens = nil
  self.sessionNonce = nil

  local request,err = self.services:createRequest(MessageId.CLOSE_SESSION_REQUEST, closeSessionParams)
  if err then return nil, err end
  return self:execRequest(request, callback)
end

function C:closeSecureChannel(callback)
  local infOn = self.config.logging.services.infOn
  local errOn = self.config.logging.services.errOn

  -- Just send request: there is no CloseSecureChannelResponse.
  if infOn then traceI("services | Closing secure channel") end
  if self.services.enc == nil then return BadNotConnected end

  if self.channelTimer then
    if infOn then traceI("services | Stop channel refresh timer") end
    self.channelTimer:cancel()
    self.channelTimer = nil
  end

  local request, err = self.services:createRequest(MessageId.CLOSE_SECURE_CHANNEL_REQUEST)
  if err and errOn then traceI(fmt("services | Failed to close secure channel: %s", err)) end
  if err then return nil, err end
  return self:execRequest(request, callback)
end

function C:findServers(params, callback)
  if self.services.enc == nil then return nil, BadNotConnected end
  if type(params) == 'function' then
    callback = params
    params = nil
  end

  local request, err = self.services:createRequest(MessageId.FIND_SERVERS_REQUEST)
  if err then return nil, err end
  if params then
    request.endpointUrl = params.endpointUrl
  end
  request.localeIds = {}
  request.serverUris = {}

  return self:execRequest(request, callback)
end

function C:getEndpoints(params, callback)
  if self.services.enc == nil then return nil, BadNotConnected end
  if type(params) == 'function' then
    callback = params
    params = nil
  end
  local request, err = self.services:createRequest(MessageId.GET_ENDPOINTS_REQUEST, params)
  if err then return nil, err end
  request.localeIds = {}
  request.profileUris = {}

  return self:execRequest(request, callback)
end

local function NewUaClient(clientConfig, sock)
  if clientConfig == nil then
    error("no OPCUA configuration")
  end

  local uaConfig = require("opcua.config")
  local err = uaConfig.client(clientConfig)
  if err ~= nil then
    error("Configuration error: "..err)
  end

  local c = {
    config = clientConfig,
    requests = {},
    services = require("opcua.binary.client").new(clientConfig, sock),

    -- endpointUrl
    -- userIdentityTokens
    -- channelNonce
    -- sessionNonce
  }
  setmetatable(c, C)
  return c
end

return {new=NewUaClient}
