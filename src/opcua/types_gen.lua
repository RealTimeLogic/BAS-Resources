--
-- Autogenerate code from xml spec
--


local t = {

--
-- The possible encodings for a NodeId value.
--
NodeIdType = {
  TwoByte = 0,
  FourByte = 1,
  Numeric = 2,
  String = 3,
  Guid = 4,
  ByteString = 5,
},

OpenFileMode = {
  Read = 1,
  Write = 2,
  EraseExisiting = 4,
  Append = 8,
},

--
-- The type of identifier used in a node id.
--
IdType = {
  Numeric = 0,
  String = 1,
  Guid = 2,
  Opaque = 3,
},

--
-- A mask specifying the class of the node.
--
NodeClass = {
  Unspecified = 0,
  Object = 1,
  Variable = 2,
  Method = 4,
  ObjectType = 8,
  VariableType = 16,
  ReferenceType = 32,
  DataType = 64,
  View = 128,
},

--
-- The types of applications.
--
ApplicationType = {
  Server = 0,
  Client = 1,
  ClientAndServer = 2,
  DiscoveryServer = 3,
},

--
-- The type of security to use on a message.
--
MessageSecurityMode = {
  Invalid = 0,
  None = 1,
  Sign = 2,
  SignAndEncrypt = 3,
},

--
-- The possible user token types.
--
UserTokenType = {
  Anonymous = 0,
  UserName = 1,
  Certificate = 2,
  IssuedToken = 3,
},

--
-- Indicates whether a token if being created or renewed.
--
SecurityTokenRequestType = {
  Issue = 0,
  Renew = 1,
},

--
-- The bits used to specify default attributes for a new node.
--
NodeAttributesMask = {
  None = 0,
  AccessLevel = 1,
  ArrayDimensions = 2,
  BrowseName = 4,
  ContainsNoLoops = 8,
  DataType = 16,
  Description = 32,
  DisplayName = 64,
  EventNotifier = 128,
  Executable = 256,
  Historizing = 512,
  InverseName = 1024,
  IsAbstract = 2048,
  MinimumSamplingInterval = 4096,
  NodeClass = 8192,
  NodeId = 16384,
  Symmetric = 32768,
  UserAccessLevel = 65536,
  UserExecutable = 131072,
  UserWriteMask = 262144,
  ValueRank = 524288,
  WriteMask = 1048576,
  Value = 2097152,
  All = 4194303,
  BaseNode = 1335396,
  Object = 1335524,
  ObjectTypeOrDataType = 1337444,
  Variable = 4026999,
  VariableType = 3958902,
  Method = 1466724,
  ReferenceType = 1371236,
  View = 1335532,
},

--
-- Define bits used to indicate which attributes are writeable.
--
AttributeWriteMask = {
  None = 0,
  AccessLevel = 1,
  ArrayDimensions = 2,
  BrowseName = 4,
  ContainsNoLoops = 8,
  DataType = 16,
  Description = 32,
  DisplayName = 64,
  EventNotifier = 128,
  Executable = 256,
  Historizing = 512,
  InverseName = 1024,
  IsAbstract = 2048,
  MinimumSamplingInterval = 4096,
  NodeClass = 8192,
  NodeId = 16384,
  Symmetric = 32768,
  UserAccessLevel = 65536,
  UserExecutable = 131072,
  UserWriteMask = 262144,
  ValueRank = 524288,
  WriteMask = 1048576,
  ValueForVariableType = 2097152,
},

--
-- The directions of the references to return.
--
BrowseDirection = {
  Forward = 0,
  Inverse = 1,
  Both = 2,
},

--
-- A bit mask which specifies what should be returned in a browse response.
--
BrowseResultMask = {
  None = 0,
  ReferenceTypeId = 1,
  IsForward = 2,
  NodeClass = 4,
  BrowseName = 8,
  DisplayName = 16,
  TypeDefinition = 32,
  All = 63,
  ReferenceTypeInfo = 3,
  TargetInfo = 60,
},

ComplianceLevel = {
  Untested = 0,
  Partial = 1,
  SelfTested = 2,
  Certified = 3,
},

FilterOperator = {
  Equals = 0,
  IsNull = 1,
  GreaterThan = 2,
  LessThan = 3,
  GreaterThanOrEqual = 4,
  LessThanOrEqual = 5,
  Like = 6,
  Not = 7,
  Between = 8,
  InList = 9,
  And = 10,
  Or = 11,
  Cast = 12,
  InView = 13,
  OfType = 14,
  RelatedTo = 15,
  BitwiseAnd = 16,
  BitwiseOr = 17,
},

TimestampsToReturn = {
  Source = 0,
  Server = 1,
  Both = 2,
  Neither = 3,
},

HistoryUpdateType = {
  Insert = 1,
  Replace = 2,
  Update = 3,
  Delete = 4,
},

PerformUpdateType = {
  Insert = 1,
  Replace = 2,
  Update = 3,
  Remove = 4,
},

MonitoringMode = {
  Disabled = 0,
  Sampling = 1,
  Reporting = 2,
},

DataChangeTrigger = {
  Status = 0,
  StatusValue = 1,
  StatusValueTimestamp = 2,
},

DeadbandType = {
  None = 0,
  Absolute = 1,
  Percent = 2,
},

--
-- A simple enumerated type used for testing.
--
EnumeratedTestType = {
  Red = 1,
  Yellow = 4,
  Green = 5,
},

RedundancySupport = {
  None = 0,
  Cold = 1,
  Warm = 2,
  Hot = 3,
  Transparent = 4,
  HotAndMirrored = 5,
},

ServerState = {
  Running = 0,
  Failed = 1,
  NoConfiguration = 2,
  Suspended = 3,
  Shutdown = 4,
  Test = 5,
  CommunicationFault = 6,
  Unknown = 7,
},

ModelChangeStructureVerbMask = {
  NodeAdded = 1,
  NodeDeleted = 2,
  ReferenceAdded = 4,
  ReferenceDeleted = 8,
  DataTypeChanged = 16,
},

AxisScaleEnumeration = {
  Linear = 0,
  Log = 1,
  Ln = 2,
},

ExceptionDeviationFormat = {
  AbsoluteValue = 0,
  PercentOfRange = 1,
  PercentOfValue = 2,
  PercentOfEURange = 3,
  Unknown = 4,
},
}
return t
