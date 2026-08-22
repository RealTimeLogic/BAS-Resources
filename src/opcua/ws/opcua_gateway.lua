local BinaryDecoder = require("opcua.binary.decoder")
local Queue = require("opcua.binary.queue")
local tools = require("opcua.tools")
local WebSocketSocket = require("opcua.ws.websocket")

local M = {}

local SUBPROTOCOL = "opcua+uacp"
local DEFAULT_OPCUA_PORT = 4840
local UACP_HEADER_SIZE = 8

local function decodeHeader(data)
  if type(data) ~= "string" or #data < UACP_HEADER_SIZE then
    return nil, "OPC UA MessageChunk is shorter than its header"
  end

  local queue = Queue.new(#data)
  queue:pushBack(data)
  local decoder = BinaryDecoder.new(queue)
  local ok, header = pcall(decoder.messageHeader, decoder)
  if not ok then
    return nil, header
  end
  return header, decoder, queue
end

local function validateChunk(data)
  local header, err = decodeHeader(data)
  if not header then
    return nil, err
  end
  if header.MessageSize ~= #data then
    return nil, "OPC UA MessageSize does not match the WebSocket frame"
  end
  return header
end

function M.supportsSubprotocol(header)
  if type(header) ~= "string" then
    return false
  end
  for token in header:gmatch("[^,]+") do
    if token:match("^%s*(.-)%s*$") == SUBPROTOCOL then
      return true
    end
  end
  return false
end

function M.decodeHello(data)
  local header, decoder, queue = decodeHeader(data)
  if not header then
    return nil, decoder
  end
  if header.Type ~= "HEL" or header.Chunk ~= "F" then
    return nil, "The first WebSocket frame must contain HELF"
  end
  if header.MessageSize ~= #data then
    return nil, "HEL MessageSize does not match the WebSocket frame"
  end

  local ok, hello = pcall(decoder.hello, decoder)
  if not ok then
    return nil, hello
  end
  if #queue ~= 0 then
    return nil, "HEL contains trailing data"
  end

  local url, err = tools.parseUrl(hello.EndpointUrl)
  if not url then
    return nil, err
  end
  if url.scheme ~= "opc.tcp" then
    return nil, "HEL EndpointUrl must use the opc.tcp scheme"
  end
  url.port = url.port or DEFAULT_OPCUA_PORT
  url.endpointUrl = hello.EndpointUrl
  return url, hello
end

local function createTcpChunkReader(sock)
  local pending = ""

  return function()
    while #pending < UACP_HEADER_SIZE do
      local data, err = sock:read()
      if not data then
        return nil, err
      end
      pending = pending .. data
    end

    local header, err = decodeHeader(pending:sub(1, UACP_HEADER_SIZE))
    if not header then
      return nil, err
    end
    if header.MessageSize < UACP_HEADER_SIZE then
      return nil, "Invalid OPC UA MessageSize received from TCP server"
    end

    while #pending < header.MessageSize do
      local data, readError = sock:read()
      if not data then
        return nil, readError
      end
      pending = pending .. data
    end

    local chunk = pending:sub(1, header.MessageSize)
    pending = pending:sub(header.MessageSize + 1)
    return chunk
  end
end

local function pipeWebSocketToTcp(webSocket, tcpSocket)
  while true do
    local data, err = webSocket:receiveFrame()
    if not data then
      return err
    end
    local _, validationError = validateChunk(data)
    if validationError then
      return validationError
    end
    local ok
    ok, err = tcpSocket:write(data)
    if not ok then
      return err
    end
  end
end

local function pipeTcpToWebSocket(tcpSocket, webSocket)
  local readChunk = createTcpChunkReader(tcpSocket)
  while true do
    local chunk, err = readChunk()
    if not chunk then
      return err
    end
    local ok
    ok, err = webSocket:sendFrame(chunk)
    if not ok then
      return err
    end
  end
end

local function connectAndPipe(_, context)
  local tcpSocket, err = ba.socket.connect(context.target.host, context.target.port)
  if not tcpSocket then
    context.webSocket.socket:enable({error = err})
    return
  end

  local ok
  ok, err = tcpSocket:write(context.helloFrame)
  if not ok then
    context.webSocket.socket:enable({error = err})
    tcpSocket:close()
    return
  end

  context.webSocket.socket:enable({tcpSocket = tcpSocket})
  pipeTcpToWebSocket(tcpSocket, context.webSocket)
  context.webSocket:shutdown()
end

function M.run(socket)
  local webSocket = WebSocketSocket.new(socket)
  local helloFrame = webSocket:receiveFrame()
  if not helloFrame then
    webSocket:shutdown()
    return
  end

  local target = M.decodeHello(helloFrame)
  if not target then
    webSocket:shutdown()
    return
  end

  ba.socket.event(connectAndPipe, {
    webSocket = webSocket,
    target = target,
    helloFrame = helloFrame,
  })

  local result = socket:disable()
  if not result or not result.tcpSocket then
    webSocket:shutdown()
    return
  end

  pipeWebSocketToTcp(webSocket, result.tcpSocket)
  result.tcpSocket:close()
  webSocket:shutdown()
end

M.subprotocol = SUBPROTOCOL
M.validateChunk = validateChunk
M.createTcpChunkReader = createTcpChunkReader

return M
