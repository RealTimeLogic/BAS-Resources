local rtURL,rToken,rtokenB64,timer,httpOptions,zoneKey,serverIp,dKey
local fmt=string.format
local log=require"acme/log"
local checkCert=true
local lastEmsg

local cbFunctionT={}

local getTokenRunning=false

local function getToken()
   getTokenRunning=true
   local http=require"httpc".create(httpOptions)
   local _,err = http:request{method="HEAD",trusted=checkCert,url=rtURL,header={
	 ["X-Key"]=zoneKey,
	 ["X-Dev"]=dKey,
      }
   }
   local status = http:status()
   if status == 200 then
      local h = http:header()
      local token,exp = h['X-RefreshToken'], ba.datetime(h["X-Expires"])
      local now = ba.datetime"NOW"
      if token and exp and exp > now then
	 rToken,rtokenB64 = ba.b64decode(token),token
	 local s = ba.socket.http2sock(http)
	 local ip = s:peername()
	 s:close()
	 serverIp = ip:find("::ffff:",1,true) == 1 and ip:sub(8,-1) or ip
	 for func in pairs(cbFunctionT) do func(rToken,rtokenB64,serverIp) end
	 timer:reset((exp-now)/1000000)
	 getTokenRunning=false
	 return;
      end
      lastEmsg=fmt("Not a valid server: %s", rtURL)
      log.error(lastEmsg)
   elseif status == 404 then
      lastEmsg=fmt("ZoneKey %s is invalid", zoneKey)
      log.error(lastEmsg)
   else
      if "cannotresolve" == err then
	 lastEmsg = "Cannot connect to "..rtURL
      else
	 lastEmsg=fmt("Failed %s, invalid HTTP response: %s",
		      rtURL, err or status)
	 log.error(lastEmsg)
      end
   end
   getTokenRunning=false
   timer:reset(5000) -- Keep trying
end

--This function blocks
local function configure(domain, zKey, httpOp)
   zoneKey = zKey
   httpOptions=httpOp or {}
   rtURL = fmt("https://%s/rtoken.lsp",domain)
   if not timer then
      timer=ba.timer(function() if not getTokenRunning then ba.thread.run(getToken) end return true end)
      timer:set(5000)
   end
   getToken()
   if rToken then return rToken,rtokenB64,serverIp end
   if not lastEmsg then lastEmsg="unknown" end
   return nil, lastEmsg
end

local function regEvent(cbFunction, remove)
   cbFunctionT[cbFunction] = not remove and true or nil
   if remove ~= true and rToken then
      ba.thread.run(function() cbFunction(rToken,rtokenB64,serverIp) end)
   end
end

return {
   configure=configure,
   event=regEvent,
   setDKey=function(key) dKey=key end,
   getnew=function() ba.thread.run(getToken) end,
   emsg=function() return lastEmsg end,
   checkCert=function(check) checkCert=check end
}
