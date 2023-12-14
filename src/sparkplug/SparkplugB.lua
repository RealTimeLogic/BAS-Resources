-- Sparkplug B client. Copyright Real Time Logic
local fmt,slower=string.format,string.lower
local tinsert,tpack=table.insert,table.pack
local PayloadNS <const> = ".org.eclipse.tahu.protobuf.Payload"

local pb=(function()
   local fp <close> = ba.openio"vm":open".lua/sparkplug_b.proto"
   local ok,pb = pcall(require,"pb")
   assert(ok, "\nThe lua protobuf C module is not included in the server")
   local ok,protoc = pcall(require,"protoc")
   assert(ok, "\nThe Lua module 'protoc' is not included in the server's resource file")
   assert(fp, "\nsparkplug_b.proto not found")
   assert(protoc:load(fp:read"*a"), "Cannot parse .lua/sparkplug_b.proto")
   return pb
end)()

local function timestamp()
   return ba.datetime"NOW":ticks()
end

--------------------------- Encode ------------------------

local DataTypes <const> = {
   int8 = 1,
   int16 = 2,
   int = 3,
   int32 = 3,
   int64 = 4,
   uint8 = 5,
   uint16 = 6,
   uint32 = 7,
   uint64 = 8,
   float = 9,
   double = 10,
   boolean = 11,
   string = 12,
   datetime = 13,
   text = 14,
   uuid = 15,
   dataset = 16,
   bytes = 17,
   file = 18,
   template = 19,
   propertyset	   = 20,
   propertysetlist = 21,
}


local RDataTypes <const> = {
   "int8",
   "int16",
   "int32",
   "int64",
   "uint8",
   "uint16",
   "uint32",
   "uint64",
   "float",
   "double",
   "boolean",
   "string",
   "datetime",
   "text",
   "uuid",
   "dataset",
   "bytes",
   "file",
   "template",
   "propertyset",
   "propertysetlist"
}


local DataTypeNames <const> = {
   "int_value", --Int8
   "int_value", --Int16
   "int_value", --Int32
   "long_value", --Int64
   "int_value", --UInt8
   "int_value", --UInt16
   "int_value", --UInt32
   "long_value", --UInt64
   "float_value", --Float
   "double_value", --Double
   "boolean_value", --Boolean
   "string_value", --String
   "long_value", --DateTime
   "string_value", --Text
   "string_value", --UUID
   "dataset_value", --DataSet
   "bytes_value", --Bytes
   "bytes_value", --File
   "template_value", --Template
   "propertyset_value",
   "propertysets_value",
}

local encMetrics,encPropertySet -- forward decl. functions


local function encPropVal(pT,level)
   if "table" ~= type(pT) then error("property value not a table",level) end
   local dt=DataTypes[slower(pT.type or "")]
   if not pT.value then error("Property missing value",level) end
   if not dt then error("Unknown Property type",level) end
   if DataTypes.propertyset==dt then
      encPropertySet(pT.value,level+1)
   elseif DataTypes.propertysetlist==dt then
      if "table" ~= type(pT.value) then error("PropertySetList not a table",level) end
      for _, p in ipairs(pT.value.propertyset) do encPropertySet(p,level+1) end
   end
   pT.type,pT[DataTypeNames[dt]]=dt,pT.value
   pT.value=nil
end

encPropertySet=function(prT,level)
   local values=prT.values
   if "table" ~= type(prT) then error("PropertySet not a table",level) end
   if "table" ~= type(prT.keys) then error("PropertySet.keys not a table",level) end
   if "table" ~= type(values) then error("PropertySet.values not a table",level) end
   if #prT.keys ~= #values then error("PropertySet #keys not equ #values",level) end
   for _,p in ipairs(values) do encPropVal(p,level+1) end
end

local function paramErr(msg,ix,name,level)
   error(fmt("parameter %s in template %s %s value",ix,name,msg),level+1)
end

local function encParameters(psT,name,level)
   if "table" ~= type(psT) then error(fmt("Template %s missing parameters",name),level) end
   for ix,pT in ipairs(psT) do
      local dt=DataTypes[slower(pT.type or "")]
      if not pT.value then paramErr("missing",ix,name,level) end
      if not dt then paramErr("unknown type",ix,name,level) end
      pT.type,pT[DataTypeNames[dt]]=dt,pT.value
      pT.value=nil
   end
   return psT
end


