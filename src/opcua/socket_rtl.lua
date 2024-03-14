local ua = require("opcua.api")
local compat = require("opcua.compat")
local s = ua.StatusCode

local fmt = string.format

local traceD = ua.trace.dbg
local traceI = ua.trace.inf
local traceE = ua.trace.err


local clientSock = {}
clientSock.__index = clientSock

function clientSock:send(data)
  local errOn = self.logging.errOn
  local dbgOn = self.logging.dbgOn

  local sock = self.sock
  if sock == nil then
    error(s.BadCommunicationError)
  end

  if dbgOn then traceD(fmt("socket | %s sending %d bytes to client", sock, #data)) end
  local done, err = sock:write(data)
  if done == true then
    if dbgOn then traceD(fmt("socket | %s Data sent", sock)) end
  else
    if errOn and err ~= 'sysshutdown' then traceE(fmt("socket | %s TCP write error: %s", sock, err)) end
    error(s.BadCommunicationError)
  end
end

function clientSock:receive(sz)
  local dbgOn = self.logging.dbgOn
  local errOn = self.logging.errOn

  local sock = self.sock
  if sock == nil then
    error(s.BadCommunicationError)
  end

  if dbgOn then traceD(fmt("socket | %s waiting for new data", sock)) end
  local data,err = sock:read(self.timeoutMs, sz)
  if err ~= nil then
    if dbgOn then
      traceD(fmt("socket | %s TCP read error: %s", sock, err))
    elseif errOn and err ~= 'sysshutdown' and err ~= 'socketclosed' then
      traceD(fmt("socket | %s TCP read error: %s", sock, err))
    end
    error(s.BadCommunicationError)
  end
  if data == nil then
    if errOn then traceE(fmt("socket | %s TCP read nil data", sock)) end
    error(s.BadCommunicationError)
  end

  if dbgOn then traceD(fmt("socket | %s received %d bytes: ", sock, #data)) end
  return data
end

function clientSock:shutdown()
  local sock = self.sock
  if sock ~= nil then
    local infOn = self.logging.infOn
    if infOn then traceI("Closing client socket") end
    sock:close()
  end
end

function clientSock:setTimeout(ms)
  self.timeoutMs = ms
end

local function newClientSock(sock, config)
  local result = {
    sock = sock,
    logging = config.logging.socket
  }
  setmetatable(result, clientSock)
  return result;
end


local serverSock = {}
serverSock.__index = serverSock

local function newServerSock(endpoint, config)
  local result = {
    endpoint = endpoint,
    logging = config.logging.socket,
    config = config
  }
  setmetatable(result, serverSock)
  return result;
end

function serverSock:run(binaryServer)
  local infOn = self.logging.infOn
  local dbgOn = self.logging.dbgOn
  local errOn = self.logging.errOn

  local clients = {}

  local function uaServerProc(sock)
    if infOn then traceI(fmt("socket | %s Accepted new connection", sock)) end
    clients[sock] = sock

    local server = binaryServer:acceptConnection(newClientSock(sock, self.config))
    while true do
      if dbgOn then traceD(fmt("socket | %s processing next message", sock)) end
      local suc,err = pcall(server.processData, server)
      if not suc then
        if errOn and err ~= s.BadCommunicationError then traceE(fmt("socket | %s error '%s'", sock, err)) end
        break
      end
    end

    if infOn then traceI(fmt("socket | %s Closing client socket.", sock)) end
    clients[sock] = nil
    sock:close()
    if infOn then traceI(fmt("socket | %s Client socket closed.", sock)) end
  end

  local function accept(srvSock)
    while true do
      local client = srvSock:accept()
      if not client then break end -- If server listen socket was closed.
      if infOn then traceI(fmt("socket | %s new client accepted", client)) end
      client:event(uaServerProc, "s") -- Activate the cosocket.
    end

    if clients then
      for _,sock in pairs(clients) do
        sock:close()
      end
      clients = nil
    end
    self.sock = nil
  end

  if infOn then traceI(fmt("socket | Opening port '%d'", self.endpoint.listenPort)) end
  local sock = compat.socket.bind(self.endpoint.listenAddress, self.endpoint.listenPort)
  self.sock = sock
  if sock then
    if infOn then traceI(fmt("socket | %s created server socket.", sock, self.endpoint.listenPort)) end
    sock:event(accept,"r")
    if infOn then traceI(fmt("socket | %s listening on port %d.", sock, self.endpoint.listenPort)) end
  else
    if infOn then traceE("socket |Cannot open listen port!") end
  end
end

function serverSock:shutdown()
  local sock = self.sock
  if sock == nil then
    return
  end

  local infOn = self.logging.infOn
  if infOn then traceI("Closing server socket") end
  sock:close()

  while true do
    local _,active = sock:state()
    if not active then
      break
    end
    compat.sleep(1)
  end
end

return {
  newServerSock=newServerSock,
  newClientSock=newClientSock,
}
