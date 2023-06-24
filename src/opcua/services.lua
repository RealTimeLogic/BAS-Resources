local ua = require("opcua.api")
local attrs = require("opcua.services_attributes")
local createCert = require("opcua.binary.crypto.certificate").createCert
local securePolicy = require("opcua.binary.crypto.policy")
local Q = require("opcua.binary.queue")
local Binary = require("opcua.binary.encode_types")


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
  self.nodeset = require("opcua.address_space")
  self.srvObject = require("opcua.server_object")
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
    if dbgOn then traceD(fmt("Services:closeSecureChannel(ch:%s) Session '%s' deactivated", channelId, session.sessionId)) end
    session.active = false
  end
end


function Svc:getServerDescription()
  local dbgOn = self.trace.dbgOn
  if dbgOn then traceD("Services:GetServerDescription | ") end

  return {
    applicationUri = self.config.applicationUri,
    applicationName = {
      locale = "en-US",
      text = self.config.applicationName
    },

    productUri = ua.Version.ProductUri,
    applicationType = ua.Types.ApplicationType.Server,
    gatewayServerUri = nil,
    discoveryProfileUri = ua.Types.ServerProfile.NanoEmbedded2017,
    discoveryUrls = {self.endpointUrl}
  }
end


function Svc:findServers(req)
  local dbgOn = self.trace.dbgOn
  if dbgOn then traceD("Services:findServers | ") end
  req.header = req.header -- TODO Unused: can be useful?
  return {servers = {self:getServerDescription()}}
end

function Svc:addEndpointDescriptions(endpointUrl, policy, endpoints)
  local certificate = policy.certificate or self.config.certificate
  local der = certificate and createCert(certificate, self.config.io).der
  local tokenPolicies = self.config.userIdentityTokens
  for _,mode in ipairs(policy.securityMode) do
    local endpoint = {
      endpointUrl = endpointUrl,
      serverCertificate = der,
      securityMode = mode,
      securityPolicyUri = policy.securityPolicyUri,
      server = self:getServerDescription(),
      userIdentityTokens = tokenPolicies,
      transportProfileUri = ua.Types.TranportProfileUri.Binary,
      securityLevel = 0 -- TODO
    }

    tins(endpoints, endpoint)
  end
end

function Svc:listEndpoints()
  local endpoints = {}
  for _,policy in ipairs(self.config.securePolicies) do
    self:addEndpointDescriptions(self.config.endpointUrl, policy, endpoints)
  end
  return endpoints
end


function Svc:getEndpoints(req)
  local dbgOn = self.trace.dbgOn
  if dbgOn then traceD("Services:getEndpoints | ") end
  req.header = req.header -- TODO Unused: can be useful?

  return {endpoints=self:listEndpoints()}
end


local sessionsNum = math.floor(os.time())
local function getSessionNum()
  sessionsNum = sessionsNum + 1
  return sessionsNum
end

function Svc:createSession(req, channel)
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

  local sessionTimeoutSecs = math.max(30000, req.requestedSessionTimeout) / 1000
  local curTime = os.time()
  session = {
    channelId = channel.channelId,
    sessionId = "ns=1;i="..getSessionNum(),
    authenticationToken = "ns=1;s="..getSessionNum(),
    nonce = policy:genNonce(32),
    sessionExpirationTime = curTime + sessionTimeoutSecs,
    sessionTimeoutSecs = sessionTimeoutSecs
  }

  local resp = {}
  resp.sessionId = session.sessionId
  resp.authenticationToken = session.authenticationToken
  resp.revisedSessionTimeout = sessionTimeoutSecs * 1000
  resp.serverNonce = session.nonce
  resp.serverCertificate = policy:getLocalCert()
  resp.maxRequestMessageSize = 0
  resp.serverEndpoints = self:listEndpoints()
  resp.serverSoftwareCertificates = nil

  if policy.uri ~= ua.Types.SecurityPolicy.None then
    resp.serverSignature = {
      algorithm = policy.aSignatureUri,
      signature = policy:asymmetricSign(req.clientCertificate..req.clientNonce)
    }
  else
    resp.serverSignature = {}
  end

  self.sessions[channel.channelId] = session
  self:startSessionCleanup()

  if infOn then traceI(fmt("Services:CreateSession(ch:%s) | Created session '%s'  expiration time '%s'", channel.channelId, session.sessionId, session.sessionExpirationTime)) end

  return resp
end

