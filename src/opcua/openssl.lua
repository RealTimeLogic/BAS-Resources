local openssl = require("openssl")
local bytearray = require("opcua.compat").bytearray

local BlockSize = 256

local function hashSum(ctx, ...)
  local params = {...}
  for _,data in ipairs(params) do
    if type(data) == 'string' then
      ctx:update(data)
    else
      local dlen = #data
      for i = 1,dlen,BlockSize do
        local delta = dlen - (i - 1)
        if delta > BlockSize then
          delta = BlockSize
        end
        ctx:update(bytearray.tostring(data, i, i + delta - 1))
      end
    end
  end
  local sum = ctx:final(true)
  return sum
end

local function sha1Sum(...)
  local ctx = openssl.digest.new('sha1')
  return hashSum(ctx, ...)
end

local function sha256Sum(...)
  local ctx = openssl.digest.new('sha256')
  return hashSum(ctx, ...)
end

local function hmacSha1(key, ...)
  if type(key) ~= 'string' then
    key = tostring(key)
  end
  local ctx = openssl.hmac.new('sha1', key)
  return hashSum(ctx, ...)
end

local function hmacSha256(key, ...)
  if type(key) ~= 'string' then
    key = tostring(key)
  end
  local ctx = openssl.hmac.new('sha256', key)
  return hashSum(ctx, ...)
end

local function rsaPkcs15Sha256Sign(key, ...)
  local sum = sha256Sum(...)
  local ctx = key:ctx()
  ctx:sign_init()
  local a = true
  a = a and ctx:ctrl("rsa_padding_mode", "pkcs1")
  a = a and ctx:ctrl("digest", "sha256")
  a = a and ctx:sign(sum)
  if not a then
    local err = openssl.error()
    return nil,err
  end
  return a
end

local function rsaPkcs15Sha1Sign(key, ...)
  local sum = sha1Sum(...)
  local ctx = key:ctx()
  ctx:sign_init()
  local a = true
  a = a and ctx:ctrl("rsa_padding_mode", "pkcs1")
  a = a and ctx:ctrl("digest", "sha1")
  a = a and ctx:sign(sum)
  if not a then
    local err = openssl.error()
    return nil,err
  end
  return a
end

local function rsaPkcs15Sha256Verify(cert, sign, ...)
  local sum = sha256Sum(...)

  local key = cert.native:pubkey()
  local ctx = key:ctx()
  ctx:verify_init()
  local a = true
  a = a and ctx:ctrl("rsa_padding_mode", "pkcs1")
  a = a and ctx:ctrl("digest", "sha256")
  a = a and ctx:verify(sign, sum)
  if not a then
    local err = openssl.error()
    return false,err
  end
  return true
end

local function rsaPkcs15Sha1Verify(cert, sign, ...)
  local sum = sha1Sum(...)

  local key = cert.native:pubkey()
  local ctx = key:ctx()
  ctx:verify_init()
  local a = true
  a = a and ctx:ctrl("rsa_padding_mode", "pkcs1")
  a = a and ctx:ctrl("digest", "sha1")
  a = a and ctx:verify(sign, sum)
  if not a then
    local err = openssl.error()
    return false,err
  end
  return true
end

local function rsaPssSha2_256Verify(cert, sign, ...)
  local sum = sha256Sum(...)

  local key = cert.native:pubkey()
  local ctx = key:ctx()
  ctx:verify_init()
  local a = true
  a = a and ctx:ctrl("rsa_padding_mode", "pss")
  a = a and ctx:ctrl("digest", "sha256")
  a = a and ctx:ctrl("rsa_pss_saltlen", "digest")
  a = a and ctx:verify(sign, sum)
  if not a then
    local err = openssl.error()
    return false,err
  end
  return true
end

local function rsaPssSha2_256Sign(key, ...)
  local sum = sha256Sum(...)
  local ctx = key:ctx()
  ctx:sign_init()
  local a = true
  a = a and ctx:ctrl("rsa_padding_mode", "pss")
  a = a and ctx:ctrl("digest", "sha256")
  a = a and ctx:ctrl("rsa_pss_saltlen", "digest")
  a = a and ctx:sign(sum)
  if not a then
    local err = openssl.error()
    return nil,err
  end
  return a
end

local function readfile(filepath, cio)
  local f = cio and cio:open(filepath) or _G.io.open(filepath)
  if not f then return end
  local data, err
  data, err = f:read("*a")
  f:close()
  if err then error(err) end
  return data
end


