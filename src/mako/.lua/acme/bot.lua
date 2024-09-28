local acme=require"acme/engine"
local log=require"acme/log"
local fmt=string.format

local optionT={production=true}
local status={}

local hio,init,M,loadcerts,installcerts,loadcertsOnce

init=function(io,ic)
   hio = io or ba.openio"home"
   assert(hio,"No IO")
   if not hio:stat"cert" and not hio:mkdir"cert" then
      error("Cannot create directory "..hio:realpath"cert")
   end
   installcerts = ic or mako and mako.loadcerts
   assert(installcerts, "No installcerts")
   init=function() end
   M.init=init
end


local rw=require"rwfile"
local function jfile(name,tab)
   init()
   name=fmt("cert/%s.json",name)
   local ok,err=rw.json(hio,name,tab)
   if not ok and tab then log.error("Writing %s failed: %s",name,err) end
   return ok,err
end
local function cfile(name,cert)
   init()
   name=fmt("cert/%s.pem",name)
   local ok,err=rw.file(hio,name,cert)
   if not ok and cert then log.error("Writing %s failed: %s",name,err) end
   return ok,err
end


local function getproxy(op)
   pcall(function()
	    local pT=require"loadconf".proxy
	    op.proxy,op.proxyport,op.socks=pT.name,pT.port,pT.socks
	    op.proxyuser,op.proxypass=pT.proxyuser,pT.proxypass
	 end)
   return op
end

local function renewAllowed() return true end -- Default

-- ASN1 time format: YY[YY]MMDDHHMMSSZ
local function time2renew(asn1exptime)
   local exptime = ba.parsecerttime(asn1exptime)
   -- Renew no later than 22 days before exp.
   return exptime == 0 or (exptime - 1900800) < os.time()
end

local function getKeyCertNames(domain)
   return fmt("cert/%s.key.pem",domain),fmt("cert/%s.cert.pem",domain)
end

local function getCert(domain)
   return cfile(domain..".key"),cfile(domain..".cert")
end

local function updateCert(domain,key,cert)
   local domainsT=jfile"domains" or {}
   domainsT[domain]=ba.parsecert(
	 ba.b64decode(cert:match".-BEGIN.-\n%s*(.-)\n%s*%-%-")).tzto
   jfile("domains",domainsT)
   cfile(domain..".key",key)
   cfile(domain..".cert",cert)
   loadcerts()
   return domainsT
end


local function renew(accountT,domain,accepted)
   status.err=nil
   local function rspCB(key,cert)
      status={domain=domain}
      if key then
	 updateCert(domain,key,cert)
	 accountT.production = optionT.production
	 jfile("account",accountT)
	 log.info("%s renewed",domain)
	 optionT.renewed(domain,key,cert)
      else
	 status.err=cert
	 log.error("renewing %s failed: %s",domain,cert)
      end
   end
   -- if previously accepted
   if accepted then optionT.acceptterms=true end
   optionT.privkey=getCert(domain)
   acme.cert(accountT,domain,rspCB,optionT)
end

local function renOnNotFund(domain, force)
   if renewAllowed(domain) or force then
      renew(jfile"account",domain, true)
   end
end

loadcerts=function(domainsT)
   domainsT=domainsT or jfile"domains" or {}
   local keys,certs={},{}
   for domain, exptime in pairs(domainsT) do
      if #exptime > 0 then
	 local k,c=getKeyCertNames(domain)
	 if hio:stat(k) and hio:stat(c) then
	    table.insert(keys,k)
	    table.insert(certs,c)
	 else
	    log.error("%s not found, recreating...",hio:stat(k) and c or k)
	    ba.thread.run(function() renOnNotFund(domain, true) end)
	 end
      end
   end
   if #keys > 0 then
      installcerts(keys,certs)
      return true
   end
   return false
end

loadcertsOnce=function(domainsT) loadcertsOnce=function() return false end return loadcerts(domainsT) end


