local tools = require("opcua.tools")
local const = require("opcua.const")
local trace = require("opcua.trace")
local StatusCode = require("opcua.status_codes")
local uadp = require("opcua.pubsub.uadp")
local json = require("opcua.pubsub.json")

local q = require("opcua.binary.queue")

local traceI = trace.inf
local traceE = trace.err
local traceD = trace.dbg
local fmt = string.format
local TranportProfileUri = const.TranportProfileUri

local MqttJson = TranportProfileUri.MqttJson
local MqttBinary = TranportProfileUri.MqttBinary
local BadDataEncodingUnsupported = StatusCode.BadDataEncodingUnsupported

local C = {}
C.__index = C

function C:decodeJson(payload)
  local decoder = self.model:createJsonDecoder(q.new(payload))
  local msg, err = json.decode(decoder)
  if err ~= nil then
    traceE(fmt("mqtt | Failed to decode JSON payload: %s", err))
  end

  return msg, err
end

function C:decodeBinary(payload)
  local decoder = self.model:createBinaryDecoder(q.new(payload))

  local msg, err = uadp.decode(decoder)
  if err then
    traceE(fmt("mqtt | Failed to decode binary payload: %s", err))
    return nil, err
  end

  return msg
end

function C:onstatus(callback, type, code,status)
  local infOn = self.config.logging.services.infOn

  if infOn then
    traceI(fmt("mqtt | status changed: type '%s', code '%s'", type, code))
  end

  if type == "mqtt" and code == "connect" and status.reasoncode == 0 then
    if infOn then
      traceI(fmt("mqtt | Successful connection ServerProperties='%s'", ba.json.encode(status.properties)))
    end

    if callback then
      callback()
    end

    if infOn then
      traceI(fmt("mqtt | connected"))
    end

    return true -- Accept connection
  end

  if infOn then
    traceI(fmt("mqtt | disconnected"))
  end

  if callback then
    callback(StatusCode.BadDisconnect)
  end

  return false -- Deny reconnect
end

function C:subscribe(topic, messageCallback)
  local infOn = self.config.logging.services.infOn
  if infOn then traceI(fmt("mqtt | Subscribing to MQTT topic='%s'", topic)) end

  local onpublish = function(...)
    return self:onData(messageCallback, ...)
  end

  self.server:subscribe(topic, {onpub=onpublish})
end

local brCh <const> = string.byte('{')

function C:onData(messageCallback, topic, payload, properties)
  local dbgOn = self.config.logging.binary.dbgOn
  if (dbgOn) then
    traceD(fmt("mqtt | Received: topic='%s' properties='%s' payload:", topic, ba.json.encode(properties)))
    tools.hexPrint(payload, traceD)
  end

  local tranportProfileUri = self.tranportProfileUri
  if tranportProfileUri == nil then
    if payload[1] & 0x0f == 1 then
      tranportProfileUri = MqttBinary
    elseif payload[1] == brCh then
      tranportProfileUri = MqttJson
    end
  end

  local msg
  local err
  if tranportProfileUri == MqttJson then
    msg, err = self:decodeJson(payload)
  elseif tranportProfileUri == MqttBinary then
    msg, err = self:decodeBinary(payload)
  else
    err = BadDataEncodingUnsupported
  end

  messageCallback(msg, err)
end

function C:connect(endpointUrl, tranportProfileUri, connectCallback, mqttc)
  local dbgOn = self.config.logging.binary.dbgOn
  if (dbgOn) then traceD(fmt("mqtt | Connecting to '%s'", endpointUrl)) end

  if type(tranportProfileUri) ~= "string" then
    connectCallback = tranportProfileUri
    tranportProfileUri = nil
  end

  self.tranportProfileUri =  tranportProfileUri

  local onstatus = function(...)
    return self:onstatus(connectCallback, ...)
  end

  if not mqttc then
    mqttc = require("mqttc")
  end
  local url = tools.parseUrl(endpointUrl)
  self.server = mqttc.create(url.host, onstatus, {port=url.port})
end

function C:createPublisher()
  if self.publisher then
    return
  end

  local publisher = {
    dataSets = {},
    fields = {}, -- all fields
  }

  self.publisher = publisher
end

