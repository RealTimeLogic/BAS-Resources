-- SMQ Lua client; Copyright Real Time Logic.
local fmt=string.format
local btaCreate,btah2n=ba.bytearray.create,ba.bytearray.h2n
local sbyte,ssub=string.byte,string.sub
local tinsert,tconcat=table.insert,table.concat
local sn2h=ba.socket.n2h
local jenc,jdec=ba.json.encode,ba.json.decode

local MsgInit <const> = 1
local MsgConnect <const> = 2
local MsgConnack <const> = 3
local MsgSubscribe <const> = 4
local MsgSubscribeAck <const> = 5
local MsgCreate <const> = 6
local MsgCreateAck <const> = 7
local MsgPublish <const> = 8
local MsgUnsubscribe <const> = 9
local MsgDisconnect <const> = 11
local MsgPing <const> = 12
local MsgPong <const> = 13
local MsgObserve <const> = 14
local MsgUnobserve <const> = 15
local MsgChange <const> = 16
local MsgCreateSub <const> = 17
local MsgCreateSubAck <const> = 18

local startSMQ -- forward decl

local serveECodes={
   [0x02]="Server Unavailable",
   [0x03]="Incorrect Credentials",
   [0x04]="Client Certificate Required",
   [0x05]="Client Certificate Not Accepted",
   [0x06]="Access Denied"
}

local function log(...)
   tracep(false,5,"SMQC:",...)
end

-- The following 3 functions create and encode ByteArrays (bta)
local function createMsg(len,msg) -- SMQ message and packet header
   local bta=btaCreate(len)
   btah2n(bta,1,2,len)
   bta[3]=msg
   return bta,4
end
local function enc4BInt(bta,ix,number) btah2n(bta,ix,4,number) return ix+4 end
local function encString(bta,ix,str) bta[ix]=str return ix+#str end

local function fmtArgErr(argno,exp,got)
   return fmt("bad argument #%d (%s expected, got %s)",argno,exp,type(got))
end

local function argchk(argno,exp,got,level)
   if exp ~= type(got) then error(fmtArgErr(argno,exp,got),level or 3) end
end

local function typeChk(name,typename,val,level)
   if type(val) == typename then return end
   error(fmt("%s: expected %s, got %s",name,typename,type(val)),level or 3)
end


