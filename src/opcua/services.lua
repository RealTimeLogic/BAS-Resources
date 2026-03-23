local tools = require("opcua.tools")
local compat = require("opcua.compat")
local crypto = require("opcua.crypto").crypto
local securePolicy = require("opcua.binary.crypto.policy")
local Q = require("opcua.binary.queue")
local BinaryDecoder = require("opcua.binary.decoder")
local srvObject = require("opcua.server_object")
local trace = require("opcua.trace")
local const = require("opcua.const")
local version = require("opcua.version")
local s = require("opcua.status_codes")
local NodeId = require("opcua.node_id")

local AttributeId = const.AttributeId
local NodeClass = const.NodeClass

local traceD = trace.dbg
local traceI = trace.inf
local traceE = trace.err

local fmt = string.format
local tins = table.insert

local HasSubtype = "i=45"
local HasTypeDefinition = "i=40"

local Good = s.Good
local BadInvalidArgument = s.BadInvalidArgument
local BadNodeIdUnknown = s.BadNodeIdUnknown
local BadNodeClassInvalid = s.BadNodeClassInvalid
local BadBrowseDirectionInvalid = s.BadBrowseDirectionInvalid
local BadReferenceTypeIdInvalid =  s.BadReferenceTypeIdInvalid
local BadNothingToDo = s.BadNothingToDo
local BadNoMatch = s.BadNoMatch
local BadParentNodeIdInvalid = s.BadParentNodeIdInvalid
local BadTypeDefinitionInvalid = s.BadTypeDefinitionInvalid
local BadServiceUnsupported = s.BadServiceUnsupported
local BadInternalError = s.BadInternalError
local BadUserAccessDenied = s.BadUserAccessDenied
local BadIdentityTokenRejected = s.BadIdentityTokenRejected
local BadIdentityTokenInvalid = s.BadIdentityTokenInvalid
local BadApplicationSignatureInvalid = s.BadApplicationSignatureInvalid
local BadUserSignatureInvalid = s.BadUserSignatureInvalid
local BadTooManySessions = s.BadTooManySessions
local BadSessionClosed = s.BadSessionClosed
local BadRequestHeaderInvalid = s.BadRequestHeaderInvalid
local BadSessionNotActivated = s.BadSessionNotActivated
local BadNodeIdInvalid = s.BadNodeIdInvalid

local Svc = {}
Svc.__index = Svc

function Svc:start()
  self.nodeset = self.model.Nodes
  self.srvObject = srvObject()
  return self.srvObject:start(self.config, self)
end

function Svc.hello(--[[endpointUrl]])
--  self.EndpointUrl = endpointUrl
end

function Svc:openSecureChannel(_, channel)
  local infOn = self.trace.infOn
  if infOn then traceI(fmt("Services:openSecureChannel(ch:%s)", channel.channelId)) end
end

function Svc:closeSecureChannel(_, channel)
  local dbgOn = self.trace.dbgOn
  if dbgOn then traceD(fmt("Services:closeSecureChannel(ch:%s)", channel.channelId)) end

  local channelId = channel.channelId
  local session = self.sessions[channelId]
  if session then
    session.channelId = nil
    if dbgOn then traceD(fmt("Services:closeSecureChannel(ch:%s) Session '%s' deactivated", channelId, session.sessionId)) end
  end
end

function Svc:getServerDescription()
  local dbgOn = self.trace.dbgOn
  if dbgOn then traceD("Services:GetServerDescription | ") end

  local endpointUrls = {}
  for _,endpoint in ipairs(self.config.endpoints) do
    tins(endpointUrls, endpoint.endpointUrl)
  end

  return {
    ApplicationUri = self.config.applicationUri,
    ApplicationName = {
      Locale = "en-US",
      Text = self.config.applicationName
    },

    ProductUri = version.ProductUri,
    ApplicationType = const.ApplicationType.Server,
    GatewayServerUri = nil,
    DiscoveryProfileUri = const.ServerProfile.NanoEmbedded2017,
    DiscoveryUrls = endpointUrls
  }
end


function Svc:findServers(req, channel)
  local dbgOn = self.trace.dbgOn

  if dbgOn then traceD("Services:findServers | ") end
  -- Session-less call
  -- if session present then check and touch session
  if req.RequestHeader.AuthenticationToken ~= "i=0" then
    self:checkSession(req, channel)
  end

  return {Servers = {self:getServerDescription()}}
end

function Svc:addEndpointDescriptions(endpointUrl, transportProfileUri, policy, endpoints)
  local certificate = policy.certificate or self.config.certificate
  local der = certificate and crypto.createCert(certificate, self.config.io).der
  local tokenPolicies = {}

  for _,p in ipairs(self.config.userIdentityTokens) do
    tins(tokenPolicies, {PolicyId=p.policyId, SecurityPolicyUri=p.securityPolicyUri, TokenType=p.tokenType, IssuedTokenType=p.issuedTokenType, IssuerEndpointUrl=p.issuerEndpointUrl})
  end

  if string.find(endpointUrl, "http://") or string.find(endpointUrl, "https://") then
    local endpoint = {
      EndpointUrl = endpointUrl,
      ServerCertificate = der,
      SecurityMode = const.MessageSecurityMode.None,
      SecurityPolicyUri = const.SecurityPolicy.None,
      Server = self:getServerDescription(),
      UserIdentityTokens = tokenPolicies,
      TransportProfileUri = transportProfileUri,
      SecurityLevel = 0 -- TODO
    }

    tins(endpoints, endpoint)
  else
    for _,mode in ipairs(policy.securityMode) do
      local endpoint = {
        EndpointUrl = endpointUrl,
        ServerCertificate = der,
        SecurityMode = mode,
        SecurityPolicyUri = policy.securityPolicyUri,
        Server = self:getServerDescription(),
        UserIdentityTokens = tokenPolicies,
        TransportProfileUri = transportProfileUri,
        SecurityLevel = 0 -- TODO
      }

      tins(endpoints, endpoint)
    end
  end