function C:createDataset(fields, classId)
  local infOn = self.config.logging.services.infOn
  local dbgOn = self.config.logging.services.dbgOn
  if infOn then
    traceI(fmt("mqtt | Creating dataset with classId='%s'", classId))
  end

  self:createPublisher()

  classId = classId or tools.createGuid()
  local dataSet = {
    classId = classId,
    nodeIds = {},
    indexes = {},
    names = {}
  }

  local writeHook = function(nodeId, --[[attributeId]]_, value)
    if dbgOn then
      traceD(fmt("mqtt | new node value '%s': %s", nodeId, ba.json.encode(value)))
    end
    self:setValue(classId, nodeId, value)
  end

  for i, f in ipairs(fields) do
    if not f.name and not f.nodeId then
      error("Field name and nodeId are required")
    end

    local field = {
      index = i,
      nodeId = f.nodeId,
      name = f.name,
      fieldId = tools.createGuid(),
    }

    if f.name then
      assert(dataSet.names[f.name] == nil, "Duplicated field name '"..field.name.."'")
      dataSet.names[f.name] = field
    end

    if f.nodeId then
      assert(dataSet.nodeIds[f.nodeId] == nil, "Duplicated field nodeId '"..field.nodeId.."'")
      dataSet.nodeIds[f.nodeId] = field
    end

    dataSet.indexes[i] = field

    if field.nodeId and self.uaServer then
      self.uaServer:setWriteHook(field.nodeId, writeHook)
    end
  end

  self.publisher.dataSets[dataSet.classId] = dataSet
  return dataSet.classId
end

function C:setValue(classId, id, value)
  local dataset = self.publisher.dataSets[classId]
  if dataset == nil then
    error("invalid dataset Id")
  end

  local field = dataset.names[id] or dataset.nodeIds[id] or dataset.indexes[id]
  if field == nil then
    error("invalid value ID")
  end

  field.value = value
end

function C:publish(topic, publisherId)
  assert(type(topic) == 'string', "invalid topic")
  assert(publisherId ~= nil or type(publisherId) == 'string' or type(publisherId) == 'number', "invalid publisherId")

  local infOn = self.config.logging.services.infOn
  local dbgOn = self.config.logging.services.dbgOn

  if infOn then
    traceI("mqtt | sending message")
  end

  local msg = {
    PublisherId = publisherId or self.config.applicationName,
    MessageId = tools.createGuid()
  }

  local messages = {}
  for _, dataset in pairs(self.publisher.dataSets) do
    local message = {
      DataSetWriterId = 1,
      DataSetMessageType = uadp.dataSetMessageType.DELTA_DATA_FRAME
    }

    local payload = {}
    for _, field in pairs(dataset.indexes) do
      local value = field.value
      if value ~= nil then
        if self.tranportProfileUri == MqttBinary then
          table.insert(payload, {Index = field.index, Value=value})
        elseif self.tranportProfileUri == MqttJson then
          payload[field.name] = value
        end
      end
    end

      if self.tranportProfileUri == MqttBinary then
        message.Fields = payload
      else
        message.Payload = payload
      end

      table.insert(messages, message)
    end

  msg.Messages = messages

  local payload = q.new(self.config.bufSize)
  if self.tranportProfileUri == MqttBinary then
    local encoder = self.model:createBinaryEncoder(payload)
    uadp.encode(encoder, msg)
  else
    local encoder = self.model:createJsonEncoder(payload)
    json.encode(encoder, msg)
  end

  if dbgOn then
    traceD(fmt("mqtt | JSON payload: %s", tostring(payload)))
  end

  self.server:publish(topic, tostring(payload))
end

function C:startPublishing(topic, publisherId, timeout)
  assert(type(topic) == 'string', "invalid topic")
  assert(publisherId ~= nil, "invalid publisherId")
  assert(publisherId ~= nil or type(publisherId) == 'string' or type(publisherId) == 'number', "invalid publisherId")

  local infOn = self.config.logging.services.infOn
  local errOn = self.config.logging.services.errOn
  local dbgOn = self.config.logging.services.dbgOn

  if infOn then
    traceI(fmt("mqtt | Starting publishing to topic='%s' with publisherId='%s' with timeout='%s'", topic, publisherId, timeout))
  end

  self.publisher.timer = ba.timer(function()
    if dbgOn then
      traceD(fmt("mqtt | Publishing to topic='%s' with publisherId='%s'", topic, publisherId))
    end

    local ok, err = pcall(self.publish, self, topic, publisherId)
    if not ok and errOn then
        traceE(fmt("mqtt | Failed to publish: %s", err))
    end

    return true
  end)

  self.publisher.timer:set(timeout or 1000)
end

function C:stopPublishing()
  self.publisher.timer:cancel()
end

local function NewClient(config, uaServer)
  if config == nil then
    config = {
      bufSize = 1024
    }
  end

  local model
  if not uaServer or uaServer.model == nil then
    model = uaServer
    uaServer = nil
  else
    model = uaServer.model
  end

  local uaConfig = require("opcua.config")
  local err
  if uaServer then
    err = uaConfig.server(config)
  else
    err = uaConfig.client(config)
  end

  if err ~= nil then
    error("Configuration error: "..err)
  end

  if model == nil then
    model = require("opcua.model.import").getBaseModel(config)
  end

  local c = {
    config = config,
    uaServer = uaServer,
    model = model
  }

  setmetatable(c, C)
  return c
end

return {
  newClient=NewClient,
}
