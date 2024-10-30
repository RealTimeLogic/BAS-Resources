local ab=require"acme/bot"
local rt=require"acme/rtoken"
local log=require"acme/log"
local abp=ab.priv -- Import private funcs
local fmt=string.format
local b64Enc=ba.b64urlencode
local checkCert=true
local revcon,revconTimer -- set if Reverse Connection enabled
local dnsResolveTmo = 120000 -- 2 mins
local getZoneToken
local zoneKey,zoneSecret,refreshToken
local serverName,serverIp,commandURL

local httpOptions
local function setHttpOptions(op)
   httpOptions = mako and ab.getproxy(op) or op
end

-- Can optionally be set using D.init
local function sendEmail(msg)
   if mako and mako.daemon then
      local op={flush=true}
      mako.log(nil, op)
      op.subject="Set ACME DNS TXT Record"
      mako.log(msg, op)
   end
end

local function calculateSecret()
   if not refreshToken then return nil,"No X-RefreshToken" end
   local token,hash = getZoneToken(serverIp, refreshToken)
   return b64Enc(token),b64Enc(hash)
end

local function setRevConToken()
   if revcon then
      local kT=abp.jfile"devkey"
      local token,hash = calculateSecret()
      if kT and kT.key and token then
	 revcon:token{
	    ['X-Key'] = zoneKey,
	    ['X-Command']="RevCon",
	    ['X-Token']=token,
	    ['X-Hash']=hash,
	    ["X-RefreshToken"]=b64Enc(refreshToken),
	    ["X-Dev"]=kT.key
	 }
      end
   end
end

local function newRefreshToken(rToken,_,sIp)
   refreshToken,serverIp=rToken,sIp
   setRevConToken()
end

local function checkKey(key,level)
   if type(key) ~= 'string' or #key ~= 64 then
      error("Invalid zone key and/or secret",level)
   end
end

local function tryLoadTokengenModules()
   local ok,m=pcall(function() return require"tokengen" end)
   if not ok then
      ok,m=pcall(function() return require"etokengen" end)
   end
   return ok and m -- else nil
end

local function checkAndCfg(level)
   if not ab.systemDateOK() then
      rt.checkCert(false)
      checkCert=false
   end
   if zoneKey then
      checkKey(zoneKey,level+1)
      checkKey(zoneSecret,level+1)
      local crypto=ba.crypto
      local zkT={}
      local schar=string.char
      for x in zoneKey:gmatch("%x%x") do table.insert(zkT, schar(tonumber(x,16))) end
      local zkbin=table.concat(zkT)
      getZoneToken=function(ip,token)
	 local rnd=ba.rndbs(32)
	 local dk = crypto.PBKDF2("sha256",zoneSecret,zkbin,1000,32)
	 token=crypto.hash"sha256"(rnd)(dk)(ip)(token)(true,"binary")
	 return token,rnd
      end
   else
      local m = tryLoadTokengenModules()
      if not m then error("Zone key not set") end
      getZoneToken=m.token
      serverName,zoneKey=m.info()
      local sbyte=string.byte
      zoneKey=zoneKey:gsub(".",function(x) return fmt("%02X",sbyte(x)) end)
   end
   if not serverName then error"'servername' not set" end
   commandURL = fmt("https://%s/command.lsp",serverName)
   rt.event(newRefreshToken)
   local x,err = rt.configure(serverName,zoneKey,httpOptions)
   log.info(fmt("DNS server name: %s",serverName))
   if x then return true end
   abp.error(err)
   return nil,err
end

local function autoconf(level)
   if not getZoneToken then return checkAndCfg(level+1) end
   return true
end

local function configure(op,level)
   zoneKey,zoneSecret,serverName = nil,nil,nil
   if op.key then
      zoneKey,zoneSecret=op.key,string.upper(op.secret or "")
   end
   serverName = op.servername
   local ok,err=checkAndCfg(level and level+1 or 3)
   return ok,err
