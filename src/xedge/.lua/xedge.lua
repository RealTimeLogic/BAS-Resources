require"wfs" -- Install function ba.create.wfs

local function trim(s) return s:gsub("^%s*(.-)%s*$", "%1") end
local production=true -- Let's Encrypt
local sfind,ssub,sbyte,sfmt=string.find,string.sub,string.byte,string.format
local dtraceback=debug.traceback
local jencode,jdecode=ba.json.encode,ba.json.decode
local startAcmeDns -- func
local xedgeEvent -- = _XedgeEvent
local smtp -- smtp settings, a table, used by sendmail
local openid -- Single Sign On settings, a table used by the ms-sso module, set by openidDec
local authRealm="Xedge"
local ios=ba.io()
local nodisk=false -- if no DiskIo
ios.vm=nil
do -- Remove virtual disks from windows to prevent DAV lock if url=localhost
   local t={}
   for name,io in pairs(ios) do
      local xio
      local type,plat=io:resourcetype()
      if "windows" == plat and not io:realpath"" then
	 xio=ba.mkio(io,"/c/")
      end
      t[name]=xio or io
   end
   ios=t
end

local function log(fmt,...)
   local msg=sfmt("Xedge: "..fmt, ...)
   tracep(false,5,msg)
   return msg
end


local xedge={
   cfg={apps={},userdb={},elog={subject="Xedge Log",maxbuf=10000,maxtime=24,enablelog=true,smtp=false}},
   apps={},
   log=log,
   trim=trim
}
local G=_G
G.xedge=xedge
local apps=xedge.apps
local appsCfg=xedge.cfg.apps
local userdb=xedge.cfg.userdb

function xedge.file(io,name,data)
   local fp,ret,err
   if data then
      fp,err=io:open(name,"w")
      if fp then ret,err = fp:write(data) end
   else
      fp,err=io:open(name)
      if fp then ret=fp:read"*a" end
   end
   if fp then fp:close() end
   return ret,err
end
local file=xedge.file
function xedge.json(io,name,tab)
   if tab then
      return file(io,name,jencode(tab))
   end
   local ret,err=file(io,name)
   if ret then
      -- If: includes UTF-8 BOM.
      if sbyte(ret,1) == 0xEF and sbyte(ret,2) == 0xBB and sbyte(ret,3) == 0xBF then
	 ret=ret:sub(4)
      end
      ret=jdecode(ret)
      if not ret then err="jsonerr" end
   end
   return ret,err
end
-- Must be after the above xedge.json
pcall(function() xedge.portal=require"acme/dns".token().info() end)

local fakeTime=(function()
   local bv,lv,date=ba.version()
   local tm=ba.parsedate("Mon, "..date:gsub("^(%w+)%s*(%w+)","%2 %1"))
   xedge.compileTime=tm
   return function() tm=tm+1 return tm end
end)()

local ioStat={mtime=fakeTime(),size=0,isdir=true}

-- A recursive directory iterator
function recDirIter(io,curPath)
   local name
   local co
   local doDir
   function doDir(path)
      curPath=path
      for file,isdir in io:files(path, true) do
	 if "." ~= file and ".." ~= file then
	    if isdir then
	       if #path > 0 then doDir(path.."/"..file) else doDir(file) end
	       curPath=path
	    else
	       name=file
	       coroutine.yield()
	    end
	 end
      end
   end
   co=coroutine.create(
     function()
	doDir(curPath)
	name=nil
	curPath=nil
	coroutine.yield()
     end
  )
   return function()
      coroutine.resume(co)
      return curPath, name
   end
end

-- Pretty print app cfg table
local function app2json(app)
   local j= jencode(app):gsub("[{,]","%1\n   "):gsub("}","\n}")
   return j
end

-- Returns app's config table or default if not set
local function getJsonAppCfg(ion)
   return app2json(appsCfg[ion] or {running=false})
end

