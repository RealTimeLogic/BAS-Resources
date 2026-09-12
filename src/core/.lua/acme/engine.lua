-- RFC 8555 ACME client with optional RFC 9773 renewal information.
local M,encode,decode,trustedTpm={},ba.json.encode,ba.json.decode
local U=require"acme/_util"
local errorTable,copy,safeCallback=U.err,U.copy,U.callback
local validHttpsUrl,resolveService,reject,schedule=U.isHttps,U.resolveService,U.reject,U.schedule

local function problemError(response,status,headers,operation,url)
   local problem=type(response) == "table" and response or {}
   local problemType=problem.type
   local code="acme_error"
   if type(problemType) == "string" then
      code=problemType:match("([^:]+)$") or code
      code=code:gsub("(%l)(%u)","%1_%2"):lower()
   elseif status == 429 then
      code="rate_limited"
   elseif status and status >= 500 then
      code="server_error"
   end
   return errorTable(code,problem.detail or ("ACME HTTP status "..tostring(status)),{
      status=status,
      type=problemType,
      detail=problem.detail,
      subproblems=copy(problem.subproblems),
      retryAfter=headers and headers["retry-after"] or nil,
      replayNonce=headers and headers["replay-nonce"] or nil,
      operation=operation,
      url=url,
      temporary=status == 429 or (status and status >= 500) or code == "bad_nonce"
   })
end

local function pemBody(pem,label)
   if type(pem) ~= "string" then return nil end
   local pattern="%-%-%-%-%-BEGIN "..label.."%-%-%-%-%-%s*(.-)%s*%-%-%-%-%-END "..label.."%-%-%-%-%-"
   local body=pem:match(pattern)
   if not body then return nil end
   return ba.b64decode((body:gsub("%s", "")))
end

local function tlv(data,position)
   local tag,first=data:byte(position,position+1)
   if not first then return end
   local length,start=first,position+2
   if first >= 128 then
      local count=first-128
      if count < 1 or count > 4 or start+count-1 > #data then return end
      length=0
      for index=0,count-1 do length=length*256+data:byte(start+index) end
      start=start+count
   end
   local nextPosition=start+length
   if nextPosition-1 > #data then return end
   return {tag=tag,start=start,next=nextPosition,value=data:sub(start,nextPosition-1)}
end

local function certificateId(certificate)
   if type(certificate) == "table" and type(certificate.ariId) == "string" then return certificate.ariId end
   local pem=type(certificate) == "table" and certificate.certificate or certificate
   local der=pemBody(pem,"CERTIFICATE")
   if not der then return nil,errorTable("invalid_certificate") end
   local outer=tlv(der,1)
   local tbs=outer and outer.tag == 0x30 and tlv(der,outer.start)
   if not tbs or tbs.tag ~= 0x30 then return nil,errorTable("invalid_certificate") end
   local field=tlv(der,tbs.start)
   if field and field.tag == 0xA0 then field=tlv(der,field.next) end
   if not field or field.tag ~= 0x02 then return nil,errorTable("invalid_certificate") end
   local serial,position=field.value,field.next
   while position < tbs.next do
      field=tlv(der,position)
      if not field then return nil,errorTable("invalid_certificate") end
      if field.tag == 0xA3 then break end
      position=field.next
   end
   if not field or field.tag ~= 0xA3 then return nil,errorTable("ari_id_unavailable") end
   local extensions=tlv(der,field.start)
   if not extensions or extensions.tag ~= 0x30 then return nil,errorTable("invalid_certificate") end
   position=extensions.start
   while position < extensions.next do
      local extension=tlv(der,position)
      local item=extension and extension.tag == 0x30 and tlv(der,extension.start)
      if not item or item.tag ~= 0x06 then return nil,errorTable("invalid_certificate") end
      local oid=item.value
      item=tlv(der,item.next)
      if item and item.tag == 0x01 then item=tlv(der,item.next) end
      if not item or item.tag ~= 0x04 then return nil,errorTable("invalid_certificate") end
      if oid == "U\29#" then
         local sequence=tlv(item.value,1)
         local aki=sequence and sequence.tag == 0x30 and tlv(item.value,sequence.start)
         while aki do
            if aki.tag == 0x80 then return ba.b64urlencode(aki.value).."."..ba.b64urlencode(serial) end
            if aki.next >= sequence.next then break end
            aki=tlv(item.value,aki.next)
         end
         return nil,errorTable("ari_id_unavailable")
      end
      position=extension.next
   end
   return nil,errorTable("ari_id_unavailable")
