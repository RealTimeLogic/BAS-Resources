local function deferred()
   local rw=require"rwfile"
   local log=xedge.log
   -- Fetch Xedge Config (xc) from mako.conf
   local xc = require"loadconf".xedge or {}

   local cfgio = xc.ioname and ba.openio(xc.ioname) or ba.openio"home"
   local cfgname = xc.path or "xcfg.bin"

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
   local function fRwCfgFile(cdata)
      if cdata then
	 local ok,err=rw.file(cfgio, cfgname, ba.json.encode(cdata))
	 if not ok then
	    log("Cannot save %s: %s",cfgio:realpath(cfgname),err)
	 end
	 return ok
      end
      local err
      cdata,err=rw.file(cfgio,cfgname)
      log("Configuration file: %s: %s",
	  cfgio:realpath(cfgname), cdata and "loaded" or err)
      return cdata and ba.json.decode(cdata)
   end

   xinit(io,fRwCfgFile,mako.rtldir)
   xinit=nil

   if mako.udb and not xedge.authenticator then
      xedge.appsd:setauth(ba.create.authenticator(mako.udb()))
   end
end
dir:unlink()
dir=nil
mako.createloader(io)
ba.thread.run(deferred)
