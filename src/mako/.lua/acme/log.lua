local fmt=string.format
local sendlog=(function()
   if mako then
      if mako.daemon then
	 return function(isErr,msg)
	    local op = isErr and {flush=true} or {ts=true}
	    mako.log(msg,op)
	 end
      end
   elseif xedge then
      return function(isErr,msg) xedge.elog({ts=true,flush=true},msg) end
   end
   return function() end
end)()


local function log(err,prio,fmts,...)
   local msg=fmt((err and "ACME error: " or "ACME: ")..fmts,...)
   if mako then tracep(false, prio, msg) end
   sendlog(err, msg)
end

local nextErrTm=0
local function err(...)
   local t=os.time()
   if t > nextErrTm then
      nextErrTm=t+86400
      log(true,0, ...)
   end
end


return {
   info=function(...) log(false,5, ...) end,
   error=err,
   log=function(prio,...) log(false,prio, ...) end,
   setlog=function(logfunc) sendlog=logfunc end
}
