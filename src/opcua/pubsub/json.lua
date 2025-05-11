local uadp = require("opcua.pubsub.uadp")

local function getPublisherType(t)
  if type(t) == 'number' then
    if t < 0 then
      error("Unsupported PublisherId Type")
    elseif t <= 0xFF then
      return 0
    elseif t <= 0xFFFF then
      return 1
    elseif t <= 0xFFFFFFFF then
      return 2
    else
      return 3
    end
  elseif type(t) == 'string' then
    return 4
  else
    error("Unsupported PublisherId Type")
  end
end

local function encodePublisherId(enc, PublisherId, PublisherIdType)
  PublisherIdType = PublisherIdType or getPublisherType(PublisherId)
  if PublisherIdType == uadp.publisherIdType.UINT8 then
    enc:uint8(PublisherId)
  elseif PublisherIdType == uadp.publisherIdType.UINT16 then
    enc:uint16(PublisherId)
  elseif PublisherIdType == uadp.publisherIdType.UINT32 then
    enc:uint32(PublisherId)
  elseif PublisherIdType == uadp.publisherIdType.UINT64 then
    enc:uint64(PublisherId)
  elseif PublisherIdType == uadp.publisherIdType.STRING then
    enc:string(PublisherId)
  else
    error("Unsupported PublisherId Type")
  end
end

local function encodeField(enc, encF, name, val, ...)
  if val ~= nil then
    enc:beginField(name)
    encF(enc, val, ...)
    enc:endField(name)
  end
end

local function decodeField(dec, decF, name)
  dec:beginField(name)
  local field
  if dec:stackLast() ~= ba.json.null then
    field = decF(dec)
  end
  dec:endField(name)
  return field
end

local function decodeFields(dec)
  local fields = {}
  local obj = dec:stackLast()
  for name,v in pairs(obj) do
    if type(v) == 'table' and v.Value ~= nil then
      fields[name] = decodeField(dec, dec.dataValue, name)
    else
      fields[name] = decodeField(dec, dec.variant, name)
    end
  end

  return fields
end

local function encodeFields(enc, fields)
  enc:beginObject()
  for name,val in pairs(fields) do
    local encF
    if val.Value then
      encF = enc.dataValue
    else
      encF = enc.variant
    end
    encodeField(enc, encF, name, val)
  end
  enc:endObject()
end

local function encodeConfiguration(enc, val)
  enc:beginObject()
  encodeField(enc, enc.uint32, "MajorVersion", val.MajorVersion)
  encodeField(enc, enc.uint32, "MinorVersion", val.MinorVersion)
  enc:endObject()
end

local function decodeConfiguration(dec)
  return {
    MajorVersion = decodeField(dec, dec.uint32, "MajorVersion"),
    MinorVersion = decodeField(dec, dec.uint32, "MinorVersion")
  }
end

local messageTypes <const> = {
  ["ua-keyframe"] = uadp.dataSetMessageType.DATA_KEY_FRAME,
  ["ua-deltaframe"] = uadp.dataSetMessageType.DELTA_DATA_FRAME,
  [uadp.dataSetMessageType.DATA_KEY_FRAME] = "ua-keyframe",
  [uadp.dataSetMessageType.DELTA_DATA_FRAME] = "ua-deltaframe"
}

local function decodeDataSetMessage(dec)
  dec:beginObject()
  local message = {}
  if dec:stackLast().Payload == nil then
    message.DataSetMessageType = uadp.dataSetMessageType.DATA_KEY_FRAME
    message.Payload = decodeFields(dec)
  else
    message.DataSetWriterId = decodeField(dec, dec.uint16, "DataSetWriterId")
    message.DataSetWriterName = decodeField(dec, dec.string, "DataSetWriterName")
    message.PublisherId = decodeField(dec, dec.string, "PublisherId")
    message.WriterGroupName = decodeField(dec, dec.string, "WriterGroupName")
    message.SequenceNumber = decodeField(dec, dec.uint32, "SequenceNumber")
    message.MetaDataVersion = decodeField(dec, decodeConfiguration, "MetaDataVersion")
    message.MinorVersion = decodeField(dec, dec.uint32, "MinorVersion")
    message.Timestamp = decodeField(dec, dec.dateTime, "Timestamp")
    message.Status = decodeField(dec, dec.statusCode, "Status")

    local DataSetMessageType = decodeField(dec, dec.string, "MessageType")
    message.DataSetMessageType = messageTypes[DataSetMessageType] or uadp.dataSetMessageType.DATA_KEY_FRAME
    message.Payload = decodeField(dec, decodeFields, "Payload")
  end

  dec:endObject()
  return message
end

local function decodeDataSetMessages(dec)
  -- https://reference.opcfoundation.org/Core/Part14/v105/docs/7.2.5.4
  dec:beginField("Messages")

  local messages = {}
  if type(dec:stackLast()) ~= 'table' then
    error("Invalid message content")
  end

  local isArray = dec:stackLast()[1] ~= nil
  local sz = 1
  if isArray then
    sz = dec:beginArray()
  end

  for i=1,sz do
    messages[i] = decodeDataSetMessage(dec)
  end

  if isArray then
    dec:endArray()
  end

  dec:endField("Messages")

  return messages
end

