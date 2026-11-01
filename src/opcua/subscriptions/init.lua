-- Compact data-change subscription engine.  One instance and one timer serve
-- the whole server; node writes are fanned out through the services hook list.
local compat = require("opcua.compat")
local const = require("opcua.const")
local status = require("opcua.status_codes")
local tools = require("opcua.tools")

local Good = status.Good
local Mode = const.MonitoringMode
local Trigger = const.DataChangeTrigger
local Deadband = const.DeadbandType
local Attr = const.AttributeId
local InfoTypeDataValue = 0x400
local Overflow = 0x080

local M = {}
M.__index = M

local function clamp(v, lo, hi)
  v = tonumber(v) or lo
  if v < lo then
    return lo
  end
  if v > hi then
    return hi
  end
  return v
end

local function same(a, b)
  if type(a) ~= type(b) then
    return false
  end
  if type(a) ~= "table" then
    return a == b
  end
  for k, v in pairs(a) do
    if not same(v, b[k]) then
      return false
    end
  end
  for k in pairs(b) do
    if a[k] == nil then
      return false
    end
  end
  return true
end

local function changed(item, value)
  local old = item.last
  if old == nil then
    return true
  end
  local trigger = item.trigger
  if old.StatusCode ~= value.StatusCode then
    return true
  end
  if trigger == Trigger.Status then
    return false
  end

  local a, b = old.Value, value.Value
  if item.deadband and item.deadband > 0 and type(a) == "number" and type(b) == "number" then
    if math.abs(a - b) > item.deadband then
      return true
    end
  elseif not same(a, b) then
    return true
  end
  return trigger == Trigger.StatusValueTimestamp and
    old.SourceTimestamp ~= value.SourceTimestamp
end

local function timestamps(value, mode)
  value = tools.copy(value)
  if mode == const.TimestampsToReturn.Source then
    value.ServerTimestamp, value.ServerPicoseconds = nil, nil
  elseif mode == const.TimestampsToReturn.Server then
    value.SourceTimestamp, value.SourcePicoseconds = nil, nil
  elseif mode == const.TimestampsToReturn.Neither then
    value.SourceTimestamp, value.SourcePicoseconds = nil, nil
    value.ServerTimestamp, value.ServerPicoseconds = nil, nil
  end
  return value
end

local function available(sub)
  local result = {}
  for i = 1, #sub.retransmitOrder do
    result[i] = sub.retransmitOrder[i]
  end
  return result
end

local function createResult(code)
  return {StatusCode = code, MonitoredItemId = 0, RevisedSamplingInterval = 0,
    RevisedQueueSize = 0, FilterResult = {TypeId = "i=0"}}
end

local function modifyResult(code)
  return {StatusCode = code, RevisedSamplingInterval = 0, RevisedQueueSize = 0,
    FilterResult = {TypeId = "i=0"}}
end

function M.new(services, config)
  local c = config.subscriptions or {}
  local manager = {
    services = services,
    subscriptions = {},
    watched = {},
    nextSubscriptionId = 1,
    nextMonitoredItemId = 1,
    minPublishingInterval = c.minPublishingInterval or 50,
    maxPublishingInterval = c.maxPublishingInterval or 3600000,
    minSamplingInterval = c.minSamplingInterval or 10,
    maxSubscriptionsPerSession = c.maxSubscriptionsPerSession or 2,
    maxMonitoredItemsPerSubscription = c.maxMonitoredItemsPerSubscription or 16,
    maxPublishRequestsPerSession = c.maxPublishRequestsPerSession or 2,
    maxQueueSize = c.maxQueueSize or 8,
    maxRetransmitQueueSize = c.maxRetransmitQueueSize or 8,
    tickInterval = c.tickInterval or 20,
  }

  return setmetatable(manager, M)
end

function M:start()
  if self.timer then
    return
  end
  self.timer = compat.timer(function() self:tick(); return true end)
  self.timer:set(self.tickInterval)
end

function M:shutdown()
  if self.timer then
    self.timer:cancel()
    self.timer = nil
  end
  for nodeId, watch in pairs(self.watched) do
    self.services:removeWriteHook(nodeId, watch.hook)
  end
  self.watched, self.subscriptions = {}, {}
end

