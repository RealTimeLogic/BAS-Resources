local M={}
local U=require"acme/_util"
local errorTable,copy,safeCallback,isHex,reject=U.err,U.copy,U.callback,U.isHex,U.reject
local ipv4,schedule=U.ipv4,U.schedule
local encode,decode=ba.json.encode,ba.json.decode

local function normalizePortalUrl(value)
   if type(value) ~= "string" or not value:match("^https://") or value:find("[#?%s]") then
      return nil,errorTable("invalid_portal_url") end
   value=value:gsub("/+$","")
   local authority,path=value:match("^(https://[^/]+)(/.*)$")
   if not authority then authority,path=value,"" end
   if path == "" then path="/sharktrust.lsp" end
   if path ~= "/sharktrust.lsp" then return nil,errorTable("invalid_portal_url") end
   return authority..path
end

-- Resolve an explicit or compiled zone identity without opening a connection.
function M.identity(options)
   options=options or {}
   if options.portalUrl ~= nil or options.zoneKey ~= nil or
      options.proof ~= nil then return options end
   local ok,module=pcall(require,"etokengen")
   if not ok then ok,module=pcall(require,"tokengen") end
   if not ok or type(module.proof) ~= "function" then
      return nil,errorTable("sharktrust_not_configured")
   end
   local portal,zoneKey=module.info()
   local value=copy(options)
   value.portalUrl="https://"..portal
   value.zoneKey=(zoneKey:gsub(".",function(c) return string.format("%02x",c:byte()) end))
   value.proof=module.proof
   return value
end

