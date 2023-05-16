local tools = require "opcua.binary.tools"
local tins = table.insert
local enc = require("opcua.binary.encoder")
local dec = require("opcua.binary.decoder")
function enc:nodeIdType(value)
  return self:bit(value, 6);
end
function dec:nodeIdType()
  return self:bit(6)
end
enc.openFileMode = enc.uint32
dec.openFileMode = dec.uint32
enc.idType = enc.uint32
dec.idType = dec.uint32
enc.nodeClass = enc.uint32
dec.nodeClass = dec.uint32
enc.applicationType = enc.uint32
dec.applicationType = dec.uint32
enc.messageSecurityMode = enc.uint32
dec.messageSecurityMode = dec.uint32
enc.userTokenType = enc.uint32
dec.userTokenType = dec.uint32
enc.securityTokenRequestType = enc.uint32
dec.securityTokenRequestType = dec.uint32
enc.nodeAttributesMask = enc.uint32
dec.nodeAttributesMask = dec.uint32
enc.attributeWriteMask = enc.uint32
dec.attributeWriteMask = dec.uint32
enc.browseDirection = enc.uint32
dec.browseDirection = dec.uint32
enc.browseResultMask = enc.uint32
dec.browseResultMask = dec.uint32
enc.complianceLevel = enc.uint32
dec.complianceLevel = dec.uint32
enc.filterOperator = enc.uint32
dec.filterOperator = dec.uint32
enc.timestampsToReturn = enc.uint32
dec.timestampsToReturn = dec.uint32
enc.historyUpdateType = enc.uint32
dec.historyUpdateType = dec.uint32
enc.performUpdateType = enc.uint32
dec.performUpdateType = dec.uint32
enc.monitoringMode = enc.uint32
dec.monitoringMode = dec.uint32
enc.dataChangeTrigger = enc.uint32
dec.dataChangeTrigger = dec.uint32
enc.deadbandType = enc.uint32
dec.deadbandType = dec.uint32
enc.enumeratedTestType = enc.uint32
dec.enumeratedTestType = dec.uint32
enc.redundancySupport = enc.uint32
dec.redundancySupport = dec.uint32
enc.serverState = enc.uint32
dec.serverState = dec.uint32
enc.modelChangeStructureVerbMask = enc.uint32
dec.modelChangeStructureVerbMask = dec.uint32
enc.axisScaleEnumeration = enc.uint32
dec.axisScaleEnumeration = dec.uint32
enc.exceptionDeviationFormat = enc.uint32
dec.exceptionDeviationFormat = dec.uint32
function enc:guid(v)
  self:uint32(v.data1)
  self:uint16(v.data2)
  self:uint16(v.data3)
  self:byte(v.data4)
  self:byte(v.data5)
  self:byte(v.data6)
  self:byte(v.data7)
  self:byte(v.data8)
  self:byte(v.data9)
  self:byte(v.data10)
  self:byte(v.data11)
end
function dec:guid()
  local data1
  local data2
  local data3
  local data4
  local data5
  local data6
  local data7
  local data8
  local data9
  local data10
  local data11
  data1 = self:uint32()
  data2 = self:uint16()
  data3 = self:uint16()
  data4 = self:byte()
  data5 = self:byte()
  data6 = self:byte()
  data7 = self:byte()
  data8 = self:byte()
  data9 = self:byte()
  data10 = self:byte()
  data11 = self:byte()
  return {
    data1 = data1,
    data2 = data2,
    data3 = data3,
    data4 = data4,
    data5 = data5,
    data6 = data6,
    data7 = data7,
    data8 = data8,
    data9 = data9,
    data10 = data10,
    data11 = data11,
  }
