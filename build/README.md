# Build Scripts


- mako.cmd - Build mako.zip (Windows)
- mako.sh - Build mako.zip (Linux)

- Xedge.cmd - Build Xedge (Windows)
- Xedge.sh - Build Xedge (Linux)
- XedgeMako.cmd - Build the Xedge Mako Server app


## Build Script Options

You will be prompted to select several options when you run the build scripts. Below is a detailed explanation of each option to help you make an informed decision.

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

### 4. **Include Optional Components?**

- **What It Does**: The build process can include additional Lua modules if they are available on your system.
- **Optional Plugins**:
  - **lua-protobuf**: Adds Protocol Buffers support. This module is required when using MQTT Sparkplug.
  - **LPeg**: Adds pattern matching support for Lua.
- **Details**: These optional components are included by default in the pre-compiled binaries we provide.

---

### Notes
- Refer to the build script source for advanced customization to tweak configurations further.
- Ensure you meet all dependencies (like Node.js for minification) before running the scripts.
