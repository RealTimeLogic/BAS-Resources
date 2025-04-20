-- Network messages
local DATA_SET_MESSAGGE <const> = 0
local DISCOVERY_PROBE <const> = 1
local DISCOVERY_ANNOUNCEMENT <const> = 2

-- Dataset message types
local DATA_KEY_FRAME <const> = 0
local DELTA_DATA_FRAME <const> = 1
local EVENT <const> = 2
local KEEP_ALIVE <const> = 3

local PUBLISHER_TYPE_UINT8 <const> = 0
local PUBLISHER_TYPE_UINT16 <const> = 1
local PUBLISHER_TYPE_UINT32 <const> = 2
local PUBLISHER_TYPE_UINT64 <const> = 3
local PUBLISHER_TYPE_STRING <const> = 4

local FIELD_ENCODING_VARIANT <const> = 0
local FIELD_ENCODING_RAW_DATA <const> = 1
local FIELD_ENCODING_DATA_VALUE <const> = 2
local FIELD_ENCODING_KEEP_ALIVE <const> = 3

-- Discovery announcement messages
-- 0 - Reserved
local PUBLISHER_ENDPOINTS <const> = 1
local DATASET_METADATA <const> = 2
local DATASET_WRITER_CONF <const> = 3
local PUBSUB_CONNECTION <const> = 4
local APPLICATION_INFO <const> = 5

local function decodePublisherId(dec, t)
  if t == PUBLISHER_TYPE_UINT8 then
    return dec:uint8()
  elseif t == PUBLISHER_TYPE_UINT16 then
    return dec:uint16()
  elseif t == PUBLISHER_TYPE_UINT32 then
    return dec:uint32()
  elseif t == PUBLISHER_TYPE_UINT64 then
    return dec:uint64()
  elseif t == PUBLISHER_TYPE_STRING then
    return dec:string()
  end
  error("Unsupported PublisherIdType")
end

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
  if PublisherIdType == PUBLISHER_TYPE_UINT8 then
    enc:uint8(PublisherId)
  elseif PublisherIdType == PUBLISHER_TYPE_UINT16 then
    enc:uint16(PublisherId)
  elseif PublisherIdType == PUBLISHER_TYPE_UINT32 then
    enc:uint32(PublisherId)
  elseif PublisherIdType == PUBLISHER_TYPE_UINT64 then
    enc:uint64(PublisherId)
  elseif PublisherIdType == PUBLISHER_TYPE_STRING then
    enc:string(PublisherId)
  else
    error("Unsupported PublisherId Type")
  end
end


local function decodeGroupHeader(dec)
  local hdr = {}
  local flags = dec:uint8()
  if flags & 0x01 ~= 0 then
    hdr.WriterGroupId = dec:uint16()
  end

  if flags & 0x02 ~= 0 then
    hdr.GroupVersion = dec:uint32()
  end

  if flags & 0x04 ~= 0 then
    hdr.NetworkMessageNumber = dec:uint16()
  end

  if flags & 0x08 ~= 0 then
    hdr.SequenceNumber = dec:uint16()
  end

  return hdr
end

local function encodeGroupHeader(enc, hdr)
  enc:bit(hdr.WriterGroupId ~= nil)
  enc:bit(hdr.GroupVersion ~= nil)
  enc:bit(hdr.NetworkMessageNumber ~= nil)
  enc:bit(hdr.SequenceNumber ~= nil)
  enc:bit(0, 4)

  if hdr.WriterGroupId ~= nil then
    enc:uint16(hdr.WriterGroupId)
  end

  if hdr.GroupVersion ~= nil then
    enc:uint32(hdr.GroupVersion)
  end

  if hdr.NetworkMessageNumber ~= nil then
    enc:uint16(hdr.NetworkMessageNumber)
  end

  if hdr.SequenceNumber ~= nil then
    enc:uint16(hdr.SequenceNumber)
  end
end


