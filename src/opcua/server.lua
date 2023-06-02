local types = require("opcua.types")

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
  -- binary protocol server: parses requests and calls common services
  -- now it is supported only binary protocol, later we will support different protocols.
  self.binaryServer = require("opcua.binary.server").new(self.config, self.services)
  self.serverSock = require("opcua.socket_rtl").newServerSock(self.config)
  self.serverSock:run(self.binaryServer)
end

function S:shutdown()
  self.services:shutdown()
  self.serverSock:shutdown()
end


local function browseParams(nodeId)
  return {
    nodeId = nodeId, -- nodeId we want to browse
    browseDirection = types.BrowseDirection.Forward,
    referenceTypeId = "i=33", -- HierarchicalReferences
    nodeClassMask = types.NodeClass.Unspecified,
    resultMask = types.BrowseResultMask.All,
    includeSubtypes = true,
  }
end

function S:browse(params)
  local request = {
    requestedMaxReferencesPerNode = 0,
    nodesToBrowse = {}
  }

  -- single node ID
  if type(params) == 'string' then
    request.nodesToBrowse[1] = browseParams(params)
  -- array of nodeIDs
  elseif type(params) == 'table' and params[1] ~= nil then
    for _,nodeId in ipairs(params) do
      table.insert(request.nodesToBrowse, browseParams(nodeId))
    end
  else
    -- manual
    request = params
  end

  return self.services:browse(request)
end

local function allAttributes(nodeId, attrs)
  for _,val in pairs(types.AttributeId) do
    table.insert(attrs, {nodeId=nodeId, attributeId=val})
  end
end

function S:read(params)
  local readParams = {}
  if type(params) == 'string' then
    local attrs = {}
    allAttributes(params, attrs)
    readParams.nodesToRead = attrs
  elseif type(params) == 'table' then
    if type(params[1]) == 'string' then
      local attrs = {}
      for _,nodeId in ipairs(params) do
        allAttributes(nodeId, attrs)
      end
      readParams.nodesToRead = attrs
    else
      readParams.nodesToRead = params
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

function S.new(config)
  local uaConfig = require("opcua.config")
  local err = uaConfig.server(config)
  if err ~= nil then
    error("Configuration error: "..err)
  end

  local srv = {
    config = config
  }

  setmetatable(srv, S)
  return srv
end

return S
