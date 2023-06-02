local ua = require("opcua.api")

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

local function genCertificate(certType, hostname, applicationName, applicationUri)
  local basic128rsa15Config = {
    key="rsa",
    bits=2048
  }

  local basic128rsa15Key = ba.create.key(basic128rsa15Config)
  local basic128rsa15Dn = {
    commonname = hostname,
  }
  local alternativeNames = hostname..";URI:"..applicationUri
  local certtype = {"SSL_SERVER", "SSL_CLIENT"}
  local keyusage = {
    "DIGITAL_SIGNATURE",
    "NON_REPUDIATION",
    "KEY_ENCIPHERMENT",
    "DATA_ENCIPHERMENT",
    "KEY_AGREEMENT",
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

local function genClientCertificate(hostname, applicationName, applicationUri)
  return genCertificate("SSL_CLIENT", hostname, applicationName, applicationUri)
end

local function genServerCertificate(hostname, applicationName, applicationUri)
  return genCertificate("SSL_SERVER", hostname, applicationName, applicationUri)
end

local function initialize(config, hostname, applicationName, applicationUri, outputDirectory)
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
       securityPolicyUri = ua.Types.SecurityPolicy.None,
     },
     { -- #2
        securityPolicyUri = ua.Types.SecurityPolicy.Basic128Rsa15,
        securityMode = ua.Types.MessageSecurityMode.SignAndEncrypt,
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
   ua.Tools.printTable(nil, config, appendConfig)
   if err then error(err) end
   err = writeFile(io, configPath, resultConfig)
   if err then error(err) end

   local basic128rsa15Config = {
      key="rsa",
      bits=2048
   }

   print("generating certificate and private key:", basic128rsa15KeyPath)
   local basic128rsa15Cert, basic128rsa15Key = genCert(hostname, applicationName, applicationUri)
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

  initialize(config, hostname, applicationName, applicationUri, outputDirectory)
end

local function initializeClient(hostname, applicationName, applicationUri, outputDirectory)
  local config = {}
  initialize(config, hostname, applicationName, applicationUri, outputDirectory)
end


return {
  initializeServer = initializeServer,
  initializeClient = initializeClient,
  genClientCertificate = genServerCertificate,
  genServerCertificate = genClientCertificate,
}