local function decodeSecurityHeader(dec)
  local hdr = {}
  hdr.NetworkMessageSignedEnabled = dec:bit()
  hdr.NetworkMessageEncryptionEnabled = dec:bit()
  hdr.SecurityFooterEnabled = dec:bit()
  hdr.ForceKeyResetEnabled = dec:bit()
  dec:bit(4)

  hdr.SecurityTokenId = dec:uint32()

  local NonceLength = dec:uint8()
  hdr.MessageNonce = dec:array(NonceLength)
  if hdr.SecurityFooterEnabled == 1 then
    hdr.SecurityFooterSize = dec:uint16()
  end

  return hdr
end

local function encodeSecurityHeader(enc, hdr)
  enc:bit(hdr.NetworkMessageSignedEnabled)
  enc:bit(hdr.NetworkMessageEncryptionEnabled)
  enc:bit(hdr.SecurityFooterEnabled)
  enc:bit(hdr.ForceKeyResetEnabled)
  enc:bit(0, 4)
  enc:uint32(hdr.SecurityTokenId)
  local NonceLength = hdr.MessageNonce == nil and 0xFFFFFFFF or #hdr.MessageNonce
  enc:uint8(NonceLength)
  enc:array(hdr.MessageNonce)

  if hdr.SecurityFooterEnabled == 1 then
    enc:uint16(hdr.SecurityFooterSize)
  end
end

local function decodeFields(dec, DataSetMessageType, FieldEncoding)
  local decF
  if FieldEncoding == FIELD_ENCODING_VARIANT then
    decF = dec.variant
  -- elseif FieldEncoding == FIELD_ENCODING_RAW_DATA then
    -- RawDataField
    -- Not implemented yet. Parsing will be skipped and returned as bytearray
  elseif FieldEncoding == FIELD_ENCODING_DATA_VALUE then
    decF = dec.dataValue
  elseif FieldEncoding == FIELD_ENCODING_KEEP_ALIVE then
    -- KeepAlive
    decF = nil
  else
    error("Unsupported FieldEncoding " .. tostring(FieldEncoding))
  end

  local isValue = FieldEncoding == FIELD_ENCODING_DATA_VALUE
  local fields
  if DataSetMessageType == DATA_KEY_FRAME then
    -- DataKeyFrame
    local fieldCount = dec:uint16()
    fields = {}
    for fidxi=1,fieldCount do
      local field = decF(dec)
      fields[fidxi] = {
        Index=fidxi - 1,
        Value= field
      }
    end
  elseif DataSetMessageType == DELTA_DATA_FRAME then
    -- DeltaDaframe
    local fieldCount = dec:uint16()
    fields = {}
    for fidxi=1,fieldCount do
      local fieldIndex = dec:uint16()
      local fieldValue = decF(dec)
      fields[fidxi] = {
        Index = fieldIndex,
        Value= fieldValue
      }
    end
  elseif DataSetMessageType == EVENT then
    -- Event
    local fieldCount = dec:uint16()
    fields = {}
    for fidxi=1,fieldCount do
      local field = dec:variant()
      fields[fidxi] = {
        Index=fidxi - 1,
        Value= field
      }
    end
  -- elseif DataSetMessageType == KEEP_ALIVE then
    -- KeepAlive
    -- Has no payload
  end

  return fields
end

local function encodeFields(enc, fields, DataSetMessageType, FieldEncoding)
  local encF

  if FieldEncoding == FIELD_ENCODING_KEEP_ALIVE then
    return
  elseif FieldEncoding == FIELD_ENCODING_VARIANT then
    encF = enc.variant
  elseif FieldEncoding == FIELD_ENCODING_RAW_DATA then
    -- RawDataField
    error("Raw Data fields Not implemented yet.")
  elseif FieldEncoding == FIELD_ENCODING_DATA_VALUE then
    encF = enc.dataValue
  elseif DataSetMessageType == EVENT then
    encF = enc.variant
  else
    error("Unsupported FieldEncoding " .. tostring(FieldEncoding))
  end

  local hasFieldIndex = DataSetMessageType == DELTA_DATA_FRAME
  -- KeepAlive Has no payload
  if DataSetMessageType ~= KEEP_ALIVE then
    local fieldCount = 0
    for _ in pairs(fields) do
      fieldCount = fieldCount + 1
    end
    enc:uint16(fieldCount)

    for idx,field in pairs(fields) do
      if not hasFieldIndex and idx ~= (field.Index + 1) then
        error("Invalid field index")
      end

      if hasFieldIndex then
        enc:uint16(field.Index)
      end
      encF(enc, field.Value)
    end
  end
