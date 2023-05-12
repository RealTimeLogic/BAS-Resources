
local function f404(_ENV,p)
   if response:initial() then
      local m = request:method()
      -- WebDAV-MiniRedir fails otherwise
      if "OPTIONS" == m or "PROPFIND" == m then return false end
      local fp = ba.openio("vm"):open"noapp.shtml"
      if fp then
         if #p>0 then response:setstatus(404) end
         response:write(fp:read"*a")
         fp:close()
         return true
      end
   end
   return false
end


dir=ba.create.dir(nil,-100)
dir:setfunc(f404)
dir:insert()
