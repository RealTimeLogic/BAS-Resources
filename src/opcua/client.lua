local ua = require("opcua.api")
local createCert = ua.crypto.createCert
local compat = require("opcua.compat")
local securePolicy = require("opcua.binary.crypto.policy")
local Q = require("opcua.binary.queue")
local BinaryEncoder = require("opcua.binary.encoder")
local MessageId = require("opcua.binary.message_id")
local tools = ua.Tools

local traceI = ua.trace.inf
local traceD = ua.trace.dbg
local traceE = ua.trace.err
local fmt = string.format

local BadNotConnected = ua.StatusCode.BadNotConnected
local BadSessionIdInvalid = ua.StatusCode.BadSessionIdInvalid
local BadIdentityTokenRejected = ua.StatusCode.BadIdentityTokenRejected
local BadIdentityTokenInvalid = ua.StatusCode.BadIdentityTokenInvalid
local BadSecureChannelClosed = ua.StatusCode.BadSecureChannelClosed

local C={} -- OpcUa Client
C.__index=C

local function syncExecRequest(self, request)
  local dbgOn = self.config.logging.services.dbgOn
  if dbgOn then ua.Tools.printTable("services | execRequest", request, traceD) end

  local suc, err = pcall(self.services.sendMessage, self.services, request, true)
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

  local defCallback
  local coSock = compat.socket.getsock()
  if not coSock and not self.hasSecureChannel and not callback then
    return syncExecRequest(self, request)
  end

  if callback == nil then
    defCallback = function(m, e)
      if dbgOn then traceD("default cosock callback called") end
      coSock:enable(m, e)
    end
    callback = defCallback
  end

  self.requests[request.RequestHeader.RequestHandle] = callback
  local suc, err = pcall(self.services.sendMessage, self.services, request)
  if not suc then
    self.requests[request.RequestHeader.RequestHandle] = nil
    return self:processResponse(nil, err)
  end

  if coSock and defCallback then
    if dbgOn then traceD("waiting default cosock callback") end
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
    local callback = self.requests[resp.ResponseHeader.RequestHandle]
    if callback then
      if resp.ResponseHeader.ServiceResult ~= 0 then
        return callback(nil, resp.ResponseHeader.ServiceResult)
      else
        return callback(resp, err)
      end
    else
      error("unknown response handle: "..resp.ResponseHeader.RequestHandle)
    end
  end
end

local function syncProcessResp(_, resp, err)
  if resp and resp.ResponseHeader.ServiceResult ~= 0 then
    return nil, resp.ResponseHeader.ServiceResult
  end

  return resp, err
end

function C:connect(endpointUrl, transportProfile, connectCallback)
  local config = self.config
  local infOn = config.logging.services.infOn

  if type(transportProfile) == "function" then
    assert(connectCallback == nil)
    connectCallback = transportProfile
    transportProfile = nil
  end

  -- check url is valid before entering cosockets: we might hang there
  -- because of parsing URL is perofmed before first network call.
  local url,err = ua.parseUrl(endpointUrl)
  if err then
    error(err)
  end
  self.endpointUrl = endpointUrl

  if url.scheme == "opc.tcp" then
    if transportProfile == nil then
      transportProfile = ua.Types.TranportProfileUri.TcpBinary
    end

    local binary = require("opcua.binary.client")
    self.services = binary.new(self.config, self.sock, self.model)
    self.hasSecureChannel = true
  elseif
    url.scheme == "opc.http"  or url.scheme == "http" or
    url.scheme == "opc.https" or url.scheme == "https"
  then
    if transportProfile == nil then
      transportProfile = ua.Types.TranportProfileUri.HttpsBinary
    end

    self.hasSecureChannel = false
    local http = require("opcua.binary.client_http")
    self.services = http.new(self.config, self.sock, self.model)
  else
    error("OPCUA: unsupported scheme: "..url.scheme)
  end

  if config.cosocketMode == true then
    self.execRequest = coExecRequest
    self.processResp = coProcessResp
    local responseCallback = function(msg, e)
      self:processResponse(msg, e)
    end

    self.services:coRun(endpointUrl, transportProfile, connectCallback, responseCallback)
  else
    if connectCallback then
      error("OPCUA: can't use callbacks in non-cosocket mode")
    end

    if infOn then traceI(fmt("services | Connecting to endpoint '%s' in synchronous mode", endpointUrl)) end
    self.execRequest = syncExecRequest
    self.processResp = syncProcessResp
    return self.services:connectServer(endpointUrl, transportProfile)
  end
