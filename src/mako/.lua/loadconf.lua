local function lf(c,fp,cn)
   if fp then
      local x,e=load(fp:read"*a","","bt",c)
      fp:close()
      if x then
	 setmetatable(c,{__index=_G})
	 x,e=pcall(x)
	 setmetatable(c,nil)
      end
      if e then print(cn,e) end
   end
   return c
end
local function lcfg()
   local c,m,cn={},_G.mako,"apps/mako.conf"
   lf(c,ba.openio"vm":open(cn),cn)
   if not c.stop then
      cn=m.cfgfname
      lf(c, cn and ba.openio"disk":open(cn),cn)
   end
   return c
end
local c=lcfg()
c.load=lcfg
return c
