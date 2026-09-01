local M={}
local Engine,Manager,ST,Dns=require"acme/engine",require"acme/manager",require"acme/sharktrust",require"acme/dns"

local function problem(code,message) return {code=code,message=message or code} end
local function callback(cb,value,err) if cb then cb(value,err) end end

function M.create(options)
   if type(options) ~= "table" or not options.io or type(options.install) ~= "function" or
      type(options.config) ~= "table" then return nil,problem"invalid_options" end
   local config,registration=options.config,options.registration
   local notify=type(options.notify) == "function" and options.notify or function() end
   local deps=options.dependencies or {}
   local timerFactory=deps.timer or function(action) return ba.timer(action) end
   local retryFirst,retryMax=deps.retryDelay or 30000,deps.retryMaxDelay or 300000
   local engine=Engine.create{tpm=options.tpm,dependencies=options.engineDependencies}
   local challenge,st
   if options.sharktrust then
      st=assert(ST.create(options.sharktrust))
      challenge=assert(Dns.createSharkTrust{client=st,store=options.store,address=options.address,
         propagationDelay=config.propagationDelay,notify=options.notify,dependencies=options.dnsDependencies})
   elseif config.challenge then
      challenge=config.challenge
   end
   local manager=assert(Manager.create{io=options.io,engine=engine,install=options.install,
      notify=options.notify,renewAllowed=options.renewAllowed,path=options.path})
   local runtime,started,closed,starting,retryTimer,retryDelay=
      {challenge=challenge},false,false,false,nil,retryFirst
   local startAttempt

   local function emit(event) notify(event) end
   local function retryable(problem)
      return problem and problem.temporary == true and problem.retryable ~= false
   end
   local function cancelRetry()
      if retryTimer then retryTimer:cancel() retryTimer=nil end
   end
   local function scheduleRetry()
      if retryTimer or closed or started then return end
      local delay=retryDelay
      retryDelay=math.min(retryDelay*2,retryMax)
      retryTimer=timerFactory(function()
         retryTimer=nil
         if not closed and not started then startAttempt() end
         return false
      end)
      retryTimer:set(delay,true)
      emit{type="runtime",phase="retry",delay=math.floor(delay/1000)}
   end

   local function managerConfig(domain)
      local domains=domain and {domain} or config.domains
      return manager:configure{email=config.email,domains=domains,acceptTerms=config.acceptTerms,
         challenge=challenge,service=config.service,key=config.key,cleanup=config.cleanup,
         timeout=config.timeout,dnsResolveTimeout=config.dnsResolveTimeout,
         fallbackRenewBefore=config.fallbackRenewBefore}
   end
   local function address(next)
      if registration and registration.ipAddress then return next(registration) end
      if type(options.address) ~= "function" then return next(nil,problem"address_unavailable") end
      options.address(function(value,err)
         if not value then return next(nil,err or problem"address_unavailable") end
         local request={}
         for k,v in pairs(registration or {}) do request[k]=v end
         for k,v in pairs(value) do request[k]=v end
         next(request)
      end)
   end
   local function activateReverse()
      if st then
         local enable=options.reverse == true
         local ok,err=st:reverseConnection(enable)
         if ok then emit{type="reverseConnection",phase=enable and "enabled" or "disabled"} end
         return ok,err
      end
      return true
   end
   local function runManager(domain,cb,warning)
      manager:start(function(value,startErr)
         if not startErr then
            started=true
            emit{type="runtime",phase="ready",name=domain or config.domains[1]}
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
      address(function(request,addressErr)
         if not request then return callback(cb,nil,addressErr) end
         emit{type="registration",phase="enrolling",name=request.name}
         challenge:enroll(request,function(state,enrollErr)
            if not state then return callback(cb,nil,enrollErr) end
            emit{type="registration",phase="enrolled",name=state.name}
            local ok,reverseErr=activateReverse()
            if not ok then return callback(cb,nil,reverseErr) end
            startManager(state.name,cb)
         end)
      end)
   end

   startAttempt=function(cb)
      local function done(value,err)
         starting=false
         if err then emit{type="runtime",phase="failed",problem=err.message or err.code or tostring(err)} end
         if err and retryable(err) then scheduleRetry()
         elseif not err then cancelRetry() retryDelay=retryFirst end
         callback(cb,value,err)
      end
      if closed then return done(nil,problem"runtime_closed") end
      if started then done{started=false} return true end
      if starting then return callback(cb,nil,problem"operation_in_progress") end
      starting=true
      emit{type="runtime",phase="starting"}
      if not challenge or not st then startManager(nil,done) return true end
      challenge:load(function(saved,loadErr)
         if loadErr then return done(nil,loadErr) end
         if not saved then return enroll(done) end
         emit{type="registration",phase="restoring",name=saved.name}
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
               if result then emit{type="registration",phase="confirmed",name=name} end
               managerConfig(name)
               runManager(name,done,resumeErr)
            end)
         end)
      end)
      return true
   end
   function runtime:start(cb)
      cancelRetry()
      retryDelay=retryFirst
      return startAttempt(cb)
   end

   function runtime:isRegistered(cb)
      if not challenge or not st then callback(cb,nil,problem"sharktrust_not_configured") return end
      return challenge:isRegistered(cb)
   end
   function runtime:isAvailable(name,cb)
      if not challenge or not st then callback(cb,nil,problem"sharktrust_not_configured") return end
      return challenge:isAvailable(name,cb)
   end
   function runtime:setIpAddress(request,cb) return challenge:setIpAddress(request,cb) end
   function runtime:rotateCredential(cb) return challenge:rotateCredential(cb) end
   function runtime:reverseConnection(enable) options.reverse=enable and true or false return st:reverseConnection(enable) end
   function runtime:switchService(service,cb) return manager:switchService(service,{rebuild=true},cb) end
   function runtime:status()
      local value=manager:status()
      value.registration=challenge and challenge.status and challenge:status() or nil
      value.reverse=st and st:reverseStatus() or {enabled=false,connected=false,status=0,connections=0}
      value.starting,value.retryPending=starting,retryTimer ~= nil
      return value
   end
   function runtime:close(cb)
      if closed then callback(cb,true) return true end
      closed,started=true,false
      cancelRetry()
      manager:close(function(_,managerErr)
         if challenge and challenge.close then
            challenge:close(function(_,challengeErr) callback(cb,not (managerErr or challengeErr),managerErr or challengeErr) end)
         else callback(cb,not managerErr,managerErr) end
      end)
      return true
   end
   return runtime
end

return M