local function loadKey(pem, io)
  if not pem then
    return nil
  end

  local key
  if type(pem) == 'string' then
    local content = readfile(pem, io)
    if content then
      pem = content
    end

    key = pem:match("[-]-BEGIN.+PRIVATE KEY.-\n.+\n.-END.+PRIVATE KEY[-]+")
    if not key then
      error("invalid_key")
    end

    key = key and openssl.base64(key, false, false)
    key = key and openssl.pkey.read(key, true, 'der')
    if not key then
      error("invalid key pem")
    end
  else
    key = pem
  end

  return key
end

local function loadCert(pem, io)
  if not pem then
    return nil
  end

  if type(pem) == 'table' then
    return pem
  end

  if type(pem) == 'string' then
    local content = readfile(pem, io)
    if content then
      pem = content
    end
  end

  local cert = pem:match("[-]-BEGIN CERTIFICATE.-\n(.+)\n.-END.-CERTIFICATE[-]+")
  if cert then
    cert = cert and openssl.base64(cert, false, false)
  else
    cert = pem
  end

  local der = cert
  local thumbprint = sha1Sum(cert)
  cert = cert and openssl.x509.read(cert)
  if not cert then
    local err = openssl.error()
    error(err or 'invalid_cert')
  end

  return {
    native=cert,
    thumbprint=thumbprint,
    der = der
  }
end

local function parsecert(der)
  local x509 = openssl.x509
  local parsed = x509.read(der, "der")
  if not parsed then
    error("invalid_cert")
  end
  local pars = parsed:parse()
  return pars
end

local function hash(alg, alg2, key)
  local ctx
  if alg == 'hmac' then
    ctx = openssl.hmac.new(alg2, key)
  else
    ctx = openssl.digest.new(alg)
  end

  local hash1 = {
    __call = function(param, msg)
      if (type(msg) == 'boolean') then
        return ctx:final(true)
      end
      ctx:update(msg)
      return param
    end
  }

  setmetatable(hash1, hash1)

  return hash1
end

local function keysize(pem)
  local key = loadKey(pem)
  local parsed = key:parse()
  return parsed.size
end

local function decrypt(cipher, pem, params)
  local key = loadKey(pem)
  local ctx = key:ctx()
  ctx:decrypt_init()

  if params then
    if params.padding then
      ctx:ctrl("rsa_padding_mode", params.padding)
      if params.hash then
        ctx:ctrl("rsa_oaep_md", params.hash)
      end
    end
  end

  local msg = ctx:decrypt(cipher)
  if not msg then
    local err = openssl.error()
    return nil,err
  end
  return msg
end

local function encrypt(msg, cert, params)
  local key = cert.native:pubkey()
  local ctx = key:ctx()
  ctx:encrypt_init()

  if params then
    if params.padding then
      ctx:ctrl("rsa_padding_mode", params.padding)
      if params.hash then
        ctx:ctrl("rsa_oaep_md", params.hash)
      end
    end
  end

  local cipher = ctx:encrypt(msg)
  if not cipher then
    local err = openssl.error()
    return nil,err
  end
  return cipher
end

local function symmetric(alg, key, iv, op)
  local sz = #key * 8
  local cipher
  alg =  "aes-"..tostring(sz).."-"..string.lower(alg)

  if op == 'encrypt' then
    cipher = openssl.cipher.encrypt_new(alg, key, iv)
  elseif op == 'decrypt' then
    cipher = openssl.cipher.decrypt_new(alg, key, iv)
  else
    error("invalid_op")
  end

  cipher:padding(false)

  local encryptor = {
    encrypt = function(_, msg)
      return cipher:update(msg)
    end,
    decrypt = function(_, msg)
      return cipher:update(msg)
    end
  }

  return encryptor
end

local crypto = {
  sha1Sum = sha1Sum,
  hmacSha1 = hmacSha1,
  hmacSha256 = hmacSha256,
  rsaPkcs15Sha1Sign = rsaPkcs15Sha1Sign,
  rsaPkcs15Sha1Verify = rsaPkcs15Sha1Verify,
  rsaPkcs15Sha256Sign = rsaPkcs15Sha256Sign,
  rsaPkcs15Sha256Verify = rsaPkcs15Sha256Verify,
  rsaPssSha2_256Sign = rsaPssSha2_256Sign,
  rsaPssSha2_256Verify = rsaPssSha2_256Verify,
  createCert = loadCert,
  createKey = loadKey,
  rndbs = openssl.random,
  symmetric = symmetric,
  encrypt = encrypt,
  decrypt = decrypt,
  keysize = keysize,
  hash = hash,
  parsecert = parsecert,
  loadCert = loadCert,
  loadKey = loadKey,
}

return crypto
