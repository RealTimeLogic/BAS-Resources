## Securing Xedge: Standalone and Mako Server Versions

[Xedge](https://realtimelogic.com/ba/doc/en/Xedge.html) can run as standalone
firmware or as a Mako Server application. Both use the host's named-key TPM
API: softTPM by default, or a compatible PSA Crypto provider in custom builds.
Key protection depends on correct platform setup, root custody, and application
access control. Start with the
[native security settings](https://realtimelogic.com/ba/examples/xedge/readme.html#security)
and [PSA integration guide](https://realtimelogic.com/ba/doc/en/C/reference/html/PSAIntegration.html).

### Standalone configuration

The build selects `.lua/tpm.lua`; PSA packages replace it with Mako's
`psatpm.lua`. `.config` does not select a backend at runtime.

PSA firmware must supply `int xedgeInitPsa(void)`. Xedge calls this platform
hook before resource verification and Lua creation; return `0` on success or
a nonzero error to stop startup. See the
[hook contract](https://realtimelogic.com/ba/doc/en/C/reference/html/PSAHowItWorks.html#psa-xedge-init).
Rebuild the host and resources together. During debugger restarts, `.config`
closes Xedge's listeners before Lua teardown; the provider and key store stay open.

Standalone Xedge deliberately uses a global key for AES-GCM encryption of
`xcfg.bin`, allowing configuration transfer within an OEM product trust domain.
softTPM retains `SHA256(gpkey)`. PSA uses
`SHA256(ba.tpm.globalkey("xedge.config",64))`. The OEM must securely provision
the same global root value and matching derivation settings on participating
devices. A common numeric root ID alone does not produce a common key.

With two independently generated device-specific PSA roots, the same Lua code
makes configuration device-specific. An OEM may also customize the call to
`uniquekey`. Changing roots, moving from the older PSA PBKDF2 derivation, or
switching softTPM/PSA requires a controlled migration or
configuration reset; no automatic software-decryption fallback is supplied.
Retain PSA signing keys separately: copying `xcfg.bin` does not transfer them.

### Xedge hosted in Mako

Build with `BAS-Resources/build/XedgeMako.cmd` or `XedgeMako.sh`, and use the
matching `mako.zip`. Xedge inherits Mako's TPM, listeners, and shared modules.
Its configuration key is derived with `ba.tpm.uniquekey(secret,64)` and SHA-256.
The `.preload` value named `secret` is a derivation label; it does not replace
the protected device root. Configuration remains device-bound with either
backend, assuming distinct device roots.

Protect code integrity with
[signed packages](https://realtimelogic.com/ba/doc/en/C/reference/html/SignEncZip.html)
and the native verification settings. Encrypting a derivation label is not a
substitute for protecting the root or controlling which Lua code may request
derivations. Keep the original device identity and derivation label through
updates when retaining encrypted configuration.

## Xedge internal data structure:
```
xedge:
  cfg:
    apps{}:
      k: "name"
      v:
        name="name" -- same name as 'k' - the IO name (ion)
        url="io/path" -- path is http://domain/fs/ if net
        running: true/false
        if LSP app:
        dirname: -- blank if root
        priority: number
  apps{}:
    k: "name"
    v: {io,env,dir,envs,pages} -- dir set for LSP apps
      env{}: -- page table _ENV for xlua files
       k: relative path (uri)
       v: table/env
      pages{}: -- page table for LSP. Not set if not an LSP app.
       k: relative path (uri)
       v: table/env
```

function xedge.init()

Called at startup by .config, Xedge4Mako.lua, or if no disk IO, from LSP page, which receives data from browser's local storage. The function initializes Xedge and starts all applications with active state 'running'.