local function smqRec(sock,data,tmo)
   local err
   if not data then data,err = sock:read(tmo) end
   if data then
      if #data < 2 then
	 local d=data
	 data,err = sock:read(tmo)
	 if not data then return nil,err end
	 data=d..data
      end
      local len=sn2h(2,data)
      if len > #data then
	 local t={data}
	 local bytesRead = #data
	 while bytesRead < len do
	    data,err = sock:read(tmo)
	    if not data then return nil,err end
	    tinsert(t,data)
	    bytesRead = bytesRead + #data
	 end
	 data=tconcat(t)
      end
      if len == #data then return data end
      assert(#data > len)
      return data:sub(1,len),data:sub(len+1) -- data and remainder
   end
   return nil,err
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
local function sendMsg(self,bta)
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

local function initSelf(self)
   local t={
      sndQT={},sndQHead=1,sndQTail=1,sndQElems=0,
      tid2topicT={}, --Key= tid, val = topic name
      topic2tidT={}, --Key=topic name, val=tid
      topicAckCBT={}, --Key=topic name, val=array of callback funcs
      tid2subtopicT={}, --Key= tid, val = subtopic name
      subtopic2tidT={}, --Key=sub topic name, val=tid
      subtopicAckCBT={}, --Key=sub topic name, val=array of callback funcs
      onMsgCBT={}, --Key=tid, val = {all: CB, subtops: {stid: CB}}
      observeT={}, --Key=tid, val = onchange callback
      connected=false
   }
   for k,v in pairs(t) do self[k]=v end
   return self
end


local function onclose(self,err,canreconnect,msg)
   if msg then log(msg) end
   local reconn = self.onclose and self.onclose(err,canreconnect)
   self.reconTimeout = canreconnect and "number" == type(reconn) and reconn
   initSelf(self)
   return reconn
end

local function msgAck(self,data,tid2top,top2tid,ackCBT)
   local accepted=data:byte(4) == 0 and true or false
   local tid=sn2h(4,data,5)
   local topic=data:sub(9,-1)
   if accepted then tid2top[tid],top2tid[topic]=topic,tid end
   for _,onack in ipairs(ackCBT[topic]) do onack(accepted,topic,tid) end
   return true
end

local function msgSubscribeAck(self,data)
   msgAck(self,data,self.tid2topicT,self.topic2tidT,self.topicAckCBT)
   return true
end

local function msgCreateAck(self,data)
   msgAck(self,data,self.tid2topicT,self.topic2tidT,self.topicAckCBT)
   return true
end

local function msgCreateSubAck(self,data)
   msgAck(self,data,self.tid2subtopicT,self.subtopic2tidT,self.subtopicAckCBT)
   return true
end

local function msgPublish(self,data)
   local tid = sn2h(4,data,4)
   local ptid = sn2h(4,data,8)
   local subtid = sn2h(4,data,12)
   data=data:sub(16)
   local cbFunc
   local t = self.onMsgCBT[tid]
   cbFunc = t and (t.subtops[subtid] or t.onmsg) or self.onmsg or function() log("drop",tid) end
   cbFunc(data,ptid,tid,subtid)
   return true
end

local function msgDisconnect(self,data)
   return false,"Disconnect request"
end

local function msgPing(self,data)
   sendMsg(self,createMsg(3,MsgPong))
   return true
end

local function msgPong(self,data)
   sendMsg(self,createMsg(3,MsgPing))
   return true
end

local function msgChange(self,data)
   local tid = sn2h(4,data,4)
   local num = sn2h(4,data,8)
   local topic = self.tid2topicT[tid]
   local func = self.observeT[tid]
   if func then
      if not topic and num == 0 then
	 self.observeT[tid]=nil -- Remove ephemeral
      end
      func(num,topic or tid)
   end
   return true
end



local recMsgT={
   [MsgSubscribeAck] = msgSubscribeAck,
   [MsgCreateAck] = msgCreateAck,
   [MsgPublish] = msgPublish,
   [MsgDisconnect] = msgDisconnect,
   [MsgPing] = msgPing,
   [MsgPong] = msgPong,
   [MsgChange] = msgChange,
   [MsgCreateSubAck] = msgCreateSubAck
}

local function coSmqRun(self)
   local sock,data,err=self.sock
   while self.connected do
      data,err=smqRec(sock,data)
      if not data then break end
      local func = recMsgT[data:byte(3)]
      if not func then err = "protocolerror" break end
      ok,err=func(self,data)
      if not ok then break end
      data = err -- err is remainder, if any
   end
   self.etid=nil
   self.disconnectCnt=self.disconnectCnt+1
   self.connected=false
   if not self.disconnected and onclose(self,err,true) then
      self.connectTime=nil
      if "sysshutdown" ~= err then startSMQ(self) end
   end
end

local function coSmqConnect(sock,self,data)
   self.sock=sock
   local canreconnect,err=true
   data,err=smqRec(sock,data,self.opt.timeout)
   if data then
      if data:byte(3) == MsgInit and data:byte(4) == 1 then
	 local rnd,ip=sn2h(4,data,5),data:sub(9,-1)
	 local uid=self.opt.uid or (ip..self.sock:sockname())
	 local info = self.opt.info or self.sock:sockname()
	 uid = #uid < 6 and (uid..ip) or ip
	 self.opt.uid=uid
	 local oa=self.onauth
	 local credentials = oa and oa(rnd,ip) or ""
	 local bta=createMsg(6+#uid+#credentials+#info,MsgConnect)
	 bta[4]=1 -- version
	 bta[5],bta[6]=#uid,uid
	 bta[6+#uid],bta[7+#uid]=#credentials,credentials
	 if #info > 0 then bta[7+#uid+#credentials]=info end
	 self.sock:write(bta)
	 data,err=smqRec(sock,nil,self.opt.timeout)
	 if data then
	    local status,etid=data:byte(4),sn2h(4,data,5)
	    if 0 == status then
	       self.etid=etid
	       self.connected=true
	       self.tid2topicT[etid]="self"
	       self.topic2tidT.self = etid
	       if self.disconnectCnt > 0 and self.onreconnect then
		  self.onreconnect(etid,rnd,ip)
	       elseif self.onconnect then
		  self.onconnect(etid,rnd,ip)
	       end
	       self.sndCosock=ba.socket.event(sndCosock,self)
	       coSmqRun(self)
	       return
	    end
	    err=serveECodes[status]
	 end
      else
	 err,canreconnect="nonsmq",false
      end
   end
   if "sysshutdown" == err then canreconnect = false end
   if onclose(self,err or "protocolerror",canreconnect) and canreconnect then
      startSMQ(self,true)
   end
end

local function coSockConnect(cosock,self)
   self.connectTime=ba.clock()
   local sock,err,msg
   local function callback(s,e,m) sock,err,msg=s,e,m cosock:enable() end
   self.connect(self,self.opt,callback)
   cosock:disable()
   if self.disconnected then
      if sock then sock:close() end
      return
   end
   if not sock then
      if onclose(self,err,"nonsmq" ~= err and true or false,msg) then
	 startSMQ(self,true)
      end
   else
      -- err may be set to remaining data
      if cosock == sock then
	 coSmqConnect(sock,self,err)
      else
	 sock:event(coSmqConnect,"s",self,err)
      end
   end
end

startSMQ=function(self,defer)
   local function conn() ba.socket.event(coSockConnect,self) end
   if self.connectTime then
      local timeout = self.reconTimeout or 5000
      local delta = ba.clock() - self.connectTime
      if delta > 0 and delta < timeout then timeout = timeout - delta end
      if timeout > 0 then
	 ba.timer(conn):set(timeout,true)
	 return
      end
   end
   if defer then
      ba.thread.run(conn)
   else
      conn()
   end
end


local function connect2url(self,opt,callback)
   local http = require"http".create(opt)
   http:timeout(opt.timeout)
   local h = opt.header or {}
   opt.header=h
   h.SimpleMQ,h.SendSmqHttpResponse="1","true"
   local ok,err,msg
   ba.thread.run(function()
      ok,err = http:request(opt)
      local status=http:status()
      if ok and 200 ~= status then
	 ok,err,msg=nil,"nonsmq",fmt("Expected HTTP 200, got %d %s",
            status or 0, tostring(err or ""))
      end
      if ok then
	 callback(ba.socket.http2sock(http))
      else
	 callback(nil,err,msg)
      end
   end)
end


local C={} -- SMQ Client
C.__index=C

local function createTopic(self,topic,top2tidT,ackCBT,msg,onack)
   local tid=top2tidT[topic]
   if tid then
      onack(true,topic,tid)
   else
      local arr=ackCBT[topic]
      if not arr then
	 local bta,ix=createMsg(3+#topic,msg)
	 encString(bta,ix,topic)
	 sendMsg(self,bta)
	 arr={}
	 ackCBT[topic]=arr
      end
      tinsert(arr,onack)
   end
end

function C:create(topic,onack)
   createTopic(self,topic,self.topic2tidT,self.topicAckCBT,MsgCreate,onack)
end

function C:createsub(topic,onack)
   createTopic(self,topic,self.subtopic2tidT,self.subtopicAckCBT,MsgCreateSub,onack)
end

function C:close()
   if not self.disconnected then
      self.disconnected=true
      if self.sock then
	 sendMsg(self,createMsg(3,MsgDisconnect))
	 self.sock:close()
      end
   end
   self.connected=false
end
C.__gc=C.disconnect
C.__close=C.disconnect

function C:gettid()
   return self.etid
end

function C:publish(data,topic,subtopic)
   local tid,stid
   if "string" == type(topic) then
      tid=self.topic2tidT[topic]
      if not tid then
	 self:create(topic,function(ok,_,t)
	    if not ok then log("pub failed",topic) return end
	    tid=t
	    if stid then self:publish(data,tid,stid) end
	 end)
      end
   elseif "number" == type(topic) then
      tid=topic
   else
      error(fmtArgErr(2,"string | number",topic),2)
   end
   if "string" == type(subtopic) then
      stid=self.subtopic2tidT[subtopic]
      if not stid then
	 self:createsub(subtopic,function(ok,_,t)
	    if not ok then log("pub failed",subtopic) return end
	    stid=t
	    if tid then self:publish(data,tid,stid) end
	 end)
      end
   else
      stid = "number" == type(subtopic) and subtopic or 0
   end
   if tid and stid then
      data = "table" == type(data) and jenc(data) or tostring(data)
      local bta,ix=createMsg(15+#data,MsgPublish)
      ix=enc4BInt(bta,ix,tid)
      ix=enc4BInt(bta,ix,self.etid)
      ix=enc4BInt(bta,ix,stid)
      if #data > 0 then encString(bta,ix,data) end
      sendMsg(self,bta)
   end
   return true
end

function C:subscribe(topic,subtopic,settings)
   local stid
   if not settings and "table" == type(subtopic) then
      settings,subtopic=subtopic,nil
   end

   local function subscribe()
      local function topicAck(ok,_,tid)
	 if settings.onack then settings.onack(ok,topic,tid,subtopic,stid) end
	 if not ok then
	    if not settings.onack then log("sub failed",topic) end
	    return
	 end
	 local onmsg=settings.onmsg
	 if onmsg then
	    local t = self.onMsgCBT[tid]
	    if not t then t = {subtops={}} self.onMsgCBT[tid] = t end
	    if "json" == settings.datatype then
	       local onmsg2=onmsg
	       onmsg=function(data,ptid,tid,subtid)
		  onmsg2(jdec(data) or data,ptid,tid,subtid)
	       end
	    end
	    if(stid) then
	       t.subtops[stid] = onmsg
	    else
	       t.onmsg = onmsg
	    end
	 end
      end
      if "self"==topic then
         topicAck(true,topic,self.etid)
      else
         createTopic(self,topic,self.topic2tidT,self.topicAckCBT,MsgSubscribe,topicAck)
      end
   end
   if subtopic then
      if "number" == type(subtopic) then
	 stid=subtopic
      else
	 argchk(2,"string",subtopic)
	 self:createsub(subtopic,function(ok,_,tid)
	    if ok then
	       stid=tid
	       subscribe()
	    elseif settings.onack then
	       settings.onack(ok,topic,0,subtopic,0)
	    end
	 end)
	 return
      end
   end
   subscribe()
end


local function sendMsgWithTid(self,msg,tid)
   local bta,ix=createMsg(7,msg)
   enc4BInt(bta,ix,tid)
   sendMsg(self,bta)
end

local function getTid(topic)
   local tid
   if "string" == type(topic) then
      tid=self.topic2tidT[topic]
      if not tid then error("No such topic") end
   else
      tid = topic
   end
   return tid
end


function C:unsubscribe(topic)
   local tid=getTid(topic)
   if self.onMsgCBT[tid] then
      self.onMsgCBT[tid]=nil
      sendMsgWithTid(self,MsgUnsubscribe,tid)
   end
end

function C:observe(topic,onchange)
   local tid=getTid(topic)
   if tid ~= self.etid and not self.observeT[tid] then
      self.observeT[tid] = onchange;
      sendMsgWithTid(self,MsgObserve,tid);
   end
end

function C:unobserve(topic)
   local tid=getTid(topic)
   if self.observeT[tid] then
      self.observeT[tid]=nil;
      sendMsgWithTid(self,MsgUnobserve,tid);
   end
end

function C:tid2topic(tid)
   return self.tid2topicT[tid]
end

function C:topic2tid(topic)
   return self.topic2tidT[topic]
end

function C:tid2subtopic(tid)
   return self.tid2subtopicT[tid]
end

function C:subtopic2tid(topic)
   return self.subtopic2tidT[topic]
end

local function create(url,opt)
   if "function" ~= type(url) and "string" ~= type(url) then
      error(fmtArgErr(1,"string | function",url),2)
   end
   opt=opt or {}
   opt.timeout = opt.timeout or 5000
   opt.url=url
   local self=initSelf{
      disconnectCnt=0,
      opt=opt,
      connect = "function" == type(url) and url or connect2url
   }
   startSMQ(self,true)
   return setmetatable(self,C)
end

return {create=create}
