require"wfs" -- Install function ba.create.wfs

local function trim(s) return s:gsub("^%s*(.-)%s*$", "%1") end
local sfind,ssub,sfmt=string.find,string.sub,string.format
local tinsert=table.insert
local dtraceback=debug and debug.traceback or function(e) return e end
local jencode,jdecode=ba.json.encode,ba.json.decode
local startAcmeDns -- func
local acmeRuntime,acmePlatform,acmeClockReady,acmeWorkPending
local xedgeEvent -- = _XedgeEvent
local smtp -- smtp settings, a table, used by sendmail
local authRealm="Xedge"
local ios,dio=ba.io(),ba.openio"disk"
local noDiskCfg=false
local loadPlugins -- funcs
local gc=collectgarbage
local sso,saveCfg,rtld,tldir,dir404,insRtld

local function log(fmt,...)
   local msg=sfmt("Xedge: "..fmt, ...)
   tracep(false,5,msg)
   return msg
end

local xcfg={apps={},userdb={},elog={subject="Xedge Log",maxbuf=10000,maxtime=24,enablelog=true,smtp=false}}

local xedge={
   log=log,
   trim=trim
}
local G=_G
G.xedge=xedge
local apps={}
local appsCfg=xcfg.apps
local rw=require"rwfile"
local acmeConfig,acmeLogger=require"acmeconfig"
do
   local _,portal,generated=acmeConfig.identity()
   xedge.portal,xedge.generatedProof,xedge.compiledPortal=portal,generated,portal
end

local fakeTime=(function()
   local _,_,date=ba.version()
   local tm=ba.parsedate("Mon, "..date:gsub("^(%w+)%s*(%w+)","%2 %1"))
   xedge.compileTime=tm
   return function() tm=tm+1 return tm end
end)()

local ioStat={mtime=fakeTime(),size=0,isdir=true}

local function filePath(path,file)
   return #path > 0 and path.."/"..file or file
end

local function setSecH(dir)
   dir:header{
      ["Content-Security-Policy"] = "default-src 'self'; script-src 'self' https://cdn.jsdelivr.net 'unsafe-inline' blob:; connect-src 'self' https://cdn.jsdelivr.net; style-src 'self' 'unsafe-inline' https://cdn.jsdelivr.net; img-src 'self' data:; media-src 'self' https://simplemq.com; font-src 'self' data: https://cdn.jsdelivr.net; worker-src blob:;",
      ["X-Content-Type-Options"] = "nosniff",
   }
end

-- A recursive directory iterator
local function recDirIter(io,curPath,onDir)
   local name
   local co
   local doDir
   function doDir(path)
      curPath=path
      if onDir and #path > 0 then
	 name=nil
	 coroutine.yield()
      end
      for file,isdir in io:files(path, true) do
	 if "." ~= file and ".." ~= file then
	    if isdir then
	       doDir(filePath(path,file))
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
   if not s then return end
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
   cfg.subject = m.subject or xcfg.elog.subject or "Xedge"
   if not m.body and not m.htmlbody and not m.txtbody then
      cfg.body = "Xedge"
   end
   local ok,err=mail:send(cfg)
   if not ok then log("Sending email to %s failed: %s",cfg.to,err) end
   return ok,err
end

function xedge.sendmail(op,cb)
   ba.thread.run(function()
      cb = "function" == type(cb) and cb or function() end
      cb(sendmail(op))
   end)
end

-- Returns a list of all plugin names, if any
local function lsPlugins(ext)
   local rsp={}
   local io=xedge.aio
   local d=".lua/XedgePlugins"
   if io:stat(d) then
      for n in io:files(d) do
	 if n:find("%."..ext.."$") then
	    tinsert(rsp,sfmt("%s/%s",d,n))
	 end
      end
   end
   table.sort(rsp)
   return rsp
end

local function sendErr(...)
   return xedge.elog({flush=true, subject="Xedge: error"},...)
end
xedge.sendErr=sendErr