end

local function decodeDataSetMessages(dec, dataSetWriterIDs)
  -- https://reference.opcfoundation.org/Core/Part14/v105/docs/7.2.4.5
  local messageCount = dataSetWriterIDs[1] and #dataSetWriterIDs or 1
  local messageSizes = {-1}

  -- The field with message sizes shall be omitted if _messageCount_is_one_ or if _bit_6_of_the_UADPFlags_is_false_
  if messageCount > 1 then
    -- Message Sizes in bytes
    for i=1,messageCount do
      messageSizes[i] = dec:uint16()
    end
  end

  local messages = {}
  for i=1,messageCount do
    -- TODO REMOVE ACCESS INTERNALE MEMBER
    local data = dec.Deserializer.data
    local off = #data

    local message = {
      DataSetWriterId = dataSetWriterIDs[i]
    }
    -- DataSetFlags1
    local dataSetMessageValid = dec:bit()
    local FieldEncoding = dec:bit(2)
    local DataSetMessageSequenceNumberEnabled = dec:bit()
    local StatusEnabled = dec:bit()
    local ConfigurationVersionMajorVersionEnabled = dec:bit()
    local ConfigurationVersionMinorVersionEnabled = dec:bit()
    local DataSetFlags2Enabled = dec:bit()
    -- DataSetFlags2
    local DataSetMessageType = 0
    local TimestampEnabled
    local PicoSecondsIncluded

    if DataSetFlags2Enabled == 1 then
      DataSetMessageType = dec:bit(4)
      TimestampEnabled = dec:bit()
      PicoSecondsIncluded = dec:bit()
      dec:bit(2)
    end

    message.DataSetMessageValid = dataSetMessageValid
    if DataSetMessageSequenceNumberEnabled == 1 then
      message.DataSetMessageSequenceNumber = dec:uint16()
    end
    if TimestampEnabled == 1 then
      message.Timestamp = dec:dateTime()
    end
    if PicoSecondsIncluded == 1 then
      message.PicoSeconds = dec:uint16()
    end
    if StatusEnabled == 1 then
      message.Status = dec:uint16()
    end
    if ConfigurationVersionMajorVersionEnabled == 1 then
      message.ConfigurationVersionMajorVersion = dec:uint32()
    end
    if ConfigurationVersionMinorVersionEnabled == 1 then
      message.ConfigurationVersionMinorVersion = dec:uint32()
    end

    message.DataSetMessageType = DataSetMessageType
    message.FieldEncoding = FieldEncoding
    -- RawDataField (FieldEncoding == 1) is not implemented yet. Skip and returned as bytearray
    if FieldEncoding ~= FIELD_ENCODING_RAW_DATA then
      message.Fields = decodeFields(dec, DataSetMessageType, FieldEncoding)
    end

    local msgSize = messageSizes[i]
    -- Is msgSize then there is only one message: skip skip until end of data
    if msgSize < 0 then
      if #data > 0 then
        message.Padding = tostring(data)
      end
      message.PaddingSize = #data
    else
      -- Calculate padding size
      local off1 = #data
      local len = msgSize - (off - off1)
      if len > 0 then
        message.Padding = dec:array(len)
      end
      message.PaddingSize = len
    end
    messages[i] = message
  end

  return messages
end

