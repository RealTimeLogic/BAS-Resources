local tools = require("opcua.binary.tools")
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

local uaVersion = require("opcua.version")

local function versionValid(str)
  return uaVersion.Version == str
end

local function assertVersion(str)
  if not versionValid(str) then
    error(string.format("Wrong OPCUA version %s. Requred %s", uaVersion.Version, str))
  end
end


local ua = {
  newServer = function(config, model) return require("opcua.server").new(config, model) end,
  newClient = function(config, model) return require("opcua.client").new(config, model) end,
  newMqttClient = function(config, model) return require("opcua.pubsub.mqtt").newClient(config, model) end,

  Version = uaVersion,
  StatusCode = require("opcua.status_codes"),
  NodeId = require("opcua.node_id"),

  -- TODO: Types - DEPRECATED. Will be removed in future.
  -- TODO: All fields moved to 'ua' table directly.
  Types = require("opcua.types"),

  Tools = tools,
  Init = require("opcua.init"),

  trace = {
    dbg = function(msg) traceLog("[DBG] ", msg) end,  -- Debug loging print
    inf = function(msg) traceLog("[INF] ", msg) end,  -- Information logging print
    err = function(msg) traceLog("[ERR] ", msg) end   -- Error loging print
  },

  assertVersion = assertVersion,
  versionValid = versionValid,
}

ua.parseUrl = function(endpointUrl)
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
end

ua.newFolderParams = function(parentNodeId, name, newNodeId)
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
    NodeClass = 1, -- ua.NodeClass.Object,
    TypeDefinition = "i=61", -- ids.FolderType,
    NodeAttributes = {
      TypeId = "i=354",
      Body = {
        SpecifiedAttributes = ua.ObjectAttributesMask,
        DisplayName = displayName,
        Description = displayName,
        WriteMask = 0,
        UserWriteMask = 0,
        EventNotifier = 0,
      }
    }
  }

  return params
end

ua.newVariableParams = function(parentNodeId, name, val, newNodeId)
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

  if not tools.dataValueValid(val) then
    error(0x80620000) --BadNodeAttributesInvalid
  end

  local arrayDimensions = val.ArrayDimensions

  local valueRank
  if val.IsArray then
    if arrayDimensions == nil then
      valueRank = 1 -- OneDimension
      arrayDimensions = {#val.Value}
    else
      valueRank = 0 -- Unknown Dimensions
    end
  else
    valueRank = -1 -- Scalar
  end

  local params = {
    ParentNodeId = parentNodeId,
    ReferenceTypeId = "i=35", --Organizes,
    RequestedNewNodeId = newNodeId,
    BrowseName = browseName,
    NodeClass = 2, --ua.NodeClass.Variable,
    TypeDefinition = "i=63", -- ids.BaseDataVariableType,
    NodeAttributes =
    {
      TypeId = "i=355",
      Body = {
        SpecifiedAttributes = ua.VariableAttributesMask,
        DisplayName = displayName,
        Description = displayName,
        WriteMask = 0,
        UserWriteMask = 0,
        Value = val,
        DataType = tools.getVariantTypeId(val),
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
end

ua.createGuid = function()
  local n1 = ba.rnds(4) & 0xFFFF
  local n2 = ba.rnds(4) & 0xFFFF
  local n3 = ba.rnds(4) & 0xFFFF
  local n4 = ba.rnds(4) & 0xFFFF
  local n5 = ba.rnds(4) & 0xFFFF
  local n6 = ba.rnds(4) & 0xFFFF
  local n7 = ba.rnds(4) & 0xFFFF
  -- print(n1,n2,n3,n4,n5,n6)
  local guid <const> =  string.format("%0.8x-%0.4x-%0.4x-%0.4x-%0.4x%0.4x%0.4x",n1,n2,n3,n4,n5,n6,n7)
  -- print(guid)
  return guid
end

ua.debug = function()
  require("ldbgmon").connect({client=false})
end

for key, value in pairs(require("opcua.types")) do
  assert(ua[key] == nil, "type " .. key .. " already defined")
  ua[key] = value
end

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
