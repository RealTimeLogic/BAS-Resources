

local function sendHeader(soc,status,hT)
   hT=hT or {}
   hT["Transfer-Encoding"]="chunked"
   local rspT={}
   for k,v in pairs(hT) do
      table.insert(rspT, string.format("%s: %s",k,v))
   end
   soc:write(string.format("HTTP/1.1 %d AS\r\n%s\r\n\r\n",status,table.concat(rspT,"\r\n")))
end

local function err() error"Incorrect use" end


local function create(request)
   local sock,data = ba.socket.req2sock(request)
   if not sock then return nil,data end
   local function rec()
      while true do
	 local d = sock:read()
	 if not d then break end
	 data = data and (data..d) or d
      end
   end
   sock:event(rec,"s")
   local rspT={}
   local function write(d)
      return sock:write(string.format("%x\r\n%s\r\n",#d,d))
   end
   function rspT.sendHeader(status,hT)
      sendHeader(sock,status,hT)
      rspT.sendHeader=err
      rspT.write=write
   end
   function rspT.write(d)
      rspT.sendHeader(200)
      return write(d)
   end
   function rspT.close()
      if rspT.write ~= write then
	 rspT.sendHeader(204)
      end
      sock:write"0\r\n\r\n"
      ba.socket.sock2req(sock,data)
      rspT.close=error
      rspT.write=error
   end
   return rspT
end

return {
   create=create
}
