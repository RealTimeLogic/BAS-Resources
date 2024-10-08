local ua = require("opcua.api")
local attrs = require("opcua.services_attributes")
local compat = require("opcua.compat")
local createCert = ua.crypto.createCert
local securePolicy = require("opcua.binary.crypto.policy")
local Q = require("opcua.binary.queue")
local BinaryDecoder = require("opcua.binary.decoder")
local address_space = require("opcua.address_space")
local srvObject = require("opcua.server_object")


local s = ua.StatusCode
local t = ua.Tools
local AttributeId = ua.Types.AttributeId
local NodeClass = ua.Types.NodeClass

local traceD = ua.trace.dbg
local traceI = ua.trace.inf
local traceE = ua.trace.err

local fmt = string.format
local tins = table.insert

local HasSubtype = "i=45"
local LocalizedText = "i=21"
local QualifiedName = "i=20"
local HasTypeDefinition = "i=40"
local HasModellingRule = "i=37"
local ModellingRule_Mandatory = "i=78"

local Good = s.Good
local BadInvalidArgument = s.BadInvalidArgument
local BadNodeIdUnknown = s.BadNodeIdUnknown
local BadNodeClassInvalid = s.BadNodeClassInvalid
local BadBrowseDirectionInvalid = s.BadBrowseDirectionInvalid
local BadReferenceTypeIdInvalid =  s.BadReferenceTypeIdInvalid
local BadBrowseNameInvalid = s.BadBrowseNameInvalid
local BadNothingToDo = s.BadNothingToDo
local BadNoMatch = s.BadNoMatch
local BadNodeAttributesInvalid = s.BadNodeAttributesInvalid
local BadParentNodeIdInvalid = s.BadParentNodeIdInvalid
local BadTypeDefinitionInvalid = s.BadTypeDefinitionInvalid
local BadNodeIdExists = s.BadNodeIdExists
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

local Svc = {}
Svc.__index = Svc

