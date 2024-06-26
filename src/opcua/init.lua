local types = require("opcua.types")
local tools = require("opcua.binary.tools")

local function writeFile(io, filePath, content)
   local file,e,res
   file, e = io:open(filePath, "w+")
   if not file then return e end
   res,e = file:write(content)
   if not res then return e end
   res = file:flush()
   if not res then return res end
 end

local serverScriptPattern = [[
local ua = require('opcua.api')
local config = dofile('%s')
local server = ua.newServer(config)
server:initialize()
server:run()
]]

local function genCertificate(certType, hostname, applicationUri)
  local basic128rsa15Config = {
    key="rsa",
    bits=2048
  }

  local basic128rsa15Key = ba.create.key(basic128rsa15Config)
  local basic128rsa15Dn = {
    commonname = hostname,
  }
  local alternativeNames = hostname..";URI:"..applicationUri
  local certtype = type(certType) == "string" and {certType} or certType
  local keyusage = {
    "DIGITAL_SIGNATURE",
    "NON_REPUDIATION",
    "KEY_ENCIPHERMENT",
    "DATA_ENCIPHERMENT",
    "KEY_AGREEMENT",
    "KEY_CERT_SIGN"
  }

  local hashid = "sha256"
  local basic128rsa15Csr = ba.create.csr(basic128rsa15Key, basic128rsa15Dn, alternativeNames, certtype, keyusage, hashid)
  local validFrom=ba.datetime("NOW")
  validFrom = validFrom - {days=1}
  validFrom = validFrom:date(true)

  local validTo=ba.datetime("NOW")
  validTo = validTo + {days=3650}
  validTo = validTo:date(true)
  local serial = 123456

  local basic128rsa15Cert = ba.create.certificate(basic128rsa15Csr, basic128rsa15Key, validFrom, validTo, serial)
  return basic128rsa15Cert, basic128rsa15Key
end

local function genClientCertificate(hostname, applicationUri)
  return genCertificate("SSL_CLIENT", hostname, applicationUri)
end

local function genServerCertificate(hostname, applicationUri)
  return genCertificate("SSL_SERVER", hostname, applicationUri)
end

local function initialize(config, certType, hostname, applicationName, applicationUri, outputDirectory)
   local io,err = ba.openio("disk")
   if err then error(err) end

   if not outputDirectory then
     outputDirectory = os.getenv("PWD")
   end

   print(string.format("initializing server in the directory '%s'", outputDirectory))

   local mainPath = outputDirectory.."/main.lua"
   local configPath = outputDirectory.."/config.lua"
   local basic128rsa15CrtPath = outputDirectory.."/basic128rsa15.pem"
   local basic128rsa15KeyPath = outputDirectory.."/basic128rsa15.key"

   config.applicationName = applicationName
   config.applicationUri = applicationUri
   config.securePolicies ={
     { -- 1
       securityPolicyUri = types.SecurityPolicy.None,
     },
     { -- #2
        securityPolicyUri = types.SecurityPolicy.Basic128Rsa15,
        securityMode = types.MessageSecurityMode.SignAndEncrypt,
        certificate = basic128rsa15CrtPath,
        key = basic128rsa15KeyPath,
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

  print("generating certificate and private key:", basic128rsa15KeyPath)
  local basic128rsa15Cert, basic128rsa15Key = genCertificate(certType, hostname, applicationUri)
  err = writeFile(io, basic128rsa15KeyPath, basic128rsa15Key)
  if err then error(err) end

  print("saving certificate", basic128rsa15CrtPath)
  err = writeFile(io, basic128rsa15CrtPath, basic128rsa15Cert)
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

  initialize(config, "SSL_SERVER", hostname, applicationName, applicationUri, outputDirectory)
end

local function initializeClient(hostname, applicationName, applicationUri, outputDirectory)
  local config = {}
  initialize(config, "SSL_CLIENT", hostname, applicationName, applicationUri, outputDirectory)
end


return {
  initializeServer = initializeServer,
  initializeClient = initializeClient,
  genClientCertificate = genClientCertificate,
  genServerCertificate = genServerCertificate,
}
