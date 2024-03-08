
-- MTL Multiplex Transport Layer. Copyright Real Time Logic.

local sn2h=ba.socket.n2h
local sh2n=ba.socket.h2n
local tinsert=table.insert
local tconcat=table.concat

local hub=require"smq/hub"
local pfmt=hub.pfmt
local assertfunc=hub.assertfunc

-- Pre-registered ID's. User ID's must be between 100 - 0xFFFF.
local MsgOpen		= 1
local MsgClose		= 2
local MsgCheckOldConReq = 3
local MsgCheckOldConResp= 4
local MsgPing		= 5
local MsgPong		= 6


local function rmIPv6prefix(ip)
   if ip and ip:find('::ffff:',1,true) == 1 then return ip:sub(8) end
   return ip
end

local function peername(sock)
   return rmIPv6prefix(sock:peername())
end

local function sendframe(sock, id, data)
   return sock:write(sh2n(4, #data+6)..sh2n(2, id)..data)
end


-- msg size: 4
-- id size: 2
local function getSockFrame(sock,data,tmo)
   local err
   if not data then data,err = sock:read(tmo) end
   if data then
      if #data < 6 then
	 local d=data
	 data,err = sock:read(tmo)
	 if not data then return nil,err end
	 data=d..data
      end
      local len=sn2h(4,data)
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


local function MTL_log(self,highprio,msg,...)
   msg=pfmt(msg,...)
   if msg then
      if self.logCB then
	 self.logCB("MTL: "..msg,highprio)
      else
	 tracep(false,8,"MTL:",msg)
      end
   end
end

local function validateNewSock(self, sock, peerAddr, peerT)
   local lweight = ba.rnd(1,0xFFFFFFFF/2-1)
   peerT.socksT[sock]=lweight
   local data,rem = getSockFrame(sock,nil,100) -- Needed for secure serv cons
   sendframe(sock,0,sh2n(4,0x0015A5A5)..sh2n(4,lweight)..sh2n(4,0xA5A55AAA))
   if not data then data,rem = getSockFrame(sock,nil,2000) end
   if not data then return false,rem end
   local magic1,rweight,magic2=sn2h(4,data,7),sn2h(4,data,11),sn2h(4,data,15)
   if #data ~= 18 or magic1 ~= 0x0015A5A5 or magic2 ~= 0xA5A55AAA then
      MTL_log(self,true,"invalid protocol version %s",sock)
      return false,"invalid"
   end
   local weight = lweight+rweight
   peerT.socksT[sock]=weight
   local password = self.password or ""
   local key = sh2n(4,lweight)..sh2n(4,rweight)
   local hpwd = ba.crypto.hash("hmac","sha512",key)(password)(true)
   sendframe(sock,0,hpwd)
   data,rem = getSockFrame(sock,rem,10000) -- Ref-T + 1
   if not data then return false,rem end
   key=sh2n(4,rweight)..sh2n(4,lweight)
   hpwd=ba.crypto.hash("hmac","sha512",key)(password)(true)
   if hpwd ~= data:sub(7) then
      MTL_log(self,true,"incorrect password %s",sock)
      return false,"password"
   end
   local maxw,cnt=0,0
   for s,w in pairs(peerT.socksT) do
      if s ~= sock then
	 maxw = maxw > w and maxw or w
      end
      cnt = cnt + 1
   end
   if cnt > 1 then
      if maxw == weight then return false,"Weight conflict" end
      if weight < maxw then return false end -- Discard
      if peerT.sock then -- ref:Active
	 if peerT.checkOldConCB then return false end -- Discard
	 local isActive,timer
	 local function checkOldCon(active)
	    peerT.checkOldConCB=nil
	    isActive = active
	    if active then
	       timer:cancel()
	       peerT.socksT[sock]=nil
	    else
	       peerT.sock:close()
	       peerT.socksT[peerT.sock]=nil
	       peerT.sock=nil
	    end
	    sock:enable()
	 end
	 peerT.checkOldConCB=checkOldCon
	 sendframe(peerT.sock, MsgCheckOldConReq,"")
	 timer = ba.timer(function() checkOldCon(false) end)
	 timer:set(9000) -- Ref-T
	 sock:disable()
	 if isActive then return false end -- Discard
      end
   end
   return true,rem
end

-- Remove peerT.socksT[sock], then remove from peerT from peersT if
-- peerT.socksT is empty
local function removeIfEmpty(self,peerT,sock,peerAddr)
   peerT.socksT[sock]=nil
   if not next(peerT.socksT) then -- if empty
      self.peersT[peerAddr]=nil
      return true
   end
end

local function manageOpen(self,peerT,data)
   local id = sn2h(2,data,7)
   local name=data:sub(9)
   local client = self.clientsT[name]
   if client then
      client.statusCB(peerT.sock, true, id)
   else
      if not peerT.ridT then peerT.ridT={} end
      peerT.ridT[name]=id
   end
end

local function manageClose(self,peerT,data)
   local nl=sn2h(2,data,7)
   local name=data:sub(9, 8+nl)
   local client = self.clientsT[name]
   if client then
      local msg = data:sub(9+nl)
      if #msg == 0 then msg=nil end
      self.clientsT[name]=nil
      self.clientsIdT[client.id]=nil
      client.statusCB(peerT.sock, nil, msg)
   end
end


local function manageCheckOldConReq(self,peerT)
   sendframe(peerT.sock, MsgCheckOldConResp, "")
end

local function manageCheckOldConResp(self,peerT)
   if peerT.checkOldConCB then
      peerT.checkOldConCB(true)
   end
end

local function managePing(self,peerT)
   sendframe(peerT.sock, MsgPong, "")
end

local function managePong(self,peerT)
   self.ping.roundtripCB(peerT.sock,ba.clock()-peerT.pingStart)
   self.pingtmoT[peerT]=true
end


local msgT={
   [MsgPing]=managePing,
   [MsgPong]=managePong,
   [MsgOpen]=manageOpen,
   [MsgClose]=manageClose,
   [MsgCheckOldConReq]=manageCheckOldConReq,
   [MsgCheckOldConResp]=manageCheckOldConResp
}

local function sockThread(sock,self,statusCB)
   local peerAddr=peername(sock)
   local peerT=self.peersT[peerAddr]
   if not peerT then
      peerT={socksT={}}
      self.peersT[peerAddr] = peerT
   end
   local data,rem = validateNewSock(self, sock, peerAddr, peerT)
   if not data then -- not OK
      if removeIfEmpty(self,peerT,sock,peerAddr) then
	 statusCB(peerAddr,sock,false,rem)
      end
      return -- close
   end
   if not self.ping then
      sock:setoption("keepalive",true,self.keepalive,self.keepintv)
   end
   peerT.socksT[sock]=0 -- 0 weight enables CheckOldCon
   peerT.sock = sock -- Set active connection (ref:Active)
   for s in pairs(peerT.socksT) do if s~=sock then s:close() end end
   statusCB(peerAddr,sock,true)
   -- Send all in peersT
   for id, client in pairs(self.clientsIdT) do
      sendframe(sock, MsgOpen, sh2n(2,id)..client.name)
   end

   self.onstatus(peerAddr,true)
   while true do
      data,rem=getSockFrame(sock,rem)
      if not data then break end
      local id=sn2h(2,data,5)
      local client = self.clientsIdT[id]
      if client then
	 client.dataCB(sock,data)
      else
	 client = msgT[id]
	 if client then
	    client(self,peerT,data)
	 else
	    MTL_log(self, false, "dropping rec ID(%d) %s", id,sock)
	 end
      end
   end
   self.onstatus(peerAddr,false,rem)

   -- send disconnect to all in peersT
   for id, client in pairs(self.clientsIdT) do
      if client.statusCB then client.statusCB(sock, false) end
   end

   removeIfEmpty(self,peerT,sock,peerAddr)
   if not self.terminated then
      statusCB(peerAddr,sock,false,rem)
      if not peerT.nolog then
	 MTL_log(self,true, "peer %s closed: %s ",peerAddr,rem)
      end
   end
end

local function pingtimer(self)
   while true do
      local pingtmoT={}
      self.pingtmoT=pingtmoT
      local nextcheck = os.time()+self.ping.timespan
      local rndt = ba.rnd(0, 20)
      nextcheck = rndt >= 10 and (nextcheck + 10 - rndt) or (nextcheck + rndt)
      repeat coroutine.yield(true) until os.time() >= nextcheck
      local peersT=self.peersT
      for _,peerT in pairs(peersT) do
	 if peerT.sock then -- if connected
	    peerT.pingStart=ba.clock()
	    pingtmoT[peerT]=false
	    sendframe(peerT.sock, MsgPing, "")
	 end
      end
      coroutine.yield(true)
      for peerT,status in pairs(pingtmoT) do
	 if status ~= true then
	    local peerAddr=peername(peerT.sock)
	    peerT=peersT[peerAddr]
	    if peerT then
	       peerT.nolog=true
	       MTL_log(self,true,"Ping timeout for %s ",peerAddr)
	       self.ping.roundtripCB(peerT.sock)
	       peerT.sock:close()
	    end
	 end
      end
   end
end

local function mktimer(self,timerCB)
   return ba.timer(function() timerCB(self) end)
end


local MTL={log=MTL_log} -- MTL meta
MTL.__index=MTL

function MTL:commence(s,statusCB)
   if self.terminated then s:close() return false end
   if ba.cmpaddr(s:peername(), s:sockname()) then s:close() return false end
   s:event(sockThread,"s",self,statusCB)
   return true
end

function MTL:open(name,statusCB,dataCB)
   if self.clientsT[name] then error("Name in use", 2) end
   local id
   while true do
      id = ba.rnd(100, 0xFFFF)
      if not self.clientsIdT[id] then break end
   end
   local client={
      name=name,
      id=id,
      statusCB=statusCB,
      dataCB=dataCB
   }
   self.clientsT[name]=client
   self.clientsIdT[id]=client
   for _,peerT in pairs(self.peersT) do
      sendframe(peerT.sock,MsgOpen,sh2n(2,client.id)..name)
      local id = peerT.ridT and peerT.ridT[name]
      if id then
	 peerT.ridT[name]=nil
	 statusCB(peerT.sock, true, id)
      end
   end
   return true
end


function MTL:isopen(name)
   return self.clientsT[name] and true or false
end

function MTL:close(name, msg)
   local client = self.clientsT[name]
   if client then
      msg=sh2n(2,#name)..name..(msg or '')
      for _,peerT in pairs(self.peersT) do
	 sendframe(peerT.sock, MsgClose, msg)
      end
      self.clientsT[name]=nil
      self.clientsIdT[client.id]=nil
   end
   return false
end

function MTL:hascon(ipaddr)
   return self.peersT[ipaddr] and true or false
end

function MTL:shutdown()
   self.terminated=true
   if self.pingtimer then self.pingtimer:cancel() end
   for _,peerT in pairs(self.peersT) do
      if peerT.sock then peerT.sock:close() end
   end
end


local function create(password, op)
   op = op or {}
   local self = {
      password=password,
      clientsT={},
      clientsIdT={},
      peersT={},
      keepalive=op.keepalive or 20,
      keepintv=op.keepintv or 2,
      onstatus=op.onstatus or function() end
   }
   if op.ping then
      assert(type(op.ping) == "table" and
	     type(op.ping.timespan) == "number" and
		type(op.ping.timeout) == "number" and
		op.ping.timeout >= 2 and
		op.ping.timespan >= (op.ping.timeout*4),
	     "Invalid ping settings")
      self.ping=op.ping
      self.ping.roundtripCB = self.ping.roundtripCB or function() end
      self.pingtimer=mktimer(self,pingtimer)
      self.pingtimer:set(op.ping.timeout*1000)
   end

   if op.log then
      assertfunc(op.log,"op.log",4)
      self.logCB=op.log
   end
   return setmetatable(self,MTL)
end


return {
   create=create,
   peername=peername,
   sendframe=sendframe,
   meta=MTL,
}
