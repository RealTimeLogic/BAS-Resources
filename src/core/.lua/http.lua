
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



-- Compare origins without changing the caller's URL or header table.
local function origin(url)
   local scheme,host=url:lower():match("^(https?)://([^/%?#]+)")
   if not scheme or host:find("@",1,true) then return nil end
   local name,port=host:match("^(.-):(%d+)$")
   if name then host=name;port=tonumber(port) end
   return scheme.."://"..host..":"..(port or (scheme=="https" and 443 or 80))
end

-- Resolve an HTTP Location against the current URL (RFC 3986 section 5.2).
local function resolve(base,ref)
   ref=ref:match("^[^#]*")
   base=base:match("^[^#]*")
   local scheme,host,path=base:match("^([%a][%w+.-]*:)//([^/?]+)(.*)")
   if not scheme then return nil end
   local bp,bq=path:match("^([^?]*)(.*)")
   local rs=ref:match("^([%a][%w+.-]*:)")
   if rs then
      if rs:lower()~="http:" and rs:lower()~="https:" then return nil end
      scheme=rs:lower();ref=ref:sub(#rs+1)
      if ref:sub(1,2)~="//" then return nil end
   end
   if ref:sub(1,2)=="//" then
      host,ref=ref:match("^//([^/?]+)(.*)")
      if not host then return nil end
   elseif not rs then
      if ref=="" then return scheme.."//"..host..bp..bq,true end
      if ref:sub(1,1)=="?" then return scheme.."//"..host..bp..ref end
      if ref:sub(1,1)~="/" then ref=(bp:match("^(.*/)") or "/")..ref end
   end
   path,bq=ref:match("^([^?]*)(.*)")
   -- Remove dot segments without collapsing empty or escaped segments.
   local out=""
   while path~="" do
      if path:sub(1,3)=="../" then path=path:sub(4)
      elseif path:sub(1,2)=="./" then path=path:sub(3)
      elseif path:sub(1,3)=="/./" or path=="/." then path="/"..path:sub(4)
      elseif path:sub(1,4)=="/../" or path=="/.." then
         path="/"..path:sub(5);out=out:gsub("/?[^/]*$","")
      elseif path=="." or path==".." then path=""
      else
         local part=path:match("^/?[^/]*")
         out=out..part;path=path:sub(#part+1)
      end
   end
   return scheme.."//"..host..(out=="" and "/" or out)..bq
end

local function requesturl(op)
   local url=op.url
   if op.query then
      local q={}
      for k,v in pairs(op.query) do
         local key,err=ba.urlencode(tostring(k))
         if not key then return nil,err end
         for _,value in pairs(type(v)=="table" and v or {v}) do
            local encoded,err=ba.urlencode(tostring(value))
            if not encoded then return nil,err end
            q[#q+1]=key.."="..encoded
         end
      end
      if #q>0 then url=url.."?"..table.concat(q,"&") end
   end
   return url
end

-- Process supported HTTP redirects.
local function checkStatus(self)
   local raw=self.raw
   if not self.statuscode then
      local s,e1,e2,e3,ok=raw:status()
      if not s then return nil,e1,e2,e3 end
      if s == 301 or s == 302 or s == 303 or s == 307 or s == 308 then
	 local r=0
	 local op=mkop({},self.nop)
	 self.nop=op
	 local method = op.method or "GET"
         local currentURL,err=requesturl(op)
         if not currentURL then return nil,err end
	 while s == 301 or s == 302 or s == 303 or s == 307 or s == 308 do
	    ok,e1,e2,e3=raw:read(0) -- Discard response
	    if not ok then return nil,e1,e2,e3 end
	    r=r+1
	    if r == 10 then return nil, "redirect" end
	    local url=raw:header"location"
	    if not url then
	       return nil, "invalidresponse"
	    end
	    local previousOrigin=origin(op.url)
            local inherited
            currentURL,inherited=resolve(currentURL,url)
            if not currentURL then return nil,"invalidresponse" end
            local u,q=currentURL:match("^([^?]*)%?(.*)$")
            op.url=u or currentURL
            local query=inherited and op.query or nil
            if q and not query then
               local err
               query,err=http.parsequery(q)
               if not query then return nil,err=="invalidquery" and "invalidresponse" or err end
            end
            op.query=query
	    if not previousOrigin or previousOrigin ~= origin(op.url) then
	       op.user,op.password=nil,nil
	       if op.header then
	          op.header=mkop({},op.header)
	          for k in pairs(op.header) do
	             local name=tostring(k):lower()
	             if name=="authorization" or name=="cookie" then op.header[k]=nil end
	          end
	       end
	    end
	    if ((301 == s or 302 == s) and ("PUT" == method or "POST" == method)) or
	       ((307 == s or 308 == s) and method ~= "GET" and method ~= "HEAD") then
	       return nil,s,currentURL
	    end
	    method = (method == "HEAD" or s == 307 or s == 308) and method or "GET"
	    op.method = method
	    ok,e1,e2,e3=raw:request(op)
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
function H:header(name) return self.raw:header(name) end
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
function H:status()
   local ok,e1,e2,e3=checkStatus(self)
   if ok then return self.statuscode end
   return nil,e1,e2,e3
end

function H:close()
   local ok,e1,e2,e3=checkStatus(self)
   local closed,c1,c2,c3=self.raw:close()
   if not ok then return nil,e1,e2,e3 end
   return closed,c1,c2,c3
end

function H:request(op)
   self.statuscode=nil
   local sop=self.op
   local nop=mkop(sop,op)
   if type(nop.url)=="string" then
      local url=nop.url:match("^[^#]*")
      local path,query=url:match("^([^?]*)%?(.*)$")
      if path or url~=nop.url then
         nop=mkop({},nop)
         nop.url=path or url
         if query then
            local parsed,err=http.parsequery(query)
            if not parsed then
               if err=="invalidquery" then error("invalid URL query",2) end
               return nil,err
            end
            nop.query=mkop(parsed,nop.query)
         end
      end
   end
   self.nop=nop
   return self.raw:request(nop)
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
   local raw,err=http.create(op)
   if not raw then return nil,err end
   local h={
      raw=raw,
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
