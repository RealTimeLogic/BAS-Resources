local fmt,match,tinsert,tonumber=string.format,string.match,table.insert,tonumber
local ba,jEnc,type,G=ba,ba.json.encode,type,_G

local function trim(s)
   if s then
      return s:gsub("^%s*(.-)%s*$", "%1")
   end
end

local function addpath(path,name)
   return fmt("%s/%s",path,name):gsub("//","/")
end

local function isAjaxReq(_ENV)
   if jsonrsp or (cmd.header and cmd:header"x-requested-with") then
      return true
   end
   return false
end

local function getLockOwner(_ENV,rel)
   local owner
   local xml,time=dav:lockmgr(rel,true)
   if xml then
      owner=xml:match"href%s*>([^<]+)<"
   end
   owner=owner or "unknown"
   time=time or 0
   return owner,time
end


local function checklock(_ENV,rel)
   if dav:lockmgr(rel) then
      local owner=getLockOwner(_ENV,rel)
      owner = " by "..owner or ""
      if not cmd.write then cmd=cmd:response() end
      cmd:setstatus(403)
      if isAjaxReq(_ENV) then
	 cmd:json{err="noaccess",emsg=fmt("%s is locked%s.",rel,owner)}
      else
	 cmd:write(rel," is locked",owner,'.')
      end
      cmd:abort()
   end
end

local function sendresp(_ENV,emsg,ok,err,exterr)
   local function send(data)
      local len=data and #data or 0
      cmd:setcontentlength(len)
      if data then cmd:send(data,len) end
   end
   local ajax = isAjaxReq(_ENV)
   if ajax then
      cmd:setheader("Content-Type","application/json")
   end
   if ok then
      send(ajax and jEnc{ok=true} or "ok")
   else
      if type(emsg) == "function" then emsg=emsg() end
      local e2info={
	 invalidname="Invalid name",
	 notfound="Not found",
	 exist="Resource exist",
	 enoent="No such file or directory",
	 noaccess="No file system access",
	 notempty="Directory not empty",
	 ioerror="File system error",
	 nospace="No space left on file system"
      }
      local info=e2info[err]
      info = info or err
      if exterr and #exterr > 1 then
	 info=fmt("%s.\n%s",info,exterr)
      end
      local e2http={
	 invalidname=400,
	 notfound=404,
	 exist=405,
	 enoent=409,
	 noaccess=403,
	 notempty=409,
	 nospace=503,
      }
      cmd:setstatus(e2http[err] or 503)
      if ajax then
	 send(jEnc{err=err,emsg=fmt("%s: %s.",emsg,info)})
      else
	 send(fmt("Operation failed:\n%s.\n%s.",emsg,info))
      end
   end
   cmd:abort()
end

local asyncSendresp
if ba.thread and ba.thread.run then -- If installed
   asyncSendresp=function(_ENV,emsg,ok,err,exterr)
      ba.thread.run(function() sendresp(_ENV,emsg,ok,err,exterr) end)
   end
else
   asyncSendresp=sendresp
end

local function manageFilesErr(_ENV,err)
   if response:committed() then return end
   local emsg,err=err:match"[^:%s]+:%s([^%(]+)%(([^%)]+)"
   err = err or "noaccess"
   emsg = emsg or err
   response:reset"buffer"
   sendresp(_ENV,emsg,false,err)
end


local function checkresp(_ENV,emsg,ok,err,exterr)
   if ok then return end
   sendresp(_ENV,emsg,ok,err,exterr)
end


local function doNothing() end

local nolist={["."]=true,[".."]=true,[".DAV"]=true,[".LOCK"]=true}


