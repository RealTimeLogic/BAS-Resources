--[[
basoap.lua : soap integration for the Barracuda web server.
Copyright (C) Real-Time Logic 2009
--]]

local soap=require"soap"
local strmatch,strlower=string.match,string.lower

local function load_config_file(fname)
  local io=ba.openio("vm")
  local fnsource,err=io:loadfile(fname)
  if not fnsource then error("failed to load soap services : "..err) end
  return fnsource
end

local function load_config(context,env)
  local fnenv=setmetatable({soap_shared=context.userspace,print=trace,response=false},{__index=env})
  local ret,err=pcall(context.serviceloader(fnenv))
  if not ret then return nil,"failed to parse soap config :"..(err or "unspecified error") end
  local services=fnenv.soap_services
  if (not services) or (type(services)~="table") then return nil,context.config.." defines no soap services" end
  return services
end

-- only used for wsdl !
local function sendwsdl_t(context,response,status,body)
  response:setcontenttype("text/xml; charset=\"utf-8\"")
  local lifetime=context.wsdl_life or 300 -- 5 minutes
  local deathtime= os.time()+lifetime
  response:setmaxage(lifetime)
  response:setdateheader("Expires",deathtime)
  response:setdateheader("Last-Modified",context.starttime)
  response:setheader("Age",0)
  response:setstatus(status)
  for i,s in ipairs(body) do response:write(s) end
  return true
end

local function sendxml(context,response,status,body,lifetime)
  response:setcontenttype("text/xml; charset=\"utf-8\"")
  local ctxlife=context.rpc_life
  if ctxlife and (not lifetime or (ctxlife<lifetime)) then
    lifetime=ctxlife
  else
    lifetime=lifetime or 5 -- seconds default
  end
  local deathtime= os.time()+lifetime
  response:setmaxage(lifetime)
  response:setdateheader("Expires",deathtime)
  response:setdateheader("Last-Modified",os.time())
  response:setheader("Age",0)
  response:setstatus(status)
  response:write(body)
  return true
end

local function senderror(response,status,err)
    trace("SOAP ERROR",err)
    response:senderror(status,err)
    return
end

local function soaploader(dirname,serviceloader,wsdl_life,rpc_life)

  local context={serviceloader=serviceloader,
		  cache=setmetatable({},{__mode="v"}),
		  userspace={},
		  starttime=os.time(),
		  wsdl_life=wsdl_life,
		  rpc_life=rpc_life,
		  }

  return function(_ENV,rel)

    if rel=="" then return false end

    local svcname,ext=strmatch(rel,"^(.+)%.([^%.]+)$")
    svcname,ext=(svcname or rel),(ext or "wsdl")
    local lcname=strlower(svcname)

    if ext == "rpc" then
      if not request:allow{"PUT","POST"} then return false end
      lcname=strlower(rel)
    elseif ext == "wsdl" then
      if not request:allow{"GET"} then return false end
      request:checktime(context.starttime) -- returns 304 on "If-Modified-Since"
      local cached =context.cache[lcname]
      if cached then return sendwsdl_t(context,response,200,cached) end
    else
      return false
    end


    local config,err=load_config(context,_ENV)
    if not config then return senderror(response,500,err) end

    -- config is table of services
    local handler,hname
    repeat -- one-time loop for ease of breaking
      hname,handler=svcname,rawget(config,svcname)
      if handler then break end
      hname,handler=lcname,rawget(config,lcname)
      if handler then break end
      for n,h in pairs(config) do
	if lcname == strlower(n) then
	  hname,handler=n,h
	  break
	end
      end
      if not handler then return false end
    until true
    if type(handler) ~= "table" then return senderror(response,500,rel.."is not a soap operation") end

    -- here handler points to a service handler node in config
    -- time to load soap
    print=trace -- stop print statements in library from corrupting the output
    require"soap"
    soap.default_tns="http://www.barracuda-server.com/lsoap/default/"

    local ret,err=soap.check_handlers(handler)
    if not ret then return senderror(response,500,"error in soap config :"..err) end

    if ext == "wsdl" then
      local baseref=strmatch(request:url(),"^(.+)%/[^%/]+$")
      if not baseref then return false end -- should never happen!
      local ret,err=soap.build_wsdl_t(handler,hname,baseref.."/"..hname)
      if not ret then return senderror(response,500,"error in soap config :"..err) end
      context.cache[lcname]=ret
      return sendwsdl_t(context,response,200,ret)
    end
    -- rpc from here
--[[ -- to dump the request
    local xml=""
    local rdr=request:rawrdr()
    local dat,err=rdr()
    while dat do
      xml=xml..dat
      dat,err=rdr()
    end
    trace("---------- REQUEST ----------")
    trace(xml)
    trace("-----------------------------")

    local status,msg,body,life=soap.handle_rpc_request(xml,handler)
--]]
--[[ --to debug the soap stack
    local x,status, msg, body,life=pcall(soap.handle_rpc_request,request:rawrdr(),handler)
    trace ("rpc returned",x,status, msg, body)
--]]

    local status,msg,body,life=soap.handle_rpc_request(request:rawrdr(),handler)
    if status ~= 200 then
      life=0
      trace("SOAP ERROR",msg)
      if not body then
	response.senderror(response,status,msg)
	return false
      end
    end
    return sendxml(context,response,status,body,life)
  end,context -- returns dirfn,context
end


ba.create.soapdir=function (dirname,serviceloader,wsdl_life,rpc_life)
  if type(dirname) ~= "string" then error("Directory name is not a string") end
  if type(serviceloader) == "string" then
    serviceloader=load_config_file(serviceloader) -- throws an error on failure
  elseif type(serviceloader) ~= "function" then
    error("service loader is not a function")
  end
  local dirfn,ctx=soaploader(dirname,serviceloader,wsdl_life,rpc_life)
  local dir=ba.create.dir(dirname)
  dir:setfunc(dirfn)
  return dir,ctx
end