end
function enc:xmlElement(v)
  self:int32(v.value ~= nil and #v.value or -1)
  if v.value ~= nil then
    for i = 1, #v.value do
      self:char(tools.index(v.value, i))
    end
  end
end
function dec:xmlElement()
  local length
  local value
  length = self:int32()
  if length ~= -1 then
    value = {}
    for _=1,length do
      local tmp
      tmp = self:char()
      tins(value, tmp)
    end
  end
  return {
    value = tools.makeString(value),
  }
end
function enc:diagnosticInfo(v)
  self:bit(v.symbolicId ~= nil and 1 or 0, 1)
  self:bit(v.namespaceURI ~= nil and 1 or 0, 1)
  self:bit(v.localizedText ~= nil and 1 or 0, 1)
  self:bit(v.locale ~= nil and 1 or 0, 1)
  self:bit(v.additionalInfo ~= nil and 1 or 0, 1)
  self:bit(v.innerStatusCode ~= nil and 1 or 0, 1)
  self:bit(v.innerDiagnosticInfo ~= nil and 1 or 0, 1)
  self:bit(0, 1)
  if v.symbolicId ~= nil then
    self:int32(v.symbolicId)
  end
  if v.namespaceURI ~= nil then
    self:int32(v.namespaceURI)
  end
  if v.locale ~= nil then
    self:int32(v.locale)
  end
  if v.localizedText ~= nil then
    self:int32(v.localizedText)
  end
  if v.additionalInfo ~= nil then
    self:charArray(v.additionalInfo)
  end
  if v.innerStatusCode ~= nil then
    self:statusCode(v.innerStatusCode)
  end
  if v.innerDiagnosticInfo ~= nil then
    self:diagnosticInfo(v.innerDiagnosticInfo)
  end
end
function dec:diagnosticInfo()
  local symbolicIdSpecified
  local namespaceURISpecified
  local localizedTextSpecified
  local localeSpecified
  local additionalInfoSpecified
  local innerStatusCodeSpecified
  local innerDiagnosticInfoSpecified
  local symbolicId
  local namespaceURI
  local locale
  local localizedText
  local additionalInfo
  local innerStatusCode
  local innerDiagnosticInfo
  symbolicIdSpecified = self:bit()
  namespaceURISpecified = self:bit()
  localizedTextSpecified = self:bit()
  localeSpecified = self:bit()
  additionalInfoSpecified = self:bit()
  innerStatusCodeSpecified = self:bit()
  innerDiagnosticInfoSpecified = self:bit()
  self:bit(1)
  if symbolicIdSpecified ~= 0 then
    symbolicId = self:int32()
  end
  if namespaceURISpecified ~= 0 then
    namespaceURI = self:int32()
  end
  if localeSpecified ~= 0 then
    locale = self:int32()
  end
  if localizedTextSpecified ~= 0 then
    localizedText = self:int32()
  end
  if additionalInfoSpecified ~= 0 then
    additionalInfo = self:charArray()
  end
  if innerStatusCodeSpecified ~= 0 then
    innerStatusCode = self:statusCode()
  end
  if innerDiagnosticInfoSpecified ~= 0 then
    innerDiagnosticInfo = self:diagnosticInfo()
  end
  return {
    symbolicId = symbolicId,
    namespaceURI = namespaceURI,
    locale = locale,
    localizedText = localizedText,
    additionalInfo = additionalInfo,
    innerStatusCode = innerStatusCode,
    innerDiagnosticInfo = innerDiagnosticInfo,
  }
end
function enc:qualifiedName(v)
  self:uint16(v.ns)
  self:charArray(v.name)
end
function dec:qualifiedName()
  local ns
  local name
  ns = self:uint16()
  name = self:charArray()
  return {
    ns = ns,
    name = name,
  }
end
function enc:localizedText(v)
  self:bit(v.locale ~= nil and 1 or 0, 1)
  self:bit(v.text ~= nil and 1 or 0, 1)
  self:bit(0, 6)
  if v.locale ~= nil then
    self:charArray(v.locale)
  end
  if v.text ~= nil then
    self:charArray(v.text)
  end
end
function dec:localizedText()
  local localeSpecified
  local textSpecified
  local locale
  local text
  localeSpecified = self:bit()
  textSpecified = self:bit()
  self:bit(6)
  if localeSpecified ~= 0 then
    locale = self:charArray()
  end
  if textSpecified ~= 0 then
    text = self:charArray()
  end
  return {
    locale = locale,
    text = text,
  }
end
function enc:dataValue(v)
  self:bit(v.value ~= nil and 1 or 0, 1)
  self:bit(v.statusCode ~= nil and 1 or 0, 1)
  self:bit(v.sourceTimestamp ~= nil and 1 or 0, 1)
  self:bit(v.serverTimestamp ~= nil and 1 or 0, 1)
  self:bit(v.sourcePicoseconds ~= nil and 1 or 0, 1)
  self:bit(v.serverPicoseconds ~= nil and 1 or 0, 1)
  self:bit(0, 2)
  if v.value ~= nil then
    self:variant(v.value)
  end
  if v.statusCode ~= nil then
    self:statusCode(v.statusCode)
  end
  if v.sourceTimestamp ~= nil then
    self:dateTime(v.sourceTimestamp)
  end
  if v.serverTimestamp ~= nil then
    self:dateTime(v.serverTimestamp)
  end
  if v.sourcePicoseconds ~= nil then
    self:uint16(v.sourcePicoseconds)
  end
  if v.serverPicoseconds ~= nil then
    self:uint16(v.serverPicoseconds)
  end
end
function dec:dataValue()
  local valueSpecified
  local statusCodeSpecified
  local sourceTimestampSpecified
  local serverTimestampSpecified
  local sourcePicosecondsSpecified
  local serverPicosecondsSpecified
  local value
  local statusCode
  local sourceTimestamp
  local serverTimestamp
  local sourcePicoseconds
  local serverPicoseconds
  valueSpecified = self:bit()
  statusCodeSpecified = self:bit()
  sourceTimestampSpecified = self:bit()
  serverTimestampSpecified = self:bit()
  sourcePicosecondsSpecified = self:bit()
  serverPicosecondsSpecified = self:bit()
  self:bit(2)
  if valueSpecified ~= 0 then
    value = self:variant()
  end
  if statusCodeSpecified ~= 0 then
    statusCode = self:statusCode()
  end
  if sourceTimestampSpecified ~= 0 then
    sourceTimestamp = self:dateTime()
  end
  if serverTimestampSpecified ~= 0 then
    serverTimestamp = self:dateTime()
  end
  if sourcePicosecondsSpecified ~= 0 then
    sourcePicoseconds = self:uint16()
  end
  if serverPicosecondsSpecified ~= 0 then
    serverPicoseconds = self:uint16()
  end
  return {
    value = value,
    statusCode = statusCode,
    sourceTimestamp = sourceTimestamp,
    serverTimestamp = serverTimestamp,
    sourcePicoseconds = sourcePicoseconds,
    serverPicoseconds = serverPicoseconds,
  }
end
function enc:referenceNode(v)
  self:nodeId(v.referenceTypeId)
  self:boolean(v.isInverse)
  self:expandedNodeId(v.targetId)
end
function dec:referenceNode()
  local referenceTypeId
  local isInverse
  local targetId
  referenceTypeId = self:nodeId()
  isInverse = self:boolean()
  targetId = self:expandedNodeId()
  return {
    referenceTypeId = referenceTypeId,
    isInverse = isInverse,
    targetId = targetId,
  }
end
function enc:node(v)
  self:nodeId(v.nodeId)
  self:nodeClass(v.nodeClass)
  self:qualifiedName(v.browseName)
  self:localizedText(v.displayName)
  self:localizedText(v.description)
  self:uint32(v.writeMask)
  self:uint32(v.userWriteMask)
  self:int32(v.references ~= nil and #v.references or -1)
  if v.references ~= nil then
    for i = 1, #v.references do
      self:referenceNode(tools.index(v.references, i))
    end
  end
end
function dec:node()
  local nodeId
  local nodeClass
  local browseName
  local displayName
  local description
  local writeMask
  local userWriteMask
  local noOfReferences
  local references
  nodeId = self:nodeId()
  nodeClass = self:nodeClass()
  browseName = self:qualifiedName()
  displayName = self:localizedText()
  description = self:localizedText()
  writeMask = self:uint32()
  userWriteMask = self:uint32()
  noOfReferences = self:int32()
  if noOfReferences ~= -1 then
    references = {}
    for _=1,noOfReferences do
      local tmp
      tmp = self:referenceNode()
      tins(references, tmp)
    end
  end
  return {
    nodeId = nodeId,
    nodeClass = nodeClass,
    browseName = browseName,
    displayName = displayName,
    description = description,
    writeMask = writeMask,
    userWriteMask = userWriteMask,
    references = references,
  }
end
function enc:instanceNode(v)
  self:nodeId(v.nodeId)
  self:nodeClass(v.nodeClass)
  self:qualifiedName(v.browseName)
  self:localizedText(v.displayName)
  self:localizedText(v.description)
  self:uint32(v.writeMask)
  self:uint32(v.userWriteMask)
  self:int32(v.references ~= nil and #v.references or -1)
  if v.references ~= nil then
    for i = 1, #v.references do
      self:referenceNode(tools.index(v.references, i))
    end
  end
end
function dec:instanceNode()
  local nodeId
  local nodeClass
  local browseName
  local displayName
  local description
  local writeMask
  local userWriteMask
  local noOfReferences
  local references
  nodeId = self:nodeId()
  nodeClass = self:nodeClass()
  browseName = self:qualifiedName()
  displayName = self:localizedText()
  description = self:localizedText()
  writeMask = self:uint32()
  userWriteMask = self:uint32()
  noOfReferences = self:int32()
  if noOfReferences ~= -1 then
    references = {}
    for _=1,noOfReferences do
      local tmp
      tmp = self:referenceNode()
      tins(references, tmp)
    end
  end
  return {
    nodeId = nodeId,
    nodeClass = nodeClass,
    browseName = browseName,
    displayName = displayName,
    description = description,
    writeMask = writeMask,
    userWriteMask = userWriteMask,
    references = references,
  }
end
function enc:typeNode(v)
  self:nodeId(v.nodeId)
  self:nodeClass(v.nodeClass)
  self:qualifiedName(v.browseName)
  self:localizedText(v.displayName)
  self:localizedText(v.description)
  self:uint32(v.writeMask)
  self:uint32(v.userWriteMask)
  self:int32(v.references ~= nil and #v.references or -1)
  if v.references ~= nil then
    for i = 1, #v.references do
      self:referenceNode(tools.index(v.references, i))
    end
  end
end
function dec:typeNode()
  local nodeId
  local nodeClass
  local browseName
  local displayName
  local description
  local writeMask
  local userWriteMask
  local noOfReferences
  local references
  nodeId = self:nodeId()
  nodeClass = self:nodeClass()
  browseName = self:qualifiedName()
  displayName = self:localizedText()
  description = self:localizedText()
  writeMask = self:uint32()
  userWriteMask = self:uint32()
  noOfReferences = self:int32()
  if noOfReferences ~= -1 then
    references = {}
    for _=1,noOfReferences do
      local tmp
      tmp = self:referenceNode()
      tins(references, tmp)
    end
  end
  return {
    nodeId = nodeId,
    nodeClass = nodeClass,
    browseName = browseName,
    displayName = displayName,
    description = description,
    writeMask = writeMask,
    userWriteMask = userWriteMask,
    references = references,
  }
end
function enc:objectNode(v)
  self:nodeId(v.nodeId)
  self:nodeClass(v.nodeClass)
  self:qualifiedName(v.browseName)
  self:localizedText(v.displayName)
  self:localizedText(v.description)
  self:uint32(v.writeMask)
  self:uint32(v.userWriteMask)
  self:int32(v.references ~= nil and #v.references or -1)
  if v.references ~= nil then
    for i = 1, #v.references do
      self:referenceNode(tools.index(v.references, i))
    end
  end
  self:byte(v.eventNotifier)
end
function dec:objectNode()
  local nodeId
  local nodeClass
  local browseName
  local displayName
  local description
  local writeMask
  local userWriteMask
  local noOfReferences
  local references
  local eventNotifier
  nodeId = self:nodeId()
  nodeClass = self:nodeClass()
  browseName = self:qualifiedName()
  displayName = self:localizedText()
  description = self:localizedText()
  writeMask = self:uint32()
  userWriteMask = self:uint32()
  noOfReferences = self:int32()
  if noOfReferences ~= -1 then
    references = {}
    for _=1,noOfReferences do
      local tmp
      tmp = self:referenceNode()
      tins(references, tmp)
    end
  end
  eventNotifier = self:byte()
  return {
    nodeId = nodeId,
    nodeClass = nodeClass,
    browseName = browseName,
    displayName = displayName,
    description = description,
    writeMask = writeMask,
    userWriteMask = userWriteMask,
    references = references,
    eventNotifier = eventNotifier,
  }
end
function enc:objectTypeNode(v)
  self:nodeId(v.nodeId)
  self:nodeClass(v.nodeClass)
  self:qualifiedName(v.browseName)
  self:localizedText(v.displayName)
  self:localizedText(v.description)
  self:uint32(v.writeMask)
  self:uint32(v.userWriteMask)
  self:int32(v.references ~= nil and #v.references or -1)
  if v.references ~= nil then
    for i = 1, #v.references do
      self:referenceNode(tools.index(v.references, i))
    end
  end
  self:boolean(v.isAbstract)
end
function dec:objectTypeNode()
  local nodeId
  local nodeClass
  local browseName
  local displayName
  local description
  local writeMask
  local userWriteMask
  local noOfReferences
  local references
  local isAbstract
  nodeId = self:nodeId()
  nodeClass = self:nodeClass()
  browseName = self:qualifiedName()
  displayName = self:localizedText()
  description = self:localizedText()
  writeMask = self:uint32()
  userWriteMask = self:uint32()
  noOfReferences = self:int32()
  if noOfReferences ~= -1 then
    references = {}
    for _=1,noOfReferences do
      local tmp
      tmp = self:referenceNode()
      tins(references, tmp)
    end
  end
  isAbstract = self:boolean()
  return {
    nodeId = nodeId,
    nodeClass = nodeClass,
    browseName = browseName,
    displayName = displayName,
    description = description,
    writeMask = writeMask,
    userWriteMask = userWriteMask,
    references = references,
    isAbstract = isAbstract,
  }
end
function enc:variableNode(v)
  self:nodeId(v.nodeId)
  self:nodeClass(v.nodeClass)
  self:qualifiedName(v.browseName)
  self:localizedText(v.displayName)
  self:localizedText(v.description)
  self:uint32(v.writeMask)
  self:uint32(v.userWriteMask)
  self:int32(v.references ~= nil and #v.references or -1)
  if v.references ~= nil then
    for i = 1, #v.references do
      self:referenceNode(tools.index(v.references, i))
    end
  end
  self:variant(v.value)
  self:nodeId(v.dataType)
  self:int32(v.valueRank)
  self:int32(v.arrayDimensions ~= nil and #v.arrayDimensions or -1)
  if v.arrayDimensions ~= nil then
    for i = 1, #v.arrayDimensions do
      self:uint32(tools.index(v.arrayDimensions, i))
    end
  end
  self:byte(v.accessLevel)
  self:byte(v.userAccessLevel)
  self:double(v.minimumSamplingInterval)
  self:boolean(v.historizing)
end
function dec:variableNode()
  local nodeId
  local nodeClass
  local browseName
  local displayName
  local description
  local writeMask
  local userWriteMask
  local noOfReferences
  local references
  local value
  local dataType
  local valueRank
  local noOfArrayDimensions
  local arrayDimensions
  local accessLevel
  local userAccessLevel
  local minimumSamplingInterval
  local historizing
  nodeId = self:nodeId()
  nodeClass = self:nodeClass()
  browseName = self:qualifiedName()
  displayName = self:localizedText()
  description = self:localizedText()
  writeMask = self:uint32()
  userWriteMask = self:uint32()
  noOfReferences = self:int32()
  if noOfReferences ~= -1 then
    references = {}
    for _=1,noOfReferences do
      local tmp
      tmp = self:referenceNode()
      tins(references, tmp)
    end
  end
  value = self:variant()
  dataType = self:nodeId()
  valueRank = self:int32()
  noOfArrayDimensions = self:int32()
  if noOfArrayDimensions ~= -1 then
    arrayDimensions = {}
    for _=1,noOfArrayDimensions do
      local tmp
      tmp = self:uint32()
      tins(arrayDimensions, tmp)
    end
  end
  accessLevel = self:byte()
  userAccessLevel = self:byte()
  minimumSamplingInterval = self:double()
  historizing = self:boolean()
  return {
    nodeId = nodeId,
    nodeClass = nodeClass,
    browseName = browseName,
    displayName = displayName,
    description = description,
    writeMask = writeMask,
    userWriteMask = userWriteMask,
    references = references,
    value = value,
    dataType = dataType,
    valueRank = valueRank,
    arrayDimensions = arrayDimensions,
    accessLevel = accessLevel,
    userAccessLevel = userAccessLevel,
    minimumSamplingInterval = minimumSamplingInterval,
    historizing = historizing,
  }
end
function enc:variableTypeNode(v)
  self:nodeId(v.nodeId)
  self:nodeClass(v.nodeClass)
  self:qualifiedName(v.browseName)
  self:localizedText(v.displayName)
  self:localizedText(v.description)
  self:uint32(v.writeMask)
  self:uint32(v.userWriteMask)
  self:int32(v.references ~= nil and #v.references or -1)
  if v.references ~= nil then
    for i = 1, #v.references do
      self:referenceNode(tools.index(v.references, i))
    end
  end
  self:variant(v.value)
  self:nodeId(v.dataType)
  self:int32(v.valueRank)
  self:int32(v.arrayDimensions ~= nil and #v.arrayDimensions or -1)
  if v.arrayDimensions ~= nil then
    for i = 1, #v.arrayDimensions do
      self:uint32(tools.index(v.arrayDimensions, i))
    end
  end
  self:boolean(v.isAbstract)
end
function dec:variableTypeNode()
  local nodeId
  local nodeClass
  local browseName
  local displayName
  local description
  local writeMask
  local userWriteMask
  local noOfReferences
  local references
  local value
  local dataType
  local valueRank
  local noOfArrayDimensions
  local arrayDimensions
  local isAbstract
  nodeId = self:nodeId()
  nodeClass = self:nodeClass()
  browseName = self:qualifiedName()
  displayName = self:localizedText()
  description = self:localizedText()
  writeMask = self:uint32()
  userWriteMask = self:uint32()
  noOfReferences = self:int32()
  if noOfReferences ~= -1 then
    references = {}
    for _=1,noOfReferences do
      local tmp
      tmp = self:referenceNode()
      tins(references, tmp)
    end
  end
  value = self:variant()
  dataType = self:nodeId()
  valueRank = self:int32()
  noOfArrayDimensions = self:int32()
  if noOfArrayDimensions ~= -1 then
    arrayDimensions = {}
    for _=1,noOfArrayDimensions do
      local tmp
      tmp = self:uint32()
      tins(arrayDimensions, tmp)
    end
  end
  isAbstract = self:boolean()
  return {
    nodeId = nodeId,
    nodeClass = nodeClass,
    browseName = browseName,
    displayName = displayName,
    description = description,
    writeMask = writeMask,
    userWriteMask = userWriteMask,
    references = references,
    value = value,
    dataType = dataType,
    valueRank = valueRank,
    arrayDimensions = arrayDimensions,
    isAbstract = isAbstract,
  }
end
function enc:referenceTypeNode(v)
  self:nodeId(v.nodeId)
  self:nodeClass(v.nodeClass)
  self:qualifiedName(v.browseName)
  self:localizedText(v.displayName)
  self:localizedText(v.description)
  self:uint32(v.writeMask)
  self:uint32(v.userWriteMask)
  self:int32(v.references ~= nil and #v.references or -1)
  if v.references ~= nil then
    for i = 1, #v.references do
      self:referenceNode(tools.index(v.references, i))
    end
  end
  self:boolean(v.isAbstract)
  self:boolean(v.symmetric)
  self:localizedText(v.inverseName)
end
function dec:referenceTypeNode()
  local nodeId
  local nodeClass
  local browseName
  local displayName
  local description
  local writeMask
  local userWriteMask
  local noOfReferences
  local references
  local isAbstract
  local symmetric
  local inverseName
  nodeId = self:nodeId()
  nodeClass = self:nodeClass()
  browseName = self:qualifiedName()
  displayName = self:localizedText()
  description = self:localizedText()
  writeMask = self:uint32()
  userWriteMask = self:uint32()
  noOfReferences = self:int32()
  if noOfReferences ~= -1 then
    references = {}
    for _=1,noOfReferences do
      local tmp
      tmp = self:referenceNode()
      tins(references, tmp)
    end
  end
  isAbstract = self:boolean()
  symmetric = self:boolean()
  inverseName = self:localizedText()
  return {
    nodeId = nodeId,
    nodeClass = nodeClass,
    browseName = browseName,
    displayName = displayName,
    description = description,
    writeMask = writeMask,
    userWriteMask = userWriteMask,
    references = references,
    isAbstract = isAbstract,
    symmetric = symmetric,
    inverseName = inverseName,
  }
end
function enc:methodNode(v)
  self:nodeId(v.nodeId)
  self:nodeClass(v.nodeClass)
  self:qualifiedName(v.browseName)
  self:localizedText(v.displayName)
  self:localizedText(v.description)
  self:uint32(v.writeMask)
  self:uint32(v.userWriteMask)
  self:int32(v.references ~= nil and #v.references or -1)
  if v.references ~= nil then
    for i = 1, #v.references do
      self:referenceNode(tools.index(v.references, i))
    end
  end
  self:boolean(v.executable)
  self:boolean(v.userExecutable)
end
function dec:methodNode()
  local nodeId
  local nodeClass
  local browseName
  local displayName
  local description
  local writeMask
  local userWriteMask
  local noOfReferences
  local references
  local executable
  local userExecutable
  nodeId = self:nodeId()
  nodeClass = self:nodeClass()
  browseName = self:qualifiedName()
  displayName = self:localizedText()
  description = self:localizedText()
  writeMask = self:uint32()
  userWriteMask = self:uint32()
  noOfReferences = self:int32()
  if noOfReferences ~= -1 then
    references = {}
    for _=1,noOfReferences do
      local tmp
      tmp = self:referenceNode()
      tins(references, tmp)
    end
  end
  executable = self:boolean()
  userExecutable = self:boolean()
  return {
    nodeId = nodeId,
    nodeClass = nodeClass,
    browseName = browseName,
    displayName = displayName,
    description = description,
    writeMask = writeMask,
    userWriteMask = userWriteMask,
    references = references,
    executable = executable,
    userExecutable = userExecutable,
  }
end
function enc:viewNode(v)
  self:nodeId(v.nodeId)
  self:nodeClass(v.nodeClass)
  self:qualifiedName(v.browseName)
  self:localizedText(v.displayName)
  self:localizedText(v.description)
  self:uint32(v.writeMask)
  self:uint32(v.userWriteMask)
  self:int32(v.references ~= nil and #v.references or -1)
  if v.references ~= nil then
    for i = 1, #v.references do
      self:referenceNode(tools.index(v.references, i))
    end
  end
  self:boolean(v.containsNoLoops)
  self:byte(v.eventNotifier)
end
function dec:viewNode()
  local nodeId
  local nodeClass
  local browseName
  local displayName
  local description
  local writeMask
  local userWriteMask
  local noOfReferences
  local references
  local containsNoLoops
  local eventNotifier
  nodeId = self:nodeId()
  nodeClass = self:nodeClass()
  browseName = self:qualifiedName()
  displayName = self:localizedText()
  description = self:localizedText()
  writeMask = self:uint32()
  userWriteMask = self:uint32()
  noOfReferences = self:int32()
  if noOfReferences ~= -1 then
    references = {}
    for _=1,noOfReferences do
      local tmp
      tmp = self:referenceNode()
      tins(references, tmp)
    end
  end
  containsNoLoops = self:boolean()
  eventNotifier = self:byte()
  return {
    nodeId = nodeId,
    nodeClass = nodeClass,
    browseName = browseName,
    displayName = displayName,
    description = description,
    writeMask = writeMask,
    userWriteMask = userWriteMask,
    references = references,
    containsNoLoops = containsNoLoops,
    eventNotifier = eventNotifier,
  }
end
function enc:dataTypeNode(v)
  self:nodeId(v.nodeId)
  self:nodeClass(v.nodeClass)
  self:qualifiedName(v.browseName)
  self:localizedText(v.displayName)
  self:localizedText(v.description)
  self:uint32(v.writeMask)
  self:uint32(v.userWriteMask)
  self:int32(v.references ~= nil and #v.references or -1)
  if v.references ~= nil then
    for i = 1, #v.references do
      self:referenceNode(tools.index(v.references, i))
    end
  end
  self:boolean(v.isAbstract)
end
function dec:dataTypeNode()
  local nodeId
  local nodeClass
  local browseName
  local displayName
  local description
  local writeMask
  local userWriteMask
  local noOfReferences
  local references
  local isAbstract
  nodeId = self:nodeId()
  nodeClass = self:nodeClass()
  browseName = self:qualifiedName()
  displayName = self:localizedText()
  description = self:localizedText()
  writeMask = self:uint32()
  userWriteMask = self:uint32()
  noOfReferences = self:int32()
  if noOfReferences ~= -1 then
    references = {}
    for _=1,noOfReferences do
      local tmp
      tmp = self:referenceNode()
      tins(references, tmp)
    end
  end
  isAbstract = self:boolean()
  return {
    nodeId = nodeId,
    nodeClass = nodeClass,
    browseName = browseName,
    displayName = displayName,
    description = description,
    writeMask = writeMask,
    userWriteMask = userWriteMask,
    references = references,
    isAbstract = isAbstract,
  }
end
function enc:argument(v)
  self:string(v.name)
  self:nodeId(v.dataType)
  self:int32(v.valueRank)
  self:int32(v.arrayDimensions ~= nil and #v.arrayDimensions or -1)
  if v.arrayDimensions ~= nil then
    for i = 1, #v.arrayDimensions do
      self:uint32(tools.index(v.arrayDimensions, i))
    end
  end
  self:localizedText(v.description)
end
function dec:argument()
  local name
  local dataType
  local valueRank
  local noOfArrayDimensions
  local arrayDimensions
  local description
  name = self:string()
  dataType = self:nodeId()
  valueRank = self:int32()
  noOfArrayDimensions = self:int32()
  if noOfArrayDimensions ~= -1 then
    arrayDimensions = {}
    for _=1,noOfArrayDimensions do
      local tmp
      tmp = self:uint32()
      tins(arrayDimensions, tmp)
    end
  end
  description = self:localizedText()
  return {
    name = name,
    dataType = dataType,
    valueRank = valueRank,
    arrayDimensions = arrayDimensions,
    description = description,
  }
end
function enc:enumValueType(v)
  self:int64(v.value)
  self:localizedText(v.displayName)
  self:localizedText(v.description)
end
function dec:enumValueType()
  local value
  local displayName
  local description
  value = self:int64()
  displayName = self:localizedText()
  description = self:localizedText()
  return {
    value = value,
    displayName = displayName,
    description = description,
  }
end
function enc:timeZoneDataType(v)
  self:int16(v.offset)
  self:boolean(v.daylightSavingInOffset)
end
function dec:timeZoneDataType()
  local offset
  local daylightSavingInOffset
  offset = self:int16()
  daylightSavingInOffset = self:boolean()
  return {
    offset = offset,
    daylightSavingInOffset = daylightSavingInOffset,
  }
end
function enc:applicationDescription(v)
  self:string(v.applicationUri)
  self:string(v.productUri)
  self:localizedText(v.applicationName)
  self:applicationType(v.applicationType)
  self:string(v.gatewayServerUri)
  self:string(v.discoveryProfileUri)
  self:int32(v.discoveryUrls ~= nil and #v.discoveryUrls or -1)
  if v.discoveryUrls ~= nil then
    for i = 1, #v.discoveryUrls do
      self:string(tools.index(v.discoveryUrls, i))
    end
  end
end
function dec:applicationDescription()
  local applicationUri
  local productUri
  local applicationName
  local applicationType
  local gatewayServerUri
  local discoveryProfileUri
  local noOfDiscoveryUrls
  local discoveryUrls
  applicationUri = self:string()
  productUri = self:string()
  applicationName = self:localizedText()
  applicationType = self:applicationType()
  gatewayServerUri = self:string()
  discoveryProfileUri = self:string()
  noOfDiscoveryUrls = self:int32()
  if noOfDiscoveryUrls ~= -1 then
    discoveryUrls = {}
    for _=1,noOfDiscoveryUrls do
      local tmp
      tmp = self:string()
      tins(discoveryUrls, tmp)
    end
  end
  return {
    applicationUri = applicationUri,
    productUri = productUri,
    applicationName = applicationName,
    applicationType = applicationType,
    gatewayServerUri = gatewayServerUri,
    discoveryProfileUri = discoveryProfileUri,
    discoveryUrls = discoveryUrls,
  }
end
function enc:requestHeader(v)
  self:nodeId(v.authenticationToken)
  self:dateTime(v.timestamp)
  self:uint32(v.requestHandle)
  self:uint32(v.returnDiagnostics)
  self:string(v.auditEntryId)
  self:uint32(v.timeoutHint)
  self:extensionObject(v.additionalHeader)
end
function dec:requestHeader()
  local authenticationToken
  local timestamp
  local requestHandle
  local returnDiagnostics
  local auditEntryId
  local timeoutHint
  local additionalHeader
  authenticationToken = self:nodeId()
  timestamp = self:dateTime()
  requestHandle = self:uint32()
  returnDiagnostics = self:uint32()
  auditEntryId = self:string()
  timeoutHint = self:uint32()
  additionalHeader = self:extensionObject()
  return {
    authenticationToken = authenticationToken,
    timestamp = timestamp,
    requestHandle = requestHandle,
    returnDiagnostics = returnDiagnostics,
    auditEntryId = auditEntryId,
    timeoutHint = timeoutHint,
    additionalHeader = additionalHeader,
  }
end
function enc:responseHeader(v)
  self:dateTime(v.timestamp)
  self:uint32(v.requestHandle)
  self:statusCode(v.serviceResult)
  self:diagnosticInfo(v.serviceDiagnostics)
  self:int32(v.stringTable ~= nil and #v.stringTable or -1)
  if v.stringTable ~= nil then
    for i = 1, #v.stringTable do
      self:string(tools.index(v.stringTable, i))
    end
  end
  self:extensionObject(v.additionalHeader)
end
function dec:responseHeader()
  local timestamp
  local requestHandle
  local serviceResult
  local serviceDiagnostics
  local noOfStringTable
  local stringTable
  local additionalHeader
  timestamp = self:dateTime()
  requestHandle = self:uint32()
  serviceResult = self:statusCode()
  serviceDiagnostics = self:diagnosticInfo()
  noOfStringTable = self:int32()
  if noOfStringTable ~= -1 then
    stringTable = {}
    for _=1,noOfStringTable do
      local tmp
      tmp = self:string()
      tins(stringTable, tmp)
    end
  end
  additionalHeader = self:extensionObject()
  return {
    timestamp = timestamp,
    requestHandle = requestHandle,
    serviceResult = serviceResult,
    serviceDiagnostics = serviceDiagnostics,
    stringTable = stringTable,
    additionalHeader = additionalHeader,
  }
end
function enc:serviceFault(v)
  self:responseHeader(v.responseHeader)
end
function dec:serviceFault()
  local responseHeader
  responseHeader = self:responseHeader()
  return {
    responseHeader = responseHeader,
  }
end
function enc:findServersRequest(v)
  self:requestHeader(v.requestHeader)
  self:string(v.endpointUrl)
  self:int32(v.localeIds ~= nil and #v.localeIds or -1)
  if v.localeIds ~= nil then
    for i = 1, #v.localeIds do
      self:string(tools.index(v.localeIds, i))
    end
  end
  self:int32(v.serverUris ~= nil and #v.serverUris or -1)
  if v.serverUris ~= nil then
    for i = 1, #v.serverUris do
      self:string(tools.index(v.serverUris, i))
    end
  end
end
function dec:findServersRequest()
  local requestHeader
  local endpointUrl
  local noOfLocaleIds
  local localeIds
  local noOfServerUris
  local serverUris
  requestHeader = self:requestHeader()
  endpointUrl = self:string()
  noOfLocaleIds = self:int32()
  if noOfLocaleIds ~= -1 then
    localeIds = {}
    for _=1,noOfLocaleIds do
      local tmp
      tmp = self:string()
      tins(localeIds, tmp)
    end
  end
  noOfServerUris = self:int32()
  if noOfServerUris ~= -1 then
    serverUris = {}
    for _=1,noOfServerUris do
      local tmp
      tmp = self:string()
      tins(serverUris, tmp)
    end
  end
  return {
    requestHeader = requestHeader,
    endpointUrl = endpointUrl,
    localeIds = localeIds,
    serverUris = serverUris,
  }
end
function enc:findServersResponse(v)
  self:responseHeader(v.responseHeader)
  self:int32(v.servers ~= nil and #v.servers or -1)
  if v.servers ~= nil then
    for i = 1, #v.servers do
      self:applicationDescription(tools.index(v.servers, i))
    end
  end
end
function dec:findServersResponse()
  local responseHeader
  local noOfServers
  local servers
  responseHeader = self:responseHeader()
  noOfServers = self:int32()
  if noOfServers ~= -1 then
    servers = {}
    for _=1,noOfServers do
      local tmp
      tmp = self:applicationDescription()
      tins(servers, tmp)
    end
  end
  return {
    responseHeader = responseHeader,
    servers = servers,
  }
end
function enc:userTokenPolicy(v)
  self:string(v.policyId)
  self:userTokenType(v.tokenType)
  self:string(v.issuedTokenType)
  self:string(v.issuerEndpointUrl)
  self:string(v.securityPolicyUri)
end
function dec:userTokenPolicy()
  local policyId
  local tokenType
  local issuedTokenType
  local issuerEndpointUrl
  local securityPolicyUri
  policyId = self:string()
  tokenType = self:userTokenType()
  issuedTokenType = self:string()
  issuerEndpointUrl = self:string()
  securityPolicyUri = self:string()
  return {
    policyId = policyId,
    tokenType = tokenType,
    issuedTokenType = issuedTokenType,
    issuerEndpointUrl = issuerEndpointUrl,
    securityPolicyUri = securityPolicyUri,
  }
end
function enc:endpointDescription(v)
  self:string(v.endpointUrl)
  self:applicationDescription(v.server)
  self:byteString(v.serverCertificate)
  self:messageSecurityMode(v.securityMode)
  self:string(v.securityPolicyUri)
  self:int32(v.userIdentityTokens ~= nil and #v.userIdentityTokens or -1)
  if v.userIdentityTokens ~= nil then
    for i = 1, #v.userIdentityTokens do
      self:userTokenPolicy(tools.index(v.userIdentityTokens, i))
    end
  end
  self:string(v.transportProfileUri)
  self:byte(v.securityLevel)
end
function dec:endpointDescription()
  local endpointUrl
  local server
  local serverCertificate
  local securityMode
  local securityPolicyUri
  local noOfUserIdentityTokens
  local userIdentityTokens
  local transportProfileUri
  local securityLevel
  endpointUrl = self:string()
  server = self:applicationDescription()
  serverCertificate = self:byteString()
  securityMode = self:messageSecurityMode()
  securityPolicyUri = self:string()
  noOfUserIdentityTokens = self:int32()
  if noOfUserIdentityTokens ~= -1 then
    userIdentityTokens = {}
    for _=1,noOfUserIdentityTokens do
      local tmp
      tmp = self:userTokenPolicy()
      tins(userIdentityTokens, tmp)
    end
  end
  transportProfileUri = self:string()
  securityLevel = self:byte()
  return {
    endpointUrl = endpointUrl,
    server = server,
    serverCertificate = serverCertificate,
    securityMode = securityMode,
    securityPolicyUri = securityPolicyUri,
    userIdentityTokens = userIdentityTokens,
    transportProfileUri = transportProfileUri,
    securityLevel = securityLevel,
  }
end
function enc:getEndpointsRequest(v)
  self:requestHeader(v.requestHeader)
  self:string(v.endpointUrl)
  self:int32(v.localeIds ~= nil and #v.localeIds or -1)
  if v.localeIds ~= nil then
    for i = 1, #v.localeIds do
      self:string(tools.index(v.localeIds, i))
    end
  end
  self:int32(v.profileUris ~= nil and #v.profileUris or -1)
  if v.profileUris ~= nil then
    for i = 1, #v.profileUris do
      self:string(tools.index(v.profileUris, i))
    end
  end
end
function dec:getEndpointsRequest()
  local requestHeader
  local endpointUrl
  local noOfLocaleIds
  local localeIds
  local noOfProfileUris
  local profileUris
  requestHeader = self:requestHeader()
  endpointUrl = self:string()
  noOfLocaleIds = self:int32()
  if noOfLocaleIds ~= -1 then
    localeIds = {}
    for _=1,noOfLocaleIds do
      local tmp
      tmp = self:string()
      tins(localeIds, tmp)
    end
  end
  noOfProfileUris = self:int32()
  if noOfProfileUris ~= -1 then
    profileUris = {}
    for _=1,noOfProfileUris do
      local tmp
      tmp = self:string()
      tins(profileUris, tmp)
    end
  end
  return {
    requestHeader = requestHeader,
    endpointUrl = endpointUrl,
    localeIds = localeIds,
    profileUris = profileUris,
  }
end
function enc:getEndpointsResponse(v)
  self:responseHeader(v.responseHeader)
  self:int32(v.endpoints ~= nil and #v.endpoints or -1)
  if v.endpoints ~= nil then
    for i = 1, #v.endpoints do
      self:endpointDescription(tools.index(v.endpoints, i))
    end
  end
end
function dec:getEndpointsResponse()
  local responseHeader
  local noOfEndpoints
  local endpoints
  responseHeader = self:responseHeader()
  noOfEndpoints = self:int32()
  if noOfEndpoints ~= -1 then
    endpoints = {}
    for _=1,noOfEndpoints do
      local tmp
      tmp = self:endpointDescription()
      tins(endpoints, tmp)
    end
  end
  return {
    responseHeader = responseHeader,
    endpoints = endpoints,
  }
end
function enc:registeredServer(v)
  self:string(v.serverUri)
  self:string(v.productUri)
  self:int32(v.serverNames ~= nil and #v.serverNames or -1)
  if v.serverNames ~= nil then
    for i = 1, #v.serverNames do
      self:localizedText(tools.index(v.serverNames, i))
    end
  end
  self:applicationType(v.serverType)
  self:string(v.gatewayServerUri)
  self:int32(v.discoveryUrls ~= nil and #v.discoveryUrls or -1)
  if v.discoveryUrls ~= nil then
    for i = 1, #v.discoveryUrls do
      self:string(tools.index(v.discoveryUrls, i))
    end
  end
  self:string(v.semaphoreFilePath)
  self:boolean(v.isOnline)
end
function dec:registeredServer()
  local serverUri
  local productUri
  local noOfServerNames
  local serverNames
  local serverType
  local gatewayServerUri
  local noOfDiscoveryUrls
  local discoveryUrls
  local semaphoreFilePath
  local isOnline
  serverUri = self:string()
  productUri = self:string()
  noOfServerNames = self:int32()
  if noOfServerNames ~= -1 then
    serverNames = {}
    for _=1,noOfServerNames do
      local tmp
      tmp = self:localizedText()
      tins(serverNames, tmp)
    end
  end
  serverType = self:applicationType()
  gatewayServerUri = self:string()
  noOfDiscoveryUrls = self:int32()
  if noOfDiscoveryUrls ~= -1 then
    discoveryUrls = {}
    for _=1,noOfDiscoveryUrls do
      local tmp
      tmp = self:string()
      tins(discoveryUrls, tmp)
    end
  end
  semaphoreFilePath = self:string()
  isOnline = self:boolean()
  return {
    serverUri = serverUri,
    productUri = productUri,
    serverNames = serverNames,
    serverType = serverType,
    gatewayServerUri = gatewayServerUri,
    discoveryUrls = discoveryUrls,
    semaphoreFilePath = semaphoreFilePath,
    isOnline = isOnline,
  }
end
function enc:registerServerRequest(v)
  self:requestHeader(v.requestHeader)
  self:registeredServer(v.server)
end
function dec:registerServerRequest()
  local requestHeader
  local server
  requestHeader = self:requestHeader()
  server = self:registeredServer()
  return {
    requestHeader = requestHeader,
    server = server,
  }
end
function enc:registerServerResponse(v)
  self:responseHeader(v.responseHeader)
end
function dec:registerServerResponse()
  local responseHeader
  responseHeader = self:responseHeader()
  return {
    responseHeader = responseHeader,
  }
end
function enc:channelSecurityToken(v)
  self:uint32(v.channelId)
  self:uint32(v.tokenId)
  self:dateTime(v.createdAt)
  self:uint32(v.revisedLifetime)
end
function dec:channelSecurityToken()
  local channelId
  local tokenId
  local createdAt
  local revisedLifetime
  channelId = self:uint32()
  tokenId = self:uint32()
  createdAt = self:dateTime()
  revisedLifetime = self:uint32()
  return {
    channelId = channelId,
    tokenId = tokenId,
    createdAt = createdAt,
    revisedLifetime = revisedLifetime,
  }
end
function enc:openSecureChannelRequest(v)
  self:requestHeader(v.requestHeader)
  self:uint32(v.clientProtocolVersion)
  self:securityTokenRequestType(v.requestType)
  self:messageSecurityMode(v.securityMode)
  self:byteString(v.clientNonce)
  self:uint32(v.requestedLifetime)
end
function dec:openSecureChannelRequest()
  local requestHeader
  local clientProtocolVersion
  local requestType
  local securityMode
  local clientNonce
  local requestedLifetime
  requestHeader = self:requestHeader()
  clientProtocolVersion = self:uint32()
  requestType = self:securityTokenRequestType()
  securityMode = self:messageSecurityMode()
  clientNonce = self:byteString()
  requestedLifetime = self:uint32()
  return {
    requestHeader = requestHeader,
    clientProtocolVersion = clientProtocolVersion,
    requestType = requestType,
    securityMode = securityMode,
    clientNonce = clientNonce,
    requestedLifetime = requestedLifetime,
  }
end
function enc:openSecureChannelResponse(v)
  self:responseHeader(v.responseHeader)
  self:uint32(v.serverProtocolVersion)
  self:channelSecurityToken(v.securityToken)
  self:byteString(v.serverNonce)
end
function dec:openSecureChannelResponse()
  local responseHeader
  local serverProtocolVersion
  local securityToken
  local serverNonce
  responseHeader = self:responseHeader()
  serverProtocolVersion = self:uint32()
  securityToken = self:channelSecurityToken()
  serverNonce = self:byteString()
  return {
    responseHeader = responseHeader,
    serverProtocolVersion = serverProtocolVersion,
    securityToken = securityToken,
    serverNonce = serverNonce,
  }
end
function enc:closeSecureChannelRequest(v)
  self:requestHeader(v.requestHeader)
end
function dec:closeSecureChannelRequest()
  local requestHeader
  requestHeader = self:requestHeader()
  return {
    requestHeader = requestHeader,
  }
end
function enc:closeSecureChannelResponse(v)
  self:responseHeader(v.responseHeader)
end
function dec:closeSecureChannelResponse()
  local responseHeader
  responseHeader = self:responseHeader()
  return {
    responseHeader = responseHeader,
  }
end
function enc:signedSoftwareCertificate(v)
  self:byteString(v.certificateData)
  self:byteString(v.signature)
end
function dec:signedSoftwareCertificate()
  local certificateData
  local signature
  certificateData = self:byteString()
  signature = self:byteString()
  return {
    certificateData = certificateData,
    signature = signature,
  }
end
function enc:signatureData(v)
  self:string(v.algorithm)
  self:byteString(v.signature)
end
function dec:signatureData()
  local algorithm
  local signature
  algorithm = self:string()
  signature = self:byteString()
  return {
    algorithm = algorithm,
    signature = signature,
  }
end
function enc:createSessionRequest(v)
  self:requestHeader(v.requestHeader)
  self:applicationDescription(v.clientDescription)
  self:string(v.serverUri)
  self:string(v.endpointUrl)
  self:string(v.sessionName)
  self:byteString(v.clientNonce)
  self:byteString(v.clientCertificate)
  self:double(v.requestedSessionTimeout)
  self:uint32(v.maxResponseMessageSize)
end
function dec:createSessionRequest()
  local requestHeader
  local clientDescription
  local serverUri
  local endpointUrl
  local sessionName
  local clientNonce
  local clientCertificate
  local requestedSessionTimeout
  local maxResponseMessageSize
  requestHeader = self:requestHeader()
  clientDescription = self:applicationDescription()
  serverUri = self:string()
  endpointUrl = self:string()
  sessionName = self:string()
  clientNonce = self:byteString()
  clientCertificate = self:byteString()
  requestedSessionTimeout = self:double()
  maxResponseMessageSize = self:uint32()
  return {
    requestHeader = requestHeader,
    clientDescription = clientDescription,
    serverUri = serverUri,
    endpointUrl = endpointUrl,
    sessionName = sessionName,
    clientNonce = clientNonce,
    clientCertificate = clientCertificate,
    requestedSessionTimeout = requestedSessionTimeout,
    maxResponseMessageSize = maxResponseMessageSize,
  }
end
function enc:createSessionResponse(v)
  self:responseHeader(v.responseHeader)
  self:nodeId(v.sessionId)
  self:nodeId(v.authenticationToken)
  self:double(v.revisedSessionTimeout)
  self:byteString(v.serverNonce)
  self:byteString(v.serverCertificate)
  self:int32(v.serverEndpoints ~= nil and #v.serverEndpoints or -1)
  if v.serverEndpoints ~= nil then
    for i = 1, #v.serverEndpoints do
      self:endpointDescription(tools.index(v.serverEndpoints, i))
    end
  end
  self:int32(v.serverSoftwareCertificates ~= nil and #v.serverSoftwareCertificates or -1)
  if v.serverSoftwareCertificates ~= nil then
    for i = 1, #v.serverSoftwareCertificates do
      self:signedSoftwareCertificate(tools.index(v.serverSoftwareCertificates, i))
    end
  end
  self:signatureData(v.serverSignature)
  self:uint32(v.maxRequestMessageSize)
end
function dec:createSessionResponse()
  local responseHeader
  local sessionId
  local authenticationToken
  local revisedSessionTimeout
  local serverNonce
  local serverCertificate
  local noOfServerEndpoints
  local serverEndpoints
  local noOfServerSoftwareCertificates
  local serverSoftwareCertificates
  local serverSignature
  local maxRequestMessageSize
  responseHeader = self:responseHeader()
  sessionId = self:nodeId()
  authenticationToken = self:nodeId()
  revisedSessionTimeout = self:double()
  serverNonce = self:byteString()
  serverCertificate = self:byteString()
  noOfServerEndpoints = self:int32()
  if noOfServerEndpoints ~= -1 then
    serverEndpoints = {}
    for _=1,noOfServerEndpoints do
      local tmp
      tmp = self:endpointDescription()
      tins(serverEndpoints, tmp)
    end
  end
  noOfServerSoftwareCertificates = self:int32()
  if noOfServerSoftwareCertificates ~= -1 then
    serverSoftwareCertificates = {}
    for _=1,noOfServerSoftwareCertificates do
      local tmp
      tmp = self:signedSoftwareCertificate()
      tins(serverSoftwareCertificates, tmp)
    end
  end
  serverSignature = self:signatureData()
  maxRequestMessageSize = self:uint32()
  return {
    responseHeader = responseHeader,
    sessionId = sessionId,
    authenticationToken = authenticationToken,
    revisedSessionTimeout = revisedSessionTimeout,
    serverNonce = serverNonce,
    serverCertificate = serverCertificate,
    serverEndpoints = serverEndpoints,
    serverSoftwareCertificates = serverSoftwareCertificates,
    serverSignature = serverSignature,
    maxRequestMessageSize = maxRequestMessageSize,
  }
end
function enc:userIdentityToken(v)
  self:string(v.policyId)
end
function dec:userIdentityToken()
  local policyId
  policyId = self:string()
  return {
    policyId = policyId,
  }
end
function enc:anonymousIdentityToken(v)
  self:string(v.policyId)
end
function dec:anonymousIdentityToken()
  local policyId
  policyId = self:string()
  return {
    policyId = policyId,
  }
end
function enc:userNameIdentityToken(v)
  self:string(v.policyId)
  self:string(v.userName)
  self:byteString(v.password)
  self:string(v.encryptionAlgorithm)
end
function dec:userNameIdentityToken()
  local policyId
  local userName
  local password
  local encryptionAlgorithm
  policyId = self:string()
  userName = self:string()
  password = self:byteString()
  encryptionAlgorithm = self:string()
  return {
    policyId = policyId,
    userName = userName,
    password = password,
    encryptionAlgorithm = encryptionAlgorithm,
  }
end
function enc:x509identityToken(v)
  self:string(v.policyId)
  self:byteString(v.certificateData)
end
function dec:x509identityToken()
  local policyId
  local certificateData
  policyId = self:string()
  certificateData = self:byteString()
  return {
    policyId = policyId,
    certificateData = certificateData,
  }
end
function enc:issuedIdentityToken(v)
  self:string(v.policyId)
  self:byteString(v.tokenData)
  self:string(v.encryptionAlgorithm)
end
function dec:issuedIdentityToken()
  local policyId
  local tokenData
  local encryptionAlgorithm
  policyId = self:string()
  tokenData = self:byteString()
  encryptionAlgorithm = self:string()
  return {
    policyId = policyId,
    tokenData = tokenData,
    encryptionAlgorithm = encryptionAlgorithm,
  }
end
function enc:activateSessionRequest(v)
  self:requestHeader(v.requestHeader)
  self:signatureData(v.clientSignature)
  self:int32(v.clientSoftwareCertificates ~= nil and #v.clientSoftwareCertificates or -1)
  if v.clientSoftwareCertificates ~= nil then
    for i = 1, #v.clientSoftwareCertificates do
      self:signedSoftwareCertificate(tools.index(v.clientSoftwareCertificates, i))
    end
  end
  self:int32(v.localeIds ~= nil and #v.localeIds or -1)
  if v.localeIds ~= nil then
    for i = 1, #v.localeIds do
      self:string(tools.index(v.localeIds, i))
    end
  end
  self:extensionObject(v.userIdentityToken)
  self:signatureData(v.userTokenSignature)
end
function dec:activateSessionRequest()
  local requestHeader
  local clientSignature
  local noOfClientSoftwareCertificates
  local clientSoftwareCertificates
  local noOfLocaleIds
  local localeIds
  local userIdentityToken
  local userTokenSignature
  requestHeader = self:requestHeader()
  clientSignature = self:signatureData()
  noOfClientSoftwareCertificates = self:int32()
  if noOfClientSoftwareCertificates ~= -1 then
    clientSoftwareCertificates = {}
    for _=1,noOfClientSoftwareCertificates do
      local tmp
      tmp = self:signedSoftwareCertificate()
      tins(clientSoftwareCertificates, tmp)
    end
  end
  noOfLocaleIds = self:int32()
  if noOfLocaleIds ~= -1 then
    localeIds = {}
    for _=1,noOfLocaleIds do
      local tmp
      tmp = self:string()
      tins(localeIds, tmp)
    end
  end
  userIdentityToken = self:extensionObject()
  userTokenSignature = self:signatureData()
  return {
    requestHeader = requestHeader,
    clientSignature = clientSignature,
    clientSoftwareCertificates = clientSoftwareCertificates,
    localeIds = localeIds,
    userIdentityToken = userIdentityToken,
    userTokenSignature = userTokenSignature,
  }
end
function enc:activateSessionResponse(v)
  self:responseHeader(v.responseHeader)
  self:byteString(v.serverNonce)
  self:int32(v.results ~= nil and #v.results or -1)
  if v.results ~= nil then
    for i = 1, #v.results do
      self:statusCode(tools.index(v.results, i))
    end
  end
  self:int32(v.diagnosticInfos ~= nil and #v.diagnosticInfos or -1)
  if v.diagnosticInfos ~= nil then
    for i = 1, #v.diagnosticInfos do
      self:diagnosticInfo(tools.index(v.diagnosticInfos, i))
    end
  end
end
function dec:activateSessionResponse()
  local responseHeader
  local serverNonce
  local noOfResults
  local results
  local noOfDiagnosticInfos
  local diagnosticInfos
  responseHeader = self:responseHeader()
  serverNonce = self:byteString()
  noOfResults = self:int32()
  if noOfResults ~= -1 then
    results = {}
    for _=1,noOfResults do
      local tmp
      tmp = self:statusCode()
      tins(results, tmp)
    end
  end
  noOfDiagnosticInfos = self:int32()
  if noOfDiagnosticInfos ~= -1 then
    diagnosticInfos = {}
    for _=1,noOfDiagnosticInfos do
      local tmp
      tmp = self:diagnosticInfo()
      tins(diagnosticInfos, tmp)
    end
  end
  return {
    responseHeader = responseHeader,
    serverNonce = serverNonce,
    results = results,
    diagnosticInfos = diagnosticInfos,
  }
end
function enc:closeSessionRequest(v)
  self:requestHeader(v.requestHeader)
  self:boolean(v.deleteSubscriptions)
end
function dec:closeSessionRequest()
  local requestHeader
  local deleteSubscriptions
  requestHeader = self:requestHeader()
  deleteSubscriptions = self:boolean()
  return {
    requestHeader = requestHeader,
    deleteSubscriptions = deleteSubscriptions,
  }
end
function enc:closeSessionResponse(v)
  self:responseHeader(v.responseHeader)
end
function dec:closeSessionResponse()
  local responseHeader
  responseHeader = self:responseHeader()
  return {
    responseHeader = responseHeader,
  }
end
function enc:cancelRequest(v)
  self:requestHeader(v.requestHeader)
  self:uint32(v.requestHandle)
end
function dec:cancelRequest()
  local requestHeader
  local requestHandle
  requestHeader = self:requestHeader()
  requestHandle = self:uint32()
  return {
    requestHeader = requestHeader,
    requestHandle = requestHandle,
  }
end
function enc:cancelResponse(v)
  self:responseHeader(v.responseHeader)
  self:uint32(v.cancelCount)
end
function dec:cancelResponse()
  local responseHeader
  local cancelCount
  responseHeader = self:responseHeader()
  cancelCount = self:uint32()
  return {
    responseHeader = responseHeader,
    cancelCount = cancelCount,
  }
end
function enc:nodeAttributes(v)
  self:uint32(v.specifiedAttributes)
  self:localizedText(v.displayName)
  self:localizedText(v.description)
  self:uint32(v.writeMask)
  self:uint32(v.userWriteMask)
end
function dec:nodeAttributes()
  local specifiedAttributes
  local displayName
  local description
  local writeMask
  local userWriteMask
  specifiedAttributes = self:uint32()
  displayName = self:localizedText()
  description = self:localizedText()
  writeMask = self:uint32()
  userWriteMask = self:uint32()
  return {
    specifiedAttributes = specifiedAttributes,
    displayName = displayName,
    description = description,
    writeMask = writeMask,
    userWriteMask = userWriteMask,
  }
end
function enc:objectAttributes(v)
  self:uint32(v.specifiedAttributes)
  self:localizedText(v.displayName)
  self:localizedText(v.description)
  self:uint32(v.writeMask)
  self:uint32(v.userWriteMask)
  self:byte(v.eventNotifier)
end
function dec:objectAttributes()
  local specifiedAttributes
  local displayName
  local description
  local writeMask
  local userWriteMask
  local eventNotifier
  specifiedAttributes = self:uint32()
  displayName = self:localizedText()
  description = self:localizedText()
  writeMask = self:uint32()
  userWriteMask = self:uint32()
  eventNotifier = self:byte()
  return {
    specifiedAttributes = specifiedAttributes,
    displayName = displayName,
    description = description,
    writeMask = writeMask,
    userWriteMask = userWriteMask,
    eventNotifier = eventNotifier,
  }
end
function enc:variableAttributes(v)
  self:uint32(v.specifiedAttributes)
  self:localizedText(v.displayName)
  self:localizedText(v.description)
  self:uint32(v.writeMask)
  self:uint32(v.userWriteMask)
  self:variant(v.value)
  self:nodeId(v.dataType)
  self:int32(v.valueRank)
  self:int32(v.arrayDimensions ~= nil and #v.arrayDimensions or -1)
  if v.arrayDimensions ~= nil then
    for i = 1, #v.arrayDimensions do
      self:uint32(tools.index(v.arrayDimensions, i))
    end
  end
  self:byte(v.accessLevel)
  self:byte(v.userAccessLevel)
  self:double(v.minimumSamplingInterval)
  self:boolean(v.historizing)
end
function dec:variableAttributes()
  local specifiedAttributes
  local displayName
  local description
  local writeMask
  local userWriteMask
  local value
  local dataType
  local valueRank
  local noOfArrayDimensions
  local arrayDimensions
  local accessLevel
  local userAccessLevel
  local minimumSamplingInterval
  local historizing
  specifiedAttributes = self:uint32()
  displayName = self:localizedText()
  description = self:localizedText()
  writeMask = self:uint32()
  userWriteMask = self:uint32()
  value = self:variant()
  dataType = self:nodeId()
  valueRank = self:int32()
  noOfArrayDimensions = self:int32()
  if noOfArrayDimensions ~= -1 then
    arrayDimensions = {}
    for _=1,noOfArrayDimensions do
      local tmp
      tmp = self:uint32()
      tins(arrayDimensions, tmp)
    end
  end
  accessLevel = self:byte()
  userAccessLevel = self:byte()
  minimumSamplingInterval = self:double()
  historizing = self:boolean()
  return {
    specifiedAttributes = specifiedAttributes,
    displayName = displayName,
    description = description,
    writeMask = writeMask,
    userWriteMask = userWriteMask,
    value = value,
    dataType = dataType,
    valueRank = valueRank,
    arrayDimensions = arrayDimensions,
    accessLevel = accessLevel,
    userAccessLevel = userAccessLevel,
    minimumSamplingInterval = minimumSamplingInterval,
    historizing = historizing,
  }
end
function enc:methodAttributes(v)
  self:uint32(v.specifiedAttributes)
  self:localizedText(v.displayName)
  self:localizedText(v.description)
  self:uint32(v.writeMask)
  self:uint32(v.userWriteMask)
  self:boolean(v.executable)
  self:boolean(v.userExecutable)
end
function dec:methodAttributes()
  local specifiedAttributes
  local displayName
  local description
  local writeMask
  local userWriteMask
  local executable
  local userExecutable
  specifiedAttributes = self:uint32()
  displayName = self:localizedText()
  description = self:localizedText()
  writeMask = self:uint32()
  userWriteMask = self:uint32()
  executable = self:boolean()
  userExecutable = self:boolean()
  return {
    specifiedAttributes = specifiedAttributes,
    displayName = displayName,
    description = description,
    writeMask = writeMask,
    userWriteMask = userWriteMask,
    executable = executable,
    userExecutable = userExecutable,
  }
end
function enc:objectTypeAttributes(v)
  self:uint32(v.specifiedAttributes)
  self:localizedText(v.displayName)
  self:localizedText(v.description)
  self:uint32(v.writeMask)
  self:uint32(v.userWriteMask)
  self:boolean(v.isAbstract)
end
function dec:objectTypeAttributes()
  local specifiedAttributes
  local displayName
  local description
  local writeMask
  local userWriteMask
  local isAbstract
  specifiedAttributes = self:uint32()
  displayName = self:localizedText()
  description = self:localizedText()
  writeMask = self:uint32()
  userWriteMask = self:uint32()
  isAbstract = self:boolean()
  return {
    specifiedAttributes = specifiedAttributes,
    displayName = displayName,
    description = description,
    writeMask = writeMask,
    userWriteMask = userWriteMask,
    isAbstract = isAbstract,
  }
end
function enc:variableTypeAttributes(v)
  self:uint32(v.specifiedAttributes)
  self:localizedText(v.displayName)
  self:localizedText(v.description)
  self:uint32(v.writeMask)
  self:uint32(v.userWriteMask)
  self:variant(v.value)
  self:nodeId(v.dataType)
  self:int32(v.valueRank)
  self:int32(v.arrayDimensions ~= nil and #v.arrayDimensions or -1)
  if v.arrayDimensions ~= nil then
    for i = 1, #v.arrayDimensions do
      self:uint32(tools.index(v.arrayDimensions, i))
    end
  end
  self:boolean(v.isAbstract)
end
function dec:variableTypeAttributes()
  local specifiedAttributes
  local displayName
  local description
  local writeMask
  local userWriteMask
  local value
  local dataType
  local valueRank
  local noOfArrayDimensions
  local arrayDimensions
  local isAbstract
  specifiedAttributes = self:uint32()
  displayName = self:localizedText()
  description = self:localizedText()
  writeMask = self:uint32()
  userWriteMask = self:uint32()
  value = self:variant()
  dataType = self:nodeId()
  valueRank = self:int32()
  noOfArrayDimensions = self:int32()
  if noOfArrayDimensions ~= -1 then
    arrayDimensions = {}
    for _=1,noOfArrayDimensions do
      local tmp
      tmp = self:uint32()
      tins(arrayDimensions, tmp)
    end
  end
  isAbstract = self:boolean()
  return {
    specifiedAttributes = specifiedAttributes,
    displayName = displayName,
    description = description,
    writeMask = writeMask,
    userWriteMask = userWriteMask,
    value = value,
    dataType = dataType,
    valueRank = valueRank,
    arrayDimensions = arrayDimensions,
    isAbstract = isAbstract,
  }
end
function enc:referenceTypeAttributes(v)
  self:uint32(v.specifiedAttributes)
  self:localizedText(v.displayName)
  self:localizedText(v.description)
  self:uint32(v.writeMask)
  self:uint32(v.userWriteMask)
  self:boolean(v.isAbstract)
  self:boolean(v.symmetric)
  self:localizedText(v.inverseName)
end
function dec:referenceTypeAttributes()
  local specifiedAttributes
  local displayName
  local description
  local writeMask
  local userWriteMask
  local isAbstract
  local symmetric
  local inverseName
  specifiedAttributes = self:uint32()
  displayName = self:localizedText()
  description = self:localizedText()
  writeMask = self:uint32()
  userWriteMask = self:uint32()
  isAbstract = self:boolean()
  symmetric = self:boolean()
  inverseName = self:localizedText()
  return {
    specifiedAttributes = specifiedAttributes,
    displayName = displayName,
    description = description,
    writeMask = writeMask,
    userWriteMask = userWriteMask,
    isAbstract = isAbstract,
    symmetric = symmetric,
    inverseName = inverseName,
  }
end
function enc:dataTypeAttributes(v)
  self:uint32(v.specifiedAttributes)
  self:localizedText(v.displayName)
  self:localizedText(v.description)
  self:uint32(v.writeMask)
  self:uint32(v.userWriteMask)
  self:boolean(v.isAbstract)
end
function dec:dataTypeAttributes()
  local specifiedAttributes
  local displayName
  local description
  local writeMask
  local userWriteMask
  local isAbstract
  specifiedAttributes = self:uint32()
  displayName = self:localizedText()
  description = self:localizedText()
  writeMask = self:uint32()
  userWriteMask = self:uint32()
  isAbstract = self:boolean()
  return {
    specifiedAttributes = specifiedAttributes,
    displayName = displayName,
    description = description,
    writeMask = writeMask,
    userWriteMask = userWriteMask,
    isAbstract = isAbstract,
  }
end
function enc:viewAttributes(v)
  self:uint32(v.specifiedAttributes)
  self:localizedText(v.displayName)
  self:localizedText(v.description)
  self:uint32(v.writeMask)
  self:uint32(v.userWriteMask)
  self:boolean(v.containsNoLoops)
  self:byte(v.eventNotifier)
end
function dec:viewAttributes()
  local specifiedAttributes
  local displayName
  local description
  local writeMask
  local userWriteMask
  local containsNoLoops
  local eventNotifier
  specifiedAttributes = self:uint32()
  displayName = self:localizedText()
  description = self:localizedText()
  writeMask = self:uint32()
  userWriteMask = self:uint32()
  containsNoLoops = self:boolean()
  eventNotifier = self:byte()
  return {
    specifiedAttributes = specifiedAttributes,
    displayName = displayName,
    description = description,
    writeMask = writeMask,
    userWriteMask = userWriteMask,
    containsNoLoops = containsNoLoops,
    eventNotifier = eventNotifier,
  }
end
function enc:addNodesItem(v)
  self:expandedNodeId(v.parentNodeId)
  self:nodeId(v.referenceTypeId)
  self:expandedNodeId(v.requestedNewNodeId)
  self:qualifiedName(v.browseName)
  self:nodeClass(v.nodeClass)
  self:extensionObject(v.nodeAttributes)
  self:expandedNodeId(v.typeDefinition)
end
function dec:addNodesItem()
  local parentNodeId
  local referenceTypeId
  local requestedNewNodeId
  local browseName
  local nodeClass
  local nodeAttributes
  local typeDefinition
  parentNodeId = self:expandedNodeId()
  referenceTypeId = self:nodeId()
  requestedNewNodeId = self:expandedNodeId()
  browseName = self:qualifiedName()
  nodeClass = self:nodeClass()
  nodeAttributes = self:extensionObject()
  typeDefinition = self:expandedNodeId()
  return {
    parentNodeId = parentNodeId,
    referenceTypeId = referenceTypeId,
    requestedNewNodeId = requestedNewNodeId,
    browseName = browseName,
    nodeClass = nodeClass,
    nodeAttributes = nodeAttributes,
    typeDefinition = typeDefinition,
  }
end
function enc:addNodesResult(v)
  self:statusCode(v.statusCode)
  self:nodeId(v.addedNodeId)
end
function dec:addNodesResult()
  local statusCode
  local addedNodeId
  statusCode = self:statusCode()
  addedNodeId = self:nodeId()
  return {
    statusCode = statusCode,
    addedNodeId = addedNodeId,
  }
end
function enc:addNodesRequest(v)
  self:requestHeader(v.requestHeader)
  self:int32(v.nodesToAdd ~= nil and #v.nodesToAdd or -1)
  if v.nodesToAdd ~= nil then
    for i = 1, #v.nodesToAdd do
      self:addNodesItem(tools.index(v.nodesToAdd, i))
    end
  end
end
function dec:addNodesRequest()
  local requestHeader
  local noOfNodesToAdd
  local nodesToAdd
  requestHeader = self:requestHeader()
  noOfNodesToAdd = self:int32()
  if noOfNodesToAdd ~= -1 then
    nodesToAdd = {}
    for _=1,noOfNodesToAdd do
      local tmp
      tmp = self:addNodesItem()
      tins(nodesToAdd, tmp)
    end
  end
  return {
    requestHeader = requestHeader,
    nodesToAdd = nodesToAdd,
  }
end
function enc:addNodesResponse(v)
  self:responseHeader(v.responseHeader)
  self:int32(v.results ~= nil and #v.results or -1)
  if v.results ~= nil then
    for i = 1, #v.results do
      self:addNodesResult(tools.index(v.results, i))
    end
  end
  self:int32(v.diagnosticInfos ~= nil and #v.diagnosticInfos or -1)
  if v.diagnosticInfos ~= nil then
    for i = 1, #v.diagnosticInfos do
      self:diagnosticInfo(tools.index(v.diagnosticInfos, i))
    end
  end
end
function dec:addNodesResponse()
  local responseHeader
  local noOfResults
  local results
  local noOfDiagnosticInfos
  local diagnosticInfos
  responseHeader = self:responseHeader()
  noOfResults = self:int32()
  if noOfResults ~= -1 then
    results = {}
    for _=1,noOfResults do
      local tmp
      tmp = self:addNodesResult()
      tins(results, tmp)
    end
  end
  noOfDiagnosticInfos = self:int32()
  if noOfDiagnosticInfos ~= -1 then
    diagnosticInfos = {}
    for _=1,noOfDiagnosticInfos do
      local tmp
      tmp = self:diagnosticInfo()
      tins(diagnosticInfos, tmp)
    end
  end
  return {
    responseHeader = responseHeader,
    results = results,
    diagnosticInfos = diagnosticInfos,
  }
end
function enc:addReferencesItem(v)
  self:nodeId(v.sourceNodeId)
  self:nodeId(v.referenceTypeId)
  self:boolean(v.isForward)
  self:string(v.targetServerUri)
  self:expandedNodeId(v.targetNodeId)
  self:nodeClass(v.targetNodeClass)
end
function dec:addReferencesItem()
  local sourceNodeId
  local referenceTypeId
  local isForward
  local targetServerUri
  local targetNodeId
  local targetNodeClass
  sourceNodeId = self:nodeId()
  referenceTypeId = self:nodeId()
  isForward = self:boolean()
  targetServerUri = self:string()
  targetNodeId = self:expandedNodeId()
  targetNodeClass = self:nodeClass()
  return {
    sourceNodeId = sourceNodeId,
    referenceTypeId = referenceTypeId,
    isForward = isForward,
    targetServerUri = targetServerUri,
    targetNodeId = targetNodeId,
    targetNodeClass = targetNodeClass,
  }
end
function enc:addReferencesRequest(v)
  self:requestHeader(v.requestHeader)
  self:int32(v.referencesToAdd ~= nil and #v.referencesToAdd or -1)
  if v.referencesToAdd ~= nil then
    for i = 1, #v.referencesToAdd do
      self:addReferencesItem(tools.index(v.referencesToAdd, i))
    end
  end
end
function dec:addReferencesRequest()
  local requestHeader
  local noOfReferencesToAdd
  local referencesToAdd
  requestHeader = self:requestHeader()
  noOfReferencesToAdd = self:int32()
  if noOfReferencesToAdd ~= -1 then
    referencesToAdd = {}
    for _=1,noOfReferencesToAdd do
      local tmp
      tmp = self:addReferencesItem()
      tins(referencesToAdd, tmp)
    end
  end
  return {
    requestHeader = requestHeader,
    referencesToAdd = referencesToAdd,
  }
end
function enc:addReferencesResponse(v)
  self:responseHeader(v.responseHeader)
  self:int32(v.results ~= nil and #v.results or -1)
  if v.results ~= nil then
    for i = 1, #v.results do
      self:statusCode(tools.index(v.results, i))
    end
  end
  self:int32(v.diagnosticInfos ~= nil and #v.diagnosticInfos or -1)
  if v.diagnosticInfos ~= nil then
    for i = 1, #v.diagnosticInfos do
      self:diagnosticInfo(tools.index(v.diagnosticInfos, i))
    end
  end
end
function dec:addReferencesResponse()
  local responseHeader
  local noOfResults
  local results
  local noOfDiagnosticInfos
  local diagnosticInfos
  responseHeader = self:responseHeader()
  noOfResults = self:int32()
  if noOfResults ~= -1 then
    results = {}
    for _=1,noOfResults do
      local tmp
      tmp = self:statusCode()
      tins(results, tmp)
    end
  end
  noOfDiagnosticInfos = self:int32()
  if noOfDiagnosticInfos ~= -1 then
    diagnosticInfos = {}
    for _=1,noOfDiagnosticInfos do
      local tmp
      tmp = self:diagnosticInfo()
      tins(diagnosticInfos, tmp)
    end
  end
  return {
    responseHeader = responseHeader,
    results = results,
    diagnosticInfos = diagnosticInfos,
  }
end
function enc:deleteNodesItem(v)
  self:nodeId(v.nodeId)
  self:boolean(v.deleteTargetReferences)
end
function dec:deleteNodesItem()
  local nodeId
  local deleteTargetReferences
  nodeId = self:nodeId()
  deleteTargetReferences = self:boolean()
  return {
    nodeId = nodeId,
    deleteTargetReferences = deleteTargetReferences,
  }
end
function enc:deleteNodesRequest(v)
  self:requestHeader(v.requestHeader)
  self:int32(v.nodesToDelete ~= nil and #v.nodesToDelete or -1)
  if v.nodesToDelete ~= nil then
    for i = 1, #v.nodesToDelete do
      self:deleteNodesItem(tools.index(v.nodesToDelete, i))
    end
  end
end
function dec:deleteNodesRequest()
  local requestHeader
  local noOfNodesToDelete
  local nodesToDelete
  requestHeader = self:requestHeader()
  noOfNodesToDelete = self:int32()
  if noOfNodesToDelete ~= -1 then
    nodesToDelete = {}
    for _=1,noOfNodesToDelete do
      local tmp
      tmp = self:deleteNodesItem()
      tins(nodesToDelete, tmp)
    end
  end
  return {
    requestHeader = requestHeader,
    nodesToDelete = nodesToDelete,
  }
end
function enc:deleteNodesResponse(v)
  self:responseHeader(v.responseHeader)
  self:int32(v.results ~= nil and #v.results or -1)
  if v.results ~= nil then
    for i = 1, #v.results do
      self:statusCode(tools.index(v.results, i))
    end
  end
  self:int32(v.diagnosticInfos ~= nil and #v.diagnosticInfos or -1)
  if v.diagnosticInfos ~= nil then
    for i = 1, #v.diagnosticInfos do
      self:diagnosticInfo(tools.index(v.diagnosticInfos, i))
    end
  end
end
function dec:deleteNodesResponse()
  local responseHeader
  local noOfResults
  local results
  local noOfDiagnosticInfos
  local diagnosticInfos
  responseHeader = self:responseHeader()
  noOfResults = self:int32()
  if noOfResults ~= -1 then
    results = {}
    for _=1,noOfResults do
      local tmp
      tmp = self:statusCode()
      tins(results, tmp)
    end
  end
  noOfDiagnosticInfos = self:int32()
  if noOfDiagnosticInfos ~= -1 then
    diagnosticInfos = {}
    for _=1,noOfDiagnosticInfos do
      local tmp
      tmp = self:diagnosticInfo()
      tins(diagnosticInfos, tmp)
    end
  end
  return {
    responseHeader = responseHeader,
    results = results,
    diagnosticInfos = diagnosticInfos,
  }
end
function enc:deleteReferencesItem(v)
  self:nodeId(v.sourceNodeId)
  self:nodeId(v.referenceTypeId)
  self:boolean(v.isForward)
  self:expandedNodeId(v.targetNodeId)
  self:boolean(v.deleteBidirectional)
end
function dec:deleteReferencesItem()
  local sourceNodeId
  local referenceTypeId
  local isForward
  local targetNodeId
  local deleteBidirectional
  sourceNodeId = self:nodeId()
  referenceTypeId = self:nodeId()
  isForward = self:boolean()
  targetNodeId = self:expandedNodeId()
  deleteBidirectional = self:boolean()
  return {
    sourceNodeId = sourceNodeId,
    referenceTypeId = referenceTypeId,
    isForward = isForward,
    targetNodeId = targetNodeId,
    deleteBidirectional = deleteBidirectional,
  }
end
function enc:deleteReferencesRequest(v)
  self:requestHeader(v.requestHeader)
  self:int32(v.referencesToDelete ~= nil and #v.referencesToDelete or -1)
  if v.referencesToDelete ~= nil then
    for i = 1, #v.referencesToDelete do
      self:deleteReferencesItem(tools.index(v.referencesToDelete, i))
    end
  end
end
function dec:deleteReferencesRequest()
  local requestHeader
  local noOfReferencesToDelete
  local referencesToDelete
  requestHeader = self:requestHeader()
  noOfReferencesToDelete = self:int32()
  if noOfReferencesToDelete ~= -1 then
    referencesToDelete = {}
    for _=1,noOfReferencesToDelete do
      local tmp
      tmp = self:deleteReferencesItem()
      tins(referencesToDelete, tmp)
    end
  end
  return {
    requestHeader = requestHeader,
    referencesToDelete = referencesToDelete,
  }
end
function enc:deleteReferencesResponse(v)
  self:responseHeader(v.responseHeader)
  self:int32(v.results ~= nil and #v.results or -1)
  if v.results ~= nil then
    for i = 1, #v.results do
      self:statusCode(tools.index(v.results, i))
    end
  end
  self:int32(v.diagnosticInfos ~= nil and #v.diagnosticInfos or -1)
  if v.diagnosticInfos ~= nil then
    for i = 1, #v.diagnosticInfos do
      self:diagnosticInfo(tools.index(v.diagnosticInfos, i))
    end
  end
end
function dec:deleteReferencesResponse()
  local responseHeader
  local noOfResults
  local results
  local noOfDiagnosticInfos
  local diagnosticInfos
  responseHeader = self:responseHeader()
  noOfResults = self:int32()
  if noOfResults ~= -1 then
    results = {}
    for _=1,noOfResults do
      local tmp
      tmp = self:statusCode()
      tins(results, tmp)
    end
  end
  noOfDiagnosticInfos = self:int32()
  if noOfDiagnosticInfos ~= -1 then
    diagnosticInfos = {}
    for _=1,noOfDiagnosticInfos do
      local tmp
      tmp = self:diagnosticInfo()
      tins(diagnosticInfos, tmp)
    end
  end
  return {
    responseHeader = responseHeader,
    results = results,
    diagnosticInfos = diagnosticInfos,
  }
end
function enc:viewDescription(v)
  self:nodeId(v.viewId)
  self:dateTime(v.timestamp)
  self:uint32(v.viewVersion)
end
function dec:viewDescription()
  local viewId
  local timestamp
  local viewVersion
  viewId = self:nodeId()
  timestamp = self:dateTime()
  viewVersion = self:uint32()
  return {
    viewId = viewId,
    timestamp = timestamp,
    viewVersion = viewVersion,
  }
end
function enc:browseDescription(v)
  self:nodeId(v.nodeId)
  self:browseDirection(v.browseDirection)
  self:nodeId(v.referenceTypeId)
  self:boolean(v.includeSubtypes)
  self:uint32(v.nodeClassMask)
  self:uint32(v.resultMask)
end
function dec:browseDescription()
  local nodeId
  local browseDirection
  local referenceTypeId
  local includeSubtypes
  local nodeClassMask
  local resultMask
  nodeId = self:nodeId()
  browseDirection = self:browseDirection()
  referenceTypeId = self:nodeId()
  includeSubtypes = self:boolean()
  nodeClassMask = self:uint32()
  resultMask = self:uint32()
  return {
    nodeId = nodeId,
    browseDirection = browseDirection,
    referenceTypeId = referenceTypeId,
    includeSubtypes = includeSubtypes,
    nodeClassMask = nodeClassMask,
    resultMask = resultMask,
  }
end
function enc:referenceDescription(v)
  self:nodeId(v.referenceTypeId)
  self:boolean(v.isForward)
  self:expandedNodeId(v.nodeId)
  self:qualifiedName(v.browseName)
  self:localizedText(v.displayName)
  self:nodeClass(v.nodeClass)
  self:expandedNodeId(v.typeDefinition)
end
function dec:referenceDescription()
  local referenceTypeId
  local isForward
  local nodeId
  local browseName
  local displayName
  local nodeClass
  local typeDefinition
  referenceTypeId = self:nodeId()
  isForward = self:boolean()
  nodeId = self:expandedNodeId()
  browseName = self:qualifiedName()
  displayName = self:localizedText()
  nodeClass = self:nodeClass()
  typeDefinition = self:expandedNodeId()
  return {
    referenceTypeId = referenceTypeId,
    isForward = isForward,
    nodeId = nodeId,
    browseName = browseName,
    displayName = displayName,
    nodeClass = nodeClass,
    typeDefinition = typeDefinition,
  }
end
function enc:browseResult(v)
  self:statusCode(v.statusCode)
  self:byteString(v.continuationPoint)
  self:int32(v.references ~= nil and #v.references or -1)
  if v.references ~= nil then
    for i = 1, #v.references do
      self:referenceDescription(tools.index(v.references, i))
    end
  end
end
function dec:browseResult()
  local statusCode
  local continuationPoint
  local noOfReferences
  local references
  statusCode = self:statusCode()
  continuationPoint = self:byteString()
  noOfReferences = self:int32()
  if noOfReferences ~= -1 then
    references = {}
    for _=1,noOfReferences do
      local tmp
      tmp = self:referenceDescription()
      tins(references, tmp)
    end
  end
  return {
    statusCode = statusCode,
    continuationPoint = continuationPoint,
    references = references,
  }
end
function enc:browseRequest(v)
  self:requestHeader(v.requestHeader)
  self:viewDescription(v.view)
  self:uint32(v.requestedMaxReferencesPerNode)
  self:int32(v.nodesToBrowse ~= nil and #v.nodesToBrowse or -1)
  if v.nodesToBrowse ~= nil then
    for i = 1, #v.nodesToBrowse do
      self:browseDescription(tools.index(v.nodesToBrowse, i))
    end
  end
end
function dec:browseRequest()
  local requestHeader
  local view
  local requestedMaxReferencesPerNode
  local noOfNodesToBrowse
  local nodesToBrowse
  requestHeader = self:requestHeader()
  view = self:viewDescription()
  requestedMaxReferencesPerNode = self:uint32()
  noOfNodesToBrowse = self:int32()
  if noOfNodesToBrowse ~= -1 then
    nodesToBrowse = {}
    for _=1,noOfNodesToBrowse do
      local tmp
      tmp = self:browseDescription()
      tins(nodesToBrowse, tmp)
    end
  end
  return {
    requestHeader = requestHeader,
    view = view,
    requestedMaxReferencesPerNode = requestedMaxReferencesPerNode,
    nodesToBrowse = nodesToBrowse,
  }
end
function enc:browseResponse(v)
  self:responseHeader(v.responseHeader)
  self:int32(v.results ~= nil and #v.results or -1)
  if v.results ~= nil then
    for i = 1, #v.results do
      self:browseResult(tools.index(v.results, i))
    end
  end
  self:int32(v.diagnosticInfos ~= nil and #v.diagnosticInfos or -1)
  if v.diagnosticInfos ~= nil then
    for i = 1, #v.diagnosticInfos do
      self:diagnosticInfo(tools.index(v.diagnosticInfos, i))
    end
  end
end
function dec:browseResponse()
  local responseHeader
  local noOfResults
  local results
  local noOfDiagnosticInfos
  local diagnosticInfos
  responseHeader = self:responseHeader()
  noOfResults = self:int32()
  if noOfResults ~= -1 then
    results = {}
    for _=1,noOfResults do
      local tmp
      tmp = self:browseResult()
      tins(results, tmp)
    end
  end
  noOfDiagnosticInfos = self:int32()
  if noOfDiagnosticInfos ~= -1 then
    diagnosticInfos = {}
    for _=1,noOfDiagnosticInfos do
      local tmp
      tmp = self:diagnosticInfo()
      tins(diagnosticInfos, tmp)
    end
  end
  return {
    responseHeader = responseHeader,
    results = results,
    diagnosticInfos = diagnosticInfos,
  }
end
function enc:browseNextRequest(v)
  self:requestHeader(v.requestHeader)
  self:boolean(v.releaseContinuationPoints)
  self:int32(v.continuationPoints ~= nil and #v.continuationPoints or -1)
  if v.continuationPoints ~= nil then
    for i = 1, #v.continuationPoints do
      self:byteString(tools.index(v.continuationPoints, i))
    end
  end
end
function dec:browseNextRequest()
  local requestHeader
  local releaseContinuationPoints
  local noOfContinuationPoints
  local continuationPoints
  requestHeader = self:requestHeader()
  releaseContinuationPoints = self:boolean()
  noOfContinuationPoints = self:int32()
  if noOfContinuationPoints ~= -1 then
    continuationPoints = {}
    for _=1,noOfContinuationPoints do
      local tmp
      tmp = self:byteString()
      tins(continuationPoints, tmp)
    end
  end
  return {
    requestHeader = requestHeader,
    releaseContinuationPoints = releaseContinuationPoints,
    continuationPoints = continuationPoints,
  }
end
function enc:browseNextResponse(v)
  self:responseHeader(v.responseHeader)
  self:int32(v.results ~= nil and #v.results or -1)
  if v.results ~= nil then
    for i = 1, #v.results do
      self:browseResult(tools.index(v.results, i))
    end
  end
  self:int32(v.diagnosticInfos ~= nil and #v.diagnosticInfos or -1)
  if v.diagnosticInfos ~= nil then
    for i = 1, #v.diagnosticInfos do
      self:diagnosticInfo(tools.index(v.diagnosticInfos, i))
    end
  end
end
function dec:browseNextResponse()
  local responseHeader
  local noOfResults
  local results
  local noOfDiagnosticInfos
  local diagnosticInfos
  responseHeader = self:responseHeader()
  noOfResults = self:int32()
  if noOfResults ~= -1 then
    results = {}
    for _=1,noOfResults do
      local tmp
      tmp = self:browseResult()
      tins(results, tmp)
    end
  end
  noOfDiagnosticInfos = self:int32()
  if noOfDiagnosticInfos ~= -1 then
    diagnosticInfos = {}
    for _=1,noOfDiagnosticInfos do
      local tmp
      tmp = self:diagnosticInfo()
      tins(diagnosticInfos, tmp)
    end
  end
  return {
    responseHeader = responseHeader,
    results = results,
    diagnosticInfos = diagnosticInfos,
  }
end
function enc:relativePathElement(v)
  self:nodeId(v.referenceTypeId)
  self:boolean(v.isInverse)
  self:boolean(v.includeSubtypes)
  self:qualifiedName(v.targetName)
end
function dec:relativePathElement()
  local referenceTypeId
  local isInverse
  local includeSubtypes
  local targetName
  referenceTypeId = self:nodeId()
  isInverse = self:boolean()
  includeSubtypes = self:boolean()
  targetName = self:qualifiedName()
  return {
    referenceTypeId = referenceTypeId,
    isInverse = isInverse,
    includeSubtypes = includeSubtypes,
    targetName = targetName,
  }
end
function enc:relativePath(v)
  self:int32(v.elements ~= nil and #v.elements or -1)
  if v.elements ~= nil then
    for i = 1, #v.elements do
      self:relativePathElement(tools.index(v.elements, i))
    end
  end
end
function dec:relativePath()
  local noOfElements
  local elements
  noOfElements = self:int32()
  if noOfElements ~= -1 then
    elements = {}
    for _=1,noOfElements do
      local tmp
      tmp = self:relativePathElement()
      tins(elements, tmp)
    end
  end
  return {
    elements = elements,
  }
end
function enc:browsePath(v)
  self:nodeId(v.startingNode)
  self:relativePath(v.relativePath)
end
function dec:browsePath()
  local startingNode
  local relativePath
  startingNode = self:nodeId()
  relativePath = self:relativePath()
  return {
    startingNode = startingNode,
    relativePath = relativePath,
  }
end
function enc:browsePathTarget(v)
  self:expandedNodeId(v.targetId)
  self:uint32(v.remainingPathIndex)
end
function dec:browsePathTarget()
  local targetId
  local remainingPathIndex
  targetId = self:expandedNodeId()
  remainingPathIndex = self:uint32()
  return {
    targetId = targetId,
    remainingPathIndex = remainingPathIndex,
  }
end
function enc:browsePathResult(v)
  self:statusCode(v.statusCode)
  self:int32(v.targets ~= nil and #v.targets or -1)
  if v.targets ~= nil then
    for i = 1, #v.targets do
      self:browsePathTarget(tools.index(v.targets, i))
    end
  end
end
function dec:browsePathResult()
  local statusCode
  local noOfTargets
  local targets
  statusCode = self:statusCode()
  noOfTargets = self:int32()
  if noOfTargets ~= -1 then
    targets = {}
    for _=1,noOfTargets do
      local tmp
      tmp = self:browsePathTarget()
      tins(targets, tmp)
    end
  end
  return {
    statusCode = statusCode,
    targets = targets,
  }
end
function enc:translateBrowsePathsToNodeIdsRequest(v)
  self:requestHeader(v.requestHeader)
  self:int32(v.browsePaths ~= nil and #v.browsePaths or -1)
  if v.browsePaths ~= nil then
    for i = 1, #v.browsePaths do
      self:browsePath(tools.index(v.browsePaths, i))
    end
  end
end
function dec:translateBrowsePathsToNodeIdsRequest()
  local requestHeader
  local noOfBrowsePaths
  local browsePaths
  requestHeader = self:requestHeader()
  noOfBrowsePaths = self:int32()
  if noOfBrowsePaths ~= -1 then
    browsePaths = {}
    for _=1,noOfBrowsePaths do
      local tmp
      tmp = self:browsePath()
      tins(browsePaths, tmp)
    end
  end
  return {
    requestHeader = requestHeader,
    browsePaths = browsePaths,
  }
end
function enc:translateBrowsePathsToNodeIdsResponse(v)
  self:responseHeader(v.responseHeader)
  self:int32(v.results ~= nil and #v.results or -1)
  if v.results ~= nil then
    for i = 1, #v.results do
      self:browsePathResult(tools.index(v.results, i))
    end
  end
  self:int32(v.diagnosticInfos ~= nil and #v.diagnosticInfos or -1)
  if v.diagnosticInfos ~= nil then
    for i = 1, #v.diagnosticInfos do
      self:diagnosticInfo(tools.index(v.diagnosticInfos, i))
    end
  end
end
function dec:translateBrowsePathsToNodeIdsResponse()
  local responseHeader
  local noOfResults
  local results
  local noOfDiagnosticInfos
  local diagnosticInfos
  responseHeader = self:responseHeader()
  noOfResults = self:int32()
  if noOfResults ~= -1 then
    results = {}
    for _=1,noOfResults do
      local tmp
      tmp = self:browsePathResult()
      tins(results, tmp)
    end
  end
  noOfDiagnosticInfos = self:int32()
  if noOfDiagnosticInfos ~= -1 then
    diagnosticInfos = {}
    for _=1,noOfDiagnosticInfos do
      local tmp
      tmp = self:diagnosticInfo()
      tins(diagnosticInfos, tmp)
    end
  end
  return {
    responseHeader = responseHeader,
    results = results,
    diagnosticInfos = diagnosticInfos,
  }
end
function enc:registerNodesRequest(v)
  self:requestHeader(v.requestHeader)
  self:int32(v.nodesToRegister ~= nil and #v.nodesToRegister or -1)
  if v.nodesToRegister ~= nil then
    for i = 1, #v.nodesToRegister do
      self:nodeId(tools.index(v.nodesToRegister, i))
    end
  end
end
function dec:registerNodesRequest()
  local requestHeader
  local noOfNodesToRegister
  local nodesToRegister
  requestHeader = self:requestHeader()
  noOfNodesToRegister = self:int32()
  if noOfNodesToRegister ~= -1 then
    nodesToRegister = {}
    for _=1,noOfNodesToRegister do
      local tmp
      tmp = self:nodeId()
      tins(nodesToRegister, tmp)
    end
  end
  return {
    requestHeader = requestHeader,
    nodesToRegister = nodesToRegister,
  }
end
function enc:registerNodesResponse(v)
  self:responseHeader(v.responseHeader)
  self:int32(v.registeredNodeIds ~= nil and #v.registeredNodeIds or -1)
  if v.registeredNodeIds ~= nil then
    for i = 1, #v.registeredNodeIds do
      self:nodeId(tools.index(v.registeredNodeIds, i))
    end
  end
end
function dec:registerNodesResponse()
  local responseHeader
  local noOfRegisteredNodeIds
  local registeredNodeIds
  responseHeader = self:responseHeader()
  noOfRegisteredNodeIds = self:int32()
  if noOfRegisteredNodeIds ~= -1 then
    registeredNodeIds = {}
    for _=1,noOfRegisteredNodeIds do
      local tmp
      tmp = self:nodeId()
      tins(registeredNodeIds, tmp)
    end
  end
  return {
    responseHeader = responseHeader,
    registeredNodeIds = registeredNodeIds,
  }
end
function enc:unregisterNodesRequest(v)
  self:requestHeader(v.requestHeader)
  self:int32(v.nodesToUnregister ~= nil and #v.nodesToUnregister or -1)
  if v.nodesToUnregister ~= nil then
    for i = 1, #v.nodesToUnregister do
      self:nodeId(tools.index(v.nodesToUnregister, i))
    end
  end
end
function dec:unregisterNodesRequest()
  local requestHeader
  local noOfNodesToUnregister
  local nodesToUnregister
  requestHeader = self:requestHeader()
  noOfNodesToUnregister = self:int32()
  if noOfNodesToUnregister ~= -1 then
    nodesToUnregister = {}
    for _=1,noOfNodesToUnregister do
      local tmp
      tmp = self:nodeId()
      tins(nodesToUnregister, tmp)
    end
  end
  return {
    requestHeader = requestHeader,
    nodesToUnregister = nodesToUnregister,
  }
end
function enc:unregisterNodesResponse(v)
  self:responseHeader(v.responseHeader)
end
function dec:unregisterNodesResponse()
  local responseHeader
  responseHeader = self:responseHeader()
  return {
    responseHeader = responseHeader,
  }
end
function enc:endpointConfiguration(v)
  self:int32(v.operationTimeout)
  self:boolean(v.useBinaryEncoding)
  self:int32(v.maxStringLength)
  self:int32(v.maxByteStringLength)
  self:int32(v.maxArrayLength)
  self:int32(v.maxMessageSize)
  self:int32(v.maxBufferSize)
  self:int32(v.channelLifetime)
  self:int32(v.securityTokenLifetime)
end
function dec:endpointConfiguration()
  local operationTimeout
  local useBinaryEncoding
  local maxStringLength
  local maxByteStringLength
  local maxArrayLength
  local maxMessageSize
  local maxBufferSize
  local channelLifetime
  local securityTokenLifetime
  operationTimeout = self:int32()
  useBinaryEncoding = self:boolean()
  maxStringLength = self:int32()
  maxByteStringLength = self:int32()
  maxArrayLength = self:int32()
  maxMessageSize = self:int32()
  maxBufferSize = self:int32()
  channelLifetime = self:int32()
  securityTokenLifetime = self:int32()
  return {
    operationTimeout = operationTimeout,
    useBinaryEncoding = useBinaryEncoding,
    maxStringLength = maxStringLength,
    maxByteStringLength = maxByteStringLength,
    maxArrayLength = maxArrayLength,
    maxMessageSize = maxMessageSize,
    maxBufferSize = maxBufferSize,
    channelLifetime = channelLifetime,
    securityTokenLifetime = securityTokenLifetime,
  }
end
function enc:supportedProfile(v)
  self:string(v.organizationUri)
  self:string(v.profileId)
  self:string(v.complianceTool)
  self:dateTime(v.complianceDate)
  self:complianceLevel(v.complianceLevel)
  self:int32(v.unsupportedUnitIds ~= nil and #v.unsupportedUnitIds or -1)
  if v.unsupportedUnitIds ~= nil then
    for i = 1, #v.unsupportedUnitIds do
      self:string(tools.index(v.unsupportedUnitIds, i))
    end
  end
end
function dec:supportedProfile()
  local organizationUri
  local profileId
  local complianceTool
  local complianceDate
  local complianceLevel
  local noOfUnsupportedUnitIds
  local unsupportedUnitIds
  organizationUri = self:string()
  profileId = self:string()
  complianceTool = self:string()
  complianceDate = self:dateTime()
  complianceLevel = self:complianceLevel()
  noOfUnsupportedUnitIds = self:int32()
  if noOfUnsupportedUnitIds ~= -1 then
    unsupportedUnitIds = {}
    for _=1,noOfUnsupportedUnitIds do
      local tmp
      tmp = self:string()
      tins(unsupportedUnitIds, tmp)
    end
  end
  return {
    organizationUri = organizationUri,
    profileId = profileId,
    complianceTool = complianceTool,
    complianceDate = complianceDate,
    complianceLevel = complianceLevel,
    unsupportedUnitIds = unsupportedUnitIds,
  }
end
function enc:softwareCertificate(v)
  self:string(v.productName)
  self:string(v.productUri)
  self:string(v.vendorName)
  self:byteString(v.vendorProductCertificate)
  self:string(v.softwareVersion)
  self:string(v.buildNumber)
  self:dateTime(v.buildDate)
  self:string(v.issuedBy)
  self:dateTime(v.issueDate)
  self:int32(v.supportedProfiles ~= nil and #v.supportedProfiles or -1)
  if v.supportedProfiles ~= nil then
    for i = 1, #v.supportedProfiles do
      self:supportedProfile(tools.index(v.supportedProfiles, i))
    end
  end
end
function dec:softwareCertificate()
  local productName
  local productUri
  local vendorName
  local vendorProductCertificate
  local softwareVersion
  local buildNumber
  local buildDate
  local issuedBy
  local issueDate
  local noOfSupportedProfiles
  local supportedProfiles
  productName = self:string()
  productUri = self:string()
  vendorName = self:string()
  vendorProductCertificate = self:byteString()
  softwareVersion = self:string()
  buildNumber = self:string()
  buildDate = self:dateTime()
  issuedBy = self:string()
  issueDate = self:dateTime()
  noOfSupportedProfiles = self:int32()
  if noOfSupportedProfiles ~= -1 then
    supportedProfiles = {}
    for _=1,noOfSupportedProfiles do
      local tmp
      tmp = self:supportedProfile()
      tins(supportedProfiles, tmp)
    end
  end
  return {
    productName = productName,
    productUri = productUri,
    vendorName = vendorName,
    vendorProductCertificate = vendorProductCertificate,
    softwareVersion = softwareVersion,
    buildNumber = buildNumber,
    buildDate = buildDate,
    issuedBy = issuedBy,
    issueDate = issueDate,
    supportedProfiles = supportedProfiles,
  }
end
function enc:queryDataDescription(v)
  self:relativePath(v.relativePath)
  self:uint32(v.attributeId)
  self:string(v.indexRange)
end
function dec:queryDataDescription()
  local relativePath
  local attributeId
  local indexRange
  relativePath = self:relativePath()
  attributeId = self:uint32()
  indexRange = self:string()
  return {
    relativePath = relativePath,
    attributeId = attributeId,
    indexRange = indexRange,
  }
end
function enc:nodeTypeDescription(v)
  self:expandedNodeId(v.typeDefinitionNode)
  self:boolean(v.includeSubTypes)
  self:int32(v.dataToReturn ~= nil and #v.dataToReturn or -1)
  if v.dataToReturn ~= nil then
    for i = 1, #v.dataToReturn do
      self:queryDataDescription(tools.index(v.dataToReturn, i))
    end
  end
end
function dec:nodeTypeDescription()
  local typeDefinitionNode
  local includeSubTypes
  local noOfDataToReturn
  local dataToReturn
  typeDefinitionNode = self:expandedNodeId()
  includeSubTypes = self:boolean()
  noOfDataToReturn = self:int32()
  if noOfDataToReturn ~= -1 then
    dataToReturn = {}
    for _=1,noOfDataToReturn do
      local tmp
      tmp = self:queryDataDescription()
      tins(dataToReturn, tmp)
    end
  end
  return {
    typeDefinitionNode = typeDefinitionNode,
    includeSubTypes = includeSubTypes,
    dataToReturn = dataToReturn,
  }
end
function enc:queryDataSet(v)
  self:expandedNodeId(v.nodeId)
  self:expandedNodeId(v.typeDefinitionNode)
  self:int32(v.values ~= nil and #v.values or -1)
  if v.values ~= nil then
    for i = 1, #v.values do
      self:variant(tools.index(v.values, i))
    end
  end
end
function dec:queryDataSet()
  local nodeId
  local typeDefinitionNode
  local noOfValues
  local values
  nodeId = self:expandedNodeId()
  typeDefinitionNode = self:expandedNodeId()
  noOfValues = self:int32()
  if noOfValues ~= -1 then
    values = {}
    for _=1,noOfValues do
      local tmp
      tmp = self:variant()
      tins(values, tmp)
    end
  end
  return {
    nodeId = nodeId,
    typeDefinitionNode = typeDefinitionNode,
    values = values,
  }
end
function enc:nodeReference(v)
  self:nodeId(v.nodeId)
  self:nodeId(v.referenceTypeId)
  self:boolean(v.isForward)
  self:int32(v.referencedNodeIds ~= nil and #v.referencedNodeIds or -1)
  if v.referencedNodeIds ~= nil then
    for i = 1, #v.referencedNodeIds do
      self:nodeId(tools.index(v.referencedNodeIds, i))
    end
  end
end
function dec:nodeReference()
  local nodeId
  local referenceTypeId
  local isForward
  local noOfReferencedNodeIds
  local referencedNodeIds
  nodeId = self:nodeId()
  referenceTypeId = self:nodeId()
  isForward = self:boolean()
  noOfReferencedNodeIds = self:int32()
  if noOfReferencedNodeIds ~= -1 then
    referencedNodeIds = {}
    for _=1,noOfReferencedNodeIds do
      local tmp
      tmp = self:nodeId()
      tins(referencedNodeIds, tmp)
    end
  end
  return {
    nodeId = nodeId,
    referenceTypeId = referenceTypeId,
    isForward = isForward,
    referencedNodeIds = referencedNodeIds,
  }
end
function enc:contentFilterElement(v)
  self:filterOperator(v.filterOperator)
  self:int32(v.filterOperands ~= nil and #v.filterOperands or -1)
  if v.filterOperands ~= nil then
    for i = 1, #v.filterOperands do
      self:extensionObject(tools.index(v.filterOperands, i))
    end
  end
end
function dec:contentFilterElement()
  local filterOperator
  local noOfFilterOperands
  local filterOperands
  filterOperator = self:filterOperator()
  noOfFilterOperands = self:int32()
  if noOfFilterOperands ~= -1 then
    filterOperands = {}
    for _=1,noOfFilterOperands do
      local tmp
      tmp = self:extensionObject()
      tins(filterOperands, tmp)
    end
  end
  return {
    filterOperator = filterOperator,
    filterOperands = filterOperands,
  }
end
function enc:contentFilter(v)
  self:int32(v.elements ~= nil and #v.elements or -1)
  if v.elements ~= nil then
    for i = 1, #v.elements do
      self:contentFilterElement(tools.index(v.elements, i))
    end
  end
end
function dec:contentFilter()
  local noOfElements
  local elements
  noOfElements = self:int32()
  if noOfElements ~= -1 then
    elements = {}
    for _=1,noOfElements do
      local tmp
      tmp = self:contentFilterElement()
      tins(elements, tmp)
    end
  end
  return {
    elements = elements,
  }
end
function enc:filterOperand(v)
end
function dec:filterOperand()
  return {
  }
end
function enc:elementOperand(v)
  self:uint32(v.index)
end
function dec:elementOperand()
  local index
  index = self:uint32()
  return {
    index = index,
  }
end
function enc:literalOperand(v)
  self:variant(v.value)
end
function dec:literalOperand()
  local value
  value = self:variant()
  return {
    value = value,
  }
end
function enc:attributeOperand(v)
  self:nodeId(v.nodeId)
  self:string(v.alias)
  self:relativePath(v.browsePath)
  self:uint32(v.attributeId)
  self:string(v.indexRange)
end
function dec:attributeOperand()
  local nodeId
  local alias
  local browsePath
  local attributeId
  local indexRange
  nodeId = self:nodeId()
  alias = self:string()
  browsePath = self:relativePath()
  attributeId = self:uint32()
  indexRange = self:string()
  return {
    nodeId = nodeId,
    alias = alias,
    browsePath = browsePath,
    attributeId = attributeId,
    indexRange = indexRange,
  }
end
function enc:simpleAttributeOperand(v)
  self:nodeId(v.typeDefinitionId)
  self:int32(v.browsePath ~= nil and #v.browsePath or -1)
  if v.browsePath ~= nil then
    for i = 1, #v.browsePath do
      self:qualifiedName(tools.index(v.browsePath, i))
    end
  end
  self:uint32(v.attributeId)
  self:string(v.indexRange)
end
function dec:simpleAttributeOperand()
  local typeDefinitionId
  local noOfBrowsePath
  local browsePath
  local attributeId
  local indexRange
  typeDefinitionId = self:nodeId()
  noOfBrowsePath = self:int32()
  if noOfBrowsePath ~= -1 then
    browsePath = {}
    for _=1,noOfBrowsePath do
      local tmp
      tmp = self:qualifiedName()
      tins(browsePath, tmp)
    end
  end
  attributeId = self:uint32()
  indexRange = self:string()
  return {
    typeDefinitionId = typeDefinitionId,
    browsePath = browsePath,
    attributeId = attributeId,
    indexRange = indexRange,
  }
end
function enc:contentFilterElementResult(v)
  self:statusCode(v.statusCode)
  self:int32(v.operandStatusCodes ~= nil and #v.operandStatusCodes or -1)
  if v.operandStatusCodes ~= nil then
    for i = 1, #v.operandStatusCodes do
      self:statusCode(tools.index(v.operandStatusCodes, i))
    end
  end
  self:int32(v.operandDiagnosticInfos ~= nil and #v.operandDiagnosticInfos or -1)
  if v.operandDiagnosticInfos ~= nil then
    for i = 1, #v.operandDiagnosticInfos do
      self:diagnosticInfo(tools.index(v.operandDiagnosticInfos, i))
    end
  end
end
function dec:contentFilterElementResult()
  local statusCode
  local noOfOperandStatusCodes
  local operandStatusCodes
  local noOfOperandDiagnosticInfos
  local operandDiagnosticInfos
  statusCode = self:statusCode()
  noOfOperandStatusCodes = self:int32()
  if noOfOperandStatusCodes ~= -1 then
    operandStatusCodes = {}
    for _=1,noOfOperandStatusCodes do
      local tmp
      tmp = self:statusCode()
      tins(operandStatusCodes, tmp)
    end
  end
  noOfOperandDiagnosticInfos = self:int32()
  if noOfOperandDiagnosticInfos ~= -1 then
    operandDiagnosticInfos = {}
    for _=1,noOfOperandDiagnosticInfos do
      local tmp
      tmp = self:diagnosticInfo()
      tins(operandDiagnosticInfos, tmp)
    end
  end
  return {
    statusCode = statusCode,
    operandStatusCodes = operandStatusCodes,
    operandDiagnosticInfos = operandDiagnosticInfos,
  }
end
function enc:contentFilterResult(v)
  self:int32(v.elementResults ~= nil and #v.elementResults or -1)
  if v.elementResults ~= nil then
    for i = 1, #v.elementResults do
      self:contentFilterElementResult(tools.index(v.elementResults, i))
    end
  end
  self:int32(v.elementDiagnosticInfos ~= nil and #v.elementDiagnosticInfos or -1)
  if v.elementDiagnosticInfos ~= nil then
    for i = 1, #v.elementDiagnosticInfos do
      self:diagnosticInfo(tools.index(v.elementDiagnosticInfos, i))
    end
  end
end
function dec:contentFilterResult()
  local noOfElementResults
  local elementResults
  local noOfElementDiagnosticInfos
  local elementDiagnosticInfos
  noOfElementResults = self:int32()
  if noOfElementResults ~= -1 then
    elementResults = {}
    for _=1,noOfElementResults do
      local tmp
      tmp = self:contentFilterElementResult()
      tins(elementResults, tmp)
    end
  end
  noOfElementDiagnosticInfos = self:int32()
  if noOfElementDiagnosticInfos ~= -1 then
    elementDiagnosticInfos = {}
    for _=1,noOfElementDiagnosticInfos do
      local tmp
      tmp = self:diagnosticInfo()
      tins(elementDiagnosticInfos, tmp)
    end
  end
  return {
    elementResults = elementResults,
    elementDiagnosticInfos = elementDiagnosticInfos,
  }
end
function enc:parsingResult(v)
  self:statusCode(v.statusCode)
  self:int32(v.dataStatusCodes ~= nil and #v.dataStatusCodes or -1)
  if v.dataStatusCodes ~= nil then
    for i = 1, #v.dataStatusCodes do
      self:statusCode(tools.index(v.dataStatusCodes, i))
    end
  end
  self:int32(v.dataDiagnosticInfos ~= nil and #v.dataDiagnosticInfos or -1)
  if v.dataDiagnosticInfos ~= nil then
    for i = 1, #v.dataDiagnosticInfos do
      self:diagnosticInfo(tools.index(v.dataDiagnosticInfos, i))
    end
  end
end
function dec:parsingResult()
  local statusCode
  local noOfDataStatusCodes
  local dataStatusCodes
  local noOfDataDiagnosticInfos
  local dataDiagnosticInfos
  statusCode = self:statusCode()
  noOfDataStatusCodes = self:int32()
  if noOfDataStatusCodes ~= -1 then
    dataStatusCodes = {}
    for _=1,noOfDataStatusCodes do
      local tmp
      tmp = self:statusCode()
      tins(dataStatusCodes, tmp)
    end
  end
  noOfDataDiagnosticInfos = self:int32()
  if noOfDataDiagnosticInfos ~= -1 then
    dataDiagnosticInfos = {}
    for _=1,noOfDataDiagnosticInfos do
      local tmp
      tmp = self:diagnosticInfo()
      tins(dataDiagnosticInfos, tmp)
    end
  end
  return {
    statusCode = statusCode,
    dataStatusCodes = dataStatusCodes,
    dataDiagnosticInfos = dataDiagnosticInfos,
  }
end
function enc:queryFirstRequest(v)
  self:requestHeader(v.requestHeader)
  self:viewDescription(v.view)
  self:int32(v.nodeTypes ~= nil and #v.nodeTypes or -1)
  if v.nodeTypes ~= nil then
    for i = 1, #v.nodeTypes do
      self:nodeTypeDescription(tools.index(v.nodeTypes, i))
    end
  end
  self:contentFilter(v.filter)
  self:uint32(v.maxDataSetsToReturn)
  self:uint32(v.maxReferencesToReturn)
end
function dec:queryFirstRequest()
  local requestHeader
  local view
  local noOfNodeTypes
  local nodeTypes
  local filter
  local maxDataSetsToReturn
  local maxReferencesToReturn
  requestHeader = self:requestHeader()
  view = self:viewDescription()
  noOfNodeTypes = self:int32()
  if noOfNodeTypes ~= -1 then
    nodeTypes = {}
    for _=1,noOfNodeTypes do
      local tmp
      tmp = self:nodeTypeDescription()
      tins(nodeTypes, tmp)
    end
  end
  filter = self:contentFilter()
  maxDataSetsToReturn = self:uint32()
  maxReferencesToReturn = self:uint32()
  return {
    requestHeader = requestHeader,
    view = view,
    nodeTypes = nodeTypes,
    filter = filter,
    maxDataSetsToReturn = maxDataSetsToReturn,
    maxReferencesToReturn = maxReferencesToReturn,
  }
end
function enc:queryFirstResponse(v)
  self:responseHeader(v.responseHeader)
  self:int32(v.queryDataSets ~= nil and #v.queryDataSets or -1)
  if v.queryDataSets ~= nil then
    for i = 1, #v.queryDataSets do
      self:queryDataSet(tools.index(v.queryDataSets, i))
    end
  end
  self:byteString(v.continuationPoint)
  self:int32(v.parsingResults ~= nil and #v.parsingResults or -1)
  if v.parsingResults ~= nil then
    for i = 1, #v.parsingResults do
      self:parsingResult(tools.index(v.parsingResults, i))
    end
  end
  self:int32(v.diagnosticInfos ~= nil and #v.diagnosticInfos or -1)
  if v.diagnosticInfos ~= nil then
    for i = 1, #v.diagnosticInfos do
      self:diagnosticInfo(tools.index(v.diagnosticInfos, i))
    end
  end
  self:contentFilterResult(v.filterResult)
end
function dec:queryFirstResponse()
  local responseHeader
  local noOfQueryDataSets
  local queryDataSets
  local continuationPoint
  local noOfParsingResults
  local parsingResults
  local noOfDiagnosticInfos
  local diagnosticInfos
  local filterResult
  responseHeader = self:responseHeader()
  noOfQueryDataSets = self:int32()
  if noOfQueryDataSets ~= -1 then
    queryDataSets = {}
    for _=1,noOfQueryDataSets do
      local tmp
      tmp = self:queryDataSet()
      tins(queryDataSets, tmp)
    end
  end
  continuationPoint = self:byteString()
  noOfParsingResults = self:int32()
  if noOfParsingResults ~= -1 then
    parsingResults = {}
    for _=1,noOfParsingResults do
      local tmp
      tmp = self:parsingResult()
      tins(parsingResults, tmp)
    end
  end
  noOfDiagnosticInfos = self:int32()
  if noOfDiagnosticInfos ~= -1 then
    diagnosticInfos = {}
    for _=1,noOfDiagnosticInfos do
      local tmp
      tmp = self:diagnosticInfo()
      tins(diagnosticInfos, tmp)
    end
  end
  filterResult = self:contentFilterResult()
  return {
    responseHeader = responseHeader,
    queryDataSets = queryDataSets,
    continuationPoint = continuationPoint,
    parsingResults = parsingResults,
    diagnosticInfos = diagnosticInfos,
    filterResult = filterResult,
  }
end
function enc:queryNextRequest(v)
  self:requestHeader(v.requestHeader)
  self:boolean(v.releaseContinuationPoint)
  self:byteString(v.continuationPoint)
end
function dec:queryNextRequest()
  local requestHeader
  local releaseContinuationPoint
  local continuationPoint
  requestHeader = self:requestHeader()
  releaseContinuationPoint = self:boolean()
  continuationPoint = self:byteString()
  return {
    requestHeader = requestHeader,
    releaseContinuationPoint = releaseContinuationPoint,
    continuationPoint = continuationPoint,
  }
end
function enc:queryNextResponse(v)
  self:responseHeader(v.responseHeader)
  self:int32(v.queryDataSets ~= nil and #v.queryDataSets or -1)
  if v.queryDataSets ~= nil then
    for i = 1, #v.queryDataSets do
      self:queryDataSet(tools.index(v.queryDataSets, i))
    end
  end
  self:byteString(v.revisedContinuationPoint)
end
function dec:queryNextResponse()
  local responseHeader
  local noOfQueryDataSets
  local queryDataSets
  local revisedContinuationPoint
  responseHeader = self:responseHeader()
  noOfQueryDataSets = self:int32()
  if noOfQueryDataSets ~= -1 then
    queryDataSets = {}
    for _=1,noOfQueryDataSets do
      local tmp
      tmp = self:queryDataSet()
      tins(queryDataSets, tmp)
    end
  end
  revisedContinuationPoint = self:byteString()
  return {
    responseHeader = responseHeader,
    queryDataSets = queryDataSets,
    revisedContinuationPoint = revisedContinuationPoint,
  }
end
function enc:readValueId(v)
  self:nodeId(v.nodeId)
  self:uint32(v.attributeId)
  self:string(v.indexRange)
  self:qualifiedName(v.dataEncoding)
end
function dec:readValueId()
  local nodeId
  local attributeId
  local indexRange
  local dataEncoding
  nodeId = self:nodeId()
  attributeId = self:uint32()
  indexRange = self:string()
  dataEncoding = self:qualifiedName()
  return {
    nodeId = nodeId,
    attributeId = attributeId,
    indexRange = indexRange,
    dataEncoding = dataEncoding,
  }
end
function enc:readRequest(v)
  self:requestHeader(v.requestHeader)
  self:double(v.maxAge)
  self:timestampsToReturn(v.timestampsToReturn)
  self:int32(v.nodesToRead ~= nil and #v.nodesToRead or -1)
  if v.nodesToRead ~= nil then
    for i = 1, #v.nodesToRead do
      self:readValueId(tools.index(v.nodesToRead, i))
    end
  end
end
function dec:readRequest()
  local requestHeader
  local maxAge
  local timestampsToReturn
  local noOfNodesToRead
  local nodesToRead
  requestHeader = self:requestHeader()
  maxAge = self:double()
  timestampsToReturn = self:timestampsToReturn()
  noOfNodesToRead = self:int32()
  if noOfNodesToRead ~= -1 then
    nodesToRead = {}
    for _=1,noOfNodesToRead do
      local tmp
      tmp = self:readValueId()
      tins(nodesToRead, tmp)
    end
  end
  return {
    requestHeader = requestHeader,
    maxAge = maxAge,
    timestampsToReturn = timestampsToReturn,
    nodesToRead = nodesToRead,
  }
end
function enc:readResponse(v)
  self:responseHeader(v.responseHeader)
  self:int32(v.results ~= nil and #v.results or -1)
  if v.results ~= nil then
    for i = 1, #v.results do
      self:dataValue(tools.index(v.results, i))
    end
  end
  self:int32(v.diagnosticInfos ~= nil and #v.diagnosticInfos or -1)
  if v.diagnosticInfos ~= nil then
    for i = 1, #v.diagnosticInfos do
      self:diagnosticInfo(tools.index(v.diagnosticInfos, i))
    end
  end
end
function dec:readResponse()
  local responseHeader
  local noOfResults
  local results
  local noOfDiagnosticInfos
  local diagnosticInfos
  responseHeader = self:responseHeader()
  noOfResults = self:int32()
  if noOfResults ~= -1 then
    results = {}
    for _=1,noOfResults do
      local tmp
      tmp = self:dataValue()
      tins(results, tmp)
    end
  end
  noOfDiagnosticInfos = self:int32()
  if noOfDiagnosticInfos ~= -1 then
    diagnosticInfos = {}
    for _=1,noOfDiagnosticInfos do
      local tmp
      tmp = self:diagnosticInfo()
      tins(diagnosticInfos, tmp)
    end
  end
  return {
    responseHeader = responseHeader,
    results = results,
    diagnosticInfos = diagnosticInfos,
  }
end
function enc:historyReadValueId(v)
  self:nodeId(v.nodeId)
  self:string(v.indexRange)
  self:qualifiedName(v.dataEncoding)
  self:byteString(v.continuationPoint)
end
function dec:historyReadValueId()
  local nodeId
  local indexRange
  local dataEncoding
  local continuationPoint
  nodeId = self:nodeId()
  indexRange = self:string()
  dataEncoding = self:qualifiedName()
  continuationPoint = self:byteString()
  return {
    nodeId = nodeId,
    indexRange = indexRange,
    dataEncoding = dataEncoding,
    continuationPoint = continuationPoint,
  }
end
function enc:historyReadResult(v)
  self:statusCode(v.statusCode)
  self:byteString(v.continuationPoint)
  self:extensionObject(v.historyData)
end
function dec:historyReadResult()
  local statusCode
  local continuationPoint
  local historyData
  statusCode = self:statusCode()
  continuationPoint = self:byteString()
  historyData = self:extensionObject()
  return {
    statusCode = statusCode,
    continuationPoint = continuationPoint,
    historyData = historyData,
  }
end
function enc:historyReadDetails(v)
end
function dec:historyReadDetails()
  return {
  }
end
function enc:eventFilter(v)
  self:int32(v.selectClauses ~= nil and #v.selectClauses or -1)
  if v.selectClauses ~= nil then
    for i = 1, #v.selectClauses do
      self:simpleAttributeOperand(tools.index(v.selectClauses, i))
    end
  end
  self:contentFilter(v.whereClause)
end
function dec:eventFilter()
  local noOfSelectClauses
  local selectClauses
  local whereClause
  noOfSelectClauses = self:int32()
  if noOfSelectClauses ~= -1 then
    selectClauses = {}
    for _=1,noOfSelectClauses do
      local tmp
      tmp = self:simpleAttributeOperand()
      tins(selectClauses, tmp)
    end
  end
  whereClause = self:contentFilter()
  return {
    selectClauses = selectClauses,
    whereClause = whereClause,
  }
end
function enc:readEventDetails(v)
  self:uint32(v.numValuesPerNode)
  self:dateTime(v.startTime)
  self:dateTime(v.endTime)
  self:eventFilter(v.filter)
end
function dec:readEventDetails()
  local numValuesPerNode
  local startTime
  local endTime
  local filter
  numValuesPerNode = self:uint32()
  startTime = self:dateTime()
  endTime = self:dateTime()
  filter = self:eventFilter()
  return {
    numValuesPerNode = numValuesPerNode,
    startTime = startTime,
    endTime = endTime,
    filter = filter,
  }
end
function enc:readRawModifiedDetails(v)
  self:boolean(v.isReadModified)
  self:dateTime(v.startTime)
  self:dateTime(v.endTime)
  self:uint32(v.numValuesPerNode)
  self:boolean(v.returnBounds)
end
function dec:readRawModifiedDetails()
  local isReadModified
  local startTime
  local endTime
  local numValuesPerNode
  local returnBounds
  isReadModified = self:boolean()
  startTime = self:dateTime()
  endTime = self:dateTime()
  numValuesPerNode = self:uint32()
  returnBounds = self:boolean()
  return {
    isReadModified = isReadModified,
    startTime = startTime,
    endTime = endTime,
    numValuesPerNode = numValuesPerNode,
    returnBounds = returnBounds,
  }
end
function enc:aggregateConfiguration(v)
  self:boolean(v.useServerCapabilitiesDefaults)
  self:boolean(v.treatUncertainAsBad)
  self:byte(v.percentDataBad)
  self:byte(v.percentDataGood)
  self:boolean(v.useSlopedExtrapolation)
end
function dec:aggregateConfiguration()
  local useServerCapabilitiesDefaults
  local treatUncertainAsBad
  local percentDataBad
  local percentDataGood
  local useSlopedExtrapolation
  useServerCapabilitiesDefaults = self:boolean()
  treatUncertainAsBad = self:boolean()
  percentDataBad = self:byte()
  percentDataGood = self:byte()
  useSlopedExtrapolation = self:boolean()
  return {
    useServerCapabilitiesDefaults = useServerCapabilitiesDefaults,
    treatUncertainAsBad = treatUncertainAsBad,
    percentDataBad = percentDataBad,
    percentDataGood = percentDataGood,
    useSlopedExtrapolation = useSlopedExtrapolation,
  }
end
function enc:readProcessedDetails(v)
  self:dateTime(v.startTime)
  self:dateTime(v.endTime)
  self:double(v.processingInterval)
  self:int32(v.aggregateType ~= nil and #v.aggregateType or -1)
  if v.aggregateType ~= nil then
    for i = 1, #v.aggregateType do
      self:nodeId(tools.index(v.aggregateType, i))
    end
  end
  self:aggregateConfiguration(v.aggregateConfiguration)
end
function dec:readProcessedDetails()
  local startTime
  local endTime
  local processingInterval
  local noOfAggregateType
  local aggregateType
  local aggregateConfiguration
  startTime = self:dateTime()
  endTime = self:dateTime()
  processingInterval = self:double()
  noOfAggregateType = self:int32()
  if noOfAggregateType ~= -1 then
    aggregateType = {}
    for _=1,noOfAggregateType do
      local tmp
      tmp = self:nodeId()
      tins(aggregateType, tmp)
    end
  end
  aggregateConfiguration = self:aggregateConfiguration()
  return {
    startTime = startTime,
    endTime = endTime,
    processingInterval = processingInterval,
    aggregateType = aggregateType,
    aggregateConfiguration = aggregateConfiguration,
  }
end
function enc:readAtTimeDetails(v)
  self:int32(v.reqTimes ~= nil and #v.reqTimes or -1)
  if v.reqTimes ~= nil then
    for i = 1, #v.reqTimes do
      self:dateTime(tools.index(v.reqTimes, i))
    end
  end
  self:boolean(v.useSimpleBounds)
end
function dec:readAtTimeDetails()
  local noOfReqTimes
  local reqTimes
  local useSimpleBounds
  noOfReqTimes = self:int32()
  if noOfReqTimes ~= -1 then
    reqTimes = {}
    for _=1,noOfReqTimes do
      local tmp
      tmp = self:dateTime()
      tins(reqTimes, tmp)
    end
  end
  useSimpleBounds = self:boolean()
  return {
    reqTimes = reqTimes,
    useSimpleBounds = useSimpleBounds,
  }
end
function enc:historyData(v)
  self:int32(v.dataValues ~= nil and #v.dataValues or -1)
  if v.dataValues ~= nil then
    for i = 1, #v.dataValues do
      self:dataValue(tools.index(v.dataValues, i))
    end
  end
end
function dec:historyData()
  local noOfDataValues
  local dataValues
  noOfDataValues = self:int32()
  if noOfDataValues ~= -1 then
    dataValues = {}
    for _=1,noOfDataValues do
      local tmp
      tmp = self:dataValue()
      tins(dataValues, tmp)
    end
  end
  return {
    dataValues = dataValues,
  }
end
function enc:modificationInfo(v)
  self:dateTime(v.modificationTime)
  self:historyUpdateType(v.updateType)
  self:string(v.userName)
end
function dec:modificationInfo()
  local modificationTime
  local updateType
  local userName
  modificationTime = self:dateTime()
  updateType = self:historyUpdateType()
  userName = self:string()
  return {
    modificationTime = modificationTime,
    updateType = updateType,
    userName = userName,
  }
end
function enc:historyModifiedData(v)
  self:int32(v.dataValues ~= nil and #v.dataValues or -1)
  if v.dataValues ~= nil then
    for i = 1, #v.dataValues do
      self:dataValue(tools.index(v.dataValues, i))
    end
  end
  self:int32(v.modificationInfos ~= nil and #v.modificationInfos or -1)
  if v.modificationInfos ~= nil then
    for i = 1, #v.modificationInfos do
      self:modificationInfo(tools.index(v.modificationInfos, i))
    end
  end
end
function dec:historyModifiedData()
  local noOfDataValues
  local dataValues
  local noOfModificationInfos
  local modificationInfos
  noOfDataValues = self:int32()
  if noOfDataValues ~= -1 then
    dataValues = {}
    for _=1,noOfDataValues do
      local tmp
      tmp = self:dataValue()
      tins(dataValues, tmp)
    end
  end
  noOfModificationInfos = self:int32()
  if noOfModificationInfos ~= -1 then
    modificationInfos = {}
    for _=1,noOfModificationInfos do
      local tmp
      tmp = self:modificationInfo()
      tins(modificationInfos, tmp)
    end
  end
  return {
    dataValues = dataValues,
    modificationInfos = modificationInfos,
  }
end
function enc:historyEventFieldList(v)
  self:int32(v.eventFields ~= nil and #v.eventFields or -1)
  if v.eventFields ~= nil then
    for i = 1, #v.eventFields do
      self:variant(tools.index(v.eventFields, i))
    end
  end
end
function dec:historyEventFieldList()
  local noOfEventFields
  local eventFields
  noOfEventFields = self:int32()
  if noOfEventFields ~= -1 then
    eventFields = {}
    for _=1,noOfEventFields do
      local tmp
      tmp = self:variant()
      tins(eventFields, tmp)
    end
  end
  return {
    eventFields = eventFields,
  }
end
function enc:historyEvent(v)
  self:int32(v.events ~= nil and #v.events or -1)
  if v.events ~= nil then
    for i = 1, #v.events do
      self:historyEventFieldList(tools.index(v.events, i))
    end
  end
end
function dec:historyEvent()
  local noOfEvents
  local events
  noOfEvents = self:int32()
  if noOfEvents ~= -1 then
    events = {}
    for _=1,noOfEvents do
      local tmp
      tmp = self:historyEventFieldList()
      tins(events, tmp)
    end
  end
  return {
    events = events,
  }
end
function enc:historyReadRequest(v)
  self:requestHeader(v.requestHeader)
  self:extensionObject(v.historyReadDetails)
  self:timestampsToReturn(v.timestampsToReturn)
  self:boolean(v.releaseContinuationPoints)
  self:int32(v.nodesToRead ~= nil and #v.nodesToRead or -1)
  if v.nodesToRead ~= nil then
    for i = 1, #v.nodesToRead do
      self:historyReadValueId(tools.index(v.nodesToRead, i))
    end
  end
end
function dec:historyReadRequest()
  local requestHeader
  local historyReadDetails
  local timestampsToReturn
  local releaseContinuationPoints
  local noOfNodesToRead
  local nodesToRead
  requestHeader = self:requestHeader()
  historyReadDetails = self:extensionObject()
  timestampsToReturn = self:timestampsToReturn()
  releaseContinuationPoints = self:boolean()
  noOfNodesToRead = self:int32()
  if noOfNodesToRead ~= -1 then
    nodesToRead = {}
    for _=1,noOfNodesToRead do
      local tmp
      tmp = self:historyReadValueId()
      tins(nodesToRead, tmp)
    end
  end
  return {
    requestHeader = requestHeader,
    historyReadDetails = historyReadDetails,
    timestampsToReturn = timestampsToReturn,
    releaseContinuationPoints = releaseContinuationPoints,
    nodesToRead = nodesToRead,
  }
end
function enc:historyReadResponse(v)
  self:responseHeader(v.responseHeader)
  self:int32(v.results ~= nil and #v.results or -1)
  if v.results ~= nil then
    for i = 1, #v.results do
      self:historyReadResult(tools.index(v.results, i))
    end
  end
  self:int32(v.diagnosticInfos ~= nil and #v.diagnosticInfos or -1)
  if v.diagnosticInfos ~= nil then
    for i = 1, #v.diagnosticInfos do
      self:diagnosticInfo(tools.index(v.diagnosticInfos, i))
    end
  end
end
function dec:historyReadResponse()
  local responseHeader
  local noOfResults
  local results
  local noOfDiagnosticInfos
  local diagnosticInfos
  responseHeader = self:responseHeader()
  noOfResults = self:int32()
  if noOfResults ~= -1 then
    results = {}
    for _=1,noOfResults do
      local tmp
      tmp = self:historyReadResult()
      tins(results, tmp)
    end
  end
  noOfDiagnosticInfos = self:int32()
  if noOfDiagnosticInfos ~= -1 then
    diagnosticInfos = {}
    for _=1,noOfDiagnosticInfos do
      local tmp
      tmp = self:diagnosticInfo()
      tins(diagnosticInfos, tmp)
    end
  end
  return {
    responseHeader = responseHeader,
    results = results,
    diagnosticInfos = diagnosticInfos,
  }
end
function enc:writeValue(v)
  self:nodeId(v.nodeId)
  self:uint32(v.attributeId)
  self:string(v.indexRange)
  self:dataValue(v.value)
end
function dec:writeValue()
  local nodeId
  local attributeId
  local indexRange
  local value
  nodeId = self:nodeId()
  attributeId = self:uint32()
  indexRange = self:string()
  value = self:dataValue()
  return {
    nodeId = nodeId,
    attributeId = attributeId,
    indexRange = indexRange,
    value = value,
  }
end
function enc:writeRequest(v)
  self:requestHeader(v.requestHeader)
  self:int32(v.nodesToWrite ~= nil and #v.nodesToWrite or -1)
  if v.nodesToWrite ~= nil then
    for i = 1, #v.nodesToWrite do
      self:writeValue(tools.index(v.nodesToWrite, i))
    end
  end
end
function dec:writeRequest()
  local requestHeader
  local noOfNodesToWrite
  local nodesToWrite
  requestHeader = self:requestHeader()
  noOfNodesToWrite = self:int32()
  if noOfNodesToWrite ~= -1 then
    nodesToWrite = {}
    for _=1,noOfNodesToWrite do
      local tmp
      tmp = self:writeValue()
      tins(nodesToWrite, tmp)
    end
  end
  return {
    requestHeader = requestHeader,
    nodesToWrite = nodesToWrite,
  }
end
function enc:writeResponse(v)
  self:responseHeader(v.responseHeader)
  self:int32(v.results ~= nil and #v.results or -1)
  if v.results ~= nil then
    for i = 1, #v.results do
      self:statusCode(tools.index(v.results, i))
    end
  end
  self:int32(v.diagnosticInfos ~= nil and #v.diagnosticInfos or -1)
  if v.diagnosticInfos ~= nil then
    for i = 1, #v.diagnosticInfos do
      self:diagnosticInfo(tools.index(v.diagnosticInfos, i))
    end
  end
end
function dec:writeResponse()
  local responseHeader
  local noOfResults
  local results
  local noOfDiagnosticInfos
  local diagnosticInfos
  responseHeader = self:responseHeader()
  noOfResults = self:int32()
  if noOfResults ~= -1 then
    results = {}
    for _=1,noOfResults do
      local tmp
      tmp = self:statusCode()
      tins(results, tmp)
    end
  end
  noOfDiagnosticInfos = self:int32()
  if noOfDiagnosticInfos ~= -1 then
    diagnosticInfos = {}
    for _=1,noOfDiagnosticInfos do
      local tmp
      tmp = self:diagnosticInfo()
      tins(diagnosticInfos, tmp)
    end
  end
  return {
    responseHeader = responseHeader,
    results = results,
    diagnosticInfos = diagnosticInfos,
  }
end
function enc:historyUpdateDetails(v)
  self:nodeId(v.nodeId)
end
function dec:historyUpdateDetails()
  local nodeId
  nodeId = self:nodeId()
  return {
    nodeId = nodeId,
  }
end
function enc:updateDataDetails(v)
  self:nodeId(v.nodeId)
  self:performUpdateType(v.performInsertReplace)
  self:int32(v.updateValues ~= nil and #v.updateValues or -1)
  if v.updateValues ~= nil then
    for i = 1, #v.updateValues do
      self:dataValue(tools.index(v.updateValues, i))
    end
  end
end
function dec:updateDataDetails()
  local nodeId
  local performInsertReplace
  local noOfUpdateValues
  local updateValues
  nodeId = self:nodeId()
  performInsertReplace = self:performUpdateType()
  noOfUpdateValues = self:int32()
  if noOfUpdateValues ~= -1 then
    updateValues = {}
    for _=1,noOfUpdateValues do
      local tmp
      tmp = self:dataValue()
      tins(updateValues, tmp)
    end
  end
  return {
    nodeId = nodeId,
    performInsertReplace = performInsertReplace,
    updateValues = updateValues,
  }
end
function enc:updateStructureDataDetails(v)
  self:nodeId(v.nodeId)
  self:performUpdateType(v.performInsertReplace)
  self:int32(v.updateValues ~= nil and #v.updateValues or -1)
  if v.updateValues ~= nil then
    for i = 1, #v.updateValues do
      self:dataValue(tools.index(v.updateValues, i))
    end
  end
end
function dec:updateStructureDataDetails()
  local nodeId
  local performInsertReplace
  local noOfUpdateValues
  local updateValues
  nodeId = self:nodeId()
  performInsertReplace = self:performUpdateType()
  noOfUpdateValues = self:int32()
  if noOfUpdateValues ~= -1 then
    updateValues = {}
    for _=1,noOfUpdateValues do
      local tmp
      tmp = self:dataValue()
      tins(updateValues, tmp)
    end
  end
  return {
    nodeId = nodeId,
    performInsertReplace = performInsertReplace,
    updateValues = updateValues,
  }
end
function enc:updateEventDetails(v)
  self:nodeId(v.nodeId)
  self:performUpdateType(v.performInsertReplace)
  self:eventFilter(v.filter)
  self:int32(v.eventData ~= nil and #v.eventData or -1)
  if v.eventData ~= nil then
    for i = 1, #v.eventData do
      self:historyEventFieldList(tools.index(v.eventData, i))
    end
  end
end
function dec:updateEventDetails()
  local nodeId
  local performInsertReplace
  local filter
  local noOfEventData
  local eventData
  nodeId = self:nodeId()
  performInsertReplace = self:performUpdateType()
  filter = self:eventFilter()
  noOfEventData = self:int32()
  if noOfEventData ~= -1 then
    eventData = {}
    for _=1,noOfEventData do
      local tmp
      tmp = self:historyEventFieldList()
      tins(eventData, tmp)
    end
  end
  return {
    nodeId = nodeId,
    performInsertReplace = performInsertReplace,
    filter = filter,
    eventData = eventData,
  }
end
function enc:deleteRawModifiedDetails(v)
  self:nodeId(v.nodeId)
  self:boolean(v.isDeleteModified)
  self:dateTime(v.startTime)
  self:dateTime(v.endTime)
end
function dec:deleteRawModifiedDetails()
  local nodeId
  local isDeleteModified
  local startTime
  local endTime
  nodeId = self:nodeId()
  isDeleteModified = self:boolean()
  startTime = self:dateTime()
  endTime = self:dateTime()
  return {
    nodeId = nodeId,
    isDeleteModified = isDeleteModified,
    startTime = startTime,
    endTime = endTime,
  }
end
function enc:deleteAtTimeDetails(v)
  self:nodeId(v.nodeId)
  self:int32(v.reqTimes ~= nil and #v.reqTimes or -1)
  if v.reqTimes ~= nil then
    for i = 1, #v.reqTimes do
      self:dateTime(tools.index(v.reqTimes, i))
    end
  end
end
function dec:deleteAtTimeDetails()
  local nodeId
  local noOfReqTimes
  local reqTimes
  nodeId = self:nodeId()
  noOfReqTimes = self:int32()
  if noOfReqTimes ~= -1 then
    reqTimes = {}
    for _=1,noOfReqTimes do
      local tmp
      tmp = self:dateTime()
      tins(reqTimes, tmp)
    end
  end
  return {
    nodeId = nodeId,
    reqTimes = reqTimes,
  }
end
function enc:deleteEventDetails(v)
  self:nodeId(v.nodeId)
  self:int32(v.eventIds ~= nil and #v.eventIds or -1)
  if v.eventIds ~= nil then
    for i = 1, #v.eventIds do
      self:byteString(tools.index(v.eventIds, i))
    end
  end
end
function dec:deleteEventDetails()
  local nodeId
  local noOfEventIds
  local eventIds
  nodeId = self:nodeId()
  noOfEventIds = self:int32()
  if noOfEventIds ~= -1 then
    eventIds = {}
    for _=1,noOfEventIds do
      local tmp
      tmp = self:byteString()
      tins(eventIds, tmp)
    end
  end
  return {
    nodeId = nodeId,
    eventIds = eventIds,
  }
end
function enc:historyUpdateResult(v)
  self:statusCode(v.statusCode)
  self:int32(v.operationResults ~= nil and #v.operationResults or -1)
  if v.operationResults ~= nil then
    for i = 1, #v.operationResults do
      self:statusCode(tools.index(v.operationResults, i))
    end
  end
  self:int32(v.diagnosticInfos ~= nil and #v.diagnosticInfos or -1)
  if v.diagnosticInfos ~= nil then
    for i = 1, #v.diagnosticInfos do
      self:diagnosticInfo(tools.index(v.diagnosticInfos, i))
    end
  end
end
function dec:historyUpdateResult()
  local statusCode
  local noOfOperationResults
  local operationResults
  local noOfDiagnosticInfos
  local diagnosticInfos
  statusCode = self:statusCode()
  noOfOperationResults = self:int32()
  if noOfOperationResults ~= -1 then
    operationResults = {}
    for _=1,noOfOperationResults do
      local tmp
      tmp = self:statusCode()
      tins(operationResults, tmp)
    end
  end
  noOfDiagnosticInfos = self:int32()
  if noOfDiagnosticInfos ~= -1 then
    diagnosticInfos = {}
    for _=1,noOfDiagnosticInfos do
      local tmp
      tmp = self:diagnosticInfo()
      tins(diagnosticInfos, tmp)
    end
  end
  return {
    statusCode = statusCode,
    operationResults = operationResults,
    diagnosticInfos = diagnosticInfos,
  }
end
function enc:eventFilterResult(v)
  self:int32(v.selectClauseResults ~= nil and #v.selectClauseResults or -1)
  if v.selectClauseResults ~= nil then
    for i = 1, #v.selectClauseResults do
      self:statusCode(tools.index(v.selectClauseResults, i))
    end
  end
  self:int32(v.selectClauseDiagnosticInfos ~= nil and #v.selectClauseDiagnosticInfos or -1)
  if v.selectClauseDiagnosticInfos ~= nil then
    for i = 1, #v.selectClauseDiagnosticInfos do
      self:diagnosticInfo(tools.index(v.selectClauseDiagnosticInfos, i))
    end
  end
  self:contentFilterResult(v.whereClauseResult)
end
function dec:eventFilterResult()
  local noOfSelectClauseResults
  local selectClauseResults
  local noOfSelectClauseDiagnosticInfos
  local selectClauseDiagnosticInfos
  local whereClauseResult
  noOfSelectClauseResults = self:int32()
  if noOfSelectClauseResults ~= -1 then
    selectClauseResults = {}
    for _=1,noOfSelectClauseResults do
      local tmp
      tmp = self:statusCode()
      tins(selectClauseResults, tmp)
    end
  end
  noOfSelectClauseDiagnosticInfos = self:int32()
  if noOfSelectClauseDiagnosticInfos ~= -1 then
    selectClauseDiagnosticInfos = {}
    for _=1,noOfSelectClauseDiagnosticInfos do
      local tmp
      tmp = self:diagnosticInfo()
      tins(selectClauseDiagnosticInfos, tmp)
    end
  end
  whereClauseResult = self:contentFilterResult()
  return {
    selectClauseResults = selectClauseResults,
    selectClauseDiagnosticInfos = selectClauseDiagnosticInfos,
    whereClauseResult = whereClauseResult,
  }
end
function enc:historyUpdateEventResult(v)
  self:statusCode(v.statusCode)
  self:eventFilterResult(v.eventFilterResult)
end
function dec:historyUpdateEventResult()
  local statusCode
  local eventFilterResult
  statusCode = self:statusCode()
  eventFilterResult = self:eventFilterResult()
  return {
    statusCode = statusCode,
    eventFilterResult = eventFilterResult,
  }
end
function enc:historyUpdateRequest(v)
  self:requestHeader(v.requestHeader)
  self:int32(v.historyUpdateDetails ~= nil and #v.historyUpdateDetails or -1)
  if v.historyUpdateDetails ~= nil then
    for i = 1, #v.historyUpdateDetails do
      self:extensionObject(tools.index(v.historyUpdateDetails, i))
    end
  end
end
function dec:historyUpdateRequest()
  local requestHeader
  local noOfHistoryUpdateDetails
  local historyUpdateDetails
  requestHeader = self:requestHeader()
  noOfHistoryUpdateDetails = self:int32()
  if noOfHistoryUpdateDetails ~= -1 then
    historyUpdateDetails = {}
    for _=1,noOfHistoryUpdateDetails do
      local tmp
      tmp = self:extensionObject()
      tins(historyUpdateDetails, tmp)
    end
  end
  return {
    requestHeader = requestHeader,
    historyUpdateDetails = historyUpdateDetails,
  }
end
function enc:historyUpdateResponse(v)
  self:responseHeader(v.responseHeader)
  self:int32(v.results ~= nil and #v.results or -1)
  if v.results ~= nil then
    for i = 1, #v.results do
      self:historyUpdateResult(tools.index(v.results, i))
    end
  end
  self:int32(v.diagnosticInfos ~= nil and #v.diagnosticInfos or -1)
  if v.diagnosticInfos ~= nil then
    for i = 1, #v.diagnosticInfos do
      self:diagnosticInfo(tools.index(v.diagnosticInfos, i))
    end
  end
end
function dec:historyUpdateResponse()
  local responseHeader
  local noOfResults
  local results
  local noOfDiagnosticInfos
  local diagnosticInfos
  responseHeader = self:responseHeader()
  noOfResults = self:int32()
  if noOfResults ~= -1 then
    results = {}
    for _=1,noOfResults do
      local tmp
      tmp = self:historyUpdateResult()
      tins(results, tmp)
    end
  end
  noOfDiagnosticInfos = self:int32()
  if noOfDiagnosticInfos ~= -1 then
    diagnosticInfos = {}
    for _=1,noOfDiagnosticInfos do
      local tmp
      tmp = self:diagnosticInfo()
      tins(diagnosticInfos, tmp)
    end
  end
  return {
    responseHeader = responseHeader,
    results = results,
    diagnosticInfos = diagnosticInfos,
  }
end
function enc:callMethodRequest(v)
  self:nodeId(v.objectId)
  self:nodeId(v.methodId)
  self:int32(v.inputArguments ~= nil and #v.inputArguments or -1)
  if v.inputArguments ~= nil then
    for i = 1, #v.inputArguments do
      self:variant(tools.index(v.inputArguments, i))
    end
  end
end
function dec:callMethodRequest()
  local objectId
  local methodId
  local noOfInputArguments
  local inputArguments
  objectId = self:nodeId()
  methodId = self:nodeId()
  noOfInputArguments = self:int32()
  if noOfInputArguments ~= -1 then
    inputArguments = {}
    for _=1,noOfInputArguments do
      local tmp
      tmp = self:variant()
      tins(inputArguments, tmp)
    end
  end
  return {
    objectId = objectId,
    methodId = methodId,
    inputArguments = inputArguments,
  }
end
function enc:callMethodResult(v)
  self:statusCode(v.statusCode)
  self:int32(v.inputArgumentResults ~= nil and #v.inputArgumentResults or -1)
  if v.inputArgumentResults ~= nil then
    for i = 1, #v.inputArgumentResults do
      self:statusCode(tools.index(v.inputArgumentResults, i))
    end
  end
  self:int32(v.inputArgumentDiagnosticInfos ~= nil and #v.inputArgumentDiagnosticInfos or -1)
  if v.inputArgumentDiagnosticInfos ~= nil then
    for i = 1, #v.inputArgumentDiagnosticInfos do
      self:diagnosticInfo(tools.index(v.inputArgumentDiagnosticInfos, i))
    end
  end
  self:int32(v.outputArguments ~= nil and #v.outputArguments or -1)
  if v.outputArguments ~= nil then
    for i = 1, #v.outputArguments do
      self:variant(tools.index(v.outputArguments, i))
    end
  end
end
function dec:callMethodResult()
  local statusCode
  local noOfInputArgumentResults
  local inputArgumentResults
  local noOfInputArgumentDiagnosticInfos
  local inputArgumentDiagnosticInfos
  local noOfOutputArguments
  local outputArguments
  statusCode = self:statusCode()
  noOfInputArgumentResults = self:int32()
  if noOfInputArgumentResults ~= -1 then
    inputArgumentResults = {}
    for _=1,noOfInputArgumentResults do
      local tmp
      tmp = self:statusCode()
      tins(inputArgumentResults, tmp)
    end
  end
  noOfInputArgumentDiagnosticInfos = self:int32()
  if noOfInputArgumentDiagnosticInfos ~= -1 then
    inputArgumentDiagnosticInfos = {}
    for _=1,noOfInputArgumentDiagnosticInfos do
      local tmp
      tmp = self:diagnosticInfo()
      tins(inputArgumentDiagnosticInfos, tmp)
    end
  end
  noOfOutputArguments = self:int32()
  if noOfOutputArguments ~= -1 then
    outputArguments = {}
    for _=1,noOfOutputArguments do
      local tmp
      tmp = self:variant()
      tins(outputArguments, tmp)
    end
  end
  return {
    statusCode = statusCode,
    inputArgumentResults = inputArgumentResults,
    inputArgumentDiagnosticInfos = inputArgumentDiagnosticInfos,
    outputArguments = outputArguments,
  }
end
function enc:callRequest(v)
  self:requestHeader(v.requestHeader)
  self:int32(v.methodsToCall ~= nil and #v.methodsToCall or -1)
  if v.methodsToCall ~= nil then
    for i = 1, #v.methodsToCall do
      self:callMethodRequest(tools.index(v.methodsToCall, i))
    end
  end
end
function dec:callRequest()
  local requestHeader
  local noOfMethodsToCall
  local methodsToCall
  requestHeader = self:requestHeader()
  noOfMethodsToCall = self:int32()
  if noOfMethodsToCall ~= -1 then
    methodsToCall = {}
    for _=1,noOfMethodsToCall do
      local tmp
      tmp = self:callMethodRequest()
      tins(methodsToCall, tmp)
    end
  end
  return {
    requestHeader = requestHeader,
    methodsToCall = methodsToCall,
  }
end
function enc:callResponse(v)
  self:responseHeader(v.responseHeader)
  self:int32(v.results ~= nil and #v.results or -1)
  if v.results ~= nil then
    for i = 1, #v.results do
      self:callMethodResult(tools.index(v.results, i))
    end
  end
  self:int32(v.diagnosticInfos ~= nil and #v.diagnosticInfos or -1)
  if v.diagnosticInfos ~= nil then
    for i = 1, #v.diagnosticInfos do
      self:diagnosticInfo(tools.index(v.diagnosticInfos, i))
    end
  end
end
function dec:callResponse()
  local responseHeader
  local noOfResults
  local results
  local noOfDiagnosticInfos
  local diagnosticInfos
  responseHeader = self:responseHeader()
  noOfResults = self:int32()
  if noOfResults ~= -1 then
    results = {}
    for _=1,noOfResults do
      local tmp
      tmp = self:callMethodResult()
      tins(results, tmp)
    end
  end
  noOfDiagnosticInfos = self:int32()
  if noOfDiagnosticInfos ~= -1 then
    diagnosticInfos = {}
    for _=1,noOfDiagnosticInfos do
      local tmp
      tmp = self:diagnosticInfo()
      tins(diagnosticInfos, tmp)
    end
  end
  return {
    responseHeader = responseHeader,
    results = results,
    diagnosticInfos = diagnosticInfos,
  }
end
function enc:monitoringFilter(v)
end
function dec:monitoringFilter()
  return {
  }
end
function enc:dataChangeFilter(v)
  self:dataChangeTrigger(v.trigger)
  self:uint32(v.deadbandType)
  self:double(v.deadbandValue)
end
function dec:dataChangeFilter()
  local trigger
  local deadbandType
  local deadbandValue
  trigger = self:dataChangeTrigger()
  deadbandType = self:uint32()
  deadbandValue = self:double()
  return {
    trigger = trigger,
    deadbandType = deadbandType,
    deadbandValue = deadbandValue,
  }
end
function enc:aggregateFilter(v)
  self:dateTime(v.startTime)
  self:nodeId(v.aggregateType)
  self:double(v.processingInterval)
  self:aggregateConfiguration(v.aggregateConfiguration)
end
function dec:aggregateFilter()
  local startTime
  local aggregateType
  local processingInterval
  local aggregateConfiguration
  startTime = self:dateTime()
  aggregateType = self:nodeId()
  processingInterval = self:double()
  aggregateConfiguration = self:aggregateConfiguration()
  return {
    startTime = startTime,
    aggregateType = aggregateType,
    processingInterval = processingInterval,
    aggregateConfiguration = aggregateConfiguration,
  }
end
function enc:monitoringFilterResult(v)
end
function dec:monitoringFilterResult()
  return {
  }
end
function enc:aggregateFilterResult(v)
  self:dateTime(v.revisedStartTime)
  self:double(v.revisedProcessingInterval)
  self:aggregateConfiguration(v.revisedAggregateConfiguration)
end
function dec:aggregateFilterResult()
  local revisedStartTime
  local revisedProcessingInterval
  local revisedAggregateConfiguration
  revisedStartTime = self:dateTime()
  revisedProcessingInterval = self:double()
  revisedAggregateConfiguration = self:aggregateConfiguration()
  return {
    revisedStartTime = revisedStartTime,
    revisedProcessingInterval = revisedProcessingInterval,
    revisedAggregateConfiguration = revisedAggregateConfiguration,
  }
end
function enc:monitoringParameters(v)
  self:uint32(v.clientHandle)
  self:double(v.samplingInterval)
  self:extensionObject(v.filter)
  self:uint32(v.queueSize)
  self:boolean(v.discardOldest)
end
function dec:monitoringParameters()
  local clientHandle
  local samplingInterval
  local filter
  local queueSize
  local discardOldest
  clientHandle = self:uint32()
  samplingInterval = self:double()
  filter = self:extensionObject()
  queueSize = self:uint32()
  discardOldest = self:boolean()
  return {
    clientHandle = clientHandle,
    samplingInterval = samplingInterval,
    filter = filter,
    queueSize = queueSize,
    discardOldest = discardOldest,
  }
end
function enc:monitoredItemCreateRequest(v)
  self:readValueId(v.itemToMonitor)
  self:monitoringMode(v.monitoringMode)
  self:monitoringParameters(v.requestedParameters)
end
function dec:monitoredItemCreateRequest()
  local itemToMonitor
  local monitoringMode
  local requestedParameters
  itemToMonitor = self:readValueId()
  monitoringMode = self:monitoringMode()
  requestedParameters = self:monitoringParameters()
  return {
    itemToMonitor = itemToMonitor,
    monitoringMode = monitoringMode,
    requestedParameters = requestedParameters,
  }
end
function enc:monitoredItemCreateResult(v)
  self:statusCode(v.statusCode)
  self:uint32(v.monitoredItemId)
  self:double(v.revisedSamplingInterval)
  self:uint32(v.revisedQueueSize)
  self:extensionObject(v.filterResult)
end
function dec:monitoredItemCreateResult()
  local statusCode
  local monitoredItemId
  local revisedSamplingInterval
  local revisedQueueSize
  local filterResult
  statusCode = self:statusCode()
  monitoredItemId = self:uint32()
  revisedSamplingInterval = self:double()
  revisedQueueSize = self:uint32()
  filterResult = self:extensionObject()
  return {
    statusCode = statusCode,
    monitoredItemId = monitoredItemId,
    revisedSamplingInterval = revisedSamplingInterval,
    revisedQueueSize = revisedQueueSize,
    filterResult = filterResult,
  }
end
function enc:createMonitoredItemsRequest(v)
  self:requestHeader(v.requestHeader)
  self:uint32(v.subscriptionId)
  self:timestampsToReturn(v.timestampsToReturn)
  self:int32(v.itemsToCreate ~= nil and #v.itemsToCreate or -1)
  if v.itemsToCreate ~= nil then
    for i = 1, #v.itemsToCreate do
      self:monitoredItemCreateRequest(tools.index(v.itemsToCreate, i))
    end
  end
end
function dec:createMonitoredItemsRequest()
  local requestHeader
  local subscriptionId
  local timestampsToReturn
  local noOfItemsToCreate
  local itemsToCreate
  requestHeader = self:requestHeader()
  subscriptionId = self:uint32()
  timestampsToReturn = self:timestampsToReturn()
  noOfItemsToCreate = self:int32()
  if noOfItemsToCreate ~= -1 then
    itemsToCreate = {}
    for _=1,noOfItemsToCreate do
      local tmp
      tmp = self:monitoredItemCreateRequest()
      tins(itemsToCreate, tmp)
    end
  end
  return {
    requestHeader = requestHeader,
    subscriptionId = subscriptionId,
    timestampsToReturn = timestampsToReturn,
    itemsToCreate = itemsToCreate,
  }
end
function enc:createMonitoredItemsResponse(v)
  self:responseHeader(v.responseHeader)
  self:int32(v.results ~= nil and #v.results or -1)
  if v.results ~= nil then
    for i = 1, #v.results do
      self:monitoredItemCreateResult(tools.index(v.results, i))
    end
  end
  self:int32(v.diagnosticInfos ~= nil and #v.diagnosticInfos or -1)
  if v.diagnosticInfos ~= nil then
    for i = 1, #v.diagnosticInfos do
      self:diagnosticInfo(tools.index(v.diagnosticInfos, i))
    end
  end
end
function dec:createMonitoredItemsResponse()
  local responseHeader
  local noOfResults
  local results
  local noOfDiagnosticInfos
  local diagnosticInfos
  responseHeader = self:responseHeader()
  noOfResults = self:int32()
  if noOfResults ~= -1 then
    results = {}
    for _=1,noOfResults do
      local tmp
      tmp = self:monitoredItemCreateResult()
      tins(results, tmp)
    end
  end
  noOfDiagnosticInfos = self:int32()
  if noOfDiagnosticInfos ~= -1 then
    diagnosticInfos = {}
    for _=1,noOfDiagnosticInfos do
      local tmp
      tmp = self:diagnosticInfo()
      tins(diagnosticInfos, tmp)
    end
  end
  return {
    responseHeader = responseHeader,
    results = results,
    diagnosticInfos = diagnosticInfos,
  }
end
function enc:monitoredItemModifyRequest(v)
  self:uint32(v.monitoredItemId)
  self:monitoringParameters(v.requestedParameters)
end
function dec:monitoredItemModifyRequest()
  local monitoredItemId
  local requestedParameters
  monitoredItemId = self:uint32()
  requestedParameters = self:monitoringParameters()
  return {
    monitoredItemId = monitoredItemId,
    requestedParameters = requestedParameters,
  }
end
function enc:monitoredItemModifyResult(v)
  self:statusCode(v.statusCode)
  self:double(v.revisedSamplingInterval)
  self:uint32(v.revisedQueueSize)
  self:extensionObject(v.filterResult)
end
function dec:monitoredItemModifyResult()
  local statusCode
  local revisedSamplingInterval
  local revisedQueueSize
  local filterResult
  statusCode = self:statusCode()
  revisedSamplingInterval = self:double()
  revisedQueueSize = self:uint32()
  filterResult = self:extensionObject()
  return {
    statusCode = statusCode,
    revisedSamplingInterval = revisedSamplingInterval,
    revisedQueueSize = revisedQueueSize,
    filterResult = filterResult,
  }
end
function enc:modifyMonitoredItemsRequest(v)
  self:requestHeader(v.requestHeader)
  self:uint32(v.subscriptionId)
  self:timestampsToReturn(v.timestampsToReturn)
  self:int32(v.itemsToModify ~= nil and #v.itemsToModify or -1)
  if v.itemsToModify ~= nil then
    for i = 1, #v.itemsToModify do
      self:monitoredItemModifyRequest(tools.index(v.itemsToModify, i))
    end
  end
end
function dec:modifyMonitoredItemsRequest()
  local requestHeader
  local subscriptionId
  local timestampsToReturn
  local noOfItemsToModify
  local itemsToModify
  requestHeader = self:requestHeader()
  subscriptionId = self:uint32()
  timestampsToReturn = self:timestampsToReturn()
  noOfItemsToModify = self:int32()
  if noOfItemsToModify ~= -1 then
    itemsToModify = {}
    for _=1,noOfItemsToModify do
      local tmp
      tmp = self:monitoredItemModifyRequest()
      tins(itemsToModify, tmp)
    end
  end
  return {
    requestHeader = requestHeader,
    subscriptionId = subscriptionId,
    timestampsToReturn = timestampsToReturn,
    itemsToModify = itemsToModify,
  }
end
function enc:modifyMonitoredItemsResponse(v)
  self:responseHeader(v.responseHeader)
  self:int32(v.results ~= nil and #v.results or -1)
  if v.results ~= nil then
    for i = 1, #v.results do
      self:monitoredItemModifyResult(tools.index(v.results, i))
    end
  end
  self:int32(v.diagnosticInfos ~= nil and #v.diagnosticInfos or -1)
  if v.diagnosticInfos ~= nil then
    for i = 1, #v.diagnosticInfos do
      self:diagnosticInfo(tools.index(v.diagnosticInfos, i))
    end
  end
end
function dec:modifyMonitoredItemsResponse()
  local responseHeader
  local noOfResults
  local results
  local noOfDiagnosticInfos
  local diagnosticInfos
  responseHeader = self:responseHeader()
  noOfResults = self:int32()
  if noOfResults ~= -1 then
    results = {}
    for _=1,noOfResults do
      local tmp
      tmp = self:monitoredItemModifyResult()
      tins(results, tmp)
    end
  end
  noOfDiagnosticInfos = self:int32()
  if noOfDiagnosticInfos ~= -1 then
    diagnosticInfos = {}
    for _=1,noOfDiagnosticInfos do
      local tmp
      tmp = self:diagnosticInfo()
      tins(diagnosticInfos, tmp)
    end
  end
  return {
    responseHeader = responseHeader,
    results = results,
    diagnosticInfos = diagnosticInfos,
  }
end
function enc:setMonitoringModeRequest(v)
  self:requestHeader(v.requestHeader)
  self:uint32(v.subscriptionId)
  self:monitoringMode(v.monitoringMode)
  self:int32(v.monitoredItemIds ~= nil and #v.monitoredItemIds or -1)
  if v.monitoredItemIds ~= nil then
    for i = 1, #v.monitoredItemIds do
      self:uint32(tools.index(v.monitoredItemIds, i))
    end
  end
end
function dec:setMonitoringModeRequest()
  local requestHeader
  local subscriptionId
  local monitoringMode
  local noOfMonitoredItemIds
  local monitoredItemIds
  requestHeader = self:requestHeader()
  subscriptionId = self:uint32()
  monitoringMode = self:monitoringMode()
  noOfMonitoredItemIds = self:int32()
  if noOfMonitoredItemIds ~= -1 then
    monitoredItemIds = {}
    for _=1,noOfMonitoredItemIds do
      local tmp
      tmp = self:uint32()
      tins(monitoredItemIds, tmp)
    end
  end
  return {
    requestHeader = requestHeader,
    subscriptionId = subscriptionId,
    monitoringMode = monitoringMode,
    monitoredItemIds = monitoredItemIds,
  }
end
function enc:setMonitoringModeResponse(v)
  self:responseHeader(v.responseHeader)
  self:int32(v.results ~= nil and #v.results or -1)
  if v.results ~= nil then
    for i = 1, #v.results do
      self:statusCode(tools.index(v.results, i))
    end
  end
  self:int32(v.diagnosticInfos ~= nil and #v.diagnosticInfos or -1)
  if v.diagnosticInfos ~= nil then
    for i = 1, #v.diagnosticInfos do
      self:diagnosticInfo(tools.index(v.diagnosticInfos, i))
    end
  end
end
function dec:setMonitoringModeResponse()
  local responseHeader
  local noOfResults
  local results
  local noOfDiagnosticInfos
  local diagnosticInfos
  responseHeader = self:responseHeader()
  noOfResults = self:int32()
  if noOfResults ~= -1 then
    results = {}
    for _=1,noOfResults do
      local tmp
      tmp = self:statusCode()
      tins(results, tmp)
    end
  end
  noOfDiagnosticInfos = self:int32()
  if noOfDiagnosticInfos ~= -1 then
    diagnosticInfos = {}
    for _=1,noOfDiagnosticInfos do
      local tmp
      tmp = self:diagnosticInfo()
      tins(diagnosticInfos, tmp)
    end
  end
  return {
    responseHeader = responseHeader,
    results = results,
    diagnosticInfos = diagnosticInfos,
  }
end
function enc:setTriggeringRequest(v)
  self:requestHeader(v.requestHeader)
  self:uint32(v.subscriptionId)
  self:uint32(v.triggeringItemId)
  self:int32(v.linksToAdd ~= nil and #v.linksToAdd or -1)
  if v.linksToAdd ~= nil then
    for i = 1, #v.linksToAdd do
      self:uint32(tools.index(v.linksToAdd, i))
    end
  end
  self:int32(v.linksToRemove ~= nil and #v.linksToRemove or -1)
  if v.linksToRemove ~= nil then
    for i = 1, #v.linksToRemove do
      self:uint32(tools.index(v.linksToRemove, i))
    end
  end
end
function dec:setTriggeringRequest()
  local requestHeader
  local subscriptionId
  local triggeringItemId
  local noOfLinksToAdd
  local linksToAdd
  local noOfLinksToRemove
  local linksToRemove
  requestHeader = self:requestHeader()
  subscriptionId = self:uint32()
  triggeringItemId = self:uint32()
  noOfLinksToAdd = self:int32()
  if noOfLinksToAdd ~= -1 then
    linksToAdd = {}
    for _=1,noOfLinksToAdd do
      local tmp
      tmp = self:uint32()
      tins(linksToAdd, tmp)
    end
  end
  noOfLinksToRemove = self:int32()
  if noOfLinksToRemove ~= -1 then
    linksToRemove = {}
    for _=1,noOfLinksToRemove do
      local tmp
      tmp = self:uint32()
      tins(linksToRemove, tmp)
    end
  end
  return {
    requestHeader = requestHeader,
    subscriptionId = subscriptionId,
    triggeringItemId = triggeringItemId,
    linksToAdd = linksToAdd,
    linksToRemove = linksToRemove,
  }
end
function enc:setTriggeringResponse(v)
  self:responseHeader(v.responseHeader)
  self:int32(v.addResults ~= nil and #v.addResults or -1)
  if v.addResults ~= nil then
    for i = 1, #v.addResults do
      self:statusCode(tools.index(v.addResults, i))
    end
  end
  self:int32(v.addDiagnosticInfos ~= nil and #v.addDiagnosticInfos or -1)
  if v.addDiagnosticInfos ~= nil then
    for i = 1, #v.addDiagnosticInfos do
      self:diagnosticInfo(tools.index(v.addDiagnosticInfos, i))
    end
  end
  self:int32(v.removeResults ~= nil and #v.removeResults or -1)
  if v.removeResults ~= nil then
    for i = 1, #v.removeResults do
      self:statusCode(tools.index(v.removeResults, i))
    end
  end
  self:int32(v.removeDiagnosticInfos ~= nil and #v.removeDiagnosticInfos or -1)
  if v.removeDiagnosticInfos ~= nil then
    for i = 1, #v.removeDiagnosticInfos do
      self:diagnosticInfo(tools.index(v.removeDiagnosticInfos, i))
    end
  end
end
function dec:setTriggeringResponse()
  local responseHeader
  local noOfAddResults
  local addResults
  local noOfAddDiagnosticInfos
  local addDiagnosticInfos
  local noOfRemoveResults
  local removeResults
  local noOfRemoveDiagnosticInfos
  local removeDiagnosticInfos
  responseHeader = self:responseHeader()
  noOfAddResults = self:int32()
  if noOfAddResults ~= -1 then
    addResults = {}
    for _=1,noOfAddResults do
      local tmp
      tmp = self:statusCode()
      tins(addResults, tmp)
    end
  end
  noOfAddDiagnosticInfos = self:int32()
  if noOfAddDiagnosticInfos ~= -1 then
    addDiagnosticInfos = {}
    for _=1,noOfAddDiagnosticInfos do
      local tmp
      tmp = self:diagnosticInfo()
      tins(addDiagnosticInfos, tmp)
    end
  end
  noOfRemoveResults = self:int32()
  if noOfRemoveResults ~= -1 then
    removeResults = {}
    for _=1,noOfRemoveResults do
      local tmp
      tmp = self:statusCode()
      tins(removeResults, tmp)
    end
  end
  noOfRemoveDiagnosticInfos = self:int32()
  if noOfRemoveDiagnosticInfos ~= -1 then
    removeDiagnosticInfos = {}
    for _=1,noOfRemoveDiagnosticInfos do
      local tmp
      tmp = self:diagnosticInfo()
      tins(removeDiagnosticInfos, tmp)
    end
  end
  return {
    responseHeader = responseHeader,
    addResults = addResults,
    addDiagnosticInfos = addDiagnosticInfos,
    removeResults = removeResults,
    removeDiagnosticInfos = removeDiagnosticInfos,
  }
end
function enc:deleteMonitoredItemsRequest(v)
  self:requestHeader(v.requestHeader)
  self:uint32(v.subscriptionId)
  self:int32(v.monitoredItemIds ~= nil and #v.monitoredItemIds or -1)
  if v.monitoredItemIds ~= nil then
    for i = 1, #v.monitoredItemIds do
      self:uint32(tools.index(v.monitoredItemIds, i))
    end
  end
end
function dec:deleteMonitoredItemsRequest()
  local requestHeader
  local subscriptionId
  local noOfMonitoredItemIds
  local monitoredItemIds
  requestHeader = self:requestHeader()
  subscriptionId = self:uint32()
  noOfMonitoredItemIds = self:int32()
  if noOfMonitoredItemIds ~= -1 then
    monitoredItemIds = {}
    for _=1,noOfMonitoredItemIds do
      local tmp
      tmp = self:uint32()
      tins(monitoredItemIds, tmp)
    end
  end
  return {
    requestHeader = requestHeader,
    subscriptionId = subscriptionId,
    monitoredItemIds = monitoredItemIds,
  }
end
function enc:deleteMonitoredItemsResponse(v)
  self:responseHeader(v.responseHeader)
  self:int32(v.results ~= nil and #v.results or -1)
  if v.results ~= nil then
    for i = 1, #v.results do
      self:statusCode(tools.index(v.results, i))
    end
  end
  self:int32(v.diagnosticInfos ~= nil and #v.diagnosticInfos or -1)
  if v.diagnosticInfos ~= nil then
    for i = 1, #v.diagnosticInfos do
      self:diagnosticInfo(tools.index(v.diagnosticInfos, i))
    end
  end
end
function dec:deleteMonitoredItemsResponse()
  local responseHeader
  local noOfResults
  local results
  local noOfDiagnosticInfos
  local diagnosticInfos
  responseHeader = self:responseHeader()
  noOfResults = self:int32()
  if noOfResults ~= -1 then
    results = {}
    for _=1,noOfResults do
      local tmp
      tmp = self:statusCode()
      tins(results, tmp)
    end
  end
  noOfDiagnosticInfos = self:int32()
  if noOfDiagnosticInfos ~= -1 then
    diagnosticInfos = {}
    for _=1,noOfDiagnosticInfos do
      local tmp
      tmp = self:diagnosticInfo()
      tins(diagnosticInfos, tmp)
    end
  end
  return {
    responseHeader = responseHeader,
    results = results,
    diagnosticInfos = diagnosticInfos,
  }
end
function enc:createSubscriptionRequest(v)
  self:requestHeader(v.requestHeader)
  self:double(v.requestedPublishingInterval)
  self:uint32(v.requestedLifetimeCount)
  self:uint32(v.requestedMaxKeepAliveCount)
  self:uint32(v.maxNotificationsPerPublish)
  self:boolean(v.publishingEnabled)
  self:byte(v.priority)
end
function dec:createSubscriptionRequest()
  local requestHeader
  local requestedPublishingInterval
  local requestedLifetimeCount
  local requestedMaxKeepAliveCount
  local maxNotificationsPerPublish
  local publishingEnabled
  local priority
  requestHeader = self:requestHeader()
  requestedPublishingInterval = self:double()
  requestedLifetimeCount = self:uint32()
  requestedMaxKeepAliveCount = self:uint32()
  maxNotificationsPerPublish = self:uint32()
  publishingEnabled = self:boolean()
  priority = self:byte()
  return {
    requestHeader = requestHeader,
    requestedPublishingInterval = requestedPublishingInterval,
    requestedLifetimeCount = requestedLifetimeCount,
    requestedMaxKeepAliveCount = requestedMaxKeepAliveCount,
    maxNotificationsPerPublish = maxNotificationsPerPublish,
    publishingEnabled = publishingEnabled,
    priority = priority,
  }
end
function enc:createSubscriptionResponse(v)
  self:responseHeader(v.responseHeader)
  self:uint32(v.subscriptionId)
  self:double(v.revisedPublishingInterval)
  self:uint32(v.revisedLifetimeCount)
  self:uint32(v.revisedMaxKeepAliveCount)
end
function dec:createSubscriptionResponse()
  local responseHeader
  local subscriptionId
  local revisedPublishingInterval
  local revisedLifetimeCount
  local revisedMaxKeepAliveCount
  responseHeader = self:responseHeader()
  subscriptionId = self:uint32()
  revisedPublishingInterval = self:double()
  revisedLifetimeCount = self:uint32()
  revisedMaxKeepAliveCount = self:uint32()
  return {
    responseHeader = responseHeader,
    subscriptionId = subscriptionId,
    revisedPublishingInterval = revisedPublishingInterval,
    revisedLifetimeCount = revisedLifetimeCount,
    revisedMaxKeepAliveCount = revisedMaxKeepAliveCount,
  }
end
function enc:modifySubscriptionRequest(v)
  self:requestHeader(v.requestHeader)
  self:uint32(v.subscriptionId)
  self:double(v.requestedPublishingInterval)
  self:uint32(v.requestedLifetimeCount)
  self:uint32(v.requestedMaxKeepAliveCount)
  self:uint32(v.maxNotificationsPerPublish)
  self:byte(v.priority)
end
function dec:modifySubscriptionRequest()
  local requestHeader
  local subscriptionId
  local requestedPublishingInterval
  local requestedLifetimeCount
  local requestedMaxKeepAliveCount
  local maxNotificationsPerPublish
  local priority
  requestHeader = self:requestHeader()
  subscriptionId = self:uint32()
  requestedPublishingInterval = self:double()
  requestedLifetimeCount = self:uint32()
  requestedMaxKeepAliveCount = self:uint32()
  maxNotificationsPerPublish = self:uint32()
  priority = self:byte()
  return {
    requestHeader = requestHeader,
    subscriptionId = subscriptionId,
    requestedPublishingInterval = requestedPublishingInterval,
    requestedLifetimeCount = requestedLifetimeCount,
    requestedMaxKeepAliveCount = requestedMaxKeepAliveCount,
    maxNotificationsPerPublish = maxNotificationsPerPublish,
    priority = priority,
  }
end
function enc:modifySubscriptionResponse(v)
  self:responseHeader(v.responseHeader)
  self:double(v.revisedPublishingInterval)
  self:uint32(v.revisedLifetimeCount)
  self:uint32(v.revisedMaxKeepAliveCount)
end
function dec:modifySubscriptionResponse()
  local responseHeader
  local revisedPublishingInterval
  local revisedLifetimeCount
  local revisedMaxKeepAliveCount
  responseHeader = self:responseHeader()
  revisedPublishingInterval = self:double()
  revisedLifetimeCount = self:uint32()
  revisedMaxKeepAliveCount = self:uint32()
  return {
    responseHeader = responseHeader,
    revisedPublishingInterval = revisedPublishingInterval,
    revisedLifetimeCount = revisedLifetimeCount,
    revisedMaxKeepAliveCount = revisedMaxKeepAliveCount,
  }
end
function enc:setPublishingModeRequest(v)
  self:requestHeader(v.requestHeader)
  self:boolean(v.publishingEnabled)
  self:int32(v.subscriptionIds ~= nil and #v.subscriptionIds or -1)
  if v.subscriptionIds ~= nil then
    for i = 1, #v.subscriptionIds do
      self:uint32(tools.index(v.subscriptionIds, i))
    end
  end
end
function dec:setPublishingModeRequest()
  local requestHeader
  local publishingEnabled
  local noOfSubscriptionIds
  local subscriptionIds
  requestHeader = self:requestHeader()
  publishingEnabled = self:boolean()
  noOfSubscriptionIds = self:int32()
  if noOfSubscriptionIds ~= -1 then
    subscriptionIds = {}
    for _=1,noOfSubscriptionIds do
      local tmp
      tmp = self:uint32()
      tins(subscriptionIds, tmp)
    end
  end
  return {
    requestHeader = requestHeader,
    publishingEnabled = publishingEnabled,
    subscriptionIds = subscriptionIds,
  }
end
function enc:setPublishingModeResponse(v)
  self:responseHeader(v.responseHeader)
  self:int32(v.results ~= nil and #v.results or -1)
  if v.results ~= nil then
    for i = 1, #v.results do
      self:statusCode(tools.index(v.results, i))
    end
  end
  self:int32(v.diagnosticInfos ~= nil and #v.diagnosticInfos or -1)
  if v.diagnosticInfos ~= nil then
    for i = 1, #v.diagnosticInfos do
      self:diagnosticInfo(tools.index(v.diagnosticInfos, i))
    end
  end
end
function dec:setPublishingModeResponse()
  local responseHeader
  local noOfResults
  local results
  local noOfDiagnosticInfos
  local diagnosticInfos
  responseHeader = self:responseHeader()
  noOfResults = self:int32()
  if noOfResults ~= -1 then
    results = {}
    for _=1,noOfResults do
      local tmp
      tmp = self:statusCode()
      tins(results, tmp)
    end
  end
  noOfDiagnosticInfos = self:int32()
  if noOfDiagnosticInfos ~= -1 then
    diagnosticInfos = {}
    for _=1,noOfDiagnosticInfos do
      local tmp
      tmp = self:diagnosticInfo()
      tins(diagnosticInfos, tmp)
    end
  end
  return {
    responseHeader = responseHeader,
    results = results,
    diagnosticInfos = diagnosticInfos,
  }
end
function enc:notificationMessage(v)
  self:uint32(v.sequenceNumber)
  self:dateTime(v.publishTime)
  self:int32(v.notificationData ~= nil and #v.notificationData or -1)
  if v.notificationData ~= nil then
    for i = 1, #v.notificationData do
      self:extensionObject(tools.index(v.notificationData, i))
    end
  end
end
function dec:notificationMessage()
  local sequenceNumber
  local publishTime
  local noOfNotificationData
  local notificationData
  sequenceNumber = self:uint32()
  publishTime = self:dateTime()
  noOfNotificationData = self:int32()
  if noOfNotificationData ~= -1 then
    notificationData = {}
    for _=1,noOfNotificationData do
      local tmp
      tmp = self:extensionObject()
      tins(notificationData, tmp)
    end
  end
  return {
    sequenceNumber = sequenceNumber,
    publishTime = publishTime,
    notificationData = notificationData,
  }
end
function enc:notificationData(v)
end
function dec:notificationData()
  return {
  }
end
function enc:monitoredItemNotification(v)
  self:uint32(v.clientHandle)
  self:dataValue(v.value)
end
function dec:monitoredItemNotification()
  local clientHandle
  local value
  clientHandle = self:uint32()
  value = self:dataValue()
  return {
    clientHandle = clientHandle,
    value = value,
  }
end
function enc:dataChangeNotification(v)
  self:int32(v.monitoredItems ~= nil and #v.monitoredItems or -1)
  if v.monitoredItems ~= nil then
    for i = 1, #v.monitoredItems do
      self:monitoredItemNotification(tools.index(v.monitoredItems, i))
    end
  end
  self:int32(v.diagnosticInfos ~= nil and #v.diagnosticInfos or -1)
  if v.diagnosticInfos ~= nil then
    for i = 1, #v.diagnosticInfos do
      self:diagnosticInfo(tools.index(v.diagnosticInfos, i))
    end
  end
end
function dec:dataChangeNotification()
  local noOfMonitoredItems
  local monitoredItems
  local noOfDiagnosticInfos
  local diagnosticInfos
  noOfMonitoredItems = self:int32()
  if noOfMonitoredItems ~= -1 then
    monitoredItems = {}
    for _=1,noOfMonitoredItems do
      local tmp
      tmp = self:monitoredItemNotification()
      tins(monitoredItems, tmp)
    end
  end
  noOfDiagnosticInfos = self:int32()
  if noOfDiagnosticInfos ~= -1 then
    diagnosticInfos = {}
    for _=1,noOfDiagnosticInfos do
      local tmp
      tmp = self:diagnosticInfo()
      tins(diagnosticInfos, tmp)
    end
  end
  return {
    monitoredItems = monitoredItems,
    diagnosticInfos = diagnosticInfos,
  }
end
function enc:eventFieldList(v)
  self:uint32(v.clientHandle)
  self:int32(v.eventFields ~= nil and #v.eventFields or -1)
  if v.eventFields ~= nil then
    for i = 1, #v.eventFields do
      self:variant(tools.index(v.eventFields, i))
    end
  end
end
function dec:eventFieldList()
  local clientHandle
  local noOfEventFields
  local eventFields
  clientHandle = self:uint32()
  noOfEventFields = self:int32()
  if noOfEventFields ~= -1 then
    eventFields = {}
    for _=1,noOfEventFields do
      local tmp
      tmp = self:variant()
      tins(eventFields, tmp)
    end
  end
  return {
    clientHandle = clientHandle,
    eventFields = eventFields,
  }
end
function enc:eventNotificationList(v)
  self:int32(v.events ~= nil and #v.events or -1)
  if v.events ~= nil then
    for i = 1, #v.events do
      self:eventFieldList(tools.index(v.events, i))
    end
  end
end
function dec:eventNotificationList()
  local noOfEvents
  local events
  noOfEvents = self:int32()
  if noOfEvents ~= -1 then
    events = {}
    for _=1,noOfEvents do
      local tmp
      tmp = self:eventFieldList()
      tins(events, tmp)
    end
  end
  return {
    events = events,
  }
end
function enc:statusChangeNotification(v)
  self:statusCode(v.status)
  self:diagnosticInfo(v.diagnosticInfo)
end
function dec:statusChangeNotification()
  local status
  local diagnosticInfo
  status = self:statusCode()
  diagnosticInfo = self:diagnosticInfo()
  return {
    status = status,
    diagnosticInfo = diagnosticInfo,
  }
end
function enc:subscriptionAcknowledgement(v)
  self:uint32(v.subscriptionId)
  self:uint32(v.sequenceNumber)
end
function dec:subscriptionAcknowledgement()
  local subscriptionId
  local sequenceNumber
  subscriptionId = self:uint32()
  sequenceNumber = self:uint32()
  return {
    subscriptionId = subscriptionId,
    sequenceNumber = sequenceNumber,
  }
end
function enc:publishRequest(v)
  self:requestHeader(v.requestHeader)
  self:int32(v.subscriptionAcknowledgements ~= nil and #v.subscriptionAcknowledgements or -1)
  if v.subscriptionAcknowledgements ~= nil then
    for i = 1, #v.subscriptionAcknowledgements do
      self:subscriptionAcknowledgement(tools.index(v.subscriptionAcknowledgements, i))
    end
  end
end
function dec:publishRequest()
  local requestHeader
  local noOfSubscriptionAcknowledgements
  local subscriptionAcknowledgements
  requestHeader = self:requestHeader()
  noOfSubscriptionAcknowledgements = self:int32()
  if noOfSubscriptionAcknowledgements ~= -1 then
    subscriptionAcknowledgements = {}
    for _=1,noOfSubscriptionAcknowledgements do
      local tmp
      tmp = self:subscriptionAcknowledgement()
      tins(subscriptionAcknowledgements, tmp)
    end
  end
  return {
    requestHeader = requestHeader,
    subscriptionAcknowledgements = subscriptionAcknowledgements,
  }
end
function enc:publishResponse(v)
  self:responseHeader(v.responseHeader)
  self:uint32(v.subscriptionId)
  self:int32(v.availableSequenceNumbers ~= nil and #v.availableSequenceNumbers or -1)
  if v.availableSequenceNumbers ~= nil then
    for i = 1, #v.availableSequenceNumbers do
      self:uint32(tools.index(v.availableSequenceNumbers, i))
    end
  end
  self:boolean(v.moreNotifications)
  self:notificationMessage(v.notificationMessage)
  self:int32(v.results ~= nil and #v.results or -1)
  if v.results ~= nil then
    for i = 1, #v.results do
      self:statusCode(tools.index(v.results, i))
    end
  end
  self:int32(v.diagnosticInfos ~= nil and #v.diagnosticInfos or -1)
  if v.diagnosticInfos ~= nil then
    for i = 1, #v.diagnosticInfos do
      self:diagnosticInfo(tools.index(v.diagnosticInfos, i))
    end
  end
end
function dec:publishResponse()
  local responseHeader
  local subscriptionId
  local noOfAvailableSequenceNumbers
  local availableSequenceNumbers
  local moreNotifications
  local notificationMessage
  local noOfResults
  local results
  local noOfDiagnosticInfos
  local diagnosticInfos
  responseHeader = self:responseHeader()
  subscriptionId = self:uint32()
  noOfAvailableSequenceNumbers = self:int32()
  if noOfAvailableSequenceNumbers ~= -1 then
    availableSequenceNumbers = {}
    for _=1,noOfAvailableSequenceNumbers do
      local tmp
      tmp = self:uint32()
      tins(availableSequenceNumbers, tmp)
    end
  end
  moreNotifications = self:boolean()
  notificationMessage = self:notificationMessage()
  noOfResults = self:int32()
  if noOfResults ~= -1 then
    results = {}
    for _=1,noOfResults do
      local tmp
      tmp = self:statusCode()
      tins(results, tmp)
    end
  end
  noOfDiagnosticInfos = self:int32()
  if noOfDiagnosticInfos ~= -1 then
    diagnosticInfos = {}
    for _=1,noOfDiagnosticInfos do
      local tmp
      tmp = self:diagnosticInfo()
      tins(diagnosticInfos, tmp)
    end
  end
  return {
    responseHeader = responseHeader,
    subscriptionId = subscriptionId,
    availableSequenceNumbers = availableSequenceNumbers,
    moreNotifications = moreNotifications,
    notificationMessage = notificationMessage,
    results = results,
    diagnosticInfos = diagnosticInfos,
  }
end
function enc:republishRequest(v)
  self:requestHeader(v.requestHeader)
  self:uint32(v.subscriptionId)
  self:uint32(v.retransmitSequenceNumber)
end
function dec:republishRequest()
  local requestHeader
  local subscriptionId
  local retransmitSequenceNumber
  requestHeader = self:requestHeader()
  subscriptionId = self:uint32()
  retransmitSequenceNumber = self:uint32()
  return {
    requestHeader = requestHeader,
    subscriptionId = subscriptionId,
    retransmitSequenceNumber = retransmitSequenceNumber,
  }
end
function enc:republishResponse(v)
  self:responseHeader(v.responseHeader)
  self:notificationMessage(v.notificationMessage)
end
function dec:republishResponse()
  local responseHeader
  local notificationMessage
  responseHeader = self:responseHeader()
  notificationMessage = self:notificationMessage()
  return {
    responseHeader = responseHeader,
    notificationMessage = notificationMessage,
  }
end
function enc:transferResult(v)
  self:statusCode(v.statusCode)
  self:int32(v.availableSequenceNumbers ~= nil and #v.availableSequenceNumbers or -1)
  if v.availableSequenceNumbers ~= nil then
    for i = 1, #v.availableSequenceNumbers do
      self:uint32(tools.index(v.availableSequenceNumbers, i))
    end
  end
end
function dec:transferResult()
  local statusCode
  local noOfAvailableSequenceNumbers
  local availableSequenceNumbers
  statusCode = self:statusCode()
  noOfAvailableSequenceNumbers = self:int32()
  if noOfAvailableSequenceNumbers ~= -1 then
    availableSequenceNumbers = {}
    for _=1,noOfAvailableSequenceNumbers do
      local tmp
      tmp = self:uint32()
      tins(availableSequenceNumbers, tmp)
    end
  end
  return {
    statusCode = statusCode,
    availableSequenceNumbers = availableSequenceNumbers,
  }
end
function enc:transferSubscriptionsRequest(v)
  self:requestHeader(v.requestHeader)
  self:int32(v.subscriptionIds ~= nil and #v.subscriptionIds or -1)
  if v.subscriptionIds ~= nil then
    for i = 1, #v.subscriptionIds do
      self:uint32(tools.index(v.subscriptionIds, i))
    end
  end
  self:boolean(v.sendInitialValues)
end
function dec:transferSubscriptionsRequest()
  local requestHeader
  local noOfSubscriptionIds
  local subscriptionIds
  local sendInitialValues
  requestHeader = self:requestHeader()
  noOfSubscriptionIds = self:int32()
  if noOfSubscriptionIds ~= -1 then
    subscriptionIds = {}
    for _=1,noOfSubscriptionIds do
      local tmp
      tmp = self:uint32()
      tins(subscriptionIds, tmp)
    end
  end
  sendInitialValues = self:boolean()
  return {
    requestHeader = requestHeader,
    subscriptionIds = subscriptionIds,
    sendInitialValues = sendInitialValues,
  }
end
function enc:transferSubscriptionsResponse(v)
  self:responseHeader(v.responseHeader)
  self:int32(v.results ~= nil and #v.results or -1)
  if v.results ~= nil then
    for i = 1, #v.results do
      self:transferResult(tools.index(v.results, i))
    end
  end
  self:int32(v.diagnosticInfos ~= nil and #v.diagnosticInfos or -1)
  if v.diagnosticInfos ~= nil then
    for i = 1, #v.diagnosticInfos do
      self:diagnosticInfo(tools.index(v.diagnosticInfos, i))
    end
  end
end
function dec:transferSubscriptionsResponse()
  local responseHeader
  local noOfResults
  local results
  local noOfDiagnosticInfos
  local diagnosticInfos
  responseHeader = self:responseHeader()
  noOfResults = self:int32()
  if noOfResults ~= -1 then
    results = {}
    for _=1,noOfResults do
      local tmp
      tmp = self:transferResult()
      tins(results, tmp)
    end
  end
  noOfDiagnosticInfos = self:int32()
  if noOfDiagnosticInfos ~= -1 then
    diagnosticInfos = {}
    for _=1,noOfDiagnosticInfos do
      local tmp
      tmp = self:diagnosticInfo()
      tins(diagnosticInfos, tmp)
    end
  end
  return {
    responseHeader = responseHeader,
    results = results,
    diagnosticInfos = diagnosticInfos,
  }
end
function enc:deleteSubscriptionsRequest(v)
  self:requestHeader(v.requestHeader)
  self:int32(v.subscriptionIds ~= nil and #v.subscriptionIds or -1)
  if v.subscriptionIds ~= nil then
    for i = 1, #v.subscriptionIds do
      self:uint32(tools.index(v.subscriptionIds, i))
    end
  end
end
function dec:deleteSubscriptionsRequest()
  local requestHeader
  local noOfSubscriptionIds
  local subscriptionIds
  requestHeader = self:requestHeader()
  noOfSubscriptionIds = self:int32()
  if noOfSubscriptionIds ~= -1 then
    subscriptionIds = {}
    for _=1,noOfSubscriptionIds do
      local tmp
      tmp = self:uint32()
      tins(subscriptionIds, tmp)
    end
  end
  return {
    requestHeader = requestHeader,
    subscriptionIds = subscriptionIds,
  }
end
function enc:deleteSubscriptionsResponse(v)
  self:responseHeader(v.responseHeader)
  self:int32(v.results ~= nil and #v.results or -1)
  if v.results ~= nil then
    for i = 1, #v.results do
      self:statusCode(tools.index(v.results, i))
    end
  end
  self:int32(v.diagnosticInfos ~= nil and #v.diagnosticInfos or -1)
  if v.diagnosticInfos ~= nil then
    for i = 1, #v.diagnosticInfos do
      self:diagnosticInfo(tools.index(v.diagnosticInfos, i))
    end
  end
end
function dec:deleteSubscriptionsResponse()
  local responseHeader
  local noOfResults
  local results
  local noOfDiagnosticInfos
  local diagnosticInfos
  responseHeader = self:responseHeader()
  noOfResults = self:int32()
  if noOfResults ~= -1 then
    results = {}
    for _=1,noOfResults do
      local tmp
      tmp = self:statusCode()
      tins(results, tmp)
    end
  end
  noOfDiagnosticInfos = self:int32()
  if noOfDiagnosticInfos ~= -1 then
    diagnosticInfos = {}
    for _=1,noOfDiagnosticInfos do
      local tmp
      tmp = self:diagnosticInfo()
      tins(diagnosticInfos, tmp)
    end
  end
  return {
    responseHeader = responseHeader,
    results = results,
    diagnosticInfos = diagnosticInfos,
  }
end
function enc:scalarTestType(v)
  self:boolean(v.boolean)
  self:sbyte(v.sbyte)
  self:byte(v.byte)
  self:int16(v.int16)
  self:uint16(v.uint16)
  self:int32(v.int32)
  self:uint32(v.uint32)
  self:int64(v.int64)
  self:uint64(v.uint64)
  self:float(v.float)
  self:double(v.double)
  self:string(v.string)
  self:dateTime(v.dateTime)
  self:guid(v.guid)
  self:byteString(v.byteString)
  self:xmlElement(v.xmlElement)
  self:nodeId(v.nodeId)
  self:expandedNodeId(v.expandedNodeId)
  self:statusCode(v.statusCode)
  self:diagnosticInfo(v.diagnosticInfo)
  self:qualifiedName(v.qualifiedName)
  self:localizedText(v.localizedText)
  self:extensionObject(v.extensionObject)
  self:dataValue(v.dataValue)
  self:enumeratedTestType(v.enumeratedValue)
end
function dec:scalarTestType()
  local boolean
  local sbyte
  local byte
  local int16
  local uint16
  local int32
  local uint32
  local int64
  local uint64
  local float
  local double
  local string
  local dateTime
  local guid
  local byteString
  local xmlElement
  local nodeId
  local expandedNodeId
  local statusCode
  local diagnosticInfo
  local qualifiedName
  local localizedText
  local extensionObject
  local dataValue
  local enumeratedValue
  boolean = self:boolean()
  sbyte = self:sbyte()
  byte = self:byte()
  int16 = self:int16()
  uint16 = self:uint16()
  int32 = self:int32()
  uint32 = self:uint32()
  int64 = self:int64()
  uint64 = self:uint64()
  float = self:float()
  double = self:double()
  string = self:string()
  dateTime = self:dateTime()
  guid = self:guid()
  byteString = self:byteString()
  xmlElement = self:xmlElement()
  nodeId = self:nodeId()
  expandedNodeId = self:expandedNodeId()
  statusCode = self:statusCode()
  diagnosticInfo = self:diagnosticInfo()
  qualifiedName = self:qualifiedName()
  localizedText = self:localizedText()
  extensionObject = self:extensionObject()
  dataValue = self:dataValue()
  enumeratedValue = self:enumeratedTestType()
  return {
    boolean = boolean,
    sbyte = sbyte,
    byte = byte,
    int16 = int16,
    uint16 = uint16,
    int32 = int32,
    uint32 = uint32,
    int64 = int64,
    uint64 = uint64,
    float = float,
    double = double,
    string = string,
    dateTime = dateTime,
    guid = guid,
    byteString = byteString,
    xmlElement = xmlElement,
    nodeId = nodeId,
    expandedNodeId = expandedNodeId,
    statusCode = statusCode,
    diagnosticInfo = diagnosticInfo,
    qualifiedName = qualifiedName,
    localizedText = localizedText,
    extensionObject = extensionObject,
    dataValue = dataValue,
    enumeratedValue = enumeratedValue,
  }
end
function enc:arrayTestType(v)
  self:int32(v.booleans ~= nil and #v.booleans or -1)
  if v.booleans ~= nil then
    for i = 1, #v.booleans do
      self:boolean(tools.index(v.booleans, i))
    end
  end
  self:int32(v.sbytes ~= nil and #v.sbytes or -1)
  if v.sbytes ~= nil then
    for i = 1, #v.sbytes do
      self:sbyte(tools.index(v.sbytes, i))
    end
  end
  self:int32(v.int16s ~= nil and #v.int16s or -1)
  if v.int16s ~= nil then
    for i = 1, #v.int16s do
      self:int16(tools.index(v.int16s, i))
    end
  end
  self:int32(v.uint16s ~= nil and #v.uint16s or -1)
  if v.uint16s ~= nil then
    for i = 1, #v.uint16s do
      self:uint16(tools.index(v.uint16s, i))
    end
  end
  self:int32(v.int32s ~= nil and #v.int32s or -1)
  if v.int32s ~= nil then
    for i = 1, #v.int32s do
      self:int32(tools.index(v.int32s, i))
    end
  end
  self:int32(v.uint32s ~= nil and #v.uint32s or -1)
  if v.uint32s ~= nil then
    for i = 1, #v.uint32s do
      self:uint32(tools.index(v.uint32s, i))
    end
  end
  self:int32(v.int64s ~= nil and #v.int64s or -1)
  if v.int64s ~= nil then
    for i = 1, #v.int64s do
      self:int64(tools.index(v.int64s, i))
    end
  end
  self:int32(v.uint64s ~= nil and #v.uint64s or -1)
  if v.uint64s ~= nil then
    for i = 1, #v.uint64s do
      self:uint64(tools.index(v.uint64s, i))
    end
  end
  self:int32(v.floats ~= nil and #v.floats or -1)
  if v.floats ~= nil then
    for i = 1, #v.floats do
      self:float(tools.index(v.floats, i))
    end
  end
  self:int32(v.doubles ~= nil and #v.doubles or -1)
  if v.doubles ~= nil then
    for i = 1, #v.doubles do
      self:double(tools.index(v.doubles, i))
    end
  end
  self:int32(v.strings ~= nil and #v.strings or -1)
  if v.strings ~= nil then
    for i = 1, #v.strings do
      self:string(tools.index(v.strings, i))
    end
  end
  self:int32(v.dateTimes ~= nil and #v.dateTimes or -1)
  if v.dateTimes ~= nil then
    for i = 1, #v.dateTimes do
      self:dateTime(tools.index(v.dateTimes, i))
    end
  end
  self:int32(v.guids ~= nil and #v.guids or -1)
  if v.guids ~= nil then
    for i = 1, #v.guids do
      self:guid(tools.index(v.guids, i))
    end
  end
  self:int32(v.byteStrings ~= nil and #v.byteStrings or -1)
  if v.byteStrings ~= nil then
    for i = 1, #v.byteStrings do
      self:byteString(tools.index(v.byteStrings, i))
    end
  end
  self:int32(v.xmlElements ~= nil and #v.xmlElements or -1)
  if v.xmlElements ~= nil then
    for i = 1, #v.xmlElements do
      self:xmlElement(tools.index(v.xmlElements, i))
    end
  end
  self:int32(v.nodeIds ~= nil and #v.nodeIds or -1)
  if v.nodeIds ~= nil then
    for i = 1, #v.nodeIds do
      self:nodeId(tools.index(v.nodeIds, i))
    end
  end
  self:int32(v.expandedNodeIds ~= nil and #v.expandedNodeIds or -1)
  if v.expandedNodeIds ~= nil then
    for i = 1, #v.expandedNodeIds do
      self:expandedNodeId(tools.index(v.expandedNodeIds, i))
    end
  end
  self:int32(v.statusCodes ~= nil and #v.statusCodes or -1)
  if v.statusCodes ~= nil then
    for i = 1, #v.statusCodes do
      self:statusCode(tools.index(v.statusCodes, i))
    end
  end
  self:int32(v.diagnosticInfos ~= nil and #v.diagnosticInfos or -1)
  if v.diagnosticInfos ~= nil then
    for i = 1, #v.diagnosticInfos do
      self:diagnosticInfo(tools.index(v.diagnosticInfos, i))
    end
  end
  self:int32(v.qualifiedNames ~= nil and #v.qualifiedNames or -1)
  if v.qualifiedNames ~= nil then
    for i = 1, #v.qualifiedNames do
      self:qualifiedName(tools.index(v.qualifiedNames, i))
    end
  end
  self:int32(v.localizedTexts ~= nil and #v.localizedTexts or -1)
  if v.localizedTexts ~= nil then
    for i = 1, #v.localizedTexts do
      self:localizedText(tools.index(v.localizedTexts, i))
    end
  end
  self:int32(v.extensionObjects ~= nil and #v.extensionObjects or -1)
  if v.extensionObjects ~= nil then
    for i = 1, #v.extensionObjects do
      self:extensionObject(tools.index(v.extensionObjects, i))
    end
  end
  self:int32(v.dataValues ~= nil and #v.dataValues or -1)
  if v.dataValues ~= nil then
    for i = 1, #v.dataValues do
      self:dataValue(tools.index(v.dataValues, i))
    end
  end
  self:int32(v.variants ~= nil and #v.variants or -1)
  if v.variants ~= nil then
    for i = 1, #v.variants do
      self:variant(tools.index(v.variants, i))
    end
  end
  self:int32(v.enumeratedValues ~= nil and #v.enumeratedValues or -1)
  if v.enumeratedValues ~= nil then
    for i = 1, #v.enumeratedValues do
      self:enumeratedTestType(tools.index(v.enumeratedValues, i))
    end
  end
end
function dec:arrayTestType()
  local noOfBooleans
  local booleans
  local noOfSBytes
  local sbytes
  local noOfInt16s
  local int16s
  local noOfUInt16s
  local uint16s
  local noOfInt32s
  local int32s
  local noOfUInt32s
  local uint32s
  local noOfInt64s
  local int64s
  local noOfUInt64s
  local uint64s
  local noOfFloats
  local floats
  local noOfDoubles
  local doubles
  local noOfStrings
  local strings
  local noOfDateTimes
  local dateTimes
  local noOfGuids
  local guids
  local noOfByteStrings
  local byteStrings
  local noOfXmlElements
  local xmlElements
  local noOfNodeIds
  local nodeIds
  local noOfExpandedNodeIds
  local expandedNodeIds
  local noOfStatusCodes
  local statusCodes
  local noOfDiagnosticInfos
  local diagnosticInfos
  local noOfQualifiedNames
  local qualifiedNames
  local noOfLocalizedTexts
  local localizedTexts
  local noOfExtensionObjects
  local extensionObjects
  local noOfDataValues
  local dataValues
  local noOfVariants
  local variants
  local noOfEnumeratedValues
  local enumeratedValues
  noOfBooleans = self:int32()
  if noOfBooleans ~= -1 then
    booleans = {}
    for _=1,noOfBooleans do
      local tmp
      tmp = self:boolean()
      tins(booleans, tmp)
    end
  end
  noOfSBytes = self:int32()
  if noOfSBytes ~= -1 then
    sbytes = {}
    for _=1,noOfSBytes do
      local tmp
      tmp = self:sbyte()
      tins(sbytes, tmp)
    end
  end
  noOfInt16s = self:int32()
  if noOfInt16s ~= -1 then
    int16s = {}
    for _=1,noOfInt16s do
      local tmp
      tmp = self:int16()
      tins(int16s, tmp)
    end
  end
  noOfUInt16s = self:int32()
  if noOfUInt16s ~= -1 then
    uint16s = {}
    for _=1,noOfUInt16s do
      local tmp
      tmp = self:uint16()
      tins(uint16s, tmp)
    end
  end
  noOfInt32s = self:int32()
  if noOfInt32s ~= -1 then
    int32s = {}
    for _=1,noOfInt32s do
      local tmp
      tmp = self:int32()
      tins(int32s, tmp)
    end
  end
  noOfUInt32s = self:int32()
  if noOfUInt32s ~= -1 then
    uint32s = {}
    for _=1,noOfUInt32s do
      local tmp
      tmp = self:uint32()
      tins(uint32s, tmp)
    end
  end
  noOfInt64s = self:int32()
  if noOfInt64s ~= -1 then
    int64s = {}
    for _=1,noOfInt64s do
      local tmp
      tmp = self:int64()
      tins(int64s, tmp)
    end
  end
  noOfUInt64s = self:int32()
  if noOfUInt64s ~= -1 then
    uint64s = {}
    for _=1,noOfUInt64s do
      local tmp
      tmp = self:uint64()
      tins(uint64s, tmp)
    end
  end
  noOfFloats = self:int32()
  if noOfFloats ~= -1 then
    floats = {}
    for _=1,noOfFloats do
      local tmp
      tmp = self:float()
      tins(floats, tmp)
    end
  end
  noOfDoubles = self:int32()
  if noOfDoubles ~= -1 then
    doubles = {}
    for _=1,noOfDoubles do
      local tmp
      tmp = self:double()
      tins(doubles, tmp)
    end
  end
  noOfStrings = self:int32()
  if noOfStrings ~= -1 then
    strings = {}
    for _=1,noOfStrings do
      local tmp
      tmp = self:string()
      tins(strings, tmp)
    end
  end
  noOfDateTimes = self:int32()
  if noOfDateTimes ~= -1 then
    dateTimes = {}
    for _=1,noOfDateTimes do
      local tmp
      tmp = self:dateTime()
      tins(dateTimes, tmp)
    end
  end
  noOfGuids = self:int32()
  if noOfGuids ~= -1 then
    guids = {}
    for _=1,noOfGuids do
      local tmp
      tmp = self:guid()
      tins(guids, tmp)
    end
  end
  noOfByteStrings = self:int32()
  if noOfByteStrings ~= -1 then
    byteStrings = {}
    for _=1,noOfByteStrings do
      local tmp
      tmp = self:byteString()
      tins(byteStrings, tmp)
    end
  end
  noOfXmlElements = self:int32()
  if noOfXmlElements ~= -1 then
    xmlElements = {}
    for _=1,noOfXmlElements do
      local tmp
      tmp = self:xmlElement()
      tins(xmlElements, tmp)
    end
  end
  noOfNodeIds = self:int32()
  if noOfNodeIds ~= -1 then
    nodeIds = {}
    for _=1,noOfNodeIds do
      local tmp
      tmp = self:nodeId()
      tins(nodeIds, tmp)
    end
  end
  noOfExpandedNodeIds = self:int32()
  if noOfExpandedNodeIds ~= -1 then
    expandedNodeIds = {}
    for _=1,noOfExpandedNodeIds do
      local tmp
      tmp = self:expandedNodeId()
      tins(expandedNodeIds, tmp)
    end
  end
  noOfStatusCodes = self:int32()
  if noOfStatusCodes ~= -1 then
    statusCodes = {}
    for _=1,noOfStatusCodes do
      local tmp
      tmp = self:statusCode()
      tins(statusCodes, tmp)
    end
  end
  noOfDiagnosticInfos = self:int32()
  if noOfDiagnosticInfos ~= -1 then
    diagnosticInfos = {}
    for _=1,noOfDiagnosticInfos do
      local tmp
      tmp = self:diagnosticInfo()
      tins(diagnosticInfos, tmp)
    end
  end
  noOfQualifiedNames = self:int32()
  if noOfQualifiedNames ~= -1 then
    qualifiedNames = {}
    for _=1,noOfQualifiedNames do
      local tmp
      tmp = self:qualifiedName()
      tins(qualifiedNames, tmp)
    end
  end
  noOfLocalizedTexts = self:int32()
  if noOfLocalizedTexts ~= -1 then
    localizedTexts = {}
    for _=1,noOfLocalizedTexts do
      local tmp
      tmp = self:localizedText()
      tins(localizedTexts, tmp)
    end
  end
  noOfExtensionObjects = self:int32()
  if noOfExtensionObjects ~= -1 then
    extensionObjects = {}
    for _=1,noOfExtensionObjects do
      local tmp
      tmp = self:extensionObject()
      tins(extensionObjects, tmp)
    end
  end
  noOfDataValues = self:int32()
  if noOfDataValues ~= -1 then
    dataValues = {}
    for _=1,noOfDataValues do
      local tmp
      tmp = self:dataValue()
      tins(dataValues, tmp)
    end
  end
  noOfVariants = self:int32()
  if noOfVariants ~= -1 then
    variants = {}
    for _=1,noOfVariants do
      local tmp
      tmp = self:variant()
      tins(variants, tmp)
    end
  end
  noOfEnumeratedValues = self:int32()
  if noOfEnumeratedValues ~= -1 then
    enumeratedValues = {}
    for _=1,noOfEnumeratedValues do
      local tmp
      tmp = self:enumeratedTestType()
      tins(enumeratedValues, tmp)
    end
  end
  return {
    booleans = booleans,
    sbytes = sbytes,
    int16s = int16s,
    uint16s = uint16s,
    int32s = int32s,
    uint32s = uint32s,
    int64s = int64s,
    uint64s = uint64s,
    floats = floats,
    doubles = doubles,
    strings = strings,
    dateTimes = dateTimes,
    guids = guids,
    byteStrings = byteStrings,
    xmlElements = xmlElements,
    nodeIds = nodeIds,
    expandedNodeIds = expandedNodeIds,
    statusCodes = statusCodes,
    diagnosticInfos = diagnosticInfos,
    qualifiedNames = qualifiedNames,
    localizedTexts = localizedTexts,
    extensionObjects = extensionObjects,
    dataValues = dataValues,
    variants = variants,
    enumeratedValues = enumeratedValues,
  }
end
function enc:compositeTestType(v)
  self:scalarTestType(v.field1)
  self:arrayTestType(v.field2)
end
function dec:compositeTestType()
  local field1
  local field2
  field1 = self:scalarTestType()
  field2 = self:arrayTestType()
  return {
    field1 = field1,
    field2 = field2,
  }
end
function enc:testStackRequest(v)
  self:requestHeader(v.requestHeader)
  self:uint32(v.testId)
  self:int32(v.iteration)
  self:variant(v.input)
end
function dec:testStackRequest()
  local requestHeader
  local testId
  local iteration
  local input
  requestHeader = self:requestHeader()
  testId = self:uint32()
  iteration = self:int32()
  input = self:variant()
  return {
    requestHeader = requestHeader,
    testId = testId,
    iteration = iteration,
    input = input,
  }
end
function enc:testStackResponse(v)
  self:responseHeader(v.responseHeader)
  self:variant(v.output)
end
function dec:testStackResponse()
  local responseHeader
  local output
  responseHeader = self:responseHeader()
  output = self:variant()
  return {
    responseHeader = responseHeader,
    output = output,
  }
end
function enc:testStackExRequest(v)
  self:requestHeader(v.requestHeader)
  self:uint32(v.testId)
  self:int32(v.iteration)
  self:compositeTestType(v.input)
end
function dec:testStackExRequest()
  local requestHeader
  local testId
  local iteration
  local input
  requestHeader = self:requestHeader()
  testId = self:uint32()
  iteration = self:int32()
  input = self:compositeTestType()
  return {
    requestHeader = requestHeader,
    testId = testId,
    iteration = iteration,
    input = input,
  }
end
function enc:testStackExResponse(v)
  self:responseHeader(v.responseHeader)
  self:compositeTestType(v.output)
end
function dec:testStackExResponse()
  local responseHeader
  local output
  responseHeader = self:responseHeader()
  output = self:compositeTestType()
  return {
    responseHeader = responseHeader,
    output = output,
  }
end
function enc:buildInfo(v)
  self:string(v.productUri)
  self:string(v.manufacturerName)
  self:string(v.productName)
  self:string(v.softwareVersion)
  self:string(v.buildNumber)
  self:dateTime(v.buildDate)
end
function dec:buildInfo()
  local productUri
  local manufacturerName
  local productName
  local softwareVersion
  local buildNumber
  local buildDate
  productUri = self:string()
  manufacturerName = self:string()
  productName = self:string()
  softwareVersion = self:string()
  buildNumber = self:string()
  buildDate = self:dateTime()
  return {
    productUri = productUri,
    manufacturerName = manufacturerName,
    productName = productName,
    softwareVersion = softwareVersion,
    buildNumber = buildNumber,
    buildDate = buildDate,
  }
end
function enc:redundantServerDataType(v)
  self:string(v.serverId)
  self:byte(v.serviceLevel)
  self:serverState(v.serverState)
end
function dec:redundantServerDataType()
  local serverId
  local serviceLevel
  local serverState
  serverId = self:string()
  serviceLevel = self:byte()
  serverState = self:serverState()
  return {
    serverId = serverId,
    serviceLevel = serviceLevel,
    serverState = serverState,
  }
end
function enc:endpointUrlListDataType(v)
  self:int32(v.endpointUrlList ~= nil and #v.endpointUrlList or -1)
  if v.endpointUrlList ~= nil then
    for i = 1, #v.endpointUrlList do
      self:string(tools.index(v.endpointUrlList, i))
    end
  end
end
function dec:endpointUrlListDataType()
  local noOfEndpointUrlList
  local endpointUrlList
  noOfEndpointUrlList = self:int32()
  if noOfEndpointUrlList ~= -1 then
    endpointUrlList = {}
    for _=1,noOfEndpointUrlList do
      local tmp
      tmp = self:string()
      tins(endpointUrlList, tmp)
    end
  end
  return {
    endpointUrlList = endpointUrlList,
  }
end
function enc:networkGroupDataType(v)
  self:string(v.serverUri)
  self:int32(v.networkPaths ~= nil and #v.networkPaths or -1)
  if v.networkPaths ~= nil then
    for i = 1, #v.networkPaths do
      self:endpointUrlListDataType(tools.index(v.networkPaths, i))
    end
  end
end
function dec:networkGroupDataType()
  local serverUri
  local noOfNetworkPaths
  local networkPaths
  serverUri = self:string()
  noOfNetworkPaths = self:int32()
  if noOfNetworkPaths ~= -1 then
    networkPaths = {}
    for _=1,noOfNetworkPaths do
      local tmp
      tmp = self:endpointUrlListDataType()
      tins(networkPaths, tmp)
    end
  end
  return {
    serverUri = serverUri,
    networkPaths = networkPaths,
  }
end
function enc:samplingIntervalDiagnosticsDataType(v)
  self:double(v.samplingInterval)
  self:uint32(v.monitoredItemCount)
  self:uint32(v.maxMonitoredItemCount)
  self:uint32(v.disabledMonitoredItemCount)
end
function dec:samplingIntervalDiagnosticsDataType()
  local samplingInterval
  local monitoredItemCount
  local maxMonitoredItemCount
  local disabledMonitoredItemCount
  samplingInterval = self:double()
  monitoredItemCount = self:uint32()
  maxMonitoredItemCount = self:uint32()
  disabledMonitoredItemCount = self:uint32()
  return {
    samplingInterval = samplingInterval,
    monitoredItemCount = monitoredItemCount,
    maxMonitoredItemCount = maxMonitoredItemCount,
    disabledMonitoredItemCount = disabledMonitoredItemCount,
  }
end
function enc:serverDiagnosticsSummaryDataType(v)
  self:uint32(v.serverViewCount)
  self:uint32(v.currentSessionCount)
  self:uint32(v.cumulatedSessionCount)
  self:uint32(v.securityRejectedSessionCount)
  self:uint32(v.rejectedSessionCount)
  self:uint32(v.sessionTimeoutCount)
  self:uint32(v.sessionAbortCount)
  self:uint32(v.currentSubscriptionCount)
  self:uint32(v.cumulatedSubscriptionCount)
  self:uint32(v.publishingIntervalCount)
  self:uint32(v.securityRejectedRequestsCount)
  self:uint32(v.rejectedRequestsCount)
end
function dec:serverDiagnosticsSummaryDataType()
  local serverViewCount
  local currentSessionCount
  local cumulatedSessionCount
  local securityRejectedSessionCount
  local rejectedSessionCount
  local sessionTimeoutCount
  local sessionAbortCount
  local currentSubscriptionCount
  local cumulatedSubscriptionCount
  local publishingIntervalCount
  local securityRejectedRequestsCount
  local rejectedRequestsCount
  serverViewCount = self:uint32()
  currentSessionCount = self:uint32()
  cumulatedSessionCount = self:uint32()
  securityRejectedSessionCount = self:uint32()
  rejectedSessionCount = self:uint32()
  sessionTimeoutCount = self:uint32()
  sessionAbortCount = self:uint32()
  currentSubscriptionCount = self:uint32()
  cumulatedSubscriptionCount = self:uint32()
  publishingIntervalCount = self:uint32()
  securityRejectedRequestsCount = self:uint32()
  rejectedRequestsCount = self:uint32()
  return {
    serverViewCount = serverViewCount,
    currentSessionCount = currentSessionCount,
    cumulatedSessionCount = cumulatedSessionCount,
    securityRejectedSessionCount = securityRejectedSessionCount,
    rejectedSessionCount = rejectedSessionCount,
    sessionTimeoutCount = sessionTimeoutCount,
    sessionAbortCount = sessionAbortCount,
    currentSubscriptionCount = currentSubscriptionCount,
    cumulatedSubscriptionCount = cumulatedSubscriptionCount,
    publishingIntervalCount = publishingIntervalCount,
    securityRejectedRequestsCount = securityRejectedRequestsCount,
    rejectedRequestsCount = rejectedRequestsCount,
  }
end
function enc:serverStatusDataType(v)
  self:dateTime(v.startTime)
  self:dateTime(v.currentTime)
  self:serverState(v.state)
  self:buildInfo(v.buildInfo)
  self:uint32(v.secondsTillShutdown)
  self:localizedText(v.shutdownReason)
end
function dec:serverStatusDataType()
  local startTime
  local currentTime
  local state
  local buildInfo
  local secondsTillShutdown
  local shutdownReason
  startTime = self:dateTime()
  currentTime = self:dateTime()
  state = self:serverState()
  buildInfo = self:buildInfo()
  secondsTillShutdown = self:uint32()
  shutdownReason = self:localizedText()
  return {
    startTime = startTime,
    currentTime = currentTime,
    state = state,
    buildInfo = buildInfo,
    secondsTillShutdown = secondsTillShutdown,
    shutdownReason = shutdownReason,
  }
end
function enc:serviceCounterDataType(v)
  self:uint32(v.totalCount)
  self:uint32(v.errorCount)
end
function dec:serviceCounterDataType()
  local totalCount
  local errorCount
  totalCount = self:uint32()
  errorCount = self:uint32()
  return {
    totalCount = totalCount,
    errorCount = errorCount,
  }
end
function enc:sessionDiagnosticsDataType(v)
  self:nodeId(v.sessionId)
  self:string(v.sessionName)
  self:applicationDescription(v.clientDescription)
  self:string(v.serverUri)
  self:string(v.endpointUrl)
  self:int32(v.localeIds ~= nil and #v.localeIds or -1)
  if v.localeIds ~= nil then
    for i = 1, #v.localeIds do
      self:string(tools.index(v.localeIds, i))
    end
  end
  self:double(v.actualSessionTimeout)
  self:uint32(v.maxResponseMessageSize)
  self:dateTime(v.clientConnectionTime)
  self:dateTime(v.clientLastContactTime)
  self:uint32(v.currentSubscriptionsCount)
  self:uint32(v.currentMonitoredItemsCount)
  self:uint32(v.currentPublishRequestsInQueue)
  self:serviceCounterDataType(v.totalRequestCount)
  self:uint32(v.unauthorizedRequestCount)
  self:serviceCounterDataType(v.readCount)
  self:serviceCounterDataType(v.historyReadCount)
  self:serviceCounterDataType(v.writeCount)
  self:serviceCounterDataType(v.historyUpdateCount)
  self:serviceCounterDataType(v.callCount)
  self:serviceCounterDataType(v.createMonitoredItemsCount)
  self:serviceCounterDataType(v.modifyMonitoredItemsCount)
  self:serviceCounterDataType(v.setMonitoringModeCount)
  self:serviceCounterDataType(v.setTriggeringCount)
  self:serviceCounterDataType(v.deleteMonitoredItemsCount)
  self:serviceCounterDataType(v.createSubscriptionCount)
  self:serviceCounterDataType(v.modifySubscriptionCount)
  self:serviceCounterDataType(v.setPublishingModeCount)
  self:serviceCounterDataType(v.publishCount)
  self:serviceCounterDataType(v.republishCount)
  self:serviceCounterDataType(v.transferSubscriptionsCount)
  self:serviceCounterDataType(v.deleteSubscriptionsCount)
  self:serviceCounterDataType(v.addNodesCount)
  self:serviceCounterDataType(v.addReferencesCount)
  self:serviceCounterDataType(v.deleteNodesCount)
  self:serviceCounterDataType(v.deleteReferencesCount)
  self:serviceCounterDataType(v.browseCount)
  self:serviceCounterDataType(v.browseNextCount)
  self:serviceCounterDataType(v.translateBrowsePathsToNodeIdsCount)
  self:serviceCounterDataType(v.queryFirstCount)
  self:serviceCounterDataType(v.queryNextCount)
  self:serviceCounterDataType(v.registerNodesCount)
  self:serviceCounterDataType(v.unregisterNodesCount)
end
function dec:sessionDiagnosticsDataType()
  local sessionId
  local sessionName
  local clientDescription
  local serverUri
  local endpointUrl
  local noOfLocaleIds
  local localeIds
  local actualSessionTimeout
  local maxResponseMessageSize
  local clientConnectionTime
  local clientLastContactTime
  local currentSubscriptionsCount
  local currentMonitoredItemsCount
  local currentPublishRequestsInQueue
  local totalRequestCount
  local unauthorizedRequestCount
  local readCount
  local historyReadCount
  local writeCount
  local historyUpdateCount
  local callCount
  local createMonitoredItemsCount
  local modifyMonitoredItemsCount
  local setMonitoringModeCount
  local setTriggeringCount
  local deleteMonitoredItemsCount
  local createSubscriptionCount
  local modifySubscriptionCount
  local setPublishingModeCount
  local publishCount
  local republishCount
  local transferSubscriptionsCount
  local deleteSubscriptionsCount
  local addNodesCount
  local addReferencesCount
  local deleteNodesCount
  local deleteReferencesCount
  local browseCount
  local browseNextCount
  local translateBrowsePathsToNodeIdsCount
  local queryFirstCount
  local queryNextCount
  local registerNodesCount
  local unregisterNodesCount
  sessionId = self:nodeId()
  sessionName = self:string()
  clientDescription = self:applicationDescription()
  serverUri = self:string()
  endpointUrl = self:string()
  noOfLocaleIds = self:int32()
  if noOfLocaleIds ~= -1 then
    localeIds = {}
    for _=1,noOfLocaleIds do
      local tmp
      tmp = self:string()
      tins(localeIds, tmp)
    end
  end
  actualSessionTimeout = self:double()
  maxResponseMessageSize = self:uint32()
  clientConnectionTime = self:dateTime()
  clientLastContactTime = self:dateTime()
  currentSubscriptionsCount = self:uint32()
  currentMonitoredItemsCount = self:uint32()
  currentPublishRequestsInQueue = self:uint32()
  totalRequestCount = self:serviceCounterDataType()
  unauthorizedRequestCount = self:uint32()
  readCount = self:serviceCounterDataType()
  historyReadCount = self:serviceCounterDataType()
  writeCount = self:serviceCounterDataType()
  historyUpdateCount = self:serviceCounterDataType()
  callCount = self:serviceCounterDataType()
  createMonitoredItemsCount = self:serviceCounterDataType()
  modifyMonitoredItemsCount = self:serviceCounterDataType()
  setMonitoringModeCount = self:serviceCounterDataType()
  setTriggeringCount = self:serviceCounterDataType()
  deleteMonitoredItemsCount = self:serviceCounterDataType()
  createSubscriptionCount = self:serviceCounterDataType()
  modifySubscriptionCount = self:serviceCounterDataType()
  setPublishingModeCount = self:serviceCounterDataType()
  publishCount = self:serviceCounterDataType()
  republishCount = self:serviceCounterDataType()
  transferSubscriptionsCount = self:serviceCounterDataType()
  deleteSubscriptionsCount = self:serviceCounterDataType()
  addNodesCount = self:serviceCounterDataType()
  addReferencesCount = self:serviceCounterDataType()
  deleteNodesCount = self:serviceCounterDataType()
  deleteReferencesCount = self:serviceCounterDataType()
  browseCount = self:serviceCounterDataType()
  browseNextCount = self:serviceCounterDataType()
  translateBrowsePathsToNodeIdsCount = self:serviceCounterDataType()
  queryFirstCount = self:serviceCounterDataType()
  queryNextCount = self:serviceCounterDataType()
  registerNodesCount = self:serviceCounterDataType()
  unregisterNodesCount = self:serviceCounterDataType()
  return {
    sessionId = sessionId,
    sessionName = sessionName,
    clientDescription = clientDescription,
    serverUri = serverUri,
    endpointUrl = endpointUrl,
    localeIds = localeIds,
    actualSessionTimeout = actualSessionTimeout,
    maxResponseMessageSize = maxResponseMessageSize,
    clientConnectionTime = clientConnectionTime,
    clientLastContactTime = clientLastContactTime,
    currentSubscriptionsCount = currentSubscriptionsCount,
    currentMonitoredItemsCount = currentMonitoredItemsCount,
    currentPublishRequestsInQueue = currentPublishRequestsInQueue,
    totalRequestCount = totalRequestCount,
    unauthorizedRequestCount = unauthorizedRequestCount,
    readCount = readCount,
    historyReadCount = historyReadCount,
    writeCount = writeCount,
    historyUpdateCount = historyUpdateCount,
    callCount = callCount,
    createMonitoredItemsCount = createMonitoredItemsCount,
    modifyMonitoredItemsCount = modifyMonitoredItemsCount,
    setMonitoringModeCount = setMonitoringModeCount,
    setTriggeringCount = setTriggeringCount,
    deleteMonitoredItemsCount = deleteMonitoredItemsCount,
    createSubscriptionCount = createSubscriptionCount,
    modifySubscriptionCount = modifySubscriptionCount,
    setPublishingModeCount = setPublishingModeCount,
    publishCount = publishCount,
    republishCount = republishCount,
    transferSubscriptionsCount = transferSubscriptionsCount,
    deleteSubscriptionsCount = deleteSubscriptionsCount,
    addNodesCount = addNodesCount,
    addReferencesCount = addReferencesCount,
    deleteNodesCount = deleteNodesCount,
    deleteReferencesCount = deleteReferencesCount,
    browseCount = browseCount,
    browseNextCount = browseNextCount,
    translateBrowsePathsToNodeIdsCount = translateBrowsePathsToNodeIdsCount,
    queryFirstCount = queryFirstCount,
    queryNextCount = queryNextCount,
    registerNodesCount = registerNodesCount,
    unregisterNodesCount = unregisterNodesCount,
  }
end
function enc:sessionSecurityDiagnosticsDataType(v)
  self:nodeId(v.sessionId)
  self:string(v.clientUserIdOfSession)
  self:int32(v.clientUserIdHistory ~= nil and #v.clientUserIdHistory or -1)
  if v.clientUserIdHistory ~= nil then
    for i = 1, #v.clientUserIdHistory do
      self:string(tools.index(v.clientUserIdHistory, i))
    end
  end
  self:string(v.authenticationMechanism)
  self:string(v.encoding)
  self:string(v.transportProtocol)
  self:messageSecurityMode(v.securityMode)
  self:string(v.securityPolicyUri)
  self:byteString(v.clientCertificate)
end
function dec:sessionSecurityDiagnosticsDataType()
  local sessionId
  local clientUserIdOfSession
  local noOfClientUserIdHistory
  local clientUserIdHistory
  local authenticationMechanism
  local encoding
  local transportProtocol
  local securityMode
  local securityPolicyUri
  local clientCertificate
  sessionId = self:nodeId()
  clientUserIdOfSession = self:string()
  noOfClientUserIdHistory = self:int32()
  if noOfClientUserIdHistory ~= -1 then
    clientUserIdHistory = {}
    for _=1,noOfClientUserIdHistory do
      local tmp
      tmp = self:string()
      tins(clientUserIdHistory, tmp)
    end
  end
  authenticationMechanism = self:string()
  encoding = self:string()
  transportProtocol = self:string()
  securityMode = self:messageSecurityMode()
  securityPolicyUri = self:string()
  clientCertificate = self:byteString()
  return {
    sessionId = sessionId,
    clientUserIdOfSession = clientUserIdOfSession,
    clientUserIdHistory = clientUserIdHistory,
    authenticationMechanism = authenticationMechanism,
    encoding = encoding,
    transportProtocol = transportProtocol,
    securityMode = securityMode,
    securityPolicyUri = securityPolicyUri,
    clientCertificate = clientCertificate,
  }
end
function enc:statusResult(v)
  self:statusCode(v.statusCode)
  self:diagnosticInfo(v.diagnosticInfo)
end
function dec:statusResult()
  local statusCode
  local diagnosticInfo
  statusCode = self:statusCode()
  diagnosticInfo = self:diagnosticInfo()
  return {
    statusCode = statusCode,
    diagnosticInfo = diagnosticInfo,
  }
end
function enc:subscriptionDiagnosticsDataType(v)
  self:nodeId(v.sessionId)
  self:uint32(v.subscriptionId)
  self:byte(v.priority)
  self:double(v.publishingInterval)
  self:uint32(v.maxKeepAliveCount)
  self:uint32(v.maxLifetimeCount)
  self:uint32(v.maxNotificationsPerPublish)
  self:boolean(v.publishingEnabled)
  self:uint32(v.modifyCount)
  self:uint32(v.enableCount)
  self:uint32(v.disableCount)
  self:uint32(v.republishRequestCount)
  self:uint32(v.republishMessageRequestCount)
  self:uint32(v.republishMessageCount)
  self:uint32(v.transferRequestCount)
  self:uint32(v.transferredToAltClientCount)
  self:uint32(v.transferredToSameClientCount)
  self:uint32(v.publishRequestCount)
  self:uint32(v.dataChangeNotificationsCount)
  self:uint32(v.eventNotificationsCount)
  self:uint32(v.notificationsCount)
  self:uint32(v.latePublishRequestCount)
  self:uint32(v.currentKeepAliveCount)
  self:uint32(v.currentLifetimeCount)
  self:uint32(v.unacknowledgedMessageCount)
  self:uint32(v.discardedMessageCount)
  self:uint32(v.monitoredItemCount)
  self:uint32(v.disabledMonitoredItemCount)
  self:uint32(v.monitoringQueueOverflowCount)
  self:uint32(v.nextSequenceNumber)
  self:uint32(v.eventQueueOverFlowCount)
end
function dec:subscriptionDiagnosticsDataType()
  local sessionId
  local subscriptionId
  local priority
  local publishingInterval
  local maxKeepAliveCount
  local maxLifetimeCount
  local maxNotificationsPerPublish
  local publishingEnabled
  local modifyCount
  local enableCount
  local disableCount
  local republishRequestCount
  local republishMessageRequestCount
  local republishMessageCount
  local transferRequestCount
  local transferredToAltClientCount
  local transferredToSameClientCount
  local publishRequestCount
  local dataChangeNotificationsCount
  local eventNotificationsCount
  local notificationsCount
  local latePublishRequestCount
  local currentKeepAliveCount
  local currentLifetimeCount
  local unacknowledgedMessageCount
  local discardedMessageCount
  local monitoredItemCount
  local disabledMonitoredItemCount
  local monitoringQueueOverflowCount
  local nextSequenceNumber
  local eventQueueOverFlowCount
  sessionId = self:nodeId()
  subscriptionId = self:uint32()
  priority = self:byte()
  publishingInterval = self:double()
  maxKeepAliveCount = self:uint32()
  maxLifetimeCount = self:uint32()
  maxNotificationsPerPublish = self:uint32()
  publishingEnabled = self:boolean()
  modifyCount = self:uint32()
  enableCount = self:uint32()
  disableCount = self:uint32()
  republishRequestCount = self:uint32()
  republishMessageRequestCount = self:uint32()
  republishMessageCount = self:uint32()
  transferRequestCount = self:uint32()
  transferredToAltClientCount = self:uint32()
  transferredToSameClientCount = self:uint32()
  publishRequestCount = self:uint32()
  dataChangeNotificationsCount = self:uint32()
  eventNotificationsCount = self:uint32()
  notificationsCount = self:uint32()
  latePublishRequestCount = self:uint32()
  currentKeepAliveCount = self:uint32()
  currentLifetimeCount = self:uint32()
  unacknowledgedMessageCount = self:uint32()
  discardedMessageCount = self:uint32()
  monitoredItemCount = self:uint32()
  disabledMonitoredItemCount = self:uint32()
  monitoringQueueOverflowCount = self:uint32()
  nextSequenceNumber = self:uint32()
  eventQueueOverFlowCount = self:uint32()
  return {
    sessionId = sessionId,
    subscriptionId = subscriptionId,
    priority = priority,
    publishingInterval = publishingInterval,
    maxKeepAliveCount = maxKeepAliveCount,
    maxLifetimeCount = maxLifetimeCount,
    maxNotificationsPerPublish = maxNotificationsPerPublish,
    publishingEnabled = publishingEnabled,
    modifyCount = modifyCount,
    enableCount = enableCount,
    disableCount = disableCount,
    republishRequestCount = republishRequestCount,
    republishMessageRequestCount = republishMessageRequestCount,
    republishMessageCount = republishMessageCount,
    transferRequestCount = transferRequestCount,
    transferredToAltClientCount = transferredToAltClientCount,
    transferredToSameClientCount = transferredToSameClientCount,
    publishRequestCount = publishRequestCount,
    dataChangeNotificationsCount = dataChangeNotificationsCount,
    eventNotificationsCount = eventNotificationsCount,
    notificationsCount = notificationsCount,
    latePublishRequestCount = latePublishRequestCount,
    currentKeepAliveCount = currentKeepAliveCount,
    currentLifetimeCount = currentLifetimeCount,
    unacknowledgedMessageCount = unacknowledgedMessageCount,
    discardedMessageCount = discardedMessageCount,
    monitoredItemCount = monitoredItemCount,
    disabledMonitoredItemCount = disabledMonitoredItemCount,
    monitoringQueueOverflowCount = monitoringQueueOverflowCount,
    nextSequenceNumber = nextSequenceNumber,
    eventQueueOverFlowCount = eventQueueOverFlowCount,
  }
end
function enc:modelChangeStructureDataType(v)
  self:nodeId(v.affected)
  self:nodeId(v.affectedType)
  self:byte(v.verb)
end
function dec:modelChangeStructureDataType()
  local affected
  local affectedType
  local verb
  affected = self:nodeId()
  affectedType = self:nodeId()
  verb = self:byte()
  return {
    affected = affected,
    affectedType = affectedType,
    verb = verb,
  }
end
function enc:semanticChangeStructureDataType(v)
  self:nodeId(v.affected)
  self:nodeId(v.affectedType)
end
function dec:semanticChangeStructureDataType()
  local affected
  local affectedType
  affected = self:nodeId()
  affectedType = self:nodeId()
  return {
    affected = affected,
    affectedType = affectedType,
  }
end
function enc:range(v)
  self:double(v.low)
  self:double(v.high)
end
function dec:range()
  local low
  local high
  low = self:double()
  high = self:double()
  return {
    low = low,
    high = high,
  }
end
function enc:euinformation(v)
  self:string(v.namespaceUri)
  self:int32(v.unitId)
  self:localizedText(v.displayName)
  self:localizedText(v.description)
end
function dec:euinformation()
  local namespaceUri
  local unitId
  local displayName
  local description
  namespaceUri = self:string()
  unitId = self:int32()
  displayName = self:localizedText()
  description = self:localizedText()
  return {
    namespaceUri = namespaceUri,
    unitId = unitId,
    displayName = displayName,
    description = description,
  }
end
function enc:complexNumberType(v)
  self:float(v.real)
  self:float(v.imaginary)
end
function dec:complexNumberType()
  local real
  local imaginary
  real = self:float()
  imaginary = self:float()
  return {
    real = real,
    imaginary = imaginary,
  }
end
function enc:doubleComplexNumberType(v)
  self:double(v.real)
  self:double(v.imaginary)
end
function dec:doubleComplexNumberType()
  local real
  local imaginary
  real = self:double()
  imaginary = self:double()
  return {
    real = real,
    imaginary = imaginary,
  }
end
function enc:axisInformation(v)
  self:euinformation(v.engineeringUnits)
  self:range(v.eurange)
  self:localizedText(v.title)
  self:axisScaleEnumeration(v.axisScaleType)
  self:int32(v.axisSteps ~= nil and #v.axisSteps or -1)
  if v.axisSteps ~= nil then
    for i = 1, #v.axisSteps do
      self:double(tools.index(v.axisSteps, i))
    end
  end
end
function dec:axisInformation()
  local engineeringUnits
  local eurange
  local title
  local axisScaleType
  local noOfAxisSteps
  local axisSteps
  engineeringUnits = self:euinformation()
  eurange = self:range()
  title = self:localizedText()
  axisScaleType = self:axisScaleEnumeration()
  noOfAxisSteps = self:int32()
  if noOfAxisSteps ~= -1 then
    axisSteps = {}
    for _=1,noOfAxisSteps do
      local tmp
      tmp = self:double()
      tins(axisSteps, tmp)
    end
  end
  return {
    engineeringUnits = engineeringUnits,
    eurange = eurange,
    title = title,
    axisScaleType = axisScaleType,
    axisSteps = axisSteps,
  }
end
function enc:xvtype(v)
  self:double(v.x)
  self:float(v.value)
end
function dec:xvtype()
  local x
  local value
  x = self:double()
  value = self:float()
  return {
    x = x,
    value = value,
  }
end
function enc:programDiagnosticDataType(v)
  self:nodeId(v.createSessionId)
  self:string(v.createClientName)
  self:dateTime(v.invocationCreationTime)
  self:dateTime(v.lastTransitionTime)
  self:string(v.lastMethodCall)
  self:nodeId(v.lastMethodSessionId)
  self:int32(v.lastMethodInputArguments ~= nil and #v.lastMethodInputArguments or -1)
  if v.lastMethodInputArguments ~= nil then
    for i = 1, #v.lastMethodInputArguments do
      self:argument(tools.index(v.lastMethodInputArguments, i))
    end
  end
  self:int32(v.lastMethodOutputArguments ~= nil and #v.lastMethodOutputArguments or -1)
  if v.lastMethodOutputArguments ~= nil then
    for i = 1, #v.lastMethodOutputArguments do
      self:argument(tools.index(v.lastMethodOutputArguments, i))
    end
  end
  self:dateTime(v.lastMethodCallTime)
  self:statusResult(v.lastMethodReturnStatus)
end
function dec:programDiagnosticDataType()
  local createSessionId
  local createClientName
  local invocationCreationTime
  local lastTransitionTime
  local lastMethodCall
  local lastMethodSessionId
  local noOfLastMethodInputArguments
  local lastMethodInputArguments
  local noOfLastMethodOutputArguments
  local lastMethodOutputArguments
  local lastMethodCallTime
  local lastMethodReturnStatus
  createSessionId = self:nodeId()
  createClientName = self:string()
  invocationCreationTime = self:dateTime()
  lastTransitionTime = self:dateTime()
  lastMethodCall = self:string()
  lastMethodSessionId = self:nodeId()
  noOfLastMethodInputArguments = self:int32()
  if noOfLastMethodInputArguments ~= -1 then
    lastMethodInputArguments = {}
    for _=1,noOfLastMethodInputArguments do
      local tmp
      tmp = self:argument()
      tins(lastMethodInputArguments, tmp)
    end
  end
  noOfLastMethodOutputArguments = self:int32()
  if noOfLastMethodOutputArguments ~= -1 then
    lastMethodOutputArguments = {}
    for _=1,noOfLastMethodOutputArguments do
      local tmp
      tmp = self:argument()
      tins(lastMethodOutputArguments, tmp)
    end
  end
  lastMethodCallTime = self:dateTime()
  lastMethodReturnStatus = self:statusResult()
  return {
    createSessionId = createSessionId,
    createClientName = createClientName,
    invocationCreationTime = invocationCreationTime,
    lastTransitionTime = lastTransitionTime,
    lastMethodCall = lastMethodCall,
    lastMethodSessionId = lastMethodSessionId,
    lastMethodInputArguments = lastMethodInputArguments,
    lastMethodOutputArguments = lastMethodOutputArguments,
    lastMethodCallTime = lastMethodCallTime,
    lastMethodReturnStatus = lastMethodReturnStatus,
  }
end
function enc:annotation(v)
  self:string(v.message)
  self:string(v.userName)
  self:dateTime(v.annotationTime)
end
function dec:annotation()
  local message
  local userName
  local annotationTime
  message = self:string()
  userName = self:string()
  annotationTime = self:dateTime()
  return {
    message = message,
    userName = userName,
    annotationTime = annotationTime,
  }
end
return {
  Encoder = enc,
  Decoder = dec
}
