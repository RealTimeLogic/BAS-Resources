--SMQ Hub/Broker. Copyright Real Time Logic.

local sn2h=ba.socket.n2h
local sh2n=ba.socket.h2n
local tinsert=table.insert
local tconcat=table.concat
local string=string
local schar=string.char
local fmt=string.format
local ba=ba
local type=type
local trace=trace
local pairs=pairs
local next=next
local collectgarbage=collectgarbage
local assert=assert
local setmetatable=setmetatable
local G=_G

local MsgInit = 1
local MsgConnect = 2
local MsgConnack = 3
local MsgSubscribe = 4
local MsgSuback = 5
local MsgCreate = 6
local MsgCreateAck = 7
local MsgPublish = 8
local MsgUnsubscribe = 9
local MsgDisconnect = 11
local MsgPing = 12
local MsgPong = 13
local MsgObserve = 14
local MsgUnobserve = 15
local MsgChange = 16
local MsgCreateSub = 17
local MsgCreateSubAck = 18
local MsgPubFrag = 19

local function noop() end

local function pfmt(...)
   local ok,data=pcall(fmt,...)
   if ok then return data end
   trace("Err pfmt:",data,debug.traceback())
end

-- Strips the two Frame Length bytes from a raw socket frame
local function stripFL(data)
   return data and data:sub(3)
end

local function defaultLog(sock, data)
   tracep(false,8,"SMQ:HUB:"..data)
end

local function prepLog(env, sock, ...)
   local data=pfmt(...)
   if data then env.log(sock,data) end
end

-- Default OK
local function defAuthenticate()
   return 0 -- ecode 0: Connection Accepted
end

-- Default OK
local function defAuthorizeTID()
   return true
end

local function rmIPv6pf(ip)
   if ip and ip:find('::ffff:',1,true) == 1 then return ip:sub(8) end
   return ip
end

local function createTid(tidT)
   local tid
   -- Find empty slot
   repeat tid = ba.rnds(4) until not tidT[tid] and tid ~= 0
   return tid
end

-- Checks if 't' is a table and not a Pseudo Socket: ref:PS
local function istab(t)
   return type(t) == "table" and not t.onmsg -- ref:BS
end


