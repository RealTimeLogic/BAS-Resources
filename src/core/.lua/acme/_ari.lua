local errorTable=require"acme/_util"()

local function tlv(data,position)
   local tag,first=data:byte(position,position+1)
   if not first then return end
   local length,start=first,position+2
   if first >= 128 then
      local count=first-128
      if count < 1 or count > 4 or start+count-1 > #data then return end
      length=0
      for index=0,count-1 do length=length*256+data:byte(start+index) end
      start=start+count
   end
   local nextPosition=start+length
   if nextPosition-1 > #data then return end
   return {tag=tag,start=start,next=nextPosition,value=data:sub(start,nextPosition-1)}
end

return function(certificate,pemBody)
   if type(certificate) == "table" and type(certificate.ariId) == "string" then return certificate.ariId end
   local pem=type(certificate) == "table" and (certificate.certificate or certificate.pem) or certificate
   local der=pemBody(pem,"CERTIFICATE")
   if not der then return nil,errorTable("invalid_certificate") end
   local outer=tlv(der,1)
   local tbs=outer and outer.tag == 0x30 and tlv(der,outer.start)
   if not tbs or tbs.tag ~= 0x30 then return nil,errorTable("invalid_certificate") end
   local field=tlv(der,tbs.start)
   if field and field.tag == 0xA0 then field=tlv(der,field.next) end
   if not field or field.tag ~= 0x02 then return nil,errorTable("invalid_certificate") end
   local serial,position=field.value,field.next
   while position < tbs.next do
      field=tlv(der,position)
      if not field then return nil,errorTable("invalid_certificate") end
      if field.tag == 0xA3 then break end
      position=field.next
   end
   if not field or field.tag ~= 0xA3 then return nil,errorTable("ari_id_unavailable") end
   local extensions=tlv(der,field.start)
   if not extensions or extensions.tag ~= 0x30 then return nil,errorTable("invalid_certificate") end
   position=extensions.start
   while position < extensions.next do
      local extension=tlv(der,position)
      local item=extension and extension.tag == 0x30 and tlv(der,extension.start)
      if not item or item.tag ~= 0x06 then return nil,errorTable("invalid_certificate") end
      local oid=item.value
      item=tlv(der,item.next)
      if item and item.tag == 0x01 then item=tlv(der,item.next) end
      if not item or item.tag ~= 0x04 then return nil,errorTable("invalid_certificate") end
      if oid == "U\29#" then
         local sequence=tlv(item.value,1)
         local aki=sequence and sequence.tag == 0x30 and tlv(item.value,sequence.start)
         while aki do
            if aki.tag == 0x80 then return ba.b64urlencode(aki.value).."."..ba.b64urlencode(serial) end
            if aki.next >= sequence.next then break end
            aki=tlv(item.value,aki.next)
         end
         return nil,errorTable("ari_id_unavailable")
      end
      position=extension.next
   end
   return nil,errorTable("ari_id_unavailable")
end
