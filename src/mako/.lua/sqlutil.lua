
-- A few useful SQL functions

local type,unpack,fmt,coroutine=type,table.unpack,string.format,coroutine

local sqlite = luasql.sqlite
local dio=ba.openio"disk"
local _G=_G

local _ENV={}

local dbdir
local dos2unix

local function n2dbn(name)
   if not dbdir then _G.error("No DB base dir",3) end
   return fmt("%s%s%s",dbdir,name,".sqlite.db")
end

local function close(env,conn)
   conn:close()
   env:close()
end


local function select(conn,sql,func)
   local env
   if type(conn) == "function" then env,conn = conn() end
   local cur,err,err2
   for _=1,3 do
      cur,err,err2=conn:execute('SELECT '..sql)
      if cur or err ~="BUSY" then break end
   end
   if cur then
      local t={func(cur)}
      cur:close()
      if env then close(env, conn) end
      return unpack(t)
   end
   if env then close(env, conn) end
   if err2 then return nil,fmt("%s: %s",err,err2) end
   return true
end

function _ENV.iter(conn,sql,tab)
   local t,ok,err
   if tab then
      local co = coroutine.create(function()
	 local function execute(cur)
	    t = cur:fetch({},"a")
	    while t do
	       coroutine.yield()
	       t = cur:fetch({},"a")
	    end
	 end
	 ok,err=select(conn,sql,execute)
      end)
      return function()
	 coroutine.resume(co)
	 if t then return t end
	 if not ok then return nil,err end
      end
   end
   local co = coroutine.create(function()
      local function execute(cur)
	 t = cur:fetch({})
	 while t do
	    coroutine.yield()
	    t = cur:fetch({})
	 end
      end
      ok,err=select(conn,sql,execute)
   end)
   return function()
      coroutine.resume(co)
      if t then return unpack(t) end
      if not ok then return nil,err end
   end
end


function _ENV.find(conn,sql) return select(conn,sql,function(cur) return cur:fetch() end) end
function _ENV.findt(conn,sql,t)
   return select(conn,sql,function(cur) return cur:fetch(t or {},"a") end)
end

function _ENV.dir(n)
   if not n then return dbdir end
   n=dos2unix(n)
   local st=dio:stat(n)
   if st and st.isdir then
      dbdir=(n.."/"):gsub("//","/")
   else
      _G.error(fmt("%s %s", n, st and "not a dir" or "not found"), 2)
   end
end

function _ENV.exist(name)
   return dio:stat(n2dbn(name)) and true or false
end

function _ENV.open(env, name, options)
   local conn,err
   if "userdata" ~= type(env) then
      options=name
      name=env
      env,err = sqlite()
   end
   name=dio:realpath(n2dbn(name))
   if env then
      conn, err = env:connect(name, options)
      if conn then return env,conn end
      env:close()
   end
   _G.error(fmt("Cannot open %s: %s",name,err),2)
end

local function init()
   local winT={windows=true,wince=true}
   local _,os=dio:resourcetype()
   if winT[os] then
      dos2unix=function(s)
	 if not s then return "/" end
	 if _G.string.find(s,"^(%w)(:)") then
	    s=_G.string.gsub(s,"^(%w)(:)", "%1",1)
	 end
	 return _G.string.gsub(s,"\\", "/")
      end
   else
      dos2unix=function(x) return x end
   end
   local function mkdbdir(dir)
      if dir then
	 dir=dos2unix(dir.."/data"):gsub("//","/")
	 if dio:stat(dir) or dio:mkdir(dir) then return dir end
      end
   end
   dir(mkdbdir(_G.require"loadconf".dbdir) or mkdbdir(_G.mako.cfgdir) or
       mkdbdir(_G.ba.openio"home":realpath"") or mkdbdir(_G.mako.execpath))
end
init()

_ENV.close=close
_ENV.select=select
return _ENV
