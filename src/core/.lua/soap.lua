--[[
soap.lua : soap stack for the Barracuda web server.

Copyright (C) Real-Time Logic 2009

V 1.0 April 2009
Written by A. Sietsma

--]]


local xml2table =require"xml2table" -- standard parser callback function

local gsub,tconcat,unpack=string.gsub,table.concat,table.unpack
local strformat,strmatch,strchar=string.format,string.match,string.char
local setmetatable = setmetatable
local xparser = xparser
local pairs,ipairs = pairs,ipairs
local type,pcall = type,pcall
local tonumber,tostring=tonumber,tostring
local pairs,rawget=pairs,rawget
local trace=trace

local function tracerr(msg)
   trace(debug and debug.traceback(msg,2) or msg)
end

local _ENV={}


envelope_ns = "http://schemas.xmlsoap.org/soap/envelope/"
encodingStyle = "http://schemas.xmlsoap.org/soap/encoding/"
default_tns = "http://www.barracuda-server.com#lsoap/"

-- generic fault table constructor for soap error
soap_error=function(errmsg,src)

	return {
	  src=src or "Response",
	  detail=errmsg,
					msg= errmsg,
				}
end

-- generic fault table for HTTP error
http_error=function(errmsg,status)
  return { reply="HTTP",status=status or 400,msg= errmsg }
end

do -------------------------- local locals --------------------------------
local entities={["<"]="&lt;",[">"]="&gt;"}--,["'"]="&apos;",["\""]="&quot;"}
local epatt ="([<>])"--'\"])"

encode_text = function(msg)
	return gsub(msg,epatt,entities)
end

local entities={["<"]="&lt;",[">"]="&gt;",["'"]="&apos;",["\""]="&quot;"}
local epatt ="([<>'\"])"--'\"])"

encode_attribute = function(msg)
	return gsub(msg,epatt,entities)
end

local xrepl={["<"]="&lt;",[">"]="&gt;"}
local i
for i=1,31 do xrepl[strchar(i)] = "&#"..i..";" end
local xpatt = "([\001-\031<>])"

encode_string = function(s)
  return gsub(s,xpatt,xrepl)
end
end -------------------------- local locals -------------------------------



local toint = tonumber
local fromint = function(i) return strformat("%d",tonumber(i)) end

local tobool = function(s) return tonumber(s) ~= 0 end
local frombool = function(b) return (b and 1) or 0 end

local todec = tonumber
local fromdec = function(n) return gsub(strformat("%.18f",tonumber(n)),"0+$","") end

local todouble = tonumber
local fromdouble = function(d) return strformat("%.18g",tonumber(d)) end

local tostring = tostring -- string will already have been entity-decoded
local fromstring = encode_string -- xml encode the string


local xs_types = setmetatable({	 -- abbrev,to,from
	string = {"Str",tostring,tostring},
	boolean = {"Bool",tobool,frombool},
	decimal = {"Dec",todec,fromdec},
	integer = {"Int",toint,fromint},
	float = {"Flt",todouble,fromdouble},
	double = {"Dbl",todouble,fromdouble},
	duration = {"Dur",tostring,fromstring},
	dateTime = {"DT",tostring,fromstring},
	time = {"T",tostring,fromstring},
	date = {"D",tostring,fromstring},
	gYearMonth = {"YM",tostring,fromstring},
	gYear = {"YY",tostring,fromstring},
	gMonthDay = {"MD",tostring,fromstring},
	gDay = {"DD",tostring,fromstring},
	gMonth = {"MM",tostring,fromstring},
	hexBinary = {"Hex",tostring,fromstring},
	base64Binary = {"B64",tostring,fromstring},
	anyURI = {"URI",tostring,fromstring},
	QName = {"QN",tostring,fromstring},
	NOTATION = {"NOTE",tostring,fromstring},
	},{__index=function(t,k) return {k,tostring,fromstring} end}) -- default convert




do ----------------------- error handler ----------------------------------

