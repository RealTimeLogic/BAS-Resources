local ua = require("opcua.api")
local Q = require("opcua.binary.queue")
local BinaryEncoder = require("opcua.binary.encoder")

local s = require("opcua.status_codes")
local MessageId = require("opcua.binary.message_id")

local tools = ua.Tools
local fmt = string.format
local traceD = ua.trace.dbg
local traceI = ua.trace.inf
local traceE = ua.trace.err

local ch ={}
ch.__index = ch

local HeaderSize = 8
local SecureHeaderSize = 12

local BadInternalError = s.BadInternalError
local BadSecureChannelIdInvalid = s.BadSecureChannelIdInvalid
local BadTcpMessageTypeInvalid = 0x807E0000

local function makeEmptyAdditionalHeader()
  return {TypeId = "i=0"}
end


function ch:hello(hello)
  local infOn = self.logging.infOn

  if infOn then traceI(fmt("binary | sending hello")) end

  self:beginMessage("HEL")
  self.Encoder:hello(hello)
  self:finishMessage()
  self:send()

  if infOn then traceI(fmt("binary | hello sent")) end
end

function ch:acknowledge(ack)
  local infOn = self.logging.infOn
  if infOn then traceI(fmt("binary | sending acknowledge")) end

  self:beginMessage("ACK")
  self.Encoder:acknowledge(ack)
  self:finishMessage("F")
  self:send()

  if infOn then traceI(fmt("binary | acknowledge sent")) end
end

function ch.createRequest(_,type, requestParams, request)
  if not request then
    request = {}
  end

  request.TypeId = type
  request.RequestId = requestParams.RequestId
  request.RequestHeader = {
      AuthenticationToken = requestParams.SessionAuthToken,
      Timestamp = requestParams.RequestCreatedAt,
      RequestHandle = requestParams.RequestHandle,
      ReturnDiagnostics = 0,
      AuditEntryId = nil,
      TimeoutHint = requestParams.RequestTimeout,
      AdditionalHeader = makeEmptyAdditionalHeader()
    }
  return request
end

function ch.createResponse(_, type, responseParams, response)
  if not response then
    response = {}
  end

  response.TypeId = type
  response.RequestId = responseParams.RequestId
  response.ResponseHeader = {
    Timestamp = responseParams.RequestCreatedAt,
    RequestHandle = responseParams.RequestHandle,
    ServiceResult = responseParams.ServiceResult,
    ServiceDiagnostics = {},
    StringTable = {},
    AdditionalHeader = makeEmptyAdditionalHeader()
  }

  return response
end

function ch:message(body)
  local dbgOn = self.logging.dbgOn
  local infOn = self.logging.infOn
  local errOn = self.logging.errOn
  local type = body.TypeId
  if infOn then traceI(fmt("binary | sending message '%s'", type)) end

  if self.channelId == nil then
    if errOn then traceE(fmt("binary | channel Id for message not set", type)) end
    error(BadTcpMessageTypeInvalid)
  end

  local msgType
  if  type == MessageId.OPEN_SECURE_CHANNEL_REQUEST or type == MessageId.OPEN_SECURE_CHANNEL_RESPONSE then
    msgType = "OPN"
  elseif type == MessageId.CLOSE_SECURE_CHANNEL_REQUEST then
    msgType = "CLO"
  else
    msgType = "MSG"
  end
  self:beginMessage(msgType, body.RequestId)

  if dbgOn then traceD(fmt("binary | encoding message")) end
  local extObject = self.Encoder:getExtObject(type)
  self.Encoder:nodeId(extObject.binaryId)
  self.Encoder:Encode(type, body)

  self:finishMessage()
  self:send()

  if infOn then traceI(fmt("binary | message '%s' sent", type)) end
end

function ch:beginMessage(messageType, requestId)
  assert(requestId == nil or type(requestId) == 'number')
  assert(type(messageType) == 'string')
  if not self.hasChunks then
    self.headerSize = 0
  else
    if messageType == "MSG" or messageType == "CLO" then
      self.headerSize = SecureHeaderSize + 4 + 8 -- symmetricHeader + sequenceHeader
    elseif messageType == "OPN" then
      local sz = SecureHeaderSize + 4 + #self.policy.uri
      sz = sz + 4 -- certificateLen
      sz = sz + 4 -- remoteThumbprintLen

      sz = sz + self.policy:geLocalCertLen()
      sz = sz + self.policy:getRemoteThumbLen()
      self.headerSize = sz + 8 -- sequenceHeader
    else
      self.headerSize = HeaderSize
    end
  end

  self.messageType = messageType
  self.requestId = requestId
  self.data:clear(self.headerSize + 1)
end

-- Queue interface through which fills up message body
function ch:pushBack(data)
  local tailSize = self.policy and self.policy:tailSize() or 0
  local tailCap = self.data:tailCapacity() - tailSize

  if tailCap <= 0 then
    self:finishChunk("C")
    self:send()
  end

  if type(data) == 'number' then
    self.data:pushBack(data)
    return
  end

  local dsize <const> = #data
  if type(data) == 'string' and tailCap > dsize then
    self.data:pushBack(data)
  else
    local pos = 1
    while pos <= dsize do
      if pos ~= 1 then
        self:finishChunk("C")
        self:send()
      end

      tailCap = self.data:tailCapacity() - tailSize
      local leftSize = dsize - (pos - 1)
      if leftSize > tailCap then
        leftSize = tailCap
      end

      if type(data) == 'string' then
        for i = 0,(leftSize-1) do
          self.data:pushBack(data:byte(pos+i))
        end
      else
        for i = 0,(leftSize-1) do
          self.data:pushBack(data[pos+i])
        end
      end

      pos = pos + leftSize
    end
  end
