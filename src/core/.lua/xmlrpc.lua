--[[

xmlrpc.lua: XML-RPC stack
Copyright (C) Real-Time Logic 2010 - 2012
$Id$

The Lua XML-RPC implementation replaces the original C implementation.
--]]


local fmt,strmatch,sfind = string.format, string.match,string.find
local gsub, strchar = string.gsub, string.char
local tconcat, tinsert = table.concat, table.insert

local assert,error,type,pairs,ipairs,next,pcall,setmetatable =
      assert,error,type,pairs,ipairs,next,pcall,setmetatable

local unpack,deflate,b64decode=table.unpack,ba.deflate,ba.b64decode
local baloadfile = ba.loadfile

local encIso8601 = ba.xmlrpc.iso8601
local encBase64 = ba.xmlrpc.base64
ba.xmlrpc=nil

local trace=trace
local tonumber=tonumber

local mfloor = math and math.floor or nil

local xparser =require"xparser"	    -- xml parser engine
local xml2table =require"xml2table" -- standard parser callback function
local G=_G

local _ENV={}

-- Make C bindings available in the xmlrpc package
iso8601=encIso8601
base64=encBase64 


local function doError(msg)
   trace("XML-RPC",msg)
   error(msg,0)
end

local function checkArg(arg, expected, msg)
   if type(arg) == expected then
      return
   end
   doError(fmt("%s expected a %s, not a %s.",msg or "",expected,type(arg)),3)
end


local decodeParams
do -- Param decoding
   local function getVal(v)
      if v.type == "CDATA" then return v.value end
      if v.text then return v.text end
      if v[1] then
	 v=v[1]
	 if v.value then return v.value end
      end
      return ""
   end
   local xparam
   local function xstruct(v)
      local t = {}
      for k,v in ipairs(v) do
	 local el=v.elements
	 t[getVal(el.name)]=xparam(el.value)
      end
      return t
   end
   local function xarray(v)
      local t={}
      for k,v in ipairs(v.elements.data) do
	 tinsert(t, xparam(v))
      end
      return t
   end

   local function xnumber(v) return tonumber(getVal(v)) end
   local xfuncs = {
      base64 = function(v) return b64decode(getVal(v)) end,
      boolean = function(v)
	 v=getVal(v)
	 return (v == "true" or	 v == "1") and true or false
      end,
      ["dateTime.iso8601"] = function(v)
	 v=getVal(v)
	 local t=encIso8601(v,true)
	 return t and t or v
      end,
      double = xnumber, i4 = xnumber, int = xnumber,
      ["nil"] = function(v) return false end,
      string = function(v) return getVal(v) or "" end,
      struct=xstruct,
      array=xarray
   }
   xfuncs.value=xfuncs.string

   xparam = function(v)
      val=v.value and (v.value[1].tag_name and v.value[1] or v.value) or v[1] -- Val optional for strings
      if val.tag_name then
	 return xfuncs[val.tag_name](val)
      end
      return xfuncs[v.tag_name](v)
   end

   decodeParams = function(doc)
      local args={}
      local mCallEl = doc.elements.methodCall.elements
      local methodName=getVal(mCallEl.methodName)
      for k,v in ipairs(mCallEl.params) do
	 tinsert(args, xparam(v.elements))
      end
      local ok, _, intf, method = sfind(methodName, "^([^.]+)%.(.+)$")
      if not intf or not method then
	 doError(fmt("Invalid method name: %s",methodName))
      end
      return intf, method, args
   end
end -- Param decoding


local encodeResp
do  -- Response encoding
   local encodeX
   local encodeNum
   local encodeString

   if mfloor then
      encodeNum = function(x)
	 if x > 0xFFFF or x ~= mfloor(x) then
	    return fmt("<double>%f</double>",x)
	 end
	 return fmt("<i4>%d</i4>",x)
      end
   else
      encodeNum = function(x) return fmt("<i4>%d</i4>",x) end
   end

   do
      local xrepl={["<"]="&lt;",[">"]="&gt;",["&"]="&amp;"}
      local i
      for i=1,31 do xrepl[strchar(i)] = "&#"..i..";" end
      local xpatt = "([\001-\031<>&])"
      encodeString = function(s)
	 if sfind(s,xpatt) then
	    return fmt("<string><![CDATA[%s]]></string>",s)
	 end
	 return fmt("<string>%s</string>",s)
	 --return fmt("<string>%s</string>",gsub(s,xpatt,xrepl))
      end
   end

   local function tabIsArray(t)
      for k,v in pairs(t) do
	 if type(k) ~= "number" then return false end
      end
      return true
   end

   local function doTypeErr(x)
      doError(fmt("%s is not a valid XML-RPC type", type(x)))
   end

   local encodeT={
      ["number"] = encodeNum,
      ["string"] = encodeString,
      ["boolean"] = function(x)
	 return fmt("<boolean>%s</boolean>", x and "1" or "0")
      end,
      ["table"] = function(x,rt)
	 if rt[x] then return "<nil/>" end -- Ignore recursive tabs
	 rt[x]=true
	 local t={}
	 if tabIsArray(x) then
	    tinsert(t,"<array><data>")
	    for k,v in ipairs(x) do
	       tinsert(t,encodeX(v,rt))
	    end
	    tinsert(t,"</data></array>")
	 else
	    tinsert(t,"<struct>")
	    for k,v in pairs(x) do
	       tinsert(t,fmt("<member><name>%s</name>%s</member>",
			     k,encodeX(v,rt)))
	    end
	    tinsert(t,"</struct>")
	 end
	 return tconcat(t)
      end,
      ["function"] = function(x)
	 local ok, xml, stat = pcall(x)
	 -- If xmlrpc.base64 or xmlrpc.iso8601 userdata
	 if stat == "XMLRPC" then return xml end
	 doTypeErr(x)
      end,
   }

   encodeX = function(x,rt)
      local f=encodeT[type(x)]
      if f then return fmt("<value>%s</value>",f(x,rt)) end
      doTypeErr(x)
   end

   encodeResp=function(data)
      local rt={}
      return fmt('%s%s%s',
		 '<?xml version="1.0"?><methodResponse><params><param>',
		 encodeX(data,rt),
		 '</param></params></methodResponse>')
   end
