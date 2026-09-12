--SMQ Cluster Manager. Copyright Real Time Logic.

local ba=ba
local sn2h=ba.socket.n2h
local sh2n=ba.socket.h2n
local assert=assert
local schar=string.char
local pairs=pairs
local next=next
local type=type
local _G=_G

local MsgSubscribe   = 1
local MsgSubTopic    = 3
local MsgSubTopicAck = 4
local MsgPublish     = 5
local MsgUnsubscribe = 7
local MsgRelease     = 8
local MsgPubSrv	     = 10


local MTL = require"smq/mtl"
local sendframe=MTL.sendframe

-- _ENV below for all functions is the cluster's main object, unless
-- specified otherwise

local function ltidTRemove(_ENV,ltid,sock)
   local x = ltidT[ltid]
   if x then
      x[sock]=nil
      if not next(x) then ltidT[ltid]=nil end -- remove tab if empty
      local peerT = smq:etid2peer(ltid)
      -- if phantom owned by this cluster instance
      if peerT and peerT.phantom == _ENV then a_terminatePhantom(peerT) end
   end
end


local function send2AllNodes(_ENV,data)
   for sock,connenv in pairs(conT) do
      sendframe(sock,connenv.id,data)
   end
end

----------------- Start SMQ broker callbacks --------------------

local function onsubscribe(_ENV,tid)
   if a_substatus(tid) == 1 then
      send2AllNodes(
	 _ENV,schar(MsgSubscribe)..sh2n(4,tid)..smq:tid2topic(tid))
   end
end

local function nosubscribers(_ENV,tid)
   send2AllNodes(_ENV,schar(MsgUnsubscribe)..sh2n(4,tid))
end

