local fmt,schar,sbyte,ssub=string.format,string.char,string.byte,string.sub
local tinsert,tconcat=table.insert,table.concat
local h2n,n2h,fh2n,fn2h=ba.socket.h2n,ba.socket.n2h,ba.socket.fh2n,ba.socket.fn2h

-- Modbus function codes
local READ_COILS		    =0x01
local READ_DISCRETE_INPUTS	    =0x02
local READ_HOLDING_REGISTERS	    =0x03
local READ_INPUT_REGISTERS	    =0x04
local WRITE_SINGLE_COIL		    =0x05
local WRITE_SINGLE_REGISTER	    =0x06
local WRITE_MULTIPLE_COILS	    =0x0F
local WRITE_MULTIPLE_REGISTERS	    =0x10
local READ_WRITE_MULTIPLE_REGISTERS =0x17


-- Start: decode type
local dectypeT = {
   word=function(data,len)
	   local t={}
	   for i=0,len//2-1 do tinsert(t,n2h(2,data,10+(i*2))) end
	   return t
	end,
   dword=function(data,len)
	   local t={}
	   for i=0,len//4-1 do tinsert(t,n2h(4,data,10+(i*4))) end
	   return t
	 end,
   float=function(data,len)
	   local t={}
	   for i=0,len//4-1 do tinsert(t,fn2h(4,data,10+(i*4))) end
	   return t
	 end,
   double=function(data,len)
	   local t={}
	   for i=0,len//8-1 do tinsert(t,fn2h(8,data,10+(i*8))) end
	   return t
	  end,
   string=function(data)
	     return ssub(data,10)
	  end,
}
local function dectype(data,len,vtype)
   local func = dectypeT[vtype]
   return func(data,len)
end
-- End: decode type

-- Start: encode type
local enctypeT = {
   word=function(t)
	   local rsp={}
	   for _,v in ipairs(t) do tinsert(rsp,h2n(2,v)) end
	   return tconcat(rsp)
	end,
   dword=function(t)
	   local rsp={}
	   for _,v in ipairs(t) do tinsert(rsp,h2n(4,v)) end
	   return tconcat(rsp)
	 end,
   float=function(t)
	   local rsp={}
	   for _,v in ipairs(t) do tinsert(rsp,fh2n(4,v)) end
	   return tconcat(rsp)
	 end,
   double=function(t)
	   local rsp={}
	   for _,v in ipairs(t) do tinsert(rsp,fh2n(8,v)) end
	   return tconcat(rsp)
	  end,
   string=function(str)
	     if #str % 2 ~= 0 then return str.."\0" end
	     return str
	  end,
}
local function enctype(t,vtype)
   local func = enctypeT[vtype] or enctypeT.word
   return func(t)
end
-- End: encode type

-- Start: type size to modbus word len calc
local towlenT={
   word=function(len) return len end,
   dword=function(len) return len*2 end,
   double=function(len) return len*4 end,
   string=function(len) return len//2+(len %2 ~= 0 and 1 or 0) end
}
towlenT.float=towlenT.dword

local function towordlen(len,vtype)
   local func = assert(towlenT[vtype],"Invalid value type")
   return func(len)
end
-- End: type size to modbus word len calc

-- Start: modbus word len to type size
local fromwlenT={
   word=function(len) return len end,
   dword=function(len) return len//2 end,
   double=function(len) return len//4 end,
   string=function(len) return len*2 end
}
fromwlenT.float=fromwlenT.dword

local function fromwordlen(len,vtype)
   local func = fromwlenT[vtype]
   return func(len)
end
-- End: modbus word len to type size


local function fmtArgErr(argno,func,exp,got)
   return fmt("bad argument #%d to '%s' (%s expected, got %s)",
	      argno,func,exp,type(got))
end

local function eRange(max,argix,level)
   error(fmt("Arg #%d outside valid range 1-%d",argix,max),level)
end