end

-- Called once by the Mako or Xedge TPM bootstrap before it publishes ba.tpm.
M.setTPM=function(t)
   local jwtSign=t.jwtSign
   if not jwtSign and t.jwtsign then
      jwtSign=function(name,payload,header) return t.jwtsign(payload,name,header) end
   end
   trustedTpm={jwtSign=jwtSign,keyParams=t.keyParams or t.keyparams,
      createKey=t.createKey or t.createkey,hasKey=t.hasKey or t.haskey,
      createCsr=t.createCsr or t.createcsr}
   M.setTPM=nil
end

local function keyFunctions(tpm,jwt)
   local function tpmMethod(name) return tpm and type(tpm[name]) == "function" and tpm[name] or nil end
   local function restore(key)
      if type(key) ~= "table" or key.provider ~= "tpm" then return true end
      local has,create=tpmMethod"hasKey",tpmMethod"createKey"
      if has and not has(key.name) then
         if not create then return nil,errorTable("tpm_unavailable") end
         create(key.name,key.options)
      end
      return true
   end
   local function sign(key,payload,header)
      if type(key) == "table" and key.provider == "tpm" then
         local method=tpmMethod"jwtSign"
         if not method then return nil,errorTable("tpm_unavailable") end
         local ok,problem=restore(key)
         if not ok then return nil,problem end
         local a,b=method(key.name,payload,header)
         if not a then return nil,type(b) == "table" and b or errorTable("sign_failed",b) end
         return b or a
      end
      local a,b=jwt.sign(payload,key,header)
      if not a then return nil,type(b) == "table" and b or errorTable("sign_failed",b) end
      return b or a
   end
   local function params(key)
      if type(key) == "table" and key.provider == "tpm" then
         local method=tpmMethod"keyParams"
         if not method then return nil,errorTable("tpm_unavailable") end
         local ok,problem=restore(key)
         if not ok then return nil,problem end
         return method(key.name)
      end
      return ba.crypto.keyparams(key)
   end
   local function createKey(name,options)
      options=options or {}
      local kind=options.type or "ecc"
      if kind ~= "ecc" and kind ~= "rsa" then return nil,errorTable("invalid_key_type") end
      local create,has=tpmMethod"createKey",tpmMethod"hasKey"
      if kind == "ecc" and create then
         local keyOptions={key="ecc",curve=options.curve or "SECP384R1"}
         local exists=false
         if has then exists=has(name) end
         if not exists then create(name,keyOptions) end
         return {provider="tpm",name=name,options=keyOptions}
      end
      local keyOptions=kind == "rsa" and
         {key="rsa",bits=options.bits or 2048} or {key="ecc",curve=options.curve or "SECP384R1"}
      return ba.create.key(keyOptions)
   end
   local function createCsr(key,domain)
      local dn,types,usage={commonname=domain},{"SSL_CLIENT","SSL_SERVER"},{"DIGITAL_SIGNATURE","KEY_ENCIPHERMENT"}
      if type(key) == "table" and key.provider == "tpm" then
         local method=tpmMethod"createCsr"
         if not method then return nil,errorTable("tpm_unavailable") end
         local ok,problem=restore(key)
         if not ok then return nil,problem end
         return method(key.name,dn,types,usage)
      end
      return ba.create.csr(key,dn,types,usage)
   end
   return sign,params,createKey,createCsr
