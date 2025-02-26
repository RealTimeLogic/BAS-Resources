local fmt,jdecode=string.format,ba.json.decode
local msKeysT,http,openidT,downloadKeysTimer={},require"httpm".create{trusted=true}
local jwt=require"jwt"
local function log(x,...) xedge.elog({ts=true},"SSO: "..x,...) end

local aesencode,aesdecode=(function()
   local aeskey=ba.aeskey(32)
   return function(data) return ba.aesencode(aeskey,data) end,
   function(data) return ba.aesdecode(aeskey,data) end
end)()

-- Xedge login page
local function getRedirUri(cmd)
   return cmd:url():match"^https?://[^/]+".."/rtl/login/"
end

local function downloadKeys()
   local url=fmt("%s%s%s","https://login.microsoftonline.com/",openidT.tenant,"/discovery/keys")
   local d=ba.b64decode
   local t,err=http:json(url,{})
   if t then
      msKeysT={}
      for _,x in ipairs(t and t.keys or {}) do
	 msKeysT[x.kid] = {n=d(x.n),e=d(x.e)}
      end
      return true
   end
   log("Cannot download signing keys %s: %s",url,err)
end

local function startKeysDownload()
   if (os.time()+86400) < xedge.compileTime then
      local cb
      cb=function()
	 xedge.event("sntp",cb,true)
	 ba.thread.run(function() startKeysDownload() end)
      end
      xedge.event("sntp",cb)
      log"Waiting for SNTP event"
      return
   end
   if downloadKeysTimer then downloadKeysTimer:cancel() end
   local oneDay=24*60*60*1000
   downloadKeysTimer=ba.timer(function()
      ba.thread.run(function() downloadKeysTimer:reset(downloadKeys() and oneDay or 60000) end)
      return true
   end)
   downloadKeysTimer:set(oneDay,true,true)
   if mako then mako.onexit(function() downloadKeysTimer:cancel() end,true) end
end


-- JWT: decode and verify compact format (header.payload.signature) with RSA signature
local function jwtDecode(token)
   local err
   if not next(msKeysT) then return nil, "Waiting for signing keys to be downloaded" end
   local ok,header,payload=jwt.verify(token,msKeysT,true)
   if true ~= ok then return nil, header end
   return header,payload
end

local function init(idT)
   openidT=idT
   startKeysDownload()
   local function loginCallback(cmd)
      local err,ecodes,rspT -- string,array,table
      local data=cmd:data()
      local code=data.code
      if code then
	 local status,d = http:post(fmt("%s%s%s",
	   "https://login.microsoftonline.com/",idT.tenant,"/oauth2/v2.0/token"),
	   {
	      client_id=idT.client_id,
	      client_secret=idT.client_secret,
	      code=code,
	      redirect_uri=getRedirUri(cmd),
	      grant_type="authorization_code"
	   })
	 rspT = jdecode(d)
	 if status == 200 and rspT and rspT.id_token and rspT.access_token then
	    local header,payload=jwtDecode(rspT.id_token)
	    if header then
	       local now=ba.datetime"NOW"
	       local dt = ba.datetime(aesdecode(payload.nonce or "") or "MIN")
	       if (dt + {mins=10}) > now and ba.datetime(payload.nbf) <= now and ba.datetime(payload.exp) >= now then
		  if payload.aud == idT.client_id then
		     return header,payload,rspT.access_token
		  end
		  err='Invalid "aud" (Application ID)'
	       else
		  err="Login session expired"
	       end
	    else
	       err=payload
	    end
	 elseif rspT and rspT.error_description then
	    err=rspT.error_description
	 else
	    log("Error response %d, %s",status, tostring(d))
	 end
      elseif data.error_description then
	 err=data.error_description
      end
      err = err or "Not a JWT response"
      ecodes=rspT and rspT.error_codes
      return nil,err,ecodes
   end --loginCallback

   local function sendLoginRedirect(cmd)
      local state= idT.state == "url" and ba.b64urlencode(cmd:url()) or "local"
      local nonce=aesencode(ba.datetime"NOW":tostring())
      cmd:sendredirect(fmt("%s%s%s%s%s%s%s%s%s%s%s%s%s%s",
			   "https://login.microsoftonline.com/",idT.tenant,"/oauth2/v2.0/authorize?",
			   "client_id=",idT.client_id,
			   "&response_type=code",
			   "&redirect_uri=",ba.urlencode(getRedirUri(cmd)),
			   "&response_mode=form_post",
			   "&scope=openid+profile",
			   "&state=",state,
			   "&nonce=",ba.urlencode(nonce)))
   end

   return {
      sendredirect=sendLoginRedirect,
      login=loginCallback,
      decode = function(token) return jwtDecode(token) end
   }
end -- init

local function validate(idT)
   local err,desc
   local status,data = http:post(fmt("%s%s%s",
      "https://login.microsoftonline.com/",idT.tenant,"/oauth2/v2.0/token"),
      {
	 client_id=idT.client_id,
	 client_secret=idT.client_secret,
	 grant_type="client_credentials",
	 scope="https://graph.microsoft.com/.default",
      })
   local rspT = jdecode(data)
   if rspT then
      if not rspT.token_type then
	 err,desc=rspT.error,rspT.error_description
      end
   else
      err=fmt("Error response %s, %s",tostring(status), tostring(data))
   end
   if not err then return true end
   return nil,err,desc
end

return {init=init,validate=validate}