end


-- Lock/release logic for acme.lua's challenge CBs (rspCB).  The
-- function aborts any action if called with lock(nil,nil,true) and
-- only D.auto() and D.manual calls it this way.
local lock -- function set below
do
   local rspFailedCB
   local savedCleanupOnErrCB
   local emsg="Cancelling pending DNS job"
   lock=function(rspCB,cleanupOnErrCB,release)
      if rspFailedCB and release then
	 abp.error(emsg)
	 rspFailedCB()
	 savedCleanupOnErrCB()
      end
      if rspCB then
	 savedCleanupOnErrCB=cleanupOnErrCB
	 rspFailedCB=function() rspCB(false,emsg) end
      else
	 rspFailedCB,savedCleanupOnErrCB=nil,nil
      end
   end
end


local manualMode,active=false,false
local function checkM()
   if manualMode ~= true then error("Not in manual mode", 3) end
end
local function noActivation() checkM() return nil, "Challenge not active" end
local D={activate=noActivation, status=noActivation}

-- acme.lua's 'set' challenge CB for manual operation
local setManual
setManual=function(dnsRecord,dnsAuth,rspCB)
   if dnsRecord then -- activate
      -- call chain: acme.lua -> setManual
      local msg=string.format("\tRecord name:\t%s\n\tRecord data:\t%s",
			      dnsRecord, dnsAuth)
      D.status = function() return {record=dnsRecord,data=dnsAuth,msg=msg} end
      D.recordset=function() setManual() lock() rspCB(true) return true end
      lock(rspCB, setManual)
      log.log(0,"Set DNS TXT Record:\n"..msg)
      sendEmail(msg,dnsRecord,dnsAuth)
   else -- release
      -- call chain D.recordset() -> setManual OR
      -- D.get -> lock -> savedCleanupOnErrCB=setManual
      D.status,D.recordset=noActivation,noActivation
   end
end


local function sockname(http)
   local ip,_,is6=http:sockname()
   if is6 and ip:find("::ffff:",1,true) == 1 then
      ip=ip:sub(8,-1) -- IPv4-mapped IPv6 address to IPv4
   end
   return ip
end


-- activateAuto code below
local function createHttp()
   if not refreshToken then return nil, -1, "No X-RefreshToken" end
   local http=require"httpc".create(httpOptions)
   local function xhttp(command,hT,nolog)
      hT=hT or {}
      hT['X-Key'] = zoneKey
      local token,hash = calculateSecret()
      if not token then
	 local err = rt.emsg() or hash
	 abp.error(fmt("Err: %s",err))
	 return nil, -2, err
      end
      hT['X-Token'],hT['X-Hash']=token,hash
      hT['X-Command'],hT["X-RefreshToken"]=command,b64Enc(refreshToken)
      local ok,err=http:request{
	 trusted=checkCert,
	 url=commandURL,
	 method="GET",
	 size=0,
	 header=hT
      }
      if not ok then
	 abp.error(fmt("%s Err: %s\nURL: %s",
		       httpOptions.proxy and "Proxy" or "HTTP",err,commandURL))
      end
      hT = http:header()
      local status = http:status()
      if status ~= 201 then
	 if status == 403 then rt.getnew() end
	 if not nolog and status and hT then
	    abp.error(fmt("HTTP status=%d: %s\nURL: %s",status,hT["X-Reason"], commandURL))
	 end
	 return nil, status, (hT and hT["X-Reason"] or err or fmt("HTTP status=%d",status))
      end
      return hT
   end
   local hT,s,e=xhttp"GetWan"
   if hT then
      return xhttp, hT['X-IpAddress'], sockname(http)
   end
   return nil,s,e
end

local function register(http,ip,subdom,info)
   local hT={["X-IpAddress"]=ip,["X-Name"]=subdom,["X-Info"]=info}
   hT=http("Register", hT)
   if hT then
      local devKey,domain=hT['X-Dev'],hT['X-Name']
      assert(devKey and domain)
      abp.jfile("domains",{[domain]=""})
      local kT={key=devKey}
      abp.jfile("devkey", kT)
      return kT,domain
   end
