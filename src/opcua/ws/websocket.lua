local compat = require("opcua.compat")
local StatusCode = require("opcua.status_codes")

local BadCommunicationError = StatusCode.BadCommunicationError
local BadTcpMessageTypeInvalid = StatusCode.BadTcpMessageTypeInvalid
local BinaryFrameRequired = "opcua+uacp accepts binary WebSocket frames only"

local function webSocketUrl(endpointUrl)
  if endpointUrl:find("opc.wss://", 1, true) == 1 then
    return "wss://"..endpointUrl:sub(#"opc.wss://" + 1)
  end
  return endpointUrl
end

local WebSocketSocket = {}
WebSocketSocket.__index = WebSocketSocket

function WebSocketSocket:receiveFrame()
  local data, utf8, bytesRead, frameLen = self.socket:read()
  if not data then
    return nil, utf8
  end
  if utf8 then
    return nil, BinaryFrameRequired
  end

  if frameLen then
    local parts = {data}
    while bytesRead < frameLen do
      local nextData, nextUtf8
      nextData, nextUtf8, bytesRead, frameLen = self.socket:read()
      if not nextData then
        return nil, nextUtf8
      end
      if nextUtf8 then
        return nil, BinaryFrameRequired
      end
      parts[#parts + 1] = nextData
    end
    data = table.concat(parts)
  end

  return data
end

function WebSocketSocket:receive()
  local data, err = self:receiveFrame()
  if data then
    return data
  end
  if err == BinaryFrameRequired then
    error(BadTcpMessageTypeInvalid)
  end
  error(BadCommunicationError)
end

function WebSocketSocket:sendFrame(data)
  return self.socket:write(data, false)
end

function WebSocketSocket:send(data)
  local ok = self:sendFrame(tostring(data))
  if not ok then
    error(BadCommunicationError)
  end
end

function WebSocketSocket:shutdown()
  return self.socket:close()
end

local function new(socket)
  assert(socket ~= nil)
  return setmetatable({socket = socket, sock = socket}, WebSocketSocket)
end

local function connectWebSocket(endpointUrl, config)
  if not compat.httpc or not compat.socket.http2sock then
    return nil, "WebSocket transport is not supported by this runtime"
  end

  local http = compat.httpc.create()
  http:timeout(20000)

  local ok, err = http:request({
    shark = config.shark,
    url = webSocketUrl(endpointUrl),
    trusted = false
  })
  if not ok then
    http:close()
    return nil, err or BadCommunicationError
  end

  local status
  status, err = http:status()
  if err or status ~= 101 then
    http:close()
    return nil, err or string.format(
      "WebSocket upgrade failed with HTTP status %s",
      tostring(status)
    )
  end

  local socket, pending = compat.socket.http2sock(http)
  if not socket then
    http:close()
    return nil, pending or BadCommunicationError
  end
  if pending and #pending ~= 0 then
    socket:close()
    return nil, "Unexpected data received with WebSocket upgrade response"
  end

  return new(socket)
end

return {
  new = new,
  connectWebSocket = connectWebSocket,
  webSocketUrl = webSocketUrl
}
