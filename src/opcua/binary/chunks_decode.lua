local Q = require("opcua.binary.queue")
local Binary = require("opcua.binary.encode_types")
local Msg = require("opcua.binary.message_id")
local ua = require("opcua.api")

local traceE = ua.trace.err
local traceI = ua.trace.inf
local traceD = ua.trace.dbg
local tools = ua.Tools
local fmt = string.format

local HeaderSize = 8
local BadTcpMessageTypeInvalid = 0x807E0000
local BadTcpMessageTooLarge = 0x80800000
local BadNotSupported = 0x803D0000
local BadCommunicationError = 0x80050000
local BadInternalError = 0x80020000
local BadSecurityChecksFailed = 0x80130000


local ch = {}
ch.__index = ch

function ch:hello()
  local infOn = self.logging.infOn
  if infOn then traceI("binary | Receiving hello") end

  self.q.msgMode = false
  local res = self.decoder:hello()
  if infOn then traceI("binary | Hello received") end
  return res
end

function ch:acknowledge()
  local infOn = self.logging.infOn
  if infOn then traceI("binary | Receiving acknowledge") end

  self.q.msgMode = false
  local res = self.decoder:acknowledge()
  if infOn then traceI("binary | Ackowledge received") end
  return res
end

function ch:setBuferSize(size)
  local infOn = self.logging.infOn
  if infOn then traceI(fmt("binary | New buffer size %d", size)) end

  local oldData = self.q.data
  self.q.data = Q.new(size)
  self.q.data = oldData
end

local enc = {}
enc[Msg.OPEN_SECURE_CHANNEL_REQUEST] = Binary.Decoder.openSecureChannelRequest
enc[Msg.OPEN_SECURE_CHANNEL_RESPONSE] = Binary.Decoder.openSecureChannelResponse
enc[Msg.CLOSE_SECURE_CHANNEL_REQUEST] = Binary.Decoder.closeSecureChannelRequest
enc[Msg.FIND_SERVERS_REQUEST] = Binary.Decoder.findServersRequest
enc[Msg.FIND_SERVERS_RESPONSE] = Binary.Decoder.findServersResponse
enc[Msg.GET_ENDPOINTS_REQUEST] = Binary.Decoder.getEndpointsRequest
enc[Msg.GET_ENDPOINTS_RESPONSE] = Binary.Decoder.getEndpointsResponse
enc[Msg.CREATE_SESSION_REQUEST] = Binary.Decoder.createSessionRequest
enc[Msg.CREATE_SESSION_RESPONSE] = Binary.Decoder.createSessionResponse
enc[Msg.ACTIVATE_SESSION_REQUEST] = Binary.Decoder.activateSessionRequest
enc[Msg.ACTIVATE_SESSION_RESPONSE] = Binary.Decoder.activateSessionResponse
enc[Msg.CLOSE_SESSION_REQUEST] = Binary.Decoder.closeSessionRequest
enc[Msg.CLOSE_SESSION_RESPONSE] = Binary.Decoder.closeSessionResponse
enc[Msg.BROWSE_REQUEST] = Binary.Decoder.browseRequest
enc[Msg.BROWSE_RESPONSE] = Binary.Decoder.browseResponse
enc[Msg.READ_REQUEST] = Binary.Decoder.readRequest
enc[Msg.READ_RESPONSE] = Binary.Decoder.readResponse
enc[Msg.WRITE_REQUEST] = Binary.Decoder.writeRequest
enc[Msg.WRITE_RESPONSE] = Binary.Decoder.writeResponse
enc[Msg.CREATE_SUBSCRIPTION_REQUEST] = Binary.Decoder.createSubscriptionRequest
enc[Msg.CREATE_SUBSCRIPTION_RESPONSE] = Binary.Decoder.createSubscriptionResponse
enc[Msg.SERVICE_FAULT] = Binary.Decoder.serviceFault
enc[Msg.TRANSLATE_BROWSE_PATHS_TO_NODE_IdS_REQUEST] = Binary.Decoder.translateBrowsePathsToNodeIdsRequest
enc[Msg.TRANSLATE_BROWSE_PATHS_TO_NODE_IdS_RESPONSE] = Binary.Decoder.translateBrowsePathsToNodeIdsResponse
enc[Msg.ADD_NODES_REQUEST] = Binary.Decoder.addNodesRequest
enc[Msg.ADD_NODES_RESPONSE] = Binary.Decoder.addNodesResponse

