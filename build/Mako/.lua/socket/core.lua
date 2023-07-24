--[[

$Id: core.lua 4061 2017-04-28 21:51:54Z wini $ 

socket.core.lua: Included by socket.lua
Provides a compatibility layer between ba.socket and Lua sockets.
See lsocket.c for more info.
Copyright (C) Real-Time Logic 2010

--]]

local G = _G
local s = ba.socket
assert(s, "BA socket lib (lsocket.c) not included in build")
assert(sockcompat, "BA socket lib compat mode in lsocket.c removed")
G.socket=sockcompat
local socket=G.socket


function socket.gettime()
   return G.os.time()
end

function socket.sleep(secs)
   ba.sleep(secs*1000)
end

local sharkssl
function socket.secure(shark)
   sharkssl=shark
end

local tinsert=table.insert
local tremove=table.remove
local tconcat=table.concat
local sgmatch=string.gmatch
local sfind=string.find
local fmt=string.format

local _ENV={}
local ix={}
local tcpM = { __index = ix }
local function initSock(self)
   if self.s then self.s:close() end
   self.s=nil
   self.received=0
   self.sent=0
   self.recDataIx=1
   self.age=G.os.time()
end


local function bas2SockErr(err)
   if err then
      return err == "socketreadtimeout" and "timeout" or "closed"
   end
end


local function ix_pruneRecData(self,extra)
   local data = self.recData
   if data then
      self.recData=nil
      if self.recDataIx > 1 then
	 data=data:sub(self.recDataIx)
	 self.recDataIx=1
      end
      if extra then return data..extra end
      return data
   end
   return extra
end


function ix:bind(address, port)
   self.op = { intf=address, port=port, shark=sharkssl }
   return true
end
function ix:close()
   return self.s and self.s:close() or false
end

function ix:connect(address, port)
   local e
   initSock(self)
   if G.type(address) == "userdata" and address.upgrade then
      self.s=address
      return true
   end
   self.s,e=s.connect(address, port, self.op and self.op or {shark=sharkssl})
   if self.s then return true end
   return nil,e
end

function ix:certificate()
   return self.s:certificate()
end

function ix:sockname()
   return self.s:sockname()
end

function ix:getsockname()
   return self.s:getsockname()
end

function ix:upgrade(shark)
   return self.s:upgrade(shark)
end

function ix:peername()
   return self.s:peername()
end

function ix:getpeername()
   return self.s:getpeername()
end

function ix:getstats()
   return self.received,self.sent,self.age
end

function ix:setstats(received, sent, age)
   self.received,self.sent,self.age=received,sent,age
   return 1
end

function ix:listen(backlog)
   local e
   initSock(self)
   self.s,e=ba.socket.bind(self.op.port, self.op)
   if self.s then return true end
   return nil,e
end

function ix:settimeout(value, mode)
   if not value or value <= 0 then
      self.timeout=nil
   else
      self.timeout=value*1000
   end
end

function ix:receive(pattern, prefix)
   local d,e,t
   local recData=self.recData
   pattern = pattern or "*l"
   if pattern == "*a" then
      t={}
      if prefix then tinsert(t,prefix) end
      if recData then tinsert(t,ix_pruneRecData(self)) end
      while true do
	 d,e = self.s:read(self.timeout)
	 if not d then break end
	 tinsert(t,d)
      end
      if (pattern and #t > 1) or #t > 0 then return tconcat(t) end
      return nil, bas2SockErr(e)
   end
   if pattern == "*l" then
      while true do
	 if recData then
	    local x,y = recData:find("\r?\n",self.recDataIx)
	    if x then
	       recData=recData:sub(self.recDataIx, x-1)
	       if self.recDataIx >= #self.recData then
		  self.recData = nil
		  self.recDataIx=1
	       else
		  self.recDataIx=y+1
	       end
	       if prefix then return prefix..recData end
	       return recData
	    end
	 end
	 d,e = self.s:read(self.timeout)
	 if not d then
	    return nil,bas2SockErr(e),ix_pruneRecData(self)
	 end
	 recData = ix_pruneRecData(self, d)
	 self.recData=recData
      end
   end
   local recLen
   local len = G.tonumber(pattern)
   G.assert(len, "Invalid pattern")
   if len <= 0 then return "" end
   ::L_recData::
   if recData then
      local left = #recData + 1 - self.recDataIx
      if len == left then return ix_pruneRecData(self) end
      if len < left then
	 recData = recData:sub(self.recDataIx,self.recDataIx+len-1)
	 self.recDataIx = self.recDataIx + len
	 if prefix then return prefix..recData end
	 return recData
      end
      recData=ix_pruneRecData(self)
      recLen=#recData
      t={recData}
   else
      t={}
      recLen=0
   end
   while recLen < len do
      d,e = self.s:read(self.timeout)
      if not d then
	 return nil,bas2SockErr(e),tconcat(t)
      end
      tinsert(t,d)
      recLen = recLen + #d
   end
   recData=tconcat(t)
   self.recData=recData
   goto L_recData
end


function ix:send(data,i,j)
   if G.type(data) == "table" then
      data = tconcat(data)
   end
   local ok,err=self.s:write(data,i,j)
   if ok then return ok end
   return nil,err
end

function ix:setoption(...)
   return self.s:setoption(...)
end

function ix:shutdown()
   return self.s:close() -- No shutdown thus use close
end

function tcp()
   return G.setmetatable({},tcpM)
end

BLOCKSIZE=512
socket.tcp=tcp

return _ENV