local function encTemplate(name,vT,level)
   if "table" ~= type(vT) then error(fmt("Template %s missing value",name),level) end
   vT.value=nil
   vT.is_definition = vT.isDefinition and true or false
   vT.isDefinition=nil
   if not vT.is_definition then
      if not vT.templateRef then error(fmt("Template ref. %s missing 'templateRef'",name or ""),level) end
      vT.template_ref=vT.templateRef
      vT.templateRef=nil
   end
   vT.parameters=encParameters(vT.parameters,name,level+1)
   vT.metrics=encMetrics(vT.metrics,name,level+1)
end

local function encDataset(name,vT,level)
local tt="table"
   if tt ~= type(vT) then error(fmt("Dataset %s not a table",name),level) end
   if tt ~= type(vT.columns) or tt ~= type(vT.types) or tt ~= type(vT.rows) then
      error(fmt("Dataset %s missing elements",name),level)
   end
   if #vT.columns ~= #vT.types then
      error(fmt("Dataset %s: different table lengths",name),level)
   end
   local types={}
   for ix,t in ipairs(vT.types) do
      local dt=DataTypes[slower(t)]
      if not dt then error(fmt("Dataset %s's type at index %d invalid",ix,name),level) end
      types[ix]=dt
   end
   vT.types=types
   local rows={}
   for rix,row in ipairs(vT.rows) do
      if tt ~= type(row) then error(fmt("Dataset %s's row at index %d invalid",name,rix),level) end
      if #vT.columns ~= #row then error(fmt("Invalid row len at %d in Dataset %s",rix,name),level) end
      local nrow={}
      for cix,v in ipairs(row) do
	 local dt=types[cix]
	 local c={}
	 c[DataTypeNames[dt]]=v
	 nrow[cix]=c
      end
      rows[rix]={elements=nrow}
   end
   vT.rows=rows
end

local function encMetricVal(dt,mT,level)
   local v=mT.value
   mT.value=nil
   local name=mT.name
   if not name then error("Metric missing name",level) end
   if nil == v then error(fmt("Metric %s missing value",name),level) end
   if DataTypes.template==dt then
      encTemplate(name,v,level+1)
   elseif DataTypes.dataset==dt then
      encDataset(name,v,level+1)
   end
   -- Transform val to protobuf compat val.
   mT.datatype,mT[DataTypeNames[dt]]=dt,v
   mT.type,mT.value=nil,nil
   return v
end

encMetrics=function(msT,name,level)
   if "table" ~= type(msT) then error(fmt("Table %s missing metrics",name),level) end
   for ix,mT in pairs(msT) do
      if "table" == type(mT) then
	 local dt=DataTypes[slower(mT.type or "")]
	 if not dt then error(fmt("Invalid metric type at index %d in table %s",ix,name),level) end
	 encMetricVal(dt,mT,level+1)
	 if mT.properties then encPropertySet(mT.properties,level+1) end
      end
   end
   return msT
end

local function encode(pl,level)
   pl.timestamp=pl.timestamp or timestamp()
   encMetrics(pl.metrics,"metrics",level and (level+1) or 4)
   local b,e=pb.encode(PayloadNS,pl)
   if not b or 0==#b then
      trace("PB enc warning:", err or "encoded payload len is zero\n",ba.json.encode(pl))
   end
   return b
end

--------------------------- Decode ------------------------

local decMetrics -- forward decl.

local function decPropertySet(psT)
   for _,p in ipairs(psT.values) do
      local v,dt=p.value,p.type
      p.value,p[v]=p[v],nil
      if DataTypes.propertyset==dt then
	 decPropertySet(p.value)
      elseif DataTypes.propertysetlist==dt then
	 for _, p in ipairs(p.value.propertyset) do decPropertySet(p) end
      end
      p.type = RDataTypes[dt]
   end
end

local function decTemplate(vT)
   vT.isDefinition,vT.is_definition=vT.is_definition,nil
   decMetrics(vT.metrics)
   if vT.parameters then
      for ix,p in ipairs(vT.parameters) do
	 p.type,p.value,p[p.value]=RDataTypes[p.type],p[p.value],nil
      end
   end
end
local function decDataset(dsT)
   for ix,dt in ipairs(dsT.types) do
      dsT.types[ix] = RDataTypes[dt]
   end
   local rows={}
   for rix,row in ipairs(dsT.rows) do
      for cix,v in ipairs(row.elements) do
	 v.value,v[v.value]=v[v.value],nil
      end
      rows[rix]=row.elements
   end
   dsT.rows=rows
