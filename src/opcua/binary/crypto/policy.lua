local ua = require("opcua.api")
local SecurityPolicy = require("opcua.types").SecurityPolicy
local nonePolicy = require("opcua.binary.crypto.policy_none")
local rsaPolicy = require("opcua.binary.crypto.policy_rsa")
local fmt = string.format

local BadSecurityPolicyRejected = 0x80550000

local function init(config)
  local securePolicies = config.securePolicies
  assert(type(securePolicies) == 'table' and type(securePolicies[1]) == 'table', "invalid security configuration")
  local security = {}

  local engine = ua.crypto_engine
  for _,p in ipairs(securePolicies) do
    local policyParams
    local policy
    if engine =="sharkssl" then
      if p.securityPolicyUri == SecurityPolicy.None then
        policy = nonePolicy
      elseif p.securityPolicyUri == SecurityPolicy.Basic128Rsa15 then
        policyParams = require("opcua.binary.crypto.basic128rsa15")
        policy = rsaPolicy
      elseif p.securityPolicyUri == SecurityPolicy.Basic256Sha256 then
        policyParams = require("opcua.binary.crypto.basic256_sha256")
        policy = rsaPolicy
      elseif p.securityPolicyUri == SecurityPolicy.Aes128_Sha256_RsaOaep then
        policyParams = require("opcua.binary.crypto.aes128_sha256_rsa_oaep")
        policy = rsaPolicy
      end
    elseif engine =="openssl" then
      if p.securityPolicyUri == SecurityPolicy.None then
        policy = nonePolicy
      elseif p.securityPolicyUri == SecurityPolicy.Basic128Rsa15 then
        policyParams = require("opcua.binary.crypto.basic128rsa15")
        policy = rsaPolicy
      elseif p.securityPolicyUri == SecurityPolicy.Aes256_Sha256_RsaPss then
        policyParams = require("opcua.binary.crypto.aes256_sha256_rsa_pss")
        policy = rsaPolicy
      elseif p.securityPolicyUri == SecurityPolicy.Aes128_Sha256_RsaOaep then
        policyParams = require("opcua.binary.crypto.aes128_sha256_rsa_oaep")
        policy = rsaPolicy
      elseif p.securityPolicyUri == SecurityPolicy.Basic256Sha256 then
        policyParams = require("opcua.binary.crypto.basic256_sha256")
        policy = rsaPolicy
      end
    end

    if not policy then
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
      policyModule = function(modes, iio) return policy(modes, policyParams, iio) end,
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
    local policy = policyData.policyModule(policyData.secureMode, config.io)
    policy:setLocalCertificate(policyData.certificate, policyData.key)
    return policy
  end
end

return init
