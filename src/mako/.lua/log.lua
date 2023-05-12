
require "socket.mail"
local fmt=string.format
local lT,sT,pT

do -- Verify 'log'
   local emsg='log'
   local function tc(v, t) if type(v)~=t then error("Expected "..t,2) end end
   local function verify()
      local t,s,n='table','string','number'
      lT=require"loadconf".log
      tc(lT, t)
      sT=lT.smtp
      tc(sT, t)
      tc(sT.server, s) tc(sT.port, 'number') tc(sT.from, s) tc(sT.to, s)
      if sT.useauth then tc(sT.user, s) tc(sT.password, s) end
      if lT.proxy then
         emsg="proxy"
         pT=require"loadconf".proxy
         tc(pT,t)
         tc(pT.name,s)
         tc(pT.port,n)
      end
   end
   local ok,err = pcall(verify)
   if not ok then
      tracep(false,1,"Invalid '"..emsg.."' configuration table: "..err)
      return nil
   end
end

lT.sdelay = (lT.sdelay or 24*60*60) * 1000
lT.maxsize = lT.maxsize or 8192

local function perr(msg) trace("sendmail failed:", msg) return nil,msg end

local function sendmail(m)
   -- copy smtp settings to new table
   local cfg
   if pT then
      local http = require"httpc".create{
         proxy=pT.name,socks=pT.socks,proxyport=pT.port,proxycon=true}
      local ok,status = http:request{
         url=fmt("http://%s:%d",sT.server,sT.port)}
      if status ~= "prxready" then      
         return perr(fmt("proxy connection failed: %s",status))
      end
      cfg={server=ba.socket.http2sock(http)}
   else
      cfg={server=sT.server,port=sT.port}
   end
   if sT.useauth then
      cfg.user=sT.user
      cfg.password=sT.password
      if sT.consec == "tls" then
         cfg.shark=ba.sharkclient()
      elseif sT.consec == "starttls" then
         cfg.starttls=true
         cfg.shark=ba.sharkclient()
      end
   end
   -- Create send mail object
   local mail=socket.mail(cfg)
   cfg={}
   for k,v in pairs(m) do cfg[k]=v end
   -- Set defaults so we can use sendmail without params.
   cfg.from = m.from or sT.from
   cfg.to = m.to or sT.to
   cfg.subject = m.subject or sT.subject or "Mako Server"
   if not m.body and not m.htmlbody and not m.txtbody then
      cfg.body = ""
   end
   if cfg.body and lT.signature then
      cfg.body = cfg.body.."\n\n"..lT.signature..".\n"
   end
   local ok,err=mail:send(cfg)
   if not ok then perr(err) end
   return ok,err
end


do -- mako.log() setup
   local msglist={}
   local msize=0
   local timer
   local function send(data,op)
      if op then op.body=data else op={body=data} end
      sendmail(op)
   end
   local function flush(op)
      if timer then
         timer:cancel()
         timer=nil
      end
      msize=0
      local data=table.concat(msglist,"\n")
      if #data > 0 then
         msglist={}
         ba.thread.run(function() send(data, op) end)
      end
   end
   local function append(msg,ts)
      if ts then
         msg = os.date("%H:%M: ",os.time())..msg
      end
      table.insert(msglist,msg)
      msize=msize+#msg
      if timer then
         if msize > lT.maxsize then flush() end
      else
         timer=ba.timer(flush)
         timer:set(lT.sdelay)
      end
   end
   function mako.log(msg, op)
      op=op or {}
      if msg then append(msg, op.ts) end
      if op.flush then flush(op) end
      return true
   end
end

if lT.logerr and mako.daemon then
   local op={flush=true}
   local function errorh(emsg, env)
      local e
      if env and env.request then
         e=fmt("LSP Err: %s\nURL: %s\n", emsg, env.request:url())
      else
         e=fmt("Lua Err: %s\n", emsg)
      end
      mako.log(e, op)
   end
   ba.seterrh(errorh)
end


return {
   sendmail=sendmail,
   logT=lT
}
