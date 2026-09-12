local productionUrl="https://acme-v02.api.letsencrypt.org/directory"
local stagingUrl="https://acme-staging-v02.api.letsencrypt.org/directory"

local function err(code,message,extra)
   local value=extra or {}
   value.code,value.message=code,message or code
   return value
end

local function copy(value)
   if type(value) ~= "table" then return value end
   local result={}
   for name,item in pairs(value) do result[copy(name)]=copy(item) end
   return result
end

local function callback(fn,...)
   if not fn then return end
   local ok,message=pcall(fn,...)
   if not ok and type(trace) == "function" then trace("SharkTrust callback error: ",tostring(message)) end
end

local function reject(fn,code,message,extra)
   local value=err(code,message,extra)
   callback(fn,nil,value)
   return nil,value
end

local function schedule(run,action,done)
   run(function() done(action()) end)
   return true
end

local function isHex(value,length)
   return type(value) == "string" and #value == length and not value:find("[^%x]")
end

local function isHttps(value)
   return type(value) == "string" and value:match("^https://[^/%s]+") and not value:find("[\r\n#]")
end

local function ipv4(value)
   if type(value) ~= "string" then return end
   local a,b,c,d=value:match("^(%d+)%.(%d+)%.(%d+)%.(%d+)$")
   if not d then return end
   local result={a,b,c,d}
   for index,part in ipairs(result) do
      if #part > 1 and part:sub(1,1) == "0" or tonumber(part) > 255 then return end
      result[index]=tonumber(part)
   end
   return table.unpack(result)
end

local function resolveService(service)
   if type(service) ~= "table" or type(service.production) ~= "boolean" then
      return nil,err("invalid_service","ACME service.production must be true or false")
   end
   if service.productionUrl ~= nil and not isHttps(service.productionUrl) or
      service.stagingUrl ~= nil and not isHttps(service.stagingUrl) then
      return nil,err("invalid_directory_url","ACME directory URLs must use HTTPS")
   end
   local resolved=copy(service)
   resolved.directoryUrl=service.production and (service.productionUrl or productionUrl) or
      (service.stagingUrl or stagingUrl)
   resolved.serviceId=ba.crypto.hash"sha256"(resolved.directoryUrl)(true,"hex")
   return resolved
end


local transient={cannotresolve=true,cannotconnect=true,timeout=true,
   socketreadfailed=true,socketwritefailed=true}

local function transportError(message,phase,extra)
   message=tostring(message)
   extra=extra or {}
   extra.cause,extra.phase,extra.temporary,extra.retryable=
      message,phase,transient[message] == true,transient[message] == true
   return err("transport_error",message,extra)
end

local function httpRequest(factory,options,clients,request,body)
   local http=factory(copy(options or {}))
   if not http then return nil,err("http_create_failed",nil,{url=request.url}) end
   clients[http]=true
   local function close() clients[http]=nil http:close() end
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

-- A corrupt main file can recover from the last complete replacement.
local function readJson(io,path)
   local function read(name)
      local fp=io:open(name,"r")
      if not fp then return end
      local raw=fp:read"a"
      fp:close()
      local ok,value=pcall(ba.json.decode,raw or "")
      return ok and type(value) == "table" and value or nil
   end
   return read(path) or read(path..".bak"),io:stat(path) or io:stat(path..".bak")
end

local function writeJson(io,path,value)
   local temp,backup=path..".tmp",path..".bak"
   local fp,message=io:open(temp,"w")
   if not fp then return nil,err("storage_write_failed",tostring(message)) end
   local ok
   ok,message=fp:write(ba.json.encode(value))
   fp:flush()
   fp:close()
   if ok == nil then io:remove(temp) return nil,err("storage_write_failed",tostring(message)) end
   if io:stat(backup) then io:remove(backup) end
   if io:stat(path) and not io:rename(path,backup) then
      io:remove(temp) return nil,err"storage_write_failed"
   end
   if not io:rename(temp,path) then
      if io:stat(backup) then io:rename(backup,path) end
      return nil,err"storage_write_failed"
   end
   if io:stat(backup) then io:remove(backup) end
   return true
end

return {err=err,copy=copy,callback=callback,isHex=isHex,isHttps=isHttps,
   resolveService=resolveService,reject=reject,ipv4=ipv4,schedule=schedule,
   http=httpRequest,readJson=readJson,writeJson=writeJson}
