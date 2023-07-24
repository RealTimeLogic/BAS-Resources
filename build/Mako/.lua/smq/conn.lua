--Conn : SMQ Connector. Copyright Real Time Logic.

local _G=_G
local ba,pairs=ba,pairs

local createtimer -- function

local function rmIPv6prefix(ip)
   if ip and ip:find('::ffff:',1,true) == 1 then return ip:sub(8) end
   return ip
end

local function onStatusChange(_ENV,ipaddr,ok,err)
   if ok then
      conT[ipaddr]=true
   else
      conT[ipaddr]=nil
      createtimer(_ENV)
   end
   statusCB(ipaddr,ok,err)
end


local function commence(_ENV, sock)
   return mtl:commence(
      sock,function(ipaddr,s,status,err)
	      onStatusChange(_ENV,ipaddr,status,err) end)
end

local function connect(sock,_ENV,ipaddr,port)
   local sock,err=ba.socket.connect(ipaddr,port,op)
   if sock then
      if op and op.shark and not sock:trusted(nameT[ipaddr]) then
	 ipaddrT[ipaddr] = nil -- remove
	 log(true,"not Trusted: %s",ipaddr)
	 sock:close()
      elseif not commence(_ENV, sock) then
	 log(false, "%s duplicate",ipaddr)
	 ipaddrT[ipaddr] = nil -- remove address to 'self'
      end
   else
      log(false,"connecting to %s:%d failed: %s",ipaddr,port,err)
      createtimer(_ENV)
   end
end

local function timerfunc(_ENV)
   while true do
      local exit=true
      for ipaddr,port in pairs(ipaddrT) do
	 if not conT[ipaddr] then
	    ba.socket.event(connect,_ENV,ipaddr,port)
	    exit=false
	 end
      end
      if exit then break end
      _G.coroutine.yield(true)
   end
   timer=nil
end

createtimer=function(_ENV)
   if not timer and not terminated then
      timer=ba.timer(function() timerfunc(_ENV) end)
      timer:set(10000, false, true)
   end
end

local function setlist(env, addrlist)
   local nameT,ipaddrT={},{}
   local t={}
   local name,port
   for k,v in pairs(addrlist) do
      if type(k) == 'number' and  type(v) == 'string' then
	 name,port = v,env.port
      elseif type(k) == 'string' and  type(v) == 'number' then
	 name,port = k,v
      else
	 return false
      end
      local ip = rmIPv6prefix(ba.socket.toip(name))
      if not ip then return false end
      ipaddrT[ip] = port
      nameT[ip]=name
   end
   env.nameT=nameT
   env.ipaddrT=ipaddrT
   createtimer(env)
   return true
end

local function add(_ENV, name, port)
   local ip = rmIPv6prefix(ba.socket.toip(name))
   if not ip or ipaddrT[ip] then return false end
   ipaddrT[ip] = port or _ENV.port
   nameT[ip]=name
   createtimer(_ENV)
   return true
end

local function status(_ENV)
   local t={}
   for ip in pairs(ipaddrT) do
      t[ip]=conT[ip] or false
   end
   for ip in pairs(conT) do
      t[ip]=true
   end
   return t
end

local function accept(sock, env)
   while true do
      local s = sock:accept()
      if not s then break end -- shutdown called
      commence(env, s)
   end
end

local function shutdown(_ENV)
   terminated=true
   if timer then
      timer:cancel()
      timer=nil
   end
   return ssock:close()
end

local Conn={
   setlist=setlist,
   add=add,
   status=status,
   shutdown=shutdown,
}
Conn.__index=Conn


-- op: from ba.socket.bind + close callback 'onclose'
local function create(mtl, port, op)
   op=op or {}
   if mtl.mtl and mtl.mtl.commence then mtl=mtl.mtl end
   assert(type(mtl.commence) == "function", "Not a cluster manager")
   local env={port=port,conT={},nameT={},ipaddrT={},mtl=mtl,
      statusCB=op.onstatus or function() end, op=op
   }
   env.log=function(highprio,msg,...) mtl:log(highprio,"Conn "..msg,...) end
   local shark = op.shark
   if shark then
      op.shark = op.sshark
      if not op.shark then error("Attr. sshark required when shark is set") end
   end
   local s, err = ba.socket.bind(port, op)
   op.shark=shark
   if not s then return nil,err end
   env.ssock=s
   s:event(accept,"r",env)
   return setmetatable(env,Conn)
end


return {
   create=create,
}
