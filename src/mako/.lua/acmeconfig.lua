local Runtime,Log=require"acme/runtime",require"acme/log"

local function validateFields(value,names,label)
   names=" "..names.." "
   for name in pairs(value) do
      assert(names:find(" "..tostring(name).." ",1,true),
         "Invalid ACME "..label.." field: "..tostring(name))
   end
end

local function hex(value) return (value:gsub(".",function(c) return string.format("%02x",c:byte()) end)) end

local function proxyOptions()
   local p=require"loadconf".proxy
   if type(p) ~= "table" then return {} end
   return {proxy=p.name,proxyport=p.port,socks=p.socks,proxyuser=p.proxyuser,proxypass=p.proxypass}
end

local function identity(challenge)
   local explicit=challenge.portalUrl ~= nil or challenge.zoneKey ~= nil or challenge.secret ~= nil
   if explicit then
      assert(type(challenge.portalUrl) == "string" and type(challenge.zoneKey) == "string" and
         type(challenge.secret) == "string",
         "ACME DNS-01 requires portalUrl, zoneKey, and secret when using explicit credentials")
      return {portalUrl=challenge.portalUrl,zoneKey=challenge.zoneKey,
         secret=challenge.secret,http=proxyOptions()}
   end
   local ok,module=pcall(require,"etokengen")
   if not ok then ok,module=pcall(require,"tokengen") end
   if not ok then error("ACME DNS-01 requires a zone key and secret or a tokengen module",2) end
   if type(module.proof) ~= "function" then
      error("The configured SharkTrust portal does not support this enrollment protocol",2)
   end
   local serverName,zoneKey=module.info()
   return {portalUrl="https://"..serverName,zoneKey=hex(zoneKey),proof=module.proof,http=proxyOptions()}
end

return function(config)
   assert(type(config) == "table","Invalid ACME configuration")
   validateFields(config,"acceptTerms email domains production productionUrl stagingUrl cleanup keyType bits namePolicy info challenge","configuration")
   assert(type(config.email) == "string" and type(config.domains) == "table" and
      type(config.domains[1]) == "string" and config.acceptTerms == true,
      "Invalid ACME configuration")
   local keyType=config.keyType or "ecc"
   assert(keyType == "ecc" or keyType == "rsa","Invalid ACME keyType: expected ecc or rsa")
   local challenge=config.challenge or {}
   validateFields(challenge,"type mode portalUrl zoneKey secret dns reverse propagationDelay","challenge")
   assert(next(challenge) == nil or challenge.type == "dns-01",
      "Invalid ACME challenge: set type to dns-01")
   assert(challenge.mode == nil or challenge.mode == "automatic" or challenge.mode == "manual",
      "Invalid ACME challenge mode: expected automatic or manual")
   local dns=challenge.type == "dns-01"
   local manualMode=dns and challenge.mode == "manual"
   if manualMode then
      validateFields(challenge,"type mode","manual challenge")
   end
   local st=dns and not manualMode and identity(challenge) or nil
   local logger=assert(Log.create(function(event)
      local err=event.level == "error"
      local message=(err and "SharkTrust error: " or "SharkTrust: ")..event.message
      tracep(false,err and 0 or 5,message)
      if mako.daemon then mako.log(message,err and {flush=true} or {ts=true}) end
   end))
   local manual=dns and not st and require"acme/dns".createManual{
      notify=function(event) logger:notify(event) end}
   local runtime,err=Runtime.create{
      config={email=config.email,domains=config.domains,
         acceptTerms=config.acceptTerms == true,
         challenge=manual,cleanup=config.cleanup ~= false,
         propagationDelay=challenge.propagationDelay,
         service={production=config.production ~= false,productionUrl=config.productionUrl,
            stagingUrl=config.stagingUrl,http=proxyOptions()},
         key={type=keyType,bits=config.bits}},
      sharktrust=st,
      reverse=challenge.reverse == true,
      registration=st and {name=config.domains[1],namePolicy=config.namePolicy or "increment",
         dns=challenge.dns,info=config.info},
      notify=function(event) logger:notify(event) end
   }
   assert(runtime,err and err.message)
   return runtime
end
