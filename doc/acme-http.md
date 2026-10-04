# ACME HTTP trust configuration

`acme/http` supplies shared connection defaults for the ACME engine, SharkTrust
JSON/HTTPS requests, address discovery and reverse connections. Configure it
before starting client runtimes. It does not change trust for unrelated HTTP
clients or replace `ba.sharkclient()`.

## Import a private CA

```lua
-- Provision this PEM through a trusted installation path, before starting ACME.
local store = ba.create.certstore()
assert(store:addcert(caPem)) -- caPem: string containing the trusted public CA PEM
require"acme/http".setCertStore(store)
```

`setCertStore(store)` is a module function, shared by all ACME instances in one
Lua VM. `store` is a `ba.create.certstore()` userdata, or `nil` to restore the
bundled trust supplied by `ba.sharkclient()`. There is no return value. The
function creates one client SharkSSL context and reuses it for new connections.
Invalid argument types or native construction errors propagate; if construction
throws, the previous context remains selected.

Add all root certificates before passing the store. Assembly makes the store
immutable. To change the roots, construct a new store and call the setter again.
The supplied roots **replace** the default set; they are not merged with
`cacert.shark`. Supply all required private/public roots when several services
share this configuration. Importing a root on the PC does not configure an
embedded device's HTTP client.

Existing HTTP clients and established reverse connections keep their existing
TLS contexts. Close the owning runtime, change the store, then recreate/start
the runtime to apply the change consistently. The module neither closes active
connections nor persists the root; the application owns provisioning and reload.
Certificate-chain and hostname validation remain enabled by the ACME callers.

```lua
-- After closing the runtime, restore public bundled trust before recreating it.
require"acme/http".setCertStore(nil)
```

## Connection factories

`create(options)` accepts an optional table with the native `httpc.create`
connection options and returns its HTTP client userdata, or `nil, errorCode`.
It copies the option table without modifying the caller's table. An explicit
`options.shark` SharkSSL userdata takes precedence over the shared context.
Other options, including existing native proxy options, pass through unchanged.
Native errors and exceptions are preserved. The caller owns closing the client.

`options(options)` returns a new connection-options table with the same default
and override rules. The DNS module uses it when constructing a reverse
connection. It does not create or close a connection. Both arguments named
`options` are optional tables, defaulting to an empty table; `shark` defaults to
the configured shared context, or the bundled context if no store is selected.

Central proxy configuration is not implemented. The shared module provides a
single place to add it later without changing every ACME caller.
