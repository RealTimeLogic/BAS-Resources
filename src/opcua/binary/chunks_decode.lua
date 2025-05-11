local compat = require("opcua.compat")
local Q = require("opcua.binary.queue")
local BinaryDecoder = require("opcua.binary.decoder")
local ua = require("opcua.api")

local traceE = ua.trace.err
local traceI = ua.trace.inf
local traceD = ua.trace.dbg
local tools = ua.Tools
local fmt = string.format

local HeaderSize = 8
local BadTcpMessageTypeInvalid = 0x807E0000
local BadTcpMessageTooLarge = 0x80800000
local BadCommunicationError = 0x80050000
local BadInternalError = 0x80020000
local BadSecurityChecksFailed = 0x80130000
local BadDecodingError = 0x80020000


local ch = {}
ch.__index = ch

function ch:hello()
  local infOn = self.logging.infOn
  if infOn then traceI("binary | Receiving hello") end

  self.q.msgMode = false
  local res = self.Decoder:hello()
  if infOn then traceI("binary | Hello received") end
  return res
end

function ch:acknowledge()
  local infOn = self.logging.infOn
  if infOn then traceI("binary | Receiving acknowledge") end

  self.q.msgMode = false
  local res = self.Decoder:acknowledge()
  if infOn then traceI("binary | Ackowledge received") end
  return res
end

function ch:setBufferSize(size)
  local infOn = self.logging.infOn
  if infOn then traceI(fmt("binary | New buffer size %d", size)) end
  self.q.data = Q.new(size)
  self.Decoder = self.Model:createBinaryDecoder(self.q)
end

function ch:message()
  local dbgOn = self.logging.dbgOn
  local infOn = self.logging.infOn
  local errOn = self.logging.errOn

  if infOn then traceI("binary | Receiving message") end

  self.q.msgMode = true
  local i = self.Decoder:nodeId()
  if infOn then traceI(fmt("binary | Received message ID '%s'", i)) end

  if dbgOn then traceD("binary | Decoding message body") end
  local msg = self.q.msg
  local extObject = self.Decoder:getExtObject(i)
  if extObject == nil then
    if errOn then traceE(fmt("binary | Unknown extension object '%s'", i)) end
    error(BadDecodingError)
  end
  msg.TypeId = extObject.dataTypeId
  msg.Body = self.Decoder:Decode(msg.TypeId)

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

