local ua = require("opcua.api")
local crt = require("opcua.binary.crypto.certificate")

local function countPolicies(securePolicies, uri)
  local count = 0
  for _,policy in ipairs(securePolicies) do
    if uri == policy.securityPolicyUri then
      count = count + 1
    end
  end
  return count
end

local function checkSecurePolicies(config)
  local securePolicies = config.securePolicies
  if type(securePolicies) ~= 'table' or #securePolicies == 0 then
    error("invalid securePolicies")
  end

  local p = ua.Types.SecurityPolicy
  local modes = ua.Types.MessageSecurityMode
  for _,policy in ipairs(securePolicies) do
    local uri = policy.securityPolicyUri
    if countPolicies(securePolicies, uri) ~= 1 then
      error("security '"..tostring(policy.securityPolicyUri).."' specified multiple times")
    end
    local mode = policy.securityMode
    if uri == p.None then
      if mode == nil then
        policy.securityMode = {modes.None}
      elseif mode ~= modes.None and type(mode) ~= 'table' and #mode ~= 1 and mode[1] ~= modes.None then
        error("security mode must be None for securityPolicyUri "..tostring(policy.securityPolicyUri))
      end
    elseif uri == p.Basic128Rsa15 then
      local m
      if type(mode) == 'number' then
        m = {mode}
      elseif type(mode) ~= 'table' then
        error("security mode is not a number or array of numbers "..tostring(policy.securityPolicyUri))
      else
        m = mode
      end

      if #m > 2 then
        error("security mode can be Sign or SignAndAncrypt for policy "..tostring(policy.securityPolicyUri))
      end

      for k,v in pairs(m) do
        if type(k) ~= 'number' then
          error("security mode is not a number or array of numbers "..tostring(policy.securityPolicyUri))
        end
        if v ~= modes.SignAndEncrypt and v ~= modes.Sign then
          error("unsupported mode for securityPolicyUri "..tostring(policy.securityPolicyUri))
        end
      end
      policy.securityMode = m

      if not policy.certificate and not config.certificate then
        error("securityPolicyUri '"..policy.securityPolicyUri.."' has no certificate")
      end

      if not policy.key and not config.key then
        error("securityPolicyUri '"..policy.securityPolicyUri.."' has no private key")
      end

      -- Try to load certificate and key
      if policy.certificate then
        crt.createCert(policy.certificate, config.io)
      end
      if policy.key then
        crt.createKey(policy.key, config.io)
      end
    else
      error("unsupported securityPolicyUri "..tostring(policy.securityPolicyUri))
    end
  end
end

local function commonConfig(config)
  if config.cosocketMode == nil then
    config.cosocketMode = ba.socket.getsock() ~= nil
  elseif type(config.cosocketMode) ~= "boolean" then
      error("invalid cosocketMode")
  end

  if config.bufSize == nil then
    config.bufSize = 65536
  elseif type(config.bufSize) ~= "number" then
    error("invalid bufSize")
  end

  if config.applicationName == nil then
    config.applicationName = 'RealTimeLogic OPCUA'
  elseif type(config.applicationName) ~= "string" then
    error("invalid applicationName")
  end

  if config.applicationUri == nil then
    config.applicationUri = "urn:realtimelogic:opcua-lua"
  elseif type(config.applicationUri) ~= "string" then
    error("invalid applicationUri")
  end

  if config.productUri == nil then
    config.productUri = "urn:realtimelogic:opcua-lua"
  elseif type(config.productUri) ~= "string" then
    error("invalid productUri")
  end

  local err = checkSecurePolicies(config)
  if err then return err end

  if config.logging == nil then
    config.logging = {}
  elseif type(config.logging) ~= 'table' then
    error("invalid logging")
  end

  if config.logging.socket == nil then
    config.logging.socket = {}
  elseif type(config.logging.socket) ~= 'table' then
    error("invalid logging.socket")
  end

  if config.logging.binary == nil then
    config.logging.binary = {}
  elseif type(config.logging.binary) ~= 'table' then
    error("invalid logging.binary")
  end

  if config.logging.services == nil then
    config.logging.services = {}
  elseif type(config.logging.services) ~= 'table' then
    error("invalid logging.services")
  end

  if config.logging.socket.dbgOn == nil then
    config.logging.socket.dbgOn = false
  elseif type(config.logging.socket.dbgOn) ~= "boolean" then
    error("invalid logging.socket.dbgOn")
  end
  if config.logging.socket.infOn == nil then
    config.logging.socket.infOn = false
  elseif type(config.logging.socket.infOn) ~= "boolean" then
    error("invalid logging.socket.infOn")
  end
  if
   config.logging.socket.errOn == nil then
    config.logging.socket.errOn = false
  elseif type(config.logging.socket.errOn) ~= "boolean" then
    error("invalid logging.socket.errOn")
  end

  if config.logging.binary.dbgOn == nil then
    config.logging.binary.dbgOn = false
  elseif type(config.logging.binary.dbgOn) ~= "boolean" then
    error("invalid logging.binary.dbgOn")
  end
  if config.logging.binary.infOn == nil then
    config.logging.binary.infOn = false
  elseif type(config.logging.binary.infOn) ~= "boolean" then
    error("invalid logging.binary.infOn")
  end
  if
   config.logging.binary.errOn == nil then
    config.logging.binary.errOn = false
  elseif type(config.logging.binary.errOn) ~= "boolean" then
    error("invalid logging.binary.errOn")
  end


  if config.logging.services.dbgOn == nil then
    config.logging.services.dbgOn = false
  elseif type(config.logging.services.dbgOn) ~= "boolean" then
    error("invalid logging.services.dbgOn")
  end
  if config.logging.services.infOn == nil then
    config.logging.services.infOn = false
  elseif type(config.logging.services.infOn) ~= "boolean" then
    error("invalid logging.services.infOn")
  end
  if
   config.logging.services.errOn == nil then
    config.logging.services.errOn = false
  elseif type(config.logging.services.errOn) ~= "boolean" then
    error("invalid logging.services.errOn")
  end
