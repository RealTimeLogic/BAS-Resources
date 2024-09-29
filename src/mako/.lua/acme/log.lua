local fmt=string.format
local sendlog = mako and mako.daemon and
   function(isErr,msg)
      local op = isErr and {flush=true} or {ts=true}
      mako.log(msg,op)
   end
   or function() end


local function log(err,prio,fmts,...)
   local msg=fmt((err and "ACME error: " or "ACME: ")..fmts,...)
   tracep(false, prio, msg)
   sendlog(err, msg)
end

return {
   info=function(...) log(false,8, ...) end,
   error=function(...) log(true,0, ...) end,
   log=function(prio,...) log(false,prio, ...) end,
   setlog=function(logfunc) sendlog=logfunc end
}
