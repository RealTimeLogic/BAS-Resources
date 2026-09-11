local trem,jenc=table.remove,ba.json.encode
local JSONS={}
JSONS.__index = JSONS

function JSONS:get(timeout)
   if #self._data > 0 then
      return trem(self._data, 1)
   end
   if self._error then return nil,self._error end
   local sock=self._sock
   local _,connected = sock:state()
   if not connected then return nil,"closed" end
   while true do
      local data
      local x,status,bytesRead,frameLen=sock:read(timeout)
      if not x then return nil,status end
      if status~=false then -- TCP data or a WebSocket text frame
         self._size=self._size+#x
         x,data=self._parser:parse(x,true)
         if not x then
            self._error=data
            return nil,data
         end
         if data then
            self._data=data
            self._size=0
            return trem(self._data,1)
         end
         if self._mxs and self._size>=self._mxs then
            self._error="maxsize"
            return nil,self._error
         end
      else -- binary
	 if not self._bincb then
	    return nil,"binary"
	 end
	 self._bincb(x,bytesRead,frameLen,self)
      end
   end
end


function JSONS:put(data)
   local encoded,err=jenc(data)
   if not encoded then return nil,err end
   return self._sock:write(encoded,true)
end

function JSONS:binary(data)
   local encoded,err=jenc(data)
   if not encoded then return nil,err end
   return self._sock:write(encoded)
end


function JSONS:close()
   return self._sock:close()
end

return {
   create=function(o,sock,cfg)
      if "table" ~= type(o) then cfg=sock sock=o o={} end
      local maxsize=type(cfg)=="table" and cfg.maxsize or nil
      if maxsize~=nil then
         maxsize=tonumber(maxsize)
         assert(maxsize and maxsize>0 and maxsize%1==0,
                "maxsize must be a positive integer")
         maxsize=assert(math.tointeger(maxsize),"maxsize exceeds integer range")
      end
      setmetatable(o, JSONS)
      o._parser = ba.json.parser()
      o._sock = sock
      o._mxs=maxsize
      o._bincb=type(cfg)=="table" and cfg.bincb or nil
      o._error=nil
      o._size=0
      o._data={}
      return o
   end
}
