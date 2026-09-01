return function(tpm)
   return function(records,callback)
      local shark=ba.create.sharkssl(nil,{server=true})
      for _,record in ipairs(records) do
         local key,cert,err=record.privateKey
         if type(key) == "table" and key.provider == "tpm" then
            if not tpm or type(tpm.sharkcert) ~= "function" then
               callback(nil,"TPM certificate installer unavailable")
               return
            end
            cert,err=tpm.sharkcert(key.name,record.certificate)
         else
            cert,err=ba.create.sharkcert(record.certificate,key)
         end
         if not cert then callback(nil,err) return end
         shark:addcert(cert)
      end
      if records[1] then
         local op={shark=shark}
         if ba.slcon then ba.slcon=ba.create.servcon(ba.slcon,op) end
         if ba.slcon6 then ba.slcon6=ba.create.servcon(ba.slcon6,op) end
      end
      callback(true)
   end
end
