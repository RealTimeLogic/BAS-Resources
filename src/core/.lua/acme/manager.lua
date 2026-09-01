local M={}
local errorTable,copy,safeCallback,_,_,resolveService,reject=require"acme/_util"()

local function certificateExpiry(pem)
   local body=type(pem) == "string" and pem:match("%-%-%-%-%-BEGIN CERTIFICATE%-%-%-%-%-%s*(.-)%s*%-%-%-%-%-END CERTIFICATE%-%-%-%-%-")
   if not body then return end
   local ok,info=pcall(ba.parsecert,ba.b64decode((body:gsub("%s",""))))
   local expires=ok and info and ba.parsecerttime(info.tzto)
   return expires and expires ~= 0 and expires or nil
end

local function validateEngine(engine)
   if type(engine) ~= "table" then return false end
   for _,name in ipairs{"certificate","renewalInfo","revoke","jobs","close"} do
      if type(engine[name]) ~= "function" then return false end
   end
   return true
end

local function validateConfig(config)
   if type(config) ~= "table" or type(config.email) ~= "string" or config.email == "" or
      type(config.domains) ~= "table" or type(config.domains[1]) ~= "string" then
      return nil,errorTable("invalid_configuration")
   end
   if config.acceptTerms ~= true then return nil,errorTable("terms_not_accepted") end
   local challenge=config.challenge
   if challenge ~= nil and (type(challenge) ~= "table" or type(challenge.present) ~= "function" or
      type(challenge.cleanup) ~= "function") then return nil,errorTable("invalid_configuration") end
   local service,problem=resolveService(config.service)
   if not service then return nil,problem end
   local result,seen=copy(config),{}
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

