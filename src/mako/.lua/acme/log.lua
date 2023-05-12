local fmt=string.format
local sendlog = mako and mako.daemon and
   function(isErr,msg)
      local op = isErr and {flush=true} or {ts=true}
      mako.log(msg,op)
   end
   or function() end


local function log(isErr, fmts,...)
   local msg=fmt((isErr and "ACME error: " or "ACME: ")..fmts,...)
   tracep(false, isErr and 2 or 8, msg)
   sendlog(isErr, msg)
end

return {
   info=function(...) log(false, ...) end,
   error=function(...) log(true, ...) end,
   setlog=function(logfunc) sendlog=logfunc end
}