local xml_error_template = [[
<?xml version="1.0" encoding="UTF-8"?>
<soap-env:Envelope
  xmlns:soap-env="http://schemas.xmlsoap.org/soap/envelope/"
  soap-env:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/"
  >
	<soap-env:Header>
		<barracuda:fault xmlns:barracuda="http://www.barracuda-server.com#lsoap">
			%HEADERDETAIL%
		</barracuda:fault>
	</soap-env:Header>
	<soap-env:Body>
		<soap-env:Fault>
			<faultcode>soap-env:%FAULTCODE%</faultcode>
			<faultstring>%FAULTSTRING%</faultstring>
			%FAULTACTORELEMENT%
			%DETAILELEMENT%
		</soap-env:Fault>
	</soap-env:Body>
</soap-env:Envelope>
]]


local faultcodes={Request="Client",Response="Server"}

--========================= PUBLIC ========================================
--parses fault table, returns response code, message, response body
build_error_response=function(fault)

  local status = fault.status or 500
  local msg = fault.detail or fault.msg or "unknown error"
  local reply

  if fault.reply ~= "HTTP" then
    local xdetail = fault.detail or fault.msg
    xdetail = xdetail and "<detail>"..encode_text(xdetail).."</detail>"
    local xactor = fault.actor and "<faultactor>"..encode_text(fault.actor).."</faultactor>"

    local t = {
	["%HEADERDETAIL%"] = xdetail or "",
	["%FAULTCODE%"] = fault.code or faultcodes[fault.source] or "Server",
	["%FAULTSTRING%"]=fault.msg and encode_text(fault.msg) or "",
	["%FAULTACTORELEMENT%"] = xactor or "",
	["%DETAILELEMENT%"]= (fault.pos=="Body") and xdetail or "",
	}
    reply = gsub(xml_error_template,"(%%%u+%%)",t)
  end

  return status, msg, reply
end
end ----------------------- error handler ---------------------------------

















do ------------------ service callback parser -----------------------------

local badfuncerr=function(fn,err)
  return nil, "Bad Handler ("..tostring(fn)..") : "..err
end

local checkparam=function(fn,name,parm)
  if (parm) then
    if type(parm) ~= "table" then
      return badfuncerr(fn,"'"..name.."' parameter is not a table")
    end
    if #parm ==0 then -- single param
	if not parm.name then
	  return badfuncerr(fn,name.." parameter #"..tostring(i).." has no name")
	end
    else
      for i,v1 in ipairs(parm) do
	if type(v1) == "table" then
	  if not v1.name then
	    return badfuncerr(fn,name.." parameter #"..tostring(i).." has no name")
	  end
	end
      end
    end
  end
  return true
end


--========================= PUBLIC ========================================
-- soap rpc function validator.
-- returns table of handlers, or nil, errmsg
check_handlers=function(ops) -- ops is table of operations ie Add

  for k,v in pairs(ops) do

    if type(v) == "table" then
      if not (v.call) then
	return badfuncerr(k,"no 'call' function provided")
      elseif type(v.call)~="function" then
	return badfuncerr(k,"'call' is not a function")
      end

      local ret,err = checkparam(k,"input",v.input)
      if ret then ret,err = checkparam(k,"output",v.output) end
      if not ret then return nil, err end
    end
  end
  return ops
end
end ------------------ service callback parser -----------------------------










do ----------------------- wdsl builder -----------------------------------

local wsdl_head=[[
<?xml version="1.0" encoding="utf-8"?>
<wsdl:definitions
  xmlns:wsdl="http://schemas.xmlsoap.org/wsdl/"
  xmlns:soap="http://schemas.xmlsoap.org/wsdl/soap/"
  xmlns:xs="http://www.w3.org/2001/XMLSchema"
  xmlns:tns="%TNS%"
  targetNamespace="%TNS%"
  >
]]

local wsdl_body=[[
  </wsdl:portType>
  <wsdl:binding name="%NAME%SoapHttpBinding" type="tns:%NAME%Interface">
    <soap:binding style="rpc" transport="http://schemas.xmlsoap.org/soap/http"/>
]]

