local errorTable,copy,safeCallback,_,_,_,reject=require"acme/_util"()

return function(options)
   options=options or {}
   local logger,notify=options.log,type(options.notify) == "function" and options.notify or function() end
   local adapter,phase,closed={type="dns-01"},"idle",false
   local context,pending

   local function emit(event)
      local ok,message=pcall(notify,copy(event))
      if not ok and logger and type(logger.error) == "function" then
         pcall(logger.error,logger,"Manual DNS notification failed",{error=tostring(message)})
      end
   end

   function adapter:present(value,callback)
      if closed then return reject(callback,"adapter_closed") end
      if pending or phase ~= "idle" then return reject(callback,"challenge_in_progress") end
      context,phase,pending=copy(value or {}),"publish",callback
      emit{type="manualDnsChallenge",phase=phase,recordName=context.recordName,
         recordData=context.recordData,message="Publish the DNS TXT record, then continue"}
      return true
   end

   function adapter:cleanup(value,callback)
      if closed then return safeCallback(callback,true,nil) end
      if pending then safeCallback(pending,nil,errorTable("challenge_cancelled")) end
      context,phase,pending=copy(value or context or {}),"remove",callback
      emit{type="manualDnsChallenge",phase=phase,recordName=context.recordName,
         recordData=context.recordData,message="Remove the DNS TXT record, then continue"}
      return true
   end

   function adapter:continue(callback)
      if not pending then return reject(callback,"no_pending_action") end
      local operation=pending
      pending=nil
      if phase == "publish" then phase="active" else phase,context="idle",nil end
      safeCallback(operation,true,nil)
      safeCallback(callback,true,nil)
      return true
   end

   function adapter:cancel(callback)
      if pending then safeCallback(pending,nil,errorTable("challenge_cancelled")) end
      phase,context,pending="idle",nil,nil
      safeCallback(callback,true,nil)
      return true
   end

   function adapter:status()
      return {type="manual",phase=phase,recordName=context and context.recordName,
         recordData=context and context.recordData,message=phase == "publish" and
         "Publish the DNS TXT record, then continue" or phase == "remove" and
         "Remove the DNS TXT record, then continue" or nil}
   end

   function adapter:close(callback) closed=true return self:cancel(callback) end
   return adapter
end
