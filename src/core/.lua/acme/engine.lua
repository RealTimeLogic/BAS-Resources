-- SPEC: https://ietf-wg-acme.github.io/acme/draft-ietf-acme-acme.html
local dURL={ -- ACME service's directory (discover) URL
   production="https://acme-v02.api.letsencrypt.org/directory",
   staging="https://acme-staging-v02.api.letsencrypt.org/directory"
}

 -- getCert queue: list of {account=obj,rspCB=func,op=obj,getCertCO=coroutine}
local jobQ,jobs={},0
local tpm,te -- Trusted Platform Module API, TPM enabled
local jwt=require"jwt"

local slower=string.lower
local checkCert=true

local ue=ba.urlencode
local jencode,jdecode=ba.json.encode,ba.json.decode
local function aue(x) return ue(ue(x)) end -- ACME url encode

local function errlog(url,msg)
   tracep(false,5,"ACME error,URL:",url,"\n",msg,"\n",debug.traceback("",2))
   return nil,msg
end

local function respErr(err,rspCB)
   if type(err) == 'table' then
      local error=err.error or err
      err=error.detail or jencode(err)
   end
   rspCB(nil,err)
   return nil,err
end

local function useTPM(key,keyname)
   if te then
      local op=jdecode(key)
      if op then
	 if not tpm.haskey(keyname) then tpm.createkey(keyname,op) end
	 return true
      end
   end
   return false
end

local function jwtsign(key,payload,op)
   local _,t
   if useTPM(key,"$account") then
      _,t=tpm.jwtsign(payload,"$account",op)
   else
      _,t=jwt.sign(payload,key,op)
   end
   return t
end

local function keyparams(key)
   if useTPM(key,"$account") then
      return tpm.keyparams"$account"
   end
   return ba.crypto.keyparams(key)
end

local function createkey(kname,op)
   op=op or {}
   if te and "rsa" ~= op.key then
      if not tpm.haskey(kname) then tpm.createkey(kname,op) end
      return jencode{keyname=kname,curve=op.curve}
   end
   return ba.create.key(op)
end

local function createcsr(key,kname,dn,certtype,keyusage)
   return kname and useTPM(key,kname) and tpm.createcsr(kname,dn,certtype,keyusage) or ba.create.csr(key,dn,certtype,keyusage)
end



-- Extracts and returns the public x,y components from a private ECC key.
local function decodeEccPemKey(key)
   local x,y=keyparams(key)
   return ba.b64urlencode(x),ba.b64urlencode(y)
end

-- Returns: "ACME http func", dir listing, nonce
local function createAcmeHttp(op)
   local http=require"http".create(op)
   local function ahttp(url,json,getraw) -- ACME HTTP func
      local ok,err
      if json then
	 local data=jencode(json)
	 ok,err=http:request{
	    trusted=checkCert,
	    url=url,
	    method="POST",
	    size=#data,
	    header={['Content-Type']='application/jose+json'}
	 }
	 http:write(data)
      else
	 ok,err=http:request{url=url,trusted=checkCert}
      end
      if not ok then
	 err=string.format("%s err: %s",op.proxy and "proxy" or "HTTP",err)
	 return errlog(url,err)
      end
      local status=http:status()
      ok=status == 200 or status == 201 or status == 204
      local rsp=http:read"*a"
      if not ok then
	 err=rsp or string.format("HTTP err: %d",status)
	 return errlog(url,err)
      end
      if getraw then
	 if ok then return rsp end
	 return nil,err
      end
      rsp=rsp and jdecode(rsp)
      local h={}
      for k,v in pairs(http:header()) do h[slower(k)]=v end
      return ok,(rsp or err),h["replay-nonce"],h
   end -- ACME http func
   local production=op.production == nil and true or op.production
   local ok,dir=ahttp(production and dURL.production or dURL.staging)
   if ok then
      local rsp,nonce
      ok,rsp,nonce=ahttp(dir.newNonce) -- Get the first nonce
      if ok then return ahttp,dir,nonce end
      dir=rsp
   end
   return false,dir
end

local function postAsGet(http,account,nonce,url,getraw)
   local header={nonce=nonce,alg='ES256',url=aue(url),kid=account.id}
   local payload="" -- POST-as-GET
   return http(url,jwtsign(account.key,payload,header),getraw)
end