function Svc:start()
  self.nodeset = address_space()
  self.srvObject = srvObject()
  if self.srvObject.start == nil then
    ua.debug()
  end
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

    ProductUri = ua.Version.ProductUri,
    ApplicationType = ua.Types.ApplicationType.Server,
    GatewayServerUri = nil,
    DiscoveryProfileUri = ua.Types.ServerProfile.NanoEmbedded2017,
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
  local der = certificate and createCert(certificate, self.config.io).der
  local tokenPolicies = {}

  for _,p in ipairs(self.config.userIdentityTokens) do
    tins(tokenPolicies, {PolicyId=p.policyId, SecurityPolicyUri=p.securityPolicyUri, TokenType=p.tokenType, IssuedTokenType=p.issuedTokenType, IssuerEndpointUrl=p.issuerEndpointUrl})
  end

  if string.find(endpointUrl, "http://") or string.find(endpointUrl, "https://") then
    local endpoint = {
      EndpointUrl = endpointUrl,
      ServerCertificate = der,
      SecurityMode = ua.Types.MessageSecurityMode.None,
      SecurityPolicyUri = ua.Types.SecurityPolicy.None,
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
        self:addEndpointDescriptions(endpoint.endpointUrl, ua.Types.TranportProfileUri.TcpBinary, policy, endpoints)
      end
    elseif string.find(endpointUrl, "http://") or string.find(endpointUrl, "https://") then
      local policy = {}
      self:addEndpointDescriptions(endpoint.endpointUrl, ua.Types.TranportProfileUri.HttpsBinary, policy, endpoints)
      self:addEndpointDescriptions(endpoint.endpointUrl, ua.Types.TranportProfileUri.HttpsJson, policy, endpoints)
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

  if policy.uri ~= ua.Types.SecurityPolicy.None then
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
  local m,err = ua.crypto.decrypt(data, policy.key, policy.params.rsaParams)
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
    if tokenPolicy.tokenType ~= ua.Types.UserTokenType.Anonymous then
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
    if tokenPolicy.securityPolicyUri and tokenPolicy.securityPolicyUri ~= ua.Types.SecurityPolicy.None or req.UserTokenSignature.Signature then
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
    if tokenPolicy.issuedTokenType == ua.Types.IssuedTokenType.Azure then
      if infOn then traceI(fmt("Services:activateSession(%s) | Check Azure token", sessionId)) end
      allowed = authenticate("azure", tokenData, tokenPolicy.issuerEndpointUrl)
    elseif tokenPolicy.issuedTokenType == ua.Types.IssuedTokenType.JWT then
      if infOn then traceI(fmt("Services:activateSession(%s) | Check JWT token", sessionId)) end
      allowed = authenticate("jwt", tokenData, tokenPolicy.issuerEndpointUrl)
    elseif tokenPolicy.issuedTokenType == ua.Types.IssuedTokenType.OAuth2 then
      if infOn then traceI(fmt("Services:activateSession(%s) | Check OAuth2 token", sessionId)) end
      allowed = authenticate("oauth2", tokenData, tokenPolicy.issuerEndpointUrl)
    elseif tokenPolicy.issuedTokenType == ua.Types.IssuedTokenType.OPCUA then
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

  cont[parent.attrs[AttributeId.NodeId]] = 1

  local nodeClass = parent.attrs[AttributeId.NodeClass] -- node class of an inspecting type hierarchy
  for _,ref in ipairs(parent.refs) do
    if ref.type ~= HasSubtype then
      goto continue
    end

    local subtypeId = ref.target
    local subtype = self.nodeset:getNode(subtypeId)
    if subtype == nil then
      traceE(fmt("Services:getSubtypes | INTERNAL ERROR: Unknown subtype NodeId '%s'", subtypeId))
      error(BadInternalError)
    end

    if ref.isForward == false then
      goto continue
    end

    -- Collect only the same node class
    if subtype.attrs[AttributeId.NodeClass] ~= nodeClass then
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

      local node = self.nodeset:getNode(n.NodeId)
      if node == nil then
        if errOn then traceE(fmt("Services:browse(%s) | Unknown node ID '%s'", sessionId, n.NodeId)) end
        result.StatusCode = BadNodeIdUnknown
        break
      end

      -- collect subtypes of reference type
      local refNode = self.nodeset:getNode(n.ReferenceTypeId)
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

      if dbgOn then traceD(fmt("Services:browse(%s) | node has %d refs", sessionId, #node.refs)) end

      local isForward = n.BrowseDirection == ua.Types.BrowseDirection.Forward
      result.StatusCode = Good
      for _,ref in pairs(node.refs) do
        repeat
          local refType = ref.type
          if dbgOn then
            traceD(fmt("Services:browse(%s) | TargetNodeId='%s', ReferenceID='%s', isForward='%s'", sessionId, ref.target, refType, ref.isForward))
          end

          if refTypes[refType] == nil or (n.BrowseDirection ~= ua.Types.BrowseDirection.Both and ref.isForward ~= isForward) then
            if dbgOn then traceD(fmt("Services:browse(%s) | reference has different direction from %d", sessionId, n.BrowseDirection)) end
            break
          end

          local targetNode = self.nodeset:getNode(ref.target)
          if not targetNode then
            if errOn then traceE(fmt("Services:browse(%s) |   Target node '%s' not found", sessionId, ref.target)) end
            error(BadInternalError)
          end

          local displayName = attrs.getAttributeValue(targetNode.attrs, AttributeId.DisplayName, self.nodeset)
          local browseName = attrs.getAttributeValue(targetNode.attrs, AttributeId.BrowseName, self.nodeset)

          assert(t.getVariantType(displayName.Value) == LocalizedText)
          assert(t.getVariantType(browseName.Value) == QualifiedName)

          if dbgOn then traceD(fmt("Services:browse(%s) |   Target node browseName='%s'", sessionId, browseName.Value.QualifiedName.Name)) end

          local nodeClass = targetNode.attrs[AttributeId.NodeClass]
          local typeDefinition = ua.NodeId.Null

          if nodeClass == NodeClass.Object or nodeClass == NodeClass.Variable then
            for _, r in ipairs(targetNode.refs) do
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
            BrowseName = browseName.Value.QualifiedName,
            TypeDefinition = typeDefinition,
            DisplayName = displayName.Value.LocalizedText
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

  local targetId = path.StartingNode
  if dbgOn then traceD(fmt("Services:translateBrowsePath(%s) | target node %s", sessionId, targetId)) end
  local targetNode = self.nodeset:getNode(targetId)
  if targetNode == nil then
    if dbgOn then traceD(fmt("Services:translateBrowsePath(%s) | target node not found", sessionId)) end
    error(BadNodeIdUnknown)
  end

  local targets = {}

  if dbgOn then traceD(fmt("Services:translateBrowsePath(%s) | elements %d", sessionId, #path.RelativePath.Elements)) end

  for rel_idx,rel in ipairs(path.RelativePath.Elements) do
    -- Collect all reference type we should follow: Requested reference and its Sybtypes
    if dbgOn then
      traceD(fmt("Services:translateBrowsePath(%s) | element %d: browseName=%s, referenceTypeId=%s, includeSubtypes=%s",
        sessionId, rel_idx, rel.TargetName.Name, rel.ReferenceTypeId, rel.IncludeSubtypes))
    end

    local refTypes = {}
    local refId = rel.ReferenceTypeId
    if rel.IncludeSubtypes == true then
      if dbgOn then traceD(fmt("Services:translateBrowsePath(%s) | Collecting subtypes of reference %s", sessionId, rel.ReferenceTypeId)) end
      self:getSubtypes(self.nodeset:getNode(refId), refTypes)
    else
      refTypes[refId] = 1
    end

    local nextTargetId = nil
    -- follow all referencies of a node and compare it with selected reference types
    for _,nodeRef in ipairs(targetNode.refs) do
      repeat
        local refType = nodeRef.type
        if dbgOn then traceD(fmt("Services:translateBrowsePath(%s) | Processing reference %s", sessionId, refType)) end

        if nodeRef.isForward == rel.IsInverse then
          if dbgOn then traceD(fmt("Services:translateBrowsePath(%s) | Invalid direction", sessionId)) end
          break
        end

        if refTypes[refType] ~= 1 then
          if dbgOn then traceD(fmt("Services:translateBrowsePath(%s) | Not a suitable reference type", sessionId)) end
          break
        end

        local nodeId = nodeRef.target
        if dbgOn then traceD(fmt("Services:translateBrowsePath(%s) | target node id %s", sessionId, nodeId)) end
        local node = self.nodeset:getNode(nodeId)
        if node == nil then
          if dbgOn then traceD(fmt("Services:translateBrowsePath | node %s not found", sessionId, nodeId)) end
          break
        end

        if node.attrs[AttributeId.BrowseName].Name ~= rel.TargetName.Name then
          if dbgOn then traceD(fmt("Services:translateBrowsePath(%s) | browse name %s different", sessionId, node.attrs[AttributeId.BrowseName].Name)) end
          break
        end

        nextTargetId = nodeId
        targetNode = node
        if dbgOn then traceD(fmt("Services:translateBrowsePath(%s) | Next target node '%s'", sessionId, nodeId)) end
      until true

      if nextTargetId ~= nil then
        break
      end
    end

    targetId = nextTargetId
    if targetId == nil then
      if dbgOn then traceD(fmt("Services:translateBrowsePath(%s) | No match", sessionId)) end
      error(BadNoMatch)
    end
  end

  if targetId ~= nil then
    tins(targets, {TargetId=targetId, RemainingPathIndex=0xFFFFFFFF})
  end

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
    local node = self.nodeset:getNode(r.NodeId)
    if node == nil then
      if dbgOn then traceD(fmt("Services:Read(%s) | Unknown node id %s", sessionId, r.NodeId)) end
      val.StatusCode = BadNodeIdUnknown
    else
      if dbgOn then traceD(fmt("Services:Read(%s) | Node id '%s' attribute %d ", sessionId, r.NodeId, r.AttributeId)) end
      local suc,result = pcall(attrs.getAttributeValue, node.attrs, r.AttributeId, self.nodeset)
      if not suc then
        val.StatusCode = result
      else
        val = result
        if val.StatusCode == nil then
          val.StatusCode = 0
        end
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
  if dbgOn then traceD(fmt("Services:Write | searchin node '%s'", nodeId)) end
  local n = self.nodeset:getNode(nodeId)
  if n == nil then
    if dbgOn then traceD(fmt("Services:Write | node '%s' not found", nodeId)) end
    error(BadNodeIdUnknown)
  end

  if dbgOn then traceD(fmt("Services:Write | updating attribute '%d' of node '%s' ", attributeId, nodeId)) end
  if attributeId == AttributeId.Value then
    attrs.checkAttributeValue(n.attrs, attributeId, value, self.nodeset)
    n.attrs[attributeId] = value
    local valueSource = n.attrs.valueSource
    if valueSource then
      if dbgOn then traceD(fmt("Services:Write | writing value node '%s' to custom source", attributeId, nodeId)) end
      valueSource(nodeId, value)
    end
  else
    attrs.checkAttributeValue(n.attrs, attributeId, value and value.Value, self.nodeset)
    n.attrs[attributeId] = value.Value
  end
  self.nodeset:saveNode(n)
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

-- Create node attributes array from parameters of new node.
function Svc:getCommonAttributes(nodeId, nodeAttrs)
  local errOn = self.trace.errOn
  if not t.localizedTextValid(nodeAttrs.NodeAttributes.Body.DisplayName) then
    if errOn then traceE("Services:addNodes | displayName invalid") end
    error(BadNodeAttributesInvalid)
  end
  if not t.localizedTextValid(nodeAttrs.NodeAttributes.Body.Description) then
    if errOn then traceE("Services:addNodes | Description invalid") end
    error(BadNodeAttributesInvalid)
  end
  if not t.uint32Valid(nodeAttrs.NodeAttributes.Body.WriteMask) then
    if errOn then traceE("Services:addNodes | WriteMask invalid") end
    error(BadNodeAttributesInvalid)
  end
  if not t.uint32Valid(nodeAttrs.NodeAttributes.Body.UserWriteMask) then
    if errOn then traceE("Services:addNodes | UserWriteMask invalid") end
    error(BadNodeAttributesInvalid)
  end

  local result = {}
  result[AttributeId.NodeId] = nodeId
  result[AttributeId.BrowseName] = nodeAttrs.BrowseName
  result[AttributeId.DisplayName] = nodeAttrs.NodeAttributes.Body.DisplayName
  result[AttributeId.Description] = nodeAttrs.NodeAttributes.Body.Description
  result[AttributeId.WriteMask] = nodeAttrs.NodeAttributes.Body.WriteMask
  result[AttributeId.UserWriteMask] = nodeAttrs.NodeAttributes.Body.UserWriteMask
  return result
end

-- Create variable node attributes array from new node parameters
function Svc:getVariableAttributes(nodeId, allAttrs, nodeset)
  local dbgOn = self.trace.dbgOn
  local errOn = self.trace.errOn

  if dbgOn then traceD("Services:addNodes | Creating variable node attributes") end

  local result = self:getCommonAttributes(nodeId, allAttrs)

  local nodeAttrs = allAttrs.NodeAttributes.Body
  if not t.nodeIdValid(nodeAttrs.DataType)  then
    if errOn then traceE("Services:addNodes | DataType invalid") end
    error(BadNodeAttributesInvalid)
  end
  if not t.dataValueValid(nodeAttrs.Value) then
    if errOn then traceE("Services:addNodes | Value invalid") end
    error(BadNodeAttributesInvalid)
  end
  if not t.valueRankValid(nodeAttrs.ValueRank) then
    if errOn then traceE("Services:addNodes | ValueRank invalid") end
    error(BadNodeAttributesInvalid)
  end
  if not t.arrayDimensionsValid(nodeAttrs.Value.Value, nodeAttrs.ArrayDimensions, nodeAttrs.ValueRank) then
    if errOn then traceE("Services:addNodes | ArrayDimensions invalid") end
    error(BadNodeAttributesInvalid)
  end
  if not t.uint32Valid(nodeAttrs.AccessLevel) then
    if errOn then traceE("Services:addNodes | AccessLevel invalid") end
    error(BadNodeAttributesInvalid)
  end
  if not t.uint32Valid(nodeAttrs.UserAccessLevel) then
    if errOn then traceE("Services:addNodes | UserAccessLevel invalid") end
    error(BadNodeAttributesInvalid)
  end
  if not t.uint32Valid(nodeAttrs.MinimumSamplingInterval) then
    if errOn then traceE("Services:addNodes | MinimumSamplingInterval invalid") end
    error(BadNodeAttributesInvalid)
  end
  if not t.booleanValid(nodeAttrs.Historizing) then
    if errOn then traceE("Services:addNodes | Historizing invalid") end
    error(BadNodeAttributesInvalid)
  end
  local suc, code = pcall(attrs.checkDataType, nodeAttrs.Value.Value, nodeAttrs.DataType, nodeset)
  if not suc then
    if errOn then traceE("Services:addNodes | DataType of Value invalid") end
    error(code)
  end

  result[AttributeId.NodeClass] = ua.Types.NodeClass.Variable
  result[AttributeId.Value] = nodeAttrs.Value
  result[AttributeId.DataType] = nodeAttrs.DataType
  result[AttributeId.Rank] = nodeAttrs.ValueRank
  result[AttributeId.ArrayDimensions] = nodeAttrs.ArrayDimensions
  result[AttributeId.AccessLevel] = nodeAttrs.AccessLevel
  result[AttributeId.UserAccessLevel] = nodeAttrs.UserAccessLevel
  result[AttributeId.MinimumSamplingInterval] = nodeAttrs.MinimumSamplingInterval
  result[AttributeId.Historizing] = nodeAttrs.Historizing

  return result
end

-- Create Object node attributes from new object parameters
function Svc:getObjectAttributes(nodeId, nodeAttrs)
  local dbgOn = self.trace.dbgOn
  local errOn = self.trace.errOn

  if dbgOn then traceD("Services:addNodes | Creating object node attributes") end

  if not t.byteValid(nodeAttrs.NodeAttributes.Body.EventNotifier) then
    if errOn then traceE("Services:addNodes | AccessLevel invalid") end
    error(BadNodeAttributesInvalid)
  end

  local result = self:getCommonAttributes(nodeId, nodeAttrs)
  result[AttributeId.NodeClass] = ua.Types.NodeClass.Object
  result[AttributeId.EventNotifier] = nodeAttrs.EventNotifier
  return result
end


local nextNodeIdentifier = math.floor(os.time())
local function genNodeId()
  nextNodeIdentifier = nextNodeIdentifier + 1
  return "i=" .. nextNodeIdentifier
end

function Svc:addNode(node)
  local dbgOn = self.trace.dbgOn
  local errOn = self.trace.errOn
  local infOn = self.trace.infOn
  if dbgOn then traceD("Services:addNode |") end

  if node.ParentNodeId == nil then
    if errOn then traceE("Services:addNode | nil parent node ID") end
    error(BadParentNodeIdInvalid)
  end

  local parent = self.nodeset:getNode(node.ParentNodeId)
  if parent == nil then
    if errOn then traceE("Services:addNode | Parent node absent") end
    error(BadParentNodeIdInvalid)
  end

  local refNode = self.nodeset:getNode(node.ReferenceTypeId)
  if refNode == nil or refNode.attrs[AttributeId.NodeClass] ~= ua.Types.NodeClass.ReferenceType then
    if errOn then traceE("Services:addNode | Invalid referenceTypeId") end
    error(BadReferenceTypeIdInvalid)
  end

  if not ua.Tools.browseNameValid(node.BrowseName) then
    if errOn then traceE("Services:addNode | Invalid BrowseName") end
    error(BadBrowseNameInvalid)
  end

  if not ua.Tools.nodeClassValid(node.NodeClass) then
    if errOn then traceE("Services:addNode | Invalid NodeClass") end
    error(BadNodeClassInvalid)
  end

  local typeNode =self.nodeset:getNode(node.TypeDefinition)
  if typeNode == nil then
    if errOn then traceE("Services:addNode | Unknown TypeDefinition NodeID") end
    error(BadTypeDefinitionInvalid)
  end

  if typeNode.attrs[AttributeId.NodeClass] ~= ua.Types.NodeClass.VariableType and typeNode.attrs[AttributeId.NodeClass] ~= ua.Types.NodeClass.ObjectType then
    if errOn then traceE("Services:addNode | Invalid TypeDefinition. Only VariableType and ObjectType supported now.") end
    error(BadTypeDefinitionInvalid)
  end

  local nodeId = node.RequestedNewNodeId
  if ua.NodeId.isNull(nodeId) then
    nodeId = genNodeId()
    if dbgOn then traceD(fmt("Services:addNode | generated new nodeId='%s'", nodeId)) end
  elseif self.nodeset:getNode(nodeId) ~= nil then
    if errOn then traceE(fmt("Services:addNode | Node '%s' already exist", nodeId)) end
    error(BadNodeIdExists)
  end

  -- transform input parameters into array of new node attributes
  local resultAttrs
  local type
  if node.NodeClass == ua.Types.NodeClass.Variable then
    type = 'variable'
    if infOn then traceI("Services:addNode | Adding new variable node.") end
    resultAttrs = self:getVariableAttributes(nodeId, node, self.nodeset)
  elseif node.NodeClass == ua.Types.NodeClass.Object then
    type = 'object'
    if infOn then traceI("Services:addNode | Adding new object.") end
    resultAttrs = self:getObjectAttributes(nodeId, node)
  else
    if infOn then traceI("Services:addNode | Invalid Node class.") end
    error(BadNodeClassInvalid)
  end

  if infOn then traceI(fmt("Services:addNode | adding %s: nodID='%s' parent='%s', refId='%s', name='%s'", type, nodeId, node.ParentNodeId, node.ReferenceTypeId, node.BrowseName.Name)) end

  local newNodes = {}

  -- New object skeleton
  -- Add type definition becuase we instantiating a type which has no typedefinition reference
  -- Other references will be filled up further
  local n = {
    attrs = resultAttrs,
    refs = {
      {target=node.TypeDefinition, type=HasTypeDefinition, isForward=true},
    }
  }

  -- queue newNode -> referencies from instance declaration we should mirror
  local nodes = { {n = n, refs=typeNode.refs} }

  -- Depth First Search for all references to children nodes.
  while #nodes ~= 0 do
    local skel = nodes[#nodes]
    nodes[#nodes] = nil

    local curParent = skel.n
    -- enumerate all nodes with modelling rule Mandatory and create target node.
    for _,ref in pairs(skel.refs) do
      repeat
        --print(k, ref.target, ref.type, ref.isForward)
        if ref.isForward == false then
          break -- continue
        end

        local refId = ref.type
        local nextId = ref.target
        -- check if target node mandatory during instantiating
        if dbgOn then traceD(fmt("Services:addNode | searching node '%s'", ref.target)) end
        local instanceNode = self.nodeset:getNode(ref.target)
        if refId ~= HasTypeDefinition then
          local isMandatory = false
          assert(instanceNode, ref.target)
          for _,iref in ipairs(instanceNode.refs) do
            if iref.type == HasModellingRule then
              isMandatory = iref.target == ModellingRule_Mandatory
              break
            end
          end

          if not isMandatory then
            break -- continue processing next refefence
          end

          local newNode = {
            attrs = {},
            refs = {}
          }

          nextId = genNodeId()
          for i,attr in pairs(instanceNode.attrs) do
            if i == AttributeId.NodeId then
              newNode.attrs[i] = nextId
            else
              newNode.attrs[i] = attr
            end
          end
          tins(nodes, {n=newNode, refs=instanceNode.refs})
        end

        local newRef = {
          isForward = ref.isForward,
          target = nextId,
          type = refId
        }

        tins(curParent.refs, newRef)
      until true
    end
    tins(newNodes, curParent)
  end

  -- add collected nodes hierarchy to
  tins(parent.refs, {target=nodeId, type=node.ReferenceTypeId, isForward=true})
  self.nodeset:saveNode(parent)

  for _,newNode in ipairs(newNodes) do
    self.nodeset:saveNode(newNode)
  end
  if infOn then traceI(fmt("Services:addNode | new node '%s' added",nodeId)) end

  return nodeId
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

function Svc:setVariableSource(nodeId, func)
  local dbgOn = self.trace.dbgOn
  if dbgOn then traceD(fmt("Setting source callback for node '%s'", nodeId)) end
  if type(func) ~= 'function' then
    error(BadInvalidArgument)
  end

  local node = self.nodeset:getNode(nodeId)
  if nodeId == nil then
    if dbgOn then traceD(fmt("Setting source callback failed: nodeId '%s' unknown", nodeId)) end
    error(BadNodeIdUnknown)
  end
  if node.attrs[ua.Types.AttributeId.NodeClass] ~= ua.Types.NodeClass.Variable then
    if dbgOn then traceD(fmt("Setting source callback failed: nodeId '%s' is not a variable", nodeId)) end
    error(BadNodeClassInvalid)
  end

  node.attrs.valueSource = func
  self.nodeset:saveNode(node)
  if dbgOn then traceD(fmt("Source callback for nodeId '%s' was set", nodeId)) end
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


local function newServices(config)
  assert(config ~= nil)

  local svc = {
    endpointUrl = config.endpointUrl,
    trace = config.logging.services,
    config = config,
    sessions = {}
  }

  setmetatable(svc, Svc)
  return svc
end

return {new=newServices}