end

local function httpChallenge()
   local adapter,directory={type="http-01"}
   local expectedPath,expectedValue

   function adapter:present(context,callback)
      if directory then return reject(callback,"challenge_in_progress") end
      expectedPath,expectedValue=context.tokenPath,context.keyAuthorization
      local function serve(_ENV,relative)
         if relative ~= expectedPath then return false end
         response:setcontenttype"application/octet-stream"
         response:setcontentlength(#expectedValue)
         response:send(expectedValue)
         return true
      end
      directory=ba.create.dir(".well-known",1)
      directory:setfunc(serve)
      directory:insert()
      safeCallback(callback,true,nil)
      return true
   end

   function adapter:cleanup(_,callback)
      if directory then directory:unlink() end
      directory,expectedPath,expectedValue=nil,nil,nil
      safeCallback(callback,true,nil)
      return true
   end
   return adapter
end

function M.create(options)
   options=options or {}
   local deps=options.dependencies or {}
   local httpFactory=deps.httpFactory or function(httpOptions) return require"httpc".create(httpOptions) end
   local run=deps.run or function(action) ba.thread.run(action) end
   local sleep=deps.sleep or ba.sleep
   local now=options.now or deps.now or os.time
   local jsonEncode=deps.jsonEncode or encode
   local jsonDecode=deps.jsonDecode or decode
   local jwt=deps.jwt
   local tpm=trustedTpm or options.tpm
   local activeClients,closeCallbacks,standalone,closed={},{},0,false
   local queue,engine,nextJobId,current={},{},0
   local closeError
   local jwtSign,keyParams,createKey,createCsr,resume
   local function loadKeys()
      if not jwt then jwt=require"jwt" end
      if not createKey then jwtSign,keyParams,createKey,createCsr=keyFunctions(tpm,jwt) end
   end

   local function finishClose()
      if closed and standalone == 0 and not current and #queue == 0 then
         local callbacks=closeCallbacks
         closeCallbacks={}
         for _,callback in ipairs(callbacks) do safeCallback(callback,not closeError or nil,closeError) end
      end
   end
   local function rawRequest(service,method,url,body,headers)
      if closed then return nil,errorTable("engine_closed") end
      local request={trusted=true,url=url,method=method,header=headers}
      if body ~= nil then request.size=#body end
      return U.http(httpFactory,service.http,activeClients,request,body)
   end
   local function decodeResponse(response,operation,url,allowEmpty)
      if response.body == "" and allowEmpty then return {},nil end
      local ok,value=pcall(jsonDecode,response.body)
      if not ok or type(value) ~= "table" then
         return nil,errorTable("invalid_response","The ACME response is not valid JSON",{status=response.status,operation=operation,url=url})
      end
      return value,nil
   end
   local function parseRetryAfter(value,defaultSeconds)
      if type(value) == "number" then return math.max(0,value) end
      if type(value) == "string" then
         local seconds=tonumber(value)
         if seconds then return math.max(0,seconds) end
         local ok,date=pcall(ba.parsedate,value)
         if ok and date then return math.max(0,date-now()) end
      end
      return defaultSeconds or 3
   end
   local function createSession(service)
      local session={service=service,nonce=nil,directory=nil}
      function session:getDirectory()
         if self.directory then return self.directory,nil end
         local response,requestErr=rawRequest(self.service,"GET",self.service.directoryUrl,nil,{Accept="application/json"})
         if not response then return nil,requestErr end
         if response.status ~= 200 then
            local value=select(1,decodeResponse(response,"directory",self.service.directoryUrl,true))
            return nil,problemError(value,response.status,response.headers,"directory",self.service.directoryUrl)
         end
         local directory,decodeErr=decodeResponse(response,"directory",self.service.directoryUrl)
         if not directory then return nil,decodeErr end
         for _,field in ipairs{"newNonce","newAccount","newOrder","revokeCert"} do
            if not validHttpsUrl(directory[field]) then
               return nil,errorTable("invalid_directory","The ACME directory is missing "..field,{url=self.service.directoryUrl})
            end
         end
         if directory.renewalInfo ~= nil and not validHttpsUrl(directory.renewalInfo) then
            return nil,errorTable("invalid_directory","The ACME renewalInfo URL is invalid",{url=self.service.directoryUrl})
         end
         if type(directory.meta) == "table" and directory.meta.externalAccountRequired == true then
            return nil,errorTable("external_account_required","The selected ACME service requires External Account Binding",{url=self.service.directoryUrl})
         end
         self.directory=directory
         return directory,nil
      end
      function session:getNonce()
         if self.nonce then local value=self.nonce self.nonce=nil return value,nil end
         local directory,directoryErr=self:getDirectory()
         if not directory then return nil,directoryErr end
         local response,requestErr=rawRequest(self.service,"HEAD",directory.newNonce,nil)
         if not response then return nil,requestErr end
         if response.status ~= 200 and response.status ~= 204 then
            return nil,problemError(nil,response.status,response.headers,"newNonce",directory.newNonce)
         end
         local nonce=response.headers["replay-nonce"]
         if type(nonce) ~= "string" or nonce == "" then
            return nil,errorTable("missing_nonce","The ACME server did not return Replay-Nonce",{status=response.status,url=directory.newNonce})
         end
         return nonce,nil
      end
      function session:signed(account,url,payload,operation,useJwk,rawResult)
         loadKeys()
         for attempt=1,2 do
            local nonce,nonceErr=self:getNonce()
            if not nonce then return nil,nonceErr end
            local header={alg="ES256",nonce=nonce,url=url}
            if useJwk then
               local x,y=keyParams(account.key)
               if not x then return nil,y end
               header.jwk={kty="EC",crv="P-256",x=ba.b64urlencode(x),y=ba.b64urlencode(y)}
            else
               if type(account.url) ~= "string" then return nil,errorTable("account_not_registered") end
               header.kid=account.url
            end
            local signed,signErr=jwtSign(account.key,payload,header)
            if not signed then return nil,signErr end
            local body=jsonEncode(signed)
            local response,requestErr=rawRequest(self.service,"POST",url,body,{
               ["Content-Type"]="application/jose+json",
               Accept=rawResult and "application/pem-certificate-chain" or "application/json"
            })
            if not response then return nil,requestErr end
            self.nonce=response.headers["replay-nonce"]
            if response.status == 200 or response.status == 201 or response.status == 204 then
               if rawResult then return response.body,nil,response end
               local value,decodeErr=decodeResponse(response,operation,url,response.status == 204 or operation == "revokeCert")
               if not value then return nil,decodeErr end
               return value,nil,response
            end
            local value=select(1,decodeResponse(response,operation,url,true))
            local problem=problemError(value,response.status,response.headers,operation,url)
            if problem.code ~= "bad_nonce" or attempt == 2 then return nil,problem,response end
            self.nonce=response.headers["replay-nonce"]
            if not self.nonce then
               local fresh,freshErr=self:getNonce()
               if not fresh then return nil,freshErr end
               self.nonce=fresh
            end
         end
      end
      return session
   end
   local function openDirectory(service)
      local session=createSession(service)
      local directory,err=session:getDirectory()
      return session,directory,err
   end
   function engine:createKey(name,keyOptions)
      loadKeys()
      return createKey(name,keyOptions)
   end
   local function thumbprint(account)
      loadKeys()
      local x,y=keyParams(account.key)
      if not x then return nil,y end
      local canonical=string.format('{"crv":"P-256","kty":"EC","x":"%s","y":"%s"}',ba.b64urlencode(x),ba.b64urlencode(y))
      return ba.b64urlencode(ba.crypto.hash"sha256"(canonical)(true,"binary"))
   end
   local function registerAccount(session,directory,account,acceptTerms)
      if type(account.email) ~= "string" or account.email == "" then return nil,errorTable("invalid_account") end
      if not account.key then
         local key,keyErr=engine:createKey("$account",{type="ecc",curve="SECP256R1"})
         if not key then return nil,keyErr end
         account.key=key
      end
      if account.url then
         if account.directoryUrl ~= session.service.directoryUrl then
            return nil,errorTable("account_directory_mismatch","The ACME account belongs to another directory",{url=account.url,directoryUrl=session.service.directoryUrl})
         end
         return account,nil
      end
      if acceptTerms ~= true then return nil,errorTable("terms_not_accepted") end
      local result,requestErr,response=session:signed(account,directory.newAccount,{
         termsOfServiceAgreed=true,onlyReturnExisting=false,contact={"mailto:"..account.email}
      },"newAccount",true)
      if not result then return nil,requestErr end
      local location=response.headers.location
      if type(location) ~= "string" or location == "" then return nil,errorTable("invalid_response") end
      account.url=location
      account.directoryUrl=session.service.directoryUrl
      return account,nil
   end
   local function waitFor(job,starter)
      local synchronous=true
      local completed=false
      local values
      local function callback(...)
         if completed then return end
         completed=true
         values=table.pack(...)
         if not synchronous then resume(job,table.unpack(values,1,values.n)) end
      end
      local ok,result,err=pcall(starter,callback)
      synchronous=false
      if not ok then return nil,errorTable("callback_failed",tostring(result)) end
      if completed then return table.unpack(values,1,values.n) end
      if result == nil and err ~= nil then return nil,err end
      return coroutine.yield()
   end
   local function poll(session,account,url,kind,job)
      local elapsed=0
      local timeout=job.request.timeout or 600
      while elapsed <= timeout do
         if job.cancelled then return nil,errorTable("cancelled") end
         local value,err,response=session:signed(account,url,"",kind,false)
         if not value then return nil,err end
         if value.status == "valid" then return value,nil,response end
         if value.status == "invalid" then return nil,problemError(value.error or {},response.status,response.headers,kind,url) end
         if value.status ~= "pending" and value.status ~= "processing" and value.status ~= "ready" then
            return nil,errorTable("invalid_response","Unexpected "..kind.." status "..tostring(value.status),{url=url})
         end
         local delay=parseRetryAfter(response.headers["retry-after"],3)
         if elapsed+delay > timeout then break end
         sleep(math.floor(delay*1000))
         elapsed=elapsed+delay
      end
      return nil,errorTable("timeout",kind.." polling timed out",{temporary=true,url=url})
   end
   local function certificateMain(job)
      local request=job.request
      local account=job.account
      local session,directory,err=openDirectory(job.service)
      if not directory then return nil,err end
      account,err=registerAccount(session,directory,account,request.acceptTerms)
      if not account then return nil,err end
      local orderPayload={identifiers={{type="dns",value=request.domain}}}
      if request.replaces and directory.renewalInfo then orderPayload.replaces=request.replaces end
      local order,orderErr,orderResponse=session:signed(account,directory.newOrder,orderPayload,"newOrder",false)
      if not order and orderErr and orderErr.code == "account_does_not_exist" and not job.accountRetried then
         job.accountRetried=true account.url=nil account.directoryUrl=nil
         account,err=registerAccount(session,directory,account,request.acceptTerms)
         if not account then return nil,err end
         order,orderErr,orderResponse=session:signed(account,directory.newOrder,orderPayload,"newOrder",false)
      end
      if not order then return nil,orderErr end
      local orderUrl=orderResponse.headers.location
      local authorizationUrl=type(order.authorizations) == "table" and order.authorizations[1]
      local finalizeUrl=order.finalize
      if not validHttpsUrl(orderUrl) or not validHttpsUrl(authorizationUrl) or not validHttpsUrl(finalizeUrl) then
         return nil,errorTable("invalid_response")
      end
      local authorization,authorizationErr=session:signed(account,authorizationUrl,"","authorization",false)
      if not authorization then return nil,authorizationErr end
      local selected
      local challengeType=request.challenge.type
      for _,challenge in ipairs(authorization.challenges or {}) do if challenge.type == challengeType then selected=challenge break end end
      if not selected or type(selected.token) ~= "string" or not validHttpsUrl(selected.url) then
         return nil,errorTable("challenge_unavailable","The ACME server did not offer "..tostring(challengeType))
      end
      local accountThumbprint,thumbErr=thumbprint(account)
      if not accountThumbprint then return nil,thumbErr end
      local keyAuthorization=selected.token.."."..accountThumbprint
      local context={domain=request.domain,token=selected.token,keyAuthorization=keyAuthorization,challengeUrl=selected.url}
      if challengeType == "dns-01" then
         local baseDomain=request.domain:find("^%*%.") and request.domain:sub(3) or request.domain
         context.recordName="_acme-challenge."..baseDomain
         context.recordData=ba.b64urlencode(ba.crypto.hash"sha256"(keyAuthorization)(true,"binary"))
         context.dnsResolveTimeoutMs=math.floor((request.dnsResolveTimeout or 30)*1000)
      else context.tokenPath="acme-challenge/"..selected.token end
      job.challengeContext=context
      local presented,presentErr=waitFor(job,function(callback) return request.challenge:present(context,callback) end)
      if not presented then return nil,presentErr or errorTable("challenge_install_failed") end
      job.challengePresented=true
      local _,triggerErr=session:signed(account,selected.url,{},"challenge",false)
      if triggerErr then return nil,triggerErr end
      local valid,validationErr=poll(session,account,selected.url,"challenge",job)
      if not valid then return nil,validationErr end
      local cleaned,cleanupErr=waitFor(job,function(callback) return request.challenge:cleanup(context,callback) end)
      job.challengePresented=false
      if not cleaned then return nil,cleanupErr or errorTable("challenge_cleanup_failed") end
      if job.cancelled then return nil,errorTable("cancelled") end
      local keyOptions=copy(request.key or {})
      local certificateKey=keyOptions.privateKey
      if not certificateKey then certificateKey,err=engine:createKey(request.domain,keyOptions) if not certificateKey then return nil,err end end
      local csr
      loadKeys()
      csr,err=createCsr(certificateKey,request.domain)
      if not csr then return nil,err end
      local csrDer=pemBody(csr,"CERTIFICATE REQUEST") or pemBody(csr,"NEW CERTIFICATE REQUEST")
      if not csrDer then return nil,errorTable("csr_failed") end
      local finalized,finalizeErr=session:signed(account,finalizeUrl,{csr=ba.b64urlencode(csrDer)},"finalize",false)
      if not finalized then return nil,finalizeErr end
      local finalOrder=finalized
      if finalOrder.status ~= "valid" then finalOrder,err=poll(session,account,orderUrl,"order",job) if not finalOrder then return nil,err end end
      if not validHttpsUrl(finalOrder.certificate) then return nil,errorTable("invalid_response") end
      local certificate,certificateErr=session:signed(account,finalOrder.certificate,"","certificate",false,true)
      if not certificate then return nil,certificateErr end
      local ariId=certificateId(certificate)
      return {account=account,privateKey=certificateKey,certificate=certificate,orderUrl=orderUrl,
         directoryUrl=session.service.directoryUrl,ariId=ariId},nil
   end
   local function certificateFlow(job)
      local result,flowErr=certificateMain(job)
      if job.challengePresented then
         local cleaned,cleanupErr=waitFor(job,function(callback) return job.request.challenge:cleanup(job.challengeContext,callback) end)
         job.challengePresented=false
         if not cleaned then if flowErr then flowErr.cleanup=cleanupErr else flowErr=cleanupErr end end
      end
      return result,flowErr
   end
   local function finishJob(job,result,err)
      if job.finished then return end
      if err and type(err) ~= "table" then err=errorTable("operation_failed",tostring(err)) end
      job.finished=true
      job.state=err and (err.code == "cancelled" and "cancelled" or "failed") or "completed"
      job.error=err
      local cleanupErr=err and err.cleanup
      if closed then closeError=closeError or cleanupErr end
      if current == job then current=nil end
      safeCallback(job.callback,result,err)
      for _,callback in ipairs(job.cancelCallbacks) do safeCallback(callback,not cleanupErr or nil,cleanupErr) end
      if not current and #queue > 0 then local nextJob=table.remove(queue,1) current=nextJob nextJob.state="running" resume(nextJob) end
      finishClose()
   end
   -- Cancellation and unexpected Lua failures share one cleanup path.
   local function failJob(job,problem)
      if job.finished or job.finishing then return end
      job.finishing=true
      local function done(_,cleanupErr)
         if cleanupErr then problem.cleanup=cleanupErr end
         job.challengePresented=false
         finishJob(job,nil,problem)
      end
      if job.challengeContext then
         local ok,result,err=pcall(job.request.challenge.cleanup,
            job.request.challenge,job.challengeContext,done)
         if not ok then done(nil,errorTable("challenge_cleanup_failed",tostring(result)))
         elseif result == nil and err then done(nil,err) end
      else done() end
   end
   resume=function(job,...)
      local args=table.pack(...)
      run(function()
         if job.finished or job.finishing then return end
         if job.cancelled and coroutine.status(job.coroutine) == "suspended" and not job.challengePresented then
            return finishJob(job,nil,errorTable("cancelled"))
         end
         local resumed,result,err=coroutine.resume(job.coroutine,table.unpack(args,1,args.n))
         if not resumed then return failJob(job,errorTable("operation_failed",tostring(result))) end
         if coroutine.status(job.coroutine) == "dead" then finishJob(job,result,err) end
      end)
   end
   function engine:certificate(service,account,request,callback)
      if closed then return nil,errorTable("engine_closed") end
      local resolved,serviceErr=resolveService(service)
      if not resolved then safeCallback(callback,nil,serviceErr) return nil,serviceErr end
      local challenge=request.challenge
      if challenge == nil then challenge=httpChallenge() end
      nextJobId=nextJobId+1
      -- Snapshot the caller's options without copying the challenge interface.
      local requestCopy={}
      for name,value in pairs(request) do requestCopy[name]=name == "challenge" and value or copy(value) end
      local job={number=nextJobId,service=resolved,account=copy(account),request=requestCopy,callback=callback,
         state="queued",cancelCallbacks={}}
      job.request.challenge=challenge
      job.coroutine=coroutine.create(function() return certificateFlow(job) end)
      local publicJob={}
      function publicJob:id() return job.number end
      function publicJob:status() return {id=job.number,state=job.state,domain=job.request.domain,error=copy(job.error)} end
      function publicJob:cancel(cancelCallback)
         if job.finished then safeCallback(cancelCallback,true,nil) return true end
         job.cancelled=true
         if cancelCallback then job.cancelCallbacks[#job.cancelCallbacks+1]=cancelCallback end
         if job.state == "queued" then
            for index,queued in ipairs(queue) do if queued == job then table.remove(queue,index) break end end
            finishJob(job,nil,errorTable("cancelled"))
         elseif job.challengeContext then
            failJob(job,errorTable("cancelled"))
         elseif coroutine.status(job.coroutine) == "suspended" and not job.challengePresented then
            finishJob(job,nil,errorTable("cancelled"))
         end
         return true
      end
      job.public=publicJob
      if current then queue[#queue+1]=job else current=job job.state="running" resume(job) end
      return publicJob
   end
   local function standaloneOperation(service,callback,action)
      if closed then return reject(callback,"engine_closed") end
      local resolved,serviceErr=resolveService(service)
      if not resolved then safeCallback(callback,nil,serviceErr) return nil,serviceErr end
      standalone=standalone+1
      schedule(run,function() return action(resolved) end,function(result,problem)
         standalone=standalone-1 safeCallback(callback,result,problem) finishClose()
      end)
      return true
   end
   function engine:directory(service,callback)
      return standaloneOperation(service,callback,function(resolved)
         local _,directory,err=openDirectory(resolved)
         if not directory then return nil,err end
         return {directory=copy(directory),directoryUrl=resolved.directoryUrl},nil
      end)
   end
   function engine:terms(service,callback)
      return standaloneOperation(service,callback,function(resolved)
         local _,directory,err=openDirectory(resolved)
         if not directory then return nil,err end
         return {url=type(directory.meta) == "table" and directory.meta.termsOfService or nil,directoryUrl=resolved.directoryUrl},nil
      end)
   end
   function engine:renewalInfo(service,certificate,callback)
      return standaloneOperation(service,callback,function(resolved)
         local _,directory,err=openDirectory(resolved)
         if not directory then return nil,err end
         if not directory.renewalInfo then return nil,errorTable("ari_unavailable") end
         local identifier,idErr=certificateId(certificate) if not identifier then return nil,idErr end
         local url=directory.renewalInfo:gsub("/+$","").."/"..identifier
         local response,requestErr=rawRequest(resolved,"GET",url,nil,{Accept="application/json"})
         if not response then return nil,requestErr end
         local value,decodeErr=decodeResponse(response,"renewalInfo",url,true)
         if response.status ~= 200 then return nil,problemError(value,response.status,response.headers,"renewalInfo",url) end
         if not value then return nil,decodeErr end
         if type(value.suggestedWindow) ~= "table" or type(value.suggestedWindow.start) ~= "string" or type(value.suggestedWindow["end"]) ~= "string" then
            return nil,errorTable("invalid_renewal_info","The renewalInfo response has no suggested window",{url=url})
         end
         local startOK,start=pcall(function() return ba.datetime(value.suggestedWindow.start):ticks() end)
         local endOK,finish=pcall(function() return ba.datetime(value.suggestedWindow["end"]):ticks() end)
         if not startOK or not endOK or finish <= start then return nil,errorTable("invalid_renewal_info","The renewalInfo suggested window is invalid",{url=url}) end
         return {ariId=identifier,suggestedWindow={start=start,["end"]=finish},explanationUrl=value.explanationURL,
            retryAfter=parseRetryAfter(response.headers["retry-after"],21600),directoryUrl=resolved.directoryUrl},nil
      end)
   end
   function engine:revoke(service,account,certificate,revokeOptions,callback)
      revokeOptions=revokeOptions or {}
      return standaloneOperation(service,callback,function(resolved)
         if type(account) ~= "table" or account.directoryUrl ~= resolved.directoryUrl then return nil,errorTable("account_directory_mismatch") end
         local der=pemBody(type(certificate) == "table" and certificate.certificate or certificate,"CERTIFICATE")
         if not der then return nil,errorTable("invalid_certificate") end
         local session,directory,err=openDirectory(resolved)
         if not directory then return nil,err end
         local payload={certificate=ba.b64urlencode(der)} if revokeOptions.reason ~= nil then payload.reason=revokeOptions.reason end
         local result,requestErr=session:signed(account,directory.revokeCert,payload,"revokeCert",false)
         if not result then return nil,requestErr end
         return true,nil
      end)
   end
   function engine:jobs()
      local result={}
      if current then result[#result+1]=current.public:status() end
      for _,job in ipairs(queue) do result[#result+1]=job.public:status() end
      return result
   end
   function engine:close(callback)
      closed=true
      local queued=queue queue={}
      if current then current.public:cancel() end
      for _,job in ipairs(queued) do finishJob(job,nil,errorTable("cancelled")) end
      for http in pairs(activeClients) do http:close() end
      activeClients={}
      if callback then closeCallbacks[#closeCallbacks+1]=callback end
      finishClose()
      return true
   end
   return engine
end

return M
