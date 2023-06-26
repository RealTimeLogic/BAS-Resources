-- MQTT 5.0 Client. Copyright Real Time Logic. 
local fmt=string.format
local btaCreate,btaCopy,btah2n,btan2h,btaSize,btaSetsize,bta2string=
   ba.bytearray.create,ba.bytearray.copy,ba.bytearray.h2n,ba.bytearray.n2h,
   ba.bytearray.size,ba.bytearray.setsize,ba.bytearray.tostring
local sbyte,ssub=string.byte,string.sub
local tinsert,tsort=table.insert,table.sort

local startMQTT -- forward decl

local MQTT_CONNECT     = 0x01 << 4
local MQTT_CONACK      = 0x02 << 4
local MQTT_PUBLISH     = 0x03 << 4
local MQTT_PUBACK      = 0x04 << 4
local MQTT_PUBREC      = 0x05 << 4
local MQTT_PUBREL      = 0x06 << 4
local MQTT_PUBCOMP     = 0x07 << 4
local MQTT_SUBSCRIBE   = 0x08 << 4
local MQTT_SUBACK      = 0x09 << 4
local MQTT_UNSUBSCRIBE = 0x0a << 4
local MQTT_UNSUBACK    = 0x0b << 4
local MQTT_PINGREQ     = 0x0c << 4
local MQTT_PINGRESP    = 0x0d << 4
local MQTT_DISCONNECT  = 0x0e << 4
-- local MQTT_AUTH  = 0x0f << 4

local function fmtArgErr(argno,exp,got)
   return fmt("bad argument #%d (%s expected, got %s)", argno,exp,type(got))
end

local function argchk(argno,exp,got,level)
   if exp ~= type(got) then error(fmtArgErr(argno,exp,got),level or 2) end
end

local function typeChk(name,typename,val,level)
   if type(val) == typename then return end
   error(fmt("%s: expected %s, got %s",name,typename,type(val)), level or 3)
end

local function copyTab(t)
   local nt={}
   if t then
      for k,v in pairs(t) do nt[k]=v end
   end
   return nt
end

local function copy2Tab(to,from)
   for k,v in pairs(from) do to[k]=v end
end

local function getPacketId(self)
   local id = self.packetId
   id=id+1
   self.packetId = id < 0xFFFF and id or 1
   return self.packetId
end

local function getSubscriptionId(self)
   local id = self.subscriptionId
   id=id+1
   self.subscriptionId = id < 268435455 and id or 1
   return self.subscriptionId
end

local function insertRecQosT(self,pi,bta)
   local cnt=self.recQosCounter
   self.recQosCounter=cnt+1
   self.recQosQT[pi]={bta=bta,counter=cnt}
end

local function insertSndQosT(self,pi,bta)
   local cnt=self.sndQosCounter
   self.sndQosCounter=cnt+1
   self.sndQosQT[pi]={bta=bta,counter=cnt}
end

local function sortCosQT(qosQT)
   local sortT={}
   for k,v in pairs(qosQT) do tinsert(sortT,v) end
   tsort(sortT, function(a,b) return a.counter < b.counter end)
   return sortT
end

-- Encode Variable Byte Integer
local function encVBInt(bta,ix,len)
   if bta then
      local digit
      while true do
	 digit = len % 0x80
	 len = len // 0x80
	 if len == 0 then break end
	 bta[ix] = digit | 0x80
	 ix=ix+1
      end
      bta[ix] = digit
      return ix+1
   end
   while true do
      len = len // 0x80
      if len == 0 then break end
      ix=ix+1
   end
   return ix+1
end

-- Encode byte
local function encByte(bta,ix,byte)
    if bta then bta[ix]=byte end
   return ix+1
end

-- Encode 2 byte integer
local function enc2BInt(bta,ix,number)
    if bta then btah2n(bta,ix,2,number) end
   return ix+2
end

