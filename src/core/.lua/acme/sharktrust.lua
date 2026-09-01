local M,encode,decode={},ba.json.encode,ba.json.decode
local errorTable,copy,safeCallback,isHex,_,_,reject,ipv4,schedule=require"acme/_util"()
local httpRequest=require"acme/_http"

local function hexToBinary(value) return (value:gsub("%x%x",function(pair) return string.char(tonumber(pair,16)) end)) end

local function normalizePortalUrl(value)
   if type(value) ~= "string" or not value:match("^https://") or value:find("[#?%s]") then
      return nil,errorTable("invalid_portal_url") end
   value=value:gsub("/+$","")
   local authority,path=value:match("^(https://[^/]+)(/.*)$")
   if not authority then authority,path=value,"" end
   if path == "" then path="/cmdv2.lsp" end
   if path ~= "/cmdv2.lsp" then return nil,errorTable("invalid_portal_url") end
   return authority..path
end

function M.create(options)
   if type(options) ~= "table" then return nil,errorTable("invalid_options") end
   options=copy(options)
   local portalUrl,urlErr=normalizePortalUrl(options.portalUrl)
   if not portalUrl then return nil,urlErr end
   if not isHex(options.zoneKey,64) then return nil,errorTable("invalid_zone_key") end
   local zoneKey,suppliedSecret,suppliedProof=string.lower(options.zoneKey),options.secret,options.proof
   if (suppliedSecret == nil) == (suppliedProof == nil) then
      return nil,errorTable("invalid_proof_source")
   end

   local proof,proofKey
   if suppliedSecret ~= nil then
      if not isHex(suppliedSecret,64) then return nil,errorTable("invalid_zone_secret") end
      proofKey=ba.crypto.PBKDF2("sha256",string.upper(suppliedSecret),
         hexToBinary(zoneKey),1000,32)
      proof=function(message)
         return ba.crypto.hash("hmac","sha256",proofKey)(message)(true,"binary")
      end
   elseif type(suppliedProof) == "function" then
      proof=suppliedProof
   else
      return nil,errorTable("invalid_proof_source")
   end

   local deps=options.dependencies or {}
   local httpFactory=deps.httpFactory or function(httpOptions)
      return require"httpc".create(httpOptions)
   end
   local reverseFactory=deps.reverse or ba.revcon
   local run=deps.run or function(action) ba.thread.run(action) end
   local jsonEncode,jsonDecode=deps.jsonEncode or encode,deps.jsonDecode or decode
   local httpOptions=copy(options.http or {})
   local credential
   if options.credential ~= nil then
      if not isHex(options.credential,64) then return nil,errorTable("invalid_device_credential") end
      credential=string.lower(options.credential)
   end

   local identityOK,identityProof=pcall(proof,"BACME2-IDENTITY\0"..zoneKey)
   if not identityOK or type(identityProof) ~= "string" or #identityProof ~= 32 then
      return nil,errorTable("proof_failed")
   end
   local identity={portalUrl=portalUrl,
      zoneIdentity=ba.b64urlencode(ba.crypto.hash"sha256"(zoneKey)(identityProof)(true,"binary"))}
   identityProof=nil
   local clients,closeCallbacks,client,active,closed,rotating={},{},{},0,false,false
   local reverse,reverseEnabled

   local function stopReverse()
      if reverse then reverse:close() reverse=nil end
   end

   local function startReverse()
      if not isHex(credential,64) then return nil,errorTable("not_enrolled",nil,{status=401}) end
      if not reverseFactory then return nil,errorTable("reverse_connection_unavailable") end
      local ok,signature=pcall(proof,"BACME2-DEVICE\0"..credential.."\0")
      if not ok or type(signature) ~= "string" or #signature ~= 32 then
         return nil,errorTable("proof_failed")
      end
      local op=copy(options.reverse or {})
      op.url=portalUrl
      if op.shark == nil and ba.sharkclient then op.shark=ba.sharkclient() end
      stopReverse()
      reverse=reverseFactory(op)
      reverse:token{Authorization="Bearer "..credential,
         ["X-BACME-Proof"]=ba.b64urlencode(signature)}
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
      header=copy(header or {})
      header["Content-Type"]="application/json"
      header["X-BACME-Proof"]=ba.b64urlencode(signature)
      local response,requestErr=httpRequest(httpFactory,httpOptions,clients,{
         trusted=true,
         url=portalUrl,
         method="POST",
         size=#bodyData,
         header=header
      },bodyData)
      if not response then return nil,requestErr end
      local status,decodedOK=response.status
      decodedOK,response=pcall(jsonDecode,response.body)
      if not decodedOK or type(response) ~= "table" or response.version ~= "2.0" then
         return nil,errorTable("invalid_response","The SharkTrust response is not valid JSON",{status=status})
      end
      if status and status >= 200 and status < 300 and type(response.result) == "table" then
         return response.result,nil
      end
      local serverError=type(response.error) == "table" and response.error or {}
      local code=serverError.code or "http_error"
      return nil,errorTable(code,
         serverError.message or "SharkTrust HTTP status "..tostring(status),{
            status=status,
            temporary=status == 429 or status == 409 and code == "rotation_in_progress" or
               (status and status >= 500) or false
         })
   end

   local function begin(callback,action)
      if type(callback) ~= "function" then return reject(callback,"invalid_callback") end
      if closed then return reject(callback,"client_closed") end
      active=active+1
      schedule(run,action,function(result,problem) finish(callback,result,problem) end)
      return true
   end

   local function enrollmentBody(request)
      if type(request) ~= "table" then return nil,errorTable("invalid_request") end
      if not ipv4(request.ipAddress) then return nil,errorTable("invalid_ip_address") end
      if request.dns ~= nil and request.dns ~= "local" and request.dns ~= "wan" and request.dns ~= "both" then
         return nil,errorTable("invalid_dns_mode")
      end
      if request.info ~= nil and (type(request.info) ~= "string" or #request.info > 256) then
         return nil,errorTable("invalid_info")
      end
      if request.namePolicy ~= nil and request.namePolicy ~= "exact" and request.namePolicy ~= "increment" then
         return nil,errorTable("invalid_name_policy")
      end
      local body={command="Register",ipAddress=request.ipAddress}
      if request.name ~= nil then body.name=request.name end
      if request.namePolicy ~= nil then body.namePolicy=request.namePolicy end
      if request.dns ~= nil then body.dns=request.dns end
      if request.info ~= nil then body.info=request.info end
      return body
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
         "BACME2-DEVICE\0"..selectedCredential.."\0")
   end

   local function zonePost(body,purpose)
      return post(body,{["X-BACME-Zone-Key"]=zoneKey},purpose..zoneKey.."\0")
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
      if type(name) ~= "string" or #name < 1 or #name > 253 then
         return reject(callback,"invalid_name")
      end
      return begin(callback,function()
         local result,requestErr=zonePost({command="IsAvailable",name=name},"BACME2-AVAILABLE\0")
         if not result then return nil,requestErr end
         if type(result.available) ~= "boolean" or type(result.name) ~= "string" then
            return nil,errorTable("invalid_response")
         end
         return copy(result)
      end)
   end

   function client:enroll(request,callback)
      local body,err=enrollmentBody(request)
      if not body then return reject(callback,err.code,err.message) end
      return begin(callback,function()
         local result,requestErr=zonePost(body,"BACME2-REGISTER\0")
         if not result then return nil,enrollmentError(requestErr) end
         if type(result.deviceId) ~= "string" or type(result.name) ~= "string" or
            not isHex(result.credential,64) then
            return nil,errorTable("invalid_response")
         end
          credential=string.lower(result.credential)
          restartReverse()
          return copy(result),nil
      end)
   end

   function client:isRegistered(callback)
      return begin(callback,function() return devicePost("IsRegistered") end)
   end

   function client:setIpAddress(request,callback)
      if type(request) ~= "table" or not ipv4(request.ipAddress) then
         return reject(callback,"invalid_ip_address")
      end
      if request.dns ~= nil and request.dns ~= "local" and request.dns ~= "wan" and request.dns ~= "both" then
         return reject(callback,"invalid_dns_mode")
      end
      local body={ipAddress=request.ipAddress}
      if request.dns then body.dns=request.dns end
      return begin(callback,function() return devicePost("SetIpAddress",body) end)
   end

   function client:setAcmeRecord(request,callback)
      request=type(request) == "table" and request or {}
      local recordName=request.recordName or request.record
      local recordData=request.recordData or request.data
      local timeout=request.dnsResolveTimeoutMs or request.timeout
      if type(recordName) ~= "string" or #recordName == 0 or #recordName > 253 then
         return reject(callback,"invalid_record_name")
      end
      if type(recordData) ~= "string" or #recordData < 1 or #recordData > 512 or
         recordData:find("[^A-Za-z0-9_-]") then
         return reject(callback,"invalid_record_data")
      end
      if timeout ~= nil and (type(timeout) ~= "number" or timeout % 1 ~= 0 or timeout < 1000 or timeout > 300000) then
         return reject(callback,"invalid_dns_timeout")
      end
      local body={recordName=recordName,recordData=recordData}
      if timeout then body.dnsResolveTimeoutMs=timeout end
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
      if type(enable) ~= "boolean" then return nil,errorTable("invalid_reverse_connection_option") end
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

   function client:rotateCredential(saveCredential,callback)
      if type(saveCredential) ~= "function" then return reject(callback,"invalid_store") end
      if type(callback) ~= "function" then return reject(callback,"invalid_callback") end
      if rotating then return reject(callback,"rotation_in_progress",nil,{temporary=true}) end
      if closed then return reject(callback,"client_closed") end
      rotating=true
      active=active+1
      local oldCredential=credential
      local function done(result,err) rotating=false finish(callback,result,err) end
      run(function()
         local result,requestErr=devicePost("RotateCredential",nil,oldCredential)
         if not result then
            if requestErr and requestErr.code == "transport_error" then
               if requestErr.phase == "request" then return done(nil,requestErr) end
               local oldResult,oldErr=devicePost("IsRegistered",nil,oldCredential)
               if oldResult then
                  return done(nil,errorTable("rotation_not_committed",nil,{temporary=true}))
               end
               if oldErr and oldErr.status == 401 then
                  return done(nil,errorTable("rotation_reenrollment_required"))
               end
               return done(nil,errorTable("rotation_state_unknown",nil,{temporary=true}))
            end
            return done(nil,requestErr)
         end
         if not isHex(result.credential,64) then return done(nil,errorTable("invalid_response")) end
         local newCredential=result.credential:lower()
         local saved=false
         local function savedCallback(ok,saveErr)
            if saved then return end
            saved=true
             if ok then
                credential=newCredential
                restartReverse()
                done({credential=newCredential})
            else
               done(nil,errorTable("credential_persistence_failed",
                  type(saveErr) == "table" and saveErr.message or tostring(saveErr)))
            end
         end
         local saveOK,saveErr=pcall(saveCredential,newCredential,savedCallback)
         if not saveOK then savedCallback(nil,saveErr) end
      end)
      return true
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
      if callback ~= nil and type(callback) ~= "function" then
         return nil,errorTable("invalid_callback")
      end
      closed,credential,proofKey,suppliedSecret,suppliedProof=true,nil,nil,nil,nil
      stopReverse()
      for http in pairs(clients) do http:close() end
      clients={}
      if callback then table.insert(closeCallbacks,callback) end
      finishClose()
      return true
   end

   return client
end

return M