local wsdl_tail=[[
  </wsdl:binding>
  <wsdl:service name="%NAME%RpcService">
    <wsdl:port name="%NAME%Endpoint" binding="tns:%NAME%SoapHttpBinding">
      <soap:address location="%LOCATION%.rpc"/>
    </wsdl:port>
 </wsdl:service>
</wsdl:definitions>
]]

local portop=[[
<wsdl:operation name="%OPNAME%">
<wsdl:input message="tns:%OPNAME%Request" />
<wsdl:output message="tns:%OPNAME%Response" />
</wsdl:operation>
]]

local literal_bindop= [[
<wsdl:operation name="%OPNAME%">
<soap:operation soapAction="http://www.barracuda-server.com/lsoap/#%OPNAME%"/>
<wsdl:input><soap:body use="literal" /></wsdl:input>
<wsdl:output><soap:body use="literal" /></wsdl:output>
</wsdl:operation>
]]

local encoded_bindop= [[
<wsdl:operation name="%OPNAME%">
<soap:operation soapAction="http://www.barracuda-server.com/lsoap/#%OPNAME%"/>
<wsdl:input><soap:body use="encoded" encodingStyle="http://schemas.xmlsoap.org/soap/encoding/" /></wsdl:input>
<wsdl:output><soap:body use="encoded" encodingStyle="http://schemas.xmlsoap.org/soap/encoding/" /></wsdl:output>
</wsdl:operation>
]]


