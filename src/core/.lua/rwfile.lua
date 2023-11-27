
-- Read or write raw file or json file
local sbyte=string.byte

local function file(io,name,data)
   local fp,ret,err
   if data then
      fp,err=io:open(name,"w")
      if fp then ret,err = fp:write(data) end
   else
      fp,err=io:open(name)
      if fp then ret=fp:read"*a" end
   end
   if fp then fp:close() end
   return ret,err
end

local function json(io,name,tab)
   if tab then
      return file(io,name,ba.json.encode(tab))
   end
   local ret,err=file(io,name)
   if ret then
      -- If: includes UTF-8 BOM.
      if sbyte(ret,1) == 0xEF and sbyte(ret,2) == 0xBB and sbyte(ret,3) == 0xBF then
         ret=ret:sub(4)
      end
      ret=ba.json.decode(ret)
      if not ret then err="jsonerr" end
   end
   return ret,err
end

return {file=file,json=json}
