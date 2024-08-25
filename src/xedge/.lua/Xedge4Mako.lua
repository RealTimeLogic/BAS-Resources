local function deferred()
   local rw=require"rwfile"
   local log=xedge.log
   -- Fetch Xedge Config (xc) from mako.conf
   local xc = require"loadconf".xedge or {}

   -- Global set by xedge.lua
   local cfgio = xc.ioname and ba.openio(xc.ioname) or ba.openio"home"
   local cfgname = xc.path or "xedge.conf"

   local function saveCfg(cfg)
      if not cfgio then return end
      local ok,err= rw.file(cfgio, cfgname, cfg)
      if not ok then
	 log("Cannot save %s: %s",cfgio:realpath(cfgname),err)
      end
   end

   if mako.tldir then
      local t=mako.tldir
      xedge.tldir=t
      if t:configure().priority < 9 then t:configure{priority=9} end
   else
      local t=ba.create.tracelogger()
      t:configure{priority=9}
      xedge.tldir=t
   end
   xedge.tldir:unlink()

   -- Load and start apps in config file
   local cfg,err=rw.file(cfgio,cfgname)
   log("Configuration file: %s: %s",
       cfgio:realpath(cfgname), cfg and "loaded" or err)

   setkey("qwerty") -- PATCH fixme
   setkey(true)

   xinit(saveCfg,cfg,io,mako.rtldir)
   if mako.udb and not xedge.authenticator then
      xedge.appsd:setauth(ba.create.authenticator(mako.udb()))
   end
   onunload=xedge.onunload
   setkey,xinit=nil,nil
end
dir:unlink()
dir=nil
mako.createloader(io)
ba.thread.run(deferred)
