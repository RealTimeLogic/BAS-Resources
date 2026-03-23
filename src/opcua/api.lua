local version = require("opcua.version")
local const = require("opcua.const")
local tools = require("opcua.tools")

local function versionValid(str)
  return version.Version == str
end

local function assertVersion(str)
  if not versionValid(str) then
    error(string.format("Wrong OPCUA version %s. Requred %s", version.Version, str))
  end
end

local ua = {
  newServer = function(config, model) return require("opcua.server").new(config, model) end,
  newClient = function(config, model) return require("opcua.client").new(config, model) end,
  newMqttClient = function(config, model) return require("opcua.pubsub.mqtt").newClient(config, model) end,
  emptyModel = function(config) return require("opcua.model.import").createModel(config) end,
  baseModel = function(config) return require("opcua.model.import").getBaseModel(config) end,

  Version = version,
  StatusCode = require("opcua.status_codes"),
  NodeId = require("opcua.node_id"),

  crypto = require("opcua.crypto").crypto,
  crypto_engine = require("opcua.crypto").crypto_engine,
  trace = require("opcua.trace"),

  assertVersion = assertVersion,
  versionValid = versionValid,

  IssuedTokenType = const.IssuedTokenType,
  SecurityPolicy = const.SecurityPolicy,
  UserTokenType = const.UserTokenType,
  MessageSecurityMode = const.MessageSecurityMode,
  ApplicationType = const.ApplicationType,
  NodeClass = const.NodeClass,
  AttributeId = const.AttributeId,
  VariantType = const.VariantType,
  DataTypeId = const.DataTypeId,
  ReferenceType = const.ReferenceType,
  ValueRank = const.ValueRank,
  BrowseDirection = const.BrowseDirection,
  BrowseResultMask = const.BrowseResultMask,
  ServerState = const.ServerState,
  TranportProfileUri = const.TranportProfileUri,
  ServerProfile = const.ServerProfile,

  VariableAttributesMask = const.VariableAttributesMask,
  ObjectAttributesMask = const.ObjectAttributesMask,
  DataTypeAttributesMask = const.DataTypeAttributesMask,
  ReferenceAttributesMask = const.ReferenceAttributesMask,
  MethodAttributesMask = const.MethodAttributesMask,
  EventAttributesMask = const.EventAttributesMask,
  PropertyAttributesMask = const.PropertyAttributesMask,

  parseUrl = tools.parseUrl,
  printTable = tools.printTable,
  newVariableParams = tools.newVariableParams,
  newFolderParams = tools.newFolderParams,
  createGuid = tools.createGuid,
  createAnonymousToken = tools.createAnonymousToken,
  createUsernameToken = tools.createUsernameToken,
  createX509Token = tools.createX509Token,
  createIssuedToken = tools.createIssuedToken,
  debug = tools.debug
}

function ua.setCryptoEngine(name)
  if name == "sharkssl" then
    ua.crypto = require("opcua.sharkssl")
  elseif name == "openssl" then
    ua.crypto = require("opcua.openssl")
  else
    error("unsupported crypto engine")
  end
  ua.crypto_engine = name
end

return ua