local function decrypt(policy, data)
  if not policy then
    return data
  end
  local m,err = ba.crypto.decrypt(data, policy.key, {nopadding=false})
  if err then
    error(BadIdentityTokenInvalid)
  end
  local d = Q.new(#m)
  d:pushBack(m)
  local decoder = Binary.Decoder.new(d)
  local l = decoder:uint32()
  local token = decoder:str(l - 32)
  -- local nonce = decoder:str(32) // TODO: check nonce

  return token
end


local function checkSignature(policy, signature, ...)
  if not signature or not signature.signature then
    return
  end

  if signature.algorithm ~= policy.aSignatureUri then
    return
  end

  if not policy:asymmetricVerify(signature.signature, ...) then
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

  if dbgOn then traceD(fmt("Services:activateSession(ch:'%s')", channel.channelId)) end

  local session = self.sessions[channel.channelId]
  if not session then
    if infOn then traceI(fmt("Services:activateSession(ch:'%s') | Channel has no session. Try to find by auth token '%s'", channel.channelId, req.requestHeader.authenticationToken)) end
    for _, ses in pairs(self.sessions) do
      if ses.authenticationToken == req.requestHeader.authenticationToken then
        session = ses
        break
      end
    end
  end

  if not session then
    if infOn then traceI(fmt("Services:activateSession(ch:'%s') | Session not found", channel.channelId)) end
    error(BadSessionClosed)
  elseif session.authenticationToken ~= req.requestHeader.authenticationToken then
    if infOn then traceI(fmt("Services:activateSession(ch:'%s') | Invalid auth token '%s'", channel.channelId, req.requestHeader.authenticationToken)) end
    error(BadRequestHeaderInvalid)
  end

  local policy = channel:getLocalPolicy()
  if policy.secureMode == 2 or policy.secureMode == 3 then
    if not checkSignature(policy, req.clientSignature, policy.certificate.der, session.nonce) then
      if errOn then traceE(fmt("Services:activateSession(ch:'%s') | Invalid client signature", channel.channelId)) end
      error(BadApplicationSignatureInvalid)
    end
  end

  local authenticate = self.config.authenticate or allowAll
  if dbgOn then traceD(fmt("Services:activateSession(ch:'%s') | Validating identity token", channel.channelId)) end

  local allowed = false
  local token = req.userIdentityToken
  local tokenTypeId = token.typeId
  local authPolicy
  local encryption
  local tokenPolicy
  for _, p in ipairs(self.config.userIdentityTokens) do
    if p.policyId == token.body.policyId then
      tokenPolicy = p
      break
    end
  end

  if not tokenPolicy then
    if dbgOn then traceD(fmt("Services:activateSession(ch:'%s') | Invalid identity token policy", channel.channelId)) end
    error(BadIdentityTokenRejected)
  end

  if token.body.encryptionAlgorithm then
    encryption = securePolicy(self.config)
    authPolicy = encryption(tokenPolicy.securityPolicyUri)
    if authPolicy.aEncryptionAlgorithm ~= token.body.encryptionAlgorithm then
      if errOn then traceE(fmt("Services:activateSession(ch:'%s') | Cannot find secure policy", channel.channelId)) end
      error(BadIdentityTokenRejected)
    end
  end

  if tokenTypeId == "i=321" then
    if infOn then traceI(fmt("Services:activateSession(ch:'%s') | Check anonymous token", channel.channelId)) end
    if tokenPolicy.tokenType ~= ua.Types.UserTokenType.Anonymous then
      if errOn then traceE(fmt("Services:activateSession(ch:'%s') | Not an anonymous token ", channel.channelId)) end
      error(BadIdentityTokenRejected)
    end
    allowed = authenticate("anonymous")
  elseif tokenTypeId == "i=324" then
    if infOn then traceI(fmt("Services:activateSession(ch:'%s') | Check User Name", channel.channelId)) end
    local password = decrypt(authPolicy, token.body.password)
    allowed = authenticate("username", password, token.body.userName)
  elseif tokenTypeId == "i=327" then
    if infOn then traceI(fmt("Services:activateSession(ch:'%s') | Check x509 certificate", channel.channelId)) end
    if tokenPolicy.securityPolicyUri and tokenPolicy.securityPolicyUri ~= ua.Types.SecurityPolicy.None or req.userTokenSignature.signature then
      encryption = securePolicy(self.config)
      authPolicy = encryption(tokenPolicy.securityPolicyUri)
      if req.userTokenSignature.algorithm ~= authPolicy.aSignatureUri then
        if infOn then traceI(fmt("Services:activateSession(ch:'%s') | Unknown encryption algorithm", channel.channelId)) end
        error(BadUserSignatureInvalid)
      end

      authPolicy:setRemoteCertificate(token.body.certificateData)
      if not checkSignature(authPolicy, req.userTokenSignature, authPolicy:getLocalCert(), session.nonce) then
        if infOn then traceI(fmt("Services:activateSession(ch:'%s') | Invalid user token signature", channel.channelId)) end
        error(BadUserSignatureInvalid)
      end
    end
    allowed = authenticate("x509", token.body.certificateData)
  elseif tokenTypeId == "i=940" then -- IssuedToken
    local tokenData = decrypt(authPolicy, token.body.tokenData)
    if tokenPolicy.issuedTokenType == ua.Types.IssuedTokenType.Azure then
      if infOn then traceI(fmt("Services:activateSession(ch:'%s') | Check Azure token", channel.channelId)) end
      allowed = authenticate("azure", tokenData, tokenPolicy.issuerEndpointUrl)
    elseif tokenPolicy.issuedTokenType == ua.Types.IssuedTokenType.JWT then
      if infOn then traceI(fmt("Services:activateSession(ch:'%s') | Check JWT token", channel.channelId)) end
      allowed = authenticate("jwt", tokenData, tokenPolicy.issuerEndpointUrl)
    elseif tokenPolicy.issuedTokenType == ua.Types.IssuedTokenType.OAuth2 then
      if infOn then traceI(fmt("Services:activateSession(ch:'%s') | Check OAuth2 token", channel.channelId)) end
      allowed = authenticate("oauth2", tokenData, tokenPolicy.issuerEndpointUrl)
    elseif tokenPolicy.issuedTokenType == ua.Types.IssuedTokenType.OPCUA then
      if infOn then traceI(fmt("Services:activateSession(ch:'%s') | Check OPCUA token", channel.channelId)) end
      allowed = authenticate("opcua", tokenData, tokenPolicy.issuerEndpointUrl)
    else
      if errOn then traceE(fmt("Services:activateSession(ch:'%s') | Unknown issued token type '%s'", channel.channelId, tokenPolicy.issuedTokenType)) end
      error(BadIdentityTokenRejected)
    end
  else
    if errOn then traceE(fmt("Services:activateSession(ch:'%s') | Unknown token id '%s'", channel.channelId, tokenTypeId)) end
    error(BadIdentityTokenRejected)
  end

  assert(type(allowed) == "boolean")

  if not allowed then
    if errOn then traceE(fmt("Services:activateSession(ch:'%s') | Access denied", channel.channelId)) end
    error(BadUserAccessDenied)
  end

  if session.channelId ~= channel.channelId then
    self.sessions[session.channelId] = nil
    session.channelId = channel.channelId
    self.sessions[channel.channelId] = session
  end


  local curTime = os.time()
  session.sessionExpirationTime = curTime + session.sessionTimeoutSecs
  session.nonce = policy:genNonce(32)
  session.activated = true
  local result = {
    serverNonce = session.nonce,
    results = {Good}
  }

  if infOn then traceI(fmt("Services:activateSession(ch:'%s') | Access permitted", channel.channelId)) end

  return result;
end

function Svc:closeSession(_, channel)
  local errOn = self.trace.errOn
  local infOn = self.trace.infOn

  if infOn then traceI(fmt("Services:closeSession(ch:%s)", channel.channelId)) end

  local session = self.sessions[channel.channelId]
  if not session then
    if errOn then traceE(fmt("Svc:checkSession(ch:%s) | No session. ", channel.channelId)) end
    error(BadSessionClosed)
  end

  self.sessions[channel.channelId] = nil
  if infOn then traceI(fmt("Services:closeSession(ch:%s) | Session '%s' closed", channel.channelId, session and session.sessionId)) end
  return {}
end

local idxNode = 1
local idxRef = 2
local idxForward = 3

function Svc:getSubtypes(parent, cont)
  if parent == nil then
    return cont
  end

  cont[parent.attrs[AttributeId.NodeId]] = 1

  local nodeClass = parent.attrs[AttributeId.NodeClass] -- node class of an inspecting type hierarchy
  for _,ref in ipairs(parent.refs) do
    repeat-- emulate continue
      if ref[idxRef] ~= HasSubtype then
        break -- continue
      end

      local subtypeId = ref[idxNode]
      local subtype = self.nodeset:getNode(subtypeId)
      if subtype == nil or ref[idxForward] == 0 then
        break
      end

      -- Collect only the same node class
      if subtype.attrs[AttributeId.NodeClass] ~= nodeClass then
        break -- continue
      end

      self:getSubtypes(subtype, cont)
    until true
  end

  return cont
end


function Svc:browse(req, channel)
  self:checkSession(req, channel)

  local errOn = self.trace.errOn
  local infOn = self.trace.infOn
  local dbgOn = self.trace.dbgOn

  if req.nodesToBrowse[1] == nil then
    if infOn then traceI(fmt("Services:browse(ch:%s) | Nothing to do", channel.channelId)) end
    error(BadNothingToDo)
  end

  local results = {}
  for _,n in pairs(req.nodesToBrowse) do
    local result = {
      continuationPoint = nil,
      references = {}
    }

    if infOn then
      traceI(fmt("Services:browse(ch:%s) | NodeID='%s', BrowseDirection=%s, ReferenceID='%s', IncludeSubtypes=%s",
      channel.channelId, n.nodeId, n.browseDirection, n.referenceTypeId,n.includeSubtypes))
    end

    repeat
      if n.browseDirection == nil or n.browseDirection < 0 or n.browseDirection > 2 then
        if errOn then traceE(fmt("Services:browse(ch:%s) | Invalid browse direction '%s'", channel.channelId, n.browseDirection)) end
        result.statusCode = BadBrowseDirectionInvalid
        break
      end

      local node = self.nodeset:getNode(n.nodeId)
      if node == nil then
        if errOn then traceE(fmt("Services:browse(ch:%s) | Unknown node ID '%s'", channel.channelId, n.nodeId)) end
        result.statusCode = BadNodeIdUnknown
        break
      end

      -- collect subtypes of reference type
      local refNode = self.nodeset:getNode(n.referenceTypeId)
      if refNode == nil then
        if errOn then traceE(fmt("Services:browse(ch:%s) | Unknown Reference ID %s", channel.channelId, n.referenceTypeId)) end
        result.statusCode = BadReferenceTypeIdInvalid
        break
      end

      local refTypes = {}
      if n.includeSubtypes == 1 or n.includeSubtypes == true then
        if dbgOn then traceD(fmt("Services:browse(ch:%s) | Collecting subtypes of refererence", channel.channelId)) end
        self:getSubtypes(refNode, refTypes)
      else
        refTypes[n.referenceTypeId] = 1
      end

      if dbgOn then traceD(fmt("Services:browse(ch:%s) | node has %d refs", channel.channelId, #node.refs)) end

      local isForward = n.browseDirection == ua.Types.BrowseDirection.Forward and 1 or 0
      result.statusCode = Good
      for _,ref in pairs(node.refs) do
        repeat
          local refId = ref[idxRef]
          if dbgOn then
            traceD(fmt("Services:browse(ch:%s) | NodeId='%s', ReferenceID='%s', isForward='%d'", channel.channelId, ref[idxNode], refId, ref[idxForward]))
          end

          if refTypes[refId] == nil or (n.browseDirection ~= ua.Types.BrowseDirection.Both and ref[idxForward] ~= isForward) then
            if dbgOn then traceD(fmt("Services:browse(ch:%s) | reference has different direction from %d", channel.channelId, n.browseDirection)) end
            break
          end

          local targetNode = self.nodeset:getNode(ref[idxNode])
          if not targetNode then
            error(BadInternalError)
          end

          local displayName = attrs.getAttributeValue(targetNode.attrs, AttributeId.DisplayName, self.nodeset)
          local browseName = attrs.getAttributeValue(targetNode.attrs, AttributeId.BrowseName, self.nodeset)

          assert(t.getVariantType(displayName.value) == LocalizedText)
          assert(t.getVariantType(browseName.value) == QualifiedName)

          if dbgOn then traceD(fmt("Services:browse(ch:%s) |   Target node browseName='%s'", channel.channelId, browseName.value.qualifiedName.name)) end

          local nodeClass = targetNode.attrs[AttributeId.NodeClass]
          local typeDefinition = ua.NodeId.Null

          if nodeClass == NodeClass.Object or nodeClass == NodeClass.Variable then
            for _, r in ipairs(targetNode.refs) do
              if r[idxRef] == HasTypeDefinition then
                typeDefinition = r[idxNode]
                break
              end
            end
          end

          local r = {
            nodeId = ref[idxNode],
            referenceTypeId = refId,
            isForward = ref[idxForward],
            nodeClass = nodeClass,
            browseName = browseName.value.qualifiedName,
            typeDefinition = typeDefinition,
            displayName = displayName.value.localizedText
          }

          tins(result.references, r)
          if dbgOn then
            traceD(fmt("Services:browse(ch:%s) |   ReferenceID='%s' ->  BrowseName='%s', TargetNodeID='%s'",
              channel.channelId, r.referenceTypeId, r.browseName.name, r.nodeId))
          end
        until true
      end
    until true

    tins(results, result)
  end
  if dbgOn then traceD(fmt("Services:browse(ch:%s) | done", channel.channelId)) end
  return {results=results}
end

function Svc:translateBrowsePath(path)
  local dbgOn = self.trace.dbgOn
  if dbgOn then traceD("Services:translateBrowsePath |") end

    -- result for current path
  if path.relativePath == nil or path.relativePath.elements == nil or #path.relativePath.elements == 0 then
    if dbgOn then traceD("Services:translateBrowsePath | no relative paths to process") end
    error(BadNoMatch)
  end

  local targetId = path.startingNode
  if dbgOn then traceD(fmt("Services:translateBrowsePath | target node %s", targetId)) end
  local targetNode = self.nodeset:getNode(targetId)
  if targetNode == nil then
    if dbgOn then traceD("Services:translateBrowsePath | target node not found") end
    error(BadNodeIdUnknown)
  end

  local targets = {}

  if dbgOn then traceD(fmt("Services:translateBrowsePath | elements %d", #path.relativePath.elements)) end

  for rel_idx,rel in ipairs(path.relativePath.elements) do
    -- Collect all reference type we should follow: Requested reference and its Sybtypes
    if dbgOn then traceD(fmt("Services:translateBrowsePath | element %d: browseName=%s, referenceTypeId=%s, includeSubtypes=%d", rel_idx, rel.targetName.name, rel.referenceTypeId, rel.includeSubtypes)) end

    local refTypes = {}
    local refId = rel.referenceTypeId
    if rel.includeSubtypes == 1 then
      if dbgOn then traceD(fmt("Services:translateBrowsePath | Collecting subtypes of reference %s", rel.referenceTypeId)) end
      self:getSubtypes(self.nodeset:getNode(refId), refTypes)
    else
      refTypes[refId] = 1
    end

    local nextTargetId = nil
    -- follow all referencies of a node and compare it with selected reference types
    for _,nodeRef in ipairs(targetNode.refs) do
      repeat
        local refType = nodeRef[idxRef]
        if dbgOn then traceD(fmt("Services:translateBrowsePath | Processing reference %s", refType)) end

        if nodeRef[idxForward] == rel.isInverse then
          if dbgOn then traceD("Services:translateBrowsePath | Invalid direction") end
          break
        end

        if refTypes[refType] ~= 1 then
          if dbgOn then traceD("Services:translateBrowsePath | Not a suitable reference type") end
          break
        end

        local nodeId = nodeRef[idxNode]
        if dbgOn then traceD(fmt("Services:translateBrowsePath | target node id %s", nodeId)) end
        local node = self.nodeset:getNode(nodeId)
        if node == nil then
          if dbgOn then traceD(fmt("Services:translateBrowsePath | node %s not found", nodeId)) end
          break
        end

        if node.attrs[AttributeId.BrowseName].name ~= rel.targetName.name then
          if dbgOn then traceD(fmt("Services:translateBrowsePath | browse name %s different", node.attrs[AttributeId.BrowseName].name)) end
          break
        end

        nextTargetId = nodeId
        targetNode = node
        if dbgOn then traceD(fmt("Services:translateBrowsePath | Next target node '%s'", nodeId)) end
      until true

      if nextTargetId ~= nil then
        break
      end
    end

    targetId = nextTargetId
    if targetId == nil then
      if dbgOn then traceD("Services:translateBrowsePath | No match") end
      error(BadNoMatch)
    end
  end

  if targetId ~= nil then
    tins(targets, {targetId=targetId, remainingPathIndex=0xFFFFFFFF})
  end

  return targets
end


function Svc:translateBrowsePaths(req, channel)
  self:checkSession(req, channel)
  local dbgOn = self.trace.dbgOn
  if dbgOn then
    traceD(fmt("Services:translateBrowsePaths(ch:%s) | %d paths", channel.channelId, #req.browsePaths))
  end

  if #req.browsePaths == 0 then
    error(BadNothingToDo)
  end

  local results = {}

  for _, path in ipairs(req.browsePaths) do
    local suc, result = pcall(self.translateBrowsePath, self, path)
    if suc == true then
       if dbgOn then traceD(fmt("Services:translateBrowsePaths(ch:%s) | success", channel.channelId)) end
      tins(results, {statusCode = s.Good, targets=result})
    else
      if dbgOn then traceD(fmt("Services:translateBrowsePaths(ch:%s) | error %x", channel.channelId, result)) end
      tins(results, {statusCode = result, targets={}})
    end
  end

  if dbgOn then traceD(fmt("Services:translateBrowsePaths(ch:%s) | done", channel.channelId)) end
  return {results=results}
end

function Svc:read(req, channel)
  local dbgOn = self.trace.dbgOn
  local infOn = self.trace.infOn

  if infOn then traceI(fmt("Services:Read(ch:%s)", channel.channelId)) end
  self:checkSession(req, channel)

  if req.nodesToRead == nil or #req.nodesToRead == 0 then
    if dbgOn then traceD(fmt("Services:Read(ch:%s) | Empty request received", channel.channelId)) end
    error(BadNothingToDo)
  end

  local results = {}
  for _, r in ipairs(req.nodesToRead) do
    local val = {}
    local node = self.nodeset:getNode(r.nodeId)
    if node == nil then
      if dbgOn then traceD(fmt("Services:Read(ch:%s) | Unknown node id %s", channel.channelId, r.nodeId)) end
      val.statusCode = BadNodeIdUnknown
    else
      if dbgOn then traceD(fmt("Services:Read(ch:%s) | Reading node id '%s' attribute %d ", channel.channelId, r.nodeId, r.attributeId)) end
      local suc,result = pcall(attrs.getAttributeValue, node.attrs, r.attributeId, self.nodeset)
      if not suc then
        val.statusCode = result
      else
        val = result
        if val.statusCode == nil then
          val.statusCode = 0
        end
      end
    end

    if val.statusCode ~= Good and dbgOn then
      traceD(fmt("Services:Read(ch:%s) | StatusCode %d", channel.channelId, val.statusCode))
    end

    tins(results, val)
  end

  return {results=results}
end

function Svc:writeNode(val)
  local dbgOn = self.trace.dbgOn
  local nodeId = val.nodeId
  local attributeId = val.attributeId
  local value = val.value
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
    attrs.checkAttributeValue(n.attrs, attributeId, value and value.value, self.nodeset)
    n.attrs[attributeId] = value.value
  end
  self.nodeset:saveNode(n)
  if dbgOn then traceD(fmt("Services:Write | updated attribute '%d' of node '%s' ", attributeId, nodeId)) end
end


function Svc:write(req, channel)
  local infOn = self.trace.infOn
  if infOn then traceI(fmt("Services:Write")) end
  self:checkSession(req, channel)
  channel = channel or {}

  if infOn then traceI(fmt("Services:Write(ch:%s)", channel.channelId)) end
  if req.nodesToWrite == nil or req.nodesToWrite[1] == nil then
    if infOn then traceI(fmt("Services:Write(ch:%s) | Empty response received", channel.channelId)) end
    error(BadNothingToDo)
  end

  local results = {}
  for _, val in ipairs(req.nodesToWrite) do
    if infOn then traceI(fmt("Services:Write(ch:%s) | Writing '%s'", channel.channelId, val.nodeId)) end
    local suc, code = pcall(self.writeNode, self, val)
    if suc then
      code = 0
    end
    if infOn then traceI(fmt("Services:Write(ch:%s) | '%s' result '%s'", channel.channelId, val.nodeId, code)) end
    tins(results, code)
  end

  return {results=results}
end

-- Create node attributes array from parameters of new node.
function Svc:getCommonAttributes(nodeId, nodeAttrs)
  local errOn = self.trace.errOn
  if not t.localizedTextValid(nodeAttrs.displayName) then
    if errOn then traceE("Services:addNodes | displayName invalid") end
    error(BadNodeAttributesInvalid)
  end
  if not t.localizedTextValid(nodeAttrs.description) then
    if errOn then traceE("Services:addNodes | Description invalid") end
    error(BadNodeAttributesInvalid)
  end
  if not t.uint32Valid(nodeAttrs.writeMask) then
    if errOn then traceE("Services:addNodes | WriteMask invalid") end
    error(BadNodeAttributesInvalid)
  end
  if not t.uint32Valid(nodeAttrs.userWriteMask) then
    if errOn then traceE("Services:addNodes | UserWriteMask invalid") end
    error(BadNodeAttributesInvalid)
  end

  local result = {}
  result[AttributeId.NodeId] = nodeId
  result[AttributeId.BrowseName] = nodeAttrs.browseName
  result[AttributeId.DisplayName] = nodeAttrs.displayName
  result[AttributeId.Description] = nodeAttrs.description
  result[AttributeId.WriteMask] = nodeAttrs.writeMask
  result[AttributeId.UserWriteMask] = nodeAttrs.userWriteMask
  return result
end

-- Create variable node attributes array from new node parameters
function Svc:getVariableAttributes(nodeId, nodeAttrs, nodeset)
  local dbgOn = self.trace.dbgOn
  local errOn = self.trace.errOn

  if dbgOn then traceD("Services:addNodes | Creating variable node attributes") end

  local result = self:getCommonAttributes(nodeId, nodeAttrs, nodeAttrs)

  if not t.nodeIdValid(nodeAttrs.dataType)  then
    if errOn then traceE("Services:addNodes | DataType invalid") end
    error(BadNodeAttributesInvalid)
  end
  if not t.variantValid(nodeAttrs.value) then
    if errOn then traceE("Services:addNodes | Value invalid") end
    error(BadNodeAttributesInvalid)
  end
  if not t.valueRankValid(nodeAttrs.valueRank) then
    if errOn then traceE("Services:addNodes | ValueRank invalid") end
    error(BadNodeAttributesInvalid)
  end
  if not t.arrayDimensionsValid(nodeAttrs.value, nodeAttrs.arrayDimensions, nodeAttrs.valueRank) then
    if errOn then traceE("Services:addNodes | ArrayDimensions invalid") end
    error(BadNodeAttributesInvalid)
  end
  if not t.uint32Valid(nodeAttrs.accessLevel) then
    if errOn then traceE("Services:addNodes | AccessLevel invalid") end
    error(BadNodeAttributesInvalid)
  end
  if not t.uint32Valid(nodeAttrs.userAccessLevel) then
    if errOn then traceE("Services:addNodes | UserAccessLevel invalid") end
    error(BadNodeAttributesInvalid)
  end
  if not t.uint32Valid(nodeAttrs.minimumSamplingInterval) then
    if errOn then traceE("Services:addNodes | MinimumSamplingInterval invalid") end
    error(BadNodeAttributesInvalid)
  end
  if not t.booleanValid(nodeAttrs.historizing) then
    if errOn then traceE("Services:addNodes | Historizing invalid") end
    error(BadNodeAttributesInvalid)
  end
  local suc, code = pcall(attrs.checkDataType, nodeAttrs.value, nodeAttrs.dataType, nodeset)
  if not suc then
    if errOn then traceE("Services:addNodes | DataType of Value invalid") end
    error(code)
  end

  result[AttributeId.NodeClass] = ua.Types.NodeClass.Variable
  result[AttributeId.Value] = {value = nodeAttrs.value}
  result[AttributeId.DataType] = nodeAttrs.dataType
  result[AttributeId.Rank] = nodeAttrs.valueRank
  result[AttributeId.ArrayDimensions] = nodeAttrs.arrayDimensions
  result[AttributeId.AccessLevel] = nodeAttrs.accessLevel
  result[AttributeId.UserAccessLevel] = nodeAttrs.userAccessLevel
  result[AttributeId.MinimumSamplingInterval] = nodeAttrs.minimumSamplingInterval
  result[AttributeId.Historizing] = nodeAttrs.historizing

  return result
end

-- Create Object node attributes from new object parameters
function Svc:getObjectAttributes(nodeId, nodeAttrs)
  local dbgOn = self.trace.dbgOn
  local errOn = self.trace.errOn

  if dbgOn then traceD("Services:addNodes | Creating object node attributes") end

  if not t.byteValid(nodeAttrs.eventNotifier) then
    if errOn then traceE("Services:addNodes | AccessLevel invalid") end
    error(BadNodeAttributesInvalid)
  end

  local result = self:getCommonAttributes(nodeId, nodeAttrs)
  result[AttributeId.NodeClass] = ua.Types.NodeClass.Object
  result[AttributeId.EventNotifier] = nodeAttrs.eventNotifier
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

  if node.parentNodeId == nil then
    if errOn then traceE("Services:addNode | nil parent node ID") end
    error(BadParentNodeIdInvalid)
  end

  local parent = self.nodeset:getNode(node.parentNodeId)
  if parent == nil then
    if errOn then traceE("Services:addNode | Parent node absent") end
    error(BadParentNodeIdInvalid)
  end

  local refNode = self.nodeset:getNode(node.referenceTypeId)
  if refNode == nil or refNode.attrs[AttributeId.NodeClass] ~= ua.Types.NodeClass.ReferenceType then
    if errOn then traceE("Services:addNode | Invalid referenceTypeId") end
    error(BadReferenceTypeIdInvalid)
  end

  if not ua.Tools.browseNameValid(node.browseName) then
    if errOn then traceE("Services:addNode | Invalid browseName") end
    error(BadBrowseNameInvalid)
  end

  if not ua.Tools.nodeClassValid(node.nodeClass) then
    if errOn then traceE("Services:addNode | Invalid NodeClass") end
    error(BadNodeClassInvalid)
  end

  local typeNode =self.nodeset:getNode(node.typeDefinition)
  if typeNode == nil then
    if errOn then traceE("Services:addNode | Unknown TypeDefinition NodeID") end
    error(BadTypeDefinitionInvalid)
  end

  if typeNode.attrs[AttributeId.NodeClass] ~= ua.Types.NodeClass.VariableType and typeNode.attrs[AttributeId.NodeClass] ~= ua.Types.NodeClass.ObjectType then
    if errOn then traceE("Services:addNode | Invalid TypeDefinition. Only VariableType and ObjectType supported now.") end
    error(BadTypeDefinitionInvalid)
  end

  local nodeId = node.requestedNewNodeId
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
  if node.nodeClass == ua.Types.NodeClass.Variable then
    type = 'variable'
    if infOn then traceI("Services:addNode | Adding new variable node.") end
    resultAttrs = self:getVariableAttributes(nodeId, node, self.nodeset)
  elseif node.nodeClass == ua.Types.NodeClass.Object then
    type = 'object'
    if infOn then traceI("Services:addNode | Adding new object.") end
    resultAttrs = self:getObjectAttributes(nodeId, node)
  else
    if infOn then traceI("Services:addNode | Invalid Node class.") end
    error(BadNodeClassInvalid)
  end

  if infOn then traceI(fmt("Services:addNode | adding %s: nodID='%s' parent='%s', refId='%s', name='%s'", type, nodeId, node.parentNodeId, node.referenceTypeId, node.browseName.name)) end

  local newNodes = {}

  -- New object skeleton
  -- Add type definition becuase we instantiating a type which has no typedefinition reference
  -- Other references will be filled up further
  local n = {
    attrs = resultAttrs,
    refs = {
      {node.typeDefinition, HasTypeDefinition, 1},
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
        --print(k, ref[idxNode], ref[idxRef], ref[idxForward])
        if ref[idxForward] ~= 1 then
          break -- continue
        end

        local refId = ref[idxRef]
        local nextId = ref[idxNode]
        -- check if target node mandatory during instantiating
        if dbgOn then traceD(fmt("Services:addNode | searching node '%s'", ref[idxNode])) end
        local instanceNode = self.nodeset:getNode(ref[idxNode])
        if refId ~= HasTypeDefinition then
          local isMandatory = false
          assert(instanceNode, ref[idxNode])
          for _,iref in ipairs(instanceNode.refs) do
            if iref[idxRef] == HasModellingRule then
              isMandatory = iref[idxNode] == ModellingRule_Mandatory
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
          [idxForward] = ref[idxForward],
          [idxNode] = nextId,
          [idxRef] = refId
        }

        tins(curParent.refs, newRef)
      until true
    end
    tins(newNodes, curParent)
  end

  -- add collected nodes hierarchy to
  tins(parent.refs, {nodeId, node.referenceTypeId, 1})
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

  self:checkSession(req, channel)
  channel = channel or {}

  if req.nodesToAdd == nil or req.nodesToAdd[1] == nil then
    if infOn then traceD(fmt("Services:addNodes(ch:%s) | Nothing to do", channel.channelId)) end
    error(BadNothingToDo)
  end

  local results = {}

  for _, node in ipairs(req.nodesToAdd) do
    local suc, result = pcall(self.addNode, self, node)
    if suc == true then
      if infOn then traceD(fmt("Services:addNodes(ch:%s) | Added node id '%s'", channel.channelId, result)) end
      tins(results, {statusCode=Good, addedNodeId=result})
    else
      if errOn then traceD(fmt("Services:addNodes(ch:%s) | Error addin error %s", channel.channelId, result)) end
      tins(results, {statusCode=result, addedNodeId="i=0"})
    end
  end

  return {results=results}
end

function Svc:createSubscription(req, channel)
  self:checkSession(req, channel)

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

function Svc:checkSession(req, channel)
  local dbgOn = self.trace.dbgOn
  local errOn = self.trace.errOn

  if not channel then
    return
  end

  if dbgOn then traceD(fmt("Svc:checkSession(ch:%s) | Request handle '%s'", channel.channelId, req.requestHeader.requestHandle)) end

  local session = self.sessions[channel.channelId]
  if not session then
    if errOn then traceE(fmt("Svc:checkSession(ch:%s) | No session. ", channel.channelId)) end
    error(BadSessionClosed)
  end

  if session.authenticationToken ~= req.requestHeader.authenticationToken then
    if errOn then traceE(fmt("Svc:checkSession(ch:%s) | Session '%s' auth token. ", channel.channelId, session.sessionId)) end
    error(BadRequestHeaderInvalid)
  end

  if not session.activated then
    if errOn then traceE(fmt("Svc:checkSession(ch:%s) | Session '%s' inactive. ", channel.channelId, session.sessionId)) end
    error(BadSessionNotActivated)
  end

  local time = os.time()
  if time > session.sessionExpirationTime then
    self.sessions[channel.channelId] = nil
    if errOn then traceE(fmt("Svc:checkSession(ch:%s) | Session '%s' expired. ", channel.channelId, session.sessionId)) end
    error(BadSessionClosed)
  end

  session.sessionExpirationTime = time + session.sessionTimeoutSecs
  if dbgOn then traceD(fmt("Svc:checkSession(ch:%s) | Session '%s; new expiration time '%s'", channel.channelId, session.sessionId, session.sessionExpirationTime)) end
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

  local timer = ba.timer(function()
    self:cleanupSessions()
    if self.sessionTimer then
      self.sessionTimer:set(10000)
    end
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