-- Encode 4 byte integer
local function enc4BInt(bta,ix,number)
   if bta then btah2n(bta,ix,4,number) end
   return ix+4
end


-- Encode utf8 valid string
local function encString(bta,ix,str)
   local len=#str
   if bta then
      btah2n(bta,ix,2,len)
      bta[ix+2]=str
   end
   return ix+2+len
end

-- Encode Binary Data
local encBinData=encString

local function btaCreate2(packetLen)
   return btaCreate(1+encVBInt(nil,0,packetLen)+packetLen)
end


local encPropT={
   payloadformatindicator={1,encByte}, --Payload Format Indicator
   messageexpiryinterval={2,enc4BInt}, --Message Expiry Interval
   contenttype={3,encString}, -- Content Type
   responsetopic={8,encString}, --Response Topic
   correlationdata={9,encBinData}, -- Correlation Data
   zz_subid={11,encVBInt}, --Subscription Identifier (private)
   sessionexpiryinterval={17,enc4BInt}, --Session Expiry Interval
   requestprobleminformation={23,encByte}, --Request Problem Information
   willdelayinterval={24,enc4BInt}, --Will Delay Interval
   requestresponseinformation={25,encByte}, --Request Response Information
   ["$reason"]={31,encString}, --Reason String
   -- 38 User Property
   maximumpacketsize={39,enc4BInt} --Maximum Packet Size
}

local function encProp(bta,ix,name,val)
   local propA=encPropT[name]
   if propA then
      ix=encByte(bta,ix,propA[1])
      return propA[2](bta,ix,val) -- ret ix
   end
   -- User Property: 38
   ix=encByte(bta,ix,38)
   ix=encString(bta,ix,name)
   return encString(bta,ix,val) -- ret ix
end

local function encPropT(bta,ix,propT)
   if not propT then return ix end
   for name,val in pairs(propT) do
      ix = encProp(bta,ix,name,val)
   end
   return ix
end


local function checkWill(w, level)
   w.qos = w.qos or 0
   typeChk("opt.will", "table",w,level)
   typeChk("opt.will.topic", "string",w.topic,level)
   if w.prop then typeChk("opt.will.prop", "table",w.prop,level) end
   typeChk("opt.will.payload", "string",w.payload,level)
end


local function encConnect(self, cleanStart)
   local opt = self.opt
   local prop=self.prop
   local w -- will

   if not prop.sessionexpiryinterval or prop.sessionexpiryinterval==0 then
      cleanStart=true
   end

   -- Calculate total packet len
    -- 10 = 2+4+1+1+2: protlen+'MQTT'+version+flags+keepalive
   local wPropLen
   local ix=encString(nil,10,opt.clientidentifier)
   local propLen=encPropT(nil,0,prop)
   ix=encVBInt(nil,ix+propLen,propLen)
   if opt.will then
      w=opt.will
      checkWill(w,5)
      wPropLen=encPropT(nil,0,w.prop)
      ix=encVBInt(nil,ix+wPropLen,wPropLen)
      ix=encString(nil,ix,w.topic)
      ix=encString(nil,ix,w.payload or "")
   end
   if opt.username then
      typeChk("opt.username", "string",opt.username,4)
      ix=encString(nil,ix, opt.username)
   end
   if opt.password then
      typeChk("opt.password", "string",opt.password,4)
      ix=encString(nil,ix, opt.password)
   end

   -- Create and format packet
   local packetLen=ix
   local bta=btaCreate2(packetLen)
   ix=encByte(bta,1,MQTT_CONNECT)
   ix=encVBInt(bta,ix,packetLen)
   ix=encString(bta,ix,"MQTT")
   ix=encByte(bta,ix,5) -- version
   local flags=(opt.username and 0x80 or 0) |
	       (opt.password and 0x40 or 0) |
	       (cleanStart and 0x02 or 0)
   if w then
      flags=flags |
	    (w.retain and 0x20 or 0) |
	    (w.qos << 2) |
	    0x04
   end
   ix=encByte(bta,ix,flags)
   ix=enc2BInt(bta,ix,opt.keepalive)
   ix=encVBInt(bta,ix,propLen)
   ix=encPropT(bta,ix,prop)
   ix=encString(bta,ix,opt.clientidentifier)
   if w then -- Will
      ix=encVBInt(bta,ix,wPropLen)
      ix=encPropT(bta,ix,w.prop)
      ix=encString(bta,ix,w.topic)
      ix=encBinData(bta,ix,w.payload)
   end
   if opt.username then ix=encString(bta,ix, opt.username) end
   if opt.password then ix=encString(bta,ix, opt.password) end

   if (ix-1) ~= ba.bytearray.size(bta) then
      error(fmt("ix~=bta size: %d ~= %d",ix-1,ba.bytearray.size(bta)))
   end
    
   return bta
