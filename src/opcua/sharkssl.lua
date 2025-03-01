local BlockSize = 256

local function hashSum(hashName, ...)
  local params = {...}
  local sha1 = ba.crypto.hash(hashName)
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


local function sha1Sum(...)
  return hashSum("sha1", ...)
end

local function hmacHash(hashName, key, data)
  local sha1 = ba.crypto.hash("hmac", hashName, key)
  local dlen = #data
  if type(data) ~= 'string' then
    for i = 1,dlen,16 do
      local delta = dlen - (i - 1)
      if delta > 16 then
        delta = 16
      end
      local str = ba.bytearray.tostring(data, i, i + delta - 1)
      sha1(str)
    end
  else
    sha1(data)
  end
  local sum = sha1(true)
  return sum
end

local function hmacSha1(key, data)
  return hmacHash("sha1", key, data)
end

local function hmacSha256(key, data)
  return hmacHash("sha256", key, data)
end


local function rsaPkcs15Sha1Sign(key, ...)
  local sum1 = sha1Sum(...)
  local m,err = ba.crypto.sign(sum1, key, {padding="pkcs1", hashid="sha1"})
  if err then
    error(err)
  end
  return m
end

local function rsaPkcs15Sha1Verify(cert, cipherSig, ...)
  local sum1 = sha1Sum(...)
  local result,err = ba.crypto.verify(cipherSig, cert.pem, sum1, {padding="pkcs1", hashid="sha1"})
  if err then
    return false
  end
  return result
end

local function rsaPkcs15Sha256Sign(key, ...)
  local sum1 = hashSum("sha256", ...)
  local m,err = ba.crypto.sign(sum1, key, {padding="pkcs1", hashid="sha256"})
  if err then
    error(err)
  end
  return m
end

local function rsaPkcs15Sha256Verify(cert, cipherSig, ...)
  local sum1 = hashSum("sha256", ...)
  local result,err = ba.crypto.verify(cipherSig, cert.pem, sum1, {padding="pkcs1", hashid="sha256"})
  if err then
    return false
  end

  return result
end

ba.rsaPkcs15Sha1Sign = rsaPkcs15Sha1Sign
ba.rsaPkcs15Sha1Verify = rsaPkcs15Sha1Verify
ba.hmacSha1 = hmacSha1
ba.sha1Sum = sha1Sum

local function readfile(filepath, fsIo)
  if not fsIo then
    error("readfile no io")
  end

  local f, err
  if fsIo == _G.io then
    f, err = _G.io.open(filepath)
  else
    f, err = fsIo:open(filepath)
  end

  if not f then error("Failed read file '".. filepath.."' ".. err) end

  local data
  data, err = f:read("*a")
  f:close()
  if err then error(err) end
  return data
end

local function createCert(data, fsIo)
  if not data then
    return nil
  end

  if type(data) == 'table' and data.der then
    return data
  end

  local der, pem
  local cert = ba.parsecert(data)
  if cert then
    der = data
    pem = "-----BEGIN CERTIFICATE-----\n" .. ba.b64encode(der) .. "\n-----END CERTIFICATE-----"
  else
    local b64 = data:match("[-]-BEGIN CERTIFICATE.-\n(.+)\n.-END.-CERTIFICATE[-]+")
    if not b64 then
      data = readfile(data, fsIo)
      b64 = data:match("[-]-BEGIN CERTIFICATE.-\n(.+)\n.-END.-CERTIFICATE[-]+")
    end

    if not b64 then
      error("invalid_cert")
    end

    der = ba.b64decode(b64)
    pem = data
    cert = ba.parsecert(der)
  end

  if not cert then
    error("invalid_cert")
  end

  local thumbprint = ba.crypto.hash("sha1")(der)(true)

  local result = {
    pem = pem,
    der = der,
    thumbprint = thumbprint
  }

  return result
end

local function createKey(data, fsIo)
  if not data then
    return nil
  end

  local sz = ba.crypto.keysize(data)
  if not sz then
    local key = data:match("[-]-BEGIN.+PRIVATE KEY.-\n.+\n.-END.+PRIVATE KEY[-]+")
    if not key then
      data = readfile(data, fsIo)
    end
    sz = ba.crypto.keysize(data)
  end

  if not sz then
    error("invalid_key")
  end

  return data
end

local function keysize(key)
  return ba.crypto.keysize(key)
end

local function decrypt(e, key, params)
  return ba.crypto.decrypt(e, key, {padding=params.padding, hashid=params.hash})
end

local function encrypt(data, cert, params)
  return ba.crypto.encrypt(tostring(data), cert.pem, {padding=params.padding, hashid=params.hash})
end

local function symmetric(alg, key, iv, op)
  return ba.crypto.symmetric(alg, key, iv, op)
end

local crypto = {
  sha1Sum = sha1Sum,
  hmacSha1 = hmacSha1,
  hmacSha256 = hmacSha256,
  rsaPkcs15Sha1Sign = rsaPkcs15Sha1Sign,
  rsaPkcs15Sha1Verify = rsaPkcs15Sha1Verify,
  rsaPkcs15Sha256Sign = rsaPkcs15Sha256Sign,
  rsaPkcs15Sha256Verify = rsaPkcs15Sha256Verify,
  -- rsaPssSha2_256Sign = rsaPssSha2_256Sign,
  -- rsaPssSha2_256Verify = rsaPssSha2_256Verify,
  createCert = createCert,
  createKey = createKey,
  rndbs = ba.rndbs,
  symmetric = symmetric,
  encrypt = encrypt,
  decrypt = decrypt,
  keysize = keysize,
  hash = ba.crypto.hash,
  parsecert = ba.parsecert,
  loadCert = createCert,
  loadKey = createKey,
}

return crypto
