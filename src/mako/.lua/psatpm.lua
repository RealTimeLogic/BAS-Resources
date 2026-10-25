-- Capture the native capability before any application code runs.
local hash32,psa=assert(ba.hash32),assert(ba.psa)
ba.psa=true
local ok,err=psa("init")
if not ok then return nil,err end

local function keyId(name)
   if type(name)~="string" then error("key name must be a string",3) end
   local input,seed="ba.tpm\0"..name,0
   while true do
      local id=hash32(input,seed)&0x3fffffff
      if id>=0x10000 then return id end
      seed=(seed+1)&0xffffffff
   end
end

local function existingKey(name)
   local id=keyId(name)
   if not psa("haskey",id) then
      error(string.format("ECC key %s not found",name),3)
   end
   return id
end

local tpm={}
function tpm.haskey(name) return psa("haskey",keyId(name)) end
function tpm.createkey(name,op)
   local id=keyId(name)
   if psa("haskey",id) then error(string.format("ECC key %s exists",name),2) end
   return psa("createkey",id,op)
end
local function sign(hash,name,op) return psa("sign",existingKey(name),hash,op) end
tpm.sign=sign
function tpm.keyparams(name) return psa("keyparams",existingKey(name)) end
function tpm.createcsr(name,...) return psa("createcsr",existingKey(name),...) end
function tpm.createcertificate(name,...) return psa("createcertificate",existingKey(name),...) end
function tpm.sharkcert(name,cert) return psa("sharkcert",existingKey(name),cert) end
local jwtsign=require"jwt".sign
function tpm.jwtsign(payload,name,header)
   return jwtsign(payload,function(hash) return sign(hash,name) end,header)
end
function tpm.globalkey(name,len) return psa("globalkey",name,len) end
function tpm.uniquekey(name,len) return psa("uniquekey",name,len) end

local encode,decode=ba.json.encode,ba.json.decode
function tpm.jsonuser(name,global)
   if type(name)~="string" then error("key name must be a string",2) end
   global=not not global
   local ju,db=ba.create.jsonuser(),{}
   return {
      users=function()
         local users={}
         for user in pairs(db) do users[#users+1]=user end
         return users
      end,
      setuser=function(user,pwd)
         if pwd then
            if type(pwd)=="string" then pwd={pwd=pwd,roles={}} end
            db[user]=pwd
         else db[user]=nil end
         local ok,err=ju:set(db)
         if not ok then error(err,3) end
         return psa("jsonseal",name,global,encode(db))
      end,
      setdb=function(cipher)
         if type(cipher)~="string" then return nil,"Data corrupt" end
         local json=psa("jsonopen",name,global,cipher)
         local ok,data=pcall(decode,json)
         if not ok or not data then return nil,"Data corrupt" end
         local ok,err=ju:set(data)
         if ok then db=data end
         return ok,err
      end,
      getauth=function() return ju end
   }
end

-- Mako calls without arguments; Xedge also requests a named configuration key.
-- The first two arguments belong to the softTPM secret feed and are unused here.
local setTPM=require"acme/engine".setTPM
return function(_,_,name)
   -- ACME captures private callbacks before applications can replace methods.
   setTPM{jwtsign=tpm.jwtsign,keyparams=tpm.keyparams,
      createcsr=tpm.createcsr,createkey=tpm.createkey,haskey=tpm.haskey}
   ba.tpm=tpm
   if name then return tpm.globalkey(name,64) end
   return true
end