end


decMetrics=function(msT)
   for _,m in ipairs(msT) do
      local v=m.value
      if v then m.value,m[v]=m[v],nil end
      local dt=m.datatype
      m.type,m.datatype=RDataTypes[dt],nil
      if DataTypes.template==dt then
	 decTemplate(m.value)
      elseif DataTypes.dataset==dt then
	 decDataset(m.value)
      end
      if m.properties then decPropertySet(m.properties) end
   end
end

------------------------------------------------------------------------
-- The Sparkplug protocol stack extends: https://realtimelogic.com/ba/doc/?url=MQTT.html
------------------------------------------------------------------------

local createMqtt -- func, forward decl.


local function cloneT(t)
   local nt={}
   for k,v in pairs(t) do
      nt[k] = "table" == type(v) and cloneT(v) or v
   end
   return nt
end

local function metric(name, type, value, alias, ts) -- Create metric
   assert(DataTypes[slower(type)], "param 2: unknown type")
   local m={name=name,type=type,value=value,alias=alias,timestamp=ts or timestamp()}
   if nil == value then m.is_null = true end
   return m
end


-- Add bdSeq metric to NBIRTH,NDEATH messages
local function bdSeqMetric(self)
   return metric("bdSeq","Int64",self._bdSeqNum)
end

-- Create the NDEATH (MQTT Will) message
local function spWill(self)
   return {
      topic=self._fmtNTopic"NDEATH",
      payload=encode({metrics={bdSeqMetric(self)}}),
      qos=1
   }
end

-- Add 'seq' to NBIRTH and NDATA
local function addSeq(self, pl)
   local seq=self._nextSeq
   pl.seq=seq
   seq=seq+1
   self._nextSeq = seq <= 255 and seq or 0
   return pl
end



local SP = {}
SP.__index = SP

-- Stops the Sparkplug client
function SP:stop()
   -- Implementation
   if self._running then
      self._running=false
      self._mqtt.sock:close()
      self._ev:emit"close"
      return true
   end
   return false
end
SP.close=SP.stop

-- Publishes Node Birth Certificate (NBIRTH)
function SP:publishNodeBirth(pl)
   self._nextSeq=0 -- Reset sequence number
   pl=cloneT(pl)
   tinsert(pl.metrics,bdSeqMetric(self))
   self._mqtt:publish(self._fmtNTopic"NBIRTH",encode(addSeq(self,pl)))
end

-- Publishes Device Birth Certificate (DBIRTH)
function SP:publishDeviceBirth(devId, pl)
   self._mqtt:publish(self._fmtDTopic("DBIRTH",devId),encode(addSeq(self,cloneT(pl))))
end

-- Publishes Node Data (NDATA)
function SP:publishNodeData(pl)
   self._mqtt:publish(self._fmtNTopic"NDATA",encode(addSeq(self,cloneT(pl))))
end

-- Publishes Device Data (DDATA)
function SP:publishDeviceData(devId, pl)
   self._mqtt:publish(self._fmtDTopic("DDATA",devId),encode(addSeq(self,cloneT(pl))))
end

-- Publishes Device Death Certificate (DDEATH)
function SP:publishDeviceDeath(devId, pl)
   pl=cloneT(pl)
   pl.metrics={}
   self._mqtt:publish(self._fmtDTopic("DDEATH",devId),encode(addSeq(self,pl)))
end

-- Event handler setup
function SP:on(event, callback)
   self._ev:on(event,callback)
end

-- NCMD or DCMD
local function decodePl(self,pl,type)
   local t,err=pb.decode(PayloadNS, pl)
   if t then
      decMetrics(t.metrics)
   else
      self._ev:emit("error",fmt("Cannot decode %s: %s",type,err))
   end
   return t
end

local nodeCtrl={
   ["Node Control/Rebirth"]="birth",
   ["Node Control/Reboot"]="reboot"
}

-- NCMD
local function manageNCmd(self,iter,pl)
   pl=decodePl(self,pl,"NCMD")
   if pl then
      local ms={}
      for k,m in pairs(pl.metrics) do
	 local evn=nodeCtrl[m.name]
	 if evn then
	    self._ev:emit(evn,m)
	 else
	    ms[k]=m
	 end
      end
      pl.metrics=ms
      self._ev:emit("ncmd",pl)
   end
end