end

function C:setEnpointUrl(endpointUrl)
  self.endpointUrl = endpointUrl
end

function C:disconnect()
  local infOn = self.config.logging.services.infOn

  self.endpointUrl = nil
  self.channelNonce = nil
  self.userIdentityTokens = nil
  self.sessionNonce = nil

  if not self:connected() then
    return nil, BadNotConnected
  end

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
    local typeId = msg.TypeId
    response = msg.Body
    if response.ResponseHeader.ServiceResult == 0 then
      if typeId == MessageId.OPEN_SECURE_CHANNEL_RESPONSE then
        if infOn then traceI("services | received OPEN_SECURE_CHANNEL_RESPONSE") end
        err = self:processOpenSecureChannelResponse(response)
      elseif typeId == MessageId.CREATE_SESSION_RESPONSE then
        err = self:processCreateSessionResponse(response)
      elseif typeId == MessageId.ACTIVATE_SESSION_RESPONSE then
        err = self:processActivateSessionResponse(response)
      end
    end
  end

  return self:processResp(response, err)
end

function C:processOpenSecureChannelResponse(response)
  local infOn = self.config.logging.services.infOn

  local serverNonce = response.ServerNonce

  self.services:setSecureMode(self.securityMode)
  self.services:setNonces(self.channelNonce, serverNonce)

  if infOn then traceI(fmt("services | newChannelID %s, tokenID=%s", response.SecurityToken.ChannelId, response.SecurityToken.TokenId)) end

  self.services.enc:setChannelId(response.SecurityToken.ChannelId)
  self.services.enc:setTokenId(response.SecurityToken.TokenId)
  local timeoutMs = response.SecurityToken.RevisedLifetime
  self.timeoutMs = timeoutMs
  if infOn then traceI(fmt("services | secure channel token lifetime %s ms", timeoutMs)) end
  timeoutMs = timeoutMs * 3 / 4
  if self.channelTimer == nil then
    self.channelTimer = compat.timer(function()
      self.needRenewChannel = true
      return true
    end)
    if infOn then traceI(fmt("services | set timer for renewing secure channel: %s ms", timeoutMs)) end
    self.channelTimer:set(timeoutMs)
  else
    if infOn then traceI(fmt("services | reset timer for renewing secure channel: %s ms", timeoutMs)) end
    self.channelTimer:reset(timeoutMs)
  end
end

function C:processCreateSessionResponse(response)
  local infOn = self.config.logging.services.infOn
  if infOn then
    traceI("services | received CREATE_SESSION_RESPONSE SessionId='"..response.SessionId..
          "' MaxRequestMessageSize="..response.MaxRequestMessageSize..
          " AuthenticationToken='"..response.AuthenticationToken..
          "' RevisedSessionTimeout="..response.RevisedSessionTimeout)
  end

  -- search current policy
  for _,endpoint in ipairs(response.ServerEndpoints) do
    if
      endpoint.EndpointUrl == self.endpointUrl and
      endpoint.SecurityPolicyUri == self.securityPolicyUri and
      endpoint.SecurityMode == self.securityMode
    then
      self.services.sessionId = response.SessionId
      self.services.sessionAuthToken = response.AuthenticationToken

      self.session = {
        userIdentityTokens = endpoint.UserIdentityTokens,
        serverCertificate = endpoint.ServerCertificate,
        nonce = response.ServerNonce
      }
      break
    end
  end

  if not self.session then
    return BadSessionIdInvalid
  end
end

function C:processActivateSessionResponse(response)
  local infOn = self.config.logging.services.infOn
  if infOn then
    traceI("services | received ACTIVATE_SESSION_RESPONSE")
  end

  if response.ResponseHeader.ServiceResult ~= 0 then
    return
  end

  self.session.nonce = response.ServerNonce
end

