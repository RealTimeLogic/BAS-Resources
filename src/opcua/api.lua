local tools = require("opcua.binary.tools")
local types = require("opcua.types")
local compat = require("opcua.compat")
local function traceLog(level, msg)
  print(compat.gettime(), level, msg)
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

local function debug()
  require("ldbgmon").connect({client=false})
end


local ua = {
  newServer = function(config, model) return require("opcua.server").new(config, model) end,
  newClient = function(config, model) return require("opcua.client").new(config, model) end,

  Version = require("opcua.version"),
  StatusCode = require("opcua.status_codes"),
  NodeId = require("opcua.node_id"),
  Types = types,
  Tools = tools,
  Init = require("opcua.init"),

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
      s,h,pt = string.match(endpointUrl, "^([%a.]+)://([%w.-]+)(/.*)$")
    end
    if s == nil then
        s,h,p,pt = string.match(endpointUrl, "^([%a.]+)://([%w.-]+):(%d+)$")
    end
    if s == nil then
      s,h,p,pt = string.match(endpointUrl, "^([%a.]+)://([%w.-]+):(%d+)(/.*)$")
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

  newFolderParams = function(parentNodeId, name, newNodeId)
    local displayName
    local browseName
    if type(name) == "table" then
      displayName = name.DisplayName
      browseName = name.BrowseName
    elseif type(name) == "string" then
      displayName = {Text=name}
      browseName = {Name=name, ns=name.ns or 0}
    else
      error(0x80620000) -- BadNodeAttributesInvalid
    end

    checkCommonAttributes(parentNodeId, browseName, displayName, newNodeId)

    local params = {
      RequestedNewNodeId = newNodeId,
      ParentNodeId = parentNodeId,
      ReferenceTypeId = "i=35", --Organizes,
      BrowseName = browseName,
      NodeClass = 1, -- ua.Types.NodeClass.Object,
      TypeDefinition = "i=61", -- ids.FolderType,
      NodeAttributes = {
        TypeId = "i=354",
        Body = {
          SpecifiedAttributes = types.ObjectAttributesMask,
          DisplayName = displayName,
          Description = displayName,
          WriteMask = 0,
          UserWriteMask = 0,
          EventNotifier = 0,
        }
      }
    }

    return params
  end,

  newVariableParams = function(parentNodeId, name, dataValue, newNodeId)
    local displayName
    local browseName
    if type(name) == "table" then
      displayName = name.DisplayName
      browseName = name.BrowseName
    elseif type(name) == "string" then
      displayName = {Text=name}
      browseName = {Name=name, ns=name.ns or 0}
    else
      error(0x80620000) -- BadNodeAttributesInvalid
    end

    checkCommonAttributes(parentNodeId, browseName, displayName, newNodeId)

    if not tools.dataValueValid(dataValue) then
      error(0x80620000) --BadNodeAttributesInvalid
    end

    local val = dataValue.Value
    local v
    if val.Boolean ~= nil then
      v = val.Boolean
    elseif val.SByte ~= nil then
      v = val.SByte
    elseif val.Byte ~= nil then
      v = val.Byte
    elseif val.Int16 ~= nil then
      v = val.Int16
    elseif val.UInt16 ~= nil then
      v = val.UInt16
    elseif val.Int32 ~= nil then
      v = val.Int32
    elseif val.UInt32 ~= nil then
      v = val.UInt32
    elseif val.Int64 ~= nil then
      v = val.Int64
    elseif val.UInt64 ~= nil then
      v = val.UInt64
    elseif val.Float ~= nil then
      v = val.Float
    elseif val.Double ~= nil then
      v = val.Double
    elseif val.String ~= nil then
      v = val.String
    elseif val.DateTime ~= nil then
      v = val.DateTime
    elseif val.Guid ~= nil then
      v = val.Guid
    elseif val.ByteString ~= nil then
      v = val.ByteString
    elseif val.XmlElement ~= nil then
      v = val.XmlElement
    elseif val.NodeId ~= nil then
      v = val.NodeId
    elseif val.ExpandedNodeId ~= nil then
      v = val.ExpandedNodeId
    elseif val.StatusCode ~= nil then
      v = val.StatusCode
    elseif val.QualifiedName ~= nil then
      v = val.QualifiedName
    elseif val.LocalizedText ~= nil then
      v = val.LocalizedText
    elseif val.ExtensionObject ~= nil then
      v = val.ExtensionObject
    elseif val.DataValue ~= nil then
      v = val.DataValue
    elseif val.Variant ~= nil then
      v = val.Variant
    elseif val.DiagnosticInfo ~= nil then
      v = val.DiagnosticInfo
    else
      error("unknown variant type")
    end

    local valueRank
    local arrayDimensions

    if val.ByteString and type(v) ~= 'string'then
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

    local params = {
      ParentNodeId = parentNodeId,
      ReferenceTypeId = "i=35", --Organizes,
      RequestedNewNodeId = newNodeId,
      BrowseName = browseName,
      NodeClass = 2, --ua.Types.NodeClass.Variable,
      TypeDefinition = "i=63", -- ids.BaseDataVariableType,
      NodeAttributes =
      {
        TypeId = "i=355",
        Body = {
          SpecifiedAttributes = types.VariableAttributesMask,
          DisplayName = displayName,
          Description = displayName,
          WriteMask = 0,
          UserWriteMask = 0,
          Value = dataValue,
          DataType = tools.getVariantType(val),
          ValueRank = valueRank,
          ArrayDimensions = arrayDimensions,
          AccessLevel = 0,
          UserAccessLevel = 0,
          MinimumSamplingInterval = 1000,
          Historizing = false,
        }
      }
    }

    return params
  end,

  debug = debug
}

ua.setCryptoEngine = function(crypto_engine)
  if crypto_engine == "sharkssl" then
    ua.crypto_engine = "sharkssl"
    ua.crypto = require("opcua.sharkssl")
  elseif crypto_engine == "openssl" then
    ua.crypto_engine = "openssl"
    ua.crypto = require("opcua.openssl")
  else
    error("unsupported crypto engine")
  end
end

if ba then
  ua.setCryptoEngine("sharkssl")
else
  ua.setCryptoEngine("openssl")
end

return ua
