
local http=require"httpc"

-- Build New Options (nop) from Default Options (dop) and provided option (op)
local function mkop(dop,op)
   if not dop then return op and op or {} end
   if not op then return dop end
   local nop = {}
   for k,v in pairs(dop) do
      nop[k]=v
   end
   for k,v in pairs(op) do
      nop[k]=v
   end
   return nop
end



-- Basic: Check HTTP status for 301 and 302 responses
local function checkStatus(self)
   local raw=self.raw
   if not self.statuscode then
      local s,e1,e2,e3=raw:status()
      if not s then return nil,e1,e2,e3 end
      if s == 301 or s == 302 or s == 303 or s == 307 then
	 local r=0
	 local op=self.nop
	 local method = op.method or "GET"
	 while s == 301 or s == 302 or s == 303 or s == 307 do
	    raw:read(0) -- Discard response
	    r=r+1
	    if r == 10 then return nil, "redirect" end
	    local url=raw:header"location"
	    if not url then
	       return nil, "invalidresponse"
	    end
	    local u,q=url:match("([^%?]-)%?(.+)")
	    if u then
	       url=u
	       op.query=http.parsequery(q)
	    end
	    if url:match"^https?://" then
	       op.url = url
	    else
	       local xurl = op.url
	       xurl = xurl:byte(-1) == 47 and xurl:sub(1,-2) or xurl
	       op.url = xurl..url
	    end
	    if (301 == s or 302 == s) and ("PUT" == method or "POST" == method) then
	       return nil,s,op.url
	    end
	    op.method = s == 307 and method or "GET"
	    local ok,e1,e2,e3=raw:request(op)
	    if not ok then return nil,e1,e2,e3 end
	    s,e1,e2,e3=raw:status()
	    if not s then return nil,e1,e2,e3 end
	 end
      end
      self.statuscode=s
   end
   return true
end


local H={}
function H:certificate()  return self.raw:certificate() end
function H:cookie() return self.raw:cookie() end
function H:header() return self.raw:header() end
function H:headerpairs() return self.raw:headerpairs() end
function H:timeout(ms) return self.raw:timeout(ms) end
function H:write(data) return self.raw:write(data) end
function H:read(size)
   local ok,e1,e2,e3=checkStatus(self)
   if ok then return self.raw:read(size) end
   return nil,e1,e2,e3
end
function H:cipher() return self.raw:cipher() end
function H:trusted() return self.raw:trusted() end
function H:sockname() return self.raw:sockname() end
function H:peername() return self.raw:peername() end
function H:status(size)
   local ok,e1,e2,e3=checkStatus(self)
   if ok then return self.statuscode end
   return nil,e1,e2,e3
end

function H:close()
   checkStatus(self)
   return self.raw:close()
end

function H:request(op)
   self.statuscode=nil
   local sop=self.op
   sop.query=nil
   self.nop=mkop(sop,op)
   return self.raw:request(self.nop)
end

function H:url()
   if not self.statuscode then
      local ok,e1,e2,e3=checkStatus(self)
      if not ok then return nil,e1,e2,e3 end
   end
   return self.nop.url,self.nop.query
end

function H:mkop(op1,op2) return op2 and mkop(op1,op2) or mkop(self.op,op1) end

local env={}

function env.create(op)
   op = op and mkop({},op) or {}
   local h={
      raw=http.create(op),
      -- statuscode set later
   }
   local t={
      "shark",
      "persistent",
      "intf",
      "ipv6",
      "proxy",
      "proxyport",
      "socks",
      "proxyuser",
      "proxypass"
   }
   for _,v in ipairs(t) do op[v]=nil end
   h.op=op
   h.nop=op
   return setmetatable(h, {__index=H})
end

function env.getmetatable()
   return H
end

return env