-- DCMD
local function manageDCmd(self,iter,pl)
   iter() -- Skip node
   local devId=iter()
   if devId then
      pl=decodePl(self,pl,"DCMD")
      if pl then self._ev:emit("dcmd",devId,pl) end
   else
      self._ev:emit("error","Received invalid DCMD")
   end
end

-- STATE
local function manageState(self,iter,pl,groupID)
   self._ev:emit("state",groupID,pl)
end

local messageTypesT={
   NCMD=manageNCmd,
   DCMD=manageDCmd,
   STATE=manageState
}

-- STATE, NCMD, and DCMD
local function onPub(self,topic,pl)
   local iter=topic:gmatch"([^/]+)"
   iter() -- Skip ver
   local state=iter() -- STATE or groupID
   local groupID=iter() -- Only for STATE
   local manage=messageTypesT[groupID or state]
   if manage then
      manage(self,iter,pl,groupID)
   else
      self._ev:emit("error",fmt("Received unknown command %s",topic))
   end
end

local function onsuback(self,topic,reason) -- Check the MQTT subscribe status
   if reason and 0x80 <= reason then
      self._ev:emit("error",fmt("Subscribe failed for %s, reasons: %d", topic, reason),reason)
   end
   self._subscribeCntr=self._subscribeCntr+1
   if 3 == self._subscribeCntr then
      self._ev:emit"birth"
      self._ev:emit"connect"
   end
end


local function onstatus(self,type,code,status)
   if not self._running then return false end
   local ev,mqtt=self._ev,self._mqtt
   if "mqtt" == type then
      if "protocolerror" == code and nil ~= mqtt.recbta then -- recbta: if mqtt5 client
	 createMqtt(self,false)--Downgrade MQTT V.
	 return false
      end
      if "connect" == code and 0 == status.reasoncode then
	 self._connected,self._subscribeCntr=true,0
	 mqtt:subscribe(self._fmtNTopic"NCMD",
			function(t,p) onsuback(self,t,p) end,{qos=1})
	 mqtt:subscribe(self._fmtNTopic"DCMD".."/#",
			function(t,p) onsuback(self,t,p) end,{qos=1})
	 mqtt:subscribe("spBv1.0/STATE/#",
			function(t,p) onsuback(self,t,p) end,{qos=1})
	 return self._running
      end
   end
   if "sysshutdown" == code then
      ev:emit"offline"
      return false
   end
   if "socketreadfailed" == code and not self._connected and nil ~= mqtt.recbta then
      createMqtt(self,false)--Downgrade MQTT V.
      return false
   end
   ev:emit("error",code,status and status.reasoncode)
   if self._connected then
      self._connected=false
      ev:emit"offline"
      if self._running then
	 self._bdSeqNum=self._bdSeqNum+1
	 mqtt:setwill(spWill(self))
	 ev:emit"reconnect"
      end
   end
   return self._running
end

createMqtt=function(self,useMqtt5)
   self._mqtt=require(useMqtt5 and "mqttc" or "mqtt3c").create(self._addr,
      function(...) return onstatus(self,...) end,function(...) return onPub(self,...) end,self._op)
end

local function create(addr,groupId,nodeName,op)
   assert("string"==type(groupId) and
	  "string"==type(nodeName) and
	     (not op or "table"==type(op)), "Incorrect args")
   op=cloneT(op or {})
   local self = {
      _ev=require"EventEmitter".create(),
      _op=op,
      _addr=addr,
      _connected=false,
      _running=true,
      _bdSeqNum=0,
      _nextSeq=0,
      _fmtNTopic=function(msgType)
	 return fmt("%s/%s/%s/%s","spBv1.0",groupId,msgType,nodeName) end,
      _fmtDTopic=function(msgType,deviceId)
	 return fmt("%s/%s/%s/%s/%s","spBv1.0",groupId,msgType,nodeName,deviceId) end
   }
   op.will=spWill(self)
   op.recbta=false
   createMqtt(self,true)
   setmetatable(self, SP)
   return self
end

return {
   create=create,
   metric=metric,
   encode=function(pl)
      pl=cloneT(pl)
      pl.seq=pl.seq or 0
      encMetrics(pl.metrics,"metrics",3)
      return pl,pb.encode(PayloadNS,pl)
   end,
   decode=function(pl)
      local t,err=pb.decode(PayloadNS, pl)
      if t and t.metrics then decMetrics(t.metrics) end
      return t,err
   end
}
