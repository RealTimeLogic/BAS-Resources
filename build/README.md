# Build Scripts


- mako.cmd - Build mako.zip (Windows)
- mako.sh - Build mako.zip (Linux)

- Xedge.cmd - Build standalone Xedge.zip and XedgeZip.c (Windows)
- Xedge.sh - Build standalone Xedge.zip and XedgeZip.c (Linux)
- XedgeMako.cmd/XedgeMako.sh - Build Xedge.zip for loading as a Mako Server app

Run shell scripts from this `build/` directory. Both Xedge builders write
`Xedge.zip`, but the packages serve different hosts. The standalone package
includes shared core resources; the Mako application uses those resources,
including ACME, from the matching `mako.zip`. Building ZIP resources does not
compile the Mako or Xedge native executable.

## Download Pre-Built Packages

- [Xedge.zip](https://makoserver.net/download/packages/Xedge.zip) - the Mako Server edition
- [mako.zip](https://makoserver.net/download/packages/mako.zip) - the [developer edition](https://makoserver.net/documentation/developer-package/)


## Required and Optional Tools

The following is a list of required and optional tools the build
scripts use. Make sure the following tools are available in your
system's PATH.

- **curl and SharkSSLParseCAList:** Required by the standalone Xedge builder
  for certificate-store generation. The Windows script checks both at startup.
- **zip:** Required for the build scripts to package resources into a
  zip file.
- **bin2c:** The
  [bin2c tool](https://realtimelogic.com/downloads/bin2c/) converts
  the zip file into a C array, which is necessary for building the
  Xedge resource files. Executables for Windows and 64-bit Linux are
  included in the repository. To compile from source, use: gcc -o
  bin2c [BAS](https://github.com/RealTimeLogic/BAS)/tools/bin2c.c
- **Node.js and npm (optional):** The build scripts can use these
  tools to compress some resources, making the produced zip file
  smaller.


## Build Script Options

The standalone Xedge builder prompts for OPC UA, the certificate store, and
minification. The Mako and Xedge-on-Mako builders prompt for minification; they
do not offer all standalone options. The Mako package includes the OPC UA Lua
resources. Native support still depends on the executable.

For unattended Windows builds, set `MinifyMakoZip=yes|no` for `mako.cmd` or
`MinifyXedgeZip=yes|no` for either Xedge builder. `Xedge.cmd` also accepts
`IncludeOpcUa=yes|no`, `XedgeCaStore=large|small`, and `NO_BIN2C` (any nonempty
value skips C-array generation). These are Windows batch options; consult the
shell scripts for their supported environment variables.

### PSA resources

The default is softTPM. For standalone PSA Xedge, set environment variable
`SHARKSSL_PSA_CONSUMER=1` before running `Xedge.cmd` or `Xedge.sh`. The builder
replaces staged `.lua/tpm.lua` with Mako's `psatpm.lua`; unset or `0` keeps
the softTPM. `.config` loads the same path in both builds without runtime
backend selection.

Match the package to a native build compiled with `SHARKSSL_PSA_CONSUMER=1`
and linked to the target's PSA provider. The environment option above only
selects resources; it does not configure the C compiler, include paths,
provider libraries, or persistent storage. Follow the generic
[PSA integration guide](https://realtimelogic.com/ba/doc/en/C/reference/html/PSAIntegration.html) for those requirements and OEM root
provisioning. The provider must support standard SP 800-108 counter HMAC-SHA-256
and direct AES-256-GCM key output from the two persistent roots. Choose a shared
family global root for transferable data, or two independent device-specific
roots. Existing PBKDF2-root stores require data recovery or a deliberate reset
before switching. The standard native makefiles do not provide a universal
provider-selection command.

The Mako builders always package `.lua/psatpm.lua`. PSA Mako loads it from
`.openports`; non-PSA Mako retains its existing softTPM startup. PSA Mako and
standalone Xedge exclude embedded softTPM secrets and stop if PSA roots cannot
be initialized. Do not pair PSA resources with a non-PSA executable, or the
softTPM standalone package with a PSA executable.

`XedgeMako.cmd` and `XedgeMako.sh` build an application that inherits Mako's
initialized TPM and listeners. It must not initialize the PSA dispatcher a
second time. Neither package embeds production root values; provisioning and
key-store retention are platform responsibilities.

---

### 1. **Include OPC-UA Support?**

- **What It Does**: Includes the OPC-UA protocol stack, implemented in Lua, in the final ZIP file.
- **Requirement**: The Barracuda App Server C library **must be built with** the option 'USE_OPCUA=1' for OPC-UA functionality to work.
- **How to Select**:
  - Enter **Y** to include OPC-UA support.
  - Enter **N** to exclude it.

---

### 2. **Use Large 'cacert.shark' or Create a Minimal Certificate Store?**

- **What It Does**: Determines the certificate store used for validating TLS server certificates.
- **Options**:
  - **Large 'cacert.shark'**: Includes the [Curl CA bundle](https://curl.se/docs/sslcerts.html) with a comprehensive set of root certificates.
  - **Minimal Version**: Creates a much smaller certificate store with only the most common root certificates. This option is ideal for embedded systems with limited memory.
 **Details**:
 - For a list of root certificates included in the minimal version, refer to the build script.
 - If you're new to certificate stores, see the [Certificates for Embedded Systems](https://realtimelogic.com/articles/Certificate-Management-for-Embedded-Systems) tutorial for a quick overview.

---

### 3. **Minify JavaScript and CSS Files?**

- **What It Does**: Removes whitespace and compresses JavaScript (JS) and Cascading Style Sheets (CSS) files, reducing their size for optimized performance.
- **Requirement**: This option requires **Node.js** and **npm** to be installed on your system.

---

### 4. Optional Lua Resources

- The Mako and standalone Xedge scripts detect sibling source directories
  automatically; there is no optional-component prompt. These steps copy Lua
  support files and do not build or enable native modules.
- **Optional Plugins**:
  - **lua-protobuf**: Copies `protoc.lua`, `serpent.lua`, and the Sparkplug Lua
    resources when the directory is present. Protocol Buffers also requires
    the native module in the executable.
  - **LPeg**: Copies `re.lua`; the executable must provide native LPeg support.
- **Details**: These optional components are included by default in the pre-compiled binaries we provide.

---

### Notes
- Refer to the build script source for advanced customization to tweak configurations further.
- Ensure you meet all dependencies (like **zip**) before running the scripts.
