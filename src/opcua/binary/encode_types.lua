local s = require("opcua.status_codes")
local n = require("opcua.node_id")
local tools = require("opcua.binary.tools")
local t = require("opcua.types")

local BinTypes = require "opcua.binary.encode_extobj_gen"
local tenc = BinTypes.Encoder
local tdec = BinTypes.Decoder

local tins = table.insert

function tenc:string(v)
  self:int32(v ~= nil and #v or -1)
  if v ~= nil then
    for i = 1, #v do
      self:char(tools.index(v, i))
    end
  end
end
function tdec:string()
  local length = self:int32()
  if length == -1 then return end
  return self:str(length)
end

tenc.charArray = tenc.string
tdec.charArray = tdec.string
tenc.byteString = tenc.string

function tdec:byteString()
  return self:string(true) -- will return table instead string
end

function tenc:nodeId(v)
  local id -- id value
  local ns = 0  -- namespace index
  local nsUri
  local si -- server index

  local idType -- mask of NodeId Type with NodeIdType | HasServiceIndex | HasNamespaceUri
  local idEnc  -- encoding function of Id
  local nsiEnc = self.uint16 -- namespace Index endcoding func

  if type(v) == 'string' then
    v = n.fromString(v)
  end

  if type(v) == 'table' and v.id ~= nil then
    id = v.id
    if v.ns ~= nil then
      if type(v.ns) == 'number' then
        ns = v.ns
      elseif type(v.ns) == 'string' then
        nsUri = v.ns
      end
    end
    if v.srv ~= nil then
      si = v.srv
    end
  else
    id = v
  end

  if ns < 0 or ns > 0xFF then
    error(s.BadEncodingError)
  end

  if type(id) == 'number' then
    if id < 0 then
      error(s.BadEncodingError)
    end
    if id <= 0xFF and ns == 0 and nsUri == nil then
      idType = n.TwoByte
      idEnc = self.uint8
      nsiEnc = nil
    else
      if id <= 0xFFFF then
        idType = n.FourByte
        idEnc = self.uint16
        nsiEnc = self.uint8
      elseif id <= 0xFFFFFFFF then
        idType = n.Numeric
        idEnc = self.uint32
      else
        error(s.BadEncodingError)
      end
    end
  elseif type(id) == 'string' then
    idType = n.String
    idEnc = self.string
  elseif type(id) == 'table' and id.data1 ~= nil then
    idType = n.Guid
    idEnc = self.guid
  elseif type(id) == 'table' then
    idType = n.ByteString
    idEnc = self.byteString
  else
    error(s.BadEncodingError)
  end

  if si ~= nil then
    if type(si) ~= 'number' or si < 0 then
      error(s.BadEncodingError)
    end
    idType = idType | n.ServerIndexFlag
  end

  if nsUri ~= nil then
    idType = idType | n.NamespaceUriFlag
  end

  -- Node ID fields mask
  self:uint8(idType)

  -- namespace index
  if nsiEnc ~= nil then
    nsiEnc(self, ns)
  end

  -- Node ID value
  idEnc(self, id)

  -- namespace Uri
  if nsUri ~= nil then
    self:string(nsUri)
  end

  -- Server Index
  if si ~= nil then
    self:uint32(si)
  end
end

function tdec:nodeId()
  local nodeIdType = self:bit(6)
  if nodeIdType > 5 or nodeIdType < 0  then
    return error(s.BadDecodingError)
  end

  local ns
  local id
  local srv

  local hasSi = self:bit(1)
  local hasNs = self:bit(1)

  if nodeIdType == n.TwoByte then
    if hasNs == 1 then return error(s.BadDecodingError) end
    id = self:uint8()
  elseif nodeIdType == n.FourByte then
    ns = self:uint8()
    id = self:uint16()
  elseif nodeIdType == n.Numeric then
    ns = self:uint16()
    id = self:uint32()
  elseif nodeIdType == n.String then
    ns = self:uint16()
    id = self:string()
  elseif nodeIdType == n.Guid then
    ns = self:uint16()
    id = self:guid()
  elseif nodeIdType == n.ByteString then
    ns = self:uint16()
    id = self:byteString()
  end

  if hasNs == 1 then
    ns = self:string()
  end

  if hasSi == 1 then
    srv = self:uint32()
    if srv == 0 then
      srv = nil
    end
  end

  return n.toString(id,ns,srv, nodeIdType)
end

tdec.expandedNodeId = tdec.nodeId
tenc.expandedNodeId = tenc.nodeId

function tenc:variant(v)
  local data
  local encFunc
  local vt

  if v.boolean ~= nil then
    vt = 1
    data = v.boolean
    encFunc = self.boolean
  elseif v.sbyte ~= nil then
    vt = 2
    data = v.sbyte
    encFunc = self.sbyte
  elseif v.byte ~= nil then
    vt = 3
    data = v.byte
    encFunc = self.byte
  elseif v.int16 ~= nil then
    vt = 4
    data = v.int16
    encFunc = self.int16
  elseif v.uint16 ~= nil then
    vt = 5
    data = v.uint16
    encFunc = self.uint16
  elseif v.int32 ~= nil then
    vt = 6
    data = v.int32
    encFunc = self.int32
  elseif v.uint32 ~= nil then
    vt = 7
    data = v.uint32
    encFunc = self.uint32
  elseif v.int64 ~= nil then
    vt = 8
    data = v.int64
    encFunc = self.int64
  elseif v.uint64 ~= nil then
    vt = 9
    data = v.uint64
    encFunc = self.uint64
  elseif v.float ~= nil then
    vt = 10
    data = v.float
    encFunc = self.float
  elseif v.double ~= nil then
    vt = 11
    data = v.double
    encFunc = self.double
  elseif v.string ~= nil then
    vt = 12
    data = v.string
    encFunc = self.string
  elseif v.dateTime ~= nil then
    vt = 13
    data = v.dateTime
    encFunc = self.dateTime
  elseif v.guid ~= nil then
    vt = 14
    data = v.guid
    encFunc = self.guid
  elseif v.byteString ~= nil then
    vt = 15
    data = v.byteString
    encFunc = self.byteString
  elseif v.xmlElement ~= nil then
    vt = 16
    data = v.xmlElement
    encFunc = self.xmlElement
  elseif v.nodeId ~= nil then
    vt = 17
    data = v.nodeId
    encFunc = self.nodeId
  elseif v.expandedNodeId ~= nil then
    vt = 18
    data = v.expandedNodeId
    encFunc = self.expandedNodeId
  elseif v.statusCode ~= nil then
    vt = 19
    data = v.statusCode
    encFunc = self.statusCode
  elseif v.qualifiedName ~= nil then
    vt = 20
    data = v.qualifiedName
    encFunc = self.qualifiedName
  elseif v.localizedText ~= nil then
    vt = 21
    data = v.localizedText
    encFunc = self.localizedText
  elseif v.extensionObject ~= nil then
    vt = 22
    data = v.extensionObject
    encFunc = self.extensionObject
  elseif v.dataValue ~= nil then
    vt = 23
    data = v.dataValue
    encFunc = self.dataValue
  elseif v.variant ~= nil then
    vt = 24
    data = v.variant
    encFunc = self.variant
  elseif v.diagnosticInfo ~= nil then
    vt = 25
    data = v.diagnosticInfo
    encFunc = self.diagnosticInfo
  else
    for _,_ in pairs(v) do
      error(s.BadEncodingError)
    end
    self:byte(0)
    return
  end

  assert(data ~= nil)
  assert(vt ~= nil)
  assert(encFunc ~= nil)

  self:bit(vt, 7)
  local isArray = type(data) == 'table' and data[1] ~= nil
  if isArray then
    self:bit(1, 1) -- ArrayLengthSpecified = 1
    self:int32(#data)
    for _,val in ipairs(data) do
      encFunc(self, val)
    end
  else
    self:bit(0, 1) -- ArrayLengthSpecified = 0
    encFunc(self, data)
  end
end

function tdec:variant()
  local v = {}
  local arrLen = 0
  local decFunc
  local vt = self:bit(7)

  local isArray = self:bit(1)
  if isArray ~= 0 then
    arrLen = self:int32()
  end

  if vt == 0 then
    vt = 'null'
  elseif vt == 1 then
    decFunc = self.boolean
    vt = "boolean"
  elseif vt == 2 then
    decFunc = self.sbyte
    vt = "sbyte"
  elseif vt == 3 then
    decFunc = self.byte
    vt = "byte"
  elseif vt == 4 then
    decFunc = self.int16
    vt = "int16"
  elseif vt == 5 then
    decFunc = self.uint16
    vt = "uint16"
  elseif vt == 6 then
    decFunc = self.int32
    vt = "int32"
  elseif vt == 7 then
    decFunc = self.uint32
    vt = "uint32"
  elseif vt == 8 then
    decFunc = self.int64
    vt = "int64"
  elseif vt == 9 then
    decFunc = self.uint64
    vt = "uint64"
  elseif vt == 10 then
    decFunc = self.float
    vt = "float"
  elseif vt == 11 then
    decFunc = self.double
    vt = "double"
  elseif vt == 12 then
    decFunc = self.string
    vt = "string"
  elseif vt == 13 then
    decFunc = self.dateTime
    vt = "dateTime"
  elseif vt == 14 then
    decFunc = self.guid
    vt = "guid"
  elseif vt == 15 then
    decFunc = self.byteString
    vt = "byteString"
  elseif vt == 16 then
    decFunc = self.xmlElement
    vt = "xmlElement"
  elseif vt == 17 then
    decFunc = self.nodeId
    vt = "nodeId"
  elseif vt == 18 then
    decFunc = self.expandedNodeId
    vt = "expandedNodeId"
  elseif vt == 19 then
    decFunc = self.statusCode
    vt = "statusCode"
  elseif vt == 20 then
    decFunc = self.qualifiedName
    vt = "qualifiedName"
  elseif vt == 21 then
    decFunc = self.localizedText
    vt = "localizedText"
  elseif vt == 22 then
    decFunc = self.extensionObject
    vt = "extensionObject"
  elseif vt == 23 then
    decFunc = self.dataValue
    vt = "dataValue"
  elseif vt == 24 then
    decFunc = self.variant
    vt = "variant"
  elseif vt == 25 then
    decFunc = self.diagnosticInfo
    vt = "diagnosticInfo"
  else
    error(s.BadDecodingError)
  end

  local val
  if decFunc then
    if isArray == 0 then
      val = decFunc(self)
    else
      val = {}
      for _=1,arrLen do
        local curVal = decFunc(self)
        tins(val, curVal)
      end
    end
  end

  v[vt] = val

  return v
end

-------------------------------------
----- ExtensionObject ---------------
-------------------------------------

-- Small helper class that calculates size of serialized data.
local function newSizeQ()
  local sizeQ = {
    pushBack = function(self, data)
      local size = type(data) == "number" and 1 or #data
      self.size = self.size + size
    end,

    clear=function(self)
      self.size = 0
    end,
  }

  return sizeQ
end


function tenc:extensionObject(v)
  local typeId = v.typeId
  local body = v.body

  self:expandedNodeId(typeId)
  self:bit(body ~= nil and 1 or 0, 1)
  self:bit(0, 7)
  if body ~= nil then
    local f = self[typeId]
    -- Extension object body is encoded as bytestring.
    -- To encode extension object as byte string we should know its size
    -- To calculate size we use a helper class instead buffer.
    -- After calculating size we encode extension object.
    if f then
      local extBuf = self.extBuf
      local extEnc = self.extEnc
      if extEnc == nil then
        extBuf = newSizeQ()
        extEnc = tenc.new(extBuf)
        self.extEnc = extEnc
        self.extBuf = extBuf
      end
      extBuf:clear()
      f(extEnc, body)

      self:uint32(extBuf.size)
      f(self, body)
    else
      self:byteString(body)
    end
  end
end
function tdec:extensionObject()
  local typeId
  local binaryBody
  local body
  typeId = self:expandedNodeId()
  binaryBody = self:bit()
  self:bit(7)
  if binaryBody ~= 0 then
    local f = self[typeId]
    if f then
      self:uint32()
      body = f(self)
    else
      body = self:byteString()
    end
  end
  return {
    typeId = typeId,
    body = body,
  }
end

--------------------------------------
--- MessageHeader
--------------------------------------
-- headerType - values from HeaderType
-- chunkType - values from ChunkType
-- chunkSize of message chunk
function tenc:messageHeader(headerType, chunkType, chunkSize)
  self:str(headerType)
  self:str(chunkType)
  self:uint32(chunkSize)
end

function tdec:messageHeader()
  return {
    type = self:str(3),
    chunk = self:str(1),
    messageSize = self:uint32()
  }
end

--------------------------------------
--- secureMessageHeader
--------------------------------------
-- headerType - values from HeaderType
-- chunkType - values from ChunkType
-- chunkSize of message chunk
-- channelId of message chunk

function tenc:secureMessageHeader(headerType, chunkType, chunkSize, channelId)
  self:str(headerType)
  self:str(chunkType)
  self:uint32(chunkSize)
  self:uint32(channelId)
end

function tdec:secureMessageHeader()
  return {
    type = self:str(3),
    chunk = self:str(1),
    messageSize = self:uint32(),
    channelId = self:uint32()
  }
end


--------------------------------------
--- AsymmetricSecurityHeader
--------------------------------------

function tenc:asymmetricSecurityHeader(securityPolicyUri, senderCertificate, receiverCertificateThumbprint)
  self:charArray(securityPolicyUri)
  self:charArray(senderCertificate)
  self:charArray(receiverCertificateThumbprint)
end

function tdec:asymmetricSecurityHeader()
  return {
    securityPolicyUri = self:charArray(),
    senderCertificate = self:charArray(),
    receiverCertificateThumbprint = self:charArray()
  }
end

--------------------------------------
--- SymmetricSecurityHeader
--------------------------------------

function tenc:symmetricSecurityHeader(val)
  self:uint32(val.tokenId)
end

function tdec:symmetricSecurityHeader()
  return {
    tokenId = self:uint32()
  }
end

--------------------------------------
--- SequenceHeader
--------------------------------------

function tenc:sequenceHeader(val)
  self:uint32(val.sequenceNumber)
  self:uint32(val.requestId)
end

function tdec:sequenceHeader()
  return {
    sequenceNumber = self:uint32(),
    requestId = self:uint32()
  }
end

--------------------------------------
--- MessageFooter
--------------------------------------

function tenc:messageFooter(val)
  self:uint8(val.paddingSize)
  self:str(val.padding)
  self:uint8(val.extraPaddingSize)
  self:str(val.signature)
end

--------------------------------------
--- Hello message content
--------------------------------------

function tenc:hello(val)
  self:uint32(val.protocolVersion)
  self:uint32(val.receiveBufferSize)
  self:uint32(val.sendBufferSize)
  self:uint32(val.maxMessageSize)
  self:uint32(val.maxChunkCount)
  self:charArray(val.endpointUrl)
end


function tdec:hello()
  return {
    protocolVersion = self:uint32(),
    receiveBufferSize = self:uint32(),
    sendBufferSize = self:uint32(),
    maxMessageSize = self:uint32(),
    maxChunkCount = self:uint32(),
    endpointUrl = self:charArray()
  }
end

--------------------------------------
--- Acknowledge message content
--------------------------------------

function tenc:acknowledge(val)
  self:uint32(val.protocolVersion)
  self:uint32(val.receiveBufferSize)
  self:uint32(val.sendBufferSize)
  self:uint32(val.maxMessageSize)
  self:uint32(val.maxChunkCount)
end

function tdec:acknowledge()
  return {
    protocolVersion = self:uint32(),
    receiveBufferSize = self:uint32(),
    sendBufferSize = self:uint32(),
    maxMessageSize = self:uint32(),
    maxChunkCount = self:uint32()
  }
end

--------------------------------------
--- Error content
--------------------------------------

function tenc:error(val)
  self:uint32(val.error)
  self:charArray(val.reason)
end

function tdec:error()
  return {
    error = self:uint32(),
    reason = self:charArray()
  }
end

--------------------------------------
--- AddNodesItem
--------------------------------------

function tenc:addNodesItem(v)
  self:expandedNodeId(v.parentNodeId)
  self:nodeId(v.referenceTypeId)
  self:expandedNodeId(v.requestedNewNodeId)
  self:qualifiedName(v.browseName)
  self:nodeClass(v.nodeClass)
  local nodeAttributes = v.nodeAttributes

  if nodeAttributes == nil then
    if v.nodeClass == 1 then
      -- Object
      nodeAttributes = {
        typeId = "i=354",
        body = {
          specifiedAttributes = t.ObjectAttributesMask,
          displayName = v.displayName,
          description = v.description,
          writeMask = v.writeMask,
          userWriteMask = v.userWriteMask,
          eventNotifier = v.eventNotifier
        }
      }
    elseif v.nodeClass == 2 then
      -- Variable
      nodeAttributes = {
        typeId = "i=357",
        body = {
          specifiedAttributes = t.VariableAttributesMask,
          displayName = v.displayName,
          description = v.description,
          writeMask = v.writeMask,
          userWriteMask = v.userWriteMask,
          value = v.value,
          dataType= v.dataType,
          valueRank = v.valueRank,
          arrayDimensions = v.arrayDimensions,
          accessLevel = v.accessLevel,
          userAccessLevel = v.userAccessLevel,
          minimumSamplingInterval = v.minimumSamplingInterval,
          historizing = v.historizing
        }
      }
    end
  end

  self:extensionObject(nodeAttributes)
  self:expandedNodeId(v.typeDefinition)
end

function tdec:addNodesItem()
  local result = {}
  result["parentNodeId"] = self:expandedNodeId()
  result["referenceTypeId"] = self:nodeId()
  result["requestedNewNodeId"] = self:expandedNodeId()
  result["browseName"] = self:qualifiedName()
  result["nodeClass"] = self:nodeClass()
  local nodeAttributes = self:extensionObject()
  result["typeDefinition"]= self:expandedNodeId()

  if result.nodeClass == 1 then
    -- Object
    result["displayName"] = nodeAttributes.body.displayName
    result["description"] = nodeAttributes.body.description
    result["writeMask"] = nodeAttributes.body.writeMask
    result["userWriteMask"] = nodeAttributes.body.userWriteMask
    result["eventNotifier"] = nodeAttributes.body.eventNotifier
  elseif result.nodeClass == 2 then
    result["displayName"] = nodeAttributes.body.displayName
    result["description"] = nodeAttributes.body.description
    result["writeMask"] = nodeAttributes.body.writeMask
    result["userWriteMask"] = nodeAttributes.body.userWriteMask
    result["value"] = nodeAttributes.body.value
    result["dataType"] = nodeAttributes.body.dataType
    result["valueRank"] = nodeAttributes.body.valueRank
    result["arrayDimensions"] = nodeAttributes.body.arrayDimensions
    result["accessLevel"] = nodeAttributes.body.accessLevel
    result["userAccessLevel"] = nodeAttributes.body.userAccessLevel
    result["minimumSamplingInterval"] = nodeAttributes.body.minimumSamplingInterval
    result["historizing"] = nodeAttributes.body.historizing
  end

  return result
end


return {
  Encoder = tenc,
  Decoder = tdec,

  HeaderType = {
    Message = "MSG",
    Open = "OPN",
    Close = "CLO",
    Hello = "HEL",
    ReverseHello = "RHE",
    Acknowledge = "ACK",
    Error = "ERR"
  },


  ChunkType = {
    Final = "F", -- final message chunk
    Intermediate = "C", -- intermediate message chunk
    Abort = "A" -- abort multichunk message
  }

}