-- Sort and validate optional arguments without reserving a transaction.
local function ftArgSort(self,vtype,uid,onresp,level)
   if type(vtype) ~= "string" then
      -- If vtype is not a string, shift the arguments
      onresp = uid
      uid = vtype
      vtype = "word"
   end
   if type(uid) ~= "number" then
      -- If uid is not a number, shift the arguments
      onresp = uid
      uid = 1
   end
   if type(uid) ~= "number"  or uid < (self.minuid or 0) or uid > 247 then
      error("Unit Identifier", level)
   end
   if self.async and type(onresp) ~= "function" then
      error("Async callback required", level)
   end
   return uid,vtype,onresp
end

-- Wait for data
local function rec(self)
   return self.sock:read(self.timeout)
end


local function recframe(self)
   local data
   if self.recOverflowData then
      data = self.recOverflowData
      self.recOverflowData =nil
   else
      data=""
   end
   while #data < 6 do
      local p,err = rec(self)
      if not p then
	 if self.async and err=="timeout" then self.recOverflowData=data end
	 return nil,err
      end
      data = data..p
   end
   local len = n2h(2,data,5)+6
   if len < 9 or n2h(2,data,3) ~= 0 then return nil,"invalidresponse" end
   while #data < len do
      local p,err = rec(self)
      if not p then
	 if self.async and err=="timeout" then self.recOverflowData=data end
	 return nil,err
      end
      data = data..p
   end
   if len == #data then return data end
   self.recOverflowData = ssub(data, len+1)
   return ssub(data,1,len)
end


local function prepheader(self,uid,func,addr,val,len)
   local tran = self.transaction
   return h2n(2,tran)..h2n(2,0)..h2n(2,len)..schar(uid,func)..h2n(2,addr)..h2n(2,val)
end

--Start: Modbus response management
local function readbitsResp(data,vtype)
   local t={}
   -- ref-L: len saved as vtype
   local len=tonumber(vtype)
   for byteix=1,sbyte(data,9) do
      local byte = sbyte(data,9+byteix)
      if nil == byte then break end
      local bit = 1
      while bit < 256 do
	 if len == 0 then break end
	 tinsert(t,(byte & bit) ~= 0 and true or false)
	 bit = bit << 1
	 len = len - 1
      end
   end
   return t
end

local function readbytesResp(data,vtype)
   return dectype(data,sbyte(data,9),vtype)
end

local function retTrueResp() return true end

-- Manage Response (switch statement)
local mrespT={
   [READ_COILS]=readbitsResp,
   [READ_DISCRETE_INPUTS]=readbitsResp,
   [READ_HOLDING_REGISTERS]=readbytesResp,
   [READ_INPUT_REGISTERS]=readbytesResp,
   [WRITE_SINGLE_COIL]=retTrueResp,
   [WRITE_SINGLE_REGISTER]=retTrueResp,
   [WRITE_MULTIPLE_COILS]=retTrueResp,
   [WRITE_MULTIPLE_REGISTERS]=retTrueResp,
   [READ_WRITE_MULTIPLE_REGISTERS]=readbytesResp,
}
--End: Modbus response management

-- Synchronous and asynchronous response management
local function responseMatches(data,request)
   if sbyte(data,7) ~= sbyte(request,1) then return false end
   local func=sbyte(request,2)
   if sbyte(data,8) == func+0x80 then return #data==9 end
   if sbyte(data,8) ~= func then return false end
   local len=n2h(2,request,5)
   if func==READ_COILS or func==READ_DISCRETE_INPUTS then
      len=(len+7)//8
   elseif func==READ_HOLDING_REGISTERS or func==READ_INPUT_REGISTERS or
          func==READ_WRITE_MULTIPLE_REGISTERS then
      len=len*2
   else
      return ssub(data,7)==request
   end
   return #data==len+9 and sbyte(data,9)==len
end

local function close(self)
   if not self.closed then
      self.closed=true
      return self.sock:close()
   end
end

