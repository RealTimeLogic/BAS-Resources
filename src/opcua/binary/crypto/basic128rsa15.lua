-- DerivedSignatureKeyLength: 128 bits
-- MinAsymmetricKeyLength: 1024 bits
-- MaxAsymmetricKeyLength: 2048 bits
-- SecureChannelNonceLength: 16 bytes

local ua = require("opcua.api") -- REMOVE, Not used in encryption
local createCert = require("opcua.binary.crypto.certificate").createCert
local createKey = require("opcua.binary.crypto.certificate").createKey

local BlockSize = 256
local SignSize = 256

local BadSecurityChecksFailed = 0x80130000
local BadSecurityPolicyRejected = 0x80550000
local BadEncodingError = 0x80060000
local BadDecodingError = 0x80070000

local function sha1Sum(...)
  local sha1 = ba.crypto.hash("sha1")
  local params = {...}
  for _,data in ipairs(params) do
    if type(data) == 'string' then
      sha1(data)
    else
      local dlen = #data
      for i = 1,dlen,BlockSize do
        local delta = dlen - (i - 1)
        if delta > BlockSize then
          delta = BlockSize
        end
        sha1(ba.bytearray.tostring(data, i, i + delta - 1))
      end
    end
  end
  local sum = sha1(true)
  return sum
end

local function rsaPkcs15Sha1(key, ...)
  local sum1 = sha1Sum(...)
  local sum = "\x30\x21\x30\x09\x06\x05\x2B\x0E\x03\x02\x1A\x05\x00\x04\x14" .. sum1
  local m,err = ba.crypto.sign(sum, key)
  if err then
    error(BadEncodingError)
  end
  return m
end