function C:openSecureChannel(timeoutMs, securityPolicyUri, securityMode, remoteCert, callback)
  assert(type(securityPolicyUri) == 'string', "invalid policy uri")
  assert(type(securityMode) == 'number', "invalid security mode")

  if type(remoteCert) == "function" then
    assert(callback == nil)
    callback = remoteCert
    remoteCert = nil
  end

  local infOn = self.config.logging.services.infOn
  if infOn then traceI("services | Opening secure channel") end
  if not self:connected() then
    return nil, BadNotConnected
  end

  self.securityPolicyUri = securityPolicyUri
  self.securityMode = securityMode
  self.remoteCert = remoteCert
  self.policy = self.security(securityPolicyUri)
  self.policy:setRemoteCertificate(remoteCert)
  self.policy:setSecureMode(securityMode)

  self.services:setupPolicy(securityPolicyUri, remoteCert)
  self.services:setSecureMode(securityMode)

  if not self.hasSecureChannel then
    if callback then
      callback()
    end
    return
  end

  self.channelNonce = self.policy:genNonce()

  local request, err = self.services:createRequest(MessageId.OPEN_SECURE_CHANNEL_REQUEST)
  if err then return nil, err end
  request.ClientProtocolVersion = 0
  request.RequestType = ua.Types.SecurityTokenRequestType.Issue
  request.SecurityMode = securityMode
  request.ClientNonce = self.channelNonce
  request.RequestedLifetime = timeoutMs

  return self:execRequest(request, callback)
end

function C:renewSecureChannel(timeoutMs, callback)
  local infOn = self.config.logging.services.infOn
  if infOn then traceI("services | Renew secure channel") end
  if not self:connected() then
    return nil, BadNotConnected
  end

  if self.policy then
    self.channelNonce = self.policy:genNonce()
  end

  local request, err = self.services:createRequest(MessageId.OPEN_SECURE_CHANNEL_REQUEST)
  if err then return nil, err end

  request.ClientProtocolVersion = 0
  request.RequestType = ua.Types.SecurityTokenRequestType.Renew
  request.SecurityMode = self.securityMode
  request.ClientNonce = self.channelNonce
  request.RequestedLifetime = timeoutMs

  return self:execRequest(request, callback)
end

function C:checkSecureChannel()
  if not self.needRenewChannel then
    return
  end

  local infOn = self.config.logging.services.infOn
  local errOn = self.config.logging.services.errOn

  if infOn then traceI("services | renewing secure channel token") end
  local _, err = self:renewSecureChannel(self.timeoutMs)
  if err ~= nil then
    if errOn then traceE(fmt("Failed to renew secure channel: %s", err)) end
    return err
  end

  self.needRenewChannel = false
end


function C:createSession(name, timeoutMs, callback)
  local infOn = self.config.logging.services.infOn

  if infOn then traceI(fmt("services | Creating session '%s' lifetime '%s' ms", name, timeoutMs)) end

  if not self:connected() then
    return nil, BadNotConnected
  end

  local err = self:checkSecureChannel()
  if err then
    return nil, err
  end

  local nonce = self.policy:genNonce(32)
  local cert = self.policy:getLocalCert()

  local sessionParams
  if type(name) == 'string' then
    sessionParams = {
      ClientDescription = {
          ApplicationUri = self.config.applicationUri,
          ProductUri = self.config.productUri,
          ApplicationName = {
            Text = self.config.applicationName
          },
          ApplicationType = ua.Types.ApplicationType.Client,
          GatewayServerUri = nil,
          DiscoveryProfileUri = nil,
          DiscoveryUrls = {},
        },
      ServerUri = nil,
      EndpointUrl = self.endpointUrl,
      SessionName = name,
      ClientNonce = nonce,
      ClientCertificate = cert,
      RequestedSessionTimeout = timeoutMs,
      MaxResponseMessageSize = 0,
    }
  else
    sessionParams = {
      ClientDescription = {
          ApplicationUri = name.ApplicationUri,
          ProductUri = name.ProductUri,
          ApplicationName = {
            Text = name.ApplicationName
          },
          ApplicationType = name.ApplicationType,
          GatewayServerUri = nil,
          DiscoveryProfileUri = nil,
          DiscoveryUrls = {},
        },
      ServerUri = name.ServerUri,
      EndpointUrl = name.EndpointUrl,
      SessionName = name.SessionName,
      ClientNonce = nonce,
      ClientCertificate = cert,
      RequestedSessionTimeout = name.SessionTimeout,
      MaxResponseMessageSize = 0,
    }

    callback = timeoutMs
  end

  self.sessionNonce = nonce
  local request
  request, err = self.services:createRequest(MessageId.CREATE_SESSION_REQUEST, sessionParams)
  if err then return nil, err end

  return self:execRequest(request, callback)
