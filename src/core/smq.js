SMQ={};

SMQ.utf8={
    length: function(inp) {
	let outp = 0;
	for(let i = 0; i<inp.length; i++) {
	    let charCode = inp.charCodeAt(i);
	    if(charCode > 0x7FF) {
		if(0xD800 <= charCode && charCode <= 0xDBFF) {
		    i++;
		    outp++;
		}
		outp +=3;
	    }
	    else if(charCode > 0x7F) outp +=2;
	    else outp++;
	}
	return outp;
    },
    encode: function(inp, outp, start) {
	if(outp == undefined)
	    outp = new Uint8Array(SMQ.utf8.length(inp))
	let ix = start ? start : 0;
	for(let i = 0; i<inp.length; i++) {
	    let charCode = inp.charCodeAt(i);
	    if(0xD800 <= charCode && charCode <= 0xDBFF) {
		lowCharCode = inp.charCodeAt(++i);
		if(isNaN(lowCharCode)) return null;
		charCode = ((charCode-0xD800)<<10)+(lowCharCode-0xDC00)+0x10000;
	    }
	    if(charCode <= 0x7F) outp[ix++] = charCode;
	    else if(charCode <= 0x7FF) {
		outp[ix++] = charCode>>6  & 0x1F | 0xC0;
		outp[ix++] = charCode	  & 0x3F | 0x80;
	    }
	    else if(charCode <= 0xFFFF) {				    
		outp[ix++] = charCode>>12 & 0x0F | 0xE0;
		outp[ix++] = charCode>>6  & 0x3F | 0x80;   
		outp[ix++] = charCode	  & 0x3F | 0x80;   
	    }
	    else {
		outp[ix++] = charCode>>18 & 0x07 | 0xF0;
		outp[ix++] = charCode>>12 & 0x3F | 0x80;
		outp[ix++] = charCode>>6  & 0x3F | 0x80;
		outp[ix++] = charCode	  & 0x3F | 0x80;
	    };
	}
	return outp;
    },
    decode: function(inp, offset, length) {
	let outp = "";
	let utf16;
	if(offset == undefined) offset = 0;
	if(length == undefined) length = (inp.length - offset);
	let ix = offset;
	while(ix < offset+length) {
	    let b1 = inp[ix++];
	    if(b1 < 128) utf16 = b1;
	    else  {
		let b2 = inp[ix++]-128;
		if(b2 < 0) return null;
		if(b1 < 0xE0)
		    utf16 = 64*(b1-0xC0) + b2;
		else { 
		    let b3 = inp[ix++]-128;
		    if(b3 < 0) return null;
		    if(b1 < 0xF0) utf16 = 4096*(b1-0xE0) + 64*b2 + b3;
		    else {
			let b4 = inp[ix++]-128;
			if(b4 < 0) return null;
			if(b1 < 0xF8) utf16 = 262144*(b1-0xF0)+4096*b2+64*b3+b4;
			else return null;
		    }
		}
	    }  
	    if(utf16 > 0xFFFF)
	    {
		utf16 -= 0x10000;
		outp += String.fromCharCode(0xD800 + (utf16 >> 10));
		utf16 = 0xDC00 + (utf16 & 0x3FF);
	    }
	    outp += String.fromCharCode(utf16);
	}
	return outp;
    }
};


SMQ.wsURL = function(path) {
    let l = window.location;
    if(!path) path = l.pathname;
    if(path[0] !== '/') {
	let currentPath = l.pathname.split('/');
	currentPath.pop(); // Remove the last segment
	path = currentPath.join('/') + '/' + path;
    }
    return ((l.protocol === "https:") ? "wss://" : "ws://") +
	l.hostname +
	(l.port != 80 && l.port != 443 && l.port.length != 0 ? ":" + l.port : "") +
	path;
};

SMQ.websocket = function() {
    if("WebSocket" in window && window.WebSocket != undefined)
	return true;
    return false;
};