local function sendmail(m,s)
   m = m or {}
   s = s or smtp
   -- copy smtp settings to new table
   local cfg={server=s.server,port=s.port}
   if s.user and #s.user > 0 then
      cfg.user=s.user
      cfg.password=s.password
      if s.connsec == "tls" then
	 cfg.shark=ba.sharkclient()
      elseif s.connsec == "starttls" then
	 cfg.starttls=true
	 cfg.shark=ba.sharkclient()
      end
   end
   -- Create send mail object
   if not socket or not socket.mail then require"socket.mail" end
   local mail=socket.mail(cfg)
   -- Create send mail config object
   cfg={}
   for k,v in pairs(m) do
      cfg[k]=v
   end
   -- Set defaults so we can use sendmail without params.
   cfg.from = m.from or s.email
   cfg.to = m.to or s.email
   cfg.subject = m.subject or xedge.cfg.elog.subject or "Xedge"
   if not m.body and not m.htmlbody and not m.txtbody then
      cfg.body = "Xedge"
   end
   local ok,err=mail:send(cfg)
   if not ok then log("Sending email to %s failed: %s",cfg.to,err) end
   return ok,err
end

local elogInit --Func below called once by xedge.init
do -- elog
   local tlConnected=false
   local msglist={}
   local msize=0
   local timer,flushing
   local function flush(op, send2log)
      flushing=false
      if timer then
	 timer:cancel()
	 timer=nil
      end
      msize=0
      local data=table.concat(msglist,"\n")
      if #data > 0 then
	 msglist={}
	 if send2log then
	    log("%s",data)
	 else
	    op=op or {}
	    op.body=data
	    ba.thread.run(function() sendmail(op) end)
	 end
      end
   end
   xedge.eflush=flush

   local function setTimer(op,tmo)
      if flushing then return end
      if timer then timer:cancel() end
      timer=ba.timer(function() flush(op) end)
      timer:set(tmo)
   end

   function xedge.elog(op,fmt,...)
      if "table" ~= type(op) then
	 fmt=op
	 op={}
      end
      local cfg=xedge.cfg.elog
      if cfg.enablelog and cfg.smtp and not tlConnected then
	 local msg=sfmt(fmt, ...)
	 if op.ts then msg = os.date("%H:%M: ",os.time())..msg end
	 table.insert(msglist,msg)
	 msize=msize+#msg
	 if op.flush then
	    setTimer(op,30000)
	    flushing=true
	 elseif timer then
	    if msize > cfg.maxbuf then flush(op) end
	 else
	    setTimer(op,cfg.maxtime*3600000)
	 end
	 return msg
      end
      return log(fmt,...)
   end
   local orgErrh
   local function errorh(emsg, env)
      local cfg=xedge.cfg.elog
      if cfg.enablelog and cfg.smtp and not tlConnected then
	 local e
	 if env and env.request then
	    e=sfmt("LSP Err: %s\nURL: %s\n", emsg, env.request:url())
	 else
	    e=sfmt("Lua Err: %s\n", emsg)
	 end
	 xedge.elog({flush=true, subject="Xedge: Lua error"},"%s",e)
      end
      ba.thread.run(function() xedgeEvent("error",emsg) end)
      orgErrh(emsg, env)
   end
   orgErrh=ba.seterrh(errorh) or function() end
   elogInit=function()
      local s
      xedge.tldir:onclient(function(conns, sId)
	 if conns > 0 then
	    tlConnected=true
	    s=sId and ba.session(sId)
	    if s then s:lock() end
	    if timer then
	       flushing=true
	       timer:cancel()
	       timer=ba.timer(function() flush(nil,true) end)
	       timer:set(2000)
	    end
	 else
	    tlConnected=false
	    if s then
	       s:lastaccessedtime(true)
	       s:release()
	    end
	 end
      end)
   end
end -- elog

local function sendErr(...)
   return xedge.elog({flush=true, subject="Xedge: error"},...)
end

do
   local eventList={}

   local function sendEvent(...)
      for func in pairs(eventList) do
	 local ok,err = pcall(func,...)
	 if not ok then sendErr("Network event callback failed: %s",err) end
      end
   end
   function xedge.event(cb, remove)
      eventList[cb] = not remove and true or nil
   end
   local function manageEvent(cmd)
      if "sntp" == cmd then startAcmeDns(true) end
   end

   --Must be called by C code
   function _XedgeEvent(...) manageEvent(...) sendEvent(...) end
   xedgeEvent=_XedgeEvent