local function encodeDataSetMessages(enc, DatasetMessages)
  enc:beginArray()
  for i=1,#DatasetMessages do
    enc:beginObject()
    local message = DatasetMessages[i]
    encodeField(enc, enc.uint16, "DataSetWriterId", message.DataSetWriterId)
    encodeField(enc, enc.string, "DataSetWriterName", message.DataSetWriterName)
    encodeField(enc, enc.string, "PublisherId", message.PublisherId)
    encodeField(enc, enc.string, "WriterGroupName", message.WriterGroupName)
    encodeField(enc, enc.uint32, "SequenceNumber", message.SequenceNumber)
    encodeField(enc, encodeConfiguration, "MetaDataVersion", message.MetaDataVersion)
    encodeField(enc, enc.uint32, "MinorVersion", message.MinorVersion)
    encodeField(enc, enc.dateTime, "Timestamp", message.Timestamp)
    encodeField(enc, enc.statusCode, "Status", message.Status)
    encodeField(enc, enc.string, "MessageType", messageTypes[message.DataSetMessageType])
    encodeField(enc, encodeFields, "Payload", message.Payload)
    enc:endObject()
  end

  enc:endArray()
end

local function encodeDiscoveryAnouncement(enc, DiscoveryAnouncement)
  -- https://reference.opcfoundation.org/Core/Part14/v105/docs/7.2.4.6

  local DatasetMetadata = DiscoveryAnouncement.DatasetMetadata
  local AnnouncementType = DiscoveryAnouncement.AnnouncementType
  if AnnouncementType == uadp.announcementType.PUBLISHER_ENDPOINTS then
    error("AnnouncementType PUBLISHER_ENDPOINTS Not implemented")
  elseif AnnouncementType == uadp.announcementType.DATASET_METADATA then
    encodeField(enc, enc.string, "MessageType", "ua-metadata")
    encodeField(enc, enc.uint16, "DataSetWriterId", DatasetMetadata.DataSetWriterId)
    encodeField(enc, enc.string, "DataSetWriterName", DatasetMetadata.DataSetWriterName)

    enc:beginField("MetaData")
    enc:Encode("i=14523", DatasetMetadata.Metadata)
    enc:endField("MetaData")

  elseif AnnouncementType == uadp.announcementType.DATASET_WRITER_CONF then
    error("AnnouncementType DATASER_WRITER_CONF Not implemented")
  elseif AnnouncementType == uadp.announcementType.PUBSUB_CONNECTION then
    error("AnnouncementType PUBSUB_CONNECTION Not implemented")
  elseif AnnouncementType == uadp.announcementType.APPLICATION_INFO then
    -- local ApplicationInformationType = dec:uint16()
    error("AnnouncementType APPLICATION_INFO Not implemented")
  else
    error("Unsupported AnnouncementType " .. tostring(AnnouncementType))
  end
end

local function decodeAnounceMeta(dec)
  return dec:Decode("i=14523")
end

-- Format: https://reference.opcfoundation.org/Core/Part14/v105/docs/7.2.4.4
local function decodeMessage(dec)
  if dec.bit == nil then
    return error("Invalid decoder")
  end

  local result = {}

  dec:beginObject()

  result.MessageId = decodeField(dec, dec.string, "MessageId")
  result.WriterGroupName = decodeField(dec, dec.string, "WriterGroupName")

  dec:beginField("PublisherId")
  result.PublisherId = dec:stackLast()
  result.PublisherIdType = getPublisherType(result.PublisherId)
  dec:endField("PublisherId")

  result.Timestamp = decodeField(dec, dec.dateTime, "Timestamp")
  local messageType = decodeField(dec, dec.string, "MessageType")

  if messageType == 'ua-metadata' then
    local DatasetMetadata = {
      DataSetWriterId = decodeField(dec, dec.uint16, "DataSetWriterId"),
      DataSetWriterName = decodeField(dec, dec.string, "DataSetWriterName"),
      Metadata = decodeField(dec, decodeAnounceMeta, "MetaData"),
    }

    result.DiscoveryAnouncement = {
      AnnouncementType = uadp.announcementType.DATASET_METADATA,
      DatasetMetadata = DatasetMetadata
    }
  elseif messageType == 'ua-data' then
    result.ReplyTo = decodeField(dec, dec.string, "ReplyTo")
    result.DataSetClassId = decodeField(dec, dec.string, "DataSetClassId")
    result.Messages = decodeDataSetMessages(dec)
  else
    error("Unsupported message type"..messageType)
  end

  dec:endObject()

  return result
end

-- Format: https://reference.opcfoundation.org/Core/Part14/v105/docs/7.2.4.4
local function encodeMessage(enc, msg)
  enc:beginObject()

  encodeField(enc, enc.string, "MessageId", msg.MessageId)
  encodeField(enc, encodePublisherId, "PublisherId", msg.PublisherId, msg.PublisherIdType)
  encodeField(enc, enc.dateTime, "Timestamp", msg.Timestamp)
  encodeField(enc, enc.string, "WriterGroupName", msg.WriterGroupName)

  -- Payload
  if msg.Messages then
    encodeField(enc, enc.string, "MessageType", "ua-data")
    encodeField(enc, enc.string, "DataSetClassId", msg.DataSetClassId)
    encodeField(enc, enc.string, "ReplyTo", msg.ReplyTo)
    encodeField(enc, encodeDataSetMessages, "Messages", msg.Messages)
  elseif msg.DiscoveryAnouncement then
    encodeDiscoveryAnouncement(enc, msg.DiscoveryAnouncement)
  else
    error("Unsupported msg.NetworkMessageType " .. tostring(msg.NetworkMessageType))
  end

  enc:endObject()

end


return {
  decode = decodeMessage,
  encode = encodeMessage,
}