local function check(forceUpdate)
   if acme.jobs() > 0 then
      log.info("Cannot check certs: acme busy")
      return true
   end
   local domainsT=jfile"domains"
   local accountT=jfile"account"
   if not domainsT then log.error("Cannot open domains.json") return end
   if not accountT then log.error("Cannot open account.json") return end
   if accountT.production ~= optionT.production then
      forceUpdate=true
   end
   for domain,exptime in pairs(domainsT) do
      if forceUpdate or (renewAllowed(domain) and time2renew(exptime)) then
	 renew(accountT,domain,#exptime > 0)
      end
   end
   return true
end

local function configure(email,domains,op)
   optionT=getproxy(op or {})
   assert((not email or type(email)=='string') and
	  (not domains or ((type(domains)=='table' and
	   type(domains[1])=='string'))),
	  "Invalid args or 'acme' table")
   optionT.renewed=optionT.renewed or function() end
   local accountT=jfile"account" or {}
   if email and accountT.email ~= email then
      accountT.email,accountT.id=email,nil
      jfile("account",accountT)
   end
   if not domains then return true end
   local oldDomsT=jfile"domains" or {}
   local newDomsT={}
   for _,dn in ipairs(domains) do
      newDomsT[dn]=oldDomsT[dn] or "" -- renew-date or new
   end
   if optionT.cleanup then
      for dn in pairs(oldDomsT) do
	 if not newDomsT[dn] then
	    local k,c=getKeyCertNames(dn)
	    hio:remove(k)
	    hio:remove(c)
	 end
      end
   end
   if not optionT.noDomCopy then -- Set by acmedns : auto update
      jfile("domains",newDomsT)
   end
   return true
end


local systemDateChecked
local function systemDateOK()
   local _,_,date=ba.version()
   local time=os.time()+86400
   if time < ba.parsedate("Mon, "..date:gsub("^(%w+)%s*(%w+)","%2 %1")) then
      if not systemDateChecked then
	 systemDateChecked=true
	 log.error(fmt("'%s' %s",ba.datetime(time),"is in the past. Disabling TLS certificate check!"))
      end
      acme.checkCert(false)
      return false
   else
      acme.checkCert(true)
   end
end

local timer
local function autoupdate(activate,force)
   if activate then
      systemDateOK()
      -- Thread not needed, we just want to defer 'check'
      if jfile"domains" then ba.thread.run(function() check(force) end) end
      -- Check activated, but signal that auto update already active */
      if timer then return false end
      timer=ba.timer(check)
      timer:set(24*60*60*1000) -- once a day
   else
      if not timer then return false end
      timer:cancel()
      timer=nil
   end
   loadcertsOnce()
   return true
end

local function revokeCert(domain, rspCB, op)
   local _,cert=getCert(domain)
   if cert then
      acme.revoke(jfile"account", cert, rspCB, op)
   else
      ba.thread.run(function() rspCB(nil, "Cert not found") end)
   end
end


local function getcfg()
   local aT = require"loadconf".acme
   assert(type(aT.email) == 'string', "acme: Invalid email address")
   assert(aT.domains and type(aT.domains[1])=='string',"acme: Invalid domain")
   return aT,{production=aT.production,rsa=aT.rsa,bits=aT.bits,
      acceptterms=true,info=aT.info}
end

-- Called by .config if acme options set
local function cfgFileActivation()
   local aT,op=getcfg()
   configure(aT.email,aT.domains,op)
   autoupdate(true)
end

local function account()
   return jfile"account",jfile"domains"
end


pcall(function() require"seed" end) -- seed sharkssl

M={
   init=init,
   account=account,
   start = function() return autoupdate(true) end,
   configure=configure,
   getemail=function() return (jfile"account" or {}).email end,
   getdomains=function() return jfile"domains" or {} end,
   status=function(clear)
	     local e = status.err
	     if clear then status.err=nil end
	     return acme.jobs(), status.domain, e
	  end,
   getCert=getCert,
   getproxy=getproxy,
   priv={ -- private: non documented: used by other acme modules
      time2renew=time2renew,
      updateCert=updateCert,
      autoupdate=autoupdate,
      getcfg=getcfg,
      jfile=jfile,
      loadcert=function() return loadcertsOnce() end,
      setRenewAllowed=function(func) renewAllowed=func end,
      error=function(msg) log.error("%s",msg) status={err=msg} end,
   },
   revoke=revokeCert,
   systemDateOK=systemDateOK,
   cfgFileActivation=cfgFileActivation -- Called by .config if acme options
}

return M