local function aDecrypt(data, cert, key)
  local _,si,ei = ba.bytearray.size(data)
  ba.bytearray.setsize(data,1,ei)

  local len = 0
  for i = si,ei,BlockSize do
    local e = ba.bytearray.tostring(data, i, i + BlockSize - 1)
    local m,err = ba.crypto.decrypt(e, key, {nopadding=false})
    if err then
      -- if dbgOn then traceD("binary | decrypt error: "..err) end
      error(BadDecodingError)
    end
    data[si+len] = m
    len = len + #m
  end

  ba.bytearray.setsize(data, 1, si + len - BlockSize - 1)
  local sum1 = sha1Sum(data)
  ba.bytearray.setsize(data, si, si + len - 1)
  local paddingSize = data[#data - BlockSize]

  local cipherSig = ba.bytearray.tostring(data, -BlockSize)
  local sum2,err = ba.crypto.verify(cipherSig, cert.pem, {nopadding=false})
  if err then
    -- if dbgOn then traceD("binary | signature decrypt error: "..err) end
    error(BadDecodingError)
  end

  local sum = "\x30\x21\x30\x09\x06\x05\x2B\x0E\x03\x02\x1A\x05\x00\x04\x14"..sum1
  if sum2 ~= sum then
    -- if dbgOn then traceD("binary | signature wrong") end
    error(BadSecurityChecksFailed)
  end

  ba.bytearray.setsize(data, si, si + len - (BlockSize + paddingSize + 1) - 1)
end

local function hmacSha1(data, key)
  local sha1 = ba.crypto.hash("hmac", "sha1", key)
  local dlen = #data
  for i = 1,dlen,16 do
    local delta = dlen - (i - 1)
    if delta > 16 then
      delta = 16
    end
    sha1(ba.bytearray.tostring(data, i, i + delta - 1))
  end
  local sum = sha1(true)
  return sum
end


local function asymmetricMessageSize(sz, headerSize)
  local encSz = sz - headerSize
  local alignedSize = (encSz + BlockSize - 1) & 0xFFFFFF00
  local msgSz = headerSize + alignedSize + SignSize
  return msgSz
end

local function aEncrypt(data, cert, key, pos)
  local dataBlockSize = 245

  local _,si,ei = ba.bytearray.size(data)
  local encSz = ei - pos + BlockSize + 1
  local paddingSize = dataBlockSize - encSz % dataBlockSize
  local paddingSi = ei+1
  local paddingEi = paddingSi + paddingSize
  ba.bytearray.setsize(data, si, paddingEi)
  for i = paddingSi,paddingEi do
    data[i] = paddingSize
  end

  _,si,ei = ba.bytearray.size(data)
  local sum = rsaPkcs15Sha1(key, data)
  ba.bytearray.setsize(data, si, ei + BlockSize)
  data[ei + 1] = sum

  _,_,ei = ba.bytearray.size(data)
  assert((ei - pos) % dataBlockSize == 0)

  local blocks = ((ei - pos) / dataBlockSize) & 0xFFFFFFFF
  local chunkSize = pos + blocks * BlockSize
  -- Encrypt
  local chunk = ba.bytearray.create(chunkSize)
  ba.bytearray.setsize(chunk, 1, chunkSize)
  chunk[1] = data
  local encPos = pos + 1
  local srcPos = encPos
  for _ = 1,blocks do
    local msg = ba.bytearray.tostring(data, srcPos, srcPos + dataBlockSize - 1)
    local enc,err = ba.crypto.encrypt(msg, cert.pem)
    if err then
      error(BadEncodingError)
    end
    chunk[encPos] = enc
    srcPos = srcPos + dataBlockSize
    encPos = encPos + BlockSize
  end

  assert(encPos == chunkSize + 1)

  ba.bytearray.setsize(data, 1, chunkSize)
  data[1] = chunk
end

local function p_sha1(secret, seed, sizes)
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
      accum = ba.crypto.hash("hmac", "sha1", secret)(accum)(true)
      result = result..ba.crypto.hash("hmac", "sha1", secret)(accum .. seed)(true)
  end
  return result
end


local function p_hash(localNonce, remoteNonce)
  local sub = string.sub
  local siningKeyLength = 16
  local encryptingKeyLength = 16
  local encryptingBlockSize = 16
  local sizes = {siningKeyLength, encryptingKeyLength, encryptingBlockSize}
  local encryptHash = p_sha1(remoteNonce, localNonce, sizes)

  local keys = {
    signKey = sub(encryptHash, 1, siningKeyLength),
    encryptKey = sub(encryptHash, siningKeyLength + 1, siningKeyLength + encryptingKeyLength),
    encryptIV = sub(encryptHash, siningKeyLength + encryptingKeyLength + 1,
      siningKeyLength + encryptingKeyLength + encryptingBlockSize),
  }

  return keys
end

local sDebug = 0

local function sDecrypt(keys, cipher, secureMode)
  if sDebug == 1 then
    print("----------------------------------")
    print("encrypted block")
    ua.Tools.hexPrint(cipher)
    print("----------------------------------")
  end

  if secureMode == 3 then
    local decryptor = ba.crypto.symmetric("CBC", keys.encryptKey, keys.encryptIV, "decrypt")
    local msg = decryptor:decrypt(tostring(cipher))

    if sDebug == 1 then
      print("----------------------------------")
      print("decrypted block")
      ua.Tools.hexPrint(msg)
      print("----------------------------------")
    end

    cipher[1] = msg
  end

  local _,headerSize,finish = ba.bytearray.size(cipher)
  ba.bytearray.setsize(cipher, 1, finish)

  local sum1 = ba.bytearray.tostring(cipher, -20)
  if sDebug == 1 then
    print("----------------------------------")
    print("expected sign")
    ua.Tools.hexPrint(sum1)
    print("----------------------------------")
  end

  ba.bytearray.setsize(cipher, 1, finish - 20)
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

  local sum2 = hmacSha1(cipher, keys.signKey)

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
    local paddingSize = cipher[finish - 20]
    ba.bytearray.setsize(cipher, headerSize, finish - 20 - (paddingSize + 1))
  else
    ba.bytearray.setsize(cipher, headerSize, finish - 20)
  end

  if sDebug == 1 then
    print("----------------------------------")
    print("decrypted Data")
    ua.Tools.hexPrint(cipher)
    print("----------------------------------")
  end
end

local function symmetricMessageSize(sz, headerSize, secureMode)
  local signSize = 20
  if secureMode == 2 then
    return sz + signSize
  end

  local blockSize = 16
  local paddingSize = 0
  local encSz = sz - headerSize + signSize + 1
  if encSz % blockSize ~= 0 then
    paddingSize = blockSize - encSz % blockSize
  end

  local msgSz = headerSize + encSz + paddingSize
  return msgSz
end

local k = 0

local function sEncrypt(keys, data, headerSize, secureMode)
  if secureMode ~= 2 and secureMode ~= 3 then
    error(BadSecurityPolicyRejected)
  end

  if k == 1 then
    print("----------------------------------")
    print("encrypting Data")
    ua.Tools.hexPrint(data)
    print("----------------------------------")
  end

  local dataBlockSize = 16
  local signSize = 20

  local _,si,ei = ba.bytearray.size(data)
  if secureMode == 3 then
    local encSz = ei - headerSize + signSize + 1 + (dataBlockSize -1)
    encSz = encSz - (encSz & (dataBlockSize -1))
    local paddingSize = encSz - (signSize + 1) - (ei - headerSize)

    local paddingSi = ei+1
    local paddingEi = ei + paddingSize + 1
    ba.bytearray.setsize(data, si, paddingEi)
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
    print("check key")
    ua.Tools.hexPrint(keys.signKey)
    print("----------------------------------")
  end

  _,si,ei = ba.bytearray.size(data)
  local sum = hmacSha1(data, keys.signKey)

  if k == 1 then
    print("----------------------------------")
    print("sign hmacSha1")
    ua.Tools.hexPrint(sum)
    print("----------------------------------")
  end

  ba.bytearray.setsize(data, si, ei + signSize)
  data[ei + 1] = sum

  if k == 1 then
    print("------------------------")
    print("data block:")
    ua.Tools.hexPrint(data)
    print("------------------------")
  end

  _,_,ei = ba.bytearray.size(data)

  if secureMode == 3 then
    assert((ei - headerSize) % dataBlockSize == 0)
    local encryptor = ba.crypto.symmetric("CBC", keys.encryptKey, keys.encryptIV, "encrypt")
    -- local msg = ba.bytearray.tostring(data, headerSize + 1)
    -- local cipher = encryptor:encrypt(msg)
    -- data[headerSize + 1] = cipher

    for i=headerSize,ei-1,dataBlockSize do
      local msg = ba.bytearray.tostring(data, i + 1, i + dataBlockSize)
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

local function createPolicy(modes, io)
  assert(type(modes) == 'table', "node secure modes")

  return {
    modes = modes,
    uri = ua.Types.SecurityPolicy.Basic128Rsa15,
    aSignatureUri = "http://www.w3.org/2000/09/xmldsig#rsa-sha1",
    aEncryptionAlgorithm = "http://www.w3.org/2001/04/xmlenc#rsa-1_5",

    setLocalCertificate = function(self, certificate, key)
      assert(certificate)
      assert(key)
      key = createKey(key, io)
      assert(key)

      local size,err = ba.crypto.keysize(key)
      if err then error(err) end
      if size < 128 or size > 256 then
        error(BadSecurityChecksFailed)
      end
      self.certificate = createCert(certificate, io)
      assert(self.certificate)
      self.key = key
    end,

    setRemoteCertificate = function(self, remoteCert)
      assert(remoteCert, "Remote certificate empty")
      self.remote = createCert(remoteCert, io)
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

    setNonces = function(self, localNonce, remoteNonce, secureMode)
      assert(#localNonce == 16)
      if #remoteNonce ~= 16 then
        error(BadSecurityChecksFailed)
      end
      self.keys = p_hash(localNonce, remoteNonce)
      self.secureMode = secureMode
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
      return aEncrypt(data, self.remote, self.key, pos)
    end,

    asymmetricDecrypt = function(self, data)
      return aDecrypt(data, self.remote, self.key)
    end,

    asymmetricSign = function(self, ...)
      return rsaPkcs15Sha1(self.key, ...)
    end,

    asymmetricVerify = function(self, sig, ...)
      local sum1 = "\x30\x21\x30\x09\x06\x05\x2B\x0E\x03\x02\x1A\x05\x00\x04\x14"..sha1Sum(...)
      local sum2,err = ba.crypto.verify(sig, self.remote.pem, {nopadding=false})
      return sum1 == sum2
    end,


    symmetricEncrypt = function(self, data, pos)
      return sEncrypt(self.keys, data, pos, self.secureMode)
    end,

    symmetricDecrypt = function(self, data)
      return sDecrypt(self.keys, data, self.secureMode)
    end,

    aMessageSize = function(_, size, headerSize)
      return asymmetricMessageSize(size, headerSize)
    end,

    sMessageSize = function(self, size, headerSize)
      return symmetricMessageSize(size, headerSize, self.secureMode)
    end,

    genNonce = function(_, len)
      return ba.rndbs(len or 16)
    end,

    tailSize = function()
      return 21 -- sha1(20Bytes) + paddingSize(1byte)
    end
  }

end

return createPolicy
