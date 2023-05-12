--[[

$Id: mail.lua 4061 2017-04-28 21:51:54Z wini $ 

mail.lua : Simplified mail wrapper for socket.smtp

Copyright (C) Real-Time Logic 2010

--]]
local socket = require"socket"
local ltn12 = require"ltn12"
local mime = require"mime"
local smtp=require "socket.smtp"

local fmt=string.format
local tinsert,tconcat=table.insert,table.concat
local ba,error,type,setmetatable,pairs,ipairs=ba,error,type,setmetatable,pairs,ipairs
local G=_G
local _ENV={}

local function checkAttr(t,attr,info,level)
   if not t[attr] then
      error(fmt('%s is required', info and info or attr), level and level or 3)
   end
end

-- Make sure the email address is SMTP server friendly.
-- Address should be <name@domain.xx>
local function addrSmtp(addr)
   local x=addr:match"[^<]*(<[^>]*>).*"
   return x and x or fmt('<%s>',addr)
end

-- Similar to addrSmtp, but returns a table of addrs
local function addrSmtpT(addr, t)
   t = t or {}
   if addr then
      if type(addr) == 'table' then
	 for _,v in ipairs(addr) do
	    tinsert(t, addrSmtp(v))
	 end
      else
	 tinsert(t, addrSmtp(addr))
      end
   end
   return t
end

local function addrHeader(addr)
   local t={}
   if type(addr) == 'table' then
      for _,v in ipairs(addr) do
	 tinsert(t, v)
      end
   else
      tinsert(t, addr)
   end
   return #t > 0 and tconcat(t, ", ") or nil
end


local function createLtn12Source(x)
   if type(x) == 'string' then return ltn12.source.string(x) end
   if type(x) == 'userdata' and x.read then return ltn12.source.file(x) end
   error("Invalid type. Must be 'string' or 'file pointer'.",3)
end


local function createBody(body, isHtml, encoding, charset, headers)
   local enct = {
      B64=function()
	 return ltn12.source.chain(
	   createLtn12Source(body),
	   ltn12.filter.chain(mime.encode("base64"),mime.wrap())),
	 "BASE64"
      end,
      QUOTED=function()
	 return ltn12.source.chain(
	   createLtn12Source(body),
	   ltn12.filter.chain(
	      mime.normalize(),
	      mime.encode("quoted-printable"),
	      mime.wrap("quoted-printable")
	)),
	 "quoted-printable"
      end,
      ["8BIT"]=function()
	 return ltn12.source.chain(
	   createLtn12Source(body),
	   ltn12.filter.chain(mime.normalize(),mime.wrap())),
	 "8bit"
      end,
      NONE=function()
	 return createLtn12Source(body), "8bit"
      end,
   }
   headers["content-type"] = fmt('%s; charset=%s',
				isHtml and 'text/html' or 'text/plain',
				charset and charset or 'utf-8')
   local ret
   local enc=enct[encoding]
   enc = enc or enct["QUOTED"]
   ret,headers["content-transfer-encoding"]=enc()
   return ret
end


local function attach(t, att)
   local function create(att)
      local name
      if att.name then
	 name=att.name:match("([^\\/]*)$")
      end
      name = name or "unknown"
      local mimetype=att.content or ba.mime(name:match"%.([^%.]-)$" or "")
      local headers = {
	 ["content-type"] = fmt('%s; name="%s"',mimetype,name),
	 ["content-transfer-encoding"] = "BASE64"
      }
      if att.id then -- Assume inline image
	 headers["content-id"]=fmt("<%s>", att.id)
	 headers["content-disposition"] = fmt('inline; filename="%s"',name)
      else
	 headers["content-disposition"] = fmt('attachment; filename="%s"',name)
	 if att.description then
	    headers["content-description"] = att.description
	 end
      end
      return {
	 headers=headers,
	 body=ltn12.source.chain(
		 createLtn12Source(att.source),
		 ltn12.filter.chain(mime.encode("base64"),mime.wrap()))
      }
   end
   if type(att[1]) == 'table' then
      for _,v in ipairs(att) do
	 tinsert(t,create(v))
      end
   else
      tinsert(t,create(att))
   end
end


local mailM = { __index = {} }

function mailM.__index:send(t)
   checkAttr(t, "subject")
   checkAttr(t, "from")
   checkAttr(t, "to")

   local mainmsg = {
      headers={
	 from=addrHeader(t.from),
	 to=addrHeader(t.to),
	 cc=addrHeader(t.cc),
	 subject=t.subject
      }
   }
   local rt=t["reply-to"] or t.replyto
   if rt then
      mainmsg.headers["Reply-To"] = addrHeader(rt)
   end
   local preamble="This is a multi-part message in MIME format."
   local msg
   if t.attach then -- If we must assemble a multipart/mixed message
      msg={headers={}}
      mainmsg.body={preamble=preamble,[1]=msg}
      preamble=nil -- so it is not set again
   else
      msg=mainmsg
   end
   if (t.txtbody and t.htmlbody) or (t.htmlbody and t.htmlimg) then
      -- Assemble a multipart/alternative message
      msg.headers['content-type']='multipart/alternative'
      local alternative={preamble=preamble}
      if t.txtbody then
	 local m={headers={}}
	 m.body = createBody(t.txtbody,false,t.encoding,t.charset,m.headers)
	 tinsert(alternative,m)
      end
      if t.htmlbody then
	 local m={headers={}}
	 m.body = createBody(t.htmlbody,true,t.encoding,t.charset,m.headers)
	 if t.htmlimg then
	    m={
	       headers = {["content-type"] = 'multipart/related',},
	       body={[1]=m}
	    }
	    attach(m.body,t.htmlimg)
	 end
	 tinsert(alternative,m)
      end
      msg.body=alternative
   else
      local body = t.txtbody or t.htmlbody or t.body or "(body)"
      msg.body = createBody(body,t.htmlbody,t.encoding,t.charset,msg.headers)
   end
   if t.attach then
      attach(mainmsg.body,t.attach)
   end
   local mt={
      from=addrSmtp(t.from),
      rcpt=addrSmtpT(t.to),
      source=smtp.message(mainmsg),
      server=self.server,
      port=self.port,
      user=self.user,
      password=self.password,
      shark=self.shark,
      starttls=self.starttls,
      ["8bit"] = mainmsg.headers["content-transfer-encoding"] == "8bit"
	 and true or false
   }
   addrSmtpT(t.cc, mt.rcpt)
   addrSmtpT(t.bcc, mt.rcpt)
   return smtp.send(mt)
end

function socket.mail(t)
   local self=setmetatable({},mailM)
   for k,v in pairs(t) do
      self[k]=v
   end
   checkAttr(self,"server",'Mail "server name"')
   if not self.port then
      self.port = self.shark and not self.starttls and 465 or 25
   end
   return self
end