end


-- Decode Variable Byte Integer
local function decVBInt(bta,ix)
   local mult,len=1,0
   repeat
      local digit=bta[ix]
      len=len+(digit&0x7F)*mult
      mult=mult*0x80
      ix=ix+1
   until digit < 0x80
   return len,ix
end

-- Decode byte
local function decByte(bta,ix)
   return bta[ix],ix+1
end

-- Decode 2 byte integer
local function dec2BInt(bta,ix)
   return btan2h(bta,ix,2),ix+2
end

-- Decode 4 byte integer
local function dec4BInt(bta,ix)
   return btan2h(bta,ix,4),ix+4
end


-- Decode utf8 string
local function decString(bta,ix,str)
   local len=btan2h(bta,ix,2)
   ix=ix+2
   local endIx=ix+len
   return bta2string(bta,ix,endIx-1), endIx
end


-- Decode Binary Data
local decBinData=decString

local decPropT={
   [1]={"payloadformatindicator", decByte},
   [2]={"messageexpiryinterval", dec4BInt},
   [3]={"contenttype", decString},
   [8]={"responsetopic", decString},
   [9]={"correlationdata", decBinData},
   [11]={"subscriptionidentifier", decVBInt},
   [17]={"sessionexpiryinterval", dec4BInt},
   [18]={"assignedclientidentifier", decString},
   [19]={"serverkeepalive", dec2BInt},
   [21]={"authenticationmethod", decString},
   [22]={"authenticationdata", decBinData},
   [26]={"responseinformation", decString},
   [28]={"serverreference",	decString},
   [31]={"reasonstring", decString},
   [33]={"receivemaximum", dec2BInt},
   [34]={"topicaliasmaximum", dec2BInt},
   [35]={"topicalias", dec2BInt},
   [36]={"maximumqos", decByte},
   [37]={"retainavailable", decByte},
   [39]={"maximumpacketsize", dec4BInt},
   [40]={"wildcardsubscriptionavailable", decByte},
   [41]={"subscriptionidentifieravailable", decByte},
   [42]={"sharedsubscriptionavailable", decByte},
}


local function decodeProp(bta,ix,propT)
   local propId=bta[ix]
   ix=ix+1
   local propA=decPropT[propId]
   if propA then
      propT[propA[1]],ix= propA[2](bta,ix)
   elseif 38==propId then
      local key
      key,ix=decString(bta,ix)
      propT[key],ix=decString(bta,ix)
   else
      return nil
   end
   return ix
end

local function decodePropT(bta,propLen,ix)
   local propT={}
   while propLen > 0 do
      local sIx=ix
      ix=decodeProp(bta,ix,propT)
      if not ix then return nil,1 end
      propLen = propLen - (ix - sIx)
   end
   if propLen == 0 then return propT,ix end
   return nil,ix -- prot err
end