end

local function isreg()
   local cnt,http,wan,sockn=0
   while not http do
      if cnt > 5 then break end
      cnt=cnt+1
      http,wan,sockn=createHttp()
      if not http then ba.sleep(1000) end
   end
   if not http then return nil,wan,sockn end
   local kT=abp.jfile"devkey"
   if kT and kT.key then
      local hT={["X-Dev"]=kT.key}
      hT=http("IsRegistered",hT,true)
      if hT then
	 rt.setDKey(kT.key)
	 return hT["X-Name"],wan,sockn,ab.getemail(),kT.key
      end
   end
   return false,wan,sockn
end

local function available(domain)
   local http,wan,sockn=createHttp()
   if not http then return nil,wan,sockn end
   local hT,status,err={["X-Name"]=domain}
   hT,status,err=http("IsAvailable", hT)
   if hT then
      return (hT["X-Available"] == "yes" and true or false),wan,sockn
   end
   return nil,status,err
end

local function closeRevcon()
   if revcon then
      revcon:close()
      revconTimer:cancel()
      revcon=nil
   end
end

local function activateRevcon()
   if not revcon then
      if ba.revcon then
	 revcon=ba.revcon{shark=ba.sharkclient(),url=commandURL}
	 if mako then mako.onexit(function() closeRevcon() end, true) end
	 setRevConToken()
	 local function check()
	    local s=revcon:status()
	    if 202 ~= s and s > 0 then rt.getnew() end
	    return true
	 end
	 revconTimer=ba.timer(check)
	 revconTimer:set(60000)
      else
	 abp.error("No ba.revcon(): Reverse Connection not enabled");
      end
   end
end


local function auto(email,domain,op)
   local function tryagain(emsg)
      abp.error("auto failed: "..tostring(emsg or "?"))
      ba.timer(function() ba.thread.run(function() auto(email,domain,op) end) end):set(60000,true)
   end
   local http,wan,sockn=createHttp()
   if wan == sockn then
      active=false
      return abp.error(fmt("Public IP address %s equals local IP address",wan))
   elseif not http then
      abp.error(sockn or "?")
      return tryagain(sockn)
   end
   local kT=abp.jfile"devkey"
   if kT and kT.key then
      local hT={["X-Dev"]=kT.key}
      if http("IsRegistered",hT,true) then
	 rt.setDKey(kT.key)
	 hT["X-IpAddress"]=sockn
	 local rspHT=http("SetIpAddress",hT,true)
	 if rspHT then
	    local regname=rspHT['X-Name']
	    local curname = next(abp.jfile"domains" or {}) or ""
	    if regname ~= curname then
	       abp.jfile("domains",{[regname]=""})
	    end
	    domain=regname
	 else
	    return tryagain("SetIpAddress failed")
	 end
      else
	 kT,domain=register(http,sockn,domain,op.info)
      end
   else
      kT,domain=register(http,sockn,domain,op.info)
   end
   if kT then
      if op.revcon then activateRevcon() end
   else
      abp.error("No device key")
      active=false
      return  -- err
   end
   ----- Acmebot set/remove DNS record CBs
   local function set(dnsRecord, dnsAuth, rspCB)
      local hT={
	 ["X-Dev"]=abp.jfile"devkey".key,
	 ["X-RecordName"]=dnsRecord,
	 ["X-RecordData"]=dnsAuth,
	 ["X-DnsResolveTmo"]=tostring(dnsResolveTmo)
      }
      local timer
      lock(rspCB, function() timer:cancel() end)
      if http("SetAcmeRecord",hT) then
	 timer=ba.timer(function() lock() rspCB(true) end)
	 timer:set(dnsResolveTmo)
      else
	 rspCB(false,"SetAcmeRecord failed")
      end
   end
   -----
   local function remove(rspCB)
      http("RemoveAcmeRecord",{["X-Dev"]=abp.jfile"devkey".key})
      rspCB(true)
   end
   -----
   op.ch={set=set,remove=remove}
   op.noDomCopy,op.cleanup=true,true
   op.shark=httpOptions.shark
   ab.configure(email,{domain},op)
   abp.autoupdate(true)
