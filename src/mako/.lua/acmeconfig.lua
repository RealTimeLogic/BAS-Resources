local Runtime,Log=require"acme/runtime",require"acme/log"

local function hex(value) return (value:gsub(".",function(c) return string.format("%02x",c:byte()) end)) end

local function proxyOptions()
   local p=require"loadconf".proxy
   if type(p) ~= "table" then return {} end
   return {proxy=p.name,proxyport=p.port,socks=p.socks,proxyuser=p.proxyuser,proxypass=p.proxypass}
end

local function fileStore(io,path)
   local function load(cb)
      local fp=io:open(path,"r") or io:open(path..".bak","r")
      if not fp then cb() return end
      local raw=fp:read"a"
      fp:close()
      local ok,value=pcall(ba.json.decode,raw or "")
      if ok then cb(value) else cb(nil,"Invalid SharkTrust state") end
   end
   local function save(value,cb)
      local temp,backup=path..".tmp",path..".bak"
      local fp,err=io:open(temp,"w")
      if not fp then cb(nil,err) return end
      local ok
      ok,err=fp:write(ba.json.encode(value))
      fp:flush()
      fp:close()
      if ok == nil then io:remove(temp) cb(nil,err) return end
      if io:stat(backup) then io:remove(backup) end
      if io:stat(path) and not io:rename(path,backup) then io:remove(temp) cb(nil,"Cannot save SharkTrust state") return end
      ok=io:rename(temp,path)
      if not ok and io:stat(backup) then io:rename(backup,path) end
      if ok and io:stat(backup) then io:remove(backup) end
      if ok then cb(true) else cb(nil,"Cannot save SharkTrust state") end
   end
   return {load=load,save=save}
end

local function tpmAdapter()
   local tpm=ba.tpm
   if not tpm then return end
   return {
      jwtSign=tpm.jwtsign,keyParams=tpm.keyparams,createKey=tpm.createkey,
      hasKey=tpm.haskey,createCsr=tpm.createcsr,sharkcert=tpm.sharkcert
   }
end

local function identity(challenge)
   local portal=challenge.portalUrl or challenge.servername
   if challenge.key then
      return {portalUrl=portal:match"^https://" and portal or "https://"..portal,
         zoneKey=challenge.key,secret=challenge.secret,http=proxyOptions()}
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

local function address(portalUrl)
   local host=portalUrl:match"^https://([^/:]+)"
   return function(cb)
      local socket,err=ba.socket.connect(host,443)
      if not socket then err=tostring(err) cb(nil,{code="address_unavailable",message=err,
         cause=err,temporary=true,retryable=true}) return end
      local ip=socket:sockname()
      socket:close()
      if ip and ip:find("::ffff:",1,true) == 1 then ip=ip:sub(8) end
      if ip then cb{ipAddress=ip} else
         cb(nil,{code="address_unavailable",temporary=true,retryable=true})
      end
   end
end

return function(config)
   assert(type(config.email) == "string" and type(config.domains) == "table" and
      type(config.domains[1]) == "string","Invalid ACME configuration")
   local home=assert(ba.openio"home")
   if not home:stat"acme" then assert(home:mkdir"acme") end
   local challenge=config.challenge or {}
   local dns=challenge.type == "dns-01"
   local st=dns and challenge.servername ~= "manual" and identity(challenge) or nil
   local logger=assert(Log.create(function(event)
      local err=event.level == "error"
      local message=(err and "SharkTrust error: " or "SharkTrust: ")..event.message
      tracep(false,err and 0 or 5,message)
      if mako.daemon then mako.log(message,err and {flush=true} or {ts=true}) end
   end))
   local manual=dns and not st and require"acme/dns".createManual{
      notify=function(event) logger:notify(event) end}
   local tpm=tpmAdapter()
   local runtime,err=Runtime.create{
      io=home,install=require"acme/_server"(tpm),tpm=tpm,
      config={email=config.email,domains=config.domains,
         acceptTerms=config.acceptTerms == true or config.acceptterms == true,
         challenge=manual,cleanup=config.cleanup ~= false,
         propagationDelay=challenge.propagationDelay,
         service={production=config.production ~= false,productionUrl=config.productionUrl,
            stagingUrl=config.stagingUrl,http=proxyOptions()},
         key={type=config.rsa and "rsa" or config.keyType,bits=config.bits,tpm=config.tpm == true}},
      sharktrust=st,store=st and fileStore(home,"acme/bacme.json"),
      address=st and address(st.portalUrl),reverse=challenge.revcon == true,
      registration=st and {name=config.domains[1],namePolicy=config.namePolicy or "increment",
         dns=challenge.dns,info=config.info},
      notify=function(event) logger:notify(event) end
   }
   assert(runtime,err and err.message)
   return runtime
end
