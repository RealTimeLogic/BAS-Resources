# BAS-Resources

The Barracuda App Server's resource files. See the [build directory](build/README.md) for build instructions.

## Files

- **core**
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
    - .lua
        - asyncresp.lua
        - loadconf.lua
        - log.lua
        - noapp.lua
        - rwfile.lua
        - psatpm.lua - Shared PSA TPM implementation; selected at build time for standalone Xedge
        - seed.lua
        - sqlutil.lua

- **xedge** - [Xedge](https://realtimelogic.com/ba/doc/en/Xedge.html)'s client and server code
    - .config -- Xedge standalone
    - .preload -- Xedge for Mako Server
    - index.html
    - README.md
    - .lua
        - 404.html
        - intro.html
        - ms-sso.lua
        - rwfile.lua
        - tpm.lua - Default softTPM startup and named-key API; replaced in PSA packages
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


## Documents

### TPM and default TLS identity

Mako and standalone Xedge use [softTPM](https://realtimelogic.com/ba/doc/en/SoftTPM.html)
by default. Custom builds can use protected persistent keys through
[PSA Crypto](https://realtimelogic.com/ba/doc/en/C/reference/html/PSAIntegration.html) while retaining the
[Lua TPM API](https://realtimelogic.com/ba/doc/en/lua/auxlua.html#TPM).
See [build-time resource selection](build/README.md#psa-resources).
Trusted PSA initialization sets `ba.psa=true` before validating the roots;
missing or incompatible roots are fatal, without a softTPM fallback.

Both hosts generate their default self-signed certificate using a named TPM
key. There are no bundled Mako/Xedge default private keys or leaf certificates.
Configured certificates and ACME remain supported; clients must explicitly
trust a self-signed identity. Keep the shared core `.certificate/cacert.shark`:
it is a CA trust store for outbound TLS, not a default server identity.

Standalone Xedge deliberately encrypts `xcfg.bin` with a global configuration
key so devices in the same OEM trust domain can share configuration. PSA uses
`SHA256(ba.tpm.globalkey("xedge.config",64))`; the OEM must provision the same
global root value and match derivation settings on those devices. Choosing two
independent device-specific roots keeps the same Lua code but makes the file
device-specific. The softTPM
formula remains unchanged. Xedge hosted in Mako keeps its device-bound
`uniquekey` policy. See [provisioning and migration](https://realtimelogic.com/ba/doc/en/C/reference/html/PSAIntegration.html#psa-xedge-config).
Copying configuration never substitutes for retaining the PSA signing keys.


[doc](doc/)


### Xedge REST API

[Xedge REST API](doc/Xedge-REST-API.md)

### ACME client

The shared Mako Server and Xedge Automatic Certificate Management Environment
(ACME) client is under `src/core/.lua/acme/`, with host adapters in `src/mako/`
and `src/xedge/`.

- [ACME client public API](https://realtimelogic.com/ba/doc/en/lua/acme.html)
- [ACME client architecture](doc/acme-client-architecture.md)
- [Maintainer and session handover](AGENTS.md)




## mkCaCert.sh

```
# Creates rtl/.certificate/cacert.shark from curl's cacert.pem
wget https://curl.se/ca/cacert.pem
SharkSSLParseCAList -b cacert.shark cacert.pem
rm -f cacert.pem
```
