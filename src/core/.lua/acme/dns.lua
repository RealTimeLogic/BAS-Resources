local M={}
local errorTable,copy,safeCallback,isHex,_,_,reject,ipv4=require"acme/_util"()

local function validClient(client)
   if type(client) ~= "table" then return false end
   for _,name in ipairs{"enroll","isAvailable","isRegistered","setIpAddress","setAcmeRecord",
      "removeAcmeRecord","getWan","rotateCredential","setCredential","credential","identity","close"} do
      if type(client[name]) ~= "function" then return false end
   end
   return true
end

local function validState(state,identity)
   if type(state) ~= "table" or state.version ~= 2 then return nil,errorTable("invalid_saved_state") end
   if state.portalUrl ~= identity.portalUrl or state.zoneIdentity ~= identity.zoneIdentity then
      return nil,errorTable("sharktrust_identity_mismatch")
   end
   if type(state.deviceId) ~= "string" or state.deviceId == "" or type(state.name) ~= "string" or
      state.name == "" or not isHex(state.credential,64) then return nil,errorTable("invalid_saved_state") end
   state=copy(state)
   state.credential=state.credential:lower()
   return state
end

function M.isPrivateIp(address)
   local first,second=ipv4(address)
   return first == 10 or first == 172 and second >= 16 and second <= 31 or
      first == 192 and second == 168 or false
end

