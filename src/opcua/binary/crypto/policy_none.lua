local const = require("opcua.const") -- REMOVE, Not used in encryption
local crypto = require("opcua.crypto")

local BadSecurityChecksFailed = 0x80130000
local BadSecurityPolicyRejected = 0x80550000

local function empty()
end

local function size(_, sz)
  return sz
end

local function createPolicy(_--[[modes]], _--[[params]], fsIo)
  return {
    uri = const.SecurityPolicy.None,

    setLocalCertificate = function(self, certificate, key)
      if not certificate or not key then
        return
      end

      assert(certificate)
      assert(key)
      key = crypto.crypto.createKey(key, fsIo)
      assert(key)

      local sz,t = crypto.crypto.keysize(key)
      -- TODO: check error is thrown
      -- if err then error(err) end
      if t ~= "RSA" or sz < 128 or sz > 256 then
        error(BadSecurityChecksFailed)
      end
      self.certificate = crypto.crypto.createCert(certificate, fsIo)
      assert(self.certificate)
      self.key = key
    end,

    setRemoteCertificate = function(self, remoteCert)
      if not remoteCert then
        return
      end

      assert(remoteCert, "Remote certificate empty")
      self.remote = crypto.crypto.createCert(remoteCert, fsIo)
    end,

    geLocalCertLen = function(self)
      return self.certificate and #self.certificate.der or 0
    end,

    getRemoteThumbLen = function(self)
      return self.remote and #self.remote.thumbprint or 0
    end,
    genNonce = function(_, len)
      return crypto.crypto.rndbs(len or 16)
    end,
    getLocalThumbprint = function(self)
      return self.certificate and self.certificate.thumbprint
    end,
    getRemoteThumbprint = function(self)
      return self.remote and self.remote.thumbprint
    end,
    getLocalCert = function(self)
      return self.certificate and self.certificate.der
    end,
    getRemoteCert = function(self)
      return self.remote and self.remote.der
    end,
    tailSize = function()
      return 0
    end,
    setSecureMode = function(self, secureMode)
      if secureMode ~= 1 then
        error(BadSecurityPolicyRejected)
      end
      self.secureMode = secureMode
    end,

    setNonces = empty,
    asymmetricEncrypt = empty,
    asymmetricDecrypt = empty,
    symmetricEncrypt = empty,
    symmetricDecrypt = empty,
    aMessageSize = size,
    sMessageSize = size,
  }
end

return createPolicy