local function encodeDataSetMessage(enc, message)
  -- DataSetFlags1
  local DataSetMessageValid = true
  -- DataValue is ther default format since it is stored in the address space.
  local FieldEncoding = message.FieldEncoding or FIELD_ENCODING_DATA_VALUE
  local DataSetMessageSequenceNumberEnabled = message.DataSetMessageSequenceNumber ~= nil
  local StatusEnabled = message.Status ~= nil
  local ConfigurationVersionMajorVersionEnabled = message.ConfigurationVersionMajorVersion ~= nil
  local ConfigurationVersionMinorVersionEnabled = message.ConfigurationVersionMinorVersion ~= nil
  local PicoSecondsIncluded = message.PicoSeconds ~= nil
  local TimestampEnabled = message.Timestamp ~= nil
  local DataSetMessageType = message.DataSetMessageType or DATA_KEY_FRAME
  local DataSetFlags2Enabled = DataSetMessageType ~= 0 or TimestampEnabled or PicoSecondsIncluded

  enc:bit(DataSetMessageValid)
  enc:bit(FieldEncoding, 2)
  enc:bit(DataSetMessageSequenceNumberEnabled)
  enc:bit(StatusEnabled)
  enc:bit(ConfigurationVersionMajorVersionEnabled)
  enc:bit(ConfigurationVersionMinorVersionEnabled)
  enc:bit(DataSetFlags2Enabled)

  if DataSetFlags2Enabled then
    enc:bit(DataSetMessageType, 4)
    enc:bit(TimestampEnabled)
    enc:bit(PicoSecondsIncluded)
    enc:bit(0, 2)
  end

  if DataSetMessageSequenceNumberEnabled then
    enc:uint16(message.DataSetMessageSequenceNumber)
  end
  if TimestampEnabled then
    enc:dateTime(message.Timestamp)
  end
  if PicoSecondsIncluded then
    enc:uint16(message.PicoSeconds)
  end
  if StatusEnabled then
    enc:uint16(message.Status)
  end
  if ConfigurationVersionMajorVersionEnabled then
    enc:uint32(message.ConfigurationVersionMajorVersion)
  end
  if ConfigurationVersionMinorVersionEnabled then
    enc:uint32(message.ConfigurationVersionMinorVersion)
  end

  -- RawDataField (FieldEncoding == 1) is not implemented yet. Skip and returned as bytearray
  if FieldEncoding == FIELD_ENCODING_RAW_DATA then
    if message.Padding == nil then
      error("Padding is required for RawDataField")
    end
    enc:array(message.Padding)
  elseif FieldEncoding ~= FIELD_ENCODING_KEEP_ALIVE then
    encodeFields(enc, message.Fields, DataSetMessageType, FieldEncoding)
  end
end

