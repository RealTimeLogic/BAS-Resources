local compat = require("opcua.compat")

local function traceLog(level, msg)
  if tracep then
    tracep(false, 5, compat.to_datestring(compat.to_timestamp()), level, msg)
  else
    print(level, msg)
  end
end

local trace = {
  dbg = function(msg) traceLog("[DBG] ", msg) end,  -- Debug loging print
  inf = function(msg) traceLog("[INF] ", msg) end,  -- Information logging print
  err = function(msg) traceLog("[ERR] ", msg) end   -- Error loging print
}

return trace
