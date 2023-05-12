
local http=require"http"
local fmt=string.format

local function escape(s)
   return string.gsub(s, "([^A-Za-z0-9_])", function(c)
	return string.format("%%%02x", string.byte(c))
     end)
end

-- h=http-client-instance, data=query-tab, op=options-tab
local function sendUrlEncodedData(self, data, op)
   local ok,e1,e2,e3
   op.header = op.header or {}
   op.header["x-requested-with"]="XMLHttpRequest"
   if op.method == "POST" then
      op.header["Content-Type"]="application/x-www-form-urlencoded"
      local t={}
      local insert=table.insert
      for k,v in pairs(data) do
	 insert(t, fmt("%s=%s",escape(k),escape(v)))
      end
      data=table.concat(t, "&")
      op.size=#data -- Content-Length
      ok,e1,e2,e3=self:request(op)
      if ok then ok,e1,e2,e3 = self:write(data) end
   else
      op.method = "GET"
      op.query=self:mkop(op.query,data)
      ok,e1,e2,e3=self:request(op)
   end
   if ok then
      local s
      s,e1,e2,e3 = self:status()
      if s then
	 data,e1,e2,e3 = self:read"*a"
	 if data then
	    return s,data
	 end
      end
   end
   return nil,e1,e2,e3
end


local H=setmetatable({},{__index=http.getmetatable()})

function H:post(url,tab,op)
   self.op.query=nil
   op=self:mkop(self:mkop({method="POST"},op))
   op.url=url
   return sendUrlEncodedData(self, tab, op)
end

function H:json(url,tab,op)
   self.op.query=nil
   op=self:mkop(self:mkop({method="GET"},op))
   op.url=url
   local status,e1,e2,e3=sendUrlEncodedData(self, tab, op)
   if status == 200 then
      if #e1 > 0 then
	 tab,e2=ba.json.decode(e1,op.jnull and true or false) -- e1 is data
	 if tab then return tab end
	 return nil, "json", e2
      end
      return nil,"invalidresponse", "Response empty"
   end
   return nil,e1,e2,e3
end


local function mkstat(self)
   local h={}
   for k,v in pairs(self:header()) do h[k:lower()]=v end
   local r={}
   local x = h["last-modified"]
   if not x then x = h["expires"] end
   r.mtime = x and ba.parsedate(x)
   x = h["content-length"]
   r.size = x and tonumber(x)
   return r
end

function H:stat(url ,op)
   self.op.query=nil
   op=self:mkop(self:mkop({method="HEAD"},op))
   op.url=url
   local ok,e1,e2,e3=self:request(op)
   if ok then
      local s
      s,e1,e2,e3=self:status()
      if s == 200 then return mkstat(self) end
      if s then return nil,s end
   end
   return nil,e1,e2,e3
end


local function checkAttr(attr, msg, level)
   if not attr then error ("Required attribute: "..msg, level or 4) end
end

-- Upload Download Config
local function udconf(self,conf,op,method,doUpload)
   local ok,func,st,size,fp,e1,e2,e3
   self.op.query=nil
   op=self:mkop(self:mkop({method=method, url=conf.url},op))
   checkAttr(op.url, "URL")
   if conf.io and conf.name then
      if doUpload then
	 st,e1,e2,e3 = conf.io:stat(conf.name)
	 if st then
	    size=st.size
	    fp,e1,e2,e3 = conf.io:open(conf.name)
	 end
      else
	 fp,e1,e2,e3 = conf.io:open(conf.name,"w")
      end
      if not fp then return nil,e1,e2,e3 end
   else
      checkAttr(conf.fp, "(io and name) or fp")
      fp=conf.fp
   end
   func = conf.func or function() end
   op.size = size or conf.size or op.size -- Only used if uploading
   ok,e1,e2,e3=self:request(op)
   if ok then return true,fp,func,size end
   return nil,e1,e2,e3
end


function H:upload(conf,op)
   local data,e1,e2,e3
   local upsize=0
   local ok,fp,func,size=udconf(self,conf,op,"PUT",true)
   if not ok then return nil,fp,func,size end
   if not size and conf.size then size=conf.size end
   while true do
      data,e1,e2,e3 = fp:read(1024)
      if not data then break end
      upsize = upsize+#data
      data,e1,e2,e3 = self:write(data)
      if e1 then break end
      func(size,upsize)
   end
   fp:close()
   if e1 then return nil,e1,e2,e3 end
   return true
end


function H:download(conf,op)
   local data,e1,e2,e3
   local rsize=0
   local ok,fp,func=udconf(self,conf,op,"GET",false)
   if not ok then return nil,fp,func,size end
   ok,e1,e2,e3=self:status()
   if ok ~= 200 then
      if ok then return nil, ok end
      return nil,e1,e2,e3
   end
   local size = mkstat(self).size
   while true do
      data,e1,e2,e3 = self:read(1024)
      if e1 or not data or #data == 0 then break end
      ok,e1,e2,e3 = fp:write(data)
      if e1 then break end
      rsize = rsize+#data
      func(size,rsize)
   end
   fp:close()
   if e1 then return nil,e1,e2,e3 end
   return true
end


local env={}
function env.create(op)
   local h=http.create(op)
   return setmetatable(h, {__index=H})
end

return env
