local gateway = require("opcua.ws.opcua_gateway")

local M = {}
local directory
local inserted = false

local function handleRequest(env)
  local request = env.request
  local response = env.response

  if not request:header("Sec-WebSocket-Key") then
    response:senderror(426, "Upgrade to WebSocket with the opcua+uacp subprotocol")
    return true
  end

  local protocolHeader = request:header("Sec-WebSocket-Protocol")
  if protocolHeader and not gateway.supportsSubprotocol(protocolHeader) then
    response:senderror(400, "Unsupported WebSocket subprotocol")
    return true
  end

  local socket
  if protocolHeader then
    socket = env.ba.socket.req2sock(request, gateway.subprotocol)
  else
    socket = env.ba.socket.req2sock(request)
  end
  if socket then
    socket:event(gateway.run, "s")
  end
  return true
end

function M.get()
  if not directory then
    directory = ba.create.dir("ws")
    directory:setfunc(handleRequest)
  end
  return directory
end

function M.insert()
  local dir = M.get()
  if not inserted then
    dir:insert()
    inserted = true
  end
  return dir
end

return M
