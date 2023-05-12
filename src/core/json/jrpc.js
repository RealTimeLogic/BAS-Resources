/**
   Create an error object.
   @param msg the error message.
   @param errno a global unique error number.
   @param an optional exception object.
 */
function ErrorType(msg, errno, e)
{
   if(!e)
      e={};
   this.e = new Error("");
   this.message=msg;
   this.errno=errno;
   if(e.e && e.e.message) {
      this.e.orgMsg=e.message;
      this.e.orgErrno=e.errno;
      e=e.e;
   }
   for(var i in e) {
      try {
         this.e[i] = e[i];
      }
      catch(ignoreE) {}
   }
};

function XMLHttpRequestWrapper() {
   var ex;
   try {
      this.xmlhttp = new ActiveXObject("Microsoft.XMLHTTP");
   } 
   catch (e) {
      try {
         this.xmlhttp = new XMLHttpRequest();
      }
      catch(e) {ex = e;}
   }
   if(this.xmlhttp) {
      this.$$bindOnreadystatechange();
      return;
   }
   throw new ErrorType("No XMLHttpRequest support in browser", 1000,ex);
};


/*
 * We create the onreadystatechange binding in a separate function
 * such that the object contained within the scope of
 * onreadystatechange only contains xmlhttpW -- i.e. we save some memory
 * this way.
 */
XMLHttpRequestWrapper.prototype.$$bindOnreadystatechange=function() {
   var xmlhttpW = this;
   this.xmlhttp.onreadystatechange = function() {
      xmlhttpW.$$onreadystatechange();
   };
   try {
      req.xmlhttp.onerror=function() {xmlhttpW.$$onerror();};
   }
   catch(e) {}//Ignore. Valid for Mozilla(Gecko) only.
};


XMLHttpRequestWrapper.prototype.$$onreadystatechange=function() {
   if(this.xmlhttp.readyState == 4) {
      try {
         if(this.xmlhttp.status) this.status = this.xmlhttp.status;
          this.$exception={};
      }
      catch(e){this.$exception=e;}
      if( ! this.status || this.status > 1000) this.status = -1;
   }
   if(this.onreadystatechange)
      this.onreadystatechange(this.xmlhttp.readyState);
};


XMLHttpRequestWrapper.prototype.$$onerror=function() {
   this.xmlhttp.status = -1;
   this.onreadystatechange(4);
};


/**
  @param     
  @returns 
  @throws 1001: XMLHttpRequestWrapper::getResponseHeader
*/
XMLHttpRequestWrapper.prototype.getResponseHeader=function(header) {
   try {
      return this.xmlhttp.getResponseHeader(header);
   }
   catch(e) {
      throw new ErrorType(
        "getResponseHeader('"+header+"') failed", 1001,e);
   }
};



/**
  @param     
  @returns   
  @throws 1002: XMLHttpRequestWrapper::getResponseText
*/
XMLHttpRequestWrapper.prototype.getResponseText=function() {
   try {
      return this.xmlhttp.responseText;
   }
   catch(e) {
      throw new ErrorType("getResponseText failed", 1002,e);
   }
};


/**
  @param     
  @returns   
  @throws 1003: XMLHttpRequestWrapper::getRresponseXML
*/
XMLHttpRequestWrapper.prototype.getRresponseXML=function() {
   try {
      return this.xmlhttp.responseXML;
   }
   catch(e) {
      throw new ErrorType("getRresponseXML failed", 1003,e);
   }
};


/**
   @param  method must be a method supported by the server.
   Supported methods: GET, POST, HEAD, PUT, DELETE, OPTIONS etc
   @param url
   @param async Whether the request is synchronous or asynchronous,
   i.e. whether send returns only after the response is received or if
   it returns immediately after sending the request. In the latter
   case, notification of completion is sent through
   onreadystatechange.
   @param user optional user name
   @param password optional user password


  @throws 1004: XMLHttpRequestWrapper::open
*/
XMLHttpRequestWrapper.prototype.open=function(method , url) {
   try {
      switch(arguments.length) {
         case 2:
         this.xmlhttp.open(method , url);
         break;
         case 3:
         this.xmlhttp.open(method , url, arguments[2]);
         break;
         default: /* Assume all 5 arguments */
         this.xmlhttp.open(method , url, arguments[2],
                           arguments[3], arguments[4]);
      }
   }
   catch(e) {
      throw new ErrorType("Failed: open url "+url+" :", 1004,e);
   }

};


/**
  @param data  
  @throws 1005: XMLHttpRequestWrapper::setRequestHeader
*/
XMLHttpRequestWrapper.prototype.setRequestHeader=function(header,value) {
   try {
      this.xmlhttp.setRequestHeader(header,value);
   }
   catch(e) {
      throw new ErrorType("setRequestHeader failed", 1005,e);
   }
};


/**
  @param data  
  @throws 1006: XMLHttpRequestWrapper::send
*/
XMLHttpRequestWrapper.prototype.send=function(data) {
   try {
      this.xmlhttp.send(data);
      try { if(this.xmlhttp.status) this.status = this.xmlhttp.status; }
      catch(e) {}
   }
   catch(e) {
      throw new ErrorType("send failed", 1006,e);
   }
};


/**

*/
XMLHttpRequestWrapper.prototype.abort=function() {
   try {
      this.xmlhttp.abort();
   }
   catch(e) {}
};


