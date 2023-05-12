--[[
    xml2table.lua : callback table for xparser (xml parser)

    constructs Lua table from event callbacks

    V 3.0 April 2009
    Written by A. Sietsma

    Copyright(C) 2007-2009 Adrian Sietsma
    <adrian@sietsma.com>

    A non-exclusive license is hereby granted to Real Time Logic to use
    this software module on the condition that this source code is not
    modified without the express permission of Adrian Sietsma.

    Redistribution and use in source and binary forms, with or without
    modification, is permitted only with express written consent of
    Adrian Sietsma. Unauthorized use is prohibited.
--]]

local gsub = string.gsub
local strfind, strsub = string.find, string.sub
local strmatch, strrep = string.match, string.rep
local strlen,strformat = string.len,string.format
local tconcat = table.concat
local getmetatable,setmetatable = getmetatable,setmetatable
local tostring,pairs,next,type=tostring,pairs,next,type
local rawget=rawget


 -- function to remove leading and trailing whitespace
local trim_spaces = function(s)
  return strmatch(s,"^%s*(.-)%s*$")
end

local reset_context=function(context)
  context.namespace_t={["@default"]=nil}
  context.namestack={} -- namespace stack
  context.stack={} -- node stack
  context.doc={}  -- document holder
  context.node=context.doc  -- current node
  return context  -- for convenience
end

local destroy_context=function(context)
  context.namespace_t=nil
  context.namestack=nil -- namespace stack
  context.stack=nil -- node stack
  context.doc=nil  -- document holder
  context.node=nil  -- current node
end


-------------------- VISIBLE FROM HERE DOWN -----

local _ENV={}

INIT=function(context,...)
--  print("INIT: context=",context,type(context))
  return reset_context(context or {})
end

RESET=function(context,...)
--  print("RESET: context=",context)
  reset_context(context)
end

TERM=function(context,...)
--  print("TERM: context=",context)
  destroy_context(context)
end
--[[
START=function(context)
--  print("START: context=",context)
end
--]]


--- EVENT HANDLERS

XML=function(context,attribs)
--  print("xml Declaration: ctx,attrs=",context,attribs)
  context.doc.xml=attribs or {}
end

local invalid_ns = {["xml"]=true,["xmlns"]=true}

START_ELEMENT=function(_ENV,tagname,attribs)
--  print("Start Element: ctx=",context,tagname,attribs)
  -- look for namespace declarations, and add them to our table
  local new_ns
  attribs = attribs or {}
  for k,v in pairs(attribs) do -- look for xmlns:x
    local ix1,ix2,ns
    if k=="xmlns" then	-- default namespace
      ns = "@default"
    else
      ix1,ix2,ns = strfind(k,"^xmlns:(.+)$" )
      -- ns CANNOT be 'xmlns' or 'xml'
      if ns and invalid_ns[ns] then return "ERROR","Illegal namespace ("..ns..")" end
    end
    if ns then
      -- paranoia would check ns to be a valid IRI reference
      if not new_ns then
	new_ns={[ns]=v}
	namespace_t = setmetatable(new_ns,{__index=namespace_t})
      else
	namespace_t[ns]=v
      end
    end -- if ns
  end -- for

  -- now we check attributes for valid namespace prefix,
  -- and build a namespace-expanded metatable
  local a1
  for k,v in pairs(attribs) do
    local ix1,ix2,ns,attr = strfind(k,"^([^:]+):(.+)$")
    if ns then
      if strfind(attr,":",1,true) then -- only one colon allowed in a name
	return "ERROR","Illegal attribute name ("..k..")"
      end
      if ns ~= "xmlns" then
	local nsref = namespace_t[ns]
	-- namespace must be in scope
	if not nsref then return "ERROR", "Unknown attribute namespace ("..ns..")"  end
	a1 = a1 or {}
	a1[nsref.."^"..k] = v -- note the '^' will NOT appear in any attrib name
	a1[attr] = v -- store the ns-stripped attrib name
      end
    end -- if ns
  end -- for
  if a1 then setmetatable(attribs,{__index=a1})	 end

  -- check tag namespace
  local ns_ref
  local ix1,ix2,ns,tag = strfind(tagname,"^([^:]+):(.+)$")
  if ns then
    -- only one colon allowed in a name
    if strfind(tag,":",1,true ) then return "ERROR","Illegal tag name ("..tag..")" end
    if not namespace_t then return "ERROR", "namespace" end
    ns_ref = namespace_t[ns]
    if not ns_ref then return "ERROR", "Unknown tag namespace ("..ns..")" end
  end

  local ns_ref1 = ns_ref or namespace_t["@default"]
  local fullname = (ns_ref1 and tag and ns_ref1.."^"..tag) or tagname

  -- add to node stack
  local newnode = { type="element",
		    --parent=node,
		    tag_name=tagname,	   --tagName
		    local_name=tag or tagname, --localName
		    namespace_prefix=ns,
		    namespace_ref=ns_ref,  --namespaceURI
		    expanded_name=fullname,
		    attributes = attribs,
		    namespaces=namespace_t,
		    sequence=#node,
		    }
  node[#node+1]=newnode

  local el = node.elements
  if el then
    el[#el+1] = newnode
    el[tagname] = el[tagname] or newnode  -- point to first occurence
    if (fullname ~= tagname) then el[fullname] = el[fullname] or newnode end -- point to first occurence
  else
    node.elements = {newnode,[tagname]=newnode,[fullname]=newnode}
  end

  stack[#stack+1]=node --  push(stack,node)
  if new_ns then namestack[#namestack+1] = node end
  node = newnode
end

END_ELEMENT=function(_ENV,tagname)
--  print("End Element: ctx=",context,tagname)

  node.text = node.text and tconcat(node.text," ")

  if namestack[#namestack] == node then
    namespace_t = rawget(getmetatable(namespace_t),__index) --pop namespaces
    namestack[#namestack] = nil
  end
  node,stack[#stack] = stack[#stack],nil --  node = pop(stack)
  if #stack == 0 then return "DONE",_ENV.doc end
end

EMPTY_ELEMENT=function(context,tagname,attrs)
----  print("Empty Element: ctx=",context,tagname)
  local ret,err,x=START_ELEMENT(context,tagname,attrs)
  if ret then return ret,err,x end
  return END_ELEMENT(context,tagname)
end

TEXT=function(context,text)
--  print("Add Text: ctx=",context,"'"..text.."'")
  if (#text == 0) then return end
  local node = context.node
  local textnode = node.text
  if (textnode) then
    textnode[#textnode+1]=text
  else
    node.text = {text}
  end
  node[#node+1]={type="TEXT",value=text}
end

CDATA=function(context,str)
--  print("Add CDATA: ctx=",context,"'"..str.."'")
  local node = context.node
  node[#node+1]={type="CDATA",value=str}
end

COMMENT=function(context,str)
--  print("Add Comment: ctx=",context,text)
  local node = context.node
  node[#node+1]={type="COMMENT",value=str}
end

PI=function(context,name,value)
--  print("Add PI: ctx=",context,name,"'"..value.."'")
  local node = context.node
  node[#node+1]={type="PI",target=name,value=value}
end

return _ENV -- return module table