local function sendPublication(sock,id,data,subtopic)
   if not subtopic then return sendframe(sock,id,data) end
   -- One write keeps the announcement with its publication if sending yields.
   return sock:write(
      sh2n(4,#subtopic+7)..sh2n(2,id)..schar(MsgSubTopic)..subtopic..
      sh2n(4,#data+6)..sh2n(2,id)..data)
end

-- _ENV is the connection object
local function onpublishCon(_ENV,data,ptid,tid,subtid)
   local stn
   local rst = lSubTopicT[subtid] -- get Remote Sub Tid, if known
   if rst then
      subtid=rst -- translate
   elseif subtid ~= 0 then
      stn = cenv.smq:tid2subtopic(subtid)
   end
   sendPublication(sock,id,schar(MsgPublish)..sh2n(4,tid)..sh2n(4,
	     ptid)..sh2n(4,subtid)..data,stn)
end

local function onpublish(_ENV,data,lptid,ltid,lsubtid)
   local x = ltidT[ltid]
   if x then
      for sock,rtid in pairs(x) do
	 onpublishCon(conT[sock],data,lptid,rtid,lsubtid)
      end
   end
end

local function pubon(_ENV,data,ptid,topic,subtopic)
   local peerT = smq:etid2peer(ptid)
   if not peerT or peerT.phantom == _ENV then return false end
   if type(data) == "table" then data = assert(ba.json.encode(data)) end
   assert(#data <= 0xFFF0, "Max payload: 0xFFF0")
   onpublish(_ENV,data,ptid,a_getTid(topic),a_getSubTid(subtopic))
   return true
end

-- _ENV is the connection object
local function onpubsrvCon(_ENV,data,ptid,subtid)
   local stn
   local rst = lSubTopicT[subtid] -- get Remote Sub Tid, if known
   if rst then
      subtid=rst -- translate
   elseif subtid ~= 0 then
      stn = cenv.smq:tid2subtopic(subtid)
   end
   if type(data) == "table" then data = ba.json.encode(data) end
   sendPublication(sock,id,schar(MsgPubSrv)..sh2n(4,ptid)..sh2n(4,subtid)..data,stn)
end


local function onpubsrv(_ENV,data,lptid,subtopic)
   if subtopic then
      local peerT = smq:etid2peer(lptid)
      if not peerT or peerT.phantom == _ENV then return false end
   else
      subtopic=lptid
      lptid=smq:gettid()
   end
   local lsubtid=a_getSubTid(subtopic)
   if type(data) == "table" then data = ba.json.encode(data) end
   local cnt=0
   for sock,env in pairs(conT) do
      onpubsrvCon(env,data,lptid,lsubtid)
      cnt=cnt+1
   end
   return cnt
end

local function onclose(_ENV,tid)
   send2AllNodes(_ENV,schar(MsgRelease)..sh2n(4,tid))
end

----------------- End SMQ broker callbacks --------------------

----------------- Manage received messages --------------------
-- _ENV is the connection object for all functions below

-- set ltidT[tid] = sock | = table[sock]=sock
local function manageSubscribe(_ENV,data)
   local ltidT = cenv.ltidT
   local rtid=sn2h(4,data,8)
   local name=data:sub(12)
   local ltid=rtidT[rtid]
   if ltid then
      if cenv.smq:topic2tid(name) == ltid then return end
      return cenv.mtl._protocolerror
   end
   ltid = cenv.smq:create(name)
   local x = ltidT[ltid]
   if x and x[sock] then return cenv.mtl._protocolerror end
   rtidT[rtid]=ltid
   if x then
      x[sock]=rtid
   else
      ltidT[ltid] = {[sock]=rtid}
   end
end

local function manageSubTopic(_ENV,data)
   local stn = data:sub(8)
   savedStid = cenv.smq:createsub(stn) -- Temporarily store in ENV (ref:stid)
   sendframe(sock,id,schar(MsgSubTopicAck)..sh2n(4,savedStid)..stn)
end

local function manageSubTopicAck(_ENV,data)
   local smq=cenv.smq
   local rstid=sn2h(4,data,8)
   local stn=data:sub(12)
   if not smq:subtopic2tid(stn) then return cenv.mtl._protocolerror end
   lSubTopicT[smq:createsub(stn)]=rstid
end

local function managePublish(_ENV,data)
   local ltid,rptid,stid=sn2h(4,data,8),sn2h(4,data,12),sn2h(4,data,16)
   if savedStid then -- ref:stid
      stid=savedStid -- Translate remote to local
      savedStid=nil
   end
   local lptid=rtidT[rptid]
   if not lptid then
      local peerT = cenv.a_createPhantom()
      lptid=peerT.tid
      peerT.phantom=cenv
      rtidT[rptid] = lptid
      cenv.ltidT[lptid]={[sock]=rptid}
   end
   cenv.a_publish(cenv.smq:etid2peer(lptid),ltid,stid,data:sub(20))
end

local function managePubSrv(_ENV,data)
   local rptid,stid=sn2h(4,data,8),sn2h(4,data,12)
   if savedStid then -- ref:stid
      stid=savedStid -- Translate remote to local
      savedStid=nil
   end
   local lptid=rtidT[rptid]
   if not lptid then
      local peerT = cenv.a_createPhantom()
      lptid=peerT.tid
      peerT.phantom=cenv
      rtidT[rptid] = lptid
      cenv.ltidT[lptid]={[sock]=rptid}
   end
   cenv.a_publish(cenv.smq:etid2peer(lptid),cenv.smq:gettid(),stid,data:sub(16))
end

local function manageUnsubscribe(_ENV,data)
   local ltidT = cenv.ltidT
   local rtid=sn2h(4,data,8)
   local ltid=rtidT[rtid]
   if not ltid then return cenv.mtl._protocolerror end
   rtidT[rtid]=nil
   ltidTRemove(cenv,ltid,sock)
end

local function manageRelease(_ENV,data)
   local rtid=sn2h(4,data,8)
   local ltid=rtidT[rtid]
   if ltid then
      rtidT[rtid]=nil
      ltidTRemove(cenv,ltid,sock)
   end
end


local msgT={
   [MsgSubscribe]=manageSubscribe,
   [MsgSubTopic]=manageSubTopic,
   [MsgSubTopicAck]=manageSubTopicAck,
   [MsgPublish]=managePublish,
   [MsgPubSrv]=managePubSrv,
   [MsgUnsubscribe]=manageUnsubscribe,
   [MsgRelease]=manageRelease
}

local function onstatus(cenv,sock,up,id)
   if up then
      cenv.conT[sock] = {
	 rtidT={}, -- k= remote TID, v= local TID
	 lSubTopicT={}, -- k=local sub topic ID, v = remote sub topic ID
	 cenv=cenv, -- Cluster main object env
	 sock=sock,
	 id=id
      }
      for tid,name in cenv.smq:topics() do
	 if cenv.a_substatus(tid) ~= 0 then
	    sendframe(sock,id,schar(MsgSubscribe)..sh2n(4,tid)..name)
	 end
      end
   else
      local connenv = cenv.conT[sock]
      if connenv then
	 cenv.conT[sock]=nil
	 local ltidT = cenv.ltidT
	 -- loop tids for topics and ephemeral tids
	 for rtid,ltid in pairs(connenv.rtidT) do
	    ltidTRemove(cenv,ltid,sock)
	 end
      end
      if type(up) == "nil" then
	 cenv.smq:shutdown(id)
      end
   end
end

local function ondata(cenv,sock,data)
   local connenv = cenv.conT[sock]
   if connenv then
      if #data < 7 then return cenv.mtl._protocolerror end
      local msg = data:byte(7)
      local manage = msgT[msg]
      if manage then
         local minlen = msg == MsgPublish and 19 or msg == MsgPubSrv and 15 or
            msg == MsgSubTopic and 7 or 11
         if #data < minlen then return cenv.mtl._protocolerror end
	 return manage(connenv,data)
      else
	 trace("Cluster: Received unknown msg",data:byte(7))
      end
   else
      trace("Cluster: connenv not found",sock)
   end
end

local function close(cenv,msg)
   cenv.mtl:close(cenv.mtlname,msg or "close")
end

local Cluster={publish=onpubsrv,pubon=pubon,close=close}
Cluster.__index=Cluster
local createCntr=1

local function create(smq,pwdOrMtl,op)
   local env
   _G.ba.rndseed(_G.ba.clock()+os.time())
   local function onsub(tid) onsubscribe(env,tid) end
   local function nosubs(tid) nosubscribers(env,tid) end
   local function onpub(data,ptid,tid,subtid)
      onpublish(env,data,ptid,tid,subtid)
   end
   local function oncls(tid) onclose(env,tid) end
   -- env: ref:CM in smqbroker.lua
   env=smq:setcluster(onsub,nosubs,onpub,oncls)
   env.conT={}
   env.ltidT={} -- Local tid table: k=tid (topic tid or etid) and v=sock(s)
   env.smq=smq

   if not pwdOrMtl or type(pwdOrMtl) == "string" then
      env.mtl = MTL.create(pwdOrMtl,op) -- pwdOrMtl=password
   else
      env.mtl=pwdOrMtl
   end
   env.mtlname=op and op.name or string.format("SMQ-%d",createCntr)
   createCntr=createCntr+1
   env.mtl:open(env.mtlname,
		function(sock,up,id) onstatus(env,sock,up,id) end,
		function(sock,data) return ondata(env,sock,data) end)
   return setmetatable(env,Cluster)
end

return {
   create=create,
}
