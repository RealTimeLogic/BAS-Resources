local json = ba.json
local fmt, strmatch = string.format, string.match
local tconcat, tinsert = table.concat, table.insert

local assert,error,type,pairs,ipairs,next,pcall,setmetatable =
      assert,error,type,pairs,ipairs,next,pcall,setmetatable

local unpack,deflate=table.unpack,ba.deflate

local _ENV={}

  local function checkArg(arg, expected, msg)
     if type(arg) == expected then
	return
     end
     error(fmt("%s expected a %s, not a %s.",
			 msg or "",expected,type(arg)),3)
  end

  local function read(request)
     local data={}
     local f = request:rawrdr()
     for a in f do -- default read size is LUAL_BUFFERSIZE (512 ?)
	data[#data + 1]= a
     end
     return tconcat(data)
  end

  local metat = { __index = {} }

   -- execute the RPC call
  function metat.__index:execute(request, response)
      assert(request)
      assert(response)
      self.request=request
      self.response=response
      local ok, rpc = pcall(read, request)
      if ok then
	 if rpc then
	    rpc = json.decode(rpc)
	    if rpc and rpc.method then
	       -- Extract interface and method name
	       local intfn,methn=strmatch(rpc.method,"([%w_]+)%.([%w_]+)")
	       if intfn and methn then -- If valid
		  local intf = self.intf[intfn] -- Lookup interface object
		  if intf then
		     local method = intf[methn] -- Lookup method
		     if method then
			local result,errno,emsg
			-- execute method
			ok, result,errno,emsg =
			   pcall(method, unpack(rpc.params or {}))
			if ok and result ~= nil then -- Send response
			   local respo =  {
			      version="1.1",
			      result = result
			   }
			   self:sendResp(respo)
			elseif ok then
			   if type(errno) == "number" then
			      self:sendError(errno,emsg) 
			   else
			      self:sendError(0, fmt(
				 "No response from %s",rpc.method))
			   end
			else
			   self:sendError(0, fmt(
			      "%s: %s",rpc.method,result))
			end
		     else
			self:sendError(0,fmt(
			   "Cannot find method: %s", rpc.method))
		     end
		  else
		     if rpc.method == "system.describe" then
			self:doSystemDescribe()
		     else
			self:sendError(0,
			   fmt("Cannot find RPC object: %s", intf))
		     end
		  end
	       else
		  self:sendError(0,fmt("%s not a valid method name.",
						 rpc.method))
	       end
	    else
	       self:sendError(0, "JSON parse error")
	    end
	 else
	    self:sendError(0, "Expected JSON RPC data")
	 end
      else
	 self:sendError(0, "Read error: "..rpc) -- rpc is now error val
      end
  end

  function metat.__index:doSystemDescribe()
      assert(self.request)
      local procs={}
      for intfn, intf in pairs(self.intf) do
	 for methn,_ in pairs(intf) do
	    tinsert(procs, fmt("%s.%s",intfn,methn))
	 end
      end
      local respo =  {
	 sdversion="1.0",
	 name=self.name,
	 id=self.request:url(),
	 procs=procs
      }
      self:sendResp(respo)
  end

  function metat.__index:sendError(err, msg)
      local respo =  {
	 version="1.1",
	 error={
	    name="JSONRPCError",
	    code=err,
	    message=msg
	 }
      }
      self:sendResp(respo)
  end

  function metat.__index:sendResp(obj)
     local req=self.request
     local resp=self.response
     local d = json.encode(obj)
     resp:reset()
     if #d > 1400 then
	local ae = req:header("Accept-Encoding")
	if ae and ae:find("deflate") then
	   resp:setheader("Content-Encoding", "deflate")
	   d=deflate(d)
	end
     end
     resp:setcontenttype("application/json")
     resp:setheader("Cache-Control", "no-store, no-cache, must-revalidate")
     resp:setheader("Content-Length",#d) 
     resp:send(d)
  end

   -- create a new JSON-RPC object.
   --param name: The JSON-RPC name for this service
   --param intf: a table containing the interfaces (objects).
   -- each object contains a table with the object methods
  new = function(name, intf)
    -- Loop through all RPC interfaces and verify the content
    checkArg(intf, "table", "Argument: ")
    local intfCnt=0
    for n,i in pairs(intf) do
       intfCnt=intfCnt+1
       checkArg(i, "table", n..": ")
       local funcCnt=0
       for _,f in next,i do
	  checkArg(f, "function", n..": ")
	  funcCnt=funcCnt+1
       end
       assert(funcCnt ~= 0, fmt("Table '%s' is empty",n))
    end
    assert(intfCnt ~= 0, "Interface table is empty")
    return setmetatable({intf=intf, name=name}, metat)
  end

return _ENV

