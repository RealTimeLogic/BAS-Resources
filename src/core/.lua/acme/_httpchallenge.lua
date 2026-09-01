local _,_,safeCallback,_,_,_,reject=require"acme/_util"()

return function(options)
   local priority=options and options.priority or 1
   local adapter,directory={type="http-01"}
   local expectedPath,expectedValue

   function adapter:present(context,callback)
      if directory then return reject(callback,"challenge_in_progress") end
      expectedPath,expectedValue=context.tokenPath,context.keyAuthorization
      local function serve(_ENV,relative)
         if relative ~= expectedPath then return false end
         response:setcontenttype"application/octet-stream"
         response:setcontentlength(#expectedValue)
         response:send(expectedValue)
         return true
      end
      directory=ba.create.dir(".well-known",priority)
      directory:setfunc(serve)
      directory:insert()
      safeCallback(callback,true,nil)
      return true
   end

   function adapter:cleanup(_,callback)
      if directory then directory:unlink() end
      directory,expectedPath,expectedValue=nil,nil,nil
      safeCallback(callback,true,nil)
      return true
   end
   return adapter
end
