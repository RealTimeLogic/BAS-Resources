-- Supplemental public beacon input after the native C RNG bootstrap.
local busy,closed,client=false,false

local function release()
   local c=client
   client=nil
   if c then pcall(c.close,c) end
end

local function worker()
   if closed then busy=false return end
   local ok,result,err=pcall(function()
      local shark,e=ba.sharkclient()
      if not shark then return nil,e end
      client,e=require"http".create{shark=shark}
      if not client then return nil,e end
      local c=client
      c:timeout(10000)
      local requested,reason=c:request{
         trusted=true,url="https://beacon.nist.gov/beacon/2.0/pulse/last"}
      if closed then return end
      if not requested then return nil,reason end
      local status,statusErr=c:status()
      if closed then return end
      if status~=200 then return nil,statusErr or ("HTTP "..tostring(status)) end
      local data,readErr=c:read"*a"
      if closed then return end
      if not data or #data==0 then return nil,readErr or "empty beacon response" end
      local hash=ba.crypto.hash("hmac","sha256",ba.clock())
      local buffer=hash(data)(true,"binary")
      return ba.rndseed(buffer)
   end)
   release()
   busy=false
   if not closed and (not ok or not result) then
      tracep(false,1,"Internet RNG reseed failed: "..tostring(ok and err or result))
   end
end

local function seed()
   if closed then return nil,"closed" end
   if busy then return nil,"seed in progress" end
   busy=true
   local ok,queued,err=pcall(ba.thread.run,worker)
   if not ok or queued==nil then
      busy=false
      return nil,ok and err or queued
   end
   return true
end

local function close()
   closed=true -- Also prevents already queued workers from opening a connection.
   release()
end

if ba.psa then return {seed=function() return true end,close=function() end} end
local ok,err=seed()
if not ok then tracep(false,1,"Internet RNG seed: "..tostring(err)) end
return {seed=seed,close=close}