local function newWFS(name,priority,io,lockdir,maxuploads,maxlocks,lspfunc)
   local authenticate,authorize=doNothing,doNothing  -- Default
   local dav,resrdr,sesTmo,hasAuth,hasSesUri,pageaccessdenied
   local uploader=ba.create.upload(io)

   local function sessionuri(_ENV,rel)
      local id
      local uri
      if hasSesUri then
	 local s = cmd:session()
	 id = s and s:id(true)
      end
      if id then
	 uri=fmt("%s%s/%s",resrdr:baseuri(),id,rel)
      else
	 uri=fmt("%s%s",resrdr:baseuri(),rel)
      end
      cmd:json{tmo=id and sesTmo or 0,uri=uri}
   end

   local function lj(_ENV,rel)
      jsonrsp=true
      authorize(_ENV, rel, "PROPFIND",true)
      response:setheader("Content-Type","application/json")
      if hasSesUri then response:setheader("BaWfsSes","1") end
      local isFirst=true
      cmd:write"["
      local function action()
	 for name,isdir,time,size in io:files(rel,true) do
	    if not nolist[name] then
	       if isFirst then
		  isFirst=false
	       else
		  cmd:write","
	       end
	       cmd:write(jEnc({n=name,s=(isdir and -1 or size),t=time}))
	    end
	 end
	 return true
      end
      local ok,err=pcall(action)
      if not ok then manageFilesErr(_ENV,err) end
      cmd:write"]"
   end

   local function mkdir(_ENV,rel)
      local dir=trim(cmd:data"dir")
      if not dir or #dir == 0 then
	 sendresp(_ENV,"Cannot create directory",false,"invalidname")
      end
      rel=rel..dir
      authorize(_ENV,rel,"MKCOL")
      sendresp(_ENV,"Cannot create "..rel,io:mkdir(rel))
   end

   local function mv(_ENV,rel) -- Designed exclusively for NetIo
      local data=request:data()
      local from,to=trim(data.from),trim(data.to)
      if from and to then
	 local st = io:stat(rel)
	 if st and st.isdir then
	    from = addpath(rel,from)
	    authorize(_ENV, from, "DELETE")
	    checklock(_ENV,from)
	    authorize(_ENV, to, "PUT")
	    local function errmsg()
	       return fmt("Cannot rename %s -> %s",from, to)
	    end
	    checkresp(_ENV,errmsg,io:rename(from,to:sub(#resrdr:baseuri())))
	    sendresp(_ENV,nil,true)
	 end
      end
      sendresp(_ENV,rel,false,"notfound")
   end

   local function DELETE(_ENV,rel)
      local curname
      local function errmsg() return fmt("Cannot delete %s",curname) end
      local function delRes(fn, isdir)
	 authorize(_ENV, fn, "DELETE")
	 checklock(_ENV,fn)
	 curname=fn
	 if isdir then
	    for f,i in io:files(fn,true) do
	       if not nolist[f] then
		  delRes(fmt("%s/%s",fn,f),i)
	       end
	    end
	    checkresp(_ENV,errmsg,io:rmdir(fn))
	 else
	    checkresp(_ENV,errmsg,io:remove(fn))
	 end
	 return true
      end
      local len = #rel
      if rel:sub(len) == "/" then
	 rel = rel:sub(1,len-1)
      end
      curname=rel
      local st = io:stat(rel)
      if st then
	 local ok,err=pcall(delRes,rel,st.isdir)
	 if not ok then manageFilesErr(_ENV,err) end
	 sendresp(_ENV,nil,true)
      else
	 sendresp(_ENV,curname,false,"notfound")
      end
   end

   local function remove(_ENV,rel)
      local fn = trim(cmd:data("file"))
      if not fn or #fn == 0 then
	 sendresp(_ENV,"Cannot delete resource",false,"invalidname")
      end
      DELETE(_ENV,rel..fn)
   end

   local function getlock(_ENV,rel)
      local owner,time
      local name = cmd:data("name")
      if not name then sendresp(_ENV,"Missing lock name",false,"invalidname") end
      local pn=rel..name
      if dav:lockmgr(pn) then
	 owner,time=getLockOwner(_ENV,pn)
      else
	 local st = io:stat(pn)
	 if st and st.isdir then
	    name=name:match"([^/]+)/$"
	    if name then
	       pn=rel..name
	       if dav:lockmgr(pn) then
		  owner,time=getLockOwner(_ENV,pn)
	       end
	    end
	 end
      end
      if owner then
	 cmd:json{owner=owner,time=time}
      end
      cmd:json{notlocked=true}
   end

   local function getlocks(_ENV,rel)
      local files={}
      for n,v in request:datapairs() do
	 if n=="n" then
	    local name=rel..v
	    local st = io:stat(name)
	    if st and not st.isdir then
	       tinsert(files, {n=v,l=dav:lockmgr(name) and getLockOwner(_ENV,name) or false})
	    end
	 end
      end
      cmd:json{files=files}
   end

   local function lock(_ENV,rel)
      local time=tonumber(cmd:data"time" or 0)
      local tnow=os.time()
      if time and time > tnow then
	 for n,v in request:datapairs() do
	    if n=="n" then
	       local name=rel..v
	       local st = io:stat(name)
	       if st and not st.isdir and not dav:lockmgr(name) then
		  authorize(_ENV,name,"PUT")
		  dav:lockmgr(name,cmd,time - tnow)
	       end
	    end
	 end
      end
      cmd:json{ok=true}
   end

   local function unlock(_ENV,rel)
      for n,v in request:datapairs() do
	 if n=="n" then
	    local name=rel..v
	    if dav:lockmgr(name) then
	       authorize(_ENV,name,"PUT")
	       dav:lockmgr(name,false)
	    end
	 end
      end
      cmd:json{ok=true}
   end

   local dircmd={
      sesuri=sessionuri,
      lj=lj,
      mv=mv,
      mkdirt=mkdir,
      rmt=remove,
      getlock=getlock,
      getlocks=getlocks,
      unlock=unlock,
      lock=lock,
   }

   local function commandError(_ENV,rel,err)
      authorize(_ENV,rel,"PROPFIND",true)
      local data=jEnc{err=err}
      cmd:setstatus(400)
      cmd:setheader("Content-Type","application/json")
      cmd:setcontentlength(#data)
      cmd:send(data,#data)
      cmd:abort()
   end

   local function doDir(_ENV,rel,isPost)
      jsonrsp=true
      local c = cmd:data("cmd")
      if not c or #c == 0 then
	 if lspfunc and not isPost then
	    authorize(_ENV,rel,"PROPFIND","page")
	    _ENV.rel=rel
	    return lspfunc(_ENV,rel)
	 end
	 return commandError(_ENV,rel,"missingcmd")
      end
      local func = dircmd[c]
      if func then return func(_ENV,rel,isPost) end
      return commandError(_ENV,rel,"badcmd")
   end

   local function startUpload(_ENV,up)
      filename=up:url()..up:name()
      cmd=up
      local fn=up:name()
      authorize(_ENV, fn, "PUT")
      checklock(_ENV,fn)
   end

   local function uploadCompleted(_ENV,up)
      cmd=up:response()
      asyncSendresp(_ENV,nil,true)
   end

   local function uploadFailed(_ENV,up,emsg,extmsg)
      cmd=up:response()
      asyncSendresp(_ENV,fmt("Uploading %s failed",filename or up:url()),false,emsg,extmsg)
   end

   local function PUT(_ENV,rel)
      authorize(_ENV, rel, "PUT")
      checklock(_ENV,rel)
      if tonumber(cmd:header"Content-Length") == 0 then
	 local fp,err,ext=io:open(rel,"w")
	 if fp then
	    fp:close()
	    sendresp(_ENV,nil,true)
	 else
	    sendresp(_ENV,fmt("Uploading %s failed",rel),false,err or "ioerror",ext)
	 end
	 return
      end
      local env={rel=rel,dav=dav}
      if cmd:header"x-requested-with" then
	 env.jsonrsp=true
      end
      uploader(cmd,rel,startUpload,uploadCompleted,uploadFailed,env)
   end

   local function HEAD(_ENV,rel)
      authorize(_ENV, rel, "GET")
      local st = io:stat(rel)
      if not st then
	 cmd:senderror(404)
	 cmd:abort()
      end
      cmd:setcontentlength(st.isdir and 0 or st.size)
      if st.isdir then
	 cmd:setheader("BaIsDir","true")
      else
	 cmd:setcontenttype(ba.mime(rel:match("%.(%w+)$") or "bin"))
      end
      --Simulate a HttpResRdr response, which is used by the NetIo
      cmd:setheader("HttpResMgr","V2.1")
      cmd:setheader("Etag", fmt("%04X",st.mtime))
   end

   local function GET(_ENV,rel)
      local st = io:stat(rel)
      if not st then
	 authorize(_ENV, rel, "GET")
	 sendresp(_ENV,fmt("Resource %s",rel),false,"notfound")
      end
      if st.isdir then
	 return doDir(_ENV,rel,false)
      end
      authorize(_ENV, rel, "GET")
      if cmd:data"download" then
	 -- Strip path and escape "
	 local name = match(rel,"[^/]*$"):gsub('"','\\"')
	 cmd:setheader("Content-Disposition",
		       fmt('attachment; filename="%s"',name))
	 cmd:setcontenttype"multipart/form-data"
      end
      return resrdr:service(cmd,rel,true) -- Delegate to resrdr (HttpResRdr)
   end

   local function POST(_ENV,rel)
      local ct=cmd:header("Content-Type")
      if ct and ct:find("multipart/form-data",1,true) then
	 return PUT(_ENV,rel)
      end
      return doDir(_ENV,rel,true)
   end

   local serviceMethods={
      HEAD=HEAD,
      GET=GET,
      POST=POST,
      DELETE=DELETE,
      PUT=PUT
   }

   local function service(_ENV,rel,session)
      cmd=request
      _ENV.dav=dav
      local ua,site = request:header"User-Agent",request:header"Sec-Fetch-Site"
      if site and "cross-site" == site then sendresp(_ENV,"Access denied",false,"noaccess") end
      local func=serviceMethods[request:method()]
      if func then
	 if ua and ua:find("Mozilla",1,true) then -- Assume WFM client
	    if not session then authenticate(request,rel) end
	    return func(_ENV,rel)
	 end
      end
      if func ~= POST then
	 if dav:service(cmd,rel) then return end -- Accepted
      end
      if func then
	 if not session then authenticate(request,rel) end
	 return func(_ENV,rel)
      end
      return false
   end

   local function authService(_ENV,rel)
      local s
      if not request:user() then
	 local p
	 s,p=ba.session(request,rel,true)
	 if s then
	    s:maxinactiveinterval(sesTmo)
	    rel=p
	 end
      end
      return service(_ENV,rel,s)
   end

   resrdr=ba.create.resrdr(name,priority,io)
   resrdr:header{
      ["x-xss-protection"]="1; mode=block",
      ["x-frame-options"]="SAMEORIGIN",
      ["x-content-type"]="nosniff",
   }
   resrdr:setfunc(service)
   dav=ba.create.dav(name,priority,io,lockdir,maxuploads,maxlocks)

   local function setService(filterfunc)
      hasSesUri = hasAuth and sesTmo and true or false
      if filterfunc then
	 G.assert(type(filterfunc) == "function")
	 if hasSesUri then
	    local orgservice=service
	    service=
	       function(_ENV,rel,s)
		  return orgservice(_ENV,filterfunc(_ENV,rel,s))
	       end
	    resrdr:setfunc(authService)
	 else
	    local function filtserv(_ENV,rel)
	       return service(_ENV,filterfunc(_ENV,rel))
	    end
	    resrdr:setfunc(filtserv)
	 end
      else
	 resrdr:setfunc(hasSesUri and authService or service)
      end
   end

   local function setauth(authenticator, authorizer)
      local function _authenticate(cmd,rel)
	 if not authenticator:authenticate(cmd,rel) then
	    cmd:abort()
	 end
      end
      local function _authorize(_ENV,rel,method,mode)
	 if not authorizer:authorize(cmd,method,rel) then
	    if mode == "page" and pageaccessdenied then
	       if not cmd.write then cmd=cmd:response() end
	       cmd:setstatus(403)
	       pageaccessdenied(_ENV,rel,method)
	       cmd:abort()
	    end
	    if #rel == 0 then rel="root" end
	    -- If cmd is a 'upload' type
	    if not cmd.write then cmd=cmd:response() end
	    cmd:setstatus(403)
	    if isAjaxReq(_ENV) then
	       cmd:json{err="noaccess",emsg=fmt("You do not have %s access to %s",method,rel)}
	    else
	       cmd:write("You do not have access to ",rel,".")
	    end
	    cmd:abort()
	 end
      end
      authenticate = authenticator and _authenticate or doNothing
      authorize = authorizer and _authorize or doNothing
      hasAuth = (authenticator or authorizer) and true or false
      dav:setauth(authenticator,authorizer)
      setService()
   end

   local function configure(t)
      if t.pageaccessdenied ~= nil and type(t.pageaccessdenied) ~= "function" then
	 error("pageaccessdenied must be a function",2)
      end
      pageaccessdenied=t.pageaccessdenied
      if not t.tmo or t.tmo == 0 then
	 sesTmo=nil
      else
	 sesTmo=t.tmo
      end
      setService(t.filterservice)
      return {authorize=authorize,io=io}
   end

   return resrdr,setauth,configure
end



local wfs={}
wfs.__index=wfs
G.setmetatable(wfs,G.getmetatable(ba.create.dir()))
function wfs:setauth(authenticator, authorizer)
   self.dir:setauth(authenticator, authorizer)
   self.auth(authenticator, authorizer)
   return true
end

function wfs:configure(cfg)
   return self.cfg(cfg)
end

function wfs:service(req,rel)
   self.dir:service(req,rel)
end

local function parseArgs(argv)
   local priority,maxuploads,maxlocks,ix,name,io,lockdir,lspfunc=0,5,20,1
   if "string" == type(argv[ix]) then
      name=argv[ix]
      ix=ix+1
   end
   if "number" == type(argv[ix]) then
      priority=argv[ix]
      ix=ix+1
   end
   io=argv[ix]
   ix=ix+1
   if "string" == type(argv[ix]) then
      lockdir=argv[ix]
      ix=ix+1
   end
   if "number" == type(argv[ix]) then
      maxuploads=argv[ix]
      maxlocks=argv[ix+1]
      ix=ix+2
   end
   if "function" == type(argv[ix]) then lspfunc=argv[ix] end
   return name,priority,io,lockdir,maxuploads,maxlocks,lspfunc
end

local function create(...)
   local dir,setauth,configure=newWFS(parseArgs{...})
   return G.setmetatable({dir=dir,auth=setauth,cfg=configure}, wfs)
end

local function wfm(title)
   title=(title or"WFM"):gsub("&","&amp;"):gsub("<","&lt;")
   local s=ba.parselsp'<?lsp response:setdefaultheaders()?><!doctype html> <html lang=en> <head> <meta charset=utf-8> <meta name=viewport content="width=device-width,initial-scale=1"> <title><?lsp=title?></title> <link rel=stylesheet href=/rtl/wfm/wfm.css> <style>body{margin:0;background:#252526;--wfm-height:100vh}.wfm{border:0;border-radius:0}</style> </head> <body> <div id=files></div> <script type=module>import{mount,search,text}from"/rtl/wfm/wfm.js";const{rel}=<?lsp=(ba.json.encode{rel=pathname}:gsub("<","\\\\u003c"))?>,l=location;l.pathname.endsWith("/")||history.replaceState(0,"",l.pathname+"/"+l.search+l.hash);const url=new URL("../".repeat(rel.split("/").filter(Boolean).length),l.href);url.search=url.hash="";const manager=mount(document.getElementById("files"),{url:url,path:"/"+rel,history:!0,plugins:[search,text]});manager.ready.catch(console.error)</script>'
   local func=G.load(s,"WFM","t")
   return function(env,rel) env.title=title return func(env,rel) end
end

local wfmCache
ba.create.wfs=function(...)
   local a={...}
   wfmCache=wfmCache or wfm"WFM"
   tinsert(a,wfmCache)
   return create(G.table.unpack(a))
end
return {create=create,wfm=wfm}