function M.create(options)
   if type(options) ~= "table" or not validateEngine(options.engine) then return nil,errorTable("invalid_engine") end
   if type(options.install) ~= "function" then return nil,errorTable("invalid_installer") end
   if not options.io then return nil,errorTable("invalid_io") end

   local fileIo,engine,install=options.io,options.engine,options.install
   local notify=type(options.notify) == "function" and options.notify or function() end
   local renewAllowed=type(options.renewAllowed) == "function" and options.renewAllowed or function() return true end
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

   local function emit(event) safeCallback(notify,copy(event)) end
   local function ensureDirectories()
      if not fileIo:stat(basePath) and not fileIo:mkdir(basePath) or
         not fileIo:stat(servicesPath) and not fileIo:mkdir(servicesPath) then
         return nil,errorTable("storage_write_failed")
      end
      return true
   end

   local function readJson(path)
      local function read(name)
         local handle=fileIo:open(name,"r")
         if not handle then return end
         local raw=handle:read"a"
         handle:close()
         local ok,value=pcall(ba.json.decode,raw or "")
         return ok and type(value) == "table" and value or nil
      end
      local exists=fileIo:stat(path) or fileIo:stat(path..".bak")
      return read(path) or read(path..".bak"),exists
   end

   local function writeJson(path,value)
      local raw=ba.json.encode(value)
      local temp,backup=path..".tmp",path..".bak"
      local handle,message=fileIo:open(temp,"w")
      if not handle then return nil,errorTable("storage_write_failed",tostring(message)) end
      local wrote
      wrote,message=handle:write(raw)
      handle:flush()
      handle:close()
      if wrote == nil then fileIo:remove(temp) return nil,errorTable("storage_write_failed",tostring(message)) end
      if fileIo:stat(backup) then fileIo:remove(backup) end
      if fileIo:stat(path) and not fileIo:rename(path,backup) then
         fileIo:remove(temp)
         return nil,errorTable("storage_write_failed")
      end
      if not fileIo:rename(temp,path) then
         if fileIo:stat(backup) then fileIo:rename(backup,path) end
         return nil,errorTable("storage_write_failed")
      end
      if fileIo:stat(backup) then fileIo:remove(backup) end
      return true
   end

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
         account={email=config and config.email or ""},certificates={},updatedAt=now()}
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
      local called=false
      local function done(ok,message)
         if called then return end
         called=true
         if ok then safeCallback(callback,true) else
            safeCallback(callback,nil,errorTable("certificate_install_failed",
               type(message) == "table" and message.message or tostring(message)))
         end
      end
      local ok,message=pcall(install,certificateList(profile),done)
      if not ok then done(nil,message) end
   end

   local function fallbackRenewal(record)
      local expires=record.expiresAt or certificateExpiry(record.certificate)
      record.expiresAt=expires
      if not expires then record.renewAt,record.ariCheckAt=now(),nil return end
      local jitter=math.floor((random()-.5)*math.min(86400,config.fallbackRenewBefore/4))
      record.renewAt,record.ariCheckAt=math.max(now(),expires-config.fallbackRenewBefore+jitter),nil
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
      if not force and old and old.expiresAt and old.expiresAt > now() and old.renewAt and old.renewAt > now() then
         return safeCallback(callback,old)
      end
      if profile.account.email ~= config.email then profile.account={email=config.email} end
      local key=copy(config.key or {})
      if old and old.privateKey then key.privateKey=old.privateKey end
      engine:certificate(config.service,profile.account,{domain=domain,acceptTerms=config.acceptTerms,
         challenge=config.challenge,key=key,timeout=config.timeout,dnsResolveTimeout=config.dnsResolveTimeout,
         replaces=old and old.ariId},function(result,problem)
         if not result then return safeCallback(callback,nil,problem) end
         profile.account=copy(result.account)
         local expires=result.expiresAt or certificateExpiry(result.certificate)
         profile.certificates[domain]={domain=domain,privateKey=result.privateKey,certificate=result.certificate,
            expiresAt=expires,ariId=result.ariId,orderUrl=result.orderUrl,
            directoryUrl=result.directoryUrl,issuedAt=now()}
         refreshRenewal(profile,domain,function(_,renewProblem)
            if renewProblem then return safeCallback(callback,nil,renewProblem) end
            emit{type=old and "certificateRenewed" or "certificateIssued",domain=domain,
               directoryUrl=profile.directoryUrl,expiresAt=expires}
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
         if not record or not record.expiresAt or record.expiresAt <= now() then result[#result+1]=domain end
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
         emit{type="serviceChanged",directoryUrl=profile.directoryUrl}
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
      timer:set(math.max(1000,math.floor((nextTime-now())*1000)),true)
   end

   scheduledCheck=function()
      if busy or not started or not activeProfile then return scheduleTimer() end
      busy="scheduledCheck"
      retryAt=nil
      local renew,refresh,current,deferred={},{},now(),false
      for domain,record in pairs(activeProfile.certificates) do
         if record.renewAt and record.renewAt <= current then renew[#renew+1]=domain
         elseif record.ariCheckAt and record.ariCheckAt <= current then refresh[#refresh+1]=domain end
      end
      local function finish(problem)
         busy=nil
         if problem then
            lastError=copy(problem)
            if problem.temporary == true and problem.retryable ~= false then
               retryAt=now()+retryDelay
               retryDelay=math.min(retryDelay*2,retryMax)
            else retryAt=now()+21600 end
         elseif deferred then retryAt=now()+3600
         else retryDelay,retryAt=retryFirst,nil end
         installProfile(activeProfile,function() scheduleTimer() end)
      end
      each(refresh,function(domain,done) refreshRenewal(activeProfile,domain,done) end,function(_,refreshProblem)
         if refreshProblem then return finish(refreshProblem) end
         each(renew,function(domain,done)
            if renewAllowed(domain,copy(activeProfile.certificates[domain])) ~= false then
               issue(activeProfile,domain,true,done)
            else deferred=true done(true) end
         end,function(_,problem)
            finish(problem)
         end)
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

   function manager:configure(value)
      if closed then return nil,errorTable("manager_closed") end
      local validated,problem=validateConfig(value)
      if not validated then return nil,problem end
      config=validated
      return true
   end

   function manager:load(callback)
      if type(callback) ~= "function" then return reject(callback,"invalid_callback") end
      if loaded then return activeProfile and installProfile(activeProfile,callback) or safeCallback(callback,true) end
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
      if type(callback) ~= "function" then return reject(callback,"invalid_callback") end
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
      if profile.account.email ~= config.email then profile.account={email=config.email} end
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
      if type(callback) ~= "function" then return reject(callback,"invalid_callback") end
      if not config then return reject(callback,"not_configured") end
      if started then safeCallback(callback,{started=false}) return true end
      local function begin()
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
      started=false
      cancelTimer()
      safeCallback(callback,true)
      return true
   end

   function manager:renew(domain,renewOptions,callback)
      if type(callback) ~= "function" then return reject(callback,"invalid_callback") end
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
      if type(callback) ~= "function" then return reject(callback,"invalid_callback") end
      local record=activeProfile and activeProfile.certificates[domain]
      if not record then return reject(callback,"certificate_not_found") end
      if not enter("revoke",callback) then return end
      engine:revoke(config.service,activeProfile.account,record.certificate,revokeOptions or {},function(result,problem)
         if not result then return leave(callback,nil,problem) end
         activeProfile.certificates[domain]=nil
         local ok,saveProblem=saveProfile(activeProfile)
         if not ok then return leave(callback,nil,saveProblem) end
         emit{type="certificateRevoked",domain=domain,directoryUrl=activeProfile.directoryUrl}
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
      closed,started=true,false
      cancelTimer()
      engine:close(function(_,problem) safeCallback(callback,not problem,problem) end)
      return true
   end
   return manager
end

return M
