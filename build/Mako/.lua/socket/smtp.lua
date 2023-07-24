-----------------------------------------------------------------------------
-- SMTP client support for the Lua language.
-- LuaSocket toolkit.
-- Author: Diego Nehab
-- Modified by RTL
-----------------------------------------------------------------------------

-----------------------------------------------------------------------------
-- Declare module and import dependencies
-----------------------------------------------------------------------------
local base = _G
local socket = require("socket")
local tp = require("socket.tp")
local ltn12 = require("ltn12")
local mime = require("mime")
local tonumber = base.tonumber
local type = base.type

local _ENV=setmetatable({},{__index=_G})

-----------------------------------------------------------------------------
-- Program constants
-----------------------------------------------------------------------------
-- timeout for connection
TIMEOUT = 60
-- default server used to send e-mails
-- default port
PORT = 25
-- domain used in HELO command and default sendmail
-- If we are under a CGI, try to get from environment
DOMAIN = os and os.getenv and os.getenv("SERVER_NAME") or "localhost"
-- default time zone (means we don't know)
ZONE = "-0000"

---------------------------------------------------------------------------
-- Low level SMTP API
-----------------------------------------------------------------------------
local metat = { __index = {} }

function metat.__index:greet(domain)
    self.try(self.tp:check("2.."))
    self.try(self.tp:command("EHLO", domain or DOMAIN))
    return socket.skip(1, self.try(self.tp:check("2..")))
 end


function metat.__index:upgrade(shark)
   self.tp:upgrade(shark)
end

function metat.__index:starttls(domain,shark)
   self.try(self.tp:command("STARTTLS"))
   socket.skip(1, self.try(self.tp:check("2..")))
   self.tp:upgrade(shark)
   self.try(self.tp:command("EHLO", domain or DOMAIN))
   return socket.skip(1, self.try(self.tp:check("2..")))
end


function metat.__index:mail(from)
    self.try(self.tp:command("MAIL", "FROM:" .. from .. (self.fromext or "") ))
    return self.try(self.tp:check("2.."))
end

function metat.__index:rcpt(to)
    self.try(self.tp:command("RCPT", "TO:" .. to .. (self.rcptext or "") ))
    return self.try(self.tp:check("2.."))
end

function metat.__index:data(src, step)
    self.try(self.tp:command("DATA"))
    self.try(self.tp:check("3.."))
    self.try(self.tp:source(src, step))
    self.try(self.tp:send("\r\n.\r\n"))
    return self.try(self.tp:check("2.."))
end

function metat.__index:quit()
    self.try(self.tp:command("QUIT"))
    return self.try(self.tp:check("2.."))
end

function metat.__index:close()
    return self.tp:close()
end

function metat.__index:login(user, password)
    self.try(self.tp:command("AUTH", "LOGIN"))
    self.try(self.tp:check("3.."))
    self.try(self.tp:credentialcmd(mime.b64(user)))
    self.try(self.tp:check("3.."))
    self.try(self.tp:credentialcmd(mime.b64(password)))
    return self.try(self.tp:check("2.."))
end

function metat.__index:plain(user, password)
    local auth = "PLAIN " .. mime.b64("\0" .. user .. "\0" .. password)
    self.try(self.tp:command("AUTH", auth))
    return self.try(self.tp:check("2.."))
end

function metat.__index:auth(user, password, ext)
    if not user or not password then return 1 end
    if string.find(ext, "AUTH[^\n]+LOGIN") then
	return self:login(user, password)
    elseif string.find(ext, "AUTH[^\n]+PLAIN") then
	return self:plain(user, password)
    else
	self.try(nil, "authentication not supported")
    end
end

-- send message or throw an exception
function metat.__index:send(mailt)
    self:mail(mailt.from)
    if base.type(mailt.rcpt) == "table" then
	for i,v in base.ipairs(mailt.rcpt) do
	    self:rcpt(v)
	end
    else
	self:rcpt(mailt.rcpt)
    end
    self:data(ltn12.source.chain(mailt.source, mime.stuff()), mailt.step)
end

function open(server, port, create)
    local tp = socket.try(tp.connect(server, port or PORT,
	TIMEOUT, create))
    local s = base.setmetatable({tp = tp}, metat)
    -- make sure tp is closed if we get an exception
    s.try = socket.newtry(function()
	s:close()
    end)
    return s
end

function metat.__index:help(cmd)
    self.try(self.tp:command("HELP", cmd))
    return self.try(self.tp:check("2.."))
end

---------------------------------------------------------------------------
-- Multipart message source
-----------------------------------------------------------------------------
-- returns a hopefully unique mime boundary
local seqno = 0
local function newboundary()
    seqno = seqno + 1
    return string.format('%s%05d==%05u', os.date('%d%m%Y%H%M%S'),
	ba.rnd(0, 99999), seqno)
end

-- send_message forward declaration
local send_message

-- yield the headers all at once, it's faster
local function send_headers(headers)
    local h = "\r\n"
    for i,v in base.pairs(headers) do
	h = i .. ': ' .. v .. "\r\n" .. h
    end
    coroutine.yield(h)
end

-- yield multipart message body from a multipart message table
local function send_multipart(mesgt)
    -- make sure we have our boundary and send headers
    local bd = newboundary()
    local headers = mesgt.headers or {}
    headers['content-type'] = headers['content-type'] or 'multipart/mixed'
    headers['content-type'] = headers['content-type'] ..
	'; boundary="' ..  bd .. '"'
    send_headers(headers)
    -- send preamble
    if mesgt.body.preamble then
	coroutine.yield(mesgt.body.preamble)
	coroutine.yield("\r\n")
    end
    -- send each part separated by a boundary
    for i, m in base.ipairs(mesgt.body) do
	coroutine.yield("\r\n--" .. bd .. "\r\n")
	send_message(m)
    end
    -- send last boundary
    coroutine.yield("\r\n--" .. bd .. "--\r\n\r\n")
    -- send epilogue
    if mesgt.body.epilogue then
	coroutine.yield(mesgt.body.epilogue)
	coroutine.yield("\r\n")
    end
end

-- yield message body from a source
local function send_source(mesgt)
    -- make sure we have a content-type
    local headers = mesgt.headers or {}
    headers['content-type'] = headers['content-type'] or
	'text/plain; charset="iso-8859-1"'
    send_headers(headers)
    -- send body from source
    while true do
	local chunk, err = mesgt.body()
	if err then coroutine.yield(nil, err)
	elseif chunk then coroutine.yield(chunk)
	else break end
    end
end

-- yield message body from a string
local function send_string(mesgt)
    -- make sure we have a content-type
    local headers = mesgt.headers or {}
    headers['content-type'] = headers['content-type'] or
	'text/plain; charset="iso-8859-1"'
    send_headers(headers)
    -- send body from string
    coroutine.yield(mesgt.body)
end

-- message source
function send_message(mesgt)
    if base.type(mesgt.body) == "table" then send_multipart(mesgt)
    elseif base.type(mesgt.body) == "function" then send_source(mesgt)
    else send_string(mesgt) end
end

-- set default headers
-- PATCH (wini): Redesigned to not upcase first char of key val.
-- The upcasing made case sensitive tests in this code fail
local function adjust_headers(mesgt)
    local t = {}
    t["date"] = mesgt["date"] or os.date("!%a, %d %b %Y %H:%M:%S ") .. (mesgt.zone or ZONE)
    t["x-mailer"] = mesgt["x-mailer"] or socket._VERSION
    for i,v in base.pairs(mesgt.headers or {}) do
       t[string.lower(i)] = v
    end
    t["mime-version"] = "Mime-version","1.0"   -- this can't be overriden
    mesgt.headers = t
end

function message(mesgt)
    adjust_headers(mesgt)
    -- create and return message source
    local co = coroutine.create(function() send_message(mesgt) end)
    return function()
	local ret, a, b = coroutine.resume(co)
	if ret then return a, b
	else return nil, a end
    end
end

local function conaddr(addr)
    if not addr or string.len(addr) < 3 then return nil end
    return select(3,string.find(addr, "(%b<>)"))
end

---------------------------------------------------------------------------
-- High level SMTP API
-----------------------------------------------------------------------------
send = socket.protect(function(mailt)
    local s = open(mailt.server, mailt.port, mailt.create)
    if mailt.shark and not mailt.starttls then s:upgrade(mailt.shark) end
    local ext = s:greet(mailt.domain)
    local sext
    local function mkext(ext)
       sext={}
       string.gsub(ext, "250[%- ]([%u%d]+)[ ]?(%d*)",
		function (k,v) sext[k]=((v == "") and true) or tonumber(v) end)
       s.ext = sext
    end
    mkext(ext)
    if mailt.shark and mailt.starttls and s.ext["STARTTLS"] then
       ext=s:starttls(mailt.domain,mailt.shark)
       mkext(ext)
    end

    socket.try(mailt.from, "Sender (from) is required")
    socket.try(mailt.rcpt, "Recipient (rcpt) is required")

    s.fromext=""
    s.rcptext=""
    if sext.SIZE and mailt.size then
      s.fromext = s.fromext .." SIZE="..tonumber(mailt.size)
    end

    if sext["8BITMIME"] and mailt["8bit"] then
      s.fromext = s.fromext .." BODY=8BITMIME"
    end

    if sext.DELIVERBY and mailt.deliverby then
      local b,e,n,m = string.find(mailt.deliverby,"(%d*);?([RN]?)")
      s.fromext = s.fromext ..
		  " BY="..tonumber(n)..';'..((m == '' and 'N') or m)
    end

    -- dsn = {ret="FULL", notify="NEVER", id=,
    if sext.DSN and mailt.dsn and type(mailt.dsn) == "table" then
      local t = mailt.dsn
      s.rcptext = s.rcptext ..
	 ((t.notify and " NOTIFY="..string.upper(t.notify))
	  or " NOTIFY=SUCCESS,FAILURE,DELAY")	  -- || NEVER
      s.fromext=s.fromext .. " RET="..(t.ret or "HDRS")	  --	HDRS || FULL
      if t.id then
	s.fromext=s.fromext .. " ENVID="..t.id		  -- upto 100 chars
      end
    end

--     print(s.fromext)


    s:auth(mailt.user, mailt.password, ext)
    s:send(mailt)
    s:quit()
    return s:close()
end)

help = socket.protect(function(mailt)
    local s = open(mailt.server, mailt.port)
    local ext = s:greet(mailt.domain)
    local sext={}
    string.gsub(ext, "250[%- ]([%u%d]+)[ ]?(%d*)",
      function (k,v) sext[k]=((v == "") and true) or tonumber(v) end)
    if not sext.HELP then
      s:quit()
      s:close()
      return ""
    end
    s:auth(mailt.user, mailt.password, ext)
    local h,t = s:help(mailt.command)
    s:quit()
    s:close()
    return h,t
end)

extensions = socket.protect(function(mailt)
    local s = open(mailt.server, mailt.port)
    local ext = s:greet(mailt.domain)
    local sext={}
    string.gsub(ext, "250[%- ]([%u%d]+)[ ]?(%d*)",
      function (k,v) sext[k]=((v == "") and true) or tonumber(v) end)
    s:auth(mailt.user, mailt.password, ext)
    s:quit()
    s:close()
    return sext
end)

return _ENV
