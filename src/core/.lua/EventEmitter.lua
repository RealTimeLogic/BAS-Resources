local E={} -- EventEmitter
E.__index=E

function E:on(event,cb)
   local ev=self._evs[event]
   if not ev then ev={} self._evs[event]=ev end
   ev[cb]=true
   return true
end

function E:emit(event,...)
   local ev=self._evs[event]
   if ev then
      for cb in pairs(ev) do
	 local ok,err = pcall(cb,...)
	 if not ok then
	    if self.reporterr then
	       self.reporterr(event,cb,err)
	    else
	       trace("Event CB err:",event,cb,err)
	    end
	 end
      end
      return true
   end
   return false
end

function E:removeListener(event,cb2rem)
   local ret=false
   local evs=self._evs
   local ev=evs[event]
   if ev then
      if cb2rem then
	 ret=ev[cb2rem] and true or false
	 ev[cb2rem]=nil
	 if not next(ev) then evs[event]=nil end
      else
	 evs[event]=nil
	 ret=true
      end
   end
   return ret
end

return {
   create=function(self) -- Constructor
	     local self=setmetatable(self or {},E)
	     self._evs={}
	     return self
	  end
}
