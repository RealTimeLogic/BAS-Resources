# BAS-Resources

The Barracuda App Server's resource files. See the [build directory](build/README.md) for build instructions.

## Files

- **core**
    - jquery.js - Jquery and a few additional libs assembled by [mkJquery.sh](#mkjquerysh)
    - smq.js
    - sha1.js - optionally used by [form authenticator](https://realtimelogic.com/ba/doc/en/lua/lua.html#sha1_login)
    - spark-md5.min.js optionally used by form authenticator
    - .certificate
        - cacert.shark - Used by function [ba.sharkclient](https://realtimelogic.com/ba/doc/en/lua/auxlua.html#ba_sharkclient); assembled by [mkCaCert.sh](#mkcacertsh)
    - .lua
        - http.lua - [Module HTTP](https://realtimelogic.com/ba/doc/en/lua/auxlua.html#http)
        - httpm.lua - [Module HTTPM](https://realtimelogic.com/ba/doc/en/lua/auxlua.html#managed)
        - JSONS.lua - [JSON Stream Parser Module](https://realtimelogic.com/ba/doc/en/lua/lua.html#JSONS)
        - jwt.lua - [JSON Web Token (JWT) Module](https://realtimelogic.com/ba/doc/en/lua/auxlua.html#ba_crypto_JWT)
        - mqttc.lua - [MQTT 5 Client](https://realtimelogic.com/ba/doc/en/lua/MQTT.html)
        - mqtt3c.lua - [MQTT 3.1.1 Client](https://realtimelogic.com/ba/doc/en/lua/MQTT3.html)
        - soap.lua and basoap.lua - [Module SOAP](https://realtimelogic.com/ba/doc/en/lua/soap.html)
        - socket.lua - Standard Lua socket portability module
        - wfs.lua - [Web File Server - server side](https://realtimelogic.com/ba/doc/en/lua/lua.html#ba_create_wfs)
        - xml2table.lua - callback table for [xparser (xml parser)](https://realtimelogic.com/ba/doc/en/lua/xparser.html)
        - xmlrpc.lua - [Module XML-RPC](https://realtimelogic.com/ba/doc/en/lua/xml-rpc.html)
    - modbus
        - client.lua - [Modbus Client](https://realtimelogic.com/ba/doc/en/lua/Modbus.html)
    - tracelogger - [TraceLogger](https://realtimelogic.com/ba/doc/en/lua/auxlua.html#tracelogger)
        - index.html - client implementation
    - SMQ - directory with [SMQ](https://realtimelogic.com/ba/doc/en/SMQ.html) server side code, including broker
    - wfm - directory with [Web File Server - client side](https://realtimelogic.com/ba/doc/en/lua/lua.html#ba_create_wfs)

- **opcua**
    - OPC-UA - directory with the [OPC-UA Client and Server](https://realtimelogic.com/ba/opcua/index.html) Lua code.

- **sparkplug** - [MQTT Sparkplug Library](https://github.com/RealTimeLogic/LSP-Examples/tree/master/Sparkplug)
    - sparkplug.lua - The library
    - sparkplug_b.proto - Sparkplug protobuf definition

- **mako** - The [Mako Server](https://realtimelogic.com/ba/doc/en/Mako.html)'s Lua implementation
    - .config - the Mako Server's core logic
    - .openports - Logic for opening the server's listening ports
    - noapp.shtml - sent to browser when no apps are loaded
    - .certificate - Default certificate used by Mako Server
        - MakoServer.key
        - MakoServer.pem
    - .lua
        - asyncresp.lua
        - loadconf.lua
        - log.lua
        - noapp.lua
        - rwfile.lua
        - seed.lua
        - sqlutil.lua

- **xedge** - [Xedge](https://realtimelogic.com/ba/doc/en/Xedge.html)'s client and server code
    - .config -- Xedge standalone
    - .preload -- Xedge for Mako Server
    - index.html
    - README.md
    - .certificate
        - device_RSA_2048.key
        - device_RSA_2048.pem
    - .lua
        - 404.html
        - intro.html
        - ms-sso.lua
        - rwfile.lua
        - xedge.lua
    - assets
        - tree.css
        - tree.js
        - xedge.css
        - xedge.js
    - login
        - index.lsp
    - private
        - command.lsp
    - templates
        - Various templates




## mkCaCert.sh

```
# Creates rtl/.certificate/cacert.shark from curl's cacert.pem
wget https://curl.se/ca/cacert.pem
SharkSSLParseCAList -b cacert.shark cacert.pem
rm -f cacert.pem 
```


## mkJquery.sh

```
# Shell script for fetching the latest jquery, tablesorter, and cookie
# plugin. These 3 files are concatenated together and put
# in core/jquery.js
export JQVER=3.7.0
function abort() {
    echo "Oops"
    sleep 5
    exit 1
}
mkdir tmp
cd tmp
wget https://code.jquery.com/jquery-$JQVER.min.js || abort
wget https://mottie.github.io/tablesorter/dist/js/jquery.tablesorter.min.js || abort
wget --no-check-certificate https://raw.githubusercontent.com/carhartl/jquery-cookie/master/src/jquery.cookie.js || abort
wget https://raw.githubusercontent.com/briceburg/jqModal/master/jqModal.js || abort
wget https://raw.githubusercontent.com/gaarf/jqDnR-touch/master/jqdnr.js || abort
mkdir out
echo "//cat: jquery + jquery.cookie + jquery.tablesorter + jqModal" >a.js
cat a.js >x.js
cat jquery-$JQVER.min.js >> x.js
echo "" >> x.js
cat out/jquery.cookie.js >> x.js
echo "" >> x.js
cat jquery.tablesorter.min.js >> x.js
echo "" >> x.js
cat out/jqModal.js >> x.js
echo "" >> x.js
cat out/jqdnr.js >> x.js

cp x.js ../core/jquery.js 
rm *.js
cd ..
rm -rf tmp
```