function M.createSharkTrust(options)
   if type(options) ~= "table" or not validClient(options.client) then return nil,errorTable("invalid_sharktrust_client") end
   local store=options.store
   if type(store) ~= "table" or type(store.load) ~= "function" or type(store.save) ~= "function" then
      return nil,errorTable("invalid_store")
   end
   local client,notify,address=options.client,type(options.notify) == "function" and options.notify or function() end,
      type(options.address) == "function" and options.address or nil
   local deps=options.dependencies or {}
   local timerFactory,now=deps.timer or function(action) return ba.timer(action) end,deps.now or os.time
   local delay=tonumber(options.propagationDelay) or 30
   if delay < 0 then return nil,errorTable("invalid_propagation_delay") end
   local identity,adapter=client:identity(),{type="dns-01"}
   local saveQueue,loadWaiters={},{ }
   local state,pendingState,busy,challenge
   local saving,loaded,loading,closed=false,false,false,false

   local function emit(event) safeCallback(notify,copy(event)) end
   local function finishLoad(result,problem)
      loading=false
      local waiters=loadWaiters
      loadWaiters={}
      for _,callback in ipairs(waiters) do safeCallback(callback,result,problem) end
   end
   local function loadState(callback)
      if closed then return reject(callback,"adapter_closed") end
      if loaded then return safeCallback(callback,state) end
      loadWaiters[#loadWaiters+1]=callback
      if loading then return end
      loading=true
      local called=false
      local function done(saved,problem)
         if called then return end
         called=true
         if problem then return finishLoad(nil,errorTable("storage_read_failed",
            type(problem) == "table" and problem.message or tostring(problem),{temporary=true})) end
         if saved ~= nil then
            saved,problem=validState(saved,identity)
            if not saved then return finishLoad(nil,problem) end
         end
         local ok,setProblem=client:setCredential(saved and saved.credential)
         if not ok then return finishLoad(nil,setProblem) end
         state,loaded=saved,true
         finishLoad(state)
      end
      local ok,message=pcall(store.load,done)
      if not ok then done(nil,message) end
   end

   local saveNext
   saveNext=function()
      if saving or not saveQueue[1] then return end
      local item=table.remove(saveQueue,1)
      saving=true
      local called=false
      local function done(ok,problem)
         if called then return end
         called,saving=true,false
         if ok then
            state,pendingState,loaded=item.state,nil,true
            client:setCredential(state.credential)
            safeCallback(item.callback,state)
         else
            pendingState=item.state
            safeCallback(item.callback,nil,errorTable("storage_write_failed",
               type(problem) == "table" and problem.message or tostring(problem),{temporary=true}))
         end
         saveNext()
      end
      local ok,message=pcall(store.save,copy(item.state),done)
      if not ok then done(nil,message) end
   end
   local function saveState(value,callback)
      saveQueue[#saveQueue+1]={state=copy(value),callback=callback}
      saveNext()
   end
   local function makeState(result,newIdentity)
      return {version=2,portalUrl=newIdentity.portalUrl,zoneIdentity=newIdentity.zoneIdentity,
         deviceId=result.deviceId,name=result.name,credential=result.credential:lower(),updatedAt=now()}
   end
   local function enter(name,callback)
      if closed then return reject(callback,"adapter_closed") end
      if busy then return reject(callback,"operation_in_progress",nil,{temporary=true}) end
      busy=name
      return true
   end
   local function leave(callback,result,problem) busy=nil safeCallback(callback,result,problem) end
   local function withState(callback,action)
      loadState(function(saved,problem)
         if problem then return safeCallback(callback,nil,problem) end
         if not saved then return reject(callback,"not_enrolled") end
         action(saved)
      end)
   end
   local function updateAddress(result,callback)
      if not address then return safeCallback(callback,copy(result)) end
      address(function(request,problem)
         if problem or not request then return safeCallback(callback,nil,problem or errorTable("address_unavailable")) end
         client:setIpAddress(request,callback)
      end)
   end

   function adapter:enroll(request,callback)
      if type(callback) ~= "function" then return reject(callback,"invalid_callback") end
      if not enter("enroll",callback) then return end
      local oldCredential=client:credential()
      client:enroll(request,function(result,problem)
         if not result then return leave(callback,nil,problem) end
         saveState(makeState(result,identity),function(saved,saveProblem)
            if not saved then client:setCredential(oldCredential) end
            leave(callback,saved and copy(saved),saveProblem)
         end)
      end)
      return true
   end

   function adapter:isAvailable(name,callback) return client:isAvailable(name,callback) end

   function adapter:load(callback)
      if type(callback) ~= "function" then return reject(callback,"invalid_callback") end
      loadState(function(saved,problem) safeCallback(callback,saved and copy(saved),problem) end)
      return true
   end

   function adapter:resume(callback)
      if type(callback) ~= "function" then return reject(callback,"invalid_callback") end
      if pendingState then return saveState(pendingState,function(saved,problem)
         if saved then self:resume(callback) else safeCallback(callback,nil,problem) end
      end) end
      withState(callback,function(saved)
         client:isRegistered(function(result,problem)
            if not result then return safeCallback(callback,nil,problem) end
            if result.name and result.name ~= saved.name then
               saved=copy(saved)
               saved.name,saved.updatedAt=result.name,now()
               return saveState(saved,function(stored,saveProblem)
                  if stored then updateAddress(result,callback) else safeCallback(callback,nil,saveProblem) end
               end)
            end
            updateAddress(result,callback)
         end)
      end)
      return true
   end

   local function deviceCall(method,request,callback)
      if type(callback) ~= "function" then return reject(callback,"invalid_callback") end
      withState(callback,function() client[method](client,request or callback,request and callback or nil) end)
      return true
   end
   function adapter:isRegistered(callback) return deviceCall("isRegistered",nil,callback) end
   function adapter:setIpAddress(request,callback) return deviceCall("setIpAddress",request,callback) end
   function adapter:getWan(callback) return deviceCall("getWan",nil,callback) end

   function adapter:rotateCredential(callback)
      if type(callback) ~= "function" then return reject(callback,"invalid_callback") end
      if not enter("rotateCredential",callback) then return end
      withState(function(_,problem) if problem then leave(callback,nil,problem) end end,function(saved)
         client:rotateCredential(function(newCredential,stored)
            local candidate=copy(saved)
            candidate.credential,candidate.updatedAt=newCredential,now()
            saveState(candidate,function(value,saveProblem) stored(value and true or nil,saveProblem) end)
         end,function(result,problem) leave(callback,result and copy(state),problem) end)
      end)
      return true
   end

   function adapter:switchIdentity(value,switchOptions,callback)
      if type(callback) ~= "function" then return reject(callback,"invalid_callback") end
      local newClient=type(value) == "table" and value.client
      if not validClient(newClient) then return reject(callback,"invalid_sharktrust_client") end
      local newIdentity=newClient:identity()
      if newIdentity.portalUrl == identity.portalUrl and newIdentity.zoneIdentity == identity.zoneIdentity then
         local oldClient=client
         client=newClient
         if state then client:setCredential(state.credential) end
         if oldClient ~= newClient then oldClient:close() end
         safeCallback(callback,{changed=false})
         return true
      end
      if not switchOptions or switchOptions.reenroll ~= true then
         return reject(callback,"sharktrust_identity_change_requires_reenrollment")
      end
      if type(switchOptions.enrollment) ~= "table" then return reject(callback,"invalid_request") end
      if not enter("switchIdentity",callback) then return end
      local oldClient=client
      newClient:enroll(switchOptions.enrollment,function(result,problem)
         if not result then newClient:close() return leave(callback,nil,problem) end
         local candidate=makeState(result,newIdentity)
         client=newClient
         saveState(candidate,function(saved,saveProblem)
            if not saved then
               pendingState,client=nil,oldClient
               newClient:setCredential(nil)
               newClient:close()
               return leave(callback,nil,saveProblem)
            end
            identity=newIdentity
            oldClient:close()
            leave(callback,{changed=true,state=copy(saved)})
         end)
      end)
      return true
   end

   function adapter:present(context,callback)
      if type(callback) ~= "function" then return reject(callback,"invalid_callback") end
      if challenge then return reject(callback,"challenge_in_progress") end
      context=type(context) == "table" and context or {}
      local request={recordName=context.recordName,recordData=context.recordData,
         dnsResolveTimeoutMs=context.dnsResolveTimeoutMs or math.max(1000,math.floor(delay*1000))}
      withState(callback,function()
         challenge={context=copy(context),callback=callback,ready=false}
         client:setAcmeRecord(request,function(result,problem)
            if not challenge then return end
            if not result then challenge=nil return safeCallback(callback,nil,problem) end
            emit{type="dnsChallenge",phase="propagating",recordName=request.recordName}
            if delay == 0 then challenge.ready,challenge.callback=true,nil return safeCallback(callback,true) end
            challenge.timer=timerFactory(function()
               if not challenge then return false end
               challenge.ready,challenge.callback=true,nil
               safeCallback(callback,true)
               return false
            end)
            challenge.timer:set(math.floor(delay*1000),true)
         end)
      end)
      return true
   end

   function adapter:cleanup(context,callback)
      if type(callback) ~= "function" then return reject(callback,"invalid_callback") end
      local active=challenge
      challenge=nil
      if active and active.timer then active.timer:cancel() end
      if active and active.callback then safeCallback(active.callback,nil,errorTable("challenge_cancelled")) end
      if not state then return safeCallback(callback,true) end
      client:removeAcmeRecord(function(result,problem)
         emit{type="dnsChallenge",phase="removed",recordName=context and context.recordName}
         safeCallback(callback,result or not problem,problem)
      end)
      return true
   end

   function adapter:status()
      return {type="sharktrust",loaded=loaded,enrolled=state ~= nil,name=state and state.name,
         deviceId=state and state.deviceId,portalUrl=identity.portalUrl,operation=busy,
         challenge=challenge and {recordName=challenge.context.recordName,ready=challenge.ready},
         pendingSave=pendingState ~= nil}
   end
   function adapter:close(callback)
      if closed then return safeCallback(callback,true) end
      closed=true
      local active=challenge
      challenge=nil
      if active and active.timer then active.timer:cancel() end
      if active and active.callback then safeCallback(active.callback,nil,errorTable("adapter_closed")) end
      local function done() client:close(function(_,problem) safeCallback(callback,not problem,problem) end) end
      if state and active then client:removeAcmeRecord(done) else done() end
      return true
   end
   return adapter
end

function M.createManual(options) return require"acme/dnsmanual"(options) end
return M
