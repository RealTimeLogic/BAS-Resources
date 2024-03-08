local trem=table.remove
local tins=table.insert
local jenc=ba.json.encode

local JSONS={}
JSONS.__index = JSONS

function JSONS:get(timeout)
   if #self._data > 0 then
      return trem(self._data, 1)
   end
   local sock=self._sock
   local _,connected = sock:state()
   if not connected then return nil,"closed" end
   while true do
      local data
      local x,status,bytesRead,frameLen = sock:read(timeout)
      if not x then return nil,status end
      if status then -- if text frame
	 self._size = self._size + #x
	 x,data = self._parser:parse(x,true)
	 if not x then return nil,data end
	 if data then
	    self._data = data
	    self._size = 0
	    return trem(self._data, 1)
	 end
	 if self._mxs and self._size >=	 self._mxs then
	    return nil, "maxsize"
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
   return self._sock:write(jenc(data),true)
end

function JSONS:binary(data)
   return self._sock:write(jenc(data))
end


function JSONS:close()
   return self._sock:close()
end

return {
   create=function(o,sock,cfg)
      if "table" ~= type(o) then cfg=sock sock=o o={} end
      setmetatable(o, JSONS)
      o._parser = ba.json.parser()
      o._sock = sock
      if "table" == type(cfg) then
	 o._mxs = cfg.maxsize
	 o._bincb = cfg.bincb
      else
	 o._mxs = maxsize -- backw. comp.
      end
      o._size=0
      o._data={}
      return o
   end
}