local function rpcResp(self)
   local data,err=recframe(self)
   if data then
      local trans = n2h(2,data)
      local cbT = self.rspQ[trans]
      if cbT then
	 self.rspQ[trans]=nil
	 local func = sbyte(data,8)
	 if not responseMatches(data,cbT[3]) then
	    data,err=nil,"invalidresponse"
	 elseif func & 0x80 ~= 0 then
	    data,err = nil,sbyte(data,9)
	 else
	    local mresp=mrespT[func] -- Get modbus response management func
	    if mresp then
	       data,err = mresp(data, cbT[2]) -- (data, vtype) : Ref-Q
	    else
	       data,err=nil,fmt("server resp: invalid function code: %d",func)
	    end
	 end
	 self.inqueue = self.inqueue-1
	 if self.async then
	    cbT[1](data,err,trans,self) -- callbackFunc(data, err) : Ref-Q
	 end
      else
	 data,err=nil,fmt("server resp: invalid transaction id: %d",trans)
      end
   end
   if not data and (err ~= "timeout" or not self.async) then
      close(self)
   end
   return data,err
end

-- Async cosocket
local function asyncRec(_,self)
   local ok,err=nil,"closed"
   while not self.closed do
      ok,err=rpcResp(self)
      if not ok then
	 if err == "timeout" then
	    if self.inqueue > 0 then -- Async timeout management
	       if self.queuesample == self.inqueue then -- timeout error
		  break -- exit
	       end
	       self.queuesample = self.inqueue
	    else
	       self.queuesample = nil
	    end
	    if self.ontimeout then
	       self.ontimeout(self)
	    end
	 else -- error
	    break -- exit
	 end
      end
   end
   close(self)
   if self.cancelled then err="closed" end
   local pending=self.rspQ
   self.rspQ={}
   self.inqueue=0
   if self.onclose and not self.cancelled then
      self.onclose(err,self)
   elseif self.async then
      local failed,reason
      for trans,cbT in pairs(pending) do
	 local ok,msg=pcall(cbT[1],nil,err,trans,self)
	 if not ok and not failed then failed,reason=true,msg end
      end
      if failed then error(reason,0) end
   end
end

local function rpc(self,data,onresp,vtype)
   local tran=self.transaction
   assert(not self.rspQ[tran])
   self.rspQ[tran]={onresp,vtype,ssub(data,7,12)} -- Ref-Q
   self.inqueue=self.inqueue+1
   self.transaction=(tran+1) & 0xFFFF
   local ok,err=self.sock:write(data)
   if ok then
      if self.async then
	 return tran
      end
      return rpcResp(self)
   end
   if self.rspQ[tran] then
      self.rspQ[tran]=nil
      self.inqueue=self.inqueue-1
   end
   close(self)
   return nil,err
end

--  Read coils or discrete inputs
local function readbits(self,addr,len,func,uid,onresp)
   -- Save len as vtype: ref-L
   local vtype
   uid,vtype,onresp=ftArgSort(self,tostring(len),uid,onresp,3)
   if len < 1 or len > 2000 then eRange(2000,2,3) end
   return rpc(self,prepheader(self,uid,func,addr,len,6),onresp,vtype)
end


--  Read Input Registers or Read Multiple Holding Registers
local function readbytes(self,addr,tlen,func,vtype,uid,onresp)
   uid,vtype,onresp=ftArgSort(self,vtype,uid,onresp,3)
   local len = towordlen(tlen,vtype)
   if len < 1 or len > 125 then eRange(fromwordlen(125,vtype),2,3) end
   return rpc(self,prepheader(self,uid,func,addr,len,6),onresp,vtype)
end

local C={} -- Modbus Client
C.__index=C


-- Read coil(s): read one or several bits
-- Read coils: addr: number, len: number
function C:rcoil(addr,len,uid,onresp)
   return readbits(self,addr,len,READ_COILS,uid,onresp)
end


-- Discrete input(s): read one or several bits
function C:discrete(addr,len,uid,onresp)
   return readbits(self,addr,len,READ_DISCRETE_INPUTS,uid,onresp)
end