function JRpc(url, a, bindowsMode)
{
   this.bimode = bindowsMode == true ? true : false;
   this.$url=url;
   var httpR = new XMLHttpRequestWrapper();

   if(a &&
      (typeof(a)=="function" ||
       (typeof(a)=="object" && typeof(a.onResponse)=="function"))) {
      var r={
         rpc:this,
         a:a,
         onResponse:function(s, r) {
            delete this.rpc.$noCheck;
            if(s) {
               var p = r.procs;
               for(var i = 0; i < p.length; i++) this.rpc.$addMethod(p[i]);
               JRpc.$execResponse(this.a, true);
            }
            else {
               JRpc.$execResponse(this.a, false, r);
            }
         }
      };
      this.$noCheck=true;
      this.$send("system.describe",r);
   }
   else if(a == undefined || a == true)
   {
      var procs = this.$send("system.describe").procs;
      for(var i = 0; i < procs.length; i++)
         this.$addMethod(procs[i]);
   }
};

JRpc.$execResponse = function(r, s, d, x)
{
   if(typeof(r)=="object") r.onResponse(s,d,x);
   else r(s,d,x);
};


JRpc.prototype.$mkRpcMethod = function(method, func)
{
   var obj = this;
   var names = method.split(".");
   for(var n=0; n < names.length-1 ; n++)
   {
      var name = names[n];
      if(obj[name])
         obj = obj[name];
      else
      {
         obj[name]  = new Object();
         obj = obj[name];
      }
   } 
   obj[names[n]]=func;
};


JRpc.prototype.$addMethod = function(method)
{
   var obj=this;
   this.$mkRpcMethod(method,(function(){return obj.$call(method,arguments);}));
};


JRpc.prototype.$call = function(name, oargs)
{
   var args;
   var respObj;
   if(oargs.length)
   {
      var n = 0;
      var resp=oargs[0];
      if(typeof(resp)=="function" ||
         (typeof resp == "object" &&
          typeof resp.onResponse == "function"))
      {
         respObj=resp;
         n = 1;
      }
      if(oargs.length > n)
      {
         var j;
         var i = n;
         args=[];
         for(j = 0 ; i < oargs.length ; j++,i++) args[j]=oargs[i];
      }
   }
   return this.$rpc(name, respObj, args);
};

JRpc.prototype.$checkRpcResp = function(resp)
{
   if(resp.error)
   {
      var e = new ErrorType("Server error", 2000, resp.error);
      try {
         e.message=resp.error.message;
         e.code=resp.error.code;
         e.error=resp.error.error;
      }
      catch(e) {}
      throw e;
   }
   return resp.result;
};


JRpc.prototype.$rpc = function(name, respObj, args)
{
   var resp = this.$send(name, respObj, args);
   if(respObj) return;
   return this.$checkRpcResp(resp);
};


JRpc.prototype.$onreadystatechange=function(readyState)
{ // The 'this' object is of type XMLHttpRequestWrapper
   if(readyState == 4)
   {
      var respObj=this.$respObj;
      if(this.status == 200)
      {
         var resp;
         var status;
         try {
            if(this.$rpc.bimode)
               resp = BiJson.deserialize(this.getResponseText());
            else
               resp = JSON.parse(this.getResponseText());
            if(!resp) throw new ErrorType("Cannot parse", 2002, 0);
            var rpc=this.$rpc;
            if( ! rpc.$noCheck )
               resp = rpc.$checkRpcResp(resp);
            status=true;
         }
         catch(e) {
            resp = e;
         }
         try {
            if(status)
               JRpc.$execResponse(respObj, true, resp);
            else
               JRpc.$execResponse(respObj, false, resp, 200);
         }
         catch(e) { alert(e); }
      }
      else
      {
          if( ! this.$exception.message )
              this.$exception.message = "RPC failed: " + this.status;
          try {
            this.$exception.status = this.status;
            JRpc.$execResponse(respObj, false, this.$exception, this.status);
         }
         catch(e) { alert(e); }
      }
   }
};


JRpc.prototype.$send = function(name, respObj, args)
{
   var resp;
   try {
      var m = '{"version":"1.1","method":"'+name+'"';
      if(args) {
         if(this.bimode)
            m = m + ',"params":' + BiJson.serialize(args);
         else
            m = m + ',"params":' + JSON.stringify(args);
      }
      m = m + '}';
      var httpR = new XMLHttpRequestWrapper();
      
      if(respObj)
      {
         httpR.onreadystatechange = JRpc.prototype.$onreadystatechange;
         httpR.$respObj=respObj;
         httpR.$rpc=this;
         httpR.open("POST", this.$url);
      }
      else {
         httpR.open("POST", this.$url, false);
      }
      httpR.setRequestHeader("Content-Type","application/json");
      httpR.setRequestHeader("PrefAuth","digest");
      httpR.send(m);
      if(respObj) return; /* Asynch call */
      /* A blocking RPC call */
      if(httpR.status && httpR.status != 200)
      {
         throw "HTTP status "+httpR.status;
      }
      if(this.bimode)
         resp = BiJson.deserialize(httpR.getResponseText());
      else
         resp = JSON.parse(httpR.getResponseText());
      if(!resp) throw "Cannot parse JSON server response";
   }
   catch(e) {
      e = new ErrorType("Calling "+name+" failed", 2004, e);
      try { e.status = httpR.status; }
      catch(ex) {}
      throw e;
   }
   return resp;
};

   
JRpc.prototype._call = function(name)
{
   var args;
   var respObj;
   if(arguments.length > 1)
   {
      var n = 1;
      if(typeof arguments[1] == "object" &&
         typeof arguments[1].onResponse == "function")
      {
         respObj=arguments[1];
         n = 2;
      }
      if(arguments.length > n)
      {
         args=[];
         var j;
         var i = n;
         for(j=0; i < arguments.length ; j++,i++) args[j]=arguments[i];
      }
   }
   return this.$rpc(name, respObj, args);
};
 
