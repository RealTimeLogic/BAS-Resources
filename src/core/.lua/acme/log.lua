local M,levels={}, {debug=true,info=true,warning=true,error=true}

local function notification(event)
   local kind,phase=event.type,event.phase
   if kind == "runtime" then
      if phase == "starting" then return "Starting certificate management" end
      if phase == "ready" then return "Certificate management ready for "..event.name end
      if phase == "failed" then return "Startup failed: "..event.problem,"error" end
      if phase == "retry" then return "Retrying certificate management in "..event.delay.." seconds","warning" end
   elseif kind == "registration" then
      if phase == "enrolling" then return "Registering device "..event.name end
      if phase == "enrolled" then return "Device registered as "..event.name end
      if phase == "restoring" then return "Restoring registration for "..event.name end
      if phase == "confirmed" then return "Registration confirmed for "..event.name end
   elseif kind == "reverseConnection" then
      return "Reverse connection "..phase
   elseif kind == "dnsChallenge" then
      return phase == "removed" and "DNS TXT record removed: "..event.recordName or
         "DNS TXT record set: "..event.recordName
   elseif kind == "certificateIssued" then return "Certificate issued for "..event.domain
   elseif kind == "certificateRenewed" then return "Certificate renewed for "..event.domain
   elseif kind == "certificateRevoked" then return "Certificate revoked for "..event.domain
   elseif kind == "serviceChanged" then return "Using ACME service: "..event.directoryUrl end
end

local function copyFields(fields)
   if type(fields) ~= "table" then return nil end
   local copy={}
   for key,value in pairs(fields) do
      if type(key) == "string" then copy[key]=value end
   end
   return copy
end

function M.create(sink)
   if sink ~= nil and type(sink) ~= "function" then
      return nil,{code="invalid_logger",message="The log sink must be a function"}
   end
   sink=sink or function() end
   local logger,closed={},false

   local function emit(level,message,fields)
      if closed then return false end
      if not levels[level] then level="info" end
      local event={
         level=level,
         message=tostring(message or ""),
         fields=copyFields(fields)
      }
      local ok=pcall(sink,event)
      return ok
   end

   function logger:debug(message,fields) return emit("debug",message,fields) end
   function logger:info(message,fields) return emit("info",message,fields) end
   function logger:warning(message,fields) return emit("warning",message,fields) end
   function logger:error(message,fields) return emit("error",message,fields) end
   function logger:notify(event)
      local message,level
      if type(event) == "table" then message,level=notification(event) end
      return message and emit(level or "info",message,event) or false
   end
   function logger:close() closed=true sink=function() end return true end

   return logger
end

return M