-- Write single coil: addr: number, val: boolean
-- Write multiple coils: addr: number, val: table with booleans
function C:wcoil(addr,val,uid,onresp)
   local data
   local vtype
   uid,vtype,onresp=ftArgSort(self,"",uid,onresp,2)
   if type(val) == "boolean" then
      data=prepheader(self,uid,WRITE_SINGLE_COIL,addr,val and 0xFF00 or 0,6)
      return rpc(self,data,onresp,vtype)
   end
   if type(val) == "table" then
      local len = #val
      if len < 1 or len > 1968 then eRange(1968,2,3) end
      data={}
      local bit,byte = 1,0
      for _,v in ipairs(val) do
	 if v then byte = byte | bit end
	 bit = bit << 1;
	 if bit == 256 then tinsert(data,byte) bit,byte = 1,0 end
      end
      if bit ~= 1 then tinsert(data,byte) end
      data=schar(table.unpack(data))
      data=prepheader(self,uid,WRITE_MULTIPLE_COILS,addr,len,#data+7)..schar(#data)..data
      return rpc(self,data,onresp,vtype)
   end
   error(fmtArgErr(2,"wcoil","boolean/table",val),2)
end


function C:rholding(addr,len,vtype,uid,onresp)
   return readbytes(self,addr,len,READ_HOLDING_REGISTERS,vtype,uid,onresp)
end

function C:register(addr,len,vtype,uid,onresp)
   return readbytes(self,addr,len,READ_INPUT_REGISTERS,vtype,uid,onresp)
end

function C:wholding(addr,val,vtype,uid,onresp)
   uid,vtype,onresp=ftArgSort(self,vtype,uid,onresp,2)
   local data,len
   if type(val) == "table" or vtype == "string" then
      len = towordlen(#val,vtype)
      if len < 1 or len > 0x7B then eRange(fromwordlen(0x7B,vtype),2,3) end
   else
      len = towordlen(1,vtype)
      if len == 1 and type(val) == "number" then
	 data=prepheader(self,uid,WRITE_SINGLE_REGISTER,addr,val,6)
	 return rpc(self,data,onresp,vtype)
      end
      val={val}
   end
   data=prepheader(self,uid,WRITE_MULTIPLE_REGISTERS,addr,len,7+(len*2))
   data = data..schar(len*2)..enctype(val,vtype)
   return rpc(self,data,onresp,vtype)
end


function C:readwrite(raddr,rlen,waddr,wval,vtype,uid,onresp)
   uid,vtype,onresp=ftArgSort(self,vtype,uid,onresp,2)
   local data,wlen
   rlen = towordlen(rlen,vtype)
   if rlen < 1 or rlen > 0x7D then eRange(fromwordlen(0x7D,vtype),2,3) end
   if type(wval) == "table" or vtype == "string" then
      wlen = towordlen(#wval,vtype)
      if wlen < 1 or wlen > 0x79 then eRange(fromwordlen(0x79,vtype),4,3) end
   else
      wlen = towordlen(1,vtype)
      wval={wval}
   end
   data=prepheader(self,uid,READ_WRITE_MULTIPLE_REGISTERS,raddr,rlen,11+(wlen*2))
   data=data..h2n(2,waddr)..h2n(2,wlen)..schar(wlen*2)..enctype(wval,vtype)
   return rpc(self,data,onresp,vtype)
end


function C:connected()
   local s,valid = self.sock:state()
   return valid ~= false and s ~= "notcon" and s ~= "terminated", s
end

function C:close()
   self.cancelled=true
   return close(self)
end

local function connect(addr,opt)
   local sock,err
   opt = opt or {}
   local self=setmetatable({rspQ={},inqueue=0,transaction=0,timeout=opt.timeout or 3000},C)
   local onclose=type(opt.onclose) == "function" and opt.onclose
   if type(addr) == "string" then
      sock,err=ba.socket.connect(addr,opt.port or 502,opt)
      if not sock then return nil,err end
      self.sock=sock
   elseif type(addr) == "userdata" and type(addr.trusted) == "function" then
      sock,self.sock=addr,addr
   elseif type(addr) == "table" and type(addr.read) == "function" then
      self.sock,self.async,self.onclose=addr,true,onclose
      return self, function() asyncRec(addr, self) end
   else
      error(fmtArgErr(1,"connect","string",addr),2)
   end
   if sock:owner() or opt.async then
      self.async=true
      self.onclose = onclose
      if type(opt.async) == "function" then self.ontimeout=opt.async end
      if sock:owner() then -- Already in cosocket mode
	 return self, function() asyncRec(sock, self) end
      else
	 sock:event(asyncRec, "s", self)
      end
   end
   return self
end

return {connect=connect}
