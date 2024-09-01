local maxHash=pcall(function() ba.crypto.hash("sha512") end) and "sha512" or "sha256"
return function(pmkey)
   assert(nil==ba.tpm)
   local keys={}
   local createkey,createcsr,sharkcert=ba.create.key,ba.create.csr,ba.create.sharkcert
   local PBKDF2,keyparams=ba.crypto.PBKDF2,ba.crypto.keyparams
   local jwtsign=require"jwt".sign
   local function tpmGetKey(kname)
      local key=keys[kname]
      if not key then error(sfmt("ECC key %s not found",tostring(kname)), 3) end
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
      newOp.rnd=PBKDF2(maxHash, kname, pmkey, 5, 1024)
      local key=createkey(newOp)
      keys[kname]=key
      return true
   end
   local function tpmHaskey(kname) return keys[kname] and true or false end
   local function tpmSharkcert(kname,certdata) return sharkcert(certdata,tpmGetKey(kname)) end
   require"acme/engine".setTPM{
      jwtsign=tpmJwtsign,
      keyparams=tpmKeyparams,
      createcsr=tpmCreatecsr,
      createkey=tpmCreatekey,
      haskey=tpmHaskey
   }
   local t={}
   function t.haskey(k) return tpmHaskey("#"..k) end
   function t.createkey(k,...) return tpmCreatekey("#"..k,...) end
   function t.createcsr(k,...) return tpmCreatecsr("#"..k,...) end
   function t.jwtsign(k,...) return tpmJwtsign("#"..k,...) end
   function t.keyparams(k,...) return tpmKeyparams("#"..k,...) end
   function t.sharkcert(k,...) return tpmSharkcert("#"..k,...) end
   ba.tpm=t
   return function(op,certdata)
      local n=op.keyname
      if not tpmHaskey(n) then tpmCreatekey(n,op) end
      return tpmSharkcert(n,certdata)  --Create cert for .config: tpmSharkcert
   end
end
