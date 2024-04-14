local ua = require("opcua.api")
local compat = require("opcua.compat")

local traceE = ua.trace.err
local traceD = ua.trace.dbg

local Srv = {}

local function getValueAttribute(id, val)
  return {
    NodeId = id,
    AttributeId = ua.Types.AttributeId.Value,
    Value = {
      Value=val,
      StatusCode = 0
    }
  }
end

function Srv:start(config, services)
  local dbgOn = config.logging.services.dbgOn
  local errOn = config.logging.services.errOn

  if dbgOn then traceD("services | Starting server object") end
  self.Services = services
  -- Default namespace Array

  -- Server Status
  local status = {
    StartTime = compat.gettime(),
    CurrentTime = compat.gettime(),
    State = ua.Types.ServerState.Running,
    BuildInfo = {
      ProductUri = ua.Version.ProductUri,
      ManufacturerName = ua.Version.ManufacturerName,
      ProductName = ua.Version.ProductName,
      SoftwareVersion = ua.Version.Version,
      BuildNumber = ua.Version.BuildNumber,
      BuildDate = compat.gettime(),
    },
    SecondsTillShutdown = 0,
    ShutdownReason = {Text=""},
  }
  -- State structure
  local vServerStatus = {
    ExtensionObject ={
      TypeId = "i=862", --ServerStatusDataType
      Body = status
    }
  }

  local vBuildInfo = {
    ExtensionObject = {
      TypeId = "i=338", --BuildInfo
      Body = status.BuildInfo
    }
  }

  local nodes = {
    -- Server_ServerArray
    getValueAttribute("i=2254", {String={ua.Version.ApplicationUri}}),
    -- Server_NamespaceArray =
    getValueAttribute("i=2255", {String={"http://opcfoundation.org/UA/"}}),
    -- Server_ServerStatus
    getValueAttribute("i=2256", vServerStatus),
    -- Server_ServerStatus_BuildInfo
    getValueAttribute("i=2260", vBuildInfo),
    -- Server_ServerStatus_BuildInfo_ProductName
    getValueAttribute("i=2261", {String=ua.Version.ProductName}),
    -- Server_ServerStatus_BuildInfo_ProductUri
    getValueAttribute("i=2262", {String=ua.Version.ProductUri}),
    -- Server_ServerStatus_BuildInfo_ManufacturerName
    getValueAttribute("i=2263", {String=ua.Version.ManufacturerName}),
    -- Server_ServerStatus_BuildInfo_SoftwareVersion
    getValueAttribute("i=2264", {String=ua.Version.Version}),
    -- Server_ServerStatus_BuildInfo_BuildNumber
    getValueAttribute("i=2265", {String=ua.Version.BuildNumber}),
    -- Server_ServerStatus_BuildInfo_BuildDate
    getValueAttribute("i=2266", {DateTime=status.BuildInfo.BuildDate}),
    -- Server_ServerStatus_StartTime
    getValueAttribute("i=2257", {DateTime=status.StartTime}),
    -- Server_ServerStatus_CurrentTime
    getValueAttribute("i=2258", {DateTime=compat.gettime()}),
  }

  if dbgOn then traceD("services | Saving server status in address space") end
  local results = services:write({NodesToWrite=nodes})

  local code = 0
  assert(#results.Results == #nodes)
  for i,c in ipairs(results.Results) do
    if c ~= 0 then
      if errOn then traceE(string.format("services | Node '%s' write finished with code 0x%X",nodes[i].NodeId,c)) end
      code = c
    end
  end

  if code ~= 0 then
    error(code)
  end

  -- Server_ServerStatus_CurrentTime = "i=2258"
  services:setVariableSource("i=2258", function() return { Value = { DateTime = compat.gettime() } } end )
  services:setVariableSource("i=2256"  , function()
    status.CurrentTime = compat.gettime()
    return {
      Value = vServerStatus,
      StatusCode = 0
    }
  end)


  if dbgOn then traceD("services | Server object started sucessfully") end
end

local function create()
  local srv = {}
  setmetatable(srv, {__index = Srv})
  return srv
end

return create