end

function Svc:listEndpoints()
  local endpoints = {}
  for _,endpoint in ipairs(self.config.endpoints) do
    local endpointUrl = endpoint.endpointUrl
    if string.find(endpointUrl, "opc.tcp") == 1 then
      for _,policy in ipairs(self.config.securePolicies) do
        self:addEndpointDescriptions(endpoint.endpointUrl, const.TranportProfileUri.TcpBinary, policy, endpoints)
      end
    elseif string.find(endpointUrl, "http://") or string.find(endpointUrl, "https://") then
      local policy = {}
      self:addEndpointDescriptions(endpoint.endpointUrl, const.TranportProfileUri.HttpsBinary, policy, endpoints)
      self:addEndpointDescriptions(endpoint.endpointUrl, const.TranportProfileUri.HttpsJson, policy, endpoints)
    else
      error("Unsupported endpoint uri scheme: ".. endpointUrl)
    end

  end
  return endpoints
end

function Svc:getEndpoints(req, channel)
  local dbgOn = self.trace.dbgOn
  if dbgOn then traceD("Services:getEndpoints | ") end

  -- Session-less call might be called without session
  -- if session present then check and touch session
  if req.RequestHeader.AuthenticationToken ~= "i=0" then
    self:checkSession(req, channel)
  end

  return {Endpoints=self:listEndpoints()}
end


local sessionsNum = math.floor(os.time())
local function getSessionNum()
  sessionsNum = sessionsNum + 1
  return sessionsNum
end

function Svc:createSession(req, channel)
  assert(channel, "CreateSession call require to pass a channel")

  local errOn = self.trace.errOn
  local infOn = self.trace.infOn
  local dbgOn = self.trace.dbgOn

  if dbgOn then traceD("Services:createSession | ") end

  local session = self.sessions[channel.channelId]
  if session then
    if errOn then traceE(fmt("Services:createSession(ch:%s) | Already has session '%s'.", channel.channelId, session.sessionId)) end
    error(BadTooManySessions)
  end

  local policy = channel:getLocalPolicy()
  policy:setRemoteCertificate(req.ClientCertificate)
  local sessionTimeoutSecs = math.max(30000, req.RequestedSessionTimeout) / 1000
  local curTime = os.time()
  session = {
    sessionId = "ns=1;i="..getSessionNum(),
    activated = false,
    policy = policy,
    channelId = channel.channelId, -- this is nil for HTTP
    authenticationToken = "ns=1;s="..getSessionNum(),
    nonce = policy:genNonce(32),
    sessionExpirationTime = curTime + sessionTimeoutSecs,
    sessionTimeoutSecs = sessionTimeoutSecs,
  }

  local resp = {}
  resp.SessionId = session.sessionId
  resp.AuthenticationToken = session.authenticationToken
  resp.RevisedSessionTimeout = sessionTimeoutSecs * 1000
  resp.ServerNonce = session.nonce
  resp.ServerCertificate = policy:getLocalCert()
  resp.MaxRequestMessageSize = 0
  resp.ServerEndpoints = self:listEndpoints()
  resp.ServerSoftwareCertificates = nil

  if policy.uri ~= const.SecurityPolicy.None then
    resp.ServerSignature = {
      Algorithm = policy.aSignatureUri,
      Signature = policy:asymmetricSign(req.ClientCertificate..req.ClientNonce)
    }
  else
    resp.ServerSignature = {}
  end

  self.sessions[session.authenticationToken] = session
  if session.channelId then
    self.sessions[session.channelId] = session
  end

  self:startSessionCleanup()

  if infOn then traceI(fmt("Services:CreateSession(ch:%s) | Created session '%s'  expiration time '%s'", channel.channelId, session.sessionId, session.sessionExpirationTime)) end

  return resp
end