end

local function identityTokens(config)
  if config.userIdentityTokens == nil then
    config.userIdentityTokens = {
      {
        policyId = "anonymous",
        tokenType = ua.Types.UserTokenType.Anonymous
      }
    }
    return
  end

  if #config.userIdentityTokens == 0 then
    error("Empty 'userIdentityTokens' section")
  end

  for idx,policy in ipairs(config.userIdentityTokens) do
    for field,value in pairs(policy) do
      if field ~= "policyId" and
        field ~= "tokenType" and
        field ~= "issuerEndpointUrl" and
        field ~= "securityPolicyUri" and
        field ~= "issuedTokenType"
      then
        return error(string.format("Policy #%i: Unknown field '%s'", idx, field))
      end
    end

    if policy.policyId == nil then
      return error(string.format("Policy #%i: No policyId specified", idx))
    end

    if type(policy.policyId) ~= 'string' then
      return error(string.format("Policy #%i: policyId must be string", idx))
    end

    if policy.tokenType == ua.Types.UserTokenType.Anonymous then
      if policy.issuedTokenType then
        error("Anonymous policy cannot have issuedTokenType")
      elseif policy.issuerEndpointUrl then
        error("Anonymous policy cannot have issuerEndpointUrl")
      elseif policy.securityPolicyUri then
        error("Anonymous policy cannot have securityPolicyUri")
      end
    elseif policy.tokenType == ua.Types.UserTokenType.Certificate then
      if policy.issuedTokenType then
        error("Certificate policy cannot have issuedTokenType")
      elseif policy.issuerEndpointUrl then
        error("Certificate policy cannot have issuerEndpointUrl")
      end
    elseif policy.tokenType == ua.Types.UserTokenType.UserName then
      if policy.issuedTokenType then
        error("UserName policy cannot have issuedTokenType")
      elseif policy.issuerEndpointUrl then
        error("UserName policy cannot have issuerEndpointUrl")
      end
    elseif policy.tokenType == ua.Types.UserTokenType.IssuedToken then
      if policy.issuedTokenType ~= ua.Types.IssuedTokenType.Azure  and
         policy.issuedTokenType ~= ua.Types.IssuedTokenType.JWT    and
         policy.issuedTokenType ~= ua.Types.IssuedTokenType.OAuth2 and
         policy.issuedTokenType ~= ua.Types.IssuedTokenType.OPCUA
      then
        error(string.format("Token policy '%s' has invalid issuedTokenType", policy.policyId))
      end
    else
      error(string.format("Policy '%s' has unknown token type", policy.policyId))
    end

    if policy.securityPolicyUri and policy.securityPolicyUri ~= ua.Types.SecurityPolicy.None then
      local found = false
      for _,security in ipairs(config.securePolicies) do
        if security.securityPolicyUri == policy.securityPolicyUri then
          found = true
          break
        end
      end
      if found == false then
        error(string.format("Security policy '%s' for token '%s' should be configued in 'securePolicies'.", policy.securityPolicyUri, policy.policyId))
      end
    end

  end
end

local function serverConfig(config)
  if type(config.endpointUrl) ~= "string" then
    error("invalid endpointUrl")
  end

  local url,err = ua.parseUrl(config.endpointUrl)
  if err then
    error("Invalid endpointURL. "..err)
  end

  if config.listenPort == nil then
    config.listenPort = url.port
  elseif type(config.listenPort) ~= "number" then
    error("invalid listenPort")
  end

  if config.listenAddress == nil then
    config.listenAddress = url.host
  elseif type(config.listenAddress) ~= "string" then
    error("invalid listenAddress")
  end

  if config.authenticate and type(config.authenticate) ~= "function" then
    error("authorize not a function")
  end

  if config.certificate then
    crt.createCert(config.certificate, config.io)
    if not config.key then
      error("No private key")
    end
    crt.createKey(config.key, config.io)
  end

  if config.key then
    if not config.certificate then
      error("No certificate")
    end
    crt.createCert(config.certificate, config.io)
    crt.createKey(config.key, config.io)
  end

  commonConfig(config)

  -- Identity tokens goes last bcause can check security policies section
  identityTokens(config)
end

local function clientConfig(config)
  commonConfig(config)
  if config.userIdentityTokens then
    error("Client config cannot contain userIdentityTokens section")
  end
end

return {
  client = clientConfig,
  server = serverConfig,
}
