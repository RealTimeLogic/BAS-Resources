local ua = require("opcua.api")
local compat = require("opcua.compat")

local traceE = ua.trace.err
local traceD = ua.trace.dbg

local Srv = {}

local function getValueAttribute(id, val)
  return {
    NodeId = id,
    AttributeId = ua.AttributeId.Value,
    Value=val
  }
end

local function getNamespaceUries(model)
  local uries = {}
  for i = 0,#model.NamespaceUris do
    table.insert(uries, model.NamespaceUris[i])
  end
  return uries
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
    State = ua.ServerState.Running,
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
    Type = ua.VariantType.ExtensionObject,
    Value = {
      TypeId = "i=862", --ServerStatusDataType
      Body = status
    }
  }

  local vBuildInfo = {
    Type = ua.VariantType.ExtensionObject,
    Value = {
      TypeId = "i=338", --BuildInfo
      Body = status.BuildInfo
    }
  }

  local nodes = {
    -- Server_ServerArray
    getValueAttribute("i=2254", {Type=ua.VariantType.String, IsArray=true, Value={ua.Version.ApplicationUri}}),
    getValueAttribute("i=2256", vServerStatus),
    -- Server_ServerStatus_BuildInfo
    getValueAttribute("i=2260", vBuildInfo),
    -- Server_ServerStatus_BuildInfo_ProductName
    getValueAttribute("i=2261", {Type=ua.VariantType.String, Value=ua.Version.ProductName}),
    -- Server_ServerStatus_BuildInfo_ProductUri
    getValueAttribute("i=2262", {Type=ua.VariantType.String, Value=ua.Version.ProductUri}),
    -- Server_ServerStatus_BuildInfo_ManufacturerName
    getValueAttribute("i=2263", {Type=ua.VariantType.String, Value=ua.Version.ManufacturerName}),
    -- Server_ServerStatus_BuildInfo_SoftwareVersion
    getValueAttribute("i=2264", {Type=ua.VariantType.String, Value=ua.Version.Version}),
    -- Server_ServerStatus_BuildInfo_BuildNumber
    getValueAttribute("i=2265", {Type=ua.VariantType.String, Value=ua.Version.BuildNumber}),
    -- Server_ServerStatus_BuildInfo_BuildDate
    getValueAttribute("i=2266", {Type=ua.VariantType.DateTime, Value=status.BuildInfo.BuildDate}),
    -- Server_ServerStatus_StartTime
    getValueAttribute("i=2257", {Type=ua.VariantType.DateTime, Value=status.StartTime}),
    -- Server_ServerStatus_CurrentTime
    getValueAttribute("i=2258", {Type=ua.VariantType.DateTime, Value=compat.gettime()}),
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
  services:setVariableSource("i=2258",
    function()
        return {
          Type=ua.VariantType.DateTime,
          Value=compat.gettime()
        }
    end)
  services:setVariableSource("i=2256",
    function()
      status.CurrentTime = compat.gettime()
      return vServerStatus
    end)

  services:setVariableSource("i=2255"  , function()
    return {
      StatusCode = 0,
      Type=ua.VariantType.String,
      IsArray = true,
      Value=getNamespaceUries(services.model)
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