local elogInit --Func below called once by xedge.init
do -- elog
   local busy,tlConnected,msglist,msize,timer,flushing=false,false,{},0
   local function flush(op, send2log)
      if busy then return end
      flushing=false
      if timer then
	 timer:cancel()
	 timer=nil
      end
      local data=table.concat(msglist,"\n")
      if #data > 0 then
	 msglist={}
	 if send2log then
	    log("%s",data)
	 else
	    op=op or {}
	    op.body,busy=data,true
	    local send
	    send=function()
	       xedge.sendmail(op, function(ok,err)
		  if not ok and "cannotconnect" == err and (#data+msize) < xcfg.elog.maxbuf then
		     ba.timer(send):set(10000,true)
		  else
		     msize=0
		     busy=false
		  end
	       end)
	    end
	    send()
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
      local cfg=xcfg.elog
      if cfg.enablelog and cfg.smtp and not tlConnected then
	 local msg=sfmt(fmt, ...)
	 if op.ts then msg = os.date("%H:%M: ",os.time())..msg end
	 tinsert(msglist,msg)
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
      if op.noTrace then return sfmt(fmt,...) end
      return log(fmt,...)
   end
   local orgErrh
   local function errorh(emsg, env)
      local cfg,e=xcfg.elog
      if cfg.enablelog and cfg.smtp and not tlConnected then
	 if env and env.request then
	    e=sfmt("LSP Err: %s\nURL: %s\n", emsg, env.request:url())
	 else
	    e=sfmt("Lua Err: %s\n", emsg)
	 end
	 sendErr("%s",e)
      end
      ba.thread.run(function() xedgeEvent("error",emsg) end)
      orgErrh(emsg, env)
   end
   orgErrh=ba.seterrh(errorh) or function() end
   elogInit=function()
      local s
      tldir:onclient(function(conns, sId)
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
	    pcall(function() s:lastaccessedtime(true) s:release() end)
	 end
      end)
   end
end -- elog

do
   local ev=require"EventEmitter".create()
   ev.reporterr=function(event,cb,err) sendErr("Event CB err: %s %s %s",event,tostring(cb),err) end
   if dio then ev:on("sntp",function() startAcmeDns() end) end
   function xedge.event(event,cb,remove)
      assert("string" == type(event))
      if remove then return ev:removeListener(event,cb) end
      return ev:on(event,cb)
   end
   --Must be called by C code
   function _XedgeEvent(event,...)
      ev:emit({name=event,retain = true},...)
   end
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
   local function files()
      local fname=".appcfg"
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
   sendErr("%s %s failed:\n\t%s",f and "Running" or "Compiling",io:realpath(fn),err or "?")
   gc()
   gc()
   return nil,err
end
xedge.loadAndRunLua=loadAndRunLua


local function runOnUnload(pn,env,appenv)
   local func = rawget(env,"onunload")
   if type(func) == "function" then
      local ok, err = xpcall(func,errh)
      if not ok then sendErr("Stopping '%s' failed: %s",pn,err or "?") end
   end
   local level=0
   local function close(tab)
      if level > 10 then return end
      level=level+1
      for _,v in pairs(tab) do
	 if "table" == type(v) then
	    if v.close then
	       pcall(function() v:close() end)
	    end
	    if v ~= appenv and v ~= G and v ~= tab then close(v) end
	 elseif "userdata" == type(v) then
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
   gc()
end


local function manageXLuaFile(pn,app) -- start/restart an xx.xlua file
   if pn:find(".DAV/", 1, true) then return end -- skip
   local env=app.envs[pn]
   if env then runOnUnload(pn,env,app.env) end
   env=setmetatable({},{__index=app.env})
   local ok,err=loadAndRunLua(app.io,pn,env)
   app.envs[pn]= ok and env or nil
   return ok,err
end

local stopApp
do
   local ioT={}
   function xedge.createloader(io)
      assert(io and io.realpath,"Invalid IO")
      if ioT[io] then return end
      local function loader(name)
	 name=name:gsub("%.","/")
	 local lname=sfmt(".lua/%s.lua",name)
	 if not io:stat(lname) then return nil end
	 local res,err=io:loadfile(lname)
	 if not res then tracep(false,1,err) end
	 return res
      end
      tinsert(package.searchers, loader)
      ioT[io]=#package.searchers
      return loader
   end
   stopApp=function(name)
      local app=apps[name]
      assert(app)
      if app.dir then app.dir:unlink() end
      for n,env in pairs(app.envs) do runOnUnload(n,env,app.env) end
      runOnUnload(".preload",app.env,app.env)
      local ioIx=ioT[app.io]
      if ioIx then table.remove(package.searchers,ioIx) end
      app.running=nil
      gc()
   end
end

local function terminateApp(name, nosave)
   stopApp(name)
   apps[name]=nil
   appsCfg[name]=nil
   if not nosave then saveCfg() end
end

local function appreq(mT,env,n)
   local ln,f,err,m,ok
   m=mT[n]
   if m then return m end
   ln=sfmt(".lua/%s.lua",n:gsub("%.","/"))
   if not env.io:stat(ln) then error(sfmt("%s not found",n),3) end
   local f,err=env.io:loadfile(ln,env)
   if f then
      ok,err = xpcall(f,errh)
      if ok then mT[n]=err return err end -- err is now mod.
   end
   error(sfmt("%s failed: %s",n,err or "?"),3)
end


 -- start/stop/restart app by giving it a name and by using appc and io
local function controlApp(name,appc,io,isStartup)
   local ok,err=true,nil
   if apps[name] then stopApp(name) end
   local env=setmetatable({io=io},{__index=G})
   env.app=env
   local app={io=io,env=env,envs={}}
   apps[name]=app
   if appc.running and (false ~= appc.autostart or not isStartup) then
      if appc.dirname then
	 local dn,dom,dir=trim(appc.dirname),trim(appc.domainname or "")
	 if #dom > 0 then
	    dir=ba.create.domainresrdr(dom,appc.priority or 0,io)
	 else
	    dir=ba.create.resrdr(#dn > 0 and dn or nil,appc.priority or 0,io)
	 end
	 env.dir=dir
	 dir:setfunc(function(_ENV,n)
	    if n:find"%.x?lua$" then
	       response:senderror(403, "XLua files cannot be opened using the browser.")
	       return true
	    end
	    return false
	 end)
	 dir:lspfilter(env)
	 dir:insert()
      end
      local cnt=0
      app.running=true
      if io:stat".preload" then
	 local mT={}
	 function env.appreq(n) return appreq(mT,env,n) end
	 ok,err=loadAndRunLua(io,".preload", env)
      end
      if not err then
	 for path,fn in recDirIter(io,"") do
	    if fn:find"%.xlua$" then
	       ok,err=manageXLuaFile(#path == 0 and fn or path.."/"..fn,app)
	       if not ok then break end
	    else
	       cnt = cnt+1
	       if cnt > 100 then
		  err=sfmt("Too many files in application '%s' (%s)",name,appc.url)
		  break
	       end
	    end
	 end
      end
   end
   if err then
      sendErr("%s",err)
      if not appc.url:find"^https?://" then
	 terminateApp(name)
      else
	 appc.running=false
      end
      return nil,err
   end
   return app
end

 -- start/stop/restart app by using name found in appsCfg
local function manageApp(name,isStartup)
   local err
   local appc=appsCfg[name]
   assert(appc)
   local io,_,pn=fn2info(appc.url, true)
   if io then io,err=ba.mkio(io, pn) end
   if not io then
      io="$" == appc.url and ba.mkio(name)
      if io then
	 log("Loading embedded ZIP file %s",name)
      else
	 err=sendErr("Opening app '%s' (%s) failed: %s ",name,appc.url,err or "invalid URL")
	 appc.err=err
	 io=noopIO(appc)
      end
   end
   return controlApp(name,appc,io,isStartup)
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

local function newOrUpdateApp(cfg,ion,url) -- On new/update cfg file
   local nc={name=cfg.name,url=cfg.url,running=cfg.running or false,
      autostart=cfg.autostart,startprio=cfg.startprio,dirname=cfg.dirname,domainname=cfg.domainname}
   if cfg.dirname then nc.priority=cfg.priority and tonumber(cfg.priority) or 0 end
   if not nc.url then nc.url=url end
   local start=true -- or restart
   if appsCfg[ion] then -- update
      local oc=appsCfg[ion] -- original config
      if nc.name~=ion then -- renamed
	 terminateApp(ion, true)
	 newAppCfg(nc)
      else
	 start = oc.running ~= nc.running
	 appsCfg[ion]=nc
      end
   elseif ios[ion] then
      newAppCfg(nc)
      log("Creating new app '%s'",nc.name)
   else
      log("Invalid URL %s",url)
      return false
   end
   saveCfg()
   if start then manageApp(nc.name) end
   return true
end

----------------------------------------------------------------
-- The Xedge virtual file system
----------------------------------------------------------------

local function open(fn, mode)
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
	 return newOrUpdateApp(cfg or {},ion,ssub(fn,1, cfgIx-1))
      end
      local function x() return true end
      return {read=read,write=write,seek=x,flush=x,close=x}
   end
   if not pn then return nil,"notfound" end
   local fp,err=io:open(pn, mode)
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
	       if apps[ion].running then
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
   local cfg,name
   local io,ion,pn=fn2info(fn)
   if not io then
      if 0 == #fn or "." == fn then
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
   local fname,isdir,mtime,size=true
   local function read()
      if not fname or cfg then return false end
      fname, isdir, mtime, size=iter()
      if ".appcfg" == fname then fname, isdir, mtime, size=iter() end
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
   local function stat() return {name=fname,isdir=isdir,mtime=mtime,size=size} end
   return {read=read,name=function() return fname end,stat=stat}
end

local function stat(fn)
   if 0 == #fn or "." == fn then return ioStat end
   local io,ion,pn=fn2info(fn)
   if not pn then return ioStat end
   if fn:find"%.appcfg$" then
      return {mtime=fakeTime(),size=#getJsonAppCfg(ion),isdir=false}
   end
   local ret,err=io:stat(pn)
   return ret,err
end

local function mkdir(fn)
   local io,_,pn=fn2info(fn)
   if not io or not pn then return nil,"noaccess" end
   return io:mkdir(pn)
end

local function rmdir(fn)
   local io,_,pn=fn2info(fn)
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

acmeLogger=assert(require"acme/log".create(function(event)
   local err=event.level == "error"
   local message=(err and "SharkTrust error: " or "SharkTrust: ")..event.message
   tracep(false,err and 0 or 5,"Xedge: "..message)
   xedge.elog({flush=err,ts=true,noTrace=true},"%s",message)
end))

local function acmeNotify(event) acmeLogger:notify(event) end

local function createAcme()
   if not acmePlatform or type(xcfg.acme) ~= "table" then return end
   local runtime,portal,generated=acmeConfig.create(acmePlatform,xcfg.acme,saveCfg,acmeNotify)
   if not runtime then return nil,portal end
   acmeRuntime,xedge.portal,xedge.generatedProof=runtime,portal,generated
   return runtime
end

local function retryable(problem)
   return problem and problem.temporary == true and problem.retryable ~= false
end

startAcmeDns=function()
   acmeClockReady=true
   if acmeRuntime or type(xcfg.acme) ~= "table" then return end
   local runtime,err=createAcme()
   if not runtime then acmeLogger:error("Cannot configure: "..(err and (err.message or err.code) or "unknown")) return end
   acmeWorkPending=true
   runtime:start(function(_,problem) if not retryable(problem) then acmeWorkPending=false end end)
end

local installAuth -- function is: installOrSetAuth() or setdb()
local function installOrSetAuth()
   if not next(xcfg.userdb) and not sso then return end
   local ju=ba.create.jsonuser()
   local function setdb()
      if next(xcfg.userdb) then
	 -- Arg 'userdb' must be in jauthenticator format
	 if ju:set(xcfg.userdb) then return true end
	 log"Invalid user database. Authenticator not installed"
	 xcfg.userdb={} -- reset
      elseif not sso then
	 xedge.prd:unlink()
	 tldir:setauth()
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
   local function loginresponse(_ENV,_)
      response:senderror(401)
   end
   local auth=ba.create.authenticator(ju,{
      response=loginresponse,type="form",realm=authRealm})
   local az=ba.create.authorizer(function(_,_,_,s) return s.xadmin end)
   xedge.authenticator=auth
   xedge.authuser=ju
   log"Installing authenticator"
   local dir=ba.create.dir("private",127)
   dir:setauth(auth,az)
   rtld:insertprolog(dir)
   xedge.prd=dir
   tldir:setauth(auth,az)
   xedge.appsd:setauth(auth,az)
   return true
end
installAuth=installOrSetAuth

--Used by /rtl/login/
function xedge.hasUserDb() return (next(xcfg.userdb) and true or false),sso end

local function appsInit(cfg)
   if cfg.userdb then
      local ud=xcfg.userdb
      for name,data in pairs(cfg.userdb) do ud[name]=data end
   end
   local alist={}
   for name,appc in pairs(cfg.apps) do
      appc.name=name
      appsCfg[name]=appc
      tinsert(alist,appc)
   end
   table.sort(alist, function(a,b)
      return (a.startprio == nil and 100 or a.startprio) < (b.startprio == nil and 100 or b.startprio)
   end)
   for _,appc in ipairs(alist) do manageApp(appc.name,true) end
end

local function ssoInit()
   local id=xcfg.openid
   if sso then
      sso.close()
      sso=nil
   end
   if not id then return true end
   if not id.redirect_uri then return nil,"Save the OpenID settings to set the redirect URI" end
   local function ssoLog(message)
      xedge.elog({ts=true},"SSO: %s",message)
   end
   local function notify(event)
      ssoLog(event.kind..": "..event.message..
             (event.expires and " Expiration: "..event.expires or ""))
   end
   local function savecredential(secret,metadata)
      id.client_secret=secret
      id.client_secret_expires=metadata.expires
      return saveCfg()
   end
   local mod=require"ms-sso"
   local ok,value=pcall(mod.init,id,{log=ssoLog,notify=notify,
                                    savecredential=savecredential})
   if not ok then return nil,value end
   sso=value
   return true
end

local function xinit(aio,rwCfgFile,_tldir,_rtld,onAuth,_acmePlatform)
   onAuth=onAuth or function() end
   tldir=_tldir
   acmePlatform=_acmePlatform
   saveCfg = rwCfgFile and function() return rwCfgFile(xcfg) end or function() return true end
   local cfg=rwCfgFile and rwCfgFile() or {apps={}}
   ios=ba.io()
   ios.vm=nil
   -- Remove virtual disks from windows to prevent DAV lock if url=localhost
   local t={}
   for name,io in pairs(ios) do
      local xio
      local _,plat=io:resourcetype()
      if "windows" == plat and not io:realpath"" then xio=ba.mkio(io,"/c/") end
      t[name]=xio or io
   end
   ios=t
   local resrdr=ba.create.resrdr(not _rtld and "rtl" or nil,127,aio)
   if not _rtld then --Backward compat.
      local jqdir=ba.create.dir()
      resrdr:insert(jqdir,true)
      jqdir:setfunc(function(_ENV,relpath)
	 if "jquery.js"==relpath then response:sendredirect"https://code.jquery.com/jquery-3.7.1.min.js" return true end
	 return false
      end)
   end
   setSecH(resrdr)
   resrdr:lspfilter{io=aio}
   rtld=_rtld or resrdr
   insRtld=function()
      if _rtld then
	 rtld:insert(resrdr,true) -- Mako
      else
	 rtld:insert() -- Xedge standalone
      end
   end
   insRtld()
   xcfg.acme=cfg.acme
   xcfg.revcon=xcfg.acme and xcfg.acme.revcon
   do
      local _,portal,generated=acmeConfig.identity(xcfg.acme)
      xedge.portal,xedge.generatedProof=portal or xedge.compiledPortal,generated
   end
   xcfg.smtp=cfg.smtp
   xcfg.openid=cfg.openid
   if "table" == type(cfg.elog) then  xcfg.elog=cfg.elog end
   smtp=xcfg.smtp
   local ssoOK,ssoErr=ssoInit()
   if not ssoOK then log("Cannot initialize SSO: %s",ssoErr) end
   rtld:insert(tldir)
   elogInit()
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
   dir404=ba.create.dir(nil,-127)
   dir404:setfunc(function(_ENV)
      if davm[request:method()] then return false end
      response:setstatus(404)
      local fp <close> =aio:open".lua/404.html"
      response:write(fp:read"*a")
   end)
   dir404:insert()
   if dio or rwCfgFile then
      local function setUser(name,pwd)
	 pwd=xedge.ha1(name,pwd)
	 xcfg.userdb[name]={pwd={pwd},roles={},maxusers=2}
	 saveCfg()
	 installAuth()
      end
      ba.thread.run(function() appsInit(cfg) installAuth() onAuth(setUser) end)
      if dio and (os.time()+86400) > xedge.compileTime then startAcmeDns() end
   else
      noDiskCfg=true
   end
   loadPlugins()
end

local function acmeSettings(data)
   local current=xcfg.acme or {}
   local manual=data.manualIdentity == true or data.manualIdentity == "true"
   local portal,key,secret=data.portalUrl or current.portalUrl,
      data.zoneKey and #data.zoneKey > 0 and data.zoneKey or current.zoneKey,
      data.secret and #data.secret > 0 and data.secret or current.secret
   local production=current.production
   if data.staging ~= nil then production=not (data.staging == true or data.staging == "true") end
   local same=manual == (current.manualIdentity and true or false) and portal == current.portalUrl and
      key == current.zoneKey and secret == current.secret
   return {email=data.email or current.email,name=data.name or current.name,
      revcon=data.revcon == true or data.revcon == "true",production=production,
      productionUrl=current.productionUrl,stagingUrl=current.stagingUrl,state=same and current.state or nil,
      manualIdentity=manual,portalUrl=portal,zoneKey=key,secret=secret}
end

local function acmeResponse(data)
   local current=xcfg.acme
   local status=acmeRuntime and acmeRuntime:status()
   local ready=false
   for _,record in pairs(status and status.domains or {}) do
      if record.expiresAt and record.expiresAt > os.time() then ready=true break end
   end
   data.portal=current and current.manualIdentity and current.portalUrl or
      xedge.portal or current and current.portalUrl or xedge.compiledPortal or ""
   data.compiledPortal,data.compiledIdentity=xedge.compiledPortal or "",xedge.compiledPortal and true or false
   data.manualIdentity,data.generatedProof=current and current.manualIdentity and true or false,
      xedge.generatedProof and true or false
   data.staging=current and current.production == false or false
   data.revcon=xcfg.revcon and true or false
   data.reverseStatus=status and status.reverse or
      {enabled=data.revcon,connected=false,status=0,connections=0}
   data.certificateReady=ready
   data.certificateRetrying=status and status.retryPending or false
   if ready then acmeWorkPending=false end
   data.certificateWorking=not ready and (not acmeClockReady or acmeWorkPending and not status or
      status and (status.starting or status.retryPending or status.operation)) and true or false
   return data
end

local function deferredJson(response)
   response=response:deferred()
   return function(value)
      local data=jencode(value)
      response:setcontentlength(#data)
      response:send(data)
      response:close()
   end
end

local acmeCmd={
   isreg=function(_,data)
      local send=deferredJson(data.response)
      local status=acmeRuntime and acmeRuntime:status().registration
      if not status or not status.enrolled then
         send(acmeResponse{ok=true,isreg=false})
         return
      end
      acmeRuntime:isRegistered(function(result,problem)
         local rsp=acmeResponse{ok=true,isreg=result and true or false,
            name=(result and result.name or status.name or ""):match"^[^%.]+",
            email=xcfg.acme and xcfg.acme.email}
         if problem then rsp.connectionError=problem.message or problem.code end
         send(rsp)
      end)
   end,
   available=function(_,data)
      local send=deferredJson(data.response)
      acmeConfig.available(acmeSettings(data),data.name,function(result,problem)
         if not result then return send{err=problem and (problem.message or problem.code) or "Cannot check name"} end
         send{ok=true,available=result.available,name=result.name}
      end)
   end,
   auto=function(cmd,data)
      local send=deferredJson(data.response)
      local config=acmeSettings(data)
      if type(config.email) ~= "string" or type(config.name) ~= "string" then send{err="Invalid settings"} return end
      xcfg.acme,xcfg.revcon=config,config.revcon
      if not saveCfg() then send{err="Cannot save ACME settings"} return end
      acmeWorkPending=true
      local function launch()
         local runtime,err=createAcme()
         if not runtime then
            acmeWorkPending=false
            local message=err and (err.message or err.code) or "Cannot configure ACME"
            acmeLogger:error("Cannot configure: "..message)
            send{err=message}
            return
         end
         runtime:start(function(_,problem)
            if retryable(problem) then
               send{ok=true,pending=true}
            else
               acmeWorkPending=false
               send(problem and {err=problem.message or problem.code} or {ok=true})
            end
         end)
      end
      if acmeRuntime then
         local old=acmeRuntime
         acmeRuntime=nil
         old:close(function() if acmeClockReady then launch() else send{ok=true,pending=true} end end)
      elseif acmeClockReady then launch() else send{ok=true,pending=true} end
   end
}

function xedge.revcon(enable)
   xcfg.revcon=enable and true or false
   if xcfg.acme then xcfg.acme.revcon=xcfg.revcon end
   saveCfg()
   if acmeRuntime then return acmeRuntime:reverseConnection(xcfg.revcon) end
end

function xedge.ha1(name,pwd,realm)
   return ba.crypto.hash"md5"(name)":"(realm or authRealm)":"(pwd)(true,"hex")
end

-- Table 2 String. Designed for comparing two tables as strings.
local function t2s(t)
   local a={}
   for k,v in pairs(t or {}) do tinsert(a,k) tinsert(a,v) end
   table.sort(a)
   return table.concat(a)
end

local function appIniErr(name,err)
   return sfmt("%s./config failed: %s",name,err)
end

local function execConfig(io)
   if io:stat".config" then
      local ok,x=pcall(function() return io:dofile".config" end)
      if ok and "table" == type(x) then return x end
      return nil,x
   end
end

local function getCfg(io,ion)
   local app = io and apps[ion]
   if app then
      return app,(appsCfg[ion] or app) -- appsCfg[ion] not set for aux apps (Ref-AUX1)
   end
end


-- Used by command.lsp via xedge.command()
local commands={

   acme=function(cmd,data)
      local f=acmeCmd[data.acmd]
      if not f then return cmd:json{err="Unknown acmd"} end
      if not acmePlatform then return cmd:json{err="No IO"} end
      return f(cmd,data)
   end,
   getconfig=function(cmd,_)
      local cfg={apps=appsCfg}
      cmd:json{ok=true,config=ba.b64urlencode(jencode(cfg))}
   end,
   getionames=function(cmd,data)
      if noDiskCfg and data.xedgeconfig and not next(appsCfg) then
	 local cfg=jdecode(ba.b64decode(data.xedgeconfig) or "")
	 if cfg then
	    ba.thread.run(function() appsInit(cfg) end)
	 else
	    log("Received invalid browser localStorage")
	 end
      end
      ios.vm=nil
      local t={}
      for name in pairs(ios) do tinsert(t, name) end
      cmd:json{ok=true,ios=t,nodisk=noDiskCfg}
   end,
   getappsstat=function(cmd)
      local t={}
      for name,app in pairs(apps) do
	 t[name]=app.running;
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
   getmac=function(cmd) cmd:json{ok=false} end, -- Overload in plugin
   gettemplate=function(cmd,data)
      local fp <close> =xedge.aio:open("templates/template.".. (data.ext or ""))
      cmd:json{ok=true,data=fp and fp:read"*a" or "\n"}
   end,
   credentials=function(cmd,data)
      if data.name then
	 if #data.pwd > 0 then
	    local pwd=xedge.ha1(data.name,data.pwd)
	    xcfg.userdb[data.name]={pwd={pwd},roles={},maxusers=2}
	 else
	    xcfg.userdb[data.name]=nil -- delete
	 end
	 saveCfg()
	 installAuth()
	 cmd:json{ok=true}
      end
      local name = next(xcfg.userdb) or ""
      cmd:json{ok=true,data={name=name}}
   end,
   pn2url=function(cmd,data)
      if data.fn then
	 local io,ion,pn=fn2info(data.fn)
	 local app,cfg=getCfg(io,ion)
	 if cfg and cfg.running and cfg.dirname then
	    cmd:json{ok=true,url=cfg.domainname and sfmt("http://%s/%s",cfg.domainname,pn) or (
	       #cfg.dirname > 0 and sfmt("/%s/%s",cfg.dirname,pn) or "/"..pn)}
	 end
	 local emsg= cfg and (cfg.running and "'LSP App' not enabled" or "App not running") or "App not found"
	 cmd:json{err=emsg}
      end
   end,
   pn2info=function(cmd,data)
      if data.fn then
	 local io,ion,pn=fn2info(data.fn)
	 local app,cfg=getCfg(io,ion)
	 if app then
	    cmd:json{ok=true,isapp=true,running=app.running,lsp=cfg.dirname and true or false,
	       url=cfg.dirname and not pn:find"%.xlua$" and (#cfg.dirname > 0 and sfmt("/%s/%s",cfg.dirname,pn) or "/"..pn)}
	 end
	 cmd:json{ok=true} -- not an app, but rsp must be OK
      end
   end,
   run=function(cmd,data)
      if data.fn then
	 local _,ion,pn=fn2info(data.fn)
	 local app=apps[ion]
	 if app and app.running then manageXLuaFile(pn,app) end
	 cmd:json{ok=true}
      end
   end,
   smtp=function(cmd,d)
      local rsp={ok=true}
      local ecfg=xcfg.elog
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
	       xcfg.smtp=d
	       smtp=xcfg.smtp
	       if settingsOK then
		  ecfg.smtp=true
	       else
		  ecfg.smtp=false
	       end
	       saveCfg()
	    end
	 end
      else
	 for k in pairs(smtp or {}) do rsp[k]=smtp[k] end
	 for k in pairs(ecfg or {}) do rsp[k]=ecfg[k] end
      end
      cmd:json(rsp)
   end,
   openid=function(cmd,d)
      local rsp={ok=true}
      local id=xcfg.openid
      d.cmd=nil
      if next(d) then -- not empty
	 local old=t2s(id)
	 local new=t2s(d)
	 if old ~= new or not id then
	    if d.tenant and d.client_id and d.client_secret then
	       if #d.tenant==0 and #d.client_id==0 and #d.client_secret==0 then
		  xcfg.openid=nil
		  ssoInit()
		  saveCfg()
		  installAuth()
	       elseif #d.tenant > 20 and #d.client_id > 20 and #d.client_secret > 10 and
		      #(d.client_secret_expires or "") > 0 then
		  local origin=cmd:url():match"^https?://[^/]+"
		  if origin then
		     d.redirect_uri=origin.."/rtl/login/"
		     local previous=xcfg.openid
		     xcfg.openid=d
		     local ok,err=ssoInit()
		     if ok and saveCfg() then
			installAuth()
		     else
			xcfg.openid=previous
			ssoInit()
			rsp.ok,rsp.err=false,err or "Cannot save configuration"
		     end
		  else
		     rsp.ok,rsp.err=false,"Cannot determine the redirect URI"
		  end
	       else
		  rsp.ok,rsp.err=false,"Invalid data"
	       end
	    end
	 end
      else
	 rsp.data=id or {}
      end
      cmd:json(rsp)
   end,
   elog=function(cmd,d)
      local maxbuf,maxtime = math.tointeger(d.maxbuf), math.tointeger(d.maxtime)
      if maxbuf and maxtime then
	 local ecfg=xcfg.elog
	 ecfg.maxbuf,ecfg.maxtime,ecfg.enablelog=maxbuf,maxtime,("true"==d.enablelog)
	 local s=trim(d.subject)
	 ecfg.subject = #s > 0 and s or "Xedge Log"
	 saveCfg()
	 cmd:json{ok=true}
      end
   end,
   execLua=function(cmd,d)
      local f,err = load(d.code or "","LuaShell","t",G)
      if f then
	 ba.thread.run(function()
	    local ok,err=xpcall(f,errh)
	    if not ok then tracep(false,0,err) end
	 end)
	 cmd:json{ok=true}
      end
      tracep(false,0,err)
      cmd:json{ok=false,err=err}
   end,
   lsPlugins=function(cmd) cmd:json(lsPlugins"js") end,
   getPlugin=function(cmd,d)
      local n=d.name
      local f=n and n:find("%.js$") and rw.file(xedge.aio,n)
      if f then
	 cmd:write(f)
      else
	 cmd:senderror(404)
      end
      cmd:abort()
   end,
   startApp=function(cmd,d)
      local ioname,x=mako and "home" or "disk"
      local dio,zipname=ba.openio(ioname),d.name
      local dname=zipname and zipname:match"(.-)%.zip$"
      if not dname or (dio:stat(dname) and "false" == d.deploy) then
	 cmd:json{ok=false,err="Invalid params"}
      end
      local zio,err=ba.mkio(dio,zipname)
      if zio then
	 local function mkdir(io,dname)
	    if io:stat(dname) then return true end
	    return io:mkdir(dname)
	 end
	 local api,io,name,info
	 if "false" == d.deploy then
	    x,err=mkdir(dio,dname)
	    if x then io,err=ba.mkio(dio,dname) end
	    if io then
	       for path,name in recDirIter(zio,"",true) do
		  if not name then
		     x,err=mkdir(io,path)
		     if not x then err=sfmt("%s: %s",path,err) break end
		  else
		     local fname=filePath(path,name)
		     x,err=rw.file(zio,fname)
		     if x then x,err=rw.file(io,fname,x) end
		     if not x then err=sfmt("%s: %s",fname,err) break end
		  end
	       end
	    end
	    if not x then
	       cmd:json{ok=false,err=sfmt("Cannot unpack %s: %s",zipname,err)}
	    end
	    zio:close()
	    dio:remove(zipname)
	    name=dname
	 else
	    io,name=zio,zipname
	 end
	 local nc={name=name,url=sfmt("%s/%s",ioname,name)}
	 err=nil
	 api,x=execConfig(io)
	 if api then
	    nc.name = "string" == type(api.name) and api.name or name
	    nc.running,nc.autostart = api.autostart,api.autostart
	    nc.dirname = "string" == type(api.dirname) and api.dirname
	    nc.startprio=api.startprio
	 else
	    if x then err=appIniErr(name,"string" == type(x) or "failed") end
	    api={}
	 end
	 local newApp=true
	 local url=sfmt("%s/%s",ioname,zipname)
	 for _,cfg in pairs(appsCfg) do
	    if cfg.url == url then
	       if zipname == name then -- depl
		  newApp=false
		  local running=cfg.running
		  cfg.running=false
		  newOrUpdateApp(cfg,cfg.name,url)
		  appsCfg[cfg.name].running=running
		  if api.upgrade then
		     x,info=pcall(function() return api.upgrade(io) end)
		     if not x then err=appIniErr(name,info) end
		  end
		  if running then manageApp(cfg.name) end
	       else -- non-depl.
		  terminateApp(cfg.name,true)
	       end
	       break
	    end
	 end
	 if newApp then
	    if api.install then
	       x,info=pcall(function() return api.install(io) end)
	       if not x then err=appIniErr(name,info) end
	    end
	    newOrUpdateApp(nc,ioname,url)
	 end
	 cmd:json{ok=not err,upgrade=not newApp,err=err,info=info or ""}
      end
      cmd:json{ok=false,err=sfmt("Cannot open %s: %s",zipname,err)}
   end
}

local function findapp(name)
   local appc=appsCfg[name]
   if appc then return appc end
   for _,cfg in pairs(appsCfg) do if cfg.url == name then return cfg end end
   return nil,"notfound"
end

local function startOrStopApp(running,name,p)
   local appc,err=findapp(name)
   if appc then
      if running~=appc.running then
	 appc.running=running
	 manageApp(appc.name)
	 if p then saveCfg() end
	 return true
      end
      return false
   end
   return nil,err
end
function xedge.startapp(name,p) return startOrStopApp(true,name,p) end
function xedge.stopapp(name,p) return startOrStopApp(false,name,p) end
local function doUpgradeOrCfg(name,start,doCfg)
   local appc,ok,x
   appc,x=findapp(name)
   if appc then
      local io,_,pn=fn2info(appc.url, true)
      if io then
	 io,x=ba.mkio(io, pn)
	 if io then
	    ok,x=execConfig(io)
	    if doCfg then return ok,x end
	    start=appc.running or start
	    xedge.stopapp(appc.name)
	    if ok and ok.upgrade then
	       ok,x=pcall(function() return ok.upgrade(io) end)
	    end
	    if not ok and x then
	       x=appIniErr(appc.url,x)
	       log("%s",x)
	    end
	    if start then appc.autostart=true xedge.startapp(name,true) end
	    return x or true
	 end
      end
   end
   return nil,x
end
function xedge.upgradeapp(name,start)
   return doUpgradeOrCfg(name,start)
end
function xedge.getappcfg(name)
   return doUpgradeOrCfg(name,nil,true)
end

function xedge.auxapp(name,auxio,appc)
   appc=appc or {} -- simulated config
   if not appc.url then appc.url="auxapp" end
   name='$'..name
   assert("function"==type(auxio.rmdir))
   for n,io in pairs(ios) do if auxio==io then error"Cannot use default IOs" end end
   if nil == appc.running then appc.running=true end
   if appc.remove then appc.running=nil end
   local orgSendErr=sendErr
   local errs={}
   sendErr=function(...) table.insert(errs, sfmt(...)) orgSendErr(...) end
   local app,err=controlApp(name,appc,auxio)
   sendErr=orgSendErr
   if not app then return false,err end
   -- Add config (appc) to app: ref (Ref-AUX1)
   if appc.running then for k,v in pairs(appc) do app[k]=v end
   elseif appc.remove then apps[name]=nil end
   if #errs > 0 then
      return false,table.concat(errs,"\n")
   end
   return true
end

function xedge.ui(enable)
   if enable then
      rtld:insert(tldir)
      dir404:insert()
      insRtld()
   else
      rtld:unlink()
      dir404:unlink()
      tldir:unlink()
   end
end


-- Used by command.lsp
function xedge.command(cmd,response)
   local site,err=cmd:header"Sec-Fetch-Site"
   if site and "cross-site" == site then
      cmd:senderror(404)
      return
   end
   local data = cmd:data()
   data.response=response
   local f=commands[data.cmd]
   if f then return f(cmd,data) end
   err=sfmt("Unknown command '%s'",data.cmd or "?")
   sendErr("%s",err)
   cmd:json{err=err}
end

loadPlugins=function()
   local xf=rw.file
   for _,n in ipairs(lsPlugins"lua") do
      local ok
      local f,e=load(xf(xedge.aio,n),n,"bt",_ENV)
      if f then ok,e=pcall(f,commands) end
      if not ok then sendErr("Plugin error: %s",e) end
   end
end

local function onunload()
   if sso then sso.close() end
   if acmeRuntime then acmeRuntime:close() acmeRuntime=nil end
   for name,app in pairs(apps) do if(app.running) then stopApp(name) end end
end

return xinit,onunload