local function decrypt(policy, data)
  if not policy then
    return data
  end
  local m,err = crypto.decrypt(data, policy.key, policy.params.rsaParams)
  if err then
    traceE(fmt("failed to decrypt token len #%s bytes: %s", #data, err))
    error(BadIdentityTokenInvalid)
  end
  local d = Q.new(#m)
  d:pushBack(m)
  local decoder = BinaryDecoder.new(d)
  local l = decoder:uint32()
  local token = decoder:array(l - 32)
  -- local nonce = decoder:array(32) -- TODO: check nonce

  return token
end


local function checkSignature(policy, signature, ...)
  if not signature or not signature.Signature then
    return
  end

  if signature.Algorithm ~= policy.aSignatureUri then
    return
  end

  if not policy:asymmetricVerify(signature.Signature, ...) then
    return
  end

  return true
end

local function allowAll()
  return true
end

function Svc:activateSession(req, channel)
  local errOn = self.trace.errOn
  local infOn = self.trace.infOn
  local dbgOn = self.trace.dbgOn

  if dbgOn then traceD(fmt("Services:activateSession |")) end

  -- if channel and channel.channelId == nil then
  --   error(BadSecureChannelIdInvalid)
  -- end

  local session = self.sessions[req.RequestHeader.AuthenticationToken]
  if not session then
    if infOn then traceI(fmt("Services:activateSession | Session with auth token '%s' not found", req.RequestHeader.AuthenticationToken)) end
    error(BadSessionClosed)
  end
  local sessionId = session.sessionId

  local policy = session.policy
  if policy.secureMode == 2 or policy.secureMode == 3 then
    if not checkSignature(policy, req.ClientSignature, policy.certificate.der, session.nonce) then
      if errOn then traceE(fmt("Services:activateSession(%s) | Invalid client signature", sessionId)) end
      error(BadApplicationSignatureInvalid)
    end
  end

  local authenticate = self.config.authenticate or allowAll
  if dbgOn then traceD(fmt("Services:activateSession(%s) | Validating identity token", sessionId)) end

  local allowed = false
  local token = req.UserIdentityToken
  local tokenTypeId = token.TypeId
  local authPolicy
  local encryption
  local tokenPolicy
  for _, p in ipairs(self.config.userIdentityTokens) do
    if p.policyId == token.Body.PolicyId then
      tokenPolicy = p
      break
    end
  end

  if infOn then
    traceI(fmt("Services:activateSession(%s) | Token policy id: '%s', encryption algorithm: '%s'",
      sessionId, token.Body.PolicyId, token.Body.EncryptionAlgorithm))
  end

  if not tokenPolicy then
    if dbgOn then traceD(fmt("Services:activateSession(%s) | Invalid identity token policy", sessionId)) end
    error(BadIdentityTokenRejected)
  end

  if token.Body.EncryptionAlgorithm then
    if infOn then
      traceI(fmt("Services:activateSession(%s) | Decrypting user token with security policy '%s'",
        sessionId, tokenPolicy.securityPolicyUri))
    end
    encryption = securePolicy(self.config)
    authPolicy = encryption(tokenPolicy.securityPolicyUri)
    if authPolicy.aEncryptionAlgorithm ~= token.Body.EncryptionAlgorithm then
      if errOn then traceE(fmt("Services:activateSession(%s) | Cannot find secure policy %s", sessionId, token.Body.EncryptionAlgorithm)) end
      error(BadIdentityTokenRejected)
    end
  end

  if tokenTypeId == "i=319" then
    if infOn then traceI(fmt("Services:activateSession(%s) | Check anonymous token", sessionId)) end
    if tokenPolicy.tokenType ~= const.UserTokenType.Anonymous then
      if errOn then traceE(fmt("Services:activateSession(%s) | Not an anonymous token ", sessionId)) end
      error(BadIdentityTokenRejected)
    end
    allowed = authenticate("anonymous")
  elseif tokenTypeId == "i=322" then
    if infOn then traceI(fmt("Services:activateSession(%s) | Check User Name '%s'", sessionId, token.Body.UserName)) end
    local password = decrypt(authPolicy, token.Body.Password)
    allowed = authenticate("username", password, token.Body.UserName)
  elseif tokenTypeId == "i=325" then
    if infOn then traceI(fmt("Services:activateSession(%s) | Check x509 certificate", sessionId)) end
    if tokenPolicy.securityPolicyUri and tokenPolicy.securityPolicyUri ~= const.SecurityPolicy.None or req.UserTokenSignature.Signature then
      encryption = securePolicy(self.config)
      authPolicy = encryption(tokenPolicy.securityPolicyUri)
      if req.UserTokenSignature.Algorithm ~= authPolicy.aSignatureUri then
        if infOn then traceI(fmt("Services:activateSession(%s) | Unknown encryption algorithm", sessionId)) end
        error(BadUserSignatureInvalid)
      end

      authPolicy:setRemoteCertificate(token.Body.CertificateData)
      if not checkSignature(authPolicy, req.UserTokenSignature, authPolicy:getLocalCert(), session.nonce) then
        if infOn then traceI(fmt("Services:activateSession(%s) | Invalid user token signature", sessionId)) end
        error(BadUserSignatureInvalid)
      end
    end
    allowed = authenticate("x509", token.Body.CertificateData)
  elseif tokenTypeId == "i=938" then -- IssuedToken
    local tokenData = decrypt(authPolicy, token.Body.TokenData)
    if tokenPolicy.issuedTokenType == const.IssuedTokenType.Azure then
      if infOn then traceI(fmt("Services:activateSession(%s) | Check Azure token", sessionId)) end
      allowed = authenticate("azure", tokenData, tokenPolicy.issuerEndpointUrl)
    elseif tokenPolicy.issuedTokenType == const.IssuedTokenType.JWT then
      if infOn then traceI(fmt("Services:activateSession(%s) | Check JWT token", sessionId)) end
      allowed = authenticate("jwt", tokenData, tokenPolicy.issuerEndpointUrl)
    elseif tokenPolicy.issuedTokenType == const.IssuedTokenType.OAuth2 then
      if infOn then traceI(fmt("Services:activateSession(%s) | Check OAuth2 token", sessionId)) end
      allowed = authenticate("oauth2", tokenData, tokenPolicy.issuerEndpointUrl)
    elseif tokenPolicy.issuedTokenType == const.IssuedTokenType.OPCUA then
      if infOn then traceI(fmt("Services:activateSession(%s) | Check OPCUA token", sessionId)) end
      allowed = authenticate("opcua", tokenData, tokenPolicy.issuerEndpointUrl)
    else
      if errOn then traceE(fmt("Services:activateSession(%s) | Unknown issued token type '%s'", sessionId, tokenPolicy.issuedTokenType)) end
      error(BadIdentityTokenRejected)
    end
  else
    if errOn then traceE(fmt("Services:activateSession(%s) | Unknown token id '%s'", sessionId, tokenTypeId)) end
    error(BadIdentityTokenRejected)
  end

  assert(type(allowed) == "boolean")

  if not allowed then
    if errOn then traceE(fmt("Services:activateSession(%s) | Access denied", sessionId)) end
    error(BadUserAccessDenied)
  end

  local curTime = os.time()
  session.sessionExpirationTime = curTime + session.sessionTimeoutSecs
  session.nonce = policy:genNonce(32)
  session.activated = true

  -- If session transfered from TCP channel to HTTP channel
  if channel == nil and session.channelId ~= nil then
    self.sessions[session.channelId] = nil
    session.channelId = nil
  end

  -- if session changed channel number
  if channel then
    if session.channelId and session.channelId ~= channel.channelId then
      self.sessions[session.channelId] = nil -- remove session from old channel
    end
    session.channelId = channel.channelId
    self.sessions[session.channelId] = session -- bin session to new channel
  end

  local result = {
    ServerNonce = session.nonce,
    Results = {Good}
  }

  if infOn then traceI(fmt("Services:activateSession(%s) | Access permitted", sessionId)) end

  return result;
end

function Svc:closeSession(req, channel)
  local infOn = self.trace.infOn

  if infOn then traceI("Services:closeSession()") end

  local session = self:getSession(req, channel)
  if session.channelId ~= nil then
    self.sessions[session.channelId] = nil
  end
  self.sessions[session.authenticationToken] = nil

  if infOn then traceI(fmt("Services:closeSession(%s) | Session closed", session.sessionId)) end
  return {}
end

function Svc:getSubtypes(parent, cont)
  if parent == nil then
    return cont
  end

  cont[parent.Attrs.NodeId] = 1

  local nodeClass = parent.Attrs.NodeClass -- node class of an inspecting type hierarchy
  for _,ref in ipairs(parent.Refs) do
    if ref.type ~= HasSubtype then
      goto continue
    end

    local subtypeId = ref.target
    local subtype = self.nodeset[subtypeId]
    if subtype == nil then
      traceE(fmt("Services:getSubtypes | INTERNAL ERROR: Unknown subtype NodeId '%s'", subtypeId))
      error(BadInternalError)
    end

    if ref.isForward == false then
      goto continue
    end

    -- Collect only the same node class
    if subtype.Attrs.NodeClass ~= nodeClass then
      goto continue
    end

    self:getSubtypes(subtype, cont)
    ::continue::
  end

  return cont
end


function Svc:browse(req, channel)
  local errOn = self.trace.errOn
  local infOn = self.trace.infOn
  local dbgOn = self.trace.dbgOn

  if infOn then traceI(fmt("Services:browse()")) end
  local session = self:checkSession(req, channel)
  local sessionId = session.sessionId

  if req.NodesToBrowse[1] == nil then
    if infOn then traceI(fmt("Services:browse(%s) | Nothing to do", sessionId)) end
    error(BadNothingToDo)
  end

  local results = {}
  for _,n in pairs(req.NodesToBrowse) do
    local result = {
      ContinuationPoint = nil,
      References = {}
    }

    if infOn then
      traceI(fmt("Services:browse(ch:%s) | NodeID='%s', BrowseDirection=%s, ReferenceID='%s', IncludeSubtypes=%s",
      sessionId, n.NodeId, n.BrowseDirection, n.ReferenceTypeId,n.IncludeSubtypes))
    end

    repeat
      if n.BrowseDirection == nil or n.BrowseDirection < 0 or n.BrowseDirection > 2 then
        if errOn then traceE(fmt("Services:browse(%s) | Invalid browse direction '%s'", sessionId, n.BrowseDirection)) end
        result.StatusCode = BadBrowseDirectionInvalid
        break
      end

      local node = self.nodeset[n.NodeId]
      if node == nil then
        if errOn then traceE(fmt("Services:browse(%s) | Unknown node ID '%s'", sessionId, n.NodeId)) end
        result.StatusCode = BadNodeIdUnknown
        break
      end

      -- collect subtypes of reference type
      local refNode = self.nodeset[n.ReferenceTypeId]
      if refNode == nil then
        if errOn then traceE(fmt("Services:browse(%s) | Unknown Reference ID %s", sessionId, n.ReferenceTypeId)) end
        result.StatusCode = BadReferenceTypeIdInvalid
        break
      end

      local refTypes = {}
      if n.IncludeSubtypes == true then
        if dbgOn then traceD(fmt("Services:browse(%s) | Collecting subtypes of refererence", sessionId)) end
        self:getSubtypes(refNode, refTypes)
      else
        refTypes[n.ReferenceTypeId] = 1
      end

      if dbgOn then traceD(fmt("Services:browse(%s) | node has %d refs", sessionId, #node.Refs)) end

      local isForward = n.BrowseDirection == const.BrowseDirection.Forward
      result.StatusCode = Good
      for _,ref in pairs(node.Refs) do
        repeat
          local refType = ref.type
          if dbgOn then
            traceD(fmt("Services:browse(%s) | TargetNodeId='%s', ReferenceID='%s', isForward='%s'", sessionId, ref.target, refType, ref.isForward))
          end

          if refTypes[refType] == nil or (n.BrowseDirection ~= const.BrowseDirection.Both and ref.isForward ~= isForward) then
            if dbgOn then traceD(fmt("Services:browse(%s) | reference has different direction from %d", sessionId, n.BrowseDirection)) end
            break
          end

          local targetNode = self.nodeset[ref.target]
          if not targetNode then
            if errOn then traceE(fmt("Services:browse(%s) |   Target node '%s' not found", sessionId, ref.target)) end
            error(BadInternalError)
          end

          local displayName = targetNode.Attrs.DisplayName
          local browseName = targetNode.Attrs.BrowseName
          if dbgOn then
            traceD(fmt("Services:browse(%s) |   Target node browseName='%s'", sessionId, browseName.Name))
          end

          local nodeClass = targetNode.Attrs.NodeClass
          local typeDefinition = NodeId.Null

          if nodeClass == NodeClass.Object or nodeClass == NodeClass.Variable then
            for _, r in ipairs(targetNode.Refs) do
              if r.type == HasTypeDefinition then
                typeDefinition = r.target
                break
              end
            end
          end

          local r = {
            NodeId = ref.target,
            ReferenceTypeId = refType,
            IsForward = ref.isForward,
            NodeClass = nodeClass,
            BrowseName = browseName,
            TypeDefinition = typeDefinition,
            DisplayName = displayName
          }

          tins(result.References, r)
          if dbgOn then
            traceD(fmt("Services:browse(%s) |   ReferenceID='%s' ->  BrowseName='%s', TargetNodeID='%s'",
            sessionId, r.ReferenceTypeId, r.BrowseName.Name, r.NodeId))
          end
        until true
      end
    until true

    tins(results, result)
  end
  if dbgOn then traceD(fmt("Services:browse(%s) | done", sessionId)) end
  return {Results=results}
end

function Svc:translateBrowsePath(path, sessionId)
  local dbgOn = self.trace.dbgOn
  if dbgOn then traceD("Services:translateBrowsePath |") end

    -- result for current path
  if path.RelativePath == nil or path.RelativePath.Elements == nil or #path.RelativePath.Elements == 0 then
    if dbgOn then traceD(fmt("Services:translateBrowsePath(%s) | no relative paths to process", sessionId)) end
    error(BadNoMatch)
  end

  local root = self.model:browse(path.StartingNode)
  local node = root:path(path.RelativePath.Elements)

  local targets = {}
  tins(targets, {TargetId=node.Attrs.NodeId, RemainingPathIndex=0xFFFFFFFF})
  return targets
end


function Svc:translateBrowsePaths(req, channel)
  local dbgOn = self.trace.dbgOn
  local infOn = self.trace.infOn

  local session = self:checkSession(req, channel)
  local sessionId = session.sessionId or 0

  if infOn then
    traceD(fmt("Services:translateBrowsePaths(%s)", sessionId))
  end

  if dbgOn then
    traceD(fmt("Services:translateBrowsePaths(%s) | %d paths", sessionId, #req.BrowsePaths))
  end

  if #req.BrowsePaths == 0 then
    if dbgOn then
      traceD(fmt("Services:translateBrowsePaths(%s) | %d nothing to do", sessionId, #req.BrowsePaths))
    end
    error(BadNothingToDo)
  end

  local results = {}

  for _, path in ipairs(req.BrowsePaths) do
    local suc, result = pcall(self.translateBrowsePath, self, path, sessionId)
    if suc == true then
       if dbgOn then traceD(fmt("Services:translateBrowsePaths(%s) | success", sessionId)) end
      tins(results, {StatusCode = s.Good, Targets=result})
    else
      if dbgOn then traceD(fmt("Services:translateBrowsePaths(%s) | error %s", sessionId, result)) end
      tins(results, {StatusCode = result, Targets={}})
    end
  end

  if dbgOn then traceD(fmt("Services:translateBrowsePaths(%s) | done", sessionId)) end
  return {Results=results}
end

function Svc:read(req, channel)
  local dbgOn = self.trace.dbgOn
  local infOn = self.trace.infOn

  if infOn then traceI(fmt("Services:Read()")) end

  local session = self:checkSession(req, channel)
  local sessionId = session.sessionId

  if dbgOn then traceD(fmt("Services:Read(%s) | Reading %s attributes", sessionId, #req.NodesToRead)) end
  if req.NodesToRead == nil or #req.NodesToRead == 0 then
    if infOn then traceI(fmt("Services:Read(%s) | Empty request received", sessionId)) end
    error(BadNothingToDo)
  end

  local results = {}
  for _, r in ipairs(req.NodesToRead) do
    local val = {}
    local node = self.nodeset[r.NodeId]
    if node == nil then
      if dbgOn then traceD(fmt("Services:Read(%s) | Unknown node id %s", sessionId, r.NodeId)) end
      val.StatusCode = BadNodeIdUnknown
    else
      if dbgOn then traceD(fmt("Services:Read(%s) | Node id '%s' attribute %d ", sessionId, r.NodeId, r.AttributeId)) end
      if r.AttributeId == AttributeId.Value and node.Attrs.NodeClass == const.NodeClass.Variable and node.Attrs.NodeCallback then
        if dbgOn then traceD(fmt("Services:Read(%s) | reading value node '%s' from custom source", sessionId, r.NodeId)) end
        val = node.Attrs.NodeCallback(r.NodeId)
        if not tools.dataValueValid(val) then
          val = { StatusCode = const.StatusCode.BadInternalError }
        end
      else
        val = node.VAttrs[r.AttributeId]
      end
      if val.StatusCode == nil then
        val.StatusCode = s.Good
      end
    end

    if dbgOn and val.StatusCode ~= Good then
      traceD(fmt("Services:Read(%s) | StatusCode %d", sessionId, val.StatusCode))
    end

    tins(results, val)
  end

  return {Results=results}
end

function Svc:writeNode(val)
  local dbgOn = self.trace.dbgOn
  local nodeId = val.NodeId
  local attributeId = val.AttributeId
  local value = val.Value
  if dbgOn then traceD(fmt("Services:Write | searching node '%s'", nodeId)) end
  local n = self.nodeset[nodeId]
  if n == nil then
    if dbgOn then traceD(fmt("Services:Write | node '%s' not found", nodeId)) end
    error(BadNodeIdUnknown)
  end

  if dbgOn then traceD(fmt("Services:Write | updating attribute '%d' of node '%s' ", attributeId, nodeId)) end
  if attributeId == AttributeId.Value and n.Attrs.NodeCallback then
    if dbgOn then traceD(fmt("Services:Write | writing value node '%s' to custom source", attributeId, nodeId)) end
    n.Attrs.NodeCallback(nodeId, value)
  else
    n.Attrs[attributeId] = value
  end

  self.nodeset:saveNode(n)
  self:callWriteHook(nodeId, attributeId, value)
  if dbgOn then traceD(fmt("Services:Write | updated attribute '%d' of node '%s' ", attributeId, nodeId)) end
end

function Svc:write(req, channel)
  local errOn = self.trace.errOn
  local dbgOn = self.trace.dbgOn
  local infOn = self.trace.infOn

  if dbgOn then traceD(fmt("Services:Write")) end

  local session = self:checkSession(req, channel)
  local sessionId = session.sessionId

  if req.NodesToWrite == nil or req.NodesToWrite[1] == nil then
    if errOn then traceE(fmt("Services:Write(%s) | Empty response received", sessionId)) end
    error(BadNothingToDo)
  end

  local results = {}
  for _, val in ipairs(req.NodesToWrite) do
    if infOn then traceI(fmt("Services:Write(%s) | Writing '%s'", sessionId, val.NodeId)) end
    local suc, code = pcall(self.writeNode, self, val)
    if suc then
      code = 0
    end
    if dbgOn then traceD(fmt("Services:Write(%s) | '%s' result '%s'", sessionId, val.NodeId, code)) end
    tins(results, code)
  end

  return {Results=results}
end

local function setCommonAttributes(node, nodeAttrs)
  node.Attrs.DisplayName = nodeAttrs.NodeAttributes.Body.DisplayName
  node.Attrs.Description = nodeAttrs.NodeAttributes.Body.Description
  node.Attrs.WriteMask = nodeAttrs.NodeAttributes.Body.WriteMask
  node.Attrs.UserWriteMask = nodeAttrs.NodeAttributes.Body.UserWriteMask
end

local function setVariableAttributes(node, allAttrs)
  setCommonAttributes(node, allAttrs)
  local nodeAttrs = allAttrs.NodeAttributes.Body
  node.Attrs.AccessLevel = nodeAttrs.AccessLevel
  if nodeAttrs.AccessLevel ~= nil then
    node.Attrs.UserAccessLevel = nodeAttrs.UserAccessLevel
  end
  if nodeAttrs.MinimumSamplingInterval ~= nil then
    node.Attrs.MinimumSamplingInterval = nodeAttrs.MinimumSamplingInterval
  end
  node.Attrs.Rank = nodeAttrs.ValueRank
  node.Attrs.Historizing = nodeAttrs.Historizing
end

-- Create Object node attributes from new object parameters
local function setObjectAttributes(node, nodeAttrs)
  setCommonAttributes(node, nodeAttrs)
  if nodeAttrs.EventNotifier then
    node.Attrs.EventNotifier = nodeAttrs.EventNotifier
  end
end

function Svc:addNode(node)
  local dbgOn = self.trace.dbgOn
  local errOn = self.trace.errOn
  local infOn = self.trace.infOn
  if dbgOn then traceD("Services:addNode |") end

  local editor = self.model:edit()

  local parent = editor:findNode(node.ParentNodeId)
  if not parent then
    if errOn then traceE(fmt("Services:addNode | Parent node '%s' not found", node.ParentNodeId)) end
    error(BadParentNodeIdInvalid)
  end

  local typeDefinition
  if node.TypeDefinition then
    typeDefinition = editor:findNode(node.TypeDefinition)
    local nodeClass = typeDefinition.Attrs.NodeClass
    if not typeDefinition or (nodeClass ~= const.NodeClass.VariableType and nodeClass ~= const.NodeClass.ObjectType) then
      if errOn then traceE(fmt("Services:addNode | Type definition node '%s' is not a variable type or object type", node.TypeDefinition)) end
      error(BadTypeDefinitionInvalid)
    end
  end

  local refType = editor:findNode(node.ReferenceTypeId)
  if not refType or refType.Attrs.NodeClass ~= const.NodeClass.ReferenceType then
    if errOn then traceE(fmt("Services:addNode | Reference type node '%s' not found", node.ReferenceTypeId)) end
    error(BadReferenceTypeIdInvalid)
  end

  local newNode
  if node.NodeClass == const.NodeClass.Variable then
    if infOn then traceI("Services:addNode | Adding new variable node.") end
    newNode = parent:addVariable(node.BrowseName, node.NodeAttributes.Body.Value, typeDefinition, node.RequestedNewNodeId, refType)
    setVariableAttributes(newNode, node)
  elseif node.NodeClass == const.NodeClass.Object then
    if infOn then traceI("Services:addNode | Adding new object.") end
    newNode = parent:addObject(node.BrowseName, node.TypeDefinition, node.RequestedNewNodeId, node.ReferenceTypeId)
    setObjectAttributes(newNode, node)
  else
    error(BadNodeClassInvalid)
  end

  editor:save()

  if infOn then traceI(fmt("Services:addNode | new node '%s' added", newNode.Attrs.NodeId)) end

  return newNode.Attrs.NodeId
end

function Svc:addNodes(req, channel)
  local dbgOn = self.trace.dbgOn
  local errOn = self.trace.errOn
  local infOn = self.trace.infOn
  if dbgOn then traceD("Services:addNode |") end

  local session = self:checkSession(req, channel)
  local sessionId = session.sessionId

  if req.NodesToAdd == nil or req.NodesToAdd[1] == nil then
    if infOn then traceD(fmt("Services:addNodes(%s) | Nothing to do", sessionId)) end
    error(BadNothingToDo)
  end


  local results = {}
  for _, node in ipairs(req.NodesToAdd) do
    local suc, result = pcall(self.addNode, self, node)
    if suc == true then
      if infOn then traceD(fmt("Services:addNodes(%s) | Added node id '%s'", sessionId, result)) end
      tins(results, {StatusCode=Good, AddedNodeId=result})
    else
      if errOn then traceD(fmt("Services:addNodes(%s) | Error adding node %s", sessionId, result)) end
      tins(results, {StatusCode=result, AddedNodeId="i=0"})
    end
  end

  return {Results=results}
end

function Svc:createSubscription(req, channel)
  local infOn = self.trace.infOn
  local errOn = self.trace.errOn
  if infOn then traceI("Services:createSubscription |") end

  local session = self:checkSession(req, channel)
  local sessionId = session.sessionId

  if errOn then traceE(fmt("Services:createSubscription(%s) | Subsriptions unsupported", sessionId)) end

  error(BadServiceUnsupported)
end

function Svc:callMethod(method)
  local dbgOn = self.trace.dbgOn
  local errOn = self.trace.errOn
  if dbgOn then traceD("Services:callMethod |") end

  local response = {
    StatusCode = Good,
    InputArgumentResults = {},
    InputArgumentDiagnosticInfos = {},
    OutputArguments = nil
  }

  local browser = self.model:browse()
  local objectNode = browser:getNode(method.ObjectId)
  if objectNode.Attrs.NodeClass ~= const.NodeClass.Object then
    if errOn then traceE(fmt("Services:callMethod | ObjectId '%s' is not an object", method.ObjectId)) end
    response.StatusCode = BadNodeIdInvalid
    return response
  end

  local methodNode = browser:getNode(method.MethodId)
  if methodNode.Attrs.NodeClass ~= const.NodeClass.Method then
    if errOn then traceE(fmt("Services:callMethod | MethodId '%s' is not a method", method.MethodId)) end
    response.StatusCode = s.BadMethodInvalid
    return response
  end

  local inputArgumentsNode = methodNode:path("InputArguments")
  if inputArgumentsNode.Attrs.NodeClass ~= const.NodeClass.Variable then
    if errOn then traceE(fmt("Services:callMethod | InputArguments[1].NodeId '%s' is not a variable", method.InputArguments[1].NodeId)) end
    response.StatusCode = BadNodeIdInvalid
    return response
  end

  local func = methodNode.Attrs.NodeCallback
  if func == nil then
    if errOn then traceE(fmt("Services:callMethod | Node callback is nil")) end
    response.StatusCode = BadInternalError
    return response
  end

  local inputArgsDef = inputArgumentsNode.Attrs.Value.Value
  if #method.InputArguments < #inputArgsDef then
    if errOn then traceE(fmt("Services:callMethod | InputArguments count mismatch")) end
    response.StatusCode = s.BadArgumentsMissing
    return response
  end

  if #method.InputArguments > #inputArgsDef then
    if errOn then traceE(fmt("Services:callMethod | InputArguments count mismatch")) end
    response.StatusCode = s.BadTooManyArguments
    return response
  end

  for idx, field in ipairs(inputArgsDef) do
    local inputArgument = method.InputArguments[idx]
    if field.Body.DataType ~= string.format("i=%s", inputArgument.Type) then
      if errOn then traceE(fmt("Services:callMethod | InputArguments[%d].DataType '%s' is not a %s", idx, inputArgument.Type, field.DataType)) end
      response.StatusCode = BadInvalidArgument
      response.InputArgumentResults[idx] = BadInvalidArgument
    else
      response.InputArgumentResults[idx] = Good
    end
  end

  if response.StatusCode ~= Good then
    return response
  end

  local ok, result = pcall(func, method.ObjectId, method.MethodId, method.InputArguments)
  if ok then
    response.OutputArguments = result
    if dbgOn then traceD(fmt("Services:callMethod | Node callback result: %s", result)) end
  else
    if errOn then traceE(fmt("Services:callMethod | Node callback failed: %s", result)) end
    response.StatusCode = result
  end

  if errOn then traceD(fmt("Services:callMethod | Result: %s", response)) end

  return response
end

function Svc:call(req, channel)
  local dbgOn = self.trace.dbgOn
  if dbgOn then traceI("Services:call |") end

  self:checkSession(req, channel)

  local results = {}
  for _, method in ipairs(req.MethodsToCall) do
    local response = self:callMethod(method)
    tins(results, response)
  end
  return {Results=results}
end

function Svc:setValueCallback(nodeId, func)
  local dbgOn = self.trace.dbgOn
  if dbgOn then traceD(fmt("Setting source callback for node '%s'", nodeId)) end
  if type(func) ~= 'function' then
    error(BadInvalidArgument)
  end

  local node = self.nodeset[nodeId]
  if nodeId == nil then
    if dbgOn then traceD(fmt("Setting source callback failed: nodeId '%s' unknown", nodeId)) end
    error(BadNodeIdUnknown)
  end
  if node.Attrs[AttributeId.NodeClass] ~= const.NodeClass.Variable then
    if dbgOn then traceD(fmt("Setting source callback failed: nodeId '%s' is not a variable", nodeId)) end
    error(BadNodeClassInvalid)
  end

  node.Attrs.NodeCallback = func
  self.nodeset:saveNode(node)
  if dbgOn then traceD(fmt("Source callback for nodeId '%s' was set", nodeId)) end
end

function Svc:setWriteHook(nodeId, func)
  local dbgOn = self.trace.dbgOn
  if dbgOn then traceD(fmt("Setting write hook for node '%s'", nodeId)) end
  if type(func) ~= 'function' then
    error(BadInvalidArgument)
  end

  local nodeHooks = self.hooks[nodeId] or {}
  nodeHooks.onWrite = func
  self.hooks[nodeId] = nodeHooks
  if dbgOn then traceD(fmt("Write hook for nodeId '%s' was set", nodeId)) end
end

function Svc:callWriteHook(nodeId, attributeId, value)
  local hooks = self.hooks[nodeId]
  if not (hooks and hooks.onWrite) then
    return
  end

  local dbgOn = self.trace.dbgOn
  local errOn = self.trace.errOn

  if dbgOn then traceD(fmt("Services:Write | calling write hook for node '%s'", nodeId)) end
  -- IMO failing of a hook should not be a fatal error
  local ok, err = pcall(hooks.onWrite, nodeId, attributeId, tools.copy(value))
  if not ok and errOn then
    traceE(fmt("Services:Write | write hook for node '%s' failed: %s", nodeId, err))
  end
end

function Svc:getSession(req, channel)
  local dbgOn = self.trace.dbgOn
  local errOn = self.trace.errOn

  -- request header is absent in internal calls
  if req.RequestHeader == nil then
    return {}
  end

  local authenticationToken = req.RequestHeader.AuthenticationToken
  local session = self.sessions[authenticationToken]
  if not session and channel then
    session = self.sessions[channel.channelId]
  end

  if not session then
    if errOn then traceE(fmt("Svc:checkSession() | No session found for token '%s'", authenticationToken)) end
    error(BadSessionClosed)
  end

  local sessionId = session.sessionId
  if dbgOn then traceD(fmt("Svc:checkSession(%s) | Request handle '%s'", sessionId, req.RequestHeader.RequestHandle)) end

  if session.authenticationToken ~= req.RequestHeader.AuthenticationToken then
    if errOn then traceE(fmt("Svc:checkSession(%s) | Wrong '%s' auth token differ. ", sessionId, authenticationToken)) end
    error(BadRequestHeaderInvalid)
  end

  if channel and session.channelId ~= channel.channelId then
    if errOn then traceE(fmt("Svc:checkSession(%s) | channel '%s' lost session. ", session.sessionId, channel.channelId)) end
    error(BadSessionClosed)
  end

  return session
end

function Svc:checkSession(req, channel)
  -- request header is absent in internal calls
  if req.RequestHeader == nil then
    return {}
  end

  local dbgOn = self.trace.dbgOn
  local errOn = self.trace.errOn

  local session = self:getSession(req, channel)
  if not session.activated then
    if errOn then traceE(fmt("Svc:checkSession(%s) | Session inactive. ", session.sessionId)) end
    error(BadSessionNotActivated)
  end

  local time = os.time()
  if time > session.sessionExpirationTime then
    self.sessions[channel.channelId] = nil
    if errOn then traceE(fmt("Svc:checkSession(%s) | Session expired. ", session.sessionId)) end
    error(BadSessionClosed)
  end

  session.sessionExpirationTime = time + session.sessionTimeoutSecs
  if dbgOn then traceD(fmt("Svc:checkSession(%s) | New expiration time '%s'", session.sessionId, session.sessionExpirationTime)) end

  return session
end

function Svc:cleanupSessions()
  local dbgOn = self.trace.dbgOn
  local infOn = self.trace.infOn

  if dbgOn then traceD("Services:cleanupSessions") end
  local cnt = 0
  local time = os.time()
  for channelId, session in pairs(self.sessions) do
    local sessionTimeout = session.sessionExpirationTime - time
    if dbgOn then traceD(fmt("Services:cleanupSessions | session '%s' timeout '%s' secs.", session.sessionId, sessionTimeout)) end
    if sessionTimeout < 0 then
      self.sessions[channelId] = nil
      if infOn then traceI(fmt("Services:cleanupSessions | Deleting expired session '%s' for channel", session.sessionId, session.channelId)) end
    else
      cnt = cnt + 1
    end
  end
  if dbgOn then traceD(fmt("Services:cleanupSessions | Number of alive sessions: %d.", cnt)) end
  if cnt == 0 and self.sessionTimer then
    if dbgOn then traceD(fmt("Services:cleanupSessions | Stopping sessions cleanup timer")) end
    self.sessionTimer:cancel()
    self.sessionTimer = nil
  end
end

function Svc:startSessionCleanup()
  if self.sessionTimer then
    return
  end

  local timer = compat.timer(function()
    self:cleanupSessions()
    return true
  end)
  self.sessionTimer = timer
  timer:set(10000)
end

function Svc:shutdown()
  local timer = self.sessionTimer
  self.sessionTimer = nil
  if timer then
    timer:cancel()
  end
end


local function newServices(config, model)
  assert(config ~= nil, "no config")
  assert(model ~= nil, "no model")

  local svc = {
    endpointUrl = config.endpointUrl,
    trace = config.logging.services,
    config = config,
    model = model,
    sessions = {},
    hooks = {},
  }

  setmetatable(svc, Svc)
  return svc
end

return {new=newServices}
