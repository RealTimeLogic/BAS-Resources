local errorTable,copy=require"acme/_util"()
local transient={cannotresolve=true,cannotconnect=true,timeout=true,
   socketreadfailed=true,socketwritefailed=true}

local function transportError(message,phase,extra)
   message=tostring(message)
   extra=extra or {}
   extra.cause,extra.phase,extra.temporary,extra.retryable=
      message,phase,transient[message] == true,transient[message] == true
   return errorTable("transport_error",message,extra)
end

return function(factory,options,clients,request,body)
   local http=factory(copy(options or {}))
   if not http then return nil,errorTable("http_create_failed",nil,{url=request.url}) end
   clients[http]=true
   local function close() clients[http]=nil http:close() end
   request.header=copy(request.header or {})
   local phase="request"
   local ok,message=http:request(request)
   if ok and body ~= nil then phase="write" ok,message=http:write(body) end
   if not ok then
      close()
      return nil,transportError(message,phase,{url=request.url})
   end
   local status,headers=http:status(),{}
   for name,value in pairs(http:header() or {}) do headers[name:lower()]=value end
   local data=""
   if request.method ~= "HEAD" then
      data,message=http:read"a"
      if data == nil and status ~= 204 then
         close()
         return nil,transportError(message,"read",{status=status,url=request.url})
      end
      data=data or ""
   end
   close()
   return {status=status,headers=headers,body=data}
end