end

local function findTokenPolicyType(tokenPolicies, tokenType)
  for _,token in ipairs(tokenPolicies) do
    if token.TokenType == tokenType then
      return token
    end
  end
end

local function findTokenPolicyId(tokenPolicies, policyId)
  for _,token in ipairs(tokenPolicies) do
    if token.PolicyId == policyId then
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
  local encoder = BinaryEncoder.new(d)
  encoder:uint32(len)
  encoder:array(password)
  encoder:array(nonce)

  local data = tostring(d)
  local m,err = ua.crypto.encrypt(data, policy.remote, policy.params.rsaParams)
  if err then
    error(err)
  end
  return m
end

function C:activateSession(params, token, token2, callback)
  local infOn = self.config.logging.services.infOn
  local errOn = self.config.logging.services.errOn
  if infOn then traceI("services | Activating session") end

  if not self:connected() then
    return nil, BadNotConnected
  end

  if self.session == nil then
    return nil, BadSessionIdInvalid
  end

  local err = self:checkSecureChannel()
  if err then
    return nil, err
  end

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

  local activateParams = params
  if not activateParams then
    activateParams = {}
  end

  if not activateParams.ClientSignature then
    local policy = self.policy
    if policy.secureMode == 2 or policy.secureMode == 3 then
      activateParams.ClientSignature= {
        Algorithm = policy.aSignatureUri,
        Signature = policy:asymmetricSign(policy:getRemoteCert(), self.session.nonce)
      }
    elseif policy.secureMode ~= 1 then
      error("Invalid secure mode")
    end
  end

  if not activateParams.UserIdentityToken then
    if not tokenPolicy then
      return nil, BadIdentityTokenRejected
    end

    local authPolicy
    if tokenPolicy.SecurityPolicyUri and tokenPolicy.SecurityPolicyUri ~= ua.Types.SecurityPolicy.None and self.session.serverCertificate then
      authPolicy = self.security(tokenPolicy.SecurityPolicyUri)
      if tokenPolicy.TokenType == ua.Types.UserTokenType.Certificate then
        authPolicy:setLocalCertificate(token, token2)
      end
      if not self.session.serverCertificate then
        if errOn then traceE("services | Server didn't certificate sent for encrypting token") end
        return nil, BadIdentityTokenInvalid
      end
      authPolicy:setRemoteCertificate(self.session.serverCertificate)
      activateParams.UserTokenSignature = {
        Algorithm = authPolicy.aSignatureUri,
        Signature = authPolicy:asymmetricSign(self.session.serverCertificate, self.session.nonce)
      }
    end

    if tokenPolicy.TokenType == ua.Types.UserTokenType.Anonymous then
      activateParams.UserIdentityToken = tools.createAnonymousToken(tokenPolicy.PolicyId)
    elseif tokenPolicy.TokenType == ua.Types.UserTokenType.UserName then
      if type(token) ~= "string" or type(token2) ~= "string" then
        return nil, BadIdentityTokenInvalid
      end

      if authPolicy then
        token2 = encrypt(authPolicy, token2, self.session.nonce)
      end
      activateParams.UserIdentityToken = tools.createUsernameToken(tokenPolicy.PolicyId, token, token2, authPolicy and authPolicy.aEncryptionAlgorithm)
    elseif tokenPolicy.TokenType == ua.Types.UserTokenType.Certificate then
      activateParams.UserIdentityToken = tools.createX509Token(tokenPolicy.PolicyId, createCert(token, self.config.io).der)
    elseif tokenPolicy.TokenType == ua.Types.UserTokenType.IssuedToken then
      if authPolicy then
        token = encrypt(authPolicy, token, self.session.nonce)
      end
      activateParams.UserIdentityToken = tools.createIssuedToken(tokenPolicy.PolicyId, token, authPolicy and authPolicy.aEncryptionAlgorithm)
    else
      error("invalid identity token")
    end
  end

  if not activateParams.UserTokenSignature then
    activateParams.UserTokenSignature = {}
  end
  if not activateParams.ClientSignature then
    activateParams.ClientSignature = {}
  end
  if not activateParams.Locales then
    activateParams.Locales = {"en"}
  end

  activateParams.ClientSoftwareCertificates = {}

  local request
  request, err = self.services:createRequest(MessageId.ACTIVATE_SESSION_REQUEST, activateParams)
  if err then return nil, err end

  return self:execRequest(request, callback)
