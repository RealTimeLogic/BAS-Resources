local ua = require("opcua.api")
local types = require("opcua.types")

local traceI = ua.trace.inf
local fmt = string.format

local S = {}
S.__index = S


function S:initialize(initAddons)
  -- services responsible for buisness logic: sessions, address space etc.
  self.services = require("opcua.services").new(self.config)
  self.services:start()

  if type(initAddons) == "function" then
    initAddons(self.services)
  end
end

function S:run()
  local infOn = self.config.logging.services.infOn

  if self.config.httpDirName then
    local httpDirFunc = self:createHttpDirectory()
    local dir = ba.create.dir(self.config.httpDirName)
    dir:setfunc(httpDirFunc)
    dir:insert()
    self.httpDir = dir
  end

  for _,endpoint in ipairs(self.config.endpoints) do
    local endpointUrl = endpoint.endpointUrl
    if endpointUrl:find("opc.tcp://") then
      self.binaryServer = require("opcua.binary.server").new(endpoint, self.config, self.services, self.model)
      self.serverSock = require("opcua.socket_rtl").newServerSock(endpoint, self.config)
      self.serverSock:run(self.binaryServer)
    end
    if infOn then traceI(fmt("Ready endpoint: %s", endpointUrl)) end
  end

end

function S:createHttpDirectory()
  local binaryServer = require("opcua.binary.server_connection_http").new(self.config, self.services, self.model)
  return binaryServer
end


function S:shutdown()
  self.services:shutdown()
  if self.serverSock then
    self.serverSock:shutdown()
  end
  if self.httpDir then
    self.httpDir:unlink()
  end
end


local function browseParams(nodeId)
  return {
    NodeId = nodeId, -- nodeId we want to browse
    BrowseDirection = types.BrowseDirection.Forward,
    ReferenceTypeId = "i=33", -- HierarchicalReferences
    NodeClassMask = types.NodeClass.Unspecified,
    ResultMask = types.BrowseResultMask.All,
    IncludeSubtypes = true,
  }
end

function S:browse(params)
  local request = {
    RequestedMaxReferencesPerNode = 0,
    NodesToBrowse = {}
  }

  -- single node ID
  if type(params) == 'string' then
    request.NodesToBrowse[1] = browseParams(params)
  -- array of nodeIDs
  elseif type(params) == 'table' and params[1] ~= nil then
    for _,nodeId in ipairs(params) do
      table.insert(request.NodesToBrowse, browseParams(nodeId))
    end
  else
    -- manual
    request = params
  end

  return self.services:browse(request)
end

local function allAttributes(nodeId, attrs)
  for _,val in pairs(types.AttributeId) do
    table.insert(attrs, {NodeId=nodeId, AttributeId=val})
  end
end

function S:read(params)
  local readParams = {}
  if type(params) == 'string' then
    local attrs = {}
    allAttributes(params, attrs)
    readParams.NodesToRead = attrs
  elseif type(params) == 'table' then
    if type(params[1]) == 'string' then
      local attrs = {}
      for _,nodeId in ipairs(params) do
        allAttributes(nodeId, attrs)
      end
      readParams.NodesToRead = attrs
    else
      readParams.NodesToRead = params
    end
  end

  return self.services:read(readParams)
end

function S:write(params)
  return self.services:write(params)
end

function S:addNodes(params)
  return self.services:addNodes(params)
end

function S:setVariableSource(nodeId, callback)
  return self.services:setVariableSource(nodeId, callback)
end

function S.new(config, model)
  if not config then
    local ip = "localhost"
    local s,err = ba.socket.connect("8.8.8.8",53)
    if config.logging.services.infOn then
      traceI(fmt("opcua.server | Failed to detect local ip: %s", err))
    end

    if s then
      local _,_,ips = string.find(s:sockname(), "(%d+.%d+.%d+.%d+)")
      ip = ips
      s:close()
    end

    config = {
      bufSize = 16384,
      endpointUrl="opc.tcp://"..ip..":4841",
      securePolicies ={
        {
          securityPolicyUri = "http://opcfoundation.org/UA/SecurityPolicy#None"
        }
      }
    }
  end

  local uaConfig = require("opcua.config")
  local err = uaConfig.server(config)
  if err ~= nil then
    error("Configuration error: "..err)
  end

  if model == nil then
    model = require("opcua.model.import").getBaseModel()
  end

  local srv = {
    config = config,
    model = model
  }

  setmetatable(srv, S)
  return srv
end

return S
