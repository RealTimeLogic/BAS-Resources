local tools = require("opcua.tools")
local const = require("opcua.const")

local function writeFile(io, filePath, content)
  local file, err = io:open(filePath, "w+")
  if not file then return err or "cannot open "..filePath end
  local result
  result, err = file:write(content)
  if result then result, err = file:flush() end
  local closed, closeErr = file:close()
  if not result then return err or "cannot write "..filePath end
  if not closed then return closeErr or "cannot close "..filePath end
end

local serverScriptPattern = [[
local ua = require('opcua.api')
local config = dofile('%s')
local server = ua.newServer(config)
server:initialize()
server:run()
]]

local function genCertificate(isClient, hostname, applicationName, applicationUri)
  if not isClient and
      (type(hostname) ~= "string" or hostname == "" or hostname:find("[;%c]")) then
    error("invalid certificate hostname")
  end
  if type(applicationName) ~= "string" or applicationName == "" or applicationName:find("%c") then
    error("invalid certificate application name")
  end
  if type(applicationUri) ~= "string" or
      not applicationUri:match("^[%a][%w+.-]*:%S+$") or applicationUri:find("[;%s%c]") then
    error("invalid certificate application URI")
  end

  local aes128_rsa_oaepConfig = {
    key="rsa",
    bits=2048
  }

  local aes128_rsa_oaepKey = assert(ba.create.key(aes128_rsa_oaepConfig))
  local aes128_rsa_oaepDn = {
    commonname = applicationName,
    organization = "RealTimeLogic",
  }
  local alternativeNames = "URI:"..applicationUri
  if not isClient then alternativeNames = hostname..";"..alternativeNames end
  local certtype = {isClient and "SSL_CLIENT" or "SSL_SERVER"}
  local keyusage = {
    "DIGITAL_SIGNATURE",
    "NON_REPUDIATION",
    "KEY_ENCIPHERMENT",
    "DATA_ENCIPHERMENT",
    "KEY_CERT_SIGN"
  }

  local hashid = "sha256"
  local aes128_rsa_oaepCsr = assert(ba.create.csr(aes128_rsa_oaepKey, aes128_rsa_oaepDn, alternativeNames, certtype, keyusage, hashid))

  local now = assert(ba.datetime("NOW", 0))
  local validFrom = (now - {days = 1}):date()
  -- Use a fixed duration; TimeSpan does not support calendar years.
  local validTo = (now + {days = 10 * 365}):date()

  -- Generate a positive 48-bit serial independently of the private key.
  local serial
  repeat
    local randomBytes = ba.rndbs(6)
    serial = 0
    for i = 1, 6 do
      serial = serial * 256 + randomBytes:byte(i)
    end
  until serial > 0

  local policy = {
    profile = isClient and "opcuaClient" or "opcuaServer",
    approveSANs = function(names)
      if #names ~= (isClient and 1 or 2) then return false end
      local dns, uri = false, false
      for _, name in ipairs(names) do
        if not dns and hostname and name.type == "DNS" and name.value == hostname then
          dns = true
        elseif not uri and name.type == "URI" and name.value == applicationUri then
          uri = true
        else
          return false
        end
      end
      return (isClient or dns) and uri
    end,
  }

  -- Omit the issuer and sign with the application's own key.
  local aes128_rsa_oaepCert = assert(ba.create.certificate(
    aes128_rsa_oaepCsr, aes128_rsa_oaepKey, validFrom, validTo, serial, policy))
  return aes128_rsa_oaepCert, aes128_rsa_oaepKey
end

local function genClientCertificate(applicationName, applicationUri)
  return genCertificate(true, nil, applicationName, applicationUri)
end

local function genServerCertificate(hostname, applicationName, applicationUri)
  return genCertificate(false, hostname, applicationName, applicationUri)
end

local function initialize(config, isClient, hostname, applicationName, applicationUri, outputDirectory)
   local io,err = ba.openio("disk")
   if err then error(err) end

   if not outputDirectory then
     outputDirectory = os.getenv("PWD")
   end

   print(string.format("initializing server in the directory '%s'", outputDirectory))

   local mainPath = outputDirectory.."/main.lua"
   local configPath = outputDirectory.."/config.lua"
   local aes128_rsa_oaepCrtPath = outputDirectory.."/aes128_rsa_oaep.pem"
   local aes128_rsa_oaepKeyPath = outputDirectory.."/aes128_rsa_oaep.key"

   -- Generate before writing example files so signing failure preserves them.
   local aes128_rsa_oaepCert, aes128_rsa_oaepKey =
     genCertificate(isClient, hostname, applicationName, applicationUri)

   config.applicationName = applicationName
   config.applicationUri = applicationUri
   config.securePolicies ={
     { -- #1: Aes128_Sha256_RsaOaep
        securityPolicyUri = const.SecurityPolicy.Aes128_Sha256_RsaOaep,
        securityMode = const.MessageSecurityMode.SignAndEncrypt,
        certificate = aes128_rsa_oaepCrtPath,
        key = aes128_rsa_oaepKeyPath,
     }
   }

   config.logging = {
    socket = {
      dbgOn = false,  -- debug logs of socket
      infOn = true,  -- information logs about sockets
      errOn = true,  -- Errors on sockets
    },
    binary = {
      dbgOn = false,  -- Debugging traces about binary protocol. Print encoded message hex data.
      infOn = true,  -- Information traces about binary protocol
      errOn = true,  -- Errors in binary protocol
    },
    services = {
      dbgOn = false,  -- Debugging traces about UA services work
      infOn = true,  -- Informations traces
      errOn = true,  -- Errors
    }
  }

  print(string.format("saving configuration file '%s'", configPath))

  local resultConfig = "return "
  local function appendConfig(str)
    resultConfig = resultConfig..str
  end
  tools.printTable(nil, config, appendConfig)
  if err then error(err) end
  err = writeFile(io, configPath, resultConfig)
  if err then error(err) end

  print("saving private key", aes128_rsa_oaepKeyPath)
  err = writeFile(io, aes128_rsa_oaepKeyPath, aes128_rsa_oaepKey)
  if err then error(err) end

  print("saving certificate", aes128_rsa_oaepCrtPath)
  err = writeFile(io, aes128_rsa_oaepCrtPath, aes128_rsa_oaepCert)
  if err then error(err) end

  print(string.format("saving main script '%s'", mainPath))
  local serverScript = string.format(serverScriptPattern, configPath)
  if err then error(err) end
  err = writeFile(io, mainPath, serverScript)
  if err then error(err) end
end

local function initializeServer(hostname, applicationName, applicationUri, outputDirectory)
  local config = {
    listenPort = 4841,
    listenAddress=hostname,
    endpointUrl = "opc.tcp://"..hostname..":4841"
  }

  initialize(config, false, hostname, applicationName, applicationUri, outputDirectory)
end

local function initializeClient(hostname, applicationName, applicationUri, outputDirectory)
  local config = {}
  initialize(config, true, hostname, applicationName, applicationUri, outputDirectory)
end


return {
  initializeServer = initializeServer,
  initializeClient = initializeClient,
  genClientCertificate = genClientCertificate,
  genServerCertificate = genServerCertificate,
}