end

-- Returns IO obj,io name (ion), path name (pn)
-- pn is the path without ion: /ion/path -> path
local function fn2info(fn, noapp)
   if 0 == #fn or "." == fn then return nil end
   fn=ba.urldecode(fn)
   if fn:find"^https?://" then
      return ios.net,"net",fn
   end
   local ix=sfind(fn, "/", 1, true)
   local ion=ix and ssub(fn,1,ix-1) or fn
   local io=ios[ion]
   if not io then
      if noapp then return end
      local app=apps[ion]
      if not app then return end
      io=app.io
   end
   local pn=ix and ssub(fn,ix+1,-1)
   return io, ion, pn and #pn > 0 and pn or nil
end

local function noopIO(cfg)
   local function files(fn)
      local fname, isdir, mtime, size=".appcfg", false, fakeTime(), #cfg
      local function read() return false end
      local function name() return fname end
      local function stat() return {name=fname,isdir=false,mtime=fakeTime(),size=#cfg} end
      return {read=read,name=name,stat=stat}
   end
   local function stat(fn)
      if 0 == #fn or "." == fn then return ioStat end
      if fn:find"%.appcfg$" then
	 return {mtime=fakeTime(),size=#getJsonAppCfg(cfg.name),isdir=false}
      end
      return false
   end
   local function x() return nil, "noaccess" end
   local iofuncs={open=x,files=files,stat=stat,mkdir=x,rmdir=x,remove=x}
   return ba.create.luaio(iofuncs)
end

local function errh(emsg) return dtraceback(emsg,2) end

local function loadAndRunLua(io,fn,env)
   local ok
   local f,err = io:loadfile(fn,env)
   if f then
      ok, err = xpcall(f,errh)
      if ok then return true end
   end
   sendErr("%s %s failed:\n\t%s",f and "Running" or "Compiling", io:realpath(fn), err or "?")
end
xedge.loadAndRunLua=loadAndRunLua


local function runOnUnload(pn,env,appenv)
   local func = rawget(env,"onunload")
   if type(func) == "function" then
      local ok, err = pcall(func)
      if not ok then sendErr("Stopping '%s' failed: %s",pn,err or "?") end
   end
   local level=0
   local function close(tab)
      if level > 10 then return end
      level=level+1
      for k,v in pairs(tab) do
	 if "table" == type(v) then
	    if v.close then
	       pcall(function() v:close() end)
	    end
	    if v ~= appenv and v ~= G and v ~= tab then close(v) end
	 elseif "userdata" == type(v) and v.peername then
	    pcall(function() v:close() end)
	 end
      end
      local ix=next(tab)
      while ix do
	 tab[ix]=nil
	 ix=next(tab)
      end
      level=level-1
   end
   close(env)
   collectgarbage()
end


local function manageXLuaFile(pn,app) -- start/restart an xx.xlua file
   if pn:find(".DAV/", 1, true) then return end -- skip
   local env=app.envs[pn]
   if env then runOnUnload(pn,env,app.env) end
   env=setmetatable({},{__index=app.env})
   app.envs[pn]=loadAndRunLua(app.io,pn,env) and env or nil
end

local function stopApp(name)
   local app=apps[name]
   assert(app)
   if app.dir then app.dir:unlink() end
   for n,env in pairs(app.envs) do runOnUnload(n,env,app.env) end
   runOnUnload(app.url,app.env)
   collectgarbage()
end

local function terminateApp(name, nosave)
   stopApp(name)
   apps[name]=nil
   appsCfg[name]=nil
   if not nosave then xedge.saveCfg() end
end

local function manageApp(name) -- start/stop/restart
   local err
   local appc=appsCfg[name]
   assert(appc)
   local io,ion,pn=fn2info(appc.url, true)
   if io then io,err=ba.mkio(io, pn) end
   if not io then
      err=sendErr("Opening app '%s' (%s) failed: %s ",name,appc.url,err or "invalid URL")
      appc.err=err
      io=noopIO(appc)
   end
   if apps[name] then stopApp(name) end
   local env=setmetatable({io=io},{__index=G})
   env.app=env
   local app={io=io,env=env,envs={}}
   apps[name]=app
   if appc.running and not err then
      if appc.dirname then
	 app.pages={}
	 local dn=trim(appc.dirname)
	 local dir=ba.create.resrdr(#dn > 1 and dn or nil,appc.priority or 0,io)
	 app.dir=dir
	 dir:setfunc(function(_ENV,pn)
	    if pn:find"%.x?lua$" then
	       response:senderror(403, "XLua files cannot be opened using the browser.")
	       return true
	    end
	    return false
	 end)
	 dir:lspfilter(app.env)
	 dir:insert()
      end
      local cnt=0
      if io:stat".preload" then loadAndRunLua(io,".preload", app.env) end
      for path,fn in recDirIter(io,"") do
	 if fn:find"%.xlua$" then
	    manageXLuaFile(#path == 0 and fn or path.."/"..fn,app)
	 else
	    cnt = cnt+1
	    if cnt > 100 then sendErr("Too many files in application '%s' (%s)",name,appc.url) break end
	 end
	 
      end
   end
end


local function newAppCfg(cfg)
   local name=cfg.name or "APP"
   local ix,n=0,name
   while ios[n] do
      ix=ix+1
      n=sfmt("%s-%d",name,ix)
   end
   while appsCfg[n] do
      ix=ix+1
      n=sfmt("%s-%d",name,ix)
   end
   cfg.name=n
   appsCfg[n]=cfg
end

--something weird here

local function newOrUpdateApp(cfg,cfgIx,fn,ion) -- On new/update cfg file
   local url=ssub(fn,1, cfgIx-1)
   local nc={name=cfg.name,url=cfg.url,running=cfg.running or false,dirname=cfg.dirname}
   if cfg.dirname then nc.priority=cfg.priority or 0 end
   if not nc.url then nc.url=url end
   if appsCfg[ion] then -- update
      local oc=appsCfg[ion] -- original config
      local aio=apps[ion].io
      -- no: if aio:stat(oc.url) then nc.url=oc.url end -- keep org.
      if nc.name~=ion then -- renamed
	 terminateApp(ion, true)
	 newAppCfg(nc)
      else
	 appsCfg[ion]=nc
      end
   elseif ios[ion] then
      newAppCfg(nc)
      log("Creating new app '%s'",nc.name)
   else
      log("Invalid URL %s",fn)
      return false
   end
   xedge.saveCfg()
   manageApp(nc.name)
   return true
end

----------------------------------------------------------------
-- The Xedge virtual file system
----------------------------------------------------------------

local function open(fn, mode)
   local fp
   local io,ion,pn=fn2info(fn)
   if not io then return nil,"notfound" end
   local cfgIx=fn:find"%.appcfg$"
   if cfgIx then
      local function read(size)
	 local cfg=getJsonAppCfg(ion)
	 if #cfg <= size then return cfg end
	 return nil, "enoent"
      end
      local function write(data)
	 if fn:find(".DAV/", 1, true) then return true end -- do nothing
	 data=trim(data)
	 local cfg=#data > 0 and jdecode(data) or {running=false}
	 return newOrUpdateApp(cfg or {},cfgIx,fn,ion)
      end
      local function x() return true end
      return {read=read,write=write,seek=x,flush=x,close=x}
   end
   if not pn then return nil,"notfound" end
   fp,err=io:open(pn, mode)
   if not fp then return nil,err end
   local function read(maxsize) return fp:read(maxsize) end
   local function write(data) return fp:write(data) end
   local function seek(offset) return fp:seek(offset) end
   local function flush() return fp:flush() end
   local function close()
      if fp:close() then
	 if "w" == mode and pn:find"%.xlua$" then
	    local app=apps[ion]
	    if app then
	       if appsCfg[ion].running then
		  manageXLuaFile(pn,app)
	       else
		  log("parent app for %s not running!",pn)
	       end
	    end
	 end
	 return true
      end
      return false
   end
   return {read=read,write=write,seek=seek,flush=flush,close=close}
end
 
local function files(fn)
   local cfg
   local io,ion,pn=fn2info(fn)
   if not io then
      if 0 == #fn or "." == fn then
	 local name,io
	 local function appRead()
	    name,io=next(apps,name)
	    return name and true or false
	 end
	 local funcs
	 funcs={
	    read=function() name,io=next(ios,name)
	       if name then return true end
	       funcs.read=appRead
	       return appRead()
	    end,
	    name=function() return name end,
	    stat=function() return ioStat end
	 }
	 return funcs
      end
      return nil,"notfound" -- failed
   end
   if not io:stat(pn or "") then return nil,"notfound" end
   local iter
   pcall(function()iter=io:files(pn or "",true)end)
   if not iter then return nil,"notfound" end
   local fname, isdir, mtime, size=true
   local function read()
      if not fname or cfg then return false end
      fname, isdir, mtime, size=iter()
      if not fname then
	 if not pn and appsCfg[ion] then
	    cfg=getJsonAppCfg(ion)
	    fname,isdir,mtime,size=".appcfg",false,fakeTime(),#cfg
	    return true
	 end
	 return false
      end
      return true
   end
   local function name() return fname end
   local function stat() return {name=name,isdir=isdir,mtime=mtime,size=size} end
   return {read=read,name=name,stat=stat}
end
 
local function stat(fn)
   if 0 == #fn or "." == fn then return ioStat end
   local io,ion,pn=fn2info(fn)
   if not pn then return ioStat end
   local ret,err=io:stat(pn)
   if not ret then
      if fn:find"%.appcfg$" then
	 return {mtime=fakeTime(),size=#getJsonAppCfg(ion),isdir=false}
      end
   end
   return ret,err
end
 
local function mkdir(fn)
   local io,ion,pn=fn2info(fn)
   if not io or not pn then return nil,"noaccess" end
   return io:mkdir(pn)
end
 
local function rmdir(fn)
   local io,ion,pn=fn2info(fn)
   if not io or not pn then return nil,"notfound" end
   return io:rmdir(pn)
end
 

local function remove(fn)
   local io,ion,pn=fn2info(fn)
   if not io then return nil,"notfound" end
   if apps[ion] and ".appcfg" == pn then
      terminateApp(ion)
      return true
   end
   return io:remove(pn)
end

local function rename(fn,to)
   local io,ion,pn=fn2info(fn)
   if not io then return nil,"notfound" end
   if not pn and (ios[ion] or apps[ion]) then return nil,"noaccess" end
   return io:rename(pn,to:sub(#ion+2))
end

 
local iofuncs={open=open,files=files,stat=stat,mkdir=mkdir,rmdir=rmdir,remove=remove,rename=rename}
local lio=ba.create.luaio(iofuncs)
xedge.lio=lio

----------------------------------------------------------------
-- End virtual file system
----------------------------------------------------------------

startAcmeDns=function(warn)
   local portal=xedge.portal
   assert(portal,"ACME security module not intalled")
   local s <close> = ba.socket.connect(portal,443)
   if s then
      if os.time() < xedge.compileTime then
	 if warn then xedge.log"System time is in the past!" end
      else
	 local ad=require"acme/dns"
	 ad.isreg(function(name)
	    if name then
	       local ok=ad.auto{production=production,revcon=xedge.cfg.revcon}
	       if ok then startAcmeDns=function() end end
	    end
	 end)
      end
   else
      sendErr("Cannot connect to portal %s",portal)
   end
end

local installAuth -- function is: installOrSetAuth() or setdb()
function installOrSetAuth()
   if not next(userdb) and not xedge.sso then return end
   local ju=ba.create.jsonuser()
   local function setdb()
      if next(userdb) then
	 -- Arg 'userdb' must be in jauthenticator format
	 if ju:set(userdb) then return true end
	 log"Invalid user database. Authenticator not installed"
	 userdb={} -- reset
	 xedge.cfg.userdb=userdb
      elseif not xedge.sso then
	 xedge.prd:unlink()
	 if xedge.tldir then xedge.tldir:setauth() end
	 xedge.appsd:setauth()
	 log"Removing authenticator"
	 xedge.authenticator=nil
	 xedge.authuser=nil
	 installAuth=installOrSetAuth
	 return false
      end
      return true
   end
   if not setdb() then return false end
   installAuth=setdb
   local function loginresponse(_ENV, authinfo)
      response:senderror(401)
   end
   local auth=ba.create.authenticator(ju,{
      response=loginresponse,type="form",realm=authRealm})
   xedge.authenticator=auth
   xedge.authuser=ju
   log"Installing authenticator"
   local dir=ba.create.dir("private",127)
   dir:setauth(auth)
   xedge.rtld:insertprolog(dir)
   xedge.prd=dir
   if xedge.tldir then xedge.tldir:setauth(auth) end
   xedge.appsd:setauth(auth)
   return true
end
installAuth=installOrSetAuth

--Used by /rtl/login/
function xedge.hasUserDb() return next(userdb) and true or false end


local function init(cfg)
   -- Load apps from the Xedge conf. file.
   local ok,err=pcall(function()
      if cfg.userdb then
	 for name,data in pairs(cfg.userdb) do userdb[name]=data end
      end
      for name,appc in pairs(cfg.apps) do
	 appc.name=name
	 appsCfg[name]=appc
	 manageApp(name)
      end
   end)
   if not ok then
      sendErr("configuration file corrupt (%s)!",err)
      return false
   end
   return true
end

local k
if ba.encryptionkey then
   k=ba.encryptionkey()
   ba.encryptionkey=nil
else
   k="438fccj39dewe8vc"
end
k=ba.crypto.hash("sha256")(k)(true)
function encodedStr2Tab(str)
   return jdecode(ba.aesdecode(k,str or "") or "") or {}
end

function openidDec() -- Decode encoded SSO JSON settings
   xedge.sso=nil
   openid=encodedStr2Tab(xedge.cfg.openid)
   pcall(function()
      xedge.sso=require"ms-sso".init(openid)
   end)
end

function xedge.init(cfg,aio,rtld) -- cfg from Xedge config file
   local err
   -- rtld set if mako
   local resrdr=ba.create.resrdr(not rtld and "rtl" or nil,0,aio)
   resrdr:lspfilter{io=aio}
   if rtld then
      rtld:insert(resrdr,true) -- Mako
   else
      resrdr:insert() -- Xedge standalone
      rtld=resrdr
   end
   xedge.rtld=rtld
   xedge.cfg.revcon=cfg.revcon
   xedge.cfg.smtp=cfg.smtp
   xedge.cfg.openid=cfg.openid
   if "table" == type(cfg.elog) then  xedge.cfg.elog=cfg.elog end
   smtp=encodedStr2Tab(xedge.cfg.smtp)
   openidDec()
   if xedge.tldir then rtld:insert(xedge.tldir,true) elogInit() end
   local lockDir -- Scan and look for writable DAV lock dir.
   for name,io in pairs(ios) do
      if io:stat".LOCK" or io:mkdir".LOCK" then
	 lockDir=sfmt("%s/.LOCK",name)
	 break
      end
   end
   local appsd=ba.create.wfs("apps",lio, lockDir)
   appsd:configure{tmo=7200,helpuri="https://realtimelogic.com/rtl/wfshelp/"}
   rtld:insert(appsd,true)
   xedge.appsd=appsd
   xedge.aio=aio

   -- The default 404 handler
   local davm={PROPFIND=true,OPTIONS=true} 
   local dir=ba.create.dir(nil,-127)
   dir:setfunc(function(_ENV)
      if davm[request:method()] then return false end
      response:setstatus(404)
      local fp <close> =aio:open".lua/404.html"
      response:write(fp:read"*a")
   end)
   dir:insert()
   xedge.dir404=dir
   if xedge.saveCfg then
      init(cfg)
      installAuth()
      startAcmeDns()
   else -- No DiskIo
      nodisk=true
      function xedge.saveCfg() end
   end
end

--   isreg=function(cmd,data) adns.isreg(function() cmd:json{ok=true, isreg=adns.isreg} end) end,


local adns=require"acme/dns"
local acmeCmd={
   isreg=function(cmd)
      local status,wan,sockname,email=adns.isreg()
      cmd:json{
	 ok=true,
	 isreg=status and true or false,
	 wan=wan,
	 sockname=sockname,
	 name=status and status:match"^[^%.]+",
	 email=email,
	 portal=xedge.portal,
	 revcon=xedge.cfg.revcon and true or false
      }
   end,
   available=function(cmd,data)
      cmd:json{ok=true, available=adns.available(data.name)}
   end,
   auto=function(cmd,data)
      xedge.cfg.revcon = xedge.cfg.revcon or false -- not nil
      local revcon = "true" == data.revcon and true or false
      local op={revcon=revcon,rsa=true,acceptterms=true,production=production}
      if data.email and data.name then
	 xedge.cfg.revcon=revcon
	 xedge.saveCfg()
	 local name=adns.isreg()
	 if name then data.name=name:match"^[^%.]+" end
	 adns.auto(data.email, data.name, op)
      elseif xedge.cfg.revcon ~= revcon then
	 xedge.cfg.revcon=revcon
	 adns.auto(op)
	 xedge.saveCfg()
      end
      cmd:json{ok=true}
   end
}

function xedge.ha1(name,pwd)
   return ba.crypto.hash"md5"(name)":"(authRealm)":"(pwd)(true,"hex")
end

-- Table 2 String. Designed for comparing two tables as strings.
local function t2s(t)
   local a={}
   for k,v in pairs(t or {}) do table.insert(a,k) table.insert(a,v) end
   table.sort(a)
   return table.concat(a)
end


-- Used by command.lsp via xedge.command()
local commands={

   acme=function(cmd,data)
	   local f=acmeCmd[data.acmd]
      if not f then cmd:json{err="Unknown acmd"}  end
      f(cmd,data)
   end,
   getconfig=function(cmd,data)
   local cfg={apps=appsCfg}
   cmd:json{ok=true,config=ba.b64urlencode(jencode(cfg))}
   end,
   getionames=function(cmd,data)
      if nodisk and data.xedgeconfig and not next(appsCfg) then
	 local cfg=jdecode(ba.b64decode(data.xedgeconfig) or "")
	 if cfg then
	    init(cfg)
	 else
	    log("Received invalid browser localStorage")
	 end
      end
      local ios=ba.io()
      ios.vm=nil
      local t={}
      for name in pairs(ios) do table.insert(t, name) end
      cmd:json{ok=true,ios=t,nodisk=nodisk}
   end,
   getappsstat=function(cmd)
      local t={}
      for name,cfg in pairs(appsCfg) do
	 t[name]=cfg.running;
      end
      cmd:json{ok=true,apps=t}
   end,
   gethost=function(cmd)
      cmd:json{ok=true,ip=cmd:domain()}
   end,
   getintro=function(cmd)
      local fp <close> = xedge.aio:open".lua/intro.html"
      cmd:json{ok=true,intro=fp:read"*a"}
   end,
   gettemplate=function(cmd,data)
      local fp <close> =xedge.aio:open("templates/template.".. (data.ext or ""))
      cmd:json{ok=true,data=fp and fp:read"*a" or "\n"}
   end,
   credentials=function(cmd,data)
      if data.name then
	 if #data.pwd > 0 then
	    local pwd=xedge.ha1(data.name,data.pwd)
	    userdb[data.name]={pwd={pwd},roles={},maxusers=2}
	 else
	    userdb[data.name]=nil -- delete
	 end
	 xedge.saveCfg()
	 installAuth()
	 cmd:json{ok=true}
      end
      local name = next(userdb) or ""
      cmd:json{ok=true,data={name=name}}
   end,
   pn2url=function(cmd,data)
      if data.fn then
	 local io,ion,pn=fn2info(data.fn)
	 local cfg = io and appsCfg[ion]
	 if cfg and cfg.running and cfg.dirname then
	    cmd:json{ok=true,url= #cfg.dirname > 0 and sfmt("/%s/%s",cfg.dirname,pn) or "/"..pn}
	 end
	 local emsg= cfg and (cfg.running and "Not an LSP app" or "App not running") or "App not found"
	 cmd:json{err=emsg}
      end
   end,
   pn2info=function(cmd,data)
      if data.fn then
	 local io,ion,pn=fn2info(data.fn)
	 local cfg = io and appsCfg[ion]
	 if cfg then
	    cmd:json{ok=true,isapp=true,running=cfg.running,lsp=cfg.dirname and yes or no,
	       url=cfg.dirname and not pn:find"%.xlua$" and (#cfg.dirname > 0 and sfmt("/%s/%s",cfg.dirname,pn) or "/"..pn)}
	 end
	 cmd:json{ok=true} -- not an app, but rsp must be OK
      end
   end,
   run=function(cmd,data) 
      if data.fn then
	 local io,ion,pn=fn2info(data.fn)
	 local app=apps[ion]
	 if app and appsCfg[ion].running then manageXLuaFile(pn,app) end
	 cmd:json{ok=true}
      end
   end,
   smtp=function(cmd,d)
      local rsp={ok=true}
      local ecfg=xedge.cfg.elog
      d.cmd=nil
      if next(d) then -- not empty
	 for k,v in pairs(d) do d[k]=trim(v) end
	 local old=t2s(smtp)
	 local newsmtp=d
	 local new=t2s(newsmtp)
	 if old ~= new or not ecfg.smtp then
	    local settingsOK
	    if #d.server > 4 and #d.connsec > 0 and #d.password > 3 and
	       #d.email > 4 and tonumber(d.port) and #d.user > 2 then
	       log("Sending test email to %s",d.email)
	       rsp.ok,rsp.err=sendmail({body="Test email"}, newsmtp)
	       settingsOK=true
	    else
	       rsp.ok=true
	    end
	    if rsp.ok then
	       log(settingsOK and "SMTP settings OK" or "Disabling SMTP")
	       xedge.cfg.smtp=ba.aesencode(k,jencode(d))
	       smtp=encodedStr2Tab(xedge.cfg.smtp)
	       if settingsOK then
		  ecfg.smtp=true
	       else
		  ecfg.smtp=false
	       end
	       xedge.saveCfg()
	    end
	 end
      else
	 for k,v in pairs(smtp or {}) do rsp[k]=smtp[k] end
	 for k,v in pairs(ecfg or {}) do rsp[k]=ecfg[k] end
      end
      cmd:json(rsp)
   end,
   openid=function(cmd,d)
      local rsp={ok=true}
      local ecfg=xedge.cfg.elog
      d.cmd=nil
      if next(d) then -- not empty
	 local old=t2s(openid)
	 local new=t2s(d)
	 if old ~= new or not openid then
	    if d.tenant and d.client_id and d.client_secret then
	       if #d.tenant > 20 and #d.client_id > 20 and #d.client_secret > 10 then
		  xedge.cfg.openid=ba.aesencode(k,jencode(d))
		  xedge.saveCfg()
		  openidDec()
		  installAuth()
	       elseif #d.client_secret==0 then
		  d.client_secret=nil
		  xedge.cfg.openid=ba.aesencode(k,jencode(d))
		  openidDec()
		  xedge.saveCfg()
		  installAuth()
	       else
		  rsp.ok=false
		  rsp.err="Invalid data"
	       end
	    end
	 end
      elseif openid then
	 rsp.data=openid
      end
      cmd:json(rsp)
   end,
   elog=function(cmd,d)
      local maxbuf,maxtime = math.tointeger(d.maxbuf), math.tointeger(d.maxtime)
      if maxbuf and maxtime then
	 local ecfg=xedge.cfg.elog
	 ecfg.maxbuf,ecfg.maxtime,ecfg.enablelog=maxbuf,maxtime,("true"==d.enablelog)
	 local s=trim(d.subject)
	 ecfg.subject = #s > 0 and s or "Xedge Log"
	 xedge.saveCfg()
	 cmd:json{ok=true}
      end
   end,
}

-- Used by command.lsp
function xedge.command(cmd)
   local data = cmd:data()
   local f=commands[data.cmd]
   if f then f(cmd,data) end
   cmd:json{err=sfmt("Unknown command '%s'",data.cmd or "?")}
end

function xedge.onunload()
   for name,cfg in pairs(appsCfg) do
      if(cfg.running) then stopApp(name) end
   end
end