end

local function browseParams(nodeId)
  return {
    NodeId = nodeId, -- nodeId we want to browse
    BrowseDirection = ua.Types.BrowseDirection.Forward,
    ReferenceTypeId = "i=33", -- HierarchicalReferences,
    NodeClassMask = ua.Types.NodeClass.Unspecified,
    ResultMask = ua.Types.BrowseResultMask.All,
    IncludeSubtypes = true,
  }
end

function C:browse(params, callback)
  local infOn = self.config.logging.services.infOn
  if infOn then traceI("servcies | Browsing nodes") end

  if not self:connected() then
    return nil, BadNotConnected
  end

  local err = self:checkSecureChannel()
  if err then
    return nil, err
  end

  local request = {
    NodesToBrowse = {}
  }

  -- single node ID
  if type(params) == 'string' then
    request.NodesToBrowse[1] = browseParams(params)
  -- array of nodeIDs
  elseif type(params) == 'table' and params[1] ~= nil then
    for _,nodeId in ipairs(params) do
      table.insert(request.NodesToBrowse, browseParams(nodeId))
    end
  else
    -- manual
    request = params
  end

  if request.View == nil then
    request.View = {
      ViewId = ua.NodeId.Null,
      Timestamp = nil, -- not specified ~1600 year
      ViewVersion = 0
    }
  end
  if request.RequestedMaxReferencesPerNode == nil then
    request.RequestedMaxReferencesPerNode = 1000
  end

  request, err = self.services:createRequest(MessageId.BROWSE_REQUEST, request)
  if err then return request, err end

  return self:execRequest(request, callback)
end

local function allAttributes(nodeId, attrs)
  for _,val in pairs(ua.Types.AttributeId) do
    attrs[val] = {NodeId=nodeId, AttributeId=val}
  end
end

function C:read(params, callback)
  local infOn = self.config.logging.services.infOn
  if infOn then traceI("services | Reading attributes") end

  if not self:connected() then
    return nil, BadNotConnected
  end

  local err = self:checkSecureChannel()
  if err then
    return nil, err
  end

  local readParams = {}
  if type(params) == 'string' then
    local attrs = {}
    allAttributes(params, attrs)
    readParams.NodesToRead = attrs
  elseif type(params) == 'table' then
    if type(params[1]) == 'string' then
      local attrs = {}
      for _,nodeId in ipairs(params) do
        allAttributes(nodeId, attrs)
      end
      readParams.NodesToRead = attrs
    else
      readParams = params
    end
  end

  if readParams.MaxAge == nil then
    readParams.MaxAge = 0
  end

  if readParams.TimestampsToReturn == nil then
    readParams.TimestampsToReturn = 0
  end

  if readParams.NodesToRead then
    for _,v in pairs(readParams.NodesToRead) do
      if v.IndexRange == nil then
        v.IndexRange = ""
      end
      if v.DataEncoding == nil then
        v.DataEncoding = {ns=0}
      end
    end
  end

  local request
  request, err = self.services:createRequest(MessageId.READ_REQUEST, readParams)
  if err then return nil, err end

  return self:execRequest(request, callback)
end

function C:write(nodes, callback)
  if not self:connected() then
    return nil, BadNotConnected
  end

  local err = self:checkSecureChannel()
  if err then
    return nil, err
  end

  local request
  request, err = self.services:createRequest(MessageId.WRITE_REQUEST, nodes)
  if err then return nil, err end
  return self:execRequest(request, callback)
end


function C:addNodes(params, callback)
  if not self:connected() then
    return nil, BadNotConnected
  end

  local err = self:checkSecureChannel()
  if err then
    return nil, err
  end

  local request
  request, err = self.services:createRequest(MessageId.ADD_NODES_REQUEST, params)
  if err then return nil, err end
  return self:execRequest(request, callback)
end