local function build_part(t,typenames,parm)
  local tn = typenames[parm.type] or "xs:string"
  t[#t+1] = "<wsdl:part name='"..parm.name.."' type='"..tn.."'/>\n"
end

local function build_msg(t,typenames,name,parm,msgtype)
  t[#t+1] = "<wsdl:message name='"..name..msgtype.."'>\n"

  if parm then
    if #parm == 0 then -- single element
      build_part(t,typenames,parm)
    else  -- multiple elements
      for k,v in ipairs(parm) do build_part(t,typenames,v) end
    end
  end

  t[#t+1]="</wsdl:message>\n"
end



local schema_head=[[
<xs:schema targetNamespace="%TNS%" xmlns:tns="%TNS%" >
]]


local function hashtype(typ)
  local xstyp = rawget(xs_types,typ)
  if xstyp then return xstyp[1] end

  local arrayTyp=strmatch(typ,"^(.+)Array$")
  if arrayTyp then return xs_types[arrayTyp][1].."Array" end

  return typ
end

local array_template=[[
<xs:complexType name="%TYPE%Array">
<xs:sequence>
<xs:element name="%TYPE%" type="xs:%TYPE%" minOccurs="0" maxOccurs="unbounded"/>
</xs:sequence>
</xs:complexType>
]]


local function build_simple_type(schema,typenames,typ)
  local tn = typenames[typ]
  if not tn then
    local arrayType=strmatch(typ,"^(.+)Array$")
    if arrayType then
      schema[#schema+1]=gsub(array_template,"(%%%u+%%)",arrayType)
      tn="tns:"..typ
    else -- assume xml schema type
      tn="xs:"..typ
    end
    typenames[typ]=tn
  end
  return tn
end

local function build_complex_type(schema,typenames,type_t)
  local hash = {}
  local t = {false} -- placeholder for <complexType >
  for k,v in ipairs(type_t) do
    local typ,name = v.type,v.name
    if type(typ) ~= "table" then
      local tn = build_simple_type(schema,typenames,typ)
      t[#t+1] = "<xs:element name='"..name.."' type='"..tn.."'/>\n"
      hash[#hash+1] = name..hashtype(typ)
    end
    -- nested type - ignore for now !!
  end
  hash = tconcat(hash,"_")
  typenames[type_t] = "tns:"..hash
  t[1] = "<xs:complexType name='"..hash.."'><xs:sequence>\n"
  t[#t+1] = "</xs:sequence></xs:complexType>\n"
  schema[#schema+1] = tconcat(t)
end

local function build_type(schema,typenames,typ)
  if typ and not typenames[typ] then
    if type(typ) == "table" then -- we're nested !
      build_complex_type(schema,typenames,typ)
    else
      build_simple_type(schema,typenames,typ)
    end
  end
end

-- build schema type and qualified name for single parameter
local function build_paramtype(schema,typenames,parm)
  if parm then
    if #parm == 0 then -- single element
      build_type(schema,typenames,parm.type)
    else  -- multiple elements
      for k,v in ipairs(parm) do build_type(schema,typenames,v.type) end
    end
  end
end


--========================= PUBLIC ========================================
--returns a table of strings containing the wsdl for the given service
-- NOTE : bindop_type should be "literal" (default) for MS Office, or
-- "encoded" for VS2005 c++
--
function build_wsdl_t(service_t,name,uri,tns, bindop_type)

  local subst= {
    ["%NAME%"]=name,
    ["%LOCATION%"]=uri,
    ["%TNS%"]=tns or (default_tns..name)
  }
  local t = {(gsub(wsdl_head,"(%%%u+%%)",subst))}

  local st={} -- service table map
  for k,v in pairs(service_t) do if type(v)=="table" then st[k]=v end end

  local schema,typenames={},{}
  for k,v in pairs(st) do
    build_paramtype(schema,typenames,v.input)
    build_paramtype(schema,typenames,v.output)
  end

  if #schema > 0 then
    t[#t+1] = "<wsdl:types>"
    t[#t+1] = (gsub(schema_head,"(%%%u+%%)",subst))
    for i,v in ipairs(schema) do
      t[#t+1] = v
    end
    t[#t+1] = "</xs:schema></wsdl:types>"
  end
  schema = nil

  for k,v in pairs(st) do
    build_msg(t,typenames,k,v.input,"Request")
    build_msg(t,typenames,k,v.output,"Response")
  end

  t[#t+1] = "<wsdl:portType name='"..name.."Interface'>\n"

  for k,v in pairs(st) do
      subst["%OPNAME%"] = k
      t[#t+1] = (gsub(portop,"(%%%u+%%)",subst))
  end

  t[#t+1] = gsub(wsdl_body,"(%%%u+%%)",subst)

  local bindop = (bindop_type == "encoded") and encoded_bindop or literal_bindop
  for k,v in pairs(st) do
      subst["%OPNAME%"] = k
      t[#t+1] = (gsub(bindop,"(%%%u+%%)",subst))
  end

  t[#t+1] = gsub(wsdl_tail,"(%%%u+%%)",subst)

  return t
end

--========================= PUBLIC ========================================
--returns a string containing the wsdl for the given service
-- see build_wsdl_t for parameters
function build_wsdl(service_t,name,uri,tns, bindop_type)
  return tconcat(build_wsdl_t(service_t,name,uri,tns, bindop_type))
end

end ------------------------ wsdl builder ---------------------------------



















do ---------------------- soap request parser -----------------------------

-- check xml doc is valid soap envelope, and setup soap header & body links
-- returns updated doc on success; nil,fault_t on error
local bind_envelope = function(doc)

  local root = doc.elements[1]
	if root.local_name ~= "Envelope" then
		return nil,{src="Request",doc=doc, msg="Not a SOAP Envelope"}
	end
  doc.soap_envelope=root

	local ns = root.namespace_ref
	if ns and ns ~= envelope_ns then
		return nil,{src="Request",code = "VersionMismatch",
		  doc=doc,msg="version namespace mismatch"}
	end

	if root.encodingStyle ~= nil then
		return nil,{src="Request",doc=doc,msg="encodingStyle illegal in <Envelope>"}
	end

  local kids=root.elements
	if #kids == 0 then
		return nil,{src="Request",doc=doc,msg="No children of <Envelope>"}
	elseif #kids	> 2 then -- could be text nodes!!!
		return {src="Request",doc=doc,msg="Too many children of <Envelope>"}
	elseif (#kids == 2) then
		local hdr = kids[1]
		if hdr.local_name ~= "Header" then
			return nil,{src="Request",doc=doc,node=hdr,msg="bad <Envelope> child #1 (Expecting <Header>, found <"..hdr.local_name..")"}
		elseif hdr.namespace_ref ~= root.namespace_ref then
			return nil,{src="Request",doc=doc,node=hdr,msg="Header namespace mismatch"}
		end
    doc.soap_header=hdr
	end

	local body = kids[#kids]
	if body.local_name ~= "Body" then
		return nil,{src="Request",doc=doc,node=body,msg="bad <Envelope> child #"..#doc.." (Expecting <Body>, found <"..body.local_name..")"}
	elseif body.namespace_ref ~= root.namespace_ref then
		return nil,{src="Request",doc=doc,node=body,msg="Body namespace mismatch"}
	end
  doc.soap_body=body
  return doc
end


-- parse an xml soap request
-- this will return "MORE" or doc or nil,error
local parse_request=function(parser,xmlstr)
  local doc
  local ret,err = parser:parse(xmlstr)
  if (ret == "DONE") then
    doc, err = err, nil
  elseif (ret == true) then
    return "MORE"
  elseif (ret == "ABORT") then
    local context = parser:get_context()
    err= {
	  src= "Request",
	  doc=context and context.doc,
					node=context and context.node,
	  detail=err,
					msg= err or "Invalid SOAP syntax",
				}
  elseif (ret == nil) then
    err=soap_error(err or "XML Syntax error","Request")
 else
    local msg="Internal parser error"
    tracerr(msg)
    err=soap_error(msg,"Response")
 end
  parser:reset()
  if err then return nil,err end
  return bind_envelope(doc)
end


-- event handlers for parser
local soap_cb = {
	PI=function()
		return nil, "PI element not allowed in SOAP request"
	end,

  COMMENT=function() end, -- strip comments !
}
setmetatable(soap_cb,{__index=xml2table})

--========================= PUBLIC ========================================
--returns a new soap parser object
new_parser=function(options)

  local lxp = xparser.create(soap_cb,{soap_options=options},"SKIPBLANK")
  local sp = {
    parse = function(p,...) return parse_request(lxp,...) end,
    destroy = function(p,...) return lxp:destroy() end,
  }
  setmetatable(sp,{__index=lxp})

  return sp
end
end --------------------- soap request parser -----------------------------













do --------------------- soap response builder ----------------------------

------------- XML chunks ------------
local xml_response_head = [[
<?xml version="1.0" encoding="UTF-8" ?>
<soap-env:Envelope
  xmlns:soap-env="http://schemas.xmlsoap.org/soap/envelope/"
  soap-env:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/"
  >
  <soap-env:Body>
]]

local xml_response_tail = [[
  </soap-env:Body>
</soap-env:Envelope>
]]

local reply_error=function(doc,node,msg)
  return {src="Server",pos="Body",doc=doc,node=node,
	msg=msg,
	detail="function '"..node.expanded_name.."' error : "..msg}
end


local function build_simple_output(t,name,typ,reply)

  if reply == nil then return nil,"reply '"..name.."' is nil" end

  local arrayType=strmatch(typ,"^(.+)Array$")
    if arrayType then
      if type(reply) ~= "table" then return nil, "reply '"..name.."' is not table" end
      local cvt = xs_types[arrayTyp][3]
      local t0,t1="<"..arrayType..">","</"..arrayType..">"
      for i=1,#reply do t[#t+1] = t0..cvt(reply[i])..t1 end
    else
      t[#t+1] = xs_types[typ][3](reply)
   end
  return true
end

local function build_table_output(t,name,typ,reply)
  for i,v in ipairs(typ) do
    local typ,name = v.type,v.name
    if type(typ) ~= "table" then
      t[#t+1]="<"..name..">"
      local ret, err = build_simple_output(t,name,typ,reply[name])
      if not ret then return nil, err end
      t[#t+1]="</"..name..">"
    end
    -- nested type - ignore for now !!
  end
  return true
end


local function build_output(t,parm,reply)
  t[#t+1]="<"..parm.name..">"
  local typ=parm.type
  local ret, err = true
  if not typ then -- default to string
    t[#t+1] = tostring(ret[1])
  elseif type(typ)=="table" then
    if type(reply) ~= "table" then return nil, "reply '"..parm.name.."' is not a table" end
    ret, err = build_table_output(t,parm.name,typ,reply)
  else
    ret, err = build_simple_output(t,parm.name,typ,reply)
  end
  t[#t+1]="</"..parm.name..">"
  return ret,err
end


local build_reply_xml=function(doc,node)
  local fn = node.soap_func
  local tagname = node.tag_name
  local xml={"<",tagname,">"}

  local reply = node.soap_reply -- note reply[1] is status
  local output = fn.output
  if output then
    if #output > 0 then -- multi-return
      for i,v in ipairs(output) do
	local ret, err = build_output(xml,v,reply[i+1])
	if not ret then return nil,reply_error(doc,node,err) end
      end
    else
      local ret, err = build_output(xml,output,reply[2])
      if not ret then return nil,reply_error(doc,node,err) end
    end
  end
  xml[#xml+1]="</"..tagname..">\n"
  return tconcat(xml), node.soap_func.lifetime
end

--========================= PUBLIC ========================================
--returns an xml string
build_reply=function(doc)
  local body = doc.soap_body
	local reply = {xml_response_head}
  local life
  local kids = body.elements
  for i,node in ipairs(kids) do -- iterate child nodes
    local ret,err=build_reply_xml(doc,node)
    if not ret then return nil,err end
    reply[#reply+1] = ret
    if err then life = (not life or (err < life)) and err end -- err is lifetime on good ret
  end
  reply[#reply+1] = xml_response_tail
  return tconcat(reply), life
end
end -------------------- soap response builder ----------------------------



do ----------------------- function mapper --------------------------------
-- error helpers
local func_not_found=function(doc,node)
  return {src="Server",pos="Body",doc=doc,node=node,
	msg="function not found",
	detail="function '"..node.expanded_name.."' not found"}
end

local param_not_found=function(doc,node,func,name)
  return {src="Server",pos="Body",doc=doc,node=node,
	msg="parameter not found",
	detail="parameter '"..name.."' not found"}
end

local bad_param_type=function(doc,node,func,name)
  return {src="Server",pos="Body",doc=doc,node=node,
	msg="bad parameter type",
	detail=name and "parameter '"..name.."' invalid type"}
end

local unknown_err=function(doc,node,func,name)
   local msg="internal error"
   local detail=name and "parameter '"..name.."' unrecognised" or "?"
   tracerr(strformat("%s: %s",msg,detail))
  return {src="Server",pos="Body",doc=doc,node=node,msg=msg,detail=detail}
end



local bind_struct_param=function(parm,node)

  local typ,name = parm.type,parm.name

  if not typ then return (node.text or "") end-- default to string
  if type(typ)=="table" then return nil,"nested struct",name end

  local arrayType=strmatch(typ,"^(.+)Array$")
  if arrayType then
    local p={}
    local cvt = xs_types[arrayType][2]
    for k,v in ipairs(node.elements) do
      local txt = cvt(v.text)
      if not txt then return nil,"bad type",name end
      p[#p+1] = txt
    end
    return p
  end

  return xs_types[typ][2](node.text)

end

local bind_struct=function(parm,node)
  local p = {}
  for i,v in ipairs(parm) do
    local el  = node.elements[v.name]
    if not el then return nil,v.name end
    local pp,err,nn = bind_struct_param(v,el)
    if not pp then return nil, err,nn end
    p[#p+1] = pp
    p[v.name]=pp
  end
  return p
end

local bind_param=function(parm,node)

  local typ,name = parm.type,parm.name
  local el = node.elements[name]
  if not el then return nil,"not found", name end

  if not typ then return (el.text or "") end-- default to string
  if type(typ)=="table" then return bind_struct(typ,el) end

  local arrayType=strmatch(typ,"^(.+)Array$")
  if arrayType then
    local p={}
    local cvt = xs_types[arrayType][2]
    for k,v in ipairs(el) do
      local txt = cvt(v.text)
      if not txt then return nil,"bad type",v.name end
      p[#p+1] = txt
    end
    return p
  end
  return xs_types[typ][2](el.text)
end


--========================= PUBLIC ========================================
-- map functions and parameters to soap request doc
-- returns doc, or nil,error_table
bind_funcs=function(doc,funcs)
  local body = doc.soap_body
  for i,node in ipairs(body.elements) do -- iterate child nodes
    local fn=funcs[node.expanded_name]
    if type(fn)~="table" then return nil,func_not_found(doc,node) end
    node.soap_func=fn

    local parm = fn.input
    if parm then
      if #parm > 0 then -- multi values
	local p = {}
	for i,v in ipairs(parm) do
	  local ret, err,nn = bind_param(v,node)
	  if not ret then
	    if err=="not found" then return nil, param_not_found(doc,node,fn,nn) end
	    if err=="bad type" then return nil, bad_param_type(doc,node,fn,nn) end
	    return nil,unknown_err(doc,node,fn,nn)
	  end
	  p[#p+1] = ret
	end
	node.soap_parms=p
      else
	local ret, err,nn = bind_param(parm,node)
	if not ret then
	  if err=="not found" then return nil, param_not_found(doc,node,fn,nn) end
	  if err=="bad type" then return nil, bad_param_type(doc,node,fn,nn) end
	  return nil,unknown_err(doc,node,fn,nn)
	end
	node.soap_parms={ret}
      end
    end
  end
  return doc
end
end ----------------------- function mapper --------------------------------


do ----------------------- function caller --------------------------------

local call_failed=function(doc,node,err)
  return {src="Server",pos="Body",doc=doc,node=node,
	msg="call failed with error '"..err.."'",
	detail="'"..node.tag_name.."' failed with error '"..err.."'"
	}
end

--========================= PUBLIC ========================================
-- call rpc functions, placing results in the request doc
-- returns doc, or nil,error_table
call_funcs=function(doc)
  local body = doc.soap_body
  for i,node in ipairs(body.elements) do -- iterate child nodes
    local parms = node.soap_parms
    local ret
    if (parms) then
      ret = {pcall(node.soap_func.call,unpack(parms))}
    else
      ret = {pcall(node.soap_func.call)}
    end
    if not ret[1] then return nil,call_failed(doc,node,ret[2]) end
    if node.soap_func.output then
      if (ret[2]==nil) and ret[3] then return nil,call_failed(doc,node,tostring(ret[3])) end
    end
    node.soap_reply = ret
  end
  return doc
end
end ---------------------- function caller --------------------------------




do ---------------------- wrapper functions -------------------------------


--========================= PUBLIC ========================================
-- call rpc function(s), given soap doc and table of handlers
-- returns xml reply, or nil,error_table
execute_rpc_request=function(doc,funcs)
  local ret, err = bind_funcs(doc,funcs)
  if ret then ret,err = call_funcs(doc) end
  if ret then ret,err = build_reply(doc) end

  return ret,err
end


--========================= PUBLIC ========================================
-- parse handlers and call rpc function(s), building response
-- data is string or reader
-- returns doc, or nil,error_table
handle_rpc_request=function(data,service_t)

  local parser=new_parser()
  local doc, ret,err

  if type(data) == "string" then
    doc, ret = parser:parse(data)
  else-- assume it's a reader
    xml=""
    local dat; dat, err = data()
    while dat do
      doc, ret = parser:parse(dat)
      if doc ~= "MORE" then break end
      dat, err = data()
    end
  end
  parser:destroy()
  if (not dat) and err then return 400,"Data read error:"..err end
  dat,data = nil,nil

  if doc==nil then err = ret
  elseif doc=="MORE" then
    err= soap_error("Incomplete XML document","Request")
  elseif type(doc)~="table" then
    err= soap_error("broken state","Response")
  else
    ret,err=execute_rpc_request(doc,service_t)
    if ret then return 200,"OK",ret,err end -- err is lifetime on good ret
  end

  return build_error_response(err)
end
end --------------------- wrapper functions -------------------------------


return _ENV -- return module table