function M.createClient(options)
   local identityErr
   options,identityErr=M.identity(options)
   if not options then return nil,identityErr end
   local portalUrl,urlErr=normalizePortalUrl(options.portalUrl)
   if not portalUrl then return nil,urlErr end
   if not isHex(options.zoneKey,64) then return nil,errorTable("invalid_zone_key") end
   local zoneKey,proof=string.lower(options.zoneKey),options.proof
   if type(proof) ~= "function" then return nil,errorTable("invalid_proof_source") end

   local deps=options.dependencies or {}
   local httpFactory=deps.httpFactory or function(httpOptions)
      return require"httpc".create(httpOptions)
   end
   local reverseFactory=deps.reverse or ba.revcon
   local run=deps.run or function(action) ba.thread.run(action) end
   local jsonEncode,jsonDecode=deps.jsonEncode or encode,deps.jsonDecode or decode
   local httpOptions,reverseOptions=copy(options.http or {}),options.reverse
   local credential
   if options.credential ~= nil then
      if not isHex(options.credential,64) then return nil,errorTable("invalid_device_credential") end
      credential=string.lower(options.credential)
   end

   local identityOK,identityProof=pcall(proof,"SHARKTRUST-IDENTITY\0"..zoneKey)
   if not identityOK or type(identityProof) ~= "string" or #identityProof ~= 32 then
      return nil,errorTable("proof_failed")
   end
   local identity={portalUrl=portalUrl,
      zoneIdentity=ba.b64urlencode(ba.crypto.hash"sha256"(zoneKey)(identityProof)(true,"binary"))}
   identityProof=nil
   local clients,closeCallbacks,client,active,closed={},{},{},0,false
   local reverse,reverseEnabled

   local function networkAddress()
      if type(deps.address) == "function" then return deps.address() end
      local http=httpFactory(copy(httpOptions))
      if not http then return nil,errorTable("http_create_failed",nil,{url=portalUrl}) end
      clients[http]=true
      local ok,message=http:request{trusted=true,url=portalUrl,method="HEAD"}
      local address=ok and http:sockname()
      clients[http]=nil
      http:close()
      if address and address:find("::ffff:",1,true) == 1 then address=address:sub(8) end
      if ipv4(address) then return address end
      message=tostring(message or "Cannot determine the local IPv4 address")
      return nil,errorTable("address_unavailable",message,{cause=message,temporary=true,retryable=true})
   end

   local function stopReverse()
      if reverse then reverse:close() reverse=nil end
   end

   local function startReverse()
      if not isHex(credential,64) then return nil,errorTable("not_enrolled",nil,{status=401}) end
      if not reverseFactory then return nil,errorTable("reverse_connection_unavailable") end
      local ok,signature=pcall(proof,"SHARKTRUST-DEVICE\0"..credential.."\0")
      if not ok or type(signature) ~= "string" or #signature ~= 32 then
         return nil,errorTable("proof_failed")
      end
      local op=copy(reverseOptions or {})
      op.url=portalUrl
      if op.shark == nil and ba.sharkclient then op.shark=ba.sharkclient() end
      stopReverse()
      reverse=reverseFactory(op)
      reverse:token{Authorization="Bearer "..credential,
         ["X-SharkTrust-Proof"]=ba.b64urlencode(signature)}
      return true
   end

   local function restartReverse()
      if reverseEnabled then return startReverse() end
      return true
   end

   local function finishClose()
      if closed and active == 0 then
         local callbacks=closeCallbacks
         closeCallbacks={}
         for _,callback in ipairs(callbacks) do safeCallback(callback,true,nil) end
      end
   end

   local function finish(callback,result,err)
      active=active-1
      safeCallback(callback,result,err)
      finishClose()
   end

   local function post(body,header,context)
      if closed then return nil,errorTable("client_closed") end
      local bodyData=jsonEncode(body)
      if #bodyData > 4096 then
         return nil,errorTable("request_too_large")
      end
      local proofOK,signature=pcall(proof,context..bodyData)
      if not proofOK or type(signature) ~= "string" or #signature ~= 32 then
         return nil,errorTable("proof_failed")
      end
      header["Content-Type"]="application/json"
      header["X-SharkTrust-Proof"]=ba.b64urlencode(signature)
      local response,requestErr=U.http(httpFactory,httpOptions,clients,{
         trusted=true,
         url=portalUrl,
         method="POST",
         size=#bodyData,
         header=header
      },bodyData)
      if not response then return nil,requestErr end
      local status,decodedOK=response.status
      decodedOK,response=pcall(jsonDecode,response.body)
      if not decodedOK or type(response) ~= "table" then
         return nil,errorTable("invalid_response","The SharkTrust response is not valid JSON",{status=status})
      end
      if status and status >= 200 and status < 300 and type(response.result) == "table" then
         return response.result,nil
      end
      local serverError=type(response.error) == "table" and response.error or {}
      local code=serverError.code or "http_error"
      return nil,errorTable(code,
         serverError.message or "SharkTrust HTTP status "..tostring(status),{
            status=status,temporary=status == 429 or (status and status >= 500) or false
         })
   end

   local function begin(callback,action)
      if closed then return reject(callback,"client_closed") end
      active=active+1
      schedule(run,action,function(result,problem) finish(callback,result,problem) end)
      return true
   end

   local function devicePost(command,data,selectedCredential)
      selectedCredential=selectedCredential or credential
      if not isHex(selectedCredential,64) then
         return nil,errorTable("not_enrolled",nil,{status=401})
      end
      selectedCredential=string.lower(selectedCredential)
      local body=copy(data or {})
      body.command=command
      return post(body,{Authorization="Bearer "..selectedCredential},
         "SHARKTRUST-DEVICE\0"..selectedCredential.."\0")
   end

   local function zonePost(body,purpose)
      return post(body,{["X-SharkTrust-Zone-Key"]=zoneKey},purpose..zoneKey.."\0")
   end

   local function enrollmentError(problem)
      if problem and problem.code == "transport_error" and
         (problem.phase == "write" or problem.phase == "read") then
         problem=copy(problem)
         problem.code,problem.message,problem.retryable="enrollment_state_unknown",
            "Enrollment may have been committed",false
      end
      return problem
   end

   function client:isAvailable(name,callback)
      return begin(callback,function()
         local result,requestErr=zonePost({command="IsAvailable",name=name},"SHARKTRUST-AVAILABLE\0")
         if not result then return nil,requestErr end
         if type(result.available) ~= "boolean" or type(result.name) ~= "string" then
            return nil,errorTable("invalid_response")
         end
         return result
      end)
   end

   function client:enroll(request,callback)
      local body={command="Register",name=request.name,namePolicy=request.namePolicy,
         dns=request.dns,info=request.info,credential=request.credential}
      return begin(callback,function()
         local address,addressErr=networkAddress()
         if not address then return nil,addressErr end
         body.ipAddress=address
         local result,requestErr=zonePost(body,"SHARKTRUST-REGISTER\0")
         if not result then
            return nil,request.credential and requestErr or enrollmentError(requestErr)
         end
         if type(result.deviceId) ~= "string" or type(result.name) ~= "string" or
            not isHex(result.credential,64) then
            return nil,errorTable("invalid_response")
         end
         if request.credential and result.credential ~= request.credential then
            return nil,errorTable("enrollment_credential_mismatch")
         end
         credential=string.lower(result.credential)
         restartReverse()
         return result,nil
      end)
   end

   function client:isRegistered(callback)
      return begin(callback,function()
         local result,requestErr=devicePost("IsRegistered")
         if not result then return nil,requestErr end
         local address,addressErr=networkAddress()
         if not address then return nil,addressErr end
         local _,updateErr=devicePost("SetIpAddress",{ipAddress=address})
         if updateErr then return nil,updateErr end
         result.sockname=address -- Local endpoint of the portal connection.
         return result
      end)
   end

   function client:setIpAddress(ipAddress,callback)
      return begin(callback,function() return devicePost("SetIpAddress",{ipAddress=ipAddress}) end)
   end

   function client:setAcmeRecord(request,callback)
      local body={recordName=request.recordName,recordData=request.recordData,
         dnsResolveTimeoutMs=request.dnsResolveTimeoutMs}
      return begin(callback,function() return devicePost("SetAcmeRecord",body) end)
   end

   function client:removeAcmeRecord(callback)
      return begin(callback,function() return devicePost("RemoveAcmeRecord") end)
   end

   function client:getWan(callback)
      return begin(callback,function() return devicePost("GetWan") end)
   end

   function client:reverseConnection(enable)
      if enable == nil then enable=true end
      if closed then return nil,errorTable("client_closed") end
      reverseEnabled=enable
      if not enable then stopReverse() return true end
      return startReverse()
   end

   function client:reverseStatus()
      local status,connections=0,0
      if reverse then status,connections=reverse:status() end
      return {enabled=reverseEnabled == true,connected=status == 202,
         status=status,connections=connections}
   end

   function client:credential() return credential end

   function client:setCredential(value)
      if value == nil then credential=nil stopReverse() return true end
      if not isHex(value,64) then
         return nil,errorTable("invalid_device_credential")
      end
      credential=value:lower()
      restartReverse()
      return true
   end

   function client:identity() return copy(identity) end

   function client:close(callback)
      closed,credential,proof=true,nil,nil
      stopReverse()
      for http in pairs(clients) do http:close() end
      clients={}
      if callback then table.insert(closeCallbacks,callback) end
      finishClose()
      return true
   end

   return client
