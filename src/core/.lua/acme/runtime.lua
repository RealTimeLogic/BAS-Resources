local M={}

local U=require"acme/_util"
local errorTable,copy,safeCallback,resolveService,reject=U.err,U.copy,U.callback,U.resolveService,U.reject
local problem,callback=errorTable,safeCallback
local function identifiersKey(ids)
   local values={}
   for _,id in ipairs(ids or {}) do values[#values+1]=id.type..":"..id.value end
   table.sort(values)
   return table.concat(values,"\0")
end

local function fileStore(io,base)
   local path=base.."/sharktrust.json"
   return {
      load=function(cb)
         local value,exists=U.readJson(io,path)
         cb(value,exists and not value and problem"invalid_saved_state" or nil)
      end,
      save=function(value,cb)
         if not io:stat(base) and not io:mkdir(base) then cb(nil,problem"storage_write_failed") return end
         cb(U.writeJson(io,path,value))
      end
   }
end

local function certificateExpiry(pem)
   local body=type(pem) == "string" and pem:match("%-%-%-%-%-BEGIN CERTIFICATE%-%-%-%-%-%s*(.-)%s*%-%-%-%-%-END CERTIFICATE%-%-%-%-%-")
   if not body then return end
   local ok,info=pcall(ba.parsecert,ba.b64decode((body:gsub("%s",""))))
   local expires=ok and info and ba.parsecerttime(info.tzto)
   return expires and expires ~= 0 and expires or nil,ok and info and ba.parsecerttime(info.tzfrom)
end

-- Keep account identities with registration, outside the certificate cache.
local function registrationStore(store)
   local state
   local function access(value,cb)
      local called
      local function done(result,err)
         if called then return end
         called=true
         if err then err=errorTable(value and "storage_write_failed" or "storage_read_failed",
            type(err)=="table" and err.message or tostring(err),{temporary=true}) end
         safeCallback(cb,result,err)
      end
      local ok,err=pcall(value and store.save or store.load,value or done,value and done)
      if not ok then done(nil,err) end
   end
   local function load(cb)
      access(nil,function(value,err) state=copy(value or {}) cb(value,err) end)
   end
   return {
      load=function(cb) load(function(value,err)
         cb(value and (value.credential or not value.accounts) and value or nil,err)
      end) end,
      save=function(value,cb)
         value.accounts=state and state.accounts
         access(value,cb)
      end,
      account=function(id,value,cb)
         if not value then return load(function(_,err) cb(state.accounts and state.accounts[id],err) end) end
         state.accounts=state.accounts or {}
         state.accounts[id]=copy(value)
         access(state,cb)
      end
   }
end

local function validateConfig(config)
   if type(config) ~= "table" or not (config.service and config.service.sharkca) and
      (type(config.email) ~= "string" or config.email == "") or
      type(config.domains) ~= "table" or type(config.domains[1]) ~= "string" then
      return nil,errorTable("invalid_configuration")
   end
   if not (config.service and config.service.sharkca) and config.acceptTerms ~= true then return nil,errorTable("terms_not_accepted") end
   local service,problem=resolveService(config.service)
   if not service then return nil,problem end
   local result,seen={},{}
   for name,value in pairs(config) do result[name]=name == "challenge" and value or copy(value) end
   result.domains={}
   for _,domain in ipairs(config.domains) do
      if type(domain) ~= "string" or domain == "" then return nil,errorTable("invalid_configuration") end
      domain=domain:lower()
      if not seen[domain] then seen[domain]=true result.domains[#result.domains+1]=domain end
   end
   result.service=service
   result.fallbackRenewBefore=tonumber(config.fallbackRenewBefore) or 22*86400
   if result.fallbackRenewBefore < 3600 then return nil,errorTable("invalid_configuration") end
   return result
end

function M.createManager(options)
   if type(options.install) ~= "function" then return nil,errorTable("invalid_installer") end
   if not options.io then return nil,errorTable("invalid_io") end

   local fileIo,engine,install=options.io,options.engine,options.install
   local notify=options.notify
   local renewAllowed=options.renewAllowed
   local deps=options.dependencies or {}
   local run=deps.run or function(action) ba.thread.run(action) end
   local timerFactory=deps.timer or function(action) return ba.timer(action) end
   local now,random=deps.now or os.time,deps.random or math.random
   local retryFirst,retryMax=deps.renewRetryDelay or 30,deps.renewRetryMaxDelay or 300
   local basePath=options.path or "acme"
   local servicesPath,activePath=basePath.."/services",basePath.."/active.json"
   local profiles,manager,loaded,started,closed={},{},false,false,false
   local config,activeProfile,busy,timer,lastError,scheduledCheck,retryAt
   local retryDelay=retryFirst
   local stopCount=0
   local installing=0
   local pendingUpdates,drainUpdates={}

   local function emit(...) safeCallback(notify,...) end
   local function ensureDirectories()
      if not fileIo:stat(basePath) and not fileIo:mkdir(basePath) or
         not fileIo:stat(servicesPath) and not fileIo:mkdir(servicesPath) then
         return nil,errorTable("storage_write_failed")
      end
      return true
   end

   local function readJson(path) return U.readJson(fileIo,path) end
   local function writeJson(path,value) return U.writeJson(fileIo,path,value) end

   local function profilePath(id) return servicesPath.."/"..id..".json" end
   local function loadProfile(service)
      local profile=profiles[service.serviceId]
      if profile then return profile end
      local saved,exists=readJson(profilePath(service.serviceId))
      if exists and (type(saved) ~= "table" or saved.version ~= 2 or
         saved.serviceId ~= service.serviceId or saved.directoryUrl ~= service.directoryUrl or
         type(saved.account) ~= "table" or type(saved.certificates) ~= "table") then
         return nil,errorTable("invalid_saved_state")
      end
      profile=saved or {version=2,serviceId=service.serviceId,directoryUrl=service.directoryUrl,
         account={email=config and config.email},certificates={},updatedAt=now()}
      profiles[service.serviceId]=profile
      return profile
   end
   local function saveProfile(profile)
      profile.updatedAt=now()
      return writeJson(profilePath(profile.serviceId),profile)
   end

   local function certificateList(profile)
      local result={}
      for domain,record in pairs(profile and profile.certificates or {}) do
         if record.privateKey and type(record.certificate) == "string" then
            result[#result+1]={domain=domain,privateKey=record.privateKey,certificate=record.certificate}
         end
      end
      table.sort(result,function(a,b) return a.domain < b.domain end)
      return result
   end

   local function installProfile(profile,callback)
      local records=certificateList(profile)
      installing=installing+1
      local called=false
      local function done(ok,message)
         if called then return end
         called=true
         installing=installing-1
         if ok then safeCallback(callback,true) else
            safeCallback(callback,nil,errorTable("certificate_install_failed",
               type(message) == "table" and message.message or tostring(message)))
         end
      end
      local ok,message=pcall(install,records,done)
      if not ok then done(nil,message) end
   end

   local function fallbackRenewal(record)
      local expires,issued=certificateExpiry(record.certificate)
      expires=record.expiresAt or expires
      record.expiresAt=expires
      if not expires then record.renewAt,record.ariCheckAt=now(),nil return end
      local before=math.min(config.fallbackRenewBefore,math.max(0,expires-(issued or record.issuedAt or now()))/3)
      local jitter=math.floor((random()-.5)*math.min(86400,before/4))
      record.renewAt,record.ariCheckAt=math.max(now(),expires-before+jitter),nil
   end

   local function refreshRenewal(profile,domain,callback)
      local record=profile.certificates[domain]
      if not record then return reject(callback,"certificate_not_found") end
      local function save() local ok,problem=saveProfile(profile) safeCallback(callback,ok,problem) end
      if not record.ariId then fallbackRenewal(record) return save() end
      engine:renewalInfo(config.service,{certificate=record.certificate,ariId=record.ariId},function(info,problem)
         if info and info.suggestedWindow then
            local first,last=info.suggestedWindow.start,info.suggestedWindow["end"]
            record.renewAt=math.max(now(),math.floor(first+random()*(last-first)))
            record.ariCheckAt=now()+math.max(60,math.min(86400,info.retryAfter or 21600))
            record.explanationUrl,record.ariError=info.explanationUrl,nil
         else
            fallbackRenewal(record)
            record.ariCheckAt,record.ariError=now()+21600,problem and problem.code or "ari_unavailable"
         end
         save()
      end)
   end

   local function issue(profile,domain,force,callback)
      if closed then return reject(callback,"manager_closed") end
      local old=profile.certificates[domain]
      local ids=copy(config.identifiers)
      local idKey=identifiersKey(ids)
      if not force and old and old.expiresAt and old.expiresAt > now() and old.renewAt and old.renewAt > now() then
         return safeCallback(callback,old)
      end
      if not config.service.sharkca and profile.account.email ~= config.email then profile.account={email=config.email} end
      local key=copy(config.key or {})
      if old and old.privateKey then key.privateKey=old.privateKey end
      if config.service.sharkca and not key.privateKey then
         local thumb,err=engine:prepareAccount(profile.account)
         if not thumb then return safeCallback(callback,nil,err) end
         key.privateKey,err=engine:createKey("device-"..thumb,key)
         if not key.privateKey then return safeCallback(callback,nil,err) end
      end
      engine:certificate(config.service,profile.account,{domain=domain,identifiers=ids,acceptTerms=config.acceptTerms,
         challenge=config.challenge,key=key,timeout=config.timeout,dnsResolveTimeout=config.dnsResolveTimeout,
         replaces=old and old.ariId},function(result,problem)
         if not result then return safeCallback(callback,nil,problem) end
         if idKey~=identifiersKey(config.identifiers) then return reject(callback,"identifiers_changed",nil,{temporary=true}) end
         profile.account=result.account
         local expires=result.expiresAt or certificateExpiry(result.certificate)
         profile.certificates[domain]={domain=domain,identifiers=ids,privateKey=result.privateKey,certificate=result.certificate,
            expiresAt=expires,ariId=result.ariId,orderUrl=result.orderUrl,
            directoryUrl=result.directoryUrl,issuedAt=now()}
         refreshRenewal(profile,domain,function(_,renewProblem)
            if renewProblem then return safeCallback(callback,nil,renewProblem) end
            emit(old and 41 or 40)
            safeCallback(callback,profile.certificates[domain])
         end)
      end)
   end

   local function each(items,action,callback,index)
      index=index or 1
      if not items[index] then return safeCallback(callback,true) end
      action(items[index],function(_,problem)
         if problem then return safeCallback(callback,nil,problem) end
         each(items,action,callback,index+1)
      end)
   end
   local function needed(profile)
      local result={}
      for _,domain in ipairs(config.domains) do
         local record=profile.certificates[domain]
         if not record or not record.expiresAt or record.expiresAt <= now() or
            identifiersKey(record.identifiers)~=identifiersKey(config.identifiers) then result[#result+1]=domain end
      end
      return result
   end
   local function prune(profile)
      if not config.cleanup then return false end
      local keep,changed={},false
      for _,domain in ipairs(config.domains) do keep[domain]=true end
      for domain in pairs(profile.certificates) do
         if not keep[domain] then profile.certificates[domain],changed=nil,true end
      end
      return changed
   end

   local function commit(profile,callback)
      local previous=activeProfile
      installProfile(profile,function(installed,problem)
         if not installed then return safeCallback(callback,nil,problem) end
         local ok,saveProblem=writeJson(activePath,{version=2,serviceId=profile.serviceId,
            directoryUrl=profile.directoryUrl,updatedAt=now()})
         if not ok then
            return installProfile(previous or {certificates={}},function(restored,restoreProblem)
               if not restored then saveProblem.rollback=restoreProblem end
               safeCallback(callback,nil,saveProblem)
            end)
         end
         activeProfile=profile
         emit(50)
         safeCallback(callback,true)
      end)
   end

   local function enter(name,callback)
      if closed then return reject(callback,"manager_closed") end
      if busy then return reject(callback,"operation_in_progress",nil,{temporary=true}) end
      busy=name
      return true
   end
   local function leave(callback,result,problem)
      busy=nil
      if problem then lastError=copy(problem) end
      safeCallback(callback,result,problem)
      if drainUpdates then drainUpdates() end
   end
   local function cancelTimer()
      if timer then timer:cancel() timer=nil end
   end
   local function scheduleTimer()
      cancelTimer()
      if not started or not activeProfile then return end
      local nextTime=retryAt
      if not nextTime then
         for _,record in pairs(activeProfile.certificates) do
            local candidate=record.renewAt
            if candidate and (not nextTime or candidate < nextTime) then nextTime=candidate end
            candidate=record.ariCheckAt
            if candidate and (not nextTime or candidate < nextTime) then nextTime=candidate end
         end
      end
      if not nextTime then return end
      timer=timerFactory(function() timer=nil scheduledCheck() return false end)
      -- Long renewal delays need another due-date check before they expire.
      timer:set(math.min(4294967295,math.max(1000,math.floor((nextTime-now())*1000))),true)
   end

   scheduledCheck=function()
      if busy or not started or not activeProfile then return scheduleTimer() end
      busy="scheduledCheck"
      retryAt=nil
      local renew,refresh,current,deferred={},{},now(),false
      for domain,record in pairs(activeProfile.certificates) do
         if record.renewAt and record.renewAt <= current or
            identifiersKey(record.identifiers)~=identifiersKey(config.identifiers) then renew[#renew+1]=domain
         elseif record.ariCheckAt and record.ariCheckAt <= current then refresh[#refresh+1]=domain end
      end
      local function finish(problem)
         installProfile(activeProfile,function(_,installProblem)
            busy=nil
            if problem and installProblem then problem.install=installProblem end
            problem=problem or installProblem
            if problem then
               lastError=copy(problem)
               if problem.temporary == true and problem.retryable ~= false then
                  retryAt=now()+retryDelay
                  retryDelay=math.min(retryDelay*2,retryMax)
               else retryAt=now()+21600 end
            elseif deferred then retryAt=now()+3600
            else retryDelay,retryAt=retryFirst,nil end
            scheduleTimer()
            drainUpdates()
         end)
      end
      local firstProblem
      local function continueWith(done)
         return function(_,problem)
            firstProblem=firstProblem or problem
            done(true)
         end
      end
      -- A failing domain must not prevent other due certificates from renewing.
      each(refresh,function(domain,done)
         refreshRenewal(activeProfile,domain,continueWith(done))
      end,function()
         each(renew,function(domain,done)
            local record=activeProfile.certificates[domain]
            if not renewAllowed or renewAllowed(domain,record.expiresAt) ~= false then
               issue(activeProfile,domain,true,continueWith(done))
            else deferred=true done(true) end
         end,function() finish(firstProblem) end)
      end)
   end

   local function prepare(profile,callback)
      local domains=needed(profile)
      each(domains,function(domain,done) issue(profile,domain,true,done) end,function(_,problem)
         if problem then return safeCallback(callback,nil,problem) end
         local changed=prune(profile)
         if changed then
            local ok,saveProblem=saveProfile(profile)
            if not ok then return safeCallback(callback,nil,saveProblem) end
         end
         safeCallback(callback,{rebuilt=#domains,reused=#domains == 0,cleaned=changed})
      end)
   end

   drainUpdates=function()
      if busy or #pendingUpdates==0 then return end
      local waiting=pendingUpdates pendingUpdates={}
      local function done(result,err)
         for _,cb in ipairs(waiting) do safeCallback(cb,result,err) end
      end
      if closed then return done(nil,errorTable("manager_closed")) end
      busy="identifiers"
      prepare(activeProfile,function(result,err)
         if not result then
            retryAt=now()+(err and err.temporary and retryFirst or 21600)
            scheduleTimer()
            return leave(done,nil,err)
         end
         installProfile(activeProfile,function(ok,e)
            scheduleTimer()
            leave(done,ok and result or nil,e)
         end)
      end)
   end

   function manager:updateIdentifiers(ids,cb)
      if closed or not activeProfile then return reject(cb,"manager_not_started") end
      config.identifiers=copy(ids)
      pendingUpdates[#pendingUpdates+1]=cb or function() end
      drainUpdates()
      return true
   end

   function manager:prepareAccount(service,cb)
      run(function()
         local ready,err=ensureDirectories()
         if not ready then return safeCallback(cb,nil,err) end
         local resolved,e=resolveService(service)
         if not resolved then return safeCallback(cb,nil,e) end
         local profile,err=loadProfile(resolved)
         if not profile then return safeCallback(cb,nil,err) end
         local function prepare(saved,err)
            if err then return safeCallback(cb,nil,err) end
            if not profile.account.key and saved then profile.account.key=copy(saved.key) end
            if not profile.account.key then
               profile.account.key,err=engine:createKey("account-"..ba.b64urlencode(ba.rndbs(18)),{type="ecc",curve="SECP256R1"})
               if not profile.account.key then return safeCallback(cb,nil,err) end
            end
            local thumb,err=engine:prepareAccount(profile.account)
            if not thumb then return safeCallback(cb,nil,err) end
            local function finish(ok,e)
               if ok then ok,e=saveProfile(profile) end
               safeCallback(cb,ok and {directoryUrl=resolved.directoryUrl,keyThumbprint=thumb} or nil,e)
            end
            if options.accountStore then options.accountStore(resolved.serviceId,{key=profile.account.key},finish)
            else finish(true) end
         end
         if options.accountStore then options.accountStore(resolved.serviceId,nil,prepare) else prepare() end
      end)
      return true
   end

   function manager:configure(value)
      if closed then return nil,errorTable("manager_closed") end
      local validated,problem=validateConfig(value)
      if not validated then return nil,problem end
      config=validated
      return true
   end

   function manager:load(callback)
      if loaded then
         if activeProfile then return installProfile(activeProfile,callback) end
         return safeCallback(callback,true)
      end
      run(function()
         local ready,problem=ensureDirectories()
         if not ready then return safeCallback(callback,nil,problem) end
         local active,exists=readJson(activePath)
         if not active then
            if exists then return reject(callback,"invalid_saved_state") end
            loaded=true
            return safeCallback(callback,true)
         end
         if active.version ~= 2 or type(active.directoryUrl) ~= "string" or type(active.serviceId) ~= "string" then
            return reject(callback,"invalid_saved_state")
         end
         local profile
         profile,problem=loadProfile{directoryUrl=active.directoryUrl,serviceId=active.serviceId}
         if not profile then return safeCallback(callback,nil,problem) end
         activeProfile,loaded=profile,true
         installProfile(profile,callback)
      end)
      return true
   end

   function manager:switchService(service,switchOptions,callback)
      if not config then return reject(callback,"not_configured") end
      local resolved,problem=resolveService(service)
      if not resolved then return safeCallback(callback,nil,problem) end
      if activeProfile and activeProfile.directoryUrl == resolved.directoryUrl then
         config.service=resolved
         safeCallback(callback,{changed=false,reused=true})
         return true
      end
      if not switchOptions or switchOptions.rebuild ~= true then
         return reject(callback,"directory_change_requires_rebuild")
      end
      if not enter("switchService",callback) then return end
      local previous=config.service
      config.service=resolved
      local profile
      profile,problem=loadProfile(resolved)
      if not profile then config.service=previous return leave(callback,nil,problem) end
      if not config.service.sharkca and profile.account.email ~= config.email then profile.account={email=config.email} end
      prepare(profile,function(result,prepareProblem)
         if not result then config.service=previous return leave(callback,nil,prepareProblem) end
         commit(profile,function(committed,commitProblem)
            if not committed then config.service=previous return leave(callback,nil,commitProblem) end
            scheduleTimer()
            leave(callback,{changed=true,reused=result.reused,rebuilt=result.rebuilt})
         end)
      end)
      return true
   end

   function manager:start(callback)
      if closed then return reject(callback,"manager_closed") end
      if not config then return reject(callback,"not_configured") end
      if started then safeCallback(callback,{started=false}) return true end
      local startedAt=stopCount
      local function begin()
         if closed then return reject(callback,"manager_closed") end
         if startedAt ~= stopCount then return reject(callback,"manager_stopped") end
         started=true
         if not activeProfile or activeProfile.directoryUrl ~= config.service.directoryUrl then
            return self:switchService(config.service,{rebuild=true},function(result,problem)
               if problem then started=false return safeCallback(callback,nil,problem) end
               scheduleTimer()
               safeCallback(callback,{started=true,switch=result})
            end)
         end
         if not enter("start",callback) then started=false return end
         prepare(activeProfile,function(result,problem)
            if not result then started=false return leave(callback,nil,problem) end
            installProfile(activeProfile,function(ok,installProblem)
               if not ok then started=false return leave(callback,nil,installProblem) end
               scheduleTimer()
               result.started=true
               leave(callback,result)
            end)
         end)
      end
      if loaded then begin() else self:load(function(_,problem)
         if problem then safeCallback(callback,nil,problem) else begin() end
      end) end
      return true
   end

   function manager:stop(callback)
      stopCount=stopCount+1
      started=false
      cancelTimer()
      safeCallback(callback,true)
      return true
   end

   function manager:renew(domain,renewOptions,callback)
      if not activeProfile or not activeProfile.certificates[domain] then return reject(callback,"certificate_not_found") end
      if not enter("renew",callback) then return end
      issue(activeProfile,domain,renewOptions and renewOptions.force == true,function(record,problem)
         if not record then return leave(callback,nil,problem) end
         installProfile(activeProfile,function(ok,installProblem)
            scheduleTimer()
            leave(callback,ok and copy(record) or nil,installProblem)
         end)
      end)
      return true
   end

   function manager:revoke(domain,revokeOptions,callback)
      local record=activeProfile and activeProfile.certificates[domain]
      if not record then return reject(callback,"certificate_not_found") end
      if not enter("revoke",callback) then return end
      engine:revoke(config.service,activeProfile.account,record.certificate,revokeOptions or {},function(result,problem)
         if not result then return leave(callback,nil,problem) end
         activeProfile.certificates[domain]=nil
         local ok,saveProblem=saveProfile(activeProfile)
         if not ok then return leave(callback,nil,saveProblem) end
         emit(42)
         installProfile(activeProfile,function(installed,installProblem)
            scheduleTimer()
            leave(callback,installed,installProblem)
         end)
      end)
      return true
   end

   function manager:status()
      local domains={}
      for domain,record in pairs(activeProfile and activeProfile.certificates or {}) do
         domains[domain]={expiresAt=record.expiresAt,renewAt=record.renewAt,ariCheckAt=record.ariCheckAt,
            ariId=record.ariId,explanationUrl=record.explanationUrl}
      end
      return {loaded=loaded,started=started,closed=closed,operation=busy,
         directoryUrl=activeProfile and activeProfile.directoryUrl,domains=domains,
         jobs=engine:jobs(),lastError=copy(lastError),retryAt=retryAt}
   end
   function manager:domains() return copy(activeProfile and activeProfile.certificates or {}) end
   function manager:certificate(domain) return copy(activeProfile and activeProfile.certificates[domain]) end
   function manager:account() return copy(activeProfile and activeProfile.account) end
   function manager:close(callback)
      if closed then return safeCallback(callback,true) end
      if installing > 0 then return nil,"busy" end
      closed,started=true,false
      cancelTimer()
      drainUpdates()
      engine:close(function(_,problem) safeCallback(callback,not problem or nil,problem) end)
      return true
   end
   return manager
end


function M.create(options)
   if type(options) ~= "table" or type(options.config) ~= "table" then
      return nil,problem"invalid_options"
   end
   local fileIo=options.io
   if not fileIo and ba and ba.openio and (mako or xedge) then
      fileIo=ba.openio(mako and "home" or "disk")
   end
   if not fileIo then return nil,problem"invalid_io" end
   local install=options.install
   if install == nil and (mako or xedge) and ba and (ba.slcon or ba.slcon6) then
      install=require"acme/_server"(options.tpm)
   end
   if type(install) ~= "function" then return nil,problem"invalid_installer" end
   local config=options.config
   local private=config.sharkca
   if private then
      if type(private)~="table" or config.challenge or config.keyType and config.keyType~="ecc" or
         type(config.domains)~="table" or #config.domains>1 or
         config.domains[1]~=nil and (type(config.domains[1])~="string" or config.domains[1]=="") then
         return nil,problem"invalid_sharkca_configuration"
      end
   elseif config.acceptTerms ~= true then return nil,problem"terms_not_accepted" end
   local dnsConfig=private or config.challenge or {}
   local registration={name=config.domains[1],namePolicy=config.namePolicy or "increment",
      dns=dnsConfig.dns,info=config.info}
   local service={production=config.production ~= false,productionUrl=config.productionUrl,
      stagingUrl=config.stagingUrl,http=options.http}
   local key={type=config.keyType or "ecc",bits=config.bits,curve=config.curve}
   local reverse=not private and dnsConfig.reverse == true
   local notify=options.notify
   local deps=options.dependencies or {}
   local timerFactory=deps.timer or function(action) return ba.timer(action) end
   local retryFirst,retryMax=deps.retryDelay or 30000,deps.retryMaxDelay or 300000
   local engine,err=require"acme/engine".create{tpm=options.tpm,dependencies=options.engineDependencies}
   if not engine then return nil,err end
   local challenge,st,store
   local function fail(problem)
      if challenge and challenge.close then challenge:close() elseif st then st:close() end
      engine:close()
      return nil,problem
   end
   if private or dnsConfig.type == "dns-01" and dnsConfig.mode ~= "manual" then
      local Dns=require"acme/dns"
      if private and not dnsConfig.zoneKey and not dnsConfig.proof then
         local embedded,e=Dns.identity()
         if not embedded then return fail(e) end
         dnsConfig=copy(embedded) dnsConfig.portalUrl=private.portalUrl or embedded.portalUrl
      end
      st,err=Dns.createClient{portalUrl=dnsConfig.portalUrl,zoneKey=dnsConfig.zoneKey,
         proof=dnsConfig.proof,http=options.http,profile=private and "sharkca-v1" or nil}
      if not st then return fail(err) end
      if private then
         service={production=true,productionUrl=st:identity().portalUrl:gsub("/sharktrust%.lsp$","/acme/directory"),
            sharkca=true,http=options.http}
      end
      store=registrationStore(options.store or fileStore(fileIo,options.path or "acme"))
      challenge,err=Dns.createSharkTrust{client=st,store=store,
         propagationDelay=dnsConfig.propagationDelay,notify=options.notify,dependencies=options.dnsDependencies}
      if not challenge then return fail(err) end
   elseif dnsConfig.type == "dns-01" and dnsConfig.mode == "manual" then
      challenge=require"acme/dns".createManual{notify=options.notify}
   else
      challenge=options.challenge
   end
   local manager
   manager,err=M.createManager{io=fileIo,engine=engine,install=install,
      notify=options.notify,renewAllowed=options.renewAllowed,path=options.path,accountStore=store and store.account}
   if not manager then return fail(err) end
   local runtime,started,closed,starting,retryTimer,retryDelay=
      {challenge=challenge},false,false,false,nil,retryFirst
   local startAttempt
   local lastStartError

   local function emit(...) safeCallback(notify,...) end
   local function retryable(problem)
      return problem and problem.temporary == true and problem.retryable ~= false
   end
   local function cancelRetry()
      if retryTimer then retryTimer:cancel() retryTimer=nil end
   end
   local function scheduleRetry(err)
      if retryTimer or closed or started then return end
      -- Error classification selects the delay, never whether an enabled runtime survives.
      local delay=retryable(err) and retryDelay or 3600000
      if err and err.code == "name_unavailable" then delay=3600000 end
      if delay ~= 3600000 then retryDelay=math.min(retryDelay*2,retryMax) end
      retryTimer=timerFactory(function()
         retryTimer=nil
         if not closed and not started then startAttempt() end
         return false
      end)
      retryTimer:set(delay,true)
      emit(4)
   end

   local function managerConfig(domain,ids)
      local domains=domain and {domain} or config.domains
      return manager:configure{email=not private and config.email or nil,domains=private and {"$device"} or domains,
         identifiers=ids,acceptTerms=not private and config.acceptTerms or nil,
         challenge=challenge,service=service,key=key,cleanup=config.cleanup ~= false,
         timeout=config.timeout,dnsResolveTimeout=config.dnsResolveTimeout,
         fallbackRenewBefore=config.fallbackRenewBefore}
   end
   local function activateReverse()
      if st then
         local enable=reverse
         local ok,err=st:reverseConnection(enable)
         if ok then emit(enable and 20 or 21) end
         return ok,err
      end
      return true
   end
   local function runManager(domain,cb,warning)
      manager:start(function(value,startErr)
         if not startErr then
            started=true
            emit(2)
         end
         if warning and value then value.warning=warning end
         callback(cb,value,startErr)
      end)
   end
   local function startManager(domain,cb)
      local ok,err=managerConfig(domain)
      if not ok then return callback(cb,nil,err) end
      manager:load(function(_,loadErr)
         if loadErr then return callback(cb,nil,loadErr) end
         runManager(domain,cb)
      end)
   end
   local function enroll(cb)
      emit(10)
      challenge:enroll(registration,function(state,enrollErr)
         if not state then return callback(cb,nil,enrollErr) end
         emit(11)
         emit(13,state.name)
         local ok,reverseErr=activateReverse()
         if not ok then return callback(cb,nil,reverseErr) end
         startManager(state.name,cb)
      end)
   end

   local function startRegistered(done)
      challenge:load(function(saved,loadErr)
         if loadErr and loadErr.code == "sharktrust_identity_mismatch" then return enroll(done) end
         if loadErr then return done(nil,loadErr) end
         if not saved or saved.pending then return enroll(done) end
         emit(12)
         local ok,err=managerConfig(saved.name)
         if not ok then return done(nil,err) end
         manager:load(function(_,managerErr)
            if managerErr then return done(nil,managerErr) end
            local reverseOK,reverseErr=activateReverse()
            if not reverseOK then return done(nil,reverseErr) end
            challenge:resume(function(result,resumeErr)
               if not result and resumeErr and (resumeErr.status == 401 or resumeErr.code == "not_enrolled" or
                  resumeErr.code == "device_not_found") then return enroll(done) end
               if not result and retryable(resumeErr) then return done(nil,resumeErr) end
               local name=result and result.name or saved.name
               if result then emit(13,name) end
               managerConfig(name)
               runManager(name,done,resumeErr)
            end)
         end)
      end)
   end

   startAttempt=function(cb)
      local function done(value,err)
         starting=false
         lastStartError=err
         if err then emit(3,err.code) end
         if err then scheduleRetry(err)
         else cancelRetry() retryDelay=retryFirst end
         callback(cb,value,err)
      end
      if closed then return done(nil,problem"runtime_closed") end
      if started then done{started=false} return true end
      if starting then return callback(cb,nil,problem"operation_in_progress") end
      starting=true
      emit(1)
      if st then
         if not private then
            local ok,err=managerConfig()
            if not ok then return done(nil,err) end
         end
         manager:prepareAccount(service,function(account,e)
            if not account then return done(nil,e) end
            if not private then return startRegistered(done) end
            st:bindAccount(account,function(ok,err)
               if not ok then return done(nil,err) end
               local function ready(state,e)
                  if not state then return done(nil,e) end
                  emit(13,state.name or state.certificateIdentifiers[1].value)
                  local ok,err=managerConfig(state.name,state.certificateIdentifiers)
                  if not ok then return done(nil,err) end
                  manager:load(function(_,e)
                     if e then return done(nil,e) end
                     runManager(state.name,done)
                  end)
               end
               local function register()
                  emit(10)
                  challenge:enroll(registration,function(state,e)
                     if state then emit(11) end
                     ready(state,e)
                  end)
               end
               challenge:load(function(saved,e)
                  if e and e.code~="sharktrust_identity_mismatch" then return done(nil,e) end
                  if not saved or saved.pending then return register() end
                  emit(12)
                  challenge:resume(function(state,e)
                     if e and (e.status==401 or e.code=="device_not_found") then return register() end
                     ready(state,e)
                  end)
               end)
            end)
         end)
         return true
      end
      startManager(nil,done)
      return true
   end
   function runtime:start(cb)
      cancelRetry()
      retryDelay=retryFirst
      return startAttempt(cb)
   end

   local function noSharkTrust(cb) return callback(cb,nil,problem"sharktrust_not_configured") end
   function runtime:isRegistered(cb)
      if not st then return noSharkTrust(cb) end
      if private then return challenge:resume(function(result,err)
         if not result then return callback(cb,nil,err) end
         manager:updateIdentifiers(result.certificateIdentifiers,function(ok,e) callback(cb,ok and result or nil,e) end)
      end) end
      return challenge:isRegistered(cb)
   end
   function runtime:isAvailable(name,cb)
      if not st then return noSharkTrust(cb) end
      return challenge:isAvailable(name,cb)
   end
   function runtime:setIpAddress(ipAddress,cb)
      if not st then return noSharkTrust(cb) end
      if private then
         if not started then return reject(cb,"runtime_not_started") end
         return challenge:setIpAddress(ipAddress,function(result,err)
            if not result then return callback(cb,nil,err) end
            manager:updateIdentifiers(result.certificateIdentifiers,function(ok,e) callback(cb,ok and result or nil,e) end)
         end)
      end
      return challenge:setIpAddress(ipAddress,cb)
   end
   function runtime:reverseConnection(enable)
      if private then return nil,problem"sharkca_reverse_unavailable" end
      if not st then return nil,problem"sharktrust_not_configured" end
      reverse=enable and true or false
      return st:reverseConnection(enable)
   end
   function runtime:switchService(service,cb)
      if private then return reject(cb,"sharkca_reconfigure_required") end
      if st then return manager:prepareAccount(service,function(_,err)
         if err then return callback(cb,nil,err) end
         manager:switchService(service,{rebuild=true},cb)
      end) end
      return manager:switchService(service,{rebuild=true},cb)
   end
   function runtime:renew(domain,cb) return manager:renew(private and "$device" or domain,{force=true},cb) end
   function runtime:status()
      local value=manager:status()
      value.lastError=copy(lastStartError or value.lastError)
      value.registration=challenge and challenge.status and challenge:status() or nil
      value.reverse=st and st:reverseStatus() or {enabled=false,connected=false,status=0,connections=0}
      value.starting,value.retryPending=starting,retryTimer ~= nil
      return value
   end
   function runtime:close(cb)
      if closed then callback(cb,true) return true end
      if st and challenge:status().busy then return nil,"busy" end
      local wasStarted=started
      closed,started=true,false
      local _,err=manager:close(function(_,managerErr)
         if challenge and challenge.close then
            challenge:close(function(_,challengeErr) callback(cb,not (managerErr or challengeErr) or nil,managerErr or challengeErr) end)
         else callback(cb,not managerErr or nil,managerErr) end
      end)
      if err == "busy" then closed,started=false,wasStarted return nil,err end
      cancelRetry()
      return true
   end
   return runtime
end

return M
