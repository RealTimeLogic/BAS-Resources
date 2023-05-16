local ua = require("opcua.api")
local socket = require("socket")

local traceE = ua.trace.err
local traceD = ua.trace.dbg

local Srv = {}

local function getValueAttribute(id, val)
  return {
    nodeId = id,
    attributeId = ua.Types.AttributeId.Value,
    value = {
      value=val,
      statusCode = 0
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
    startTime = socket.gettime(),
    currentTime = socket.gettime(),
    state = ua.Types.ServerState.Running,
    buildInfo = {
      productUri = ua.Version.ProductUri,
      manufacturerName = ua.Version.ManufacturerName,
      productName = ua.Version.ProductName,
      softwareVersion = ua.Version.Version,
      buildNumber = ua.Version.BuildNumber,
      buildDate = socket.gettime(),
    },
    secondsTillShutdown = 0,
    shutdownReason = {},
  }
  -- State structure
  local vServerStatus = {
    extensionObject ={
      typeId = "i=864", --ServerStatusDataType_Encoding_DefaultBinary
      body = status
    }
  }

  local vBuildInfo = {
    extensionObject = {
      typeId = "i=340", --BuildInfo_Encoding_DefaultBinary
      body = status.buildInfo
    }
  }

  local vServerDiagnosticsSummary = {
    typeId = "i=861", -- ServerDiagnosticsSummaryDataType_Encoding_DefaultBinary,
    body = {
      serverViewCount = 0,
      currentSessionCount = 0,
      cumulatedSessionCount = 0,
      securityRejectedSessionCount = 0,
      rejectedSessionCount = 0,
      sessionTimeoutCount = 0,
      sessionAbortCount = 0,
      currentSubscriptionCount = 0,
      cumulatedSubscriptionCount = 0,
      publishingIntervalCount = 0,
      securityRejectedRequestsCount = 0,
      rejectedRequestsCount = 0,
    }
  }

  local nodes = {
    getValueAttribute("i=11314", {string={ua.Version.ProductUri}}), -- Server_ServerRedundancy_ServerUriArray

    -- Server_ServerArray
    getValueAttribute("i=2254", {string={ua.Version.ApplicationUri}}),
    -- Server_NamespaceArray =
    getValueAttribute("i=2255", {string={"http://opcfoundation.org/UA/"}}),

    -- Server_ServerStatus
    getValueAttribute("i=2256", vServerStatus),
    -- Server_ServerStatus_BuildInfo
    getValueAttribute("i=2260", vBuildInfo),
    -- Server_ServerStatus_BuildInfo_ProductName
    getValueAttribute("i=2261", {string=ua.Version.ProductName}),
    -- Server_ServerStatus_BuildInfo_ProductUri
    getValueAttribute("i=2262", {string=ua.Version.ProductUri}),
    -- Server_ServerStatus_BuildInfo_ManufacturerName
    getValueAttribute("i=2263", {string=ua.Version.ManufacturerName}),
    -- Server_ServerStatus_BuildInfo_SoftwareVersion
    getValueAttribute("i=2264", {string=ua.Version.Version}),
    -- Server_ServerStatus_BuildInfo_BuildNumber
    getValueAttribute("i=2265", {string=ua.Version.BuildNumber}),
    -- Server_ServerStatus_BuildInfo_BuildDate
    getValueAttribute("i=2266", {dateTime=status.buildInfo.buildDate}),
    -- Server_ServerStatus_StartTime
    getValueAttribute("i=2257", {dateTime=status.startTime}),
    -- Server_ServerStatus_State
    getValueAttribute("i=2259", {int32=ua.Types.ServerState.Running}),
    -- Server_ServerStatus_CurrentTime
    getValueAttribute("i=2258", {dateTime=socket.gettime()}),
    --Server_ServerStatus_SecondsTillShutdown
    getValueAttribute("i=2992", {uint32=0}),
    --Server_ServerStatus_ShutdownReason
    getValueAttribute("i=2993", {localizedText={text=""}}),

    -- Server_ServiceLevel
    getValueAttribute("i=2267", {byte=0}),  -- check what does it mean
    -- Server_Auditing
    getValueAttribute("i=2994", {boolean=false}),
    --Server_ServerCapabilities_ServerProfileArray
    getValueAttribute("i=2269", {string={ua.Types.ServerProfile.NanoEmbedded2017}  }),
    -- Server_ServerCapabilities_LocaleIdArray
    getValueAttribute("i=2271", {string={"en-US"}}),
    -- Server_ServerCapabilities_MinSupportedSampleRate
    getValueAttribute("i=2272", {double=0}),
    -- Server_ServerCapabilities_MaxBrowseContinuationPoints
    getValueAttribute("i=2735", {uint16=65535}),
    --Server_ServerCapabilities_MaxQueryContinuationPoints
    getValueAttribute("i=2736", {uint16=0}),
    -- Server_ServerCapabilities_MaxHistoryContinuationPoints
    getValueAttribute("i=2737", {uint16=0}),
    -- Server_ServerCapabilities_MaxArrayLength
    getValueAttribute("i=11702", {uint32=0xFFFFFFFF}),
    -- Server_ServerCapabilities_MaxStringLength
    getValueAttribute("i=11703", {uint32=0xFFFFFFFF}),

    -- Server_ServerDiagnostics_EnabledFlag
    getValueAttribute("i=2294", {boolean=false}),
    -- Server_ServerDiagnostics_ServerDiagnosticsSummary
    getValueAttribute("i=2275", {extensionObject=vServerDiagnosticsSummary}),
    -- Server_ServerDiagnostics_ServerDiagnosticsSummary_ServerViewCount
    getValueAttribute("i=2276", {uint32=0}),
    -- Server_ServerDiagnostics_ServerDiagnosticsSummary_CurrentSessionCount
    getValueAttribute("i=2277", {uint32=0}),
    -- Server_ServerDiagnostics_ServerDiagnosticsSummary_CumulatedSessionCount =
    getValueAttribute("i=2278", {uint32=0}),
    -- Server_ServerDiagnostics_ServerDiagnosticsSummary_SecurityRejectedSessionCount
    getValueAttribute("i=2279", {uint32=0}),
    -- Server_ServerDiagnostics_ServerDiagnosticsSummary_SessionTimeoutCount
    getValueAttribute("i=2281", {uint32=0}),
    -- Server_ServerDiagnostics_ServerDiagnosticsSummary_SessionAbortCount
    getValueAttribute("i=2282", {uint32=0}),
    -- Server_ServerDiagnostics_ServerDiagnosticsSummary_PublishingIntervalCount
    getValueAttribute("i=2284", {uint32=0}),
    -- Server_ServerDiagnostics_ServerDiagnosticsSummary_CurrentSubscriptionCount
    getValueAttribute("i=2285", {uint32=0}),
    -- Server_ServerDiagnostics_ServerDiagnosticsSummary_CumulatedSubscriptionCount
    getValueAttribute("i=2286", {uint32=0}),
    -- Server_ServerDiagnostics_ServerDiagnosticsSummary_SecurityRejectedRequestsCount
    getValueAttribute("i=2287", {uint32=0}),
    -- Server_ServerDiagnostics_ServerDiagnosticsSummary_RejectedRequestsCount
    getValueAttribute("i=2288", {uint32=0}),
    --Server_ServerDiagnostics_ServerDiagnosticsSummary_RejectedSessionCount
    getValueAttribute("i=3705", {uint32=0}),
  }

  if dbgOn then traceD("services | Saving server status in address space") end
  local results = services:write({nodesToWrite=nodes})

  local code = 0
  assert(#results.results == #nodes)
  for i,c in ipairs(results.results) do
    if c ~= 0 then
      if errOn then traceE(string.format("services | Node '%s' write finished with code 0x%X",nodes[i].nodeId,c)) end
      code = c
    end
  end

  if code ~= 0 then
    error(code)
  end

  -- Server_ServerStatus_CurrentTime = "i=2258"
  services:setVariableSource("i=2258", function() return { value = { dateTime = socket.gettime() } } end )
  if dbgOn then traceD("services | Server object started sucessfully") end
end

return Srv