function C:createSubscription(sub, callback)
  if not self:connected() then
    return nil, BadNotConnected
  end

  local err = self:checkSecureChannel()
  if err then
    return nil, err
  end

  local request
  request, err = self.services:createRequest(MessageId.CREATE_SUBSCRIPTION_REQUEST, sub)
  if err then return nil, err end
  return self:execRequest(request, callback)
end

function C:translateBrowsePaths(browsePaths, callback)
  if not self:connected() then
    return nil, BadNotConnected
  end

  local err = self:checkSecureChannel()
  if err then
    return nil, err
  end

  local request
  request, err = self.services:createRequest(MessageId.TRANSLATE_BROWSE_PATHS_TO_NODE_IdS_REQUEST,browsePaths)
  if err then return nil, err end
  return self:execRequest(request, callback)
end

function C:closeSession(callback)
  local infOn = self.config.logging.services.infOn
  if infOn then traceI("Closing session") end

  if not self:connected() then
    return nil, BadNotConnected
  end

  local closeSessionParams = {
    DeleteSubscriptions = true
  }

  local err = self:checkSecureChannel()
  if err then
    return nil, err
  end

  self.userIdentityTokens = nil
  self.sessionNonce = nil

  local request
  request,err = self.services:createRequest(MessageId.CLOSE_SESSION_REQUEST, closeSessionParams)
  if err then return nil, err end
  return self:execRequest(request, callback)
end

function C:closeSecureChannel(callback)
  local infOn = self.config.logging.services.infOn
  local errOn = self.config.logging.services.errOn

  -- Just send request: there is no CloseSecureChannelResponse.
  if infOn then traceI("services | Closing secure channel") end
  if not self:connected() then
    return nil, BadNotConnected
  end

  if not self.hasSecureChannel then
    if callback then
      callback(nil, BadSecureChannelClosed)
      return
    else
      return nil, BadSecureChannelClosed
    end
  end

  if self.channelTimer then
    if infOn then traceI("services | Stop channel refresh timer") end
    self.channelTimer:cancel()
    self.channelTimer = nil
    self.needRenewChannel = false
  end

  local request, err = self.services:createRequest(MessageId.CLOSE_SECURE_CHANNEL_REQUEST)
  if err and errOn then traceI(fmt("services | Failed to close secure channel: %s", err)) end
  if err then return nil, err end
  return self:execRequest(request, callback)
end

function C:findServers(params, callback)
  if not self:connected() then
    return nil, BadNotConnected
  end

  if type(params) == 'function' then
    callback = params
    params = nil
  end

  local err = self:checkSecureChannel()
  if err then
    return nil, err
  end

  local request
  request, err = self.services:createRequest(MessageId.FIND_SERVERS_REQUEST)
  if err then return nil, err end
  if params then
    request.EndpointUrl = params.EndpointUrl
  end
  request.LocaleIds = {}
  request.ServerUris = {}

  return self:execRequest(request, callback)
end

function C:getEndpoints(params, callback)

  if not self:connected() then
    return nil, BadNotConnected
  end

  if type(params) == 'function' then
    callback = params
    params = nil
  end

  local err = self:checkSecureChannel()
  if err then
    return nil, err
  end

  local request
  request, err = self.services:createRequest(MessageId.GET_ENDPOINTS_REQUEST, params)
  if err then return nil, err end
  request.LocaleIds = {}
  request.ProfileUris = {}

  return self:execRequest(request, callback)
end

function C:connected()
  if self.services == nil then
    return false
  end
  return self.services:connected()
end

local function NewUaClient(clientConfig, sock, model)
  if clientConfig == nil then
    error("no OPCUA configuration")
  end
  local uaConfig = require("opcua.config")
  local err = uaConfig.client(clientConfig)
  if err ~= nil then
    error("Configuration error: "..err)
  end

  if model == nil then
    model = require("opcua.model.import").getBaseModel(clientConfig)
  end

  local c = {
    needRenewChannel = false,
    config = clientConfig,
    security = securePolicy(clientConfig),
    requests = {},
    sock = sock,
    model = model,
    hasSecureChannel = true,

    -- endpointUrl
    -- userIdentityTokens
    -- channelNonce
    -- sessionNonce
  }
  setmetatable(c, C)
  return c
end

return {new=NewUaClient}