end


local function validState(state,identity)
   if type(state) ~= "table" or state.version ~= 2 then return nil,errorTable("invalid_saved_state") end
   if state.portalUrl ~= identity.portalUrl or state.zoneIdentity ~= identity.zoneIdentity then
      return nil,errorTable("sharktrust_identity_mismatch")
   end
   if not isHex(state.credential,64) then return nil,errorTable("invalid_saved_state") end
   if state.pending then
      if state.pending ~= true or type(state.request) ~= "table" then return nil,errorTable("invalid_saved_state") end
   elseif type(state.deviceId) ~= "string" or state.deviceId == "" or type(state.name) ~= "string" or
      state.name == "" then return nil,errorTable("invalid_saved_state") end
   state=copy(state)
   state.credential=state.credential:lower()
   return state
end

function M.createSharkTrust(options)
   local store=options.store
   local client,notify=options.client,options.notify
   local deps=options.dependencies or {}
   local timerFactory,now=deps.timer or function(action) return ba.timer(action) end,deps.now or os.time
   local delay=tonumber(options.propagationDelay) or 30
   if delay < 0 then return nil,errorTable("invalid_propagation_delay") end
   local identity,adapter=client:identity(),{type="dns-01"}
   local saveQueue,loadWaiters={},{ }
   local state,pendingState,busy,challenge
   local saving,loaded,loading,closed=false,false,false,false

   local function emit(code) safeCallback(notify,code) end
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
      local ok,message=pcall(store.save,item.state,done)
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
   function adapter:enroll(request,callback)
      if not enter("enroll",callback) then return end
      local saved=pendingState or state
      local function done(result,problem) leave(callback,result and copy(result),problem) end
      -- A successful reply awaiting disk storage must not cause another registration.
      if pendingState and not pendingState.pending then return saveState(pendingState,done) end
      if not saved or not saved.pending then
         saved={version=2,portalUrl=identity.portalUrl,zoneIdentity=identity.zoneIdentity,
            pending=true,request=copy(request),updatedAt=now(),
            credential=ba.rndbs(32):gsub(".",function(c) return string.format("%02x",string.byte(c)) end)}
      end
      -- Persist before sending. Reuse this credential after timeouts and process restarts.
      saveState(saved,function(pending,saveProblem)
         if not pending then return done(nil,saveProblem) end
         local attempt=copy(pending.request)
         attempt.credential=pending.credential
         client:enroll(attempt,function(result,problem)
            if not result then return done(nil,problem) end
            saveState(makeState(result,identity),done)
         end)
      end)
      return true
   end

   function adapter:isAvailable(name,callback) return client:isAvailable(name,callback) end

   function adapter:load(callback)
      loadState(function(saved,problem) safeCallback(callback,saved and copy(saved),problem) end)
      return true
   end

   function adapter:resume(callback)
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
                  safeCallback(callback,stored and copy(result),saveProblem)
               end)
            end
            safeCallback(callback,copy(result))
         end)
      end)
      return true
   end

   local function deviceCall(method,request,callback)
      withState(callback,function() client[method](client,request or callback,request and callback or nil) end)
      return true
   end
   function adapter:isRegistered(callback) return deviceCall("isRegistered",nil,callback) end
   function adapter:setIpAddress(ipAddress,callback) return deviceCall("setIpAddress",ipAddress,callback) end
   function adapter:getWan(callback) return deviceCall("getWan",nil,callback) end

   function adapter:switchIdentity(value,switchOptions,callback)
      local newClient=type(value) == "table" and value.client
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
      if challenge then return reject(callback,"challenge_in_progress") end
      context=type(context) == "table" and context or {}
      local request={recordName=context.recordName,recordData=context.recordData,
         dnsResolveTimeoutMs=context.dnsResolveTimeoutMs or math.max(1000,math.floor(delay*1000))}
      withState(callback,function()
         challenge={context=context,callback=callback,ready=false}
         client:setAcmeRecord(request,function(result,problem)
            if not challenge then return end
            if not result then challenge=nil return safeCallback(callback,nil,problem) end
            emit(30)
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
      local active=challenge
      challenge=nil
      if active and active.timer then active.timer:cancel() end
      if active and active.callback then safeCallback(active.callback,nil,errorTable("challenge_cancelled")) end
      if not state then return safeCallback(callback,true) end
      client:removeAcmeRecord(function(result,problem)
         if result and not problem then emit(31) end
         safeCallback(callback,result or not problem or nil,problem)
      end)
      return true
   end

   function adapter:status()
      return {type="sharktrust",loaded=loaded,enrolled=state ~= nil and not state.pending,name=state and state.name,
         deviceId=state and state.deviceId,portalUrl=identity.portalUrl,operation=busy,
         challenge=challenge and {recordName=challenge.context.recordName,ready=challenge.ready},
         pendingSave=pendingState ~= nil,busy=busy ~= nil or loading or saving or #saveQueue > 0}
   end
   function adapter:close(callback)
      if closed then return safeCallback(callback,true) end
      if busy or loading or saving or saveQueue[1] then return nil,"busy" end
      closed=true
      local active=challenge
      challenge=nil
      if active and active.timer then active.timer:cancel() end
      if active and active.callback then safeCallback(active.callback,nil,errorTable("adapter_closed")) end
      local function done(_,removeError)
         client:close(function(_,problem)
            problem=removeError or problem
            safeCallback(callback,not problem or nil,problem)
         end)
      end
      if state and active then client:removeAcmeRecord(done) else done() end
      return true
   end
   return adapter
end

function M.createManual(options)
   options=options or {}
   local notify=options.notify
   local adapter,phase,closed={type="dns-01"},"idle",false
   local context,pending

   function adapter:present(value,callback)
      if closed then return reject(callback,"adapter_closed") end
      if pending or phase ~= "idle" then return reject(callback,"challenge_in_progress") end
      context,phase,pending=value,"publish",callback
      safeCallback(notify,32)
      return true
   end

   function adapter:cleanup(_,callback)
      phase,context,pending="idle",nil,nil
      safeCallback(callback,true,nil)
      return true
   end

   function adapter:continue(callback)
      if not pending then return reject(callback,"no_pending_action") end
      local operation=pending
      pending=nil
      phase="active"
      safeCallback(operation,true,nil)
      safeCallback(callback,true,nil)
      return true
   end

   function adapter:cancel(callback)
      local operation=pending
      phase,context,pending="idle",nil,nil
      if operation then safeCallback(operation,nil,errorTable("challenge_cancelled")) end
      safeCallback(callback,true,nil)
      return true
   end

   function adapter:status()
      return {type="manual",phase=phase,recordName=context and context.recordName,
         recordData=context and context.recordData}
   end

   function adapter:close(callback) closed=true return self:cancel(callback) end
   return adapter
end
return M
