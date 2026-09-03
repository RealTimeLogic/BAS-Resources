local errorTable,copy=require"acme/_util"()

return function(tpm,jwt)
   local function tpmMethod(name) return tpm and type(tpm[name]) == "function" and tpm[name] or nil end
   local function restore(key)
      if type(key) ~= "table" or key.provider ~= "tpm" then return true end
      local has,create=tpmMethod"hasKey",tpmMethod"createKey"
      if has and not has(key.name) then
         if not create then return nil,errorTable("tpm_unavailable") end
         create(key.name,key.options)
      end
      return true
   end
   local function sign(key,payload,header)
      if type(key) == "table" and key.provider == "tpm" then
         local method=tpmMethod"jwtSign"
         if not method then return nil,errorTable("tpm_unavailable") end
         local ok,problem=restore(key)
         if not ok then return nil,problem end
         local a,b=method(key.name,payload,header)
         return b or a
      end
      local a,b=jwt.sign(payload,key,header)
      return b or a
   end
   local function params(key)
      if type(key) == "table" and key.provider == "tpm" then
         local method=tpmMethod"keyParams"
         if not method then return nil,errorTable("tpm_unavailable") end
         local ok,problem=restore(key)
         if not ok then return nil,problem end
         return method(key.name)
      end
      return ba.crypto.keyparams(key)
   end
   local function createKey(name,options)
      options=copy(options or {})
      if options.tpm == true or options.type == "tpm" then
         local create,has=tpmMethod"createKey",tpmMethod"hasKey"
         if not create then return nil,errorTable("tpm_unavailable") end
         local exists=false
         if has then exists=has(name) end
         if not exists then create(name,options) end
         return {provider="tpm",name=name,options=options}
      end
      local rsa=options.type == "rsa" or options.key == "rsa"
      local keyOptions=rsa and
         {key="rsa",bits=options.bits or 2048} or {key="ecc",curve=options.curve or "SECP384R1"}
      return ba.create.key(keyOptions)
   end
   local function createCsr(key,domain)
      local dn,types,usage={commonname=domain},{"SSL_CLIENT","SSL_SERVER"},{"DIGITAL_SIGNATURE","KEY_ENCIPHERMENT"}
      if type(key) == "table" and key.provider == "tpm" then
         local method=tpmMethod"createCsr"
         if not method then return nil,errorTable("tpm_unavailable") end
         local ok,problem=restore(key)
         if not ok then return nil,problem end
         return method(key.name,dn,types,usage)
      end
      return ba.create.csr(key,dn,types,usage)
   end
   return sign,params,createKey,createCsr
end