-- Small helper class that calculates size of serialized data.
local function newSizeQ()
  local sizeQ = {

    size = 0,

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


local function encodeDataSetMessages(enc, Messages, PayloadHeaderEnabled)
  -- https://reference.opcfoundation.org/Core/Part14/v105/docs/7.2.4.5
  local messageCount = #Messages

  -- The field with message sizes shall be omitted if _messageCount_is_one_ or if _bit_6_of_the_UADPFlags_is_false_
  if PayloadHeaderEnabled and messageCount > 1 then
    local data = enc.Serializer.data
    local sizeQ = newSizeQ()
    for i=1,messageCount do
      sizeQ:clear()
      enc.Serializer.data = sizeQ
      encodeDataSetMessage(enc, Messages[i])
      enc.Serializer.data = data

      enc:uint16(sizeQ.size)
    end

  end

  for i=1,messageCount do
    encodeDataSetMessage(enc, Messages[i])

    -- local msgSize = messageSizes[i]
    -- -- Is msgSize then there is only one message: skip skip until end of data
    -- if msgSize < 0 then
    --   if #dec.data > 0 then
    --     message.Padding = tostring(dec.data)
    --   end
    --   message.PaddingSize = #dec.data
    -- else
    --   -- Calculate padding size
    --   local off1 = #dec.data
    --   local len = msgSize - (off - off1)
    --   if len > 0 then
    --     message.Padding = dec:array(len)
    --   end
    --   message.PaddingSize = len
    -- end
  end
end


local function decodeDiscoveryAnouncement(dec)
  -- https://reference.opcfoundation.org/Core/Part14/v105/docs/7.2.4.6
  local AnnouncementType = dec:byte()
  local SequenceNumber = dec:uint16()
  local DiscoveryAnouncement = {
    AnnouncementType = AnnouncementType,
    SequenceNumber = SequenceNumber
  }

  if AnnouncementType == PUBLISHER_ENDPOINTS then
    error("AnnouncementType PUBLISHER_ENDPOINTS Not implemented")
  elseif AnnouncementType == DATASET_METADATA then
    DiscoveryAnouncement.DatasetMetadata = {
      DataSetWriterId = dec:uint16(),
      Metadata = dec:Decode("i=14523"),
      StatusCode = dec:statusCode()
    }
  elseif AnnouncementType == DATASET_WRITER_CONF then
    error("AnnouncementType DATASER_WRITER_CONF Not implemented")
  elseif AnnouncementType == PUBSUB_CONNECTION then
    error("AnnouncementType PUBSUB_CONNECTION Not implemented")
  elseif AnnouncementType == APPLICATION_INFO then
    error("AnnouncementType APPLICATION_INFO Not implemented")
    -- local ApplicationInformationType = dec:uint16()
  else
    error("Unsupported AnnouncementType " .. tostring(AnnouncementType))
  end

  return DiscoveryAnouncement
end

local function encodeDiscoveryAnouncement(enc, DiscoveryAnouncement)
  -- https://reference.opcfoundation.org/Core/Part14/v105/docs/7.2.4.6

  enc:byte(DiscoveryAnouncement.AnnouncementType)
  enc:uint16(DiscoveryAnouncement.SequenceNumber)
  local AnnouncementType = DiscoveryAnouncement.AnnouncementType
  if AnnouncementType == PUBLISHER_ENDPOINTS then
    error("AnnouncementType PUBLISHER_ENDPOINTS Not implemented")
  elseif AnnouncementType == DATASET_METADATA then
    local DatasetMetadata = DiscoveryAnouncement.DatasetMetadata
    enc:uint16(DatasetMetadata.DataSetWriterId)

    local metadata = DatasetMetadata.Metadata
    -- DataTypeSchemaHeader (https://reference.opcfoundation.org/Core/Part5/v105/docs/12.31)
    local namespacesSize = metadata.Namespaces and #metadata.Namespaces or 0xFFFFFFFF
    enc:uint32(namespacesSize)
    if namespacesSize ~= 0xFFFFFFFF then
      for i=1,namespacesSize do
        enc:string(metadata.Namespaces[i])
      end
    end

    local structureDataTypeSize = metadata.StructureDataTypes and #metadata.StructureDataTypes or 0xFFFFFFFF
    enc:uint32(structureDataTypeSize)
    if structureDataTypeSize ~= 0xFFFFFFFF then
      if structureDataTypeSize ~= 0 then
        error("encoding metadata.StructureDataTypes not implemented")
      end
      -- for =1,structureDataTypeSize do
      --   error("encoding metadata.StructureDataTypes not implemented")
      -- end
    end

    local enumDataTypeSize = metadata.EnumDataTypes and #metadata.EnumDataTypes or 0xFFFFFFFF
    enc:uint32(enumDataTypeSize)
    if enumDataTypeSize ~= 0xFFFFFFFF then
      if enumDataTypeSize ~= 0 then
        error("encoding metadata.EnumDataTypes not implemented")
      end
      -- local enumDataTypes = metadata.EnumDataTypes
      -- for i=1,enumDataTypeSize do
      --   error("encoding metadata.EnumDataTypes not implemented")
      -- end
    end

    local simpleDataTypeSize = metadata.SimpleDataTypes and #metadata.SimpleDataTypes or 0xFFFFFFFF
    enc:uint32(simpleDataTypeSize)
    if simpleDataTypeSize ~= 0xFFFFFFFF then
      if simpleDataTypeSize ~= 0 then
        error("encoding metadata.SimpleDataTypes not implemented")
      end
      -- local simpleDataTypes = metadata.SimpleDataTypes
      -- for i=1,simpleDataTypeSize do
      --   error("encoding metadata.SimpleDataTypes not implemented")
      -- end
    end

    -- DataSetMetaDataType
    enc:string(metadata.Name)
    enc:localizedText(metadata.Description)
    local fieldCount = #metadata.Fields
    enc:uint32(fieldCount)
    for i=1,fieldCount do
      local field = metadata.Fields[i]
      enc:string(field.Name)
      enc:localizedText(field.Description)
      enc:uint16(field.FieldFlags)
      enc:byte(field.BuiltInType)
      enc:nodeId(field.DataType)
      enc:int32(field.ValueRank)

      local arrayDimensionsSize = field.ArrayDimensions and #field.ArrayDimensions or 0xFFFFFFFF
      enc:uint32(arrayDimensionsSize)
      if arrayDimensionsSize ~= 0xFFFFFFFF then
        local arrayDimensions = field.ArrayDimensions
        for j=1,arrayDimensionsSize do
          enc:uint32(arrayDimensions[j])
        end
      end

      enc:uint32(field.MaxStringLength)
      enc:guid(field.DataSetFieldId)

      -- Array of KeyValuePair
      local propertiesSize = field.Properties and #field.Properties or 0xFFFFFFFF
      enc:uint32(propertiesSize)
      if propertiesSize ~= 0xFFFFFFFF then
        local keyValuePair = field.Properties
        for _=1,propertiesSize do
          error("encoding field.Properties not implemented")
          local key = enc:qualifiedName()
          local value = enc:variant()
          keyValuePair[key] = value
        end
      end
    end

    enc:guid(metadata.DataSetClassId)
    enc:uint32(metadata.ConfigurationVersion.MajorVersion)
    enc:uint32(metadata.ConfigurationVersion.MinorVersion)

    enc:statusCode(DatasetMetadata.StatusCode)

  elseif AnnouncementType == DATASET_WRITER_CONF then
    error("AnnouncementType DATASER_WRITER_CONF Not implemented")
  elseif AnnouncementType == PUBSUB_CONNECTION then
    error("AnnouncementType PUBSUB_CONNECTION Not implemented")
  elseif AnnouncementType == APPLICATION_INFO then
    -- local ApplicationInformationType = dec:uint16()
    error("AnnouncementType APPLICATION_INFO Not implemented")
  else
    error("Unsupported AnnouncementType " .. tostring(AnnouncementType))
  end
end

-- Format: https://reference.opcfoundation.org/Core/Part14/v105/docs/7.2.4.4
local function decodeMessage(dec)
  local msg = {}

  -- Byte 1 Version/Flags
  local UADPVersion = dec:bit(4)
  if UADPVersion ~= 1 then
    return error("Unsupported UADPVersion " .. tostring(UADPVersion))
  end
  local PublisherIdEnabled = dec:bit()
  local GroupHeaderEnabled = dec:bit()
  local PayloadHeaderEnabled = dec:bit()
  local ExtendedFlags1Enabled = dec:bit()

  -- Byte 2 ExtendedFlags1
  local DataSetClassIdEnabled
  local SecurityHeaderEnabled
  local TimestampEnabled
  local PicoSecondsEnabled
  local ExtendedFlags2Enabled
  local PublisherIdType = 0
  if ExtendedFlags1Enabled == 1 then
    PublisherIdType = dec:bit(3)
    DataSetClassIdEnabled = dec:bit()
    SecurityHeaderEnabled = dec:bit()
    TimestampEnabled = dec:bit()
    PicoSecondsEnabled = dec:bit()
    ExtendedFlags2Enabled = dec:bit()
  end

  -- Byte 3 ExtendedFlags2
  -- local ChunksEnabled
  local PromotedFieldsEnabled

  local NetworkMessageType = 0 -- default value
  if ExtendedFlags2Enabled == 1 then
    dec:bit() -- ChunksEnabled
    PromotedFieldsEnabled = dec:bit()
    NetworkMessageType = dec:bit(3)
    dec:bit(3)
  end

  if PublisherIdEnabled == 1 then
    msg.PublisherId = decodePublisherId(dec, PublisherIdType)
    msg.PublisherIdType = PublisherIdType
  end

  if DataSetClassIdEnabled == 1 then
    msg.DataSetClassId = dec:guid()
  end

  if GroupHeaderEnabled == 1 then
    msg.GroupHeader = decodeGroupHeader(dec)
  end

  -- PayloadHeader
  local dataSetWriterIDs = {}
  if PayloadHeaderEnabled == 1 then
    if NetworkMessageType == 0 then
      -- https://reference.opcfoundation.org/Core/Part14/v104/docs/7.2.2.3.2
      local messageCount = dec:uint8()
      for i=1,messageCount do
        dataSetWriterIDs[i] = dec:uint16()
      end
    end
  end

  -- ExtendedNetworkMessageHeader
  if TimestampEnabled == 1 then
    msg.Timestamp = dec:dateTime()
  end

  if PicoSecondsEnabled == 1 then
    msg.PicoSeconds = dec:uint16()
  end

  if PromotedFieldsEnabled == 1 then
    -- https://reference.opcfoundation.org/Core/Part14/v105/docs/6.2.3.2.4
    local PromotedFiledsDataSize = dec:uint16()
    -- local fieldsData = dec:array(PromotedFiledsDataSize)
    dec:array(PromotedFiledsDataSize)
    local PromotedFields = {}
    -- for i=1,PromotedFieldCount do
    --   local PromotedField = {}
    --   PromotedField.FieldIndex = dec:uint16()
    --   PromotedField.FieldValue = dec:variant()
    --   PromotedFields[i] = PromotedField
    -- end
    msg.PromotedFields = PromotedFields
  end

  if SecurityHeaderEnabled == 1 then
    msg.SecurityHeader = decodeSecurityHeader(dec)
  end

  -- Payload

  -- DataSetMessage
  if NetworkMessageType == DATA_SET_MESSAGGE then
    msg.Messages = decodeDataSetMessages(dec, dataSetWriterIDs)
  -- Discovery Announcement
  elseif NetworkMessageType == DISCOVERY_ANNOUNCEMENT then
    msg.DiscoveryAnouncement = decodeDiscoveryAnouncement(dec)
  else
    return error("Unsupported msg.NetworkMessageType " .. tostring(NetworkMessageType))
  end

  -- SecurityFooter
  -- Signature

  return msg
end

-- Format: https://reference.opcfoundation.org/Core/Part14/v105/docs/7.2.4.4
local function encodeMessage(enc, msg)
  -- Byte 1 Version/Flags
  if enc.bit == nil then
    error("Invalid decoder")
  end

  local UADPVersion = 1
  local PublisherIdEnabled = msg.PublisherId ~= nil
  local PublisherIdType = 0
  if PublisherIdEnabled then
    PublisherIdType = msg.PublisherIdType or getPublisherType(msg.PublisherId)
  end

  local GroupHeaderEnabled = msg.GroupHeader ~= nil

  -- mgs.PayloadHeaderEnabled can be set to need to force encoding array of DataSetWriterId and message sizes
  local PayloadHeaderEnabled = (msg.PayloadHeaderEnabled ~= nil and msg.PayloadHeaderEnabled) or (msg.Messages ~= nil and #msg.Messages > 0 and msg.Messages[1].DataSetWriterId ~= nil)

  local DataSetClassIdEnabled = msg.DataSetClassId ~= nil
  local SecurityHeaderEnabled = msg.SecurityHeader ~= nil
  local TimestampEnabled = msg.Timestamp ~= nil
  local PicoSecondsEnabled = msg.PicoSeconds ~= nil

  local ChunksEnabled = false -- TODO
  local PromotedFieldsEnabled = msg.PromotedFields ~= nil

  local NetworkMessageType
  if msg.Messages ~= nil then
    NetworkMessageType = DATA_SET_MESSAGGE
  elseif msg.DiscoveryAnouncement then
    NetworkMessageType = DISCOVERY_ANNOUNCEMENT
  else
    error("Unsupported network message")
  end

  local ExtendedFlags2Enabled = ChunksEnabled or PromotedFieldsEnabled or NetworkMessageType ~= 0

  local ExtendedFlags1Enabled = PublisherIdType > 0 or
    DataSetClassIdEnabled or SecurityHeaderEnabled or
    TimestampEnabled or PicoSecondsEnabled or ExtendedFlags2Enabled


  -- Byte 1 Version/Flags
  enc:bit(UADPVersion, 4)
  enc:bit(PublisherIdEnabled)
  enc:bit(GroupHeaderEnabled)
  enc:bit(PayloadHeaderEnabled)
  enc:bit(ExtendedFlags1Enabled)

  -- Byte 3 ExtendedFlags2
  if ExtendedFlags1Enabled then
    enc:bit(PublisherIdType, 3)
    enc:bit(DataSetClassIdEnabled)
    enc:bit(SecurityHeaderEnabled)
    enc:bit(TimestampEnabled)
    enc:bit(PicoSecondsEnabled)
    enc:bit(ExtendedFlags2Enabled)
  end

  if ExtendedFlags2Enabled then
    enc:bit(ChunksEnabled)
    enc:bit(PromotedFieldsEnabled)
    enc:bit(NetworkMessageType, 3)
    enc:bit(0, 3)
  end

  if PublisherIdEnabled then
    encodePublisherId(enc, msg.PublisherId, PublisherIdType)
  end

  if DataSetClassIdEnabled then
    enc:guid(msg.DataSetClassId)
  end

  if GroupHeaderEnabled then
    encodeGroupHeader(enc, msg.GroupHeader)
  end

  -- PayloadHeader
  if PayloadHeaderEnabled then
    if NetworkMessageType == 0 then
      -- https://reference.opcfoundation.org/Core/Part14/v104/docs/7.2.2.3.2
      local messageCount = #msg.Messages
      enc:uint8(messageCount)
      for i=1,messageCount do
        enc:uint16(msg.Messages[i].DataSetWriterId)
      end
    end
  end

  -- ExtendedNetworkMessageHeader
  if TimestampEnabled then
    enc:dateTime(msg.Timestamp)
  end

  if PicoSecondsEnabled then
    enc:uint16(msg.PicoSeconds)
  end

  if PromotedFieldsEnabled then
    -- https://reference.opcfoundation.org/Core/Part14/v105/docs/6.2.3.2.4
    local PromotedFiledsDataSize = enc:uint16()
    -- local fieldsData = enc:array(PromotedFiledsDataSize)
    enc:array(PromotedFiledsDataSize)
    local PromotedFields = {}
    -- for i=1,PromotedFieldCount do
    --   local PromotedField = {}
    --   PromotedField.FieldIndex = enc:uint16()
    --   PromotedField.FieldValue = enc:variant()
    --   PromotedFields[i] = PromotedField
    -- end
    msg.PromotedFields = PromotedFields
  end

  if SecurityHeaderEnabled then
    encodeSecurityHeader(enc, msg.SecurityHeader)
  end

  -- Payload

  if NetworkMessageType == DATA_SET_MESSAGGE then
    encodeDataSetMessages(enc, msg.Messages, PayloadHeaderEnabled)
  elseif NetworkMessageType == DISCOVERY_ANNOUNCEMENT then
    encodeDiscoveryAnouncement(enc, msg.DiscoveryAnouncement)
  else
    error("Unsupported msg.NetworkMessageType " .. tostring(msg.NetworkMessageType))
  end

  -- SecurityFooter
  -- Signature
end


return {
  decode = decodeMessage,
  encode = encodeMessage,

  -- Network messages
  messageType = {
    DATA_SET_MESSAGGE = DATA_SET_MESSAGGE,
    DISCOVERY_PROBE = DISCOVERY_PROBE,
    DISCOVERY_ANNOUNCEMENT = DISCOVERY_ANNOUNCEMENT
  },

  -- Dataset message types
  dataSetMessageType = {
    DATA_KEY_FRAME = DATA_KEY_FRAME,
    DELTA_DATA_FRAME = DELTA_DATA_FRAME,
    EVENT = EVENT,
    KEEP_ALIVE = KEEP_ALIVE
  },

  -- PublisherId types
  publisherIdType = {
    UINT8 = PUBLISHER_TYPE_UINT8,
    UINT16 = PUBLISHER_TYPE_UINT16,
    UINT32 = PUBLISHER_TYPE_UINT32,
    UINT64 = PUBLISHER_TYPE_UINT64,
    STRING = PUBLISHER_TYPE_STRING
  },

  -- Field encoding in dataset messages
  fieldEncoding = {
    VARIANT = FIELD_ENCODING_VARIANT,
    RAW_DATA = FIELD_ENCODING_RAW_DATA,
    DATA_VALUE = FIELD_ENCODING_DATA_VALUE,
    KEEP_ALIVE = FIELD_ENCODING_KEEP_ALIVE
  },

  announcementType = {
    PUBLISHER_ENDPOINTS = PUBLISHER_ENDPOINTS,
    DATASET_METADATA = DATASET_METADATA,
    DATASET_WRITER_CONF = DATASET_WRITER_CONF,
    PUBSUB_CONNECTION = PUBSUB_CONNECTION,
    APPLICATION_INFO = APPLICATION_INFO
  }
}
