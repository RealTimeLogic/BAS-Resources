local commands=...

local function senderror(cmd,msg)
   cmd:setheader("X-Error",msg)
   cmd:senderror(400, msg)
   cmd:abort()
end

function commands.uploadfw(cmd)
   cmd:allow{"PUT"}
   local fn = cmd:header"X-File-Name"
   if not fn then senderror(cmd,"") end
   local n,ext=fn:match"(.-)%.([^%./]+)$"
   if not n or not ext then senderror(cmd,"Invalid file name") end
   ext=ext:lower()
   if "zip" == ext then
      local rsp
      fn=n.."."..ext
      local io = mako and ba.openio"home" or ba.openio"disk"
      if io:stat(n) then
	 rsp={err="<p><b>Conflict Detected:</b> The server has found an existing directory with the same name as your uploaded zip file, indicating a non-deployed application already exists with this name. Deployed applications are uploaded and managed as zip files, whereas non-deployed applications exist as directories on the server.</p><p>To resolve this:</p><ul><li>If you intend to update or replace the existing non-deployed application, please delete the corresponding directory on the server first, then attempt the upload again.</li><li>If deploying a new application, rename your zip file to avoid naming conflicts and upload it again.</li></ul>"}
      else
	 local upgrade = io:stat(fn) and true or false
	 local fp,err = io:open(fn,"w")
	 if fp then
	    local ok
	    for data in cmd:rawrdr(4096) do
	       ok,err=fp:write(data)
	       if not ok then break end
	    end
	    fp:close()
	    rsp={ok=ok,err=err,upgrade=upgrade}
	 else
	    rsp={err=err}
	 end
      end
      cmd:json(rsp)
   end
   cmd:abort()
end
