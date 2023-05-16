local function readfile(filepath, fsIo)
  local f = fsIo and fsIo:open(filepath) or _G.io.open(filepath);
  if not f then return end
  local data, err
  data, err = f:read("*a")
  if err then error(err) end
  f:close()
  return data
end

local function createCert(data, fsIo)
  if not data then
    return nil
  end

  if type(data) == 'table' and data.der then
    return data
  end

  if type(data) == 'string' then
    local content = readfile(data, fsIo)
    if content then
      data = content
    end
  end

  local b64 = data:match(".-BEGIN.-\n%s*(.-)\n%s*%-%-")
  local der
  local pem
  if b64 then
    der = ba.b64decode(b64)
    pem = data
  else
    der = data
    pem = "-----BEGIN CERTIFICATE-----\n" .. ba.b64encode(der) .. "\n-----END CERTIFICATE-----"
  end

  local crt = ba.parsecert(der)
  if not crt then
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

  if type(data) == 'string' then
    local content = readfile(data, fsIo)
    if content then
      data = content
    end
  end

  local sz = ba.crypto.keysize(data)
  if not sz then
    error("invalid_key")
  end

  return data
end

return {
  createCert = createCert,
  createKey = createKey
}