function ch:message()
  local dbgOn = self.logging.dbgOn
  local infOn = self.logging.infOn
  local errOn = self.logging.errOn

  if infOn then traceI("binary | Receiving message") end

  self.q.msgMode = true
  local i = self.decoder:nodeId()
  if infOn then traceI(fmt("binary | Received message ID '%s'", i)) end
  local f = enc[i]
  if not f then
    if errOn then traceE("binary | Decoding unsupported") end
    error(BadNotSupported)
  end

  if dbgOn then traceD("binary | Decoding message body") end

  local msg = self.q.msg
  msg.type = i
  msg.body = f(self.decoder)

  if infOn then traceI("binary | Message decoded") end
  return msg
end

function ch:setNonces(localNonce, remoteNonce)
  self.q.policy:setNonces(localNonce, remoteNonce)
end

function ch:setSecureMode(secureMode)
  self.q.policy:setSecureMode(secureMode)
end

function ch:setupPolicy(uri, remoteCert)
  local policy = self.q.security(uri)
  policy:setRemoteCertificate(remoteCert)
  self.q.policy = policy
end


local function new(config, security, sock)
  assert(config ~= nil, "no config")
  assert(sock ~= nil, "no socket")
  assert(security ~= nil, "no security")

  local d = Q.new(config.bufSize)
  local coq = {
    security = security,
    config = config,
    msgMode = false,
    d = d,  -- Queue with chunk data
    decoder = Binary.Decoder.new(d),
    sock = sock,
    leftSize = 0, -- size of data left in current chunk buffer
    logging = config.logging.binary,

    recvSize = function(self, size)
      local dbgOn = self.logging.dbgOn
      local errOn = self.logging.errOn

      if dbgOn then traceD(fmt("binary | Readind next %d bytes", size)) end
      local q = self.d
      if self.partBuf then
        if dbgOn then traceD(fmt("binary | Partial buffer of size %d", #self.partBuf)) end
        local partSize = math.min(#self.partBuf - self.partSize, size)
        q:pushBack(string.sub(self.partBuf, self.partSize + 1, self.partSize + partSize))
        self.partSize = self.partSize + partSize
        if self.partSize ~= #self.partBuf then
          if dbgOn then traceD("binary | Whole data read from buffer ") end
          return
        end

        if dbgOn then traceD("binary | Partial buffer read completely") end

        self.partSize = nil
        self.partBuf = nil
      end

      -- receive rest chunk data
      while #q < size do
        if dbgOn then traceD("binary | Reading data from socket") end
        if self.partBuf ~= nil or self.partSize ~= nil then
          if errOn then traceE("binary | partial buffer was not read completely") end
          error(BadInternalError)
        end

        local data = sock:receive(size - #q)
        if self.logging.dbgOn  then
          traceD(fmt("socket | ------------ RECEIVED %d BYTES----------------", #data))
          tools.hexPrint(data, function(msg) traceD("socket | "..msg) end)
          traceD("socket | ----------------------------------------------")
        end

        local leftSize = math.min(size - #q, #data)
        if leftSize >= #data then
          if dbgOn then traceD("binary | Push all data to queue") end
          q:pushBack(data)
        else
          if dbgOn then traceD(fmt("binary | Received too much data. Put to partial buffer. Push to queue %d bytes", leftSize)) end
          q:pushBack(string.sub(data, 1, leftSize))
          self.partBuf = data
          self.partSize = leftSize
        end
      end
    end,

    receiveChunk = function(self)
      local dbgOn = self.logging.dbgOn
      local errOn = self.logging.errOn

      if dbgOn then traceD("binary | Receiving next chunk") end
      local q = self.d
      if #q ~= 0 then
        if errOn then traceE("binary | Chunk read partially") end
        error(BadInternalError)
      end

      q:clear()

      local capacity = ba.bytearray.size(q.Buf)

      self:recvSize(HeaderSize)
      local hdr = self.decoder:messageHeader()
      if hdr.messageSize > capacity then
        error(BadTcpMessageTooLarge)
      end

      local bodySize = hdr.messageSize - HeaderSize
      self:recvSize(bodySize)

      if hdr.type ~= "MSG" and hdr.chunk ~= "F" then
        if errOn then traceE(fmt("binary | Message %s cannot be chunked", hdr.type)) end
        error(BadTcpMessageTypeInvalid)
      end

      if dbgOn then traceD(fmt("binary | Received message '%s' chunk '%s'", hdr.type, hdr.chunk)) end
      if hdr.type == "MSG" or hdr.type == "CLO" then
        if self.msgMode == false then
          if errOn then traceE("binary | Secure channel not opened") end
          error(BadTcpMessageTypeInvalid)
        end

        local channelId = self.decoder:uint32()
        local secureHeader = self.decoder:symmetricSecurityHeader()
        self.policy:symmetricDecrypt(q.Buf)

        local sequenceHeader = self.decoder:sequenceHeader()

        self.msg = {
          channelId = channelId,
          secureHeader = secureHeader,
          requestId = sequenceHeader.requestId
        }

        if hdr.chunk == 'A' then
          if errOn then traceE("binary | Received ABORT message") end
          local msg = self.decoder:error()
          if errOn then traceE(fmt("binary | ERROR code: %s. Reason: %s", msg.error, msg.reason)) end
          error(msg.error)
        end

      elseif hdr.type == "OPN" then
        if self.msgMode == false then
          if errOn then traceE("binary | Secure channel not opened") end
          error(BadTcpMessageTypeInvalid)
        end

        local channelId = self.decoder:uint32()
        local secureHeader = self.decoder:asymmetricSecurityHeader()

        local securePolicy = self.security(secureHeader.securityPolicyUri)
        if securePolicy.uri ~= ua.Types.SecurityPolicy.None and secureHeader.receiverCertificateThumbprint ~= securePolicy:getLocalThumbprint() then
          if errOn then traceE("binary | Unknown local certificate thumbprint") end
          error(BadSecurityChecksFailed)
        end

        securePolicy:setRemoteCertificate(secureHeader.senderCertificate)
        securePolicy:asymmetricDecrypt(self.decoder.data.Buf)
        self.policy = securePolicy

        local sequenceHeader = self.decoder:sequenceHeader()
        self.msg = {
          channelId = channelId,
          secureHeader = secureHeader,
          requestId = sequenceHeader.requestId,
        }
      elseif hdr.type == "HEL" then
        if self.msgMode == true then
          if errOn then traceE("binary | Secure channel already opened") end
          error(BadTcpMessageTypeInvalid)
        end

        self.msg = nil
      elseif hdr.type == "ACK" then
        if self.msgMode == true then
          if errOn then traceE("binary | Secure channel already opened") end
          error(BadTcpMessageTypeInvalid)
        end

        if hdr.messageSize ~= 28 then
          if errOn then traceE("binary | Invalid Acnowledge message") end
          error(BadCommunicationError)
        end
        self.msg = nil
      elseif hdr.type == "ERR" then
        if errOn then traceE("binary | Received ERR message") end
        local msg = self.decoder:error()
        if errOn then traceE(fmt("binary | ERROR code: %s. Reason:%s", msg.error, msg.reason)) end
        error(msg.error)
      else
        if errOn then traceE("binary | Unknown message") end
        error(BadTcpMessageTypeInvalid)
      end
    end,

    popFront = function (self, len, tgt)
      local q = self.d
      local qlen = #q
      if qlen >= len then
        q:popFront(len, tgt)
        return
      end

      if qlen == 0 then
        self:receiveChunk()
        q:popFront(len, tgt)
        return
      end

      if qlen > 0 then
        q:popFront(qlen, tgt)
        self:receiveChunk()
        local qi = 1
        for pos = qlen+1,len do
          tgt[pos] = q[qi]
          qi = qi + 1
        end
        q:popFront(qi-1)
      end
    end
  }

  setmetatable(coq, {__index=d})

  local res = {
    config = config,
    logging = config.logging.binary,

    -- buffer for Chunk.
    q = coq,
    decoder = Binary.Decoder.new(coq),
  }

  setmetatable(res, ch)
  return res
end

return {new=new}
