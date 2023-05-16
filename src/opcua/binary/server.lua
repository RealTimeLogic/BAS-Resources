local Connections = require("opcua.binary.server_connection")
local ua = require("opcua.api")

local S = {}
S.__index = S

function S:acceptConnection(out)
  if self.trace.infOn then ua.trace.inf("binary | new connection accepted") end
  assert(out ~= nil and out.send ~= nil)
  return Connections.new(self.config, self.services, out)
end

local function newServer(config, services)
  assert(config ~= nil)
  assert(services ~= nil)

  if config.logging.binary.infOn then
    ua.trace.inf("binary: Creating new endpoint '"..config.endpointUrl.."'")
  end

  local srv = {
    config = config,
    trace = config.logging.binary,
    services = services,
    connections = {},
    channelId = 0,
  }

  setmetatable(srv, S)
  return srv
end

return {new=newServer}