end


function D.isreg(cb)
   if type(cb) ~= "function" then cb=nil end
   local m = tryLoadTokengenModules()
   if not m then error("Zone key not set") end
   local function run()
      local ok,err=autoconf(2)
      if not ok then
	 if cb then cb(nil,-1,err) end
	 return nil,-1,err
      end
      if not cb then
	 local status,wan,sockn,email,key
	 cb=function(st,w,sn,e,k) status,wan,sockn,email,key=st,w,sn,e,k end
	 cb(isreg())
	 return status,wan,sockn,email,key
      end
      cb(isreg())
   end
   local function testCon()
      local s <close> = ba.socket.connect(m.info(),443)
      if s then
	 run()
      else
	 ba.timer(function() ba.thread.run(testCon) end):set(30000,true)
      end
   end
   if cb then ba.thread.run(testCon) else return run() end
end


function D.available(domain,cb)
   if type(cb) ~= "function" then cb=nil end
   local ok,err=autoconf(2)
   if not ok then
      if cb then cb(nil,err) end
      return nil,err
   end
   local function action() cb(available(domain)) end
   if not cb then
      local status,wan,sockn
      cb=function(st,w,sn) status,wan,sockn=st,w,sn end
      action()
      return status,wan,sockn
   end
   ba.thread.run(action)
end

function D.auto(email,domain,op)
   local reactivate=false
   if not domain then
      if type(email) == "table" and not op then op=email end
      email=ab.getemail()
      if not email then
	 active=false
	 return nil,"not previously activated"
      end
      op.acceptterms=true
      reactivate=true
   end
   if not op.revcon then closeRevcon() end
   if type(op) ~= "table" or op.acceptterms ~= true then
      error("'acceptterms' not set",2)
   end
   assert(type(email) == "string")
   if active then return email end
   manualMode,active=false,true
   local function run()
      abp.autoupdate(false)
      lock(nil,nil,true) -- release
      ba.thread.run(function() auto(email,domain,op) end)
   end
   if reactivate then
      D.isreg(function(name) if name then run() end end)
   else
      local ok,err=autoconf(2)
      if not ok then return nil,err end
      run()
   end
   return email
end

function D.manual(email,domain,op)
   manualMode,active=true,true
   abp.autoupdate(false)
   lock(nil,nil,true) -- release
   op.ch={set=setManual,remove=function(rspCB) rspCB(true) end}
   op.shark=httpOptions.shark
   ab.configure(email,{domain},op)
   abp.autoupdate(true, true)
   return true
end

function D.loadcert() return abp.loadcert() end
function D.active() return active and (manualMode and "manual" or "auto") end
function D.configure(op) return configure(op or {}, 4) end
function D.token() return tryLoadTokengenModules() end

-- Called by .config if acme options
function D.cfgFileActivation()
   local aT,op=abp.getcfg()
   if aT.challenge.servername ~= "manual" then
      configure(aT.challenge)
      op.revcon=aT.challenge.revcon
      D.auto(aT.email,aT.domains[1],op)
   else
      local d=abp.jfile"domains"
      local dn=d and next(d)
      if dn and ab.hascert(dn) then
	 D.loadcert()
      else
	 D.manual(aT.email,aT.domains[1],op)
      end
   end
end

function D.init(op,sm)
   if op then setHttpOptions(op) end
   if sm then
      assert(type(sm) == 'function', 'arg #2 must be func.')
      sendEmail=sm
   end
end

setHttpOptions{}

return D