function M:revise(req, sub)
  local interval = clamp(req.RequestedPublishingInterval,
    self.minPublishingInterval, self.maxPublishingInterval)
  local keepAlive = math.max(1, math.floor(req.RequestedMaxKeepAliveCount or 1))
  local lifetime = math.max(3 * keepAlive,
    math.floor(req.RequestedLifetimeCount or (3 * keepAlive)))
  sub.interval, sub.keepAlive, sub.lifetime = interval, keepAlive, lifetime
  sub.maxNotifications = math.max(0, math.floor(req.MaxNotificationsPerPublish or 0))
  sub.priority = req.Priority or sub.priority or 0
end

function M:createSubscription(session, req)
  if session.subscriptionCount >= self.maxSubscriptionsPerSession then
    error(status.BadTooManySubscriptions)
  end
  local id = self.nextSubscriptionId
  self.nextSubscriptionId = id + 1
  local now = compat.timestamp()
  local sub = {
    id = id, session = session, enabled = req.PublishingEnabled ~= false,
    items = {}, itemCount = 0, sequence = 1, retransmit = {}, retransmitOrder = {},
    nextPublish = now, keepAliveCounter = 0, lifetimeCounter = 0,
  }
  self:revise(req, sub)
  self.subscriptions[id], session.subscriptions[id] = sub, true
  session.subscriptionCount = session.subscriptionCount + 1
  return {
    SubscriptionId = id, RevisedPublishingInterval = sub.interval,
    RevisedLifetimeCount = sub.lifetime, RevisedMaxKeepAliveCount = sub.keepAlive,
  }
end

function M:get(session, id)
  local sub = self.subscriptions[id]
  if not sub or sub.session ~= session then
    error(status.BadSubscriptionIdInvalid)
  end
  return sub
end

function M:modifySubscription(session, req)
  local sub = self:get(session, req.SubscriptionId)
  self:revise(req, sub)
  sub.nextPublish = compat.timestamp() + sub.interval / 1000
  return {RevisedPublishingInterval = sub.interval,
    RevisedLifetimeCount = sub.lifetime, RevisedMaxKeepAliveCount = sub.keepAlive}
end

function M:unwatch(item)
  local watch = self.watched[item.nodeId]
  if not watch then
    return
  end
  watch.items[item] = nil
  if next(watch.items) == nil then
    self.services:removeWriteHook(item.nodeId, watch.hook)
    self.watched[item.nodeId] = nil
  end
end

function M:deleteSubscription(sub, code)
  self.subscriptions[sub.id] = nil
  sub.session.subscriptions[sub.id] = nil
  sub.session.subscriptionCount = math.max(0, sub.session.subscriptionCount - 1)
  for _, item in pairs(sub.items) do
    self:unwatch(item)
  end
  if code and sub.session.publishRequests[1] then
    local p = table.remove(sub.session.publishRequests, 1)
    p.respond(nil, code)
  end
end

function M:deleteSubscriptions(session, ids)
  local result = {}
  for i, id in ipairs(ids or {}) do
    local sub = self.subscriptions[id]
    if sub and sub.session == session then
      self:deleteSubscription(sub)
      result[i] = Good
    else
      result[i] = status.BadSubscriptionIdInvalid
    end
  end
  return {Results = result}
end

