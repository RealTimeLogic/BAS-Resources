-- Backward compat wrapper

local function create(op)
   tracep(false,8,"WARNING: using deprecated SMQ broker. Use the new SMQ Hub instead\n",
	 debug.traceback())
   op.rndtid=true
   local hub,err = require"smq.hub".create(op)
   if hub then
      return {
	 connect=function(cmd,arg) return hub:connect(cmd,arg) end,
	 create=function(topic,tid) return hub:create(topic,tid) end,
	 createsub=function(subtopic,tid) return hub:createsub(subtopic,tid) end,
	 etid2peer=function(tid) return hub:etid2peer(tid) end,
	 gettid=function() return hub:gettid() end,
	 observe=function(topic,func) return hub:observe(topic,func) end,
	 onmsg=function(cbfunc) return hub:onmsg(cbfunc) end,
	 peers=function() return hub:peers() end,
	 publish=function(data, topic, subtopic) return hub:publish(data, topic, subtopic) end,
	 queuesize=function() return hub:queuesize() end,
	 setkeepalive=function(time) return hub:setkeepalive(time) end,
	 shutdown=function(msg,etid) return hub:shutdown(msg,etid) end,
	 sock2peer=function(sock) return hub:sock2peer(sock) end,
	 subscribe=function(topic, op) return hub:subscribe(topic, op) end,
	 subtopic2tid=function(tid) return hub:subtopic2tid(tid) end,
	 subtopics=function() return hub:subtopics() end,
	 tid2subtopic=function(tid) return hub:tid2subtopic(tid) end,
	 tid2topic=function(tid) return hub:tid2topic(tid) end,
	 topic2tid=function(tid) return hub:topic2tid(tid) end,
	 topics=function() return hub:topics() end,
	 unobserve=function(topic) return hub:unobserve(topic) end,
	 unsubscribe=function(topic) return hub:unsubscribe(topic) end,
	 getbroker=function() return hub end
      }
   end
   return nil,err
end

return {
   create=create,
   isSMQ=require"smq.hub".isSMQ
}
