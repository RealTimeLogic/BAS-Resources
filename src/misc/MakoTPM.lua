local maxHash=pcall(function() ba.crypto.hash("sha512") end) and "sha512" or "sha256"
local jencode,jdecode,symmetric,PBKDF2,keyparams,jwtsign,createkey,createcsr,sharkcert=
ba.json.encode,ba.json.decode,ba.crypto.symmetric,ba.crypto.PBKDF2,ba.crypto.keyparams,
require"jwt".sign,ba.create.key,ba.create.csr,ba.create.sharkcert
local function setuser(ju,db,name,pwd)
   if pwd then
      if type(pwd) == "string" then
	 pwd={pwd=pwd,roles={}}
      end
      db[name]=pwd
   else
      db[name]=nil
   end
   local ok,err=ju:set(db)
   if not ok then error(err,3) end
end
local function tpm(gpkey,upkey)
   local keys={}
   local function tpmGetKey(kname)
      local key=keys[kname]
      if not key then error(sfmt("ECC key %s not found",tostring(kname)),3) end
      return key
   end
   local function tpmJwtsign(kname,...) return jwtsign(tpmGetKey(kname),...) end
   local function tpmKeyparams(kname) return keyparams(tpmGetKey(kname)) end
   local function tpmCreatecsr(kname,...) return createcsr(tpmGetKey(kname),...) end
   local function tpmCreatekey(kname,op)
      if keys[kname] then error(sfmt("ECC key %s exists",kname),2) end
      op = op or {}
      if op.key and op.key ~= "ecc" then error("TPM can only create ECC keys",2) end
      local newOp={}
      for k,v in pairs(op) do newOp[k]=v end
      newOp.rnd=PBKDF2(maxHash,kname,upkey,5,1024)
      local key=createkey(newOp)
      keys[kname]=key
      return true
   end
   local function tpmHaskey(kname) return keys[kname] and true or false end
   local function tpmSharkcert(kname,certdata) return sharkcert(certdata,tpmGetKey(kname)) end
   require"acme/engine".setTPM{jwtsign=tpmJwtsign,keyparams=tpmKeyparams,createcsr=tpmCreatecsr,createkey=tpmCreatekey,haskey=tpmHaskey}
   local t={}
   function t.haskey(k) return tpmHaskey("#"..k) end
   function t.createkey(k,...) return tpmCreatekey("#"..k,...) end
   function t.createcsr(k,...) return tpmCreatecsr("#"..k,...) end
   function t.jwtsign(k,...) return tpmJwtsign("#"..k,...) end
   function t.keyparams(k,...) return tpmKeyparams("#"..k,...) end
   function t.sharkcert(k,...) return tpmSharkcert("#"..k,...) end
   function t.globalkey(n,l) return PBKDF2(maxHash,"#"..n,gpkey,5,l) end
   function t.uniquekey(n,l) return PBKDF2(maxHash,"#"..n,upkey,5,l) end
   function t.jsonuser(k,global)
      k=PBKDF2("sha256","@#"..k,global and gpkey or upkey,6,1)
      local function enc(db)
	 local iv=ba.rndbs(12)
	 local gcmEnc=symmetric("GCM",k,iv)
	 local cipher,tag=gcmEnc:encrypt(jencode(db),"PKCS7")
	 return iv..tag..cipher
      end
      local function dec(encdb)
	 if encdb and #encdb > 30 then
	    local iv=encdb:sub(1,12)
	    local tag=encdb:sub(13,28)
	    local gcmDec=symmetric("GCM",k,iv)
	    pcall(function() db=jdecode(gcmDec:decrypt(encdb:sub(29,-1),tag,"PKCS7")) end)
	    if db then return db end
	 end
	 return nil,"Data corrupt"
      end
      local ju,db=ba.create.jsonuser(),{}
      return {
	 users=function() local t={} for u in pairs(db) do table.insert(t,u) end return t end,
	 setuser=function(name,pwd) setuser(ju,db,name,pwd) return enc(db) end,
	 setdb=function(encdb) local db,err,ok=dec(encdb) if db then ok,err=ju:set(db) if ok then return ok end end return nil,err end,
	 getauth=function() return ju end
      }
   end
   ba.tpm=t
end

local klist={}
return function(x)
   if true == x then
      local hf=ba.crypto.hash(maxHash)
      for _,k in ipairs(klist) do hf(k) end
      tpm(ba.crypto.hash(maxHash)(klist[1])(true),hf(true))
      klist=nil
      return
   end
   table.insert(klist,x)
end
