# Build Scripts


- mako.cmd - Build mako.zip (Windows)
- mako.sh - Build mako.zip (Linux)

- Xedge.cmd - Build Xedge (Windows)
- Xedge.sh - Build Xedge (Linux)
- XedgeMako.cmd/XedgeMako.sh - Build the Xedge Mako Server app

## Required and Optional Tools

The following is a list of required and optional tools the build
scripts use. Make sure the following tools are available in your
system's PATH.

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

You will be prompted to select several options when you run the build
scripts. Below is a detailed explanation of each option to help you
make an informed decision.

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
- Ensure you meet all dependencies (like **zip**) before running the scripts.