end

-- function ch:abort()
--   self.data:clear()
--   self:finishChunk("A")
--   self.send()
-- end
function ch:finishMessage()
  self:finishChunk("F")
end

function ch:finishChunk(chunkType)
  local errOn = self.logging.errOn

  if chunkType == "C" and self.messageType ~= "MSG" then
    if errOn then traceE(fmt("binary | %s Internal error: Message type '%s' can't be chunked.",self.channelId, self.messageType)) end
    self.data:clear()
    error(BadInternalError)
  end

  local policy = self.policy
  local pos = 0

  if self.hasChunks then
    local headerQ = Q.new(self.headerSize) -- +sequenceHeader
    local header = BinaryEncoder.new(headerQ)
    if self.hasChunks and self.messageType == "MSG" or self.messageType == "CLO" then
      if self.channelId == nil then error(BadSecureChannelIdInvalid) end
      if self.secureHeader == nil then error(BadSecureChannelIdInvalid) end
      assert(self.requestId ~= 0 and self.requestId ~= nil)
      header:symmetricSecurityHeader(self.secureHeader)
      self:sequenceHeader(header)
      self.data:pushFront(headerQ.Buf)
    elseif self.messageType == "OPN" then
      assert(self.requestId ~= 0 and self.requestId ~= nil)
      assert(policy)
      if policy.uri ~= ua.SecurityPolicy.None then
        header:asymmetricSecurityHeader(policy.uri, policy:getLocalCert(), policy:getRemoteThumbprint())
      else
        header:asymmetricSecurityHeader(policy.uri)
      end
      self:sequenceHeader(header)
      self.data:pushFront(headerQ.Buf)
    end
    headerQ:clear()

    if self.messageType == "MSG" or self.messageType == "OPN" or self.messageType == "CLO" then
      local msgSize
      if self.messageType == "OPN" then
        msgSize = policy:aMessageSize(SecureHeaderSize + #self.data, self.headerSize - 8)
      else
        msgSize = policy:sMessageSize(SecureHeaderSize + #self.data, self.headerSize - 8)
      end
      header:secureMessageHeader(self.messageType, chunkType, msgSize, self.channelId)
    else
      header:messageHeader(self.messageType, chunkType, HeaderSize + #self.data)
    end

    self.data:pushFront(headerQ.Buf)
    pos = self.headerSize - 8
  end

  if self.messageType == "OPN" then
    policy:asymmetricEncrypt(self.data.Buf, pos)
  elseif self.messageType == "MSG" or self.messageType == "CLO" then
    policy:symmetricEncrypt(self.data.Buf, pos)
  end
end

function ch:send()
  local dbgOn = self.logging.dbgOn
  local errOn = self.logging.errOn
  if dbgOn then traceD(fmt("binary | sending message")) end
  if #self.data == 0 then
    if errOn then traceE("binary | Internal error: No data to send") end
    error(BadInternalError)
  end

  if self.logging.dbgOn  then
    traceD(fmt("binary | ------------ SENDING MESSAGE DATA %d BYTES ----------------", #self.data.Buf))
    tools.hexPrint(self.data.Buf, function(msg) traceD("binary | "..msg) end)
    traceD("binary | ---------------------------------------------------------")
  end

  self.sock:send(self.data.Buf)
  self.data:clear(self.headerSize + 1) -- prepare for next chunk
  if dbgOn then traceD(fmt("binary | Message sent sucessfully")) end
end

function ch:sequenceHeader(en)
  self.sequenceNumber = self.sequenceNumber + 1
  local sequenceHeader = {
    SequenceNumber = self.sequenceNumber,
    RequestId = self.requestId
  }
  en:sequenceHeader(sequenceHeader)
end

function ch:setBufferSize(size)
  local infOn = self.logging.infOn
  if infOn then traceI(fmt("binary | New buffer size '%d'",size)) end
  self.data = Q.new(size)
  self.Encoder = self.Model:createBinaryEncoder(self)
end

function ch:setChannelId(channelId)
  assert(channelId ==nil or type(channelId) == 'number')
  local infOn = self.logging.infOn
  if infOn then traceI(fmt("binary | New channelId '%s'", channelId)) end
  self.channelId = channelId
end

function ch:setTokenId(tokenId)
  assert(tokenId == nil or type(tokenId) == 'number')
  local infOn = self.logging.infOn
  if infOn then traceI(fmt("binary | New token '%s'", tokenId)) end
  self.secureHeader = {TokenId = tokenId}
end

function ch:setupPolicy(uri, remoteCert)
  local policy = self.security(uri)
  policy:setRemoteCertificate(remoteCert)
  self.policy = policy
end

function ch:setNonces(localNonce, remoteNonce)
  self.policy:setNonces(localNonce, remoteNonce)
end

function ch:setSecureMode(secureMode)
  self.policy:setSecureMode(secureMode)
end

local function new(config, security, sock, hasChunks, model)
  assert(config ~= nil, "no config")
  assert(security ~= nil, "no security")
  assert(sock ~= nil, "no socket")
  assert(type(hasChunks) == "boolean", "hasChunks must be boolean")
  assert(model ~= nil, "no model")

  local res = {
    security = security,
    logging = config.logging.binary,

    requestId = 0,
    sequenceNumber = 0,
    channelId = 0,

    headerSize = 0,

    -- buffer for Chunk.
    -- Binary types encoder
    Model = model,

    -- Socket where to flush chunks
    sock = sock,

    -- Binary mappings has support for breakin message to chunks: HEL,OPN,MSG,CLO
    -- http transport has no support for chunks
    hasChunks = hasChunks
  }

  setmetatable(res, ch)

  res:setBufferSize(config.bufSize)

  return res
end

return {new=new}