end -- Response encoding


local function read(request)
   local lxp = xparser.create(xml2table,{},"SKIPBLANK")
   local f = request:rawrdr()
   local doc,ret,err
   for a in f do -- default read size is LUAL_BUFFERSIZE (512 ?)
      if not doc then
	 ret,err = lxp:parse(a)
	 if (ret == "DONE") then
	    doc=err
	 elseif (ret ~= true) then
	    doError(fmt("XML syntax error: %s",err))
	 end
      end
   end
   lxp:destroy()
   if not doc then doError"Premature end of XML" end
   return doc
end

local metat = { __index = {} }

-- execute the RPC call
function metat.__index:execute(request, response)
   assert(request)
   assert(response)
   self.request=request
   self.response=response
   local ok, doc = pcall(read, request)
   if ok then
      local ok, intfn, methn, args = pcall(decodeParams,doc)
      --trace(ok, intfn, methn)
      doc=nil
      if ok then
	 -- Lookup interface object
	 local intf = intfn and self.intf[intfn] or self.intf
	 local method
	 if intf then
	    method = intf[methn] -- Lookup method
	 end
	 if method then
	    local result,errno,emsg
	    -- execute method
	    ok,result,errno,emsg = pcall(method, unpack(args))
	    if ok and result ~= nil then -- Send response
	       self:sendResp(result)
	    elseif ok then
	       if type(errno) == "number" then
		  self:sendError(errno,emsg) 
	       else
		  self:sendError(0,fmt("No response from %s",methn))
	       end
	    else
	       self:sendError(0, fmt("%s: %s",methn,result))
	    end
	 else
	    local found=true
	    if intfn == "system" then
	       if methn == "listMethods" then
		  self:doSystemDescribe()
	       elseif methn == "methodSignature" then
		  self:sendResp("undef") -- Not implemented
	       elseif methn == "methodHelp" then
		  self:sendResp("") -- Not implemented
	       else
		  found=false
	       end
	    else
	       found=false
	    end
	    if not found then
	       methn=fmt("%s.%s",intfn,methn)
	       local msg=fmt("Cannot find method: %s", methn)
	       self:sendError(0,msg)
	    end
	 end
      else
	 self.response:setstatus(200)
	 local msg=fmt("Semanantic error %s",intfn)
	 self:sendError(0, msg)
      end
   else
      self.response:setstatus(200)
      local msg="Read error: "..doc -- doc is now error val
      self:sendError(0, msg)
   end
end

function metat.__index:doSystemDescribe()
   assert(self.request)
   local procs={"system.listMethods"}
   for intfn, intf in pairs(self.intf) do
      if type(intf) == "function" then
	 tinsert(procs, fmt("%s",intfn))
      else
	 for methn,_ in pairs(intf) do
	    tinsert(procs, fmt("%s.%s",intfn,methn))
	 end
      end
   end
   self:sendResp(procs)
end

local function sendResp(req,resp,d)
   resp:reset()
   if #d > 1400 then
      local ae = req:header("Accept-Encoding")
      if ae and ae:find("deflate") then
	 resp:setheader("Content-Encoding", "deflate")
	 d=deflate(d)
      end
   end
   resp:setcontenttype("text/xml")
   resp:setheader("Cache-Control", "no-store, no-cache, must-revalidate")
   resp:setheader("Content-Length",#d) 
   resp:send(d)
end

function metat.__index:sendError(err, msg)
   local fmtFault=[[<?xml version="1.0"?><methodResponse><fault><value><struct><member><name>faultCode</name><value><int>%d</int></value></member><member><name>faultString</name><value><string>%s</string></value></member></struct></value></fault></methodResponse>]]
   if not msg then
      msg="(unknown)"
   end
   trace("XML-RPC",msg)
   sendResp(self.request,self.response,fmt(fmtFault,err,msg))
end

function metat.__index:sendResp(obj)
   sendResp(self.request,self.response,encodeResp(obj))
end

-- create a new XML-RPC object.
--param name: The XML-RPC name for this service
--param intf is one of:
--   1
--     A table containing the interfaces (objects).
--     each object contains a table with the object methods
--   2
--     A table with methods.
new = function(name, intf)
   -- Loop through all RPC interfaces and verify the content
   function checkIntf(i,n)
      local funcCnt=0
      for _,f in next,i do
	 checkArg(f, "function", n and (n..": ") or "")
	 funcCnt=funcCnt+1
      end
      assert(funcCnt ~= 0, fmt("Table '%s' is empty",n and n or ""))
   end
   checkArg(intf, "table", "Argument: ")
   local intfCnt=0
   for n,i in pairs(intf) do
      intfCnt=intfCnt+1
      if type(i) == "function" then
	 checkIntf(intf)
	 intfCnt=1
	 break
      end
      checkArg(i, "table", n..": ")
      checkIntf(i, n)
   end
   assert(intfCnt ~= 0, "Interface table is empty")
   return setmetatable({intf=intf, name=name}, metat)
end

return _ENV
