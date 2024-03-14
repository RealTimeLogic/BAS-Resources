local t = require("opcua.types_gen")

t.AttributeId = {
  Invalid = 0,
  NodeId = 1,
  NodeClass = 2,
  BrowseName = 3,
  DisplayName = 4,
  Description = 5,
  WriteMask = 6,
  UserWriteMask = 7,
  IsAbstract = 8,
  Symmetric = 9,
  InverseName = 10,
  ContainsNoLoops = 11,
  EventNotifier = 12,
  Value = 13,
  DataType = 14,
  Rank = 15,
  ArrayDimensions = 16,
  AccessLevel = 17,
  UserAccessLevel = 18,
  MinimumSamplingInterval = 19,
  Historizing = 20,
  Executable = 21,
  UserExecutable = 22,
  DataTypeDefinition = 23,
  RolePermissions = 24,
  UserRolePermissions = 25,
  AccessRestrictions = 26,
  AccessLevelEx = 27,
  Max = 27
}

t.SecurityPolicy = {
  None = "http://opcfoundation.org/UA/SecurityPolicy#None",
  Basic128Rsa15 = "http://opcfoundation.org/UA/SecurityPolicy#Basic128Rsa15",
  Aes128_Sha256_RsaOaep = "http://opcfoundation.org/UA/SecurityPolicy#Aes128_Sha256_RsaOaep",
  Basic256Sha256 = "http://opcfoundation.org/UA/SecurityPolicy#Basic256Sha256",
  Aes256_Sha256_RsaPss = "http://opcfoundation.org/UA/SecurityPolicy#Aes256_Sha256_RsaPss",
  PubSub_Aes128_CTR = "http://opcfoundation.org/UA/SecurityPolicy#PubSub-Aes128-CTR",
  PubSub_Aes256_CTR = "http://opcfoundation.org/UA/SecurityPolicy#PubSub-Aes256-CTR"
}

t.TranportProfileUri = {
  TcpBinary = "http://opcfoundation.org/UA-Profile/Transport/uatcp-uasc-uabinary",
  HttpsBinary = "http://opcfoundation.org/UA-Profile/Transport/https-uabinary",
  HttpsJson ="http://opcfoundation.org/UA-Profile/Transport/https-uajson"
}

t.ServerProfile = {
  NanoEmbedded2017 = "http://opcfoundation.org/UA-Profile/Server/NanoEmbeddedDevice2017"
}

t.IssuedTokenType = {
  Azure = "http://opcfoundation.org/UA/UserToken#Azure",
  JWT = "http://opcfoundation.org/UA/Authorization#JWT",
  OAuth2 = "http://opcfoundation.org/UA/Authorization#OAuth2",
  OPCUA = "http://opcfoundation.org/UA/Authorization#OPCUA"
}

t.ValueRank = {
  ScalarOrOneDimension = -3,
  Any = -2,
  Scalar = -1,
  OneOrMoreDimensions = 0,
  OneDimension = 1,
  -- Number of dimensions are valid: 2(matrix),3,4..
}

local m = t.NodeAttributesMask

t.CommonAttributesMask = m.DisplayName | m.Description | m.WriteMask | m.UserWriteMask

t.ObjectAttributesMask = t.CommonAttributesMask | m.EventNotifier

t.ObjectTypeAttributesMask = t.CommonAttributesMask | m.IsAbstract

t.VariableAttributesMask = t.CommonAttributesMask | m.Value |
                           m.DataType | m.ValueRank | m.ArrayDimensions |
                           m.AccessLevel | m.UserAccessLevel | m.MinimumSamplingInterval |
                           m.Historizing

t.VariableTypeAttributesMask = t.CommonAttributesMask | m.Value |
                           m.DataType | m.ValueRank | m.ArrayDimensions | m.IsAbstract

t.MethodAttributesMask = t.CommonAttributesMask | m.Executable | m.UserExecutable

t.ReferenceTypeAttributesMask = t.CommonAttributesMask | m.IsAbstract | m.Symmetric | m.InverseName

t.DataTypeAttributesMask = t.CommonAttributesMask | m.IsAbstract

t.ViewAttributesMask = t.CommonAttributesMask | m.ContainsNoLoops | m.EventNotifier



return t