function M:deleteSession(session)
  local list = {}
  for id in pairs(session.subscriptions) do
    list[#list + 1] = id
  end
  for _, id in ipairs(list) do
    self:deleteSubscription(self.subscriptions[id])
  end
  for _, p in ipairs(session.publishRequests) do
    p.respond(nil, status.BadSessionClosed)
  end
  session.publishRequests = {}
end

function M:setPublishingMode(session, req)
  local result = {}
  for i, id in ipairs(req.SubscriptionIds or {}) do
    local sub = self.subscriptions[id]
    if sub and sub.session == session then
      sub.enabled = req.PublishingEnabled
      result[i] = Good
    else
      result[i] = status.BadSubscriptionIdInvalid
    end
  end
  return {Results = result}
end

function M.filter(params)
  local f = params.Filter
  if not f.Body then
    return Trigger.StatusValue, nil
  end
  -- DataChangeFilter encoding id is i=724 (some internal callers use i=722).
  if f.TypeId ~= "i=724" and f.TypeId ~= "i=722" then
    return nil, status.BadMonitoredItemFilterUnsupported
  end
  local b = f.Body
  if b.DeadbandType == Deadband.Percent then
    return nil, status.BadMonitoredItemFilterUnsupported
  end
  if b.DeadbandType ~= Deadband.None and b.DeadbandType ~= Deadband.Absolute then
    return nil, status.BadDeadbandFilterInvalid
  end
  return b.Trigger,
    b.DeadbandType == Deadband.Absolute and b.DeadbandValue or nil
end

function M.queue(item, value)
  value = timestamps(value, item.timestamps)
  value.StatusCode = value.StatusCode or Good
  if not changed(item, value) then
    return
  end
  item.last = tools.copy(value)
  local q = item.queue
  if #q >= item.queueSize then
    if item.discardOldest then
      table.remove(q, 1)
      value.StatusCode = value.StatusCode | InfoTypeDataValue | Overflow
    else
      q[#q].StatusCode = (q[#q].StatusCode or Good) | InfoTypeDataValue | Overflow
      return
    end
  end
  q[#q + 1] = value
end

function M:sample(item)
  local ok, value = pcall(self.services.readValue, self.services, item.node)
  if not ok then
    value = {StatusCode = type(value) == "number" and value or status.BadInternalError}
  end
  M.queue(item, value)
end

function M:onWrite(nodeId, attributeId, value)
  local watch = self.watched[nodeId]
  local now = compat.timestamp()
  for item in pairs(watch.items) do
    if item.mode ~= Mode.Disabled and item.attributeId == attributeId then
      if item.sampling <= 0 or now >= item.nextSample then
        M.queue(item, value)
        item.nextSample = now + item.sampling / 1000
      else
        item.pending = tools.copy(value)
      end
    end
  end
end

function M:addWatch(item)
  local watch = self.watched[item.nodeId]
  if not watch then
    watch = {items = {}}
    watch.hook = self.services:addWriteHook(item.nodeId,
      function(nodeId, attributeId, value) self:onWrite(nodeId, attributeId, value) end)
    self.watched[item.nodeId] = watch
  end
  watch.items[item] = true
end

local function validMode(mode)
  return mode == Mode.Disabled or mode == Mode.Sampling or mode == Mode.Reporting
end

function M:createMonitoredItem(sub, req, timestampsToReturn)
  local node = req.ItemToMonitor
  local params = req.RequestedParameters
  if not validMode(req.MonitoringMode) then
    return createResult(status.BadMonitoringModeInvalid)
  end
  if not self.services.nodeset[node.NodeId] then
    return createResult(status.BadNodeIdUnknown)
  end
  if node.AttributeId ~= Attr.Value then
    return createResult(status.BadAttributeIdInvalid)
  end
  if node.IndexRange and node.IndexRange ~= "" then
    return createResult(status.BadIndexRangeInvalid)
  end
  if node.DataEncoding and node.DataEncoding.Name and node.DataEncoding.Name ~= "" then
    return createResult(status.BadDataEncodingUnsupported)
  end
  local trigger, deadband = M.filter(params)
  if not trigger then
    return createResult(deadband)
  end
  local id = self.nextMonitoredItemId
  self.nextMonitoredItemId = id + 1
  local sampling = params.SamplingInterval
  if sampling < 0 then
    sampling = sub.interval
  end
  if sampling > 0 then
    sampling = math.max(sampling, self.minSamplingInterval)
  end
  local queueSize = clamp(math.floor(params.QueueSize), 1, self.maxQueueSize)
  local item = {
    id = id, node = node, nodeId = node.NodeId, attributeId = node.AttributeId,
    clientHandle = params.ClientHandle, mode = req.MonitoringMode,
    sampling = sampling, queueSize = queueSize, discardOldest = params.DiscardOldest,
    queue = {}, nextSample = compat.timestamp(), timestamps = timestampsToReturn,
    trigger = trigger, deadband = deadband,
  }
  sub.items[id], sub.itemCount = item, sub.itemCount + 1
  self:addWatch(item)
  if item.mode ~= Mode.Disabled then
    self:sample(item)
  end
  return {StatusCode = Good, MonitoredItemId = id,
    RevisedSamplingInterval = sampling, RevisedQueueSize = queueSize,
    FilterResult = {TypeId = "i=0"}}
end

function M:createMonitoredItems(session, req)
  local sub = self:get(session, req.SubscriptionId)
  if req.TimestampsToReturn < 0 or req.TimestampsToReturn > 3 then
    error(status.BadTimestampsToReturnInvalid)
  end
  local result = {}
  for i, item in ipairs(req.ItemsToCreate or {}) do
    if sub.itemCount >= self.maxMonitoredItemsPerSubscription then
      result[i] = createResult(status.BadTooManyMonitoredItems)
    else
      result[i] = self:createMonitoredItem(sub, item, req.TimestampsToReturn)
    end
  end
  return {Results = result}
end

function M:modifyMonitoredItems(session, req)
  local sub = self:get(session, req.SubscriptionId)
  if req.TimestampsToReturn < 0 or req.TimestampsToReturn > 3 then
    error(status.BadTimestampsToReturnInvalid)
  end
  local result = {}
  for i, change in ipairs(req.ItemsToModify or {}) do
    local item = sub.items[change.MonitoredItemId]
    local params = change.RequestedParameters
    if not item then
      result[i] = modifyResult(status.BadMonitoredItemIdInvalid)
    else
      local trigger, deadband = M.filter(params)
      if not trigger then
        result[i] = modifyResult(deadband)
      else
        local sampling = params.SamplingInterval
        if sampling < 0 then
          sampling = sub.interval
        end
        if sampling > 0 then
          sampling = math.max(sampling, self.minSamplingInterval)
        end
        local size = clamp(math.floor(params.QueueSize), 1, self.maxQueueSize)
        while #item.queue > size do
          table.remove(item.queue, item.discardOldest and 1 or #item.queue)
        end
        item.sampling, item.queueSize, item.discardOldest =
          sampling, size, params.DiscardOldest
        item.clientHandle, item.timestamps =
          params.ClientHandle, req.TimestampsToReturn
        item.trigger, item.deadband = trigger, deadband
        result[i] = {StatusCode = Good, RevisedSamplingInterval = sampling,
          RevisedQueueSize = size, FilterResult = {TypeId = "i=0"}}
      end
    end
  end
  return {Results = result}
end

function M:setMonitoringMode(session, req)
  local sub = self:get(session, req.SubscriptionId)
  if not validMode(req.MonitoringMode) then
    error(status.BadMonitoringModeInvalid)
  end
  local result = {}
  for i, id in ipairs(req.MonitoredItemIds or {}) do
    local item = sub.items[id]
    if not item then
      result[i] = status.BadMonitoredItemIdInvalid
    else
      local old = item.mode
      item.mode = req.MonitoringMode
      result[i] = Good
      if item.mode == Mode.Disabled then
        item.queue, item.pending = {}, nil
      elseif old == Mode.Disabled then
        item.last = nil
        self:sample(item)
      end
    end
  end
  return {Results = result}
end

function M:deleteMonitoredItems(session, req)
  local sub = self:get(session, req.SubscriptionId)
  local result = {}
  for i, id in ipairs(req.MonitoredItemIds or {}) do
    local item = sub.items[id]
    if item then
      self:unwatch(item)
      sub.items[id] = nil
      sub.itemCount = sub.itemCount-1
      result[i] = Good
    else
      result[i] = status.BadMonitoredItemIdInvalid
    end
  end
  return {Results = result}
end

function M:notification(sub, now)
  local out, limit = {}, sub.maxNotifications
  if limit == 0 then
    limit = math.huge
  end
  for _, item in pairs(sub.items) do
    if item.mode == Mode.Reporting then
      while item.queue[1] and #out < limit do
        out[#out+1] = {ClientHandle = item.clientHandle, Value = table.remove(item.queue, 1)}
      end
    end
    if #out >= limit then
      break
    end
  end
  if #out == 0 then
    return
  end
  local sequence = sub.sequence
  sub.sequence = sequence == 0xFFFFFFFF and 1 or sequence + 1
  local message = {SequenceNumber = sequence, PublishTime = now, NotificationData = {{
    TypeId = "i=811", Body = {MonitoredItems = out, DiagnosticInfos = {}}
  }}}
  sub.retransmit[sequence] = tools.copy(message)
  sub.retransmitOrder[#sub.retransmitOrder+1] = sequence
  if #sub.retransmitOrder > self.maxRetransmitQueueSize then
    sub.retransmit[table.remove(sub.retransmitOrder, 1)] = nil
  end
  return message
end

function M.hasNotifications(sub)
  for _, item in pairs(sub.items) do
    if item.mode == Mode.Reporting and item.queue[1] then
      return true
    end
  end
  return false
end

function M:respond(sub, publish, now, keepAlive)
  local message
  if keepAlive then
    message = {SequenceNumber = sub.sequence, PublishTime = now, NotificationData = {}}
  else
    message = self:notification(sub, now)
  end
  publish.respond({SubscriptionId = sub.id, AvailableSequenceNumbers = available(sub),
    MoreNotifications = M.hasNotifications(sub), NotificationMessage = message,
    Results = publish.results, DiagnosticInfos = {}})
end

function M:publish(session, req, respond, channel)
  if session.subscriptionCount == 0 then
    error(status.BadNoSubscription)
  end
  if #session.publishRequests >= self.maxPublishRequestsPerSession then
    error(status.BadTooManyPublishRequests)
  end
  local results = {}
  for i, ack in ipairs(req.SubscriptionAcknowledgements or {}) do
    local sub = self.subscriptions[ack.SubscriptionId]
    if not sub or sub.session ~= session then
      results[i] = status.BadSubscriptionIdInvalid
    elseif not sub.retransmit[ack.SequenceNumber] then
      results[i] = status.BadSequenceNumberUnknown
    else
      sub.retransmit[ack.SequenceNumber] = nil
      for n, v in ipairs(sub.retransmitOrder) do
        if v == ack.SequenceNumber then
          table.remove(sub.retransmitOrder, n)
          break
        end
      end
      results[i] = Good
    end
  end
  local timeout = (req.RequestHeader and req.RequestHeader.TimeoutHint or 0)/1000
  session.publishRequests[#session.publishRequests+1] = {respond = respond, results = results, channel = channel,
    deadline = timeout>0 and compat.timestamp()+timeout or nil}
  self:tick()
end

function M:cancelChannel(channel)
  for _, sub in pairs(self.subscriptions) do
    local q = sub.session.publishRequests
    local i = 1
    while q[i] do
      if q[i].channel == channel then
        table.remove(q, i)
      else
        i = i+1
      end
    end
  end
end

function M:republish(session, req)
  local sub = self:get(session, req.SubscriptionId)
  local msg = sub.retransmit[req.RetransmitSequenceNumber]
  if not msg then
    error(status.BadMessageNotAvailable)
  end
  return {NotificationMessage = tools.copy(msg)}
end

function M:tick(now)
  now = now or compat.timestamp()
  for _, sub in pairs(self.subscriptions) do
    for _, item in pairs(sub.items) do
      if item.mode ~= Mode.Disabled and now >= item.nextSample then
        if item.pending then
          M.queue(item, item.pending)
          item.pending = nil
        elseif self.services.nodeset[item.nodeId].Attrs.NodeCallback then
          self:sample(item)
        end
        item.nextSample = now+item.sampling/1000
      end
    end
  end
  -- Expire timed-out Publish requests before assigning publishing cycles.
  local sessions = {}
  for _, sub in pairs(self.subscriptions) do
    sessions[sub.session] = true
  end
  for session in pairs(sessions) do
    local q = session.publishRequests
    local i = 1
    while q[i] do
      if q[i].deadline and now>=q[i].deadline then
        local p = table.remove(q, i)
        p.respond(nil, status.BadTimeout)
      else
        i = i+1
      end
    end
  end
  local expired = {}
  for _, sub in pairs(self.subscriptions) do
    if now >= sub.nextPublish then
      sub.nextPublish = now+sub.interval/1000
      local q = sub.session.publishRequests
      if q[1] then
        sub.lifetimeCounter = 0
        if sub.enabled and M.hasNotifications(sub) then
          sub.keepAliveCounter = 0; self:respond(sub, table.remove(q, 1), now, false)
        else
          sub.keepAliveCounter = sub.keepAliveCounter+1
          if sub.keepAliveCounter>=sub.keepAlive then
            sub.keepAliveCounter = 0; self:respond(sub, table.remove(q, 1), now, true)
          end
        end
      else
        sub.lifetimeCounter = sub.lifetimeCounter+1
        if sub.lifetimeCounter>=sub.lifetime then
          expired[#expired+1] = sub
        end
      end
    end
  end
  for _, sub in ipairs(expired) do
    self:deleteSubscription(sub, status.BadTimeout)
  end
end

return M
