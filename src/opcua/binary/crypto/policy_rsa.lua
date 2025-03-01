-- DerivedSignatureKeyLength: 256 bits
-- MinAsymmetricKeyLength: 2048 bits
-- MaxAsymmetricKeyLength: 4096 bits
-- SecureChannelNonceLength: 32 bytes

local compat = require("opcua.compat")
local ua = require("opcua.api") -- REMOVE, Not used in encryption
local createCert = ua.crypto.createCert
local createKey = ua.crypto.createKey
local bytearray = compat.bytearray

local BadSecurityChecksFailed = 0x80130000
local BadSecurityPolicyRejected = 0x80550000
local BadEncodingError = 0x80060000
local BadDecodingError = 0x80070000

local function aDecrypt(data, cert, key, params)
  local _,si,ei = bytearray.size(data)
  bytearray.setsize(data,1,ei)

  local keySize = ua.crypto.keysize(key)
  local blockSize = keySize

  local len = 0
  for i = si,ei,blockSize do
    local e = bytearray.tostring(data, i, i + blockSize - 1)
    local m,err = ua.crypto.decrypt(e, key, params.rsaParams)
    if err then
      -- if dbgOn then traceD("binary | decrypt error: "..err) end
      error(BadDecodingError)
    end
    data[si+len] = m
    len = len + #m
  end

  bytearray.setsize(data, si, si + len - 1)
  local paddingSize = data[#data - blockSize]

  local cipherSig = bytearray.tostring(data, -blockSize)
  bytearray.setsize(data, 1, si + len - blockSize - 1)
  local resultVerify = params.asymmetricVerify(cert, cipherSig, data)
  if not resultVerify then
    -- if dbgOn then traceD("binary | signature wrong") end
    error(BadSecurityChecksFailed)
  end

  bytearray.setsize(data, si, si + len - (blockSize + paddingSize + 1) - 1)
end

local function asymmetricMessageSize(sz, headerSize, key)
  local keySize = ua.crypto.keysize(key)
  local encSz = sz - headerSize
  local alignedSize = (encSz + keySize - 1) & 0xFFFFFF00
  local msgSz = headerSize + alignedSize + keySize
  return msgSz
end

local function aEncrypt(data, cert, key, pos, params)
  local keySize = ua.crypto.keysize(key)
  local blockSize = keySize
  local dataBlockSize = blockSize - params.aPaddingSize

  local _,si,ei = bytearray.size(data)
  local encSz = ei - pos + blockSize + 1
  local paddingSize = dataBlockSize - encSz % dataBlockSize
  local paddingSi = ei+1
  local paddingEi = paddingSi + paddingSize
  bytearray.setsize(data, si, paddingEi)
  for i = paddingSi,paddingEi do
    data[i] = paddingSize
  end

  _,si,ei = bytearray.size(data)
  local sum = params.asymmetricSign(key, data)
  bytearray.setsize(data, si, ei + blockSize)
  data[ei + 1] = sum

  _,_,ei = bytearray.size(data)
  assert((ei - pos) % dataBlockSize == 0)

  local blocks = ((ei - pos) / dataBlockSize) & 0xFFFFFFFF
  local chunkSize = pos + blocks * blockSize
  -- Encrypt
  local chunk = bytearray.create(chunkSize)
  bytearray.setsize(chunk, 1, chunkSize)
  chunk[1] = data
  local encPos = pos + 1
  local srcPos = encPos
  for _ = 1,blocks do
    local msg = bytearray.tostring(data, srcPos, srcPos + dataBlockSize - 1)
    local enc,err = ua.crypto.encrypt(msg, cert, params.rsaParams)
    if err then
      error(BadEncodingError)
    end
    chunk[encPos] = enc
    srcPos = srcPos + dataBlockSize
    encPos = encPos + blockSize
  end

  assert(encPos == chunkSize + 1)

  bytearray.setsize(data, 1, chunkSize)
  data[1] = chunk
end

local function p_key(secret, seed, sizes, hmac)
  -- Derive one or more keys from secret and seed.
  -- (See specs part 6, 6.7.5 and RFC 2246 - TLS v1.0)
  -- Lengths of keys will match sizes argument
  local full_size = 0
  for _,size in ipairs(sizes) do
      full_size = full_size + size
  end

  local result = ""
  local accum = seed
  while #result < full_size do
      accum = hmac(secret, accum)
      result = result..hmac(secret, accum .. seed)
  end
  return result
end


local function p_hash(localNonce, remoteNonce, params)
  local sub = string.sub
  local hmac = params.hmacSum
  local siningKeyLength = params.siningKeyLength
  local encryptingKeyLength = params.encryptingKeyLength
  local encryptingBlockSize = params.encryptingBlockSize

  local sizes = {siningKeyLength, encryptingKeyLength, encryptingBlockSize}
  local encryptHash = p_key(remoteNonce, localNonce, sizes, hmac)

  local keys = {
    signKey = sub(encryptHash, 1, siningKeyLength),
    encryptKey = sub(encryptHash, siningKeyLength + 1, siningKeyLength + encryptingKeyLength),
    encryptIV = sub(encryptHash, siningKeyLength + encryptingKeyLength + 1,
      siningKeyLength + encryptingKeyLength + encryptingBlockSize),
  }

  return keys
end

local sDebug = 0

local function sDecrypt(keys, cipher, secureMode, params)
  if sDebug == 1 then
    print("----------------------------------")
    print("encrypted block")
    ua.Tools.hexPrint(cipher)
    print("----------------------------------")
  end

  if secureMode == 3 then
    local decryptor = ua.crypto.symmetric("CBC", keys.encryptKey, keys.encryptIV, "decrypt")
    local msg = decryptor:decrypt(tostring(cipher))

    if sDebug == 1 then
      print("----------------------------------")
      print("decrypted block")
      ua.Tools.hexPrint(msg)
      print("----------------------------------")
    end

    cipher[1] = msg
  end

  local _,headerSize,finish = bytearray.size(cipher)
  bytearray.setsize(cipher, 1, finish)

  local sum1 = bytearray.tostring(cipher, -params.hmacSize)
  if sDebug == 1 then
    print("----------------------------------")
    print("expected sign")
    ua.Tools.hexPrint(sum1)
    print("----------------------------------")
  end

  bytearray.setsize(cipher, 1, finish - params.hmacSize)
  if sDebug == 1 then
    print("----------------------------------")
    print("data to check sign")
    ua.Tools.hexPrint(cipher)
    print("----------------------------------")
  end

  if sDebug == 1 then
    print("----------------------------------")
    print("sign key")
    ua.Tools.hexPrint(keys.signKey)
    print("----------------------------------")
  end

  local sum2 = params.hmacSum(keys.signKey, cipher)

  if sDebug == 1 then
    print("----------------------------------")
    print("calculated sign")
    ua.Tools.hexPrint(sum2)
    print("----------------------------------")
  end

  if sum1 ~= sum2 then
    error(BadSecurityChecksFailed)
  end

  if secureMode == 3 then
    local paddingSize = cipher[finish - params.hmacSize]
    bytearray.setsize(cipher, headerSize, finish - params.hmacSize - (paddingSize + 1))
  else
    bytearray.setsize(cipher, headerSize, finish - params.hmacSize)
  end

  if sDebug == 1 then
    print("----------------------------------")
    print("decrypted Data")
    ua.Tools.hexPrint(cipher)
    print("----------------------------------")
  end
end

local function symmetricMessageSize(sz, headerSize, secureMode, params)
  local signSize = params.hmacSize
  if secureMode == 2 then
    return sz + signSize
  end

  local blockSize = params.symmetricBlockSize
  local paddingSize = 0
  local encSz = sz - headerSize + signSize + 1
  if encSz % blockSize ~= 0 then
    paddingSize = blockSize - encSz % blockSize
  end

  local msgSz = headerSize + encSz + paddingSize
  return msgSz
end

local k = 0

local function sEncrypt(keys, data, headerSize, secureMode, params)
  if secureMode ~= 2 and secureMode ~= 3 then
    error(BadSecurityPolicyRejected)
  end

  if k == 1 then
    print("----------------------------------")
    print("encrypting Data")
    ua.Tools.hexPrint(data)
    print("----------------------------------")
  end

  local dataBlockSize = params.symmetricBlockSize
  local signSize = params.hmacSize

  local _,si,ei = bytearray.size(data)
  if secureMode == 3 then
    local encSz = ei - headerSize + signSize + 1 + (dataBlockSize -1)
    encSz = encSz - (encSz & (dataBlockSize -1))
    local paddingSize = encSz - (signSize + 1) - (ei - headerSize)

    local paddingSi = ei+1
    local paddingEi = ei + paddingSize + 1
    bytearray.setsize(data, si, paddingEi)
    for i = paddingSi,paddingEi do
      data[i] = paddingSize
    end
  end

  if k == 1 then
    print("----------------------------------")
    print("data to sign")
    ua.Tools.hexPrint(data)
    print("----------------------------------")
  end


  if k == 1 then
    print("----------------------------------")
    print("sign key")
    ua.Tools.hexPrint(keys.signKey)
    print("----------------------------------")
  end

  _,si,ei = bytearray.size(data)
  local sum = params.hmacSum(keys.signKey, data)

  if k == 1 then
    print("----------------------------------")
    print("sign hmacSum")
    ua.Tools.hexPrint(sum)
    print("----------------------------------")
  end

  bytearray.setsize(data, si, ei + signSize)
  data[ei + 1] = sum

  if k == 1 then
    print("------------------------")
    print("data block:")
    ua.Tools.hexPrint(data)
    print("------------------------")
  end

  _,_,ei = bytearray.size(data)

  if secureMode == 3 then
    assert((ei - headerSize) % dataBlockSize == 0)
    local encryptor = ua.crypto.symmetric("CBC", keys.encryptKey, keys.encryptIV, "encrypt")
    for i=headerSize,ei-1,dataBlockSize do
      local msg = bytearray.tostring(data, i + 1, i + dataBlockSize)
      local cipher = encryptor:encrypt(msg)
      if k == 1 then
        print("------------------------")
        print("encrypting data:")
        ua.Tools.hexPrint(msg)
        print("cipher data:")
        ua.Tools.hexPrint(cipher)
        print("------------------------")
      end
      data[i+1] = cipher
    end
  end

  if k == 1 then
    print("------------------------")
    print("encrypted block:")
    ua.Tools.hexPrint(data)
    print("------------------------")
  end
end

local function createPolicy(modes, params, fsIo)
  assert(type(modes) == 'table', "node secure modes")

  return {
    modes = modes,
    params = params,
    uri = params.policyUri,
    aSignatureUri = params.aSignatureUri,
    aEncryptionAlgorithm = params.aEncryptionAlgorithm,

    setLocalCertificate = function(self, certificate, key)
      assert(certificate)
      assert(key)
      key = createKey(key, fsIo)
      assert(key)

      local size,t = ua.crypto.keysize(key)
      -- TODO: check error is thrown
      -- if err then error(err) end
      if t ~= "RSA" or size < self.params.minKeySize or size > self.params.maxKeySize then
        error(BadSecurityChecksFailed)
      end
      self.certificate = createCert(certificate, fsIo)
      assert(self.certificate)
      self.key = key
    end,

    setRemoteCertificate = function(self, remoteCert)
      assert(remoteCert, "Remote certificate empty")
      self.remote = createCert(remoteCert, fsIo)
    end,

    geLocalCertLen = function(self)
      return #self.certificate.der
    end,

    getLocalCert = function(self)
      return self.certificate.der
    end,

    getRemoteCert = function(self)
      return self.remote.der
    end,

    getLocalThumbprint = function(self)
      return self.certificate.thumbprint
    end,

    getRemoteThumbprint = function(self)
      return self.remote.thumbprint
    end,

    getRemoteThumbLen = function(self)
      return #self.remote.thumbprint
    end,

    setNonces = function(self, localNonce, remoteNonce)
      assert(#localNonce >= self.params.nonceSize)
      if #remoteNonce < self.params.nonceSize then
        error(BadSecurityChecksFailed)
      end
      self.keys = p_hash(localNonce, remoteNonce, self.params)
    end,

    setSecureMode = function(self, secureMode)
      for _,m in ipairs(self.modes) do
        if m == secureMode then
          self.secureMode = secureMode
          return
        end
      end

      error(BadSecurityPolicyRejected)
    end,

    asymmetricEncrypt = function(self, data, pos)
      return aEncrypt(data, self.remote, self.key, pos, self.params)
    end,

    asymmetricDecrypt = function(self, data)
      return aDecrypt(data, self.remote, self.key, self.params)
    end,

    asymmetricSign = function(self, ...)
      return self.params.asymmetricSign(self.key, ...)
    end,

    asymmetricVerify = function(self,...)
      return self.params.asymmetricVerify(self.remote, ...)
    end,

    symmetricEncrypt = function(self, data, pos)
      return sEncrypt(self.keys, data, pos, self.secureMode, self.params)
    end,

    symmetricDecrypt = function(self, data)
      return sDecrypt(self.keys, data, self.secureMode, self.params)
    end,

    aMessageSize = function(self, size, headerSize)
      return asymmetricMessageSize(size, headerSize, self.key)
    end,

    sMessageSize = function(self, size, headerSize)
      return symmetricMessageSize(size, headerSize, self.secureMode, self.params)
    end,

    genNonce = function(self, len)
      return ua.crypto.rndbs(len or self.params.nonceSize)
    end,

    tailSize = function(self)
      return self.params.hmacSize + 1
    end
  }

end

return createPolicy