local function resumeCo(...)
   assert(#jobQ > 0)
   local args={...}
   ba.thread.run(function()
      local job=jobQ[1]
      local ok,err=coroutine.resume(job.getCertCO,table.unpack(args))
      if not ok then
	 respErr(err,job.rspCB)
      end
      if not ok or coroutine.status(job.getCertCO) == "dead" then
	 table.remove(jobQ,1)
	 jobs=jobs-1
	 if #jobQ > 0 then resumeCo(jobQ[1]) end
      end
   end)
end

-- The default HTTP challenge
local function httpChallengeIntf()
   local dir
   local function insert(tokenURL,keyAuth,rspCB)
      local function wellknown(_ENV,rel)
	 if tokenURL==rel then
	    response:setcontenttype"application/octet-stream"
	    response:setcontentlength(#keyAuth)
	    response:send(keyAuth)
	    return true
	 end
	 return false
      end
      dir=ba.create.dir(".well-known",1)
      dir:setfunc(wellknown)
      dir:insert()
      rspCB(true)
   end
   local function remove(rspCB)
      dir:unlink()
      rspCB(true)
   end
   return {insert=insert,remove=remove}
end

local function getCertCOFunc(job)
   local account,op=job.account,job.op
   local dnsch
   if op.ch then
      dnsch=op.ch.set and true
   else
      op.ch=httpChallengeIntf()
   end
   local function retErr(err) respErr(err,job.rspCB) end
   local ok,rsp,nonce,h -- ret values from ACME HTTP
   local http,dir -- ACME HTTP and directory listing
   http,dir,nonce=createAcmeHttp(op)
   if not http then return retErr(dir) end

   local newAccount,header,payload
   -- Create the accountKey (pem) and extract the private key and the
   -- public key (x,y) components
   local x,y
   if account.id and account.key then
      newAccount=false
      x,y=decodeEccPemKey(account.key)
   else
      newAccount=true
      tracep(false,5,"Creating new ACME account")
      account.key=account.key or createkey"$account"
      x,y=decodeEccPemKey(account.key)
      -- Prepare for new account request
      header={
	 nonce=nonce,
	 url=dir.newAccount,
	 alg='ES256',
	 jwk={
	    kty="EC",
	    crv="P-256",
	    x=x,
	    y=y,
	 }
      }
      payload={
	 termsOfServiceAgreed=true,
	 onlyReturnExisting=false,
	 contact={'mailto:'..account.email},
      }
      -- Send account request
      ok,rsp,nonce,h=http(dir.newAccount,jwtsign(account.key,payload,header))
      if not ok then return retErr(rsp) end
      account.id=h.location
   end

   -- Prepare the order
   header={nonce=nonce,alg='ES256',url=dir.newOrder,kid=account.id}
   payload={identifiers={{ type='dns',value=job.domain }}}
   -- Send order request
   ok,rsp,nonce,h=http(dir.newOrder,jwtsign(account.key,payload,header))
   if not ok then
      if newAccount==false then
	 account.id=nil
	 return getCertCOFunc(job)
      end
      return retErr(rsp)
   end
   local currentOrderURL=h.location
   local authURL=rsp.authorizations[1]
   local finalizeURL=rsp.finalize

   -- The authURL returns a list of possible challenges.
   ok,rsp,nonce=postAsGet(http,account,nonce,authURL)
   if not ok then return retErr(rsp) end
   local token,challengeUrl
   for _,ch in ipairs(rsp.challenges) do -- Find the HTTP challenge option
      if(not dnsch and ch.type=="http-01") or (dnsch and ch.type=="dns-01") then
	 -- Fetch the token and HTTP challenge URL
	 token,challengeUrl=ch.token,ch.url
	 break
      end
   end
   if not challengeUrl then
      return retErr(string.format("%s-01 challenge err",
				  dnsch and "dns" or "http"))
   end

   -- Canonical (sorted) JWK fingerprint (fp)
   local fp=string.format('{"crv":"P-256","kty":"EC","x":"%s","y":"%s"}',x,y)
   local thumbprint=ba.b64urlencode(ba.crypto.hash"sha256"(fp)(true))
   local keyAuth=token..'.'..thumbprint;
   local dnsRecord
   if dnsch then
      local dnsAuth=ba.b64urlencode(ba.crypto.hash"sha256"(keyAuth)(true))
      dnsRecord='_acme-challenge.'..(job.domain:find"^%*%." and job.domain:sub(3) or job.domain)
      op.ch.set(dnsRecord,dnsAuth,resumeCo,job.domain)
   else
      local tokenURL="acme-challenge/"..token
      op.ch.insert(tokenURL,keyAuth,resumeCo,job.domain)
   end
   ok,rsp=coroutine.yield()
   if not ok then return retErr(rsp or "Start: challenge API") end

   if dnsch then -- DNS challenge slow, nonce expires fast; need new nonce
      http,dir,nonce=createAcmeHttp(op)
   end

-- Initiate challenge
   header={nonce=nonce,alg='ES256',url=aue(challengeUrl),kid=account.id}
   payload=ba.b64urlencode"{}"
   --  http -> ACME will now call our 'wellknown' dir or checks DNS rec.
   ok,rsp,nonce=http(challengeUrl,jwtsign(account.key,payload,header))
   if not ok then return retErr(rsp) end
   local challengePollURL=rsp.url
   local cnt=0
   -- Loop and poll the 'challengePollURL'
   local mcnt=dnsch and 60 or 10
   while true do
      cnt=cnt+1
      if cnt > mcnt then ok,rsp=false,"Challenge timeout" break end
      ba.sleep(3000)
      ok,rsp,nonce=postAsGet(http,account,nonce,challengePollURL)
      if not ok then break end
      if rsp.status ~= "pending" and rsp.status ~= "processing" then
	 if rsp.status ~= "valid" then ok=false end
	 break
      end
   end
   op.ch.remove(resumeCo,dnsRecord,job.domain)
   local ok2,rsp2=coroutine.yield()
   if not ok then return retErr(rsp) end
   if not ok2 then return retErr(rsp2 or "End: challenge API") end

   -- Create the CSR
   local certtype={"SSL_CLIENT","SSL_SERVER"}
   local keyusage={"DIGITAL_SIGNATURE","KEY_ENCIPHERMENT"}
   local kop=op.rsa == true and { key="rsa",bits=op.bits} or {curve=op.curve or "SECP384R1"}
   local certKey=op.privkey or createkey(job.domain,kop) -- use key via option or new
   local csr=createcsr(certKey,job.domain,{commonname=job.domain},certtype,keyusage)
   -- Convert CSR to raw URL-safe B64
   header={nonce=nonce,alg='ES256',url=aue(finalizeURL),kid=account.id}
   csr=ba.b64urlencode(ba.b64decode(csr:match".-BEGIN.-\n%s*(.-)\n%s*%-%-"))
   payload={csr=csr}
   -- Send the CSR
   ok,rsp,nonce=http(finalizeURL,jwtsign(account.key,payload,header))
   if not ok then return retErr(rsp) end
   if rsp.status ~= "valid" then -- If not ready
      cnt=0
      -- Loop and poll the 'challengePollURL'
      while true do
	 cnt=cnt+1
	 if cnt > 10 then return retErr"CSR response timeout" end
	 ba.sleep(3000)
	 ok,rsp,nonce=postAsGet(http,account,nonce,currentOrderURL)
	 if not ok then return retErr(rsp) end
	 if rsp.status == "valid" then break end
      end
   end
   local cert,err=postAsGet(http,account,nonce,rsp.certificate,true)
   if not cert then return retErr(err) end
   job.rspCB(certKey,cert)
   return true
end


local function getCert(account,domain,rspCB,op)
   if op.acceptterms~=true then
      ba.thread.run(function() rspCB(nil,"No acceptterms") end)
      return
   end
   assert(type(domain) == 'string' and
	  type(account.email) == 'string' and type(rspCB) == 'function')
   op=op or {}
   if op.ch then
      assert(type(op.ch.remove) == "function")
      if op.ch.set then
	 assert(type(op.ch.set) == "function" and not op.ch.insert)
      else
	 assert(type(op.ch.insert) == "function" and not op.ch.set)
      end
   end
   local job={account=account,domain=domain,rspCB=rspCB,op=op,
      getCertCO=coroutine.create(getCertCOFunc)}
   local empty=#jobQ == 0
   table.insert(jobQ,job)
   jobs=jobs+1
   if empty then resumeCo(jobQ[1]) end
   return jobs
end

local function revokeCert(account,cert,rspCB,op)
   local http,dir,nonce=createAcmeHttp(op or {})
   local header={nonce=nonce,alg='ES256',url=dir.revokeCert,kid=account.id}
   local payload={certificate=
      ba.b64urlencode(ba.b64decode(cert:match".-BEGIN.-\n%s*(.-)\n%s*%-%-"))}
   local ok,rsp=http(dir.revokeCert,jwtsign(account.key,payload,header))
   if ok then
      rspCB(true)
   else
      respErr(rsp,rspCB)
   end
end

local function terms(op)
   local ok,dir=createAcmeHttp(op or {})
   return ok and dir.meta.termsOfService or "https://letsencrypt.org/"
end

local M
M={
   tpm=function(en)
      assert(tpm,"not enabled")
      if "boolean"==type(en) then te=en end
      return te
   end,
   setTPM=function(t) tpm=t te=true M.setTPM=nil end,
   terms=terms,
   cert=getCert,
   jobs=function() return jobs end,
   revoke=function(account,cert,rspCB)
      ba.thread.run(function() revokeCert(account,cert,rspCB) end) end,
   ahttp=createAcmeHttp,
   checkCert=function(check) checkCert=check end
}
return M
