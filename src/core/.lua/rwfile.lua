
-- Read or write raw file or json file
local sbyte=string.byte

local function file(io,name,data)
   local fp,ret,err
   if data then
      fp,err=io:open(name,"w")
      if fp then ret,err = fp:write(data) end
   else
      fp,err=io:open(name)
      if fp then ret,err=fp:read"*a" end
   end
   if fp then
      local ok,closeErr=fp:close()
      if not ok and not err then ret,err=nil,closeErr end
   end
   return ret,err
end

local function json(io,name,tab)
   if tab then
      local data,err=ba.json.encode(tab)
      if not data then return nil,err end
      return file(io,name,data)
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
