local tools = require("opcua.binary.tools")


local gettime = require("socket").gettime
local function traceLog(level, msg)
  print(gettime(), level, msg)
end


local function checkCommonAttributes(parentNodeId, browseName, displayName, newNodeId)
  if not tools.qualifiedNameValid(browseName) then
    error(0x80600000) -- BadBrowseNameInvalid
  end

  if not tools.nodeIdValid(parentNodeId) then
    error(0x805B0000) -- BadParentNodeIdInvalid
  end

  if newNodeId ~= nil and not tools.nodeIdValid(newNodeId) then
    error(0x80330000) -- BadBrowseNameInvalid
  end

  if not tools.localizedTextValid(displayName) then
    error(0x80620000) -- BadNodeAttributesInvalid
  end
end

local ua = {
  newServer = function(config) return require("opcua.server").new(config) end,
  newClient = function(config) return require("opcua.client").new(config) end,

  Version = require("opcua.version"),
  StatusCode = require("opcua.status_codes"),
  NodeId = require("opcua.node_id"),
  Types = require("opcua.types"),
  Tools = tools,

  trace = {
    dbg = function(msg) traceLog("[DBG] ", msg) end,  -- Debug loging print
    inf = function(msg) traceLog("[INF] ", msg) end,  -- Information logging print
    err = function(msg) traceLog("[ERR] ", msg) end   -- Error loging print
  },

  parseUrl = function(endpointUrl)
    if type(endpointUrl) ~= "string" then
      error("invalid endpointUrl")
    end

    local s,h,p,pt
    s,h = string.match(endpointUrl, "^([%a.]+)://([%w.-]+)$")
    if s == nil then
      s,h,p,pt = string.match(endpointUrl, "^([%a.]+)://([%w.-]+):(%d+)$")
    end
    if s == nil then
      s,h,p,pt = string.match(endpointUrl, "^([%a.]+)://([%w.-]+):(%d+)(/.+)$")
    end
    if s == nil then
      return nil, 0x80830000 -- BadTcpEndpointUrlInvalid
    end

    return {
      scheme = s,
      host = h,
      port = tonumber(p),
      path = pt
    }
  end,

  newFolderParams = function(parentNodeId, browseName, displayName, newNodeId)
    if type(displayName) == "string" then
      displayName = {text=displayName}
    end
    checkCommonAttributes(parentNodeId, browseName, displayName, newNodeId)

    local params = {
      requestedNewNodeId = newNodeId,
      parentNodeId = parentNodeId,
      referenceTypeId = "i=35", --Organizes,
      browseName = browseName,
      nodeClass = 1, -- ua.Types.NodeClass.Object
      displayName = displayName,
      description = displayName,
      writeMask = 0,
      userWriteMask = 0,
      eventNotifier = 0,
      typeDefinition = "i=61", -- FolderType
    }
    return params
  end,

  newVariableParams = function(parentNodeId, browseName, displayName, val, newNodeId)
    if type(displayName) == "string" then
      displayName = {text=displayName}
    end
    checkCommonAttributes(parentNodeId, browseName, displayName, newNodeId)

    if not tools.variantValid(val) then
      error(0x80620000) --BadNodeAttributesInvalid
    end

    local v
    if val.boolean ~= nil then
      v = val.boolean
    elseif val.sbyte ~= nil then
      v = val.sbyte
    elseif val.byte ~= nil then
      v = val.byte
    elseif val.int16 ~= nil then
      v = val.int16
    elseif val.uint16 ~= nil then
      v = val.uint16
    elseif val.int32 ~= nil then
      v = val.int32
    elseif val.uint32 ~= nil then
      v = val.uint32
    elseif val.int64 ~= nil then
      v = val.int64
    elseif val.uint64 ~= nil then
      v = val.uint64
    elseif val.float ~= nil then
      v = val.float
    elseif val.double ~= nil then
      v = val.double
    elseif val.string ~= nil then
      v = val.string
    elseif val.dateTime ~= nil then
      v = val.dateTime
    elseif val.guid ~= nil then
      v = val.guid
    elseif val.byteString ~= nil then
      v = val.byteString
    elseif val.xmlElement ~= nil then
      v = val.xmlElement
    elseif val.nodeId ~= nil then
      v = val.nodeId
    elseif val.expandedNodeId ~= nil then
      v = val.expandedNodeId
    elseif val.statusCode ~= nil then
      v = val.statusCode
    elseif val.qualifiedName ~= nil then
      v = val.qualifiedName
    elseif val.localizedText ~= nil then
      v = val.localizedText
    elseif val.extensionObject ~= nil then
      v = val.extensionObject
    elseif val.dataValue ~= nil then
      v = val.dataValue
    elseif val.variant ~= nil then
      v = val.variant
    elseif val.diagnosticInfo ~= nil then
      v = val.diagnosticInfo
    else
      error("unknown variant type")
    end

    local valueRank
    local arrayDimensions

    if val.byteString and type(v) ~= 'string'then
       if type(v[1]) == 'number' then
          valueRank = -1 -- Scalar
       else
        valueRank = 1 -- OneDimension
        arrayDimensions = {#v}
      end
    else
      if type(v) == 'table' and v[1] ~= nil then
        valueRank = 1 -- OneDimension
        arrayDimensions = {#v}
      else
        valueRank = -1 -- Scalar
      end
    end

    local params = { -- #1
      parentNodeId = parentNodeId,
      referenceTypeId = "i=35", --Organizes,
      requestedNewNodeId = newNodeId,
      browseName = browseName,
      nodeClass = 2, --ua.Types.NodeClass.Variable
      displayName = displayName,
      description = displayName,
      writeMask = 0,
      userWriteMask = 0,
      value = val,
      dataType = tools.getVariantType(val),
      valueRank = valueRank, -- ua.Types.ValueRank.ScalarOrOneDimension
      arrayDimensions = arrayDimensions,
      accessLevel = 0,
      userAccessLevel = 0,
      minimumSamplingInterval = 1000,
      historizing = 0,
      typeDefinition = "i=63", -- BaseDataVariableType
    }

    return params
  end,

  debug = function()
    require("ldbgmon").connect({client=false})
  end
}

return ua