local function new(config, security, sock, hasChunks, model)
  assert(config ~= nil, "no config")
  assert(sock ~= nil, "no socket")
  assert(security ~= nil, "no security")
  assert(type(hasChunks) == "boolean", "hasChunks must be boolean")
  assert(model ~= nil, "no model")

  local d = Q.new(config.bufSize)
  local coq = {
    security = security,
    config = config,
    hasChunks = hasChunks,
    msgMode = false,
    d = d,  -- Queue with chunk data
    binaryDecoder = BinaryDecoder.new(d),
    sock = sock,
    leftSize = 0, -- size of data left in current chunk buffer
    logging = config.logging.binary,

    recvSize = function(self, size)
      local dbgOn = self.logging.dbgOn
      local errOn = self.logging.errOn

      if dbgOn then traceD(fmt("binary | Reading next %d bytes", size)) end
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
          self:disconnect()
          error(BadInternalError)
        end

        local data = sock:receive(size - #q)
        if self.logging.dbgOn  then
          traceD(fmt("binary | ------------ RECEIVED %d BYTES----------------", #data))
          tools.hexPrint(data, function(msg) traceD("binary | "..msg) end)
          traceD("binary | ----------------------------------------------")
        end

        local leftSize = math.min(size - #q, #data)
        if leftSize >= #data then
          if dbgOn then traceD("binary | Push all data to queue") end
          q:pushBack(data)
        else
          if dbgOn then
            traceD(fmt("binary | Received too much data. Put to partial buffer. Push to queue %d bytes", leftSize))
          end
          q:pushBack(string.sub(data, 1, leftSize))
          self.partBuf = data
          self.partSize = leftSize
        end
      end
    end,

    disconnect = function(self)
      local infOn = self.logging.infOn
      if infOn then traceI("binary | Disconnecing and closing socket") end
      self.sock:shutdown()
      self.d:clear()
      self.partBuf = nil
      self.partSize = 0
    end,

    receiveChunk = function(self, sz)
      local dbgOn = self.logging.dbgOn
      local errOn = self.logging.errOn

      if dbgOn then traceD("binary | Receiving next chunk") end
      local q = self.d
      if #q ~= 0 then
        if errOn then traceE("binary | Chunk read partially") end
        self:disconnect()
        error(BadInternalError)
      end

      q:clear()

      if not self.hasChunks then
        if self.partBuf then
          sz = #self.partBuf - self.partSize
        end
        self:recvSize(sz)
        self.msg = {
          ChannelId = 0,
          RequestId = 0
        }

        return
      end

      local capacity = compat.bytearray.size(q.Buf)

      self:recvSize(HeaderSize)
      local hdr = self.binaryDecoder:messageHeader()
      if hdr.MessageSize > capacity then
        self:disconnect()
        error(BadTcpMessageTooLarge)
      end

      local bodySize = hdr.MessageSize - HeaderSize
      self:recvSize(bodySize)

      if hdr.Type ~= "MSG" and hdr.Chunk ~= "F" then
        if errOn then traceE(fmt("binary | Message %s cannot be chunked", hdr.Type)) end
        self:disconnect()
        error(BadTcpMessageTypeInvalid)
      end

      if dbgOn then traceD(fmt("binary | Received message '%s' chunk '%s'", hdr.Type, hdr.Chunk)) end
      if hdr.Type == "MSG" or hdr.Type == "CLO" then
        if self.msgMode == false then
          if errOn then traceE("binary | Secure channel not opened") end
          self:disconnect()
          error(BadTcpMessageTypeInvalid)
        end

        local channelId = self.binaryDecoder:uint32()
        local secureHeader = self.binaryDecoder:symmetricSecurityHeader()
        self.policy:symmetricDecrypt(q.Buf)

        local sequenceHeader = self.binaryDecoder:sequenceHeader()

        self.msg = {
          ChannelId = channelId,
          SecureHeader = secureHeader,
          RequestId = sequenceHeader.RequestId
        }

        if hdr.Chunk == 'A' then
          if errOn then traceE("binary | Received ABORT message") end
          local msg = self.binaryDecoder:error()
          if errOn then traceE(fmt("binary | ERROR code: %s. Reason: %s", msg.Error, msg.Reason)) end
          error(msg.Error)
        end

      elseif hdr.Type == "OPN" then
        if self.msgMode == false then
          if errOn then traceE("binary | Secure channel not opened") end
          self:disconnect()
          error(BadTcpMessageTypeInvalid)
        end

        local channelId = self.binaryDecoder:uint32()
        local secureHeader = self.binaryDecoder:asymmetricSecurityHeader()

        local securePolicy = self.security(secureHeader.SecurityPolicyUri)
        if securePolicy.uri ~= ua.Types.SecurityPolicy.None and secureHeader.ReceiverCertificateThumbprint ~= securePolicy:getLocalThumbprint() then
          if errOn then traceE("binary | Unknown local certificate thumbprint") end
          self:disconnect()
          error(BadSecurityChecksFailed)
        end

        securePolicy:setRemoteCertificate(secureHeader.SenderCertificate)
        securePolicy:asymmetricDecrypt(self.binaryDecoder.data.Buf)
        self.policy = securePolicy

        local sequenceHeader = self.binaryDecoder:sequenceHeader()
        self.msg = {
          ChannelId = channelId,
          SecureHeader = secureHeader,
          RequestId = sequenceHeader.RequestId,
        }
      elseif hdr.Type == "HEL" then
        if self.msgMode == true then
          if errOn then traceE("binary | Secure channel already opened") end
          self:disconnect()
          error(BadTcpMessageTypeInvalid)
        end

        self.msg = nil
      elseif hdr.Type == "ACK" then
        if self.msgMode == true then
          if errOn then traceE("binary | Secure channel already opened") end
          self:disconnect()
          error(BadTcpMessageTypeInvalid)
        end

        if hdr.MessageSize ~= 28 then
          if errOn then traceE("binary | Invalid Acnowledge message") end
          self:disconnect()
          error(BadCommunicationError)
        end
        self.msg = nil
      elseif hdr.Type == "ERR" then
        if errOn then traceE("binary | Received ERR message") end
        local msg = self.binaryDecoder:error()
        if errOn then traceE(fmt("binary | ERROR code: %s. Reason:%s", msg.Error, msg.Reason)) end
        error(msg.Error)
      else
        if errOn then traceE("binary | Unknown message") end
        self:disconnect()
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
        self:receiveChunk(len)
        q:popFront(len, tgt)
        return
      end

      if qlen > 0 then
        q:popFront(qlen, tgt)
        self:receiveChunk(len - qlen)
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
    Model = model,
    Decoder = model:createBinaryDecoder(coq),
  }

  setmetatable(res, ch)
  return res
end

return {new=new}
