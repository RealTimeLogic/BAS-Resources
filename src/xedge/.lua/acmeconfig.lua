local Runtime,ST=require"acme/runtime",require"acme/sharktrust"

local function hex(value) return (value:gsub(".",function(c) return string.format("%02x",c:byte()) end)) end

local function generatedIdentity()
   local ok,module=pcall(require,"etokengen")
   if not ok then ok,module=pcall(require,"tokengen") end
   if not ok then return end
   local portal,zoneKey=module.info()
   return {portalUrl="https://"..portal,zoneKey=hex(zoneKey),proof=module.proof},portal
end

local function identity(config)
   local manual=type(config) == "table" and config.manualIdentity == true
   local value,portal=generatedIdentity()
   if value and not manual then return value,portal,true end
   if type(config) ~= "table" or type(config.portalUrl) ~= "string" or
      type(config.zoneKey) ~= "string" or type(config.secret) ~= "string" then return end
   portal=config.portalUrl:gsub("^https://",""):gsub("/.*$","")
   return {portalUrl=config.portalUrl,zoneKey=config.zoneKey,secret=config.secret},portal,false
end

local function available(config,name,callback)
   local options=identity(config)
   if not options then callback(nil,{code="sharktrust_not_configured"}) return end
   local client,problem=ST.create(options)
   if not client then callback(nil,problem) return end
   return client:isAvailable(name,function(result,err)
      client:close()
      callback(result,err)
   end)
end

local function create(config,save,notify)
   local st,portal,generated=identity(config)
   if not st then return nil,{code="sharktrust_not_configured"} end
   local runtime,err=Runtime.create{
      config={email=config.email,domains={config.name},acceptTerms=true,cleanup=true,
         service={production=config.production ~= false,productionUrl=config.productionUrl,
            stagingUrl=config.stagingUrl},key={type="ecc"}},
      sharktrust=st,reverse=config.revcon == true,
      registration={name=config.name,namePolicy="exact",info=config.info or "Xedge"},
      store={
         load=function(cb) cb(config.state) end,
         save=function(state,cb)
            local previous=config.state
            config.state=state
            local ok=save()
            if not ok then config.state=previous end
            if ok then cb(true) else cb(nil,"Cannot save SharkTrust state") end
         end
      },
      notify=notify
   }
   if not runtime then return nil,err end
   return runtime,portal,generated
end

return {create=create,identity=identity,available=available}
