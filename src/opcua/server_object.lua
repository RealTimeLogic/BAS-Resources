local compat = require("opcua.compat")
local trace = require("opcua.trace")
local const = require("opcua.const")
local version = require("opcua.version")

local traceD = trace.dbg

local VariantType = const.VariantType

local Srv = {}

local function getNamespaceUries(model)
  local uries = {}
  for i = 0,#model.Namespaces do
    table.insert(uries, model.Namespaces[i].NamespaceUri)
  end
  return uries
end

function Srv:start(config, services)
  local dbgOn = config.logging.services.dbgOn

  if dbgOn then traceD("services | Starting server object") end
  self.Services = services
  -- Default namespace Array

  -- Server Status
  local status = {
    StartTime = compat.gettime(),
    CurrentTime = compat.gettime(),
    State = const.ServerState.Running,
    BuildInfo = {
      ProductUri = version.ProductUri,
      ManufacturerName = version.ManufacturerName,
      ProductName = version.ProductName,
      SoftwareVersion = version.Version,
      BuildNumber = version.BuildNumber,
      BuildDate = compat.gettime(),
    },
    SecondsTillShutdown = 0,
    ShutdownReason = {Text=""},
  }
  -- State structure
  local vServerStatus = {
    Type = VariantType.ExtensionObject,
    Value = {
      TypeId = "i=862", --ServerStatusDataType
      Body = status
    }
  }

  local vBuildInfo = {
    Type = VariantType.ExtensionObject,
    Value = {
      TypeId = "i=338", --BuildInfo
      Body = status.BuildInfo
    }
  }

  if dbgOn then traceD("services | Saving server status in address space") end

  local editor = self.Services.model:edit()
  -- Server_ServerArray
  editor:getNode("i=2254").Attrs.Value = {Type=VariantType.String, IsArray=true, Value={version.ApplicationUri}}
  -- Server_ServerStatus
  local serverStatusNode = editor:getNode("i=2256")
  serverStatusNode.Attrs.Value = vServerStatus
  serverStatusNode:setValueCallback(
    function()
      status.CurrentTime = compat.gettime()
      return vServerStatus
    end)

  -- Server_ServerStatus_BuildInfo
  editor:getNode("i=2260").Attrs.Value = vBuildInfo
  -- Server_ServerStatus_BuildInfo_ProductName
  editor:getNode("i=2261").Attrs.Value = {Type=VariantType.String, Value=version.ProductName}
  -- Server_ServerStatus_BuildInfo_ProductUri
  editor:getNode("i=2262").Attrs.Value = {Type=VariantType.String, Value=version.ProductUri}
  -- Server_ServerStatus_BuildInfo_ManufacturerName
  editor:getNode("i=2263").Attrs.Value = {Type=VariantType.String, Value=version.ManufacturerName}
  -- Server_ServerStatus_BuildInfo_SoftwareVersion
  editor:getNode("i=2264").Attrs.Value = {Type=VariantType.String, Value=version.Version}
  -- Server_ServerStatus_BuildInfo_BuildNumber
  editor:getNode("i=2265").Attrs.Value = {Type=VariantType.String, Value=version.BuildNumber}
  -- Server_ServerStatus_BuildInfo_BuildDate
  editor:getNode("i=2266").Attrs.Value = {Type=VariantType.DateTime, Value=status.BuildInfo.BuildDate}
  -- Server_ServerStatus_StartTime
  editor:getNode("i=2257").Attrs.Value = {Type=VariantType.DateTime, Value=status.StartTime}
  -- Server_ServerStatus_CurrentTime
  editor:getNode("i=2258").Attrs.Value = {Type=VariantType.DateTime, Value=compat.gettime()}

  if dbgOn then traceD("services | Saving server status in address space") end

  editor:getNode("i=2258"):setValueCallback(
    function()
      return {
        Type=VariantType.DateTime,
        Value=compat.gettime()
      }
    end)

  editor:getNode("i=2255"):setValueCallback(function()
    return {
      StatusCode = 0,
      Type=VariantType.String,
      IsArray = true,
      Value=getNamespaceUries(services.model)
    }
  end)

  editor:save()

  if dbgOn then traceD("services | Server object started sucessfully") end
end

local function create()
  local srv = {}
  setmetatable(srv, {__index = Srv})
  return srv
end

return create
