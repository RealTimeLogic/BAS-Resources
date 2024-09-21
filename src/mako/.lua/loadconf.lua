local function loadcfg()
   local conf={}
   if _G.mako.cfgfname then
      local fp=ba.openio"disk":open(_G.mako.cfgfname)
      if fp then
	 local x,e=load(fp:read"*a","","bt",conf)
	 fp:close()
	 if x then
	    setmetatable(conf, {__index=_G})
	    x,e=pcall(x)
	    setmetatable(conf, nil)
	 end
	 if e then print(_G.mako.cfgfname,e) end
      end
   end
   return conf
end
local conf=loadcfg()
conf.load=loadcfg
return conf
