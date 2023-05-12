
SMQ={};

SMQ.utf8={
    length: function(inp) {
        var outp = 0;
        for(var i = 0; i<inp.length; i++) {
	    var charCode = inp.charCodeAt(i);
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
        var ix = start ? start : 0;
        for(var i = 0; i<inp.length; i++) {
	    var charCode = inp.charCodeAt(i);
	    if(0xD800 <= charCode && charCode <= 0xDBFF) {
	        lowCharCode = inp.charCodeAt(++i);
	        if(isNaN(lowCharCode)) return null;
	        charCode = ((charCode-0xD800)<<10)+(lowCharCode-0xDC00)+0x10000;
	    }
	    if(charCode <= 0x7F) outp[ix++] = charCode;
	    else if(charCode <= 0x7FF) {
	        outp[ix++] = charCode>>6  & 0x1F | 0xC0;
	        outp[ix++] = charCode     & 0x3F | 0x80;
	    }
            else if(charCode <= 0xFFFF) {    				    
	        outp[ix++] = charCode>>12 & 0x0F | 0xE0;
	        outp[ix++] = charCode>>6  & 0x3F | 0x80;   
	        outp[ix++] = charCode     & 0x3F | 0x80;   
	    }
            else {
	        outp[ix++] = charCode>>18 & 0x07 | 0xF0;
	        outp[ix++] = charCode>>12 & 0x3F | 0x80;
	        outp[ix++] = charCode>>6  & 0x3F | 0x80;
	        outp[ix++] = charCode     & 0x3F | 0x80;
	    };
        }
        return outp;
    },
    decode: function(inp, offset, length) {
        var outp = "";
        var utf16;
        if(offset == undefined) offset = 0;
        if(length == undefined) length = (inp.length - offset);
        var ix = offset;
        while(ix < offset+length) {
	    var b1 = inp[ix++];
	    if(b1 < 128) utf16 = b1;
	    else  {
	        var b2 = inp[ix++]-128;
	        if(b2 < 0) return null;
	        if(b1 < 0xE0)
		    utf16 = 64*(b1-0xC0) + b2;
	        else { 
		    var b3 = inp[ix++]-128;
		    if(b3 < 0) return null;
		    if(b1 < 0xF0) utf16 = 4096*(b1-0xE0) + 64*b2 + b3;
		    else {
		        var b4 = inp[ix++]-128;
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
    var l = window.location;
    if(path == undefined) path = l.pathname;
    return ((l.protocol === "https:") ? "wss://" : "ws://") +
        l.hostname +
        (l.port!=80 && l.port!=443 && l.port.length!=0 ? ":" + l.port : "") +
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
    var self = this;
    var SMQ_VERSION = 1;
    var MSG_INIT = 1;
    var MSG_CONNECT = 2;
    var MSG_CONNACK = 3;
    var MSG_SUBSCRIBE = 4;
    var MSG_SUBACK = 5;
    var MSG_CREATE = 6;
    var MSG_CREATEACK = 7;
    var MSG_PUBLISH = 8;
    var MSG_UNSUBSCRIBE = 9;
    var MSG_DISCONNECT = 11;
    var MSG_PING = 12;
    var MSG_PONG = 13;
    var MSG_OBSERVE = 14;
    var MSG_UNOBSERVE = 15;
    var MSG_CHANGE = 16;
    var MSG_CREATESUB  = 17
    var MSG_CREATESUBACK = 18;
    var socket;
    var connected=false;
    var selfTid;
    var onclose;
    var onconnect;
    var intvtmo;
    if( ! url ) url = SMQ.wsURL();
    var tid2topicT={}; //Key= tid, val = topic name
    var topic2tidT={}; //Key=topic name, val=tid
    var topicAckCBT={}; //Key=topic name, val=array of callback funcs
    var tid2subtopicT={}; //Key= tid, val = subtopic name
    var subtopic2tidT={}; //Key=sub topic name, val=tid
    var subtopicAckCBT={}; //Key=sub topic name, val=array of callback funcs
    var onMsgCBT={}; //Key=tid, val = {all: CB, subtops: {stid: CB}}
    var observeT={}; //Key=tid, val = onchange callback
    var pendingCmds=[]; //List of functions to exec on connect

    if(!opt) opt={}

    var n2h32=function(d,ix) {
        return (d[ix]*16777216) + (d[ix+1]*65536) + (d[ix+2]*256) + d[ix+3];
    };

    var h2n32=function(n,d,ix) {
        d[ix]   = n >>> 24;
        d[ix+1] = n >>> 16;
        d[ix+2] = n >>> 8;
        d[ix+3] = n;
    };

    var execPendingCmds=function() {
        for(var i = 0 ; i < pendingCmds.length; i++)
            pendingCmds[i]();
        pendingCmds=[];
    };

    var decodeTxt = function(data, ptid, tid, subtid) {
        var msg = SMQ.utf8.decode(data);
        if( ! msg ) {
            if(data.length == 0) return "";
            console.log("Cannot decode UTF8 for tid=",
                        tid,", ptid=",ptid,", subtid=",subtid);
            self.onmsg(data, ptid, tid, subtid);
        }
        return msg;
    };

    var dispatchTxt = function(cbFunc, data, ptid, tid, subtid) {
        var msg = decodeTxt(data, ptid, tid, subtid);
        if(msg) cbFunc(msg, ptid, tid, subtid);
    };

    var dispatchJSON = function(cbFunc, data, ptid, tid, subtid) {
        var msg = decodeTxt(data, ptid, tid, subtid);
        if(!msg) return;
        var j;
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

    var pushElem=function(obj,key,elem) {
        var newEntry=false;
        var arr = obj[key];
        if( ! arr ) {
            arr =[];
            obj[key]=arr;
            newEntry=true;
        }
        arr.push(elem);
        return newEntry;
    };

    var cancelIntvConnect=function() {
        if(intvtmo) clearTimeout(intvtmo);
        intvtmo=null;
    };

    var socksend=function(data) {
        try {socket.send(data);}
        catch(e) {onclose(e.message, true); }
    };

    var createSock=function(isReconnect) {
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
    var restore = function(newTid, rnd, ipaddr) {
        var tid2to = tid2topicT;
        var to2tid = topic2tidT;
        var tid2sto = tid2subtopicT;
        var sto2tid = subtopic2tidT;
        var onmsgcb = onMsgCBT;
        var obs = observeT;
        tid2topicT={};
        topic2tidT={};
        topicAckCBT={};
        tid2subtopicT={};
        subtopic2tidT={};
        subtopicAckCBT={};
        onMsgCBT={};
        observeT={};
        var oldTid = selfTid;
        selfTid = newTid;

        var onResp2Cnt=10000;
        var onResp1Cnt=10000;

        var onresp2 = function() { // (3) Re-create observed tids
            if(--onResp2Cnt <= 0 && connected) {
                onResp2Cnt=10000;
                for(var tid in obs) {
                    var topic = tid2to[tid];
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
        var onresp1 = function() { // (2) Re-create subscriptions
            if(--onResp1Cnt <= 0 && connected) {
                onResp1Cnt=10000;
                try {
                    for(var tid in onmsgcb) {
                        var topic = tid == oldTid ? "self" : tid2to[tid];
                        if(topic) {
                            var t = onmsgcb[tid];
                            if(t.onmsg) {
                                onResp2Cnt++;
                                self.subscribe(topic, {
                                    onmsg:t.onmsg,onack:onresp2});
                            }
                            for(var stid in t.subtops) {
                                var subtop = tid2sto[stid];
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
            for(var t in to2tid) {onResp1Cnt++; self.create(to2tid[t],onresp1);}
            for(var t in sto2tid) {onResp1Cnt++; self.createsub(sto2tid[t],onresp1);}
        }
        catch(e) {}
        onResp1Cnt -= 10000;
        if(connected && onResp1Cnt <= 0)
            onresp1();
    };

    onclose=function(msg,ok2reconnect) {
        if(socket) {
            connected=false;
            var s = socket;
            socket=null;
            //Prevent further event messages
            try {s.onopen=s.onmessage=s.onclose=s.onerror=function(){};}
            catch(err) {}
            try { s.close(); } catch(err) {}
            if(self.onclose) {
                var timeout = self.onclose(msg,ok2reconnect);
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

    var onmessage = function(evt) {
        var d = new Uint8Array(evt.data);
        switch(d[0]) {

        case MSG_SUBACK:
        case MSG_CREATEACK:
        case MSG_CREATESUBACK:
            var accepted=d[1] ? false : true;
            var tid=n2h32(d,2);
            var topic=SMQ.utf8.decode(d,6);
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
            var t = d[0] == MSG_CREATESUBACK ? subtopicAckCBT : topicAckCBT;
            var arr=t[topic];
            t[topic]=null;
            if(arr) {
                for (var i = 0; i < arr.length; i++)
                    arr[i](accepted,topic,tid);
            }
            break;

        case MSG_PUBLISH:
            var tid = n2h32(d,1);
            var ptid = n2h32(d,5);
            var subtid = n2h32(d,9);
            var data = new Uint8Array(evt.data,13)
            var cbFunc;
            var t = onMsgCBT[tid];
            if(t) {
                cbFunc = t.subtops[subtid];
                if(!cbFunc) cbFunc = t.onmsg ? t.onmsg : self.onmsg;
            }
            else
                cbFunc = self.onmsg;
            cbFunc(data, ptid, tid, subtid);
            break;

        case MSG_DISCONNECT:
            var msg;
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
            var tid = n2h32(d,1);
            var func = observeT[tid];
            if(func) {
                var subsribers = n2h32(d,5);
                var topic = tid2topicT[tid];
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
        var d = new Uint8Array(evt.data);
        if(d[0] == MSG_INIT)
        {
            if(d[1] == SMQ_VERSION)
            {
                var credent
                var rnd=n2h32(d,2);
                var ipaddr=SMQ.utf8.decode(d,6);
                var uid = SMQ.utf8.encode(opt.uid ? opt.uid : ipaddr+rnd);
                var info = opt.info ? SMQ.utf8.encode(opt.info) : null;
                if(self.onauth) {
                    credent=self.onauth(rnd, ipaddr);
                    if(credent) credent = SMQ.utf8.encode(credent);
                }
                var out = new Uint8Array(3 + uid.length + 
                                         (credent ? 1+credent.length : 1) + 
                                         (info ? info.length : 0));
                out[0] = MSG_CONNECT;
                out[1] = SMQ_VERSION;
                out[2] = uid.length;
                var ix;
                var i;
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
                    var d = new Uint8Array(evt.data);
                    if(d[0] == MSG_CONNACK)
                    {
                        if(d[1] == 0)
                        {
                            var tid = n2h32(d,2);
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

    var subOrCreate=function(topic, subtopic, settings, isCreate) {
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
        var onack=function(accepted,topic,tid,stopic,stid) {
            if(settings.onack) settings.onack(accepted,topic,tid,stopic,stid);
            else if(!accepted) console.log("Denied:",topic,tid,stopic,stid);
            if(!isCreate && accepted && settings.onmsg) {
                var t = onMsgCBT[tid];
                if(!t) t = onMsgCBT[tid] = {subtops:{}};
                var onmsg = settings.onmsg;
                var orgOnmsg=onmsg;
                var dt=settings.datatype;
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
            var orgOnAck = onack;
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
                    var d = new Uint8Array(SMQ.utf8.length(topic)+1)
                    d[0] = isCreate ? MSG_CREATE : MSG_SUBSCRIBE;
                    SMQ.utf8.encode(topic,d,1);
                    socksend(d.buffer);
                }
            }
            else
                throw new Error("Invalid topic type");
        }
    };

    var getTid=function(topic) {
        var tid;
        if(typeof topic =="string") {
            tid = topic2tidT[topic];
            if( ! tid ) throw new Error("tid not found");
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
        var d;
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
        var tid,stid;
        var sendit=function() { 
            h2n32(tid,d,1);
            h2n32(stid,d,9);
            socksend(d.buffer);
        };
        if(typeof(topic) == "string") {
            tid = topic2tidT[topic];
            if(!tid) {
                var orgSendit1=sendit;
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
                var orgSendit2=sendit;
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
            var d = new Uint8Array(1);
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
                    var d = new Uint8Array(SMQ.utf8.length(subtopic)+1)
                    d[0] = MSG_CREATESUB;
                    SMQ.utf8.encode(subtopic,d,1);
                    socksend(d.buffer);
                }
            }
            else
                throw new Error("Invalid subtopic type");
        }
    };

    var sendMsgWithTid=function(msgType, tid) {
        var d = new Uint8Array(5);
        d[0] = msgType;
        h2n32(tid,d,1);
        socksend(d.buffer);
    };

    self.unsubscribe = function(topic) {
        var tid=getTid(topic);
        if(onMsgCBT[tid]) {
            onMsgCBT[tid]=null;
            sendMsgWithTid(MSG_UNSUBSCRIBE, tid);
        }
    };

    self.observe=function(topic, onchange) {
        var tid=getTid(topic);
        if(tid != selfTid && !observeT[tid]) {
            observeT[tid] = onchange;
            sendMsgWithTid(MSG_OBSERVE, tid);
        }
    };

    self.unobserve=function(topic) {
        var tid=getTid(topic);
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
