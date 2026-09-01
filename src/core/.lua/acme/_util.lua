local productionUrl="https://acme-v02.api.letsencrypt.org/directory"
local stagingUrl="https://acme-staging-v02.api.letsencrypt.org/directory"

local function err(code,message,extra)
   local value={code=code,message=message or code}
   if extra then for name,item in pairs(extra) do value[name]=item end end
   return value
end

local function copy(value)
   if type(value) ~= "table" then return value end
   local result={}
   for name,item in pairs(value) do result[copy(name)]=copy(item) end
   return result
end

local function callback(fn,...)
   if type(fn) ~= "function" then return end
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

return function() return err,copy,callback,isHex,isHttps,resolveService,reject,ipv4,schedule end