-- Wait for next MQTT packet
-- returns cpt,payload or nil,err. cpt: Control Packet Type e.g. CONNACK
local function mqttRec(self)
   local sock=self.sock
   local data,msg,err
   if self.recOverflowData then
      data = self.recOverflowData
      self.recOverflowData =nil
   else
      data=""
   end
   local mult,len,ix = 1,0,1
   repeat
      ix = ix + 1
      while #data < ix do
	 msg,err = sock:read()
	 if not msg then return nil,err end
	 data = data..msg
      end
      local digit = sbyte(data,ix)
      len = len + (digit & 0x7F) * mult
      mult = mult * 0x80
   until digit < 0x80
   local cpt = sbyte(data,1)
   local bta
   if len > 0 then
      bta=btaCreate(len)
      local overflow=btaCopy(bta,1,data,ix+1,-ix-1)
      local plen=#data-ix
      while plen < len do
	 data,err = sock:read()
	 if not data then return nil,err end
	 overflow=btaCopy(bta,1+plen,data)
	 plen = plen+#data
      end
      if overflow > 0 then
	 self.recOverflowData = ssub(data, #data-overflow+1)
      end
   end
   return cpt,bta
end

-- Remove from tail and send
local function sndCosock(sock,self)
   local sndQT=self.sndQT
   while true do
      local sndQTail=self.sndQTail
      if self.sndQHead == sndQTail then sock:disable() end
      if not self.connected then return end
      assert(self.sndQHead ~= sndQTail)
      local bta=sndQT[sndQTail]
      assert(bta)
      if not self.sock:write(bta) then
	 self.connected = false
	 return
      end
      sndQT[sndQTail]=nil
      self.sndQTail=sndQTail+1
      self.sndQElems=self.sndQElems-1
   end
end


-- Send 2 sock or queue on head
local function sendMsg(self, bta)
   if self.sndQHead == self.sndQTail and self.connected then
      local ok,status=self.sock:write(bta)
      if ok then return end
      if "string" == type(status) then -- sock err
	 self.lasterror={etype="sock",status=status}
	 self.connected=false
      end
   end
   local sndQHead=self.sndQHead
   assert(nil == self.sndQT[sndQHead])
   self.sndQT[sndQHead]=bta
   self.sndQHead = sndQHead+1
   self.sndQElems=self.sndQElems+1
   if self.connected then self.sndCosock:enable() end
end

local function sendPing(self)
   local pingCounter=self.pingCounter
   pingCounter = pingCounter+1
   if pingCounter == 2 then
      local bta=btaCreate2(0)
      bta[1]=MQTT_PINGREQ
      bta[2]=0 -- packet len
      sendMsg(self,bta)
   elseif pingCounter > 2 then
      self.lasterror={etype="mqtt",status="pingtimeout"}
      self.connected=false
      self.sock:close()
   end
   self.pingCounter=pingCounter
end

-- used by recPubrec,recPubrel
local function sendAckResp(self,cpt,pi,reason)
   local bta=btaCreate2(4)
   bta[1]=cpt
   bta[2]=4 -- packet len
   btah2n(bta,3,2,pi)
   bta[5]=reason
   bta[6]=0 -- prop len
   sendMsg(self,bta)
   return bta
end

-- used by recPuback,recPubrec,recPubrel,recPubcomp
local function decAck(bta)
   local reason = btaSize(bta) == 2 and 0 or bta[3]
   return btan2h(bta,1,2),reason
end

local function recPublish(self,bta,cpt)
   local propT,pid
   local topic,ix=decString(bta, 1)
   if topic then
      local qos=(cpt>>1)&3
      if qos > 0 then pid,ix=dec2BInt(bta,ix) end
      propT,ix=decodePropT(bta,decVBInt(bta,ix))
      if propT then
	 local qosQT=self.recQosQT
	 if not qosQT[pid] then -- nil if pid is nil; if not a dup
	    local onpub=self.onpubT[propT.subscriptionidentifier] or self.onpub
	    btaSetsize(bta,ix)
	    onpub(topic,self.recbta and bta or bta2string(bta),propT,cpt)
	 end
	 -- else drop dup msg
	 if qos == 0 then return true end
	 bta=sendAckResp(self,qos==1 and MQTT_PUBACK or MQTT_PUBREC,pid,0)
	 if qos==2 then insertRecQosT(self,pid,bta) end
	 return true
      end
   end
   return nil,"mqtt","protocolerror"
end

local function recPuback(self,bta)
   local pid,reason=decAck(bta)
    -- Add log
   self.sndQosQT[pid]=nil
   return true
end

local function recPubrec(self,bta)
   local qT=self.sndQosQT
   local pid,reason=decAck(bta)
    -- Add log
   if reason < 0x80 then
      reason=qT[pid] and 0 or 146
      bta=sendAckResp(self,MQTT_PUBREL|2,pid,reason)
      if 0 == reason then
	 insertSndQosT(self,pid,bta)
	 return true
      end
   end
   qT[pid]=nil
   return true
end

local function recPubrel(self,bta)
   local pid,reason=decAck(bta)
   -- Add log if not self.recQosQT[pid]
   self.recQosQT[pid]=nil
   sendAckResp(self,MQTT_PUBCOMP,pid,reason)
   return true
end

local function recPubcomp(self,bta)
   local pid,reason=decAck(bta)
   -- Add log if not self.sndQosQT[pid]
   self.sndQosQT[pid]=nil
   return true
end

local function removeOnpubInfo(self, topic)
   local subid = self.topicT[topic]
   if subid then
      self.topicT[topic]=nil
      self.onpubT[subid]=nil
   end
end

local function recSuback(self,bta)
   local pi,ix=dec2BInt(bta,1)
   local propT
   propT,ix = decodePropT(bta,decVBInt(bta,ix))
   if not propT then return nil,"mqtt","protocolerror" end
   local reason=bta[ix]
   local t = self.subackQT[pi]
   self.sndQosQT[pi]=nil
   if t then
      self.subackQT[pi]=nil
      removeOnpubInfo(self, t.topic) -- dups, if any
      if t.onsuback then t.onsuback(t.topic,reason,propT) end
      if reason < 0x80 then
	 if t.onpub then
	    self.onpubT[t.subid]=t.onpub
	    self.topicT[t.topic]=t.subid
	 end
      end
   else
      --Add log
   end
   return true
end


local function recUnsuback(self,bta)
   local pi,ix=dec2BInt(bta,1)
   local propT
   propT,ix = decodePropT(bta,decVBInt(bta,ix))
   if not propT then return nil,"mqtt","protocolerror" end
   local reason=bta[ix]
   local t = self.subackQT[pi]
   self.sndQosQT[pi]=nil
   if t then
      self.subackQT[pi]=nil
      removeOnpubInfo(self, t.topic) -- dups, if any
      if t.onunsubscribe then t.onunsubscribe(t.topic,reason,propT) end
   else
      --Add log
   end
   return true
end

local function recPingresp(self,bta)
   self.pingCounter=0
   return true
end

local function recDisconnect(self,bta)
   local propT,ix = decodePropT(bta,decVBInt(bta,2))
   if propT then
      local statusT={reasoncode=bta[1], properties=propT}
      return nil,"mqtt","disconnect", statusT
   end
   return nil,"mqtt","protocolerror"
end

local recCpT={
   [MQTT_PUBLISH]=recPublish,
   [MQTT_PUBACK]=recPuback,
   [MQTT_PUBREC]=recPubrec,
   [MQTT_PUBREL]=recPubrel,
   [MQTT_PUBCOMP]=recPubcomp,
   [MQTT_SUBACK]=recSuback,
   [MQTT_UNSUBACK]=recUnsuback,
   [MQTT_PINGRESP]=recPingresp,
   [MQTT_DISCONNECT]=recDisconnect
}


local function resetQueues(self,save) -- Call at start or when not clean restart
   if save then
      self.savedT={
	 recQosQT=self.recQosQT,sndQosQT=self.sndQosQT,subackQT=
	    self.subackQT,onpubT=self.onpubT,topicT=self.topicT,
      }
   end
   self.recQosQT,self.sndQosQT,self.subackQT,self.onpubT,self.topicT=
      {},{},{},{},{}
end


local function restoreQueues(self,session)
   if session then
      local t=self.savedT
      copy2Tab(self.recQosQT,t.recQosQT)
      copy2Tab(self.sndQosQT,t.sndQosQT)
      copy2Tab(self.subackQT,t.subackQT)
      copy2Tab(self.onpubT,t.onpubT)
      copy2Tab(self.topicT,t.topicT)
      local qT=self.recQosQT
      if next(qT) then -- if not empty
	 for _,t in pairs(sortCosQT(qT)) do sendMsg(self, t.bta) end
      end
      qT=self.sndQosQT
      if next(qT) then -- if not empty
	 for _,t in pairs(sortCosQT(qT)) do
	    local bta=t.bta
	    local cpt=bta[1]
	    if (cpt & 0xF0) == MQTT_PUBLISH then bta[1]=cpt|0x08 end  --DUP flag
	    sendMsg(self, bta)
	 end
      end
   end
   self.savedT=nil
end

local function onErrStatus(self,etype,code)
   local reconn=self.onstatus(etype,code)
   if reconn then
      self.reconTimeout = "number" == type(reconn) and reconn
   end
   return reconn
end

local function coMqttRun(self)
   local ok,etype,status,valT
   while self.connected do
      local cpt,bta=mqttRec(self)
      if not cpt then status=bta break end
      local func = recCpT[cpt&0xF0]
      if not func then etype,status="mqtt","protocolerror" break end
      ok,etype,status,valT=func(self,bta,cpt)
      if not ok then break end
      etype,status,valT=nil,nil,nil
   end
   local lasterror=self.lasterror
   self.connected,self.lasterror,self.recOverflowData=false,nil,nil
   if self.pingTimer then self.pingTimer:cancel() end
   resetQueues(self, true)
   if not etype then
      local lasterror=self.lasterror
      if lasterror then
	 etype,status=lasterror.etype,lasterror.status
      else
	 status=status or ""
	 etype="sock"
      end
   end
   if not self.disconnected and onErrStatus(self,etype,status,valT) then
      self.connectTime=nil
      if "sysshutdown" ~= status then
	 startMQTT(self,encConnect(self,false))
      end
   end
end

local function coMqttConnect(sock,self,conbta)
   local reconnect
   self.sock=sock
   sock:write(conbta)
   local cpt,bta=mqttRec(self)
   if cpt then
      if (cpt&0xF0) == MQTT_CONACK then
	 local ackProp = decodePropT(bta,decVBInt(bta,3))
	 if ackProp then
	    local session=(bta[1] & 1) == 1 and true or false
	    local reason=bta[2]
	    reconnect=self.onstatus("mqtt","connect",{
	       sessionpresent=session,reasoncode=reason, properties=ackProp})
	    if reason == 0 and reconnect then
	       local opt=self.opt
	       if ackProp.serverkeepalive and
		  ackProp.serverkeepalive ~= opt.keepalive then
		  opt.keepalive = ackProp.serverkeepalive
	       end
	       if opt.keepalive ~= 0 then
		  self.pingCounter=0
		  self.pingTimer=ba.timer(function() sendPing(self) return true end)
		  self.pingTimer:set(opt.keepalive*1000//2)
	       end
	       local prop=self.prop
	       if ackProp.sessionexpiryinterval and
		  ackProp.sessionexpiryinterval ~= prop.sessionexpiryinterval then
		  prop.sessionexpiryinterval = ackProp.sessionexpiryinterval
	       end
	       self.connected=true
	       restoreQueues(self,session)
	       self.sndCosock=ba.socket.event(sndCosock,self)
	       coMqttRun(self)
	       return -- done
	    end
	 end
      end
      if reconnect == nil then
	 reconnect=onErrStatus(self,"mqtt","protocolerror")
      end
   else
      reconnect=onErrStatus(self,"sock",bta)
   end
   if reconnect then
      startMQTT(self,conbta,false)
   end
end

local function coSockConnect(cosock,self,conbta)
   self.connectTime=ba.clock()//1000
   local sock,err=self.connect(self,self.opt)
   if self.disconnected then
      if sock then sock:close() end
      return
   end
   self.sock=sock
   if not sock then
      if onErrStatus(self,"sock",err) then
	 -- Avoid recursion
	 startMQTT(self,conbta,true)
      end
   else
      coMqttConnect(sock,self,conbta)
   end
end


local C={} -- MQTT Client
C.__index=C

function C:publish(topic,msg,opt,prop)
   local opt=opt or {}
   local qos=opt.qos or 0
   qos=(qos&3) << 1
   local retain=opt.retain and 1 or 0
   -- Calc
   local propLen=encPropT(nil,0,prop)
   local ix=encVBInt(nil,(qos>0 and 3 or 1) + propLen,propLen)
   ix=encString(nil, ix, topic)
   packetLen = ix+#msg-1
   -- Create
   local bta=btaCreate2(packetLen)
   bta[1]=MQTT_PUBLISH | qos | retain
   ix=encVBInt(bta,2,packetLen)
   ix=encString(bta, ix, topic)
   if qos>0 then
      local pi=getPacketId(self)
      ix=enc2BInt(bta,ix,pi)
      insertSndQosT(self,pi,bta)
   end
   ix=encVBInt(bta,ix,propLen)
   ix=encPropT(bta,ix,prop)
   bta[ix]=msg
   sendMsg(self, bta)
   return self.connected
end


local function sendSubOrUnsub(self,topic,onack,prop,subOptions)
   local pi=getPacketId(self)
   -- Calc size
   local ix=subOptions and 2 or 1
   local propLen=encPropT(nil,0,prop)
   local ix=encVBInt(nil,ix+propLen,0)
   ix=enc2BInt(nil,ix, pi)
   ix=encString(nil,ix,topic)
   --Encode
   local packetLen=ix-1
   local bta=btaCreate2(packetLen)
   ix=encByte(bta,1,(subOptions and MQTT_SUBSCRIBE or MQTT_UNSUBSCRIBE) | 2)
   ix=encVBInt(bta,ix,packetLen)
   ix=enc2BInt(bta,ix, pi)
   ix=encVBInt(bta,ix,propLen)
   ix=encPropT(bta,ix,prop)
   ix=encString(bta,ix,topic)
   if subOptions then encByte(bta,ix,subOptions) end -- subscribe
   insertSndQosT(self,pi,bta)
   sendMsg(self, bta)
   return pi
end


function C:subscribe(topic,onsuback,opt,prop)
   if "table" == type(onsuback) then
      prop=opt
      opt=onsuback
      onsuback=nil
   end
   opt = opt or {}
   prop=copyTab(prop)
   if opt.onpub then
      prop.zz_subid = getSubscriptionId(self)
   end
   local retain=opt.retainaspublished==true and 8 or 0
   local retainhandling=0~=retain and ((opt.retainhandling or 0) << 4) or 0
   local nolocal = opt.nolocal and 4 or 0
   local qos=opt.qos or 0
   qos=qos&3
   local subOptions = retainhandling | retain | nolocal | qos
   local pi=sendSubOrUnsub(self,topic,onsub,prop,subOptions)
   self.subackQT[pi]={topic=topic,onsuback=onsuback,onpub=opt.onpub,subid=prop.zz_subid}
   return self.connected
end


function C:unsubscribe(topic,onunsubscribe,prop)
   local pi=sendSubOrUnsub(self,topic,onunsubscribe,prop)
   self.subackQT[pi]={topic=topic,onunsubscribe=onunsubscribe}
   return self.connected
end

function C:disconnect(reason)
   local retv=self.connected
   local disconnected=self.disconnected
   self.disconnected=true
   if not disconnected then
      local bta=btaCreate2(2)
      bta[1]=MQTT_DISCONNECT
      bta[2]=2 -- packet len
      bta[3]=reason or 0
      bta[4]=0 -- prop len
      sendMsg(self,bta)
      if self.sock then self.sock:close() end
   end
   self.connected=false
   return retv
end

function C:close() pcall(function() self:disconnect() end) end
C.__gc=C.close
C.__close=C.close



function C:setwill(w)
   checkWill(w, 3)
   self.opt.will=w
end


function C:status()
   return self.sndQElems,self.connected,(self.disconnected and true or false)
end

startMQTT=function(self,conbta,defer)
   local function conn() ba.socket.event(coSockConnect,self,conbta) end
   if self.connectTime then
      local timeout = self.reconTimeout or 5
      local delta = ba.clock()//1000 - self.connectTime
      if delta > 0 and delta < timeout then timeout = timeout - delta end
      if timeout > 0 then
	 ba.timer(conn):set(timeout*1000,true)
	 return
      end
   end
   if defer then
      ba.thread.run(conn)
   else
      conn()
   end
end

local function connect2addr(self,opt)
   if not opt.timeout then opt.timeout=5000 end
   local sock,err=ba.socket.connect(
      self.addr, opt.port or (opt.shark and 8883 or 1883), opt)
   if not sock then return nil,err end
   if opt.shark and not opt.nocheck then
      local trusted,status = sock:trusted(addr)
      if not trusted then return nil, status end
   end
   return sock
end

local function create(addr, onstatus, onpub, opt, prop)
   if "function" ~= type(addr) and "string" ~= type(addr) then
      error(fmtArgErr(1,"string | function",addr),2)
   end
   argchk(2,"function",onstatus)
   if "table" == type(onpub) then
      prop=opt
      opt=onsuback
      onpub=nil
   end
   if onpub then
      argchk(3,"function",onpub)
   else
      onpub=function(topic) trace("Received unhandled MQTT topic",topic) end
   end
   opt=opt or {}
   prop=prop or {}
   argchk(4,"table",opt)
   argchk(4,"table",prop)
   opt=copyTab(opt)
   local self={
      connected=false,
      recQosCounter=0,sndQosCounter=0,
      packetId=0,subscriptionId=0,
      sndQT={},sndQHead=1,sndQTail=1,sndQElems=0,
      onstatus=onstatus,onpub=onpub,opt=opt,
      connect = "function" == type(addr) and addr or connect2addr
   }
   self.recbta = not (opt.recbta==false) -- default true
   resetQueues(self)
   if "function" == type(addr) then
      self.connect=addr
   else
      self.connect=connect2addr
      self.addr=addr
   end
   if prop then self.prop=copyTab(prop) end
   opt.clientidentifier=opt.clientidentifier or ba.b64urlencode(ba.rndbs(15))
   if opt.keepalive then
      typeChk("opt.keepalive", "number",opt.keepalive)
   else
      opt.keepalive=0
   end
   if opt.secure then
      if opt.secure == true then
	 opt.shark=ba.sharkclient()
      else
	 typeChk("opt.secure", "userdata",opt.secure)
	 opt.shark=opt.secure
      end
      opt.secure=nil
   end
   startMQTT(self,encConnect(self,true))
   return setmetatable(self,C)
end

local function backwardCompat(...)
   return require"mqtt3c".connect(...)
end

return {
   create=create,
   connect=backwardCompat
}