-- Send a frame to a raw TCP connection or to a websocket
-- connection. A raw frame is appended with a 16 bit length. Data is
-- cached in table 't' as fd (Frame length header + Data) or rd (Raw
-- data). Raw data is sent to a websocket connection and framed data is
-- sent to a standard socket connection.
local function sendFrame(s,t)
   if s:websocket() then
      if not t.rd then t.rd = t.fd:sub(3) end
      return s:write(t.rd)
   end
   if not t.fd then t.fd = sh2n(2, #t.rd+2)..t.rd end
   return s:write(t.fd)
end


local function changeMsgFrame(tid, subscribers)
   return {rd=schar(MsgChange)..sh2n(4,tid)..sh2n(4,subscribers)}
end


local function countSubscribers(_ENV, tid)
   local subscribers = 0
   local x = tidT[tid]
   if x then
      if istab(x) then
	 for k in pairs(x) do subscribers = subscribers + 1 end
      elseif x ~= true then
	 subscribers=1
      end
   end
   return subscribers
end

-- Returns 0: none, 1: one, 2: 2 or more
local function substatus(_ENV, tid)
   local x = tidT[tid]
   if x then
      if istab(x) then return 2 end
      if x ~= true then return 1 end
   end
   return 0
end


-- Subscribe 'peerT' to Topic ID 'tid'
local function subscribe(_ENV, peerT, tid)
   --Code section: tidT[tid] = peerT.sock or tidT[tid][peerT.sock] = peerT.sock
   local sock = peerT.sock
   local x = tidT[tid]
   if istab(x) then
      if x[sock] == sock then return false end
      x[sock] = sock
   elseif x == true then -- Ref:KT
      tidT[tid] = sock
   elseif x~= sock then
      tidT[tid] = {[x]=x, [sock]=sock}
   else
      return false
   end

   --Code section: PeerT.topics = tid or PeerT.topics[tid] = tid
   x = peerT.topics
   if x then
      if type(x) == "table" then
	 x[tid]=tid
      else
	 assert(type(x) == "number")
	 peerT.topics = {[x]=x, [tid]=tid}
      end
   else
      peerT.topics=tid
   end

   return true
end


--  observeT[tid] = peerT.sock | observeT[tid] = {peerT.sock=peerT.sock,....}
local function observe(_ENV, peerT, tid)
   if tidT[tid] then
      local sock = peerT.sock
      local x = observeT[tid]
      if x then
	 if istab(x) then
	    x[sock]=sock
	 elseif x ~= sock then
	    observeT[tid] = {[x]=x, [sock]=sock}
	 end
      else
	 observeT[tid] = sock
      end
      if tid2topicT[tid] then -- No initial onchange for ephemeral tids
	 sendFrame(peerT.sock,changeMsgFrame(tid, countSubscribers(_ENV, tid)))
      end
      return true
   end
   return false
end


--  observeT[tid] = nil | observeT[tid][peerT.sock] = nil
local function unobserve(_ENV, peerT, tid)
   local sock = peerT.sock
   local x = observeT[tid]
   if istab(x) then
      x[sock] = nil
      local f,v = next(x)
      if f then
	 if not next(x,f) then -- if only 1 elem in tab
	    -- Only one observer: reduce
	    observeT[tid] = v -- where v is 'sock' instance
	 end
      else -- Tab empty
	 observeT[tid] = nil
      end
   elseif x == sock then
      tidT[tid] = nil
   end
end


local function sendChangeMsg(_ENV, tid, subscribers)
   local x = observeT[tid]
   if x then
      local frame = changeMsgFrame(tid, subscribers)
      if istab(x) then
	 for sock in pairs(x) do
	    sendFrame(sock, frame)
	 end
      else
	 sendFrame(x, frame)
      end
   end
end


-- Count subscribers for 'tid' and send 'change' event
local function countAndSendChangeMsg(_ENV, tid)
   local observers = observeT[tid]
   if observers then
      sendChangeMsg(_ENV, tid, countSubscribers(_ENV, tid))
   end
end


local function unsubscribe(_ENV, peerT, tidT, tid)
   local isremoved=true
   -- Remove 'sock' from tidT, but we keep the key 'tid' in tidT[tid]
   local sock=peerT.sock
   local x = tidT[tid]
   if istab(x) then
      isremoved = x[sock] == sock
      x[sock] = nil
      local f,v = next(x)
      if f then
	 if not next(x,f) then -- if only 1 elem in tab
	    -- Only one subscriber
	    tidT[tid] = v -- where v is 'sock' instance
	 end
      else -- Tab empty
	 tidT[tid] = true  -- We keep the 'key (tid)' in tidT (Ref:KT)
      end
   elseif x == sock then
      tidT[tid] = true -- We keep the 'key (tid)' in tidT (Ref:KT)
   else
      prepLog(_ENV,sock,"Unsubscribe: tid %X not registered", tid)
      isremoved=false
   end
   -- Remove tid from PeerT.topics
   local topics = peerT.topics
   if topics then
      if type(topics) == "table" then
	 topics[tid]=nil
	 local f,tid = next(topics)
	 assert(f)
	 if not next(topics,f) then -- if only 1 elem in tab
	    peerT.topics = tid -- reduce
	 end
      elseif peerT.topics == tid then
	 peerT.topics = nil
      end
   end
   if isremoved then
      countAndSendChangeMsg(_ENV, tid)
      if tidT[tid] == true then nosubscribers(tid) end -- (Ref:KT and ref:C1)
   end
end


-- Remove peerT from all global tables and close socket
local function terminatePeerT(_ENV,sock,err)
   local peerT = sockT[sock]
   if peerT then
      local tid=peerT.tid
      onclose(tid,sock,peerT,err or 0)
      uidT[peerT.uid] = nil
      tidT[tid] = nil
      sockT[sock] = nil
      local topics = peerT.topics
      if topics then
	 if type(topics) == "table" then
	    local t={}
	    for k,v in pairs(topics) do t[k]=v end
	    for _,tid in pairs(t) do
	       unsubscribe(_ENV, peerT, tidT, tid)
	    end
	 else -- topics is a 'tid'
	    unsubscribe(_ENV, peerT, tidT, topics)
	 end
      end
      if err and not peerT.closing and err ~= "sysshutdown" then
	 prepLog(_ENV,sock,"Unexpected socket close %s", err)
      end
      sendChangeMsg(_ENV, tid, 0)
      observeT[tid] = nil
   end
   sock:close()
end


local function manageWriteErr(env,sock,err)
   if type(err) == "number" then
      prepLog(env, sock, "Dropping message: socket queue full")
   else
      terminatePeerT(env,sock,err)
   end
end


--  return existing tid or create a new entry.
local function lookupOrCreateTid(_ENV, topic, xtid)
   local tid = topic2tidT[topic]
   if tid then return tid end -- Already created
   tid = (xtid and xtid ~= 0 and not tidT[xtid]) and xtid or createTid(tidT)
   tidT[tid] = true -- Register
   topic2tidT[topic] = tid
   tid2topicT[tid] = topic
   return tid
end

-- Extract tid from peer's 'data' (message) and either return existing
-- tid or create a new entry.
local function extractAndCreateTid(_ENV,peerT,data,hasFL,issub)
   local topic = data:sub(hasFL and 4 or 2) -- Extract Topic Name
   if issub and peerT.topics then
      local topics = peerT.topics
      local tid = topic2tidT[topic]
      if tid then
	 if tid == (type(topics) == "table" and topics[tid] or topics) then
	    log(peerT.sock, pfmt("Duplicate subscribe for %s",topic))
	    return tid, topic -- dup OK
	 end
      end
   end
   if not authorizeTID(topic, issub, peerT) then return nil, topic end
   return lookupOrCreateTid(_ENV, topic), topic
end


-- Send MsgSuback, MsgCreateAck, or MsgCreateSubAck
local function sendSuback(sock, topic, tid, msgID)
   return sendFrame(sock, {rd=
	  schar(msgID, tid and 0 or 1)..sh2n(4,tid or 0)..topic
       })
end


local function lShutdown(_ENV,msg,etid)
   if msg then
      if etid then
	 local sock=tidT[etid]
	 if sock then
	    if type(sock) == "userdata" then 
	       sendFrame(sock,{rd=schar(MsgDisconnect)..msg})
	       terminatePeerT(_ENV,sock)
	    end
	 end
	 return
      end
      for sock in pairs(sockT) do
	 if type(sock) == "userdata" then
	    sendFrame(sock,{rd=schar(MsgDisconnect)..msg})
	 end
      end
   end
   for sock in pairs(sockT) do
      if type(sock) == "userdata" then
	 terminatePeerT(_ENV,sock)
      end
   end
   onshutdown(msg)
end


local function manageSubscribe(_ENV,peerT,data,hasFL)
   local tid,topic = extractAndCreateTid(_ENV,peerT,data,hasFL,true)
   if tid then
      if subscribe(_ENV, peerT, tid) then
	 countAndSendChangeMsg(_ENV, tid)
	 onsubscribe(tid)
      end
   end
   return sendSuback(peerT.sock, topic, tid, MsgSuback)
end


local function manageCreate(_ENV,peerT,data,hasFL)
   local tid,topic = extractAndCreateTid(_ENV,peerT,data,hasFL,false)
   return sendSuback(peerT.sock, topic, tid, MsgCreateAck)
end


local function manageCreateSub(_ENV,peerT,data,hasFL)
   local subtopic = data:sub(hasFL and 4 or 2) -- Extract Sub Topic Name
   local stid = subtopic2tidT[subtopic]
   if not stid and authorizeSTID(subtopic, peerT) then
      stid = createTid(tid2subtopicT)
      tid2subtopicT[stid]=subtopic
      subtopic2tidT[subtopic]=stid
   end
   return sendSuback(peerT.sock, subtopic, stid, MsgCreateSubAck)
end


local function manageUnsubscribe(_ENV,peerT,data,hasFL)
   if #data < (hasFL and 7 or 5) then return end -- Invalid data: close sock
   local tid=sn2h(4,data,hasFL and 4 or 2) -- Get Topic ID
   unsubscribe(_ENV,peerT, tidT, tid)
   return true
end


local function managePublish(_ENV,peerT,data,hasFL)
   local atLeast1Sub,pdata,stid
   if #data < (hasFL and 15 or 13) then return end -- Invalid data: close sock
   local tid=sn2h(4,data,hasFL and 4 or 2) -- Get Topic ID
   local ptid = hasFL and sn2h(4,data,8) or sn2h(4,data,6)
   if ptid ~= peerT.tid then -- security: if hacked
      prepLog(_ENV,peerT.sock,"Corrupt sender tid")
      lShutdown(_ENV, "corrupt frame", peerT.tid)
      return
   end
   if onpublish then
      if hasFL then
	 pdata,stid=data:sub(16),sn2h(4,data,12)
      else
	 pdata,stid=data:sub(14),sn2h(4,data,10)
      end
      if not onpublish(pdata,ptid,tid,stid,peerT) then return true end
   end
   local x=tidT[tid]
   if x then
      local t={} -- Used by function 'sendFrame'
      if hasFL then
	 t.fd = data
      else
	 t.rd = data
      end
      if istab(x) then
	 local errT
	 for _, sock in pairs(x) do
	    local ok, err = sendFrame(sock,t)
	    if ok then
	       atLeast1Sub = true
	    else
	       if not errT then errT={} end
	       errT[sock] = err
	    end
	 end
	 if errT then
	    for sock,err in pairs(errT) do
	       manageWriteErr(_ENV,sock,err)
	    end
	 end
      elseif x ~= true then -- 'x' is socket
	 local ok, err = sendFrame(x,t)
	 if ok then
	    atLeast1Sub=true
	 else
	    manageWriteErr(_ENV,x,err)
	 end
      elseif not ondrop then
	 prepLog(_ENV,peerT.sock,"Publish: dropping msg for tid %X", tid)
      end
   elseif not ondrop then
      prepLog(_ENV,nil,"Publish: dropping msg for unknown tid %X", tid)
   end
   if not atLeast1Sub and ondrop then
      if not pdata then
	 if hasFL then
	    pdata,stid=data:sub(16),sn2h(4,data,12)
	 else
	    pdata,stid=data:sub(14),sn2h(4,data,10)
	 end
      end
      ondrop(pdata,ptid,tid,stid,peerT)
   end
   return true
end


local function managePubFrag(_ENV,peerT,frame,hasFL)
   if not hasFL then return end -- Not available to WebSocket
   local data = frame:sub(16)
   if peerT.fragment then
      peerT.fragsize=peerT.fragsize + #data
      if peerT.fragsize > 0xFFF0 then
	 peerT.fragment=nil
	 prepLog(_ENV,peerT.sock,"Fragment overflow")
	 return -- close sock
      end
      tinsert(peerT.fragment,data)
   else
      peerT.fragment={schar(MsgPublish),2,data}
      peerT.fragsize=#data
   end
   if sn2h(4,frame,4) ~= 0 then
      local t = peerT.fragment
      peerT.fragment=nil
      t[2] = frame:sub(4, 15)
      data = tconcat(t)
      if #data <= 0xFFF0 then -- 0xF=frame size
	 return managePublish(_ENV,peerT,data)
      end
      prepLog(_ENV,peerT.sock,"PubFrag above max payload: %d", #data)
   end
   return true
end


local function manageDisconnect(env, peerT)
   peerT.closing=true
   terminatePeerT(env, peerT.sock)
   sendFrame(peerT.sock,{rd=schar(MsgDisconnect)})
   -- No return: exit socket thread
end


local function managePing(_ENV,peerT)
   return sendFrame(peerT.sock,{rd=schar(MsgPong)})
end


local function managePong()
   -- Do nothing
   return true
end

local function manageObserve(_ENV,peerT,data,hasFL)
   if #data < (hasFL and 7 or 5) then return end
   local tid = sn2h(4, data, hasFL and 4 or 2)
   if tid ~= peerT.tid and not observe(_ENV, peerT, tid) then
      sendFrame(peerT.sock, changeMsgFrame(tid, 0))
   end
   return true
end

local function manageUnobserve(_ENV,peerT,data,hasFL)
   if #data < (hasFL and 7 or 5) then return end
   unobserve(_ENV, peerT, sn2h(4, data, hasFL and 4 or 2)) -- Get Topic ID
   return true
end


local msgT={
   [MsgSubscribe] = manageSubscribe,
   [MsgCreate] = manageCreate,
   [MsgCreateSub] = manageCreateSub,
   [MsgPublish] = managePublish,
   [MsgPubFrag] = managePubFrag,
   [MsgUnsubscribe] = manageUnsubscribe,
   [MsgDisconnect] = manageDisconnect,
   [MsgPing] = managePing,
   [MsgPong] = managePong,
   [MsgObserve] = manageObserve,
   [MsgUnobserve] = manageUnobserve,
}


local function manageMessage(_ENV,sock,data,hasFL)
   collectgarbage"step"
   local offs = hasFL and 3 or 1
   local msg = data:byte(offs, offs)
   local manage = msgT[msg]
   local peerT = sockT[sock]
   if manage then
      if peerT then
	 if peerT.closing then
	    return
	 end -- close on ret
	 return manage(_ENV,peerT,data,hasFL)
      end
      prepLog(_ENV,sock,"Msg %d from unknown peer",msg)
      sock:close()
   else
      prepLog(_ENV,sock,"Received unknown msg %d from %s",
	      msg, peerT and peerT.uid or "unknown")
      terminatePeerT(_ENV,sock)
   end
   -- close on ret
end


local function getRawSockFrame(sock,data,tmo)
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
	    tinsert(t, data)
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


local function getWebSockFrame(sock, tmo)
   local data,err,bytesRead,frameLen = sock:read(tmo)
   if frameLen then
      local t={}
      repeat
	 tinsert(t,data)
	 data,err,bytesRead,frameLen = sock:read(tmo)
	 if not data then
	    return nil,err
	 end
      until frameLen == bytesRead
      tinsert(t,data)
      data=tconcat(t)
      return data
   end
   return data,err
end


--args: sock, self
local function rawSockThread(sock,env)
   local data,err
   while true do
      data,err = getRawSockFrame(sock, data)
      if not data then break end
      if not manageMessage(env,sock,data,true) then
	 err=nil
	 break
      end
      data = err -- err is remainder, if any
   end
   terminatePeerT(env,sock,err)
end


local function webSockThread(sock,env)
   local data,err
   while true do
      data,err=getWebSockFrame(sock)
      if not data then break end
      if not manageMessage(env,sock,data,false) then break end
   end
   terminatePeerT(env,sock,err)
end

local function connect(_ENV,cmd,arg)
   local xinfo
   if not cmd:header"SimpleMQ" and not cmd:header"Sec-WebSocket-Key" then
      cmd:senderror(404)
      return
   end
   cmd:setheader("SmqBroker","true")
   if cmd:header"SendSmqHttpResponse" == "true" then cmd:flush() end
   local url = cmd:uri()
   local uname = cmd:user()
   local sock = ba.socket.req2sock(cmd)
   if sock then
      local ws = sock:websocket()
      local ecode,uid,info,reason=6
      local seed=ba.rnds(4)
      if sendFrame(sock,{rd=
	 schar(MsgInit,1)..sh2n(4,seed)..rmIPv6pf(sock:getpeername() or "")})
      then
	 local data = ws and
	    getWebSockFrame(sock, readtmo) or
	    stripFL(getRawSockFrame(sock, nil, readtmo))
	 if data then -- Extract data from Connect
	    local msg,ver = data:byte(1,2)
	    if msg == MsgConnect and (ver == 1 or ver == 2) then
	       local idlen,crlen,credentials
	       if ver == 1 then
		  idlen = data:byte(3)
		  uid = data:sub(4,idlen+3)
		  crlen=data:byte(idlen+4) or 0
		  credentials=data:sub(idlen+5,idlen+4+crlen)
		  info=data:sub(idlen+5+crlen)
	       else
		  local max=sn2h(2,data,3)
		  if max ~= 0 then sock:maxsize(max) end
		  idlen = data:byte(5)
		  uid = data:sub(6,idlen+5)
		  crlen=data:byte(idlen+6) or 0
		  credentials=data:sub(idlen+7,idlen+6+crlen)
		  info=data:sub(idlen+7+crlen)
	       end
	       if idlen > 5 then
		  xinfo = {
		     arg=arg,
		     seed=seed,
		     sock=sock,
		     url=url,
		     uid=uid,
		     info=info,
		     data=cmd:data(),
		     header=cmd:header(),
		     uname=uname,
		  }
		  ecode,reason=authenticate(credentials, xinfo)
                  if not ecode then
                     defaultLog(sock,"No response from authenticate")
                     ecode = 6
                  end
	       else
		  ecode = 0x01
	       end
	    else
	       ecode = 0x01
	    end
	 else
	    ecode = 0x02
	 end
      else
	 ecode = 0x02
      end
      if ecode == 0 then
	 local tid -- -- Client's unique Topic ID
	 local peerT = uidT[uid]
	 if peerT then
	    tid = peerT.tid
	    peerT.closing=true
	    sendFrame(peerT.sock,{rd=schar(MsgDisconnect).."reconnect"})
	    terminatePeerT(_ENV,peerT.sock,"reconnect")
	 else
	    tid = createTid(tidT)
	 end
	 local connack = schar(MsgConnack,0)..sh2n(4,tid)
	 if sendFrame(sock,{rd=connack}) then
	    peerT={
	       uid=uid,
	       sock=sock,
	       info=info,
	       -- 'topics' set later
	       tid=tid
	    }
	    -- Insert into lookup tables
	    uidT[uid]=peerT
	    tidT[tid]=sock
	    sockT[sock]=peerT
	    sock:setoption("keepalive",true,keepalive,keepalive)
	    -- Start socket thread and convert socket to non blocking.
	    sock:event(ws and webSockThread or rawSockThread, "s", _ENV)
	    onconnect(tid, xinfo, peerT)
	    return
	 end
      end
      local connack = schar(MsgConnack, ecode)..sh2n(4,0)..(reason or "")
      sendFrame(sock,{rd=connack})
      sock:close()
   end
end


----- API for Lua server code

local function chktype(val,vtype,msg,level)
   if type(val) ~= vtype then error(msg, level or 3) end
end

local function assertfunc(arg,typestr,level)
   chktype(arg, "function", 
	   fmt("%s%s",typestr or ""," must be a function"), level or 3)
end


local function psnotimpl()
   return nil, debug.traceback("Pseudo Socket: func not implemented:\n")
end

local PS={phantom=true} -- Server's Pseudo Socket
PS.__index = function(t,k) return rawget(PS,k) or psnotimpl end

-- Makes 'write' method receive data without payload len : Ref:WS
function PS:websocket() return true end

function PS:write(data)
   local msg = data:byte()
   if msg == MsgPublish then
      -- self is serverT.sock (Ref:BS)
      if self.recCounter > 20 then
	 prepLog(self.env,nil,"Err: onmsg recursive call")
      else
	 -- Pseudo write extracts [topic-tid, from-tid, and data] and
	 -- calls onmsg
	 local onmsg
	 local tid = sn2h(4,data,2)
	 local stid = sn2h(4,data,10)
	 local t = self.onMsgCBT[tid]
	 if t then onmsg = t.subtops[stid] or t.onmsg end
	 if not onmsg then onmsg = self.onmsg end
	 self.recCounter = self.recCounter + 1
	 onmsg(data:sub(14), sn2h(4,data,6), tid, stid)
	 self.recCounter = self.recCounter - 1
      end
   else
      local _ENV=self.env
      assert(msg == MsgChange)
      local tid = sn2h(4,data,2)
      local func = self.observeT[tid];
      if func then
	 local subscribers = sn2h(4,data,6)
	 local topic = tid2topicT[tid]
	 if not topic and subscribers == 0 then
	    observeT[tid]=nil
	 end
	 func(subscribers, topic or tid)
      end
   end
   return true
end

local function lCreateSub(_ENV, subtopic, tid)
   if subtopic then
      local stid = subtopic2tidT[subtopic]
      if not stid then
	 stid = (tid and tid ~= 0 and not tid2subtopicT[tid]) and
	    tid or createTid(tid2subtopicT)
	 tid2subtopicT[stid]=subtopic
	 subtopic2tidT[subtopic]=stid
      end
      return stid
   end
   return 0
end

-- Wrapper for parsing json before calling onmsg; ps is Pseudo Sock
local function onJsonMsg(ps,onmsg,data,ptid,tid,stid)
   local t = ba.json.decode(data)
   if t then
      onmsg(t,ptid,tid,stid)
   else
      pcall(function() data=tconcat({data:byte()}," ") end)
      prepLog(ps.env,nil,"JSON parse err for: ptid=%d, tid=%d, subtid=%d, data='%s'",
	      ptid,tid,stid, data)
      ps.onmsg(data,ptid,tid,stid)
   end
end

local function createOnJsonMsg(ps,onmsg)
   return function(data,ptid,tid,stid)
	     onJsonMsg(ps,onmsg,data,ptid,tid,stid) end
end


local function getTid(_ENV, topic, nocreate)
   return type(topic) == "number" and topic or
      (topic == "self" and serverT.tid or
       (not nocreate and lookupOrCreateTid(_ENV,topic) or topic2tidT[topic]))
end


local function getSubTid(env, subtopic)
   return type(subtopic) == "number" and subtopic or lCreateSub(env,subtopic)
end


local function lSubscribe(_ENV, topic, op)
   local tid = getTid(_ENV,topic)
   if subscribe(_ENV, serverT, tid) then -- serverT is peerT for server (Ref:B)
      countAndSendChangeMsg(_ENV, tid)
      onsubscribe(tid)
   end
   if op then chktype(op,"table","Options must be a table") else op={} end
   if op.onmsg then
      assertfunc(op.onmsg, "op.onmsg")
      local stid = getSubTid(_ENV,op.subtopic)
      local ps = serverT.sock -- Pseudo Sock
      local t = ps.onMsgCBT[tid]  -- Ref:SCB
      if not t then
	 t = {subtops={}}
	 ps.onMsgCBT[tid] = t
      end
      local onmsg = op.json and createOnJsonMsg(ps, op.onmsg) or op.onmsg
      if stid == 0 then
	 t.onmsg = onmsg
      else
	 t.subtops[stid] = onmsg
      end
   end
   return tid
end


local function lUnsubscribe(_ENV, topic)
   local tid = getTid(_ENV,topic,true)
   if tid then
      unsubscribe(_ENV,serverT, tidT, tid)
      serverT.sock.onMsgCBT[tid] = nil
   end
end


-- Socket thread waits for messages via queue and sends the messages
-- as if sent by a non block socket.
local function lMsgDispatcher(sockThread, _ENV)
   while true do
      managePublish(_ENV,serverT,qT[qTail])
      qTail = (qTail + 1) % qSize
      qElems = qElems - 1
      -- Stop thread if ring buffer queue empty
      if qTail == qHead then
	 if true ~= sockThread:disable() then break end
      end
   end
end

local function lPublish(_ENV, data, topic, subtopic)
   local bt = serverT
   local tid = getTid(_ENV, topic)
   local stid = getSubTid(_ENV,subtopic)
   if type(data) == "table" then data = ba.json.encode(data) end
   if #data > 0xFFF0 then error("Max payload: 0xFFF0", 2) end
   data=schar(MsgPublish)..sh2n(4, tid)..sh2n(4,bt.tid)..sh2n(4,stid)..data
   if ba.socket.getsock() then
      managePublish(_ENV,bt,data)
      return qElems
   end
   if not qT then -- Create queue (Ref:Q)
      qHead=1 -- Ring buffer head
      qTail=0
      qElems = 1
      qT={[qTail]=data}
      qConsumer=ba.socket.event(lMsgDispatcher, _ENV)
   else -- Insert into queue
      if qHead == qTail then -- Empty
	 qT[qHead] = data
	 qHead = (qHead + 1) % qSize
	 qElems = 1
	 qConsumer:enable(true) -- Start lMsgDispatcher coroutine
      else
	 local nextHead = (qHead + 1) % qSize
	 if nextHead ~= qTail then
	    qT[qHead] = data
	    qHead = nextHead
	    qElems = qElems + 1
	 else
	    prepLog(_ENV,nil,pfmt("Queue full: dropping tid %X",tid))
	 end
      end
   end
   return qElems
end


local function lObserve(_ENV,topic,func)
   local tid = getTid(_ENV, topic)
   chktype(func, "function", "arg 2 must be a function")
   if tid and tid ~= serverT.tid and observe(_ENV, serverT, tid) then
      serverT.sock.observeT[tid]=func
      return true
   end
end


local function lUnobserve(_ENV,topic)
   local tid = getTid(_ENV, topic, true)
   if tid then 
      unobserve(_ENV, serverT, tid)
      serverT.sock.observeT[tid]=nil
   end
end

local function defOnmsg(env)
   return function(data, ptid, tid, subtid)
      prepLog(env,nil,"Server dropping: ptid=%d, tid=%d, subtid=%d",
	      ptid,tid,subtid)
   end
end

--- Begin Cluster Management (intf code)

local CPS={  -- Cluster Manager's Phantom Socket
   websocket=function()	 return true end -- Ref:WS
}
CPS.__index = function(t,k) return rawget(CPS,k) or psnotimpl end
CPS.write=CPS.websocket -- not used, but must return true
CPS.onmsg=CPS.websocket -- key 'onmsg' needed for istab (ref:PS)
local function createPhantom(_ENV)
   local t={
      tid=createTid(tidT),
      uid=CPS,
      info=CPS,
      sock=setmetatable({},CPS),
   }
   -- Register
   tidT[t.tid]=t.sock
   sockT[t.sock]=t
   return t
end

local function setcluster(_ENV,onsubC,nosubscribersC,onpubC,oncloseC,onshtdwnC)
   assert(not hasCluster) hasCluster=true
   if onpublish then
      local orgOnpublish=onpublish
      local function onpublishEX(data,ptid,tid,stid,peerT)
	 local ok = orgOnpublish(data,ptid,tid,stid,peerT)
	 if ok and peerT.uid ~= CPS then onpubC(data,ptid,tid,stid) end
	 return ok
      end
      onpublish = onpublishEX
   else
      local function onpublishEX(data,ptid,tid,stid,peerT)
	 if peerT.uid ~= CPS then onpubC(data,ptid,tid,stid) end
	 return true
      end
      onpublish = onpublishEX
   end
   if onclose == noop then
      onclose=function(tid, sock, peerT)
	 if peerT.uid ~= CPS then oncloseC(tid) end
      end
   else
      local orgOnclose=onclose
      local function oncloseEX(tid, sock, peerT, err)
	 orgOnclose(tid, sock, peerT, err)
	 if peerT.uid ~= CPS then oncloseC(tid) end
      end
      onclose = oncloseEX
   end
   onsubscribe=onsubC
   nosubscribers=nosubscribersC -- ref:C1
   onshutdown=onshtdwnC
   return { -- ref:CM
      a_substatus=function(tid) return substatus(_ENV,tid) end,
      a_createPhantom=function() return createPhantom(_ENV) end,
      a_terminatePhantom=function(peerT) terminatePeerT(_ENV,peerT.sock) end,
      a_publish=function(peerT,tid,stid,data) managePublish(_ENV,peerT,
	 schar(MsgPublish)..sh2n(4, tid)..sh2n(4,peerT.tid)..sh2n(4,stid)..data)
      end,
      a_getTid=function(topic) return getTid(_ENV, topic) end,
      a_getSubTid=function(subtopic) return getSubTid(_ENV, subtopic) end
   }
end

--- End Cluster Management

local B={
   connect=connect,
   create=lookupOrCreateTid,
   createsub=lCreateSub,
   observe=lObserve,
   publish=lPublish,
   setcluster=setcluster,
   shutdown=lShutdown,
   subscribe=lSubscribe,
   unobserve=lUnobserve,
   unsubscribe=lUnsubscribe,
}
B.__index=B

function B:gettid() return self.serverT.tid end
function B:peers() return pairs(self.sockT) end
function B:sock2peer(sock) return self.sockT[sock] end
function B:subtopic2tid(tid) return self.subtopic2tidT[tid] end
function B:subtopics() return pairs(self.tid2subtopicT) end
function B:tid2subtopic(tid) return self.tid2subtopicT[tid] end
function B:tid2topic(tid) return self.tid2topicT[tid] end
function B:topic2tid(tid) return self.topic2tidT[tid] end
function B:topics() return pairs(self.tid2topicT) end
function B:onmsg(cbfunc)
	       assertfunc(cbfunc)
	       self.serverT.sock.onmsg = cbfunc
	    end
function B:queuesize() return self.qSize - self.qElems, self.qElems end
function B:etid2peer(tid)
	 local x=self.tidT[tid]
	 if x then return self.sockT[x] end
      end
function B:setkeepalive(time) self.keepalive=time end

function B:pubon(data, totid, fromtid, stid)
   local to=self.tidT[totid]
   local from=self.tidT[fromtid]
   if type(to) == "userdata" and type(from) == "userdata" then
      local ok,err=sendFrame(
	 to,{rd=schar(MsgPublish)..sh2n(4, totid)..sh2n(4,fromtid)..sh2n(4,stid)..data})
      if ok then return true end
      manageWriteErr(self,to.sock,err)
   end
   return false
end


local function create(op)
   op = op or {}
   local env={
      keepalive = "number" == type(op.keepalive) and op.keepalive or ((60*4)-10),
      uidT={}, -- K =(Universally) Unique ID, V = peerT
      topic2tidT={}, -- K = topic name, V = tid
      tid2topicT={}, -- K = tid, V = topic name
      subtopic2tidT={}, -- K = sub topic name, V = tid
      tid2subtopicT={}, -- K = tid, V = sub topic name
      -- When inserted, a tid is never removed from tidT(Ref:KT)
      tidT={}, -- K = Topic ID, V = sock or table or true(true -> Ref:KT)
      sockT={}, -- K = socket, V = peerT
      observeT={}, -- K = tid, V = sock or table of socks
      authenticate = op.authenticate or defAuthenticate,
      authorizeTID = op.permittop or defAuthorizeTID,
      authorizeSTID = op.permitsubtop or defAuthorizeTID,
      onconnect = op.onconnect or noop,
      onclose = op.onclose or noop,
      readtmo = op.readtmo or 4000,
      log = op.log or defaultLog,
      -- For server publish API(Ref:Q)
      qSize = op.queuesize or 200,
      qElems = 0,
      serverT={}, -- Server's simulated peerT
      onsubscribe=noop,
      nosubscribers=noop,
      onshutdown=noop,
   }
   assertfunc(op.ondrop or noop, "op.ondrop")
   env.ondrop = op.ondrop
   assertfunc(op.onpublish or noop, "op.onpublish")
   env.onpublish = op.onpublish
   assertfunc(env.log, "op.log")
   -- server uses a Pseudo Socket(PS) where the write method is
   -- triggered on publish(ref:BS)
   local t=env.serverT
   t.sock = setmetatable({
      env=env,
      onmsg=op.onmsg or defOnmsg(env),
      onMsgCBT={}, -- Ref:SCB
      observeT={},
      recCounter=0}, PS)
    -- Set server etid to one if not rndtid set
   t.tid = op.rndtid and createTid(env.tidT) or 1
   t.uid="SMQ server client"
   t.info=t.uid
   -- Register
   env.tidT[t.tid]=t.sock
   env.sockT[t.sock]=t
   return setmetatable(env,B)
end

return {
   create=create,
   isSMQ=function(request)
      return (request:header"Sec-WebSocket-Key" or request:header"SimpleMQ")
	 and true or false
   end,
   pfmt=pfmt,
   assertfunc=assertfunc
}
