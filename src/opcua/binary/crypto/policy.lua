local SecurityPolicy = require("opcua.types").SecurityPolicy
local fmt = string.format

local BadSecurityPolicyRejected = 0x80550000

local function init(config)
  local securePolicies = config.securePolicies
  assert(type(securePolicies) == 'table' and type(securePolicies[1]) == 'table', "invalid security configuration")
  local security = {}

  for _,p in ipairs(securePolicies) do
    local policyModule
    if p.securityPolicyUri == SecurityPolicy.None then
      policyModule = "opcua.binary.crypto.none"
    elseif p.securityPolicyUri == SecurityPolicy.Basic128Rsa15 then
      policyModule = "opcua.binary.crypto.basic128rsa15"
    else
      error(fmt("Unsupported policy URI %s", p.securityPolicyUri))
    end

    local certificate = p.certificate
    local key = p.key
    if not p.certificate then
      certificate = config.certificate
      key = config.key
    end

    -- assert(certificate, "secure policy has no cerificate")
    -- assert(key, "secure policy has no key")

    security[p.securityPolicyUri] = {
      policyModule = policyModule,
      securityPolicyUri = p.securityPolicyUri,
      secureMode = p.securityMode,
      certificate = certificate,
      key = key,
    }
  end

  return function(policyUri)
    local policyData = security[policyUri]
    if not policyData then
      error(BadSecurityPolicyRejected)
    end
    local policy = require(policyData.policyModule)(policyData.secureMode, config.io)
    policy:setLocalCertificate(policyData.certificate, policyData.key)
    return policy
  end
end

return init