SMQ.Client = function(url, opt) {
    if (!(this instanceof SMQ.Client)) return new SMQ.Client(url, opt);
    if(arguments.length < 2 && typeof(url)=="object") {
	opt=url;
	url=null;
    }
    let self = this;
    let SMQ_VERSION = 1;
    let MSG_INIT = 1;
    let MSG_CONNECT = 2;
    let MSG_CONNACK = 3;
    let MSG_SUBSCRIBE = 4;
    let MSG_SUBACK = 5;
    let MSG_CREATE = 6;
    let MSG_CREATEACK = 7;
    let MSG_PUBLISH = 8;
    let MSG_UNSUBSCRIBE = 9;
    let MSG_DISCONNECT = 11;
    let MSG_PING = 12;
    let MSG_PONG = 13;
    let MSG_OBSERVE = 14;
    let MSG_UNOBSERVE = 15;
    let MSG_CHANGE = 16;
    let MSG_CREATESUB  = 17
    let MSG_CREATESUBACK = 18;
    let socket;
    let connected=false;
    let selfTid;
    let onclose;
    let onconnect;
    let intvtmo;
    if( ! url ) url = SMQ.wsURL();
    let tid2topicT={}; //Key= tid, val = topic name
    let topic2tidT={}; //Key=topic name, val=tid
    let topicAckCBT={}; //Key=topic name, val=array of callback funcs
    let tid2subtopicT={}; //Key= tid, val = subtopic name
    let subtopic2tidT={}; //Key=sub topic name, val=tid
    let subtopicAckCBT={}; //Key=sub topic name, val=array of callback funcs
    let onMsgCBT={}; //Key=tid, val = {all: CB, subtops: {stid: CB}}
    let observeT={}; //Key=tid, val = onchange callback
    let pendingCmds=[]; //List of functions to exec on connect

    if(!opt) opt={}

    let n2h32=function(d,ix) {
	return (d[ix]*16777216) + (d[ix+1]*65536) + (d[ix+2]*256) + d[ix+3];
    };

    let h2n32=function(n,d,ix) {
	d[ix]	= n >>> 24;
	d[ix+1] = n >>> 16;
	d[ix+2] = n >>> 8;
	d[ix+3] = n;
    };

    let execPendingCmds=function() {
	for(let i = 0 ; i < pendingCmds.length; i++)
	    pendingCmds[i]();
	pendingCmds=[];
    };

    let decodeTxt = function(data, ptid, tid, subtid) {
	let msg = SMQ.utf8.decode(data);
	if( ! msg ) {
	    if(data.length == 0) return "";
	    console.log("Cannot decode UTF8 for tid=",
			tid,", ptid=",ptid,", subtid=",subtid);
	    self.onmsg(data, ptid, tid, subtid);
	}
	return msg;
    };

    let dispatchTxt = function(cbFunc, data, ptid, tid, subtid) {
	let msg = decodeTxt(data, ptid, tid, subtid);
	if(msg) cbFunc(msg, ptid, tid, subtid);
    };

    let dispatchJSON = function(cbFunc, data, ptid, tid, subtid) {
	let msg = decodeTxt(data, ptid, tid, subtid);
	if(!msg) return;
	let j;
	try {
	    j=JSON.parse(msg);
	}
	catch(e) {
	    console.log("Cannot parse JSON for tid=",
			tid,", ptid=",ptid,", subtid=",subtid);
	    self.onmsg(data, ptid, tid, subtid);
	}
	try {
	    cbFunc(j, ptid, tid, subtid);
	}
	catch(e) {
	    console.log("Callback failed: "+e+"\n"+e.stack);
	}

    };

    let pushElem=function(obj,key,elem) {
	let newEntry=false;
	let arr = obj[key];
	if( ! arr ) {
	    arr =[];
	    obj[key]=arr;
	    newEntry=true;
	}
	arr.push(elem);
	return newEntry;
    };

    let cancelIntvConnect=function() {
	if(intvtmo) clearTimeout(intvtmo);
	intvtmo=null;
    };

    let socksend=function(data) {
	try {socket.send(data);}
	catch(e) {onclose(e.message, true); }
    };

    let createSock=function(isReconnect) {
	try {
	    socket = new WebSocket(url);
	}
	catch(err) {
	    socket=null;
	}
	if( ! socket ) {
	    onclose("Cannot create WebSocket object", true);
	    return;
	}
	socket.binaryType = 'arraybuffer';
	socket.onmessage = function(evt) {
	    cancelIntvConnect();
	    onconnect(evt, isReconnect); };
	socket.onclose = function(evt) {
	    onclose("Unexpected socket close", true); };
	socket.onerror = function (err) {
	    onclose(connected ? "Socket error" : "Cannot connect", true);
	}
    };

    // Restore all tid's and subscriptions after a disconnect/reconnect
    let restore = function(newTid, rnd, ipaddr) {
	let tid2to = tid2topicT;
	let to2tid = topic2tidT;
	let tid2sto = tid2subtopicT;
	let sto2tid = subtopic2tidT;
	let onmsgcb = onMsgCBT;
	let obs = observeT;
	tid2topicT={};
	topic2tidT={};
	topicAckCBT={};
	tid2subtopicT={};
	subtopic2tidT={};
	subtopicAckCBT={};
	onMsgCBT={};
	observeT={};
	let oldTid = selfTid;
	selfTid = newTid;

	let onResp2Cnt=10000;
	let onResp1Cnt=10000;

	let onresp2 = function() { // (3) Re-create observed tids
	    if(--onResp2Cnt <= 0 && connected) {
		onResp2Cnt=10000;
		for(let tid in obs) {
		    let topic = tid2to[tid];
		    if(topic) {
			self.observe(topic, obs[tid]);
		    }
		}
		if(connected) {
		    execPendingCmds();
		    if(self.onreconnect)
			self.onreconnect(newTid, rnd, ipaddr);
		}
		else
		    onclose("reconnecting failed",false);
	    }
	};
	if(true == opt.cleanstart)
	{
	    onResp2Cnt=-1;
	    onresp2();
	    return;
	}
	let onresp1 = function() { // (2) Re-create subscriptions
	    if(--onResp1Cnt <= 0 && connected) {
		onResp1Cnt=10000;
		try {
		    for(let tid in onmsgcb) {
			let topic = tid == oldTid ? "self" : tid2to[tid];
			if(topic) {
			    let t = onmsgcb[tid];
			    if(t.onmsg) {
				onResp2Cnt++;
				self.subscribe(topic, {
				    onmsg:t.onmsg,onack:onresp2});
			    }
			    for(let stid in t.subtops) {
				let subtop = tid2sto[stid];
				if(subtop) {
				    onResp2Cnt++;
				    self.subscribe(topic,subtop,{
					onmsg:t.subtops[stid],onack:onresp2});
				}
			    }
			}
		    }
		}
		catch(e) {console.log(e.message);}
		if(connected) {
		    onResp2Cnt -= 10000;
		    if(onResp2Cnt <= 0)
			onresp2();
		}
	    }
	};
	try { // (1) Re-create tids and subtids
	    for(let t in to2tid) {onResp1Cnt++; self.create(to2tid[t],onresp1);}
	    for(let t in sto2tid) {onResp1Cnt++; self.createsub(sto2tid[t],onresp1);}
	}
	catch(e) {}
	onResp1Cnt -= 10000;
	if(connected && onResp1Cnt <= 0)
	    onresp1();
    };

    onclose=function(msg,ok2reconnect) {
	if(socket) {
	    connected=false;
	    let s = socket;
	    socket=null;
	    //Prevent further event messages
	    try {s.onopen=s.onmessage=s.onclose=s.onerror=function(){};}
	    catch(err) {}
	    try { s.close(); } catch(err) {}
	    if(self.onclose) {
		let timeout = self.onclose(msg,ok2reconnect);
		if(ok2reconnect && typeof(timeout) =="number") {
		    if(!intvtmo) {
			if(timeout < 1000) timeout = 1000;
			intvtmo=setInterval(function() {
			    if( ! socket ) createSock(true);
			},timeout);
		    }
		}
		else
		    cancelIntvConnect();
	    }
	}
	connected=false;
    };

    let onmessage = function(evt) {
	let tid;
	let t;
	let d = new Uint8Array(evt.data);
	switch(d[0]) {

	case MSG_SUBACK:
	case MSG_CREATEACK:
	case MSG_CREATESUBACK:
	    let accepted=d[1] ? false : true;
	    tid=n2h32(d,2);
	    let topic=SMQ.utf8.decode(d,6);
	    if(accepted) {
		if(d[0] == MSG_CREATESUBACK) {
		    tid2subtopicT[tid]=topic;
		    subtopic2tidT[topic]=tid;
		}
		else {
		    tid2topicT[tid]=topic;
		    topic2tidT[topic]=tid;
		}
	    }
	    t = d[0] == MSG_CREATESUBACK ? subtopicAckCBT : topicAckCBT;
	    let arr=t[topic];
	    t[topic]=null;
	    if(arr) {
		for (let i = 0; i < arr.length; i++)
		    arr[i](accepted,topic,tid);
	    }
	    break;

	case MSG_PUBLISH:
	    tid = n2h32(d,1);
	    let ptid = n2h32(d,5);
	    let subtid = n2h32(d,9);
	    let data = new Uint8Array(evt.data,13)
	    let cbFunc;
	    t = onMsgCBT[tid];
	    if(t) {
		cbFunc = t.subtops[subtid];
		if(!cbFunc) cbFunc = t.onmsg ? t.onmsg : self.onmsg;
	    }
	    else
		cbFunc = self.onmsg;
	    cbFunc(data, ptid, tid, subtid);
	    break;

	case MSG_DISCONNECT:
	    let msg;
	    if(d.length > 1)
		msg=SMQ.utf8.decode(d,1);
	    onclose(msg ? msg : "disconnect",false);
	    break;

	case MSG_PING:
	    d[0] = MSG_PONG;
	    socksend(d.buffer);
	    break;

	case MSG_PONG:
	    console.log("pong");
	    break;

	case MSG_CHANGE:
	    tid = n2h32(d,1);
	    let func = observeT[tid];
	    if(func) {
		let subsribers = n2h32(d,5);
		let topic = tid2topicT[tid];
		if(!topic && subsribers == 0)
		    observeT[tid]=null; /* Remove ephemeral */
		func(subsribers, topic ? topic : tid);
	    }
	    break;

	default:
	    onclose("protocol error", true);
	}
    };

    onconnect = function(evt, isReconnect) {
	if( ! socket ) return;
	cancelIntvConnect();
	let d = new Uint8Array(evt.data);
	if(d[0] == MSG_INIT)
	{
	    if(d[1] == SMQ_VERSION)
	    {
		let credent
		let rnd=n2h32(d,2);
		let ipaddr=SMQ.utf8.decode(d,6);
		let uid = SMQ.utf8.encode(opt.uid ? opt.uid : ipaddr+rnd);
		let info = opt.info ? SMQ.utf8.encode(opt.info) : null;
		if(self.onauth) {
		    credent=self.onauth(rnd, ipaddr);
		    if(credent) credent = SMQ.utf8.encode(credent);
		}
		let out = new Uint8Array(3 + uid.length + 
					 (credent ? 1+credent.length : 1) + 
					 (info ? info.length : 0));
		out[0] = MSG_CONNECT;
		out[1] = SMQ_VERSION;
		out[2] = uid.length;
		let ix;
		let i;
		for(i = 0; i < uid.length; i++) out[3+i]=uid[i];
		ix=3+i;
		if(credent) {
		    out[ix++]=credent.length;
		    for(i = 0; i < credent.length; i++) out[ix++]=credent[i];
		}
		else
		    out[ix++]=0;
		if(info) {
		    for(i = 0; i < info.length; i++)
			out[ix+i]=info[i];
		}
		socket.onmessage = function(evt) {
		    let d = new Uint8Array(evt.data);
		    if(d[0] == MSG_CONNACK)
		    {
			if(d[1] == 0)
			{
			    let tid = n2h32(d,2);
			    connected=true;
			    socket.onmessage=onmessage;
			    if(isReconnect) {
				restore(tid,rnd,ipaddr);
			    }
			    else {
				selfTid=tid;
				execPendingCmds();
				if(self.onconnect)
				    self.onconnect(selfTid, rnd, ipaddr); 
			    }
			}
			else
			    onclose(SMQ.utf8.decode(d,6), false);
		    }
		    else
			onclose("protocol error", false);
		};
		socksend(out.buffer);
	    }
	    else
		onclose("Incompatible ver "+d[1], false);
	}
	else
	    onclose("protocol error", false);
    };

    let subOrCreate=function(topic, subtopic, settings, isCreate) {
	if( ! connected ) {
	    pendingCmds.push(function() {
		subOrCreate(topic, subtopic, settings, isCreate);
	    });
	    return;
	}
	if(typeof(subtopic) == "object") {
	    settings = subtopic;
	    subtopic=null;
	}
	if(!settings) settings={}
	let onack=function(accepted,topic,tid,stopic,stid) {
	    if(settings.onack) settings.onack(accepted,topic,tid,stopic,stid);
	    else if(!accepted) console.log("Denied:",topic,tid,stopic,stid);
	    if(!isCreate && accepted && settings.onmsg) {
		let t = onMsgCBT[tid];
		if(!t) t = onMsgCBT[tid] = {subtops:{}};
		let onmsg = settings.onmsg;
		let orgOnmsg=onmsg;
		let dt=settings.datatype;
		if(dt) {
		    if(dt == "json") {
			onmsg=function(data, ptid, tid, subtid) {
			    dispatchJSON(orgOnmsg, data, ptid, tid, subtid);
			};
		    } 
		    else if(dt == "text") {
			onmsg=function(data, ptid, tid, subtid) {
			    dispatchTxt(orgOnmsg, data, ptid, tid, subtid);
			};
		    }
		}
		if(stid) t.subtops[stid] = onmsg;
		else t.onmsg = onmsg;
	    }
	};
	if(subtopic) {
	    let orgOnAck = onack;
	    onack=function(accepted,topic,tid) {
		if(accepted) {
		    self.createsub(subtopic, function(accepted,stopic,stid) {
			orgOnAck(accepted,topic,tid,stopic,stid)
		    });
		}
		else
		    orgOnAck(accepted,topic,tid);
	    };
	}
	if(topic == "self")
	    onack(true,topic, selfTid);
	else if(topic2tidT[topic] && isCreate)
	    onack(true,topic,topic2tidT[topic]);
	else {
	    if(typeof topic == "number") {
		topic2tidT[topic]=topic;
		tid2topicT[topic]=topic;
		onack(true, topic, topic);
	    }
	    else if(typeof topic == "string") {
		if(pushElem(topicAckCBT,topic,onack)) {
		    let d = new Uint8Array(SMQ.utf8.length(topic)+1)
		    d[0] = isCreate ? MSG_CREATE : MSG_SUBSCRIBE;
		    SMQ.utf8.encode(topic,d,1);
		    socksend(d.buffer);
		}
	    }
	    else
		throw new Error("Invalid topic type");
	}
    };

    let getTid=function(topic) {
	let tid;
	if(typeof topic =="string") {
	    tid = topic2tidT[topic];
	    if( ! tid ) {
              if("self"==topic) tid=selfTid;
              else throw new Error("tid not found");
            }
	}
	else
	    tid = topic;
	return tid;
    };

    self.publish=function(data,topic,subtopic) {
	if( ! connected ) {
	    pendingCmds.push(function() {
		self.publish(data,topic,subtopic);
	    });
	    return;
	}
	let d;
	if(typeof data == "string") {
	    d = new Uint8Array(SMQ.utf8.length(data)+13)
	    SMQ.utf8.encode(data,d,13);
	}
	else {
	    d = new Uint8Array(data.length + 13);
	    for(i = 0; i < data.length; i++)
		d[13+i]=data[i];
	}
	d[0] = MSG_PUBLISH;
	h2n32(selfTid,d,5);
	let tid,stid;
	let sendit=function() { 
	    h2n32(tid,d,1);
	    h2n32(stid,d,9);
	    socksend(d.buffer);
	};
	if(typeof(topic) == "string") {
	    tid = topic2tidT[topic];
	    if(!tid) {
		let orgSendit1=sendit;
		sendit=function() {
		    self.create(topic,function(ok,x,t) {
			if(ok) {
			    tid=t;
			    orgSendit1();
			}
		    });
		};
	    }
	}
	else
	    tid = topic;
	if( ! subtopic ) stid=0;
	else if(typeof(subtopic) == "string") {
	    stid = subtopic2tidT[subtopic];
	    if(!stid) {
		let orgSendit2=sendit;
		sendit=function() {
		    self.createsub(subtopic, function(ok,x,t) {
			if(ok) {
			    stid=t;
			    orgSendit2();
			}
		    });
		};
	    }
	}
	else
	    stid=subtopic;
	sendit();
    };

    self.pubjson=function(value,topic,subtopic) {
	self.publish(JSON.stringify(value),topic,subtopic);
    };

    self.topic2tid=function(topic) {
	return topic2tidT[topic];
    };
    
    self.tid2topic=function(tid) {
	return tid2topicT[tid];
    };

    self.subtopic2tid=function(subtopic) {
	return subtopic2tidT[subtopic];
    };
    
    self.tid2subtopic=function(tid) {
	return tid2subtopicT[tid];
    };
    
    self.disconnect=function() {
	if(connected) {
	    let d = new Uint8Array(1);
	    d[0] = MSG_DISCONNECT
	    socket.send(d.buffer);
	    connected=false;
	}
    };

    self.subscribe = function(topic, subtopic, settings) {
	subOrCreate(topic, subtopic, settings, false);
    };

    self.create = function(topic, subtopic, onack) {
	if(arguments.length == 3)
	    subOrCreate(topic, subtopic, {onack: onack}, true);
	else
	    subOrCreate(topic, 0, {onack: subtopic}, true);
    };

    self.createsub = function(subtopic, onsuback) {
	if( ! connected ) {
	    pendingCmds.push(function() {
		self.createsub(subtopic, onsuback);
	    });
	    return;
	}
	if( ! onsuback ) onsuback=function(){};
	if(subtopic2tidT[subtopic])
	    onsuback(true, subtopic, subtopic2tidT[subtopic]);
	else {
	    if(typeof subtopic == "number") {
		subtopic2tidT[subtopic]=subtopic;
		tid2subtopicT[subtopic]=subtopic;
		onsuback(true, subtopic, subtopic);
	    }
	    else if(typeof subtopic == "string") {
		if(pushElem(subtopicAckCBT,subtopic,onsuback)) {
		    let d = new Uint8Array(SMQ.utf8.length(subtopic)+1)
		    d[0] = MSG_CREATESUB;
		    SMQ.utf8.encode(subtopic,d,1);
		    socksend(d.buffer);
		}
	    }
	    else
		throw new Error("Invalid subtopic type");
	}
    };

    let sendMsgWithTid=function(msgType, tid) {
	let d = new Uint8Array(5);
	d[0] = msgType;
	h2n32(tid,d,1);
	socksend(d.buffer);
    };

    self.unsubscribe = function(topic) {
	let tid=getTid(topic);
	if(onMsgCBT[tid]) {
	    onMsgCBT[tid]=null;
	  if("self" != topic) sendMsgWithTid(MSG_UNSUBSCRIBE, tid);
	}
    };

    self.observe=function(topic, onchange) {
	let tid=getTid(topic);
	if(tid != selfTid && !observeT[tid]) {
	    observeT[tid] = onchange;
	    sendMsgWithTid(MSG_OBSERVE, tid);
	}
    };

    self.unobserve=function(topic) {
	let tid=getTid(topic);
	if(observeT[tid]) {
	    observeT[tid]=0;
	    sendMsgWithTid(MSG_UNOBSERVE, tid);
	}
    };

    self.gettid = function() { return selfTid; }
    self.getsock = function() { return socket; }

    self.onmsg = function(data, ptid, tid, subtid) {
	console.log("Dropping msg: tid=",tid,", ptid=",ptid,", subtid=",subtid);
    };

    createSock(false);
};
