local function jp(bp,name) return (bp .. "/" .. name):gsub("/+","/") end

return function(bio,bp)
   local function open(name,mode)
      local fp,err=bio:open(jp(bp,name),mode)
      if not fp then return nil,err end
      local function read(maxsize) return fp:read(maxsize) end
      local function write(data) return fp:write(data) end
      local function seek(offset) return fp:seek(offset) end
      local function flush() return fp:flush() end
      local function close() return fp:close() end
      return {read=read,write=write,seek=seek,flush=flush,close=close}
   end
   local function files(name)
      local curName,curIsdir,curMtime,curSize
      local iter,err=bio:files(jp(bp,name),true)
      if not iter then return nil,err end
      local function read()
	 curName,curIsdir,curMtime,curSize=iter()
	 return curName~=nil
      end
      local function name() return curName end
      local function stat()
	 return curName and {name=curName,mtime=curMtime,size=curSize,isdir=curIsdir}
      end
      return {read=read,name=name,stat=stat}
   end
   local function stat(name) return bio:stat(jp(bp,name)) end
   local function mkdir(name) return bio:mkdir(jp(bp,name)) end
   local function rmdir(name) return bio:rmdir(jp(bp,name)) end
   local function remove(name) return bio:remove(jp(bp,name)) end
   return ba.create.luaio{open=open,files=files,stat=stat,mkdir=mkdir,rmdir=rmdir,remove=remove}
end
