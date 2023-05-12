
local trem=table.remove
local tins=table.insert
local jenc=ba.json.encode

local JSONS={}
JSONS.__index = JSONS

function JSONS:get(timeout)
   if #self._data > 0 then
      return trem(self._data, 1)
   end
   while true do
      local data 
      local x,err = self._sock:read(timeout)
      if not x then return nil,err end
      self._size = self._size + #x
      x,data = self._parser:parse(x,true)
      if not x then return nil,data end
      if data then
	 self._data = data
	 self._size = 0
	 return trem(self._data, 1)
      end
      if self._mxs and self._size >=  self._mxs then
	 return nil, "maxsize"
      end
   end
end


function JSONS:put(data)
   return self._sock:write(jenc(data))
end

function JSONS:close()
   return self._sock:close()
end

return {
   create=function(o,sock,maxsize)
      setmetatable(o, JSONS)
      o._parser = ba.json.parser()
      o._sock = sock
      o._mxs = maxsize
      o._size=0
      o._data={}
      return o
   end
}


