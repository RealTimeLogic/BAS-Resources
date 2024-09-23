## Securing Xedge: Standalone and Mako Server Versions

The [Xedge development environment](https://realtimelogic.com/ba/doc/en/Xedge.html) can be built either as a **standalone version** or as a **Mako Server application**. Each version requires specific configurations to ensure optimal security. This guide outlines the steps needed to safeguard both versions effectively.

### Standalone Version Security

The standalone version of Xedge is secure as long as the [C code is properly configured](https://realtimelogic.com/ba/examples/xedge/readme.html#security).

### Mako Server Version Security

The Mako Server version uses a public secret, which you may consider encrypting to enhance security. To safeguard Xedge when using the Mako Server version, perform the following steps:

1. Start by reading [Signed and Encrypted ZIP files](https://realtimelogic.com/ba/doc/en/C/reference/html/SignEncZip.html) to understand the process.
2. **Modify the Secret**
  - Open BAS-Resources/src/xedge/.preload in a text editor.
  - Change the secret to a new, unique value to enhance security.
3. **Build xedge.zip**
  - Use the standard build script: BAS-Resources/build/XedgeMako.[cmd | sh].
  - This script creates the mako.zip file needed for deployment.
4. **Generate a Password**
  - Run the binpwd2str command-line tool to create a password.
  - This password will be used to encrypt the secret file.
5. **Encrypt the Secret File in xedge.zip**
  - Replace the .preload file in xedge.zip with an AES-encrypted version using the generated cleartext password.
  - Ensure that no other files in the ZIP archive are encrypted.
6. **Embed the Password into Mako Server**
  - Embed the binary version of the password into the Mako Server as explained on the [Mako Server page](https://realtimelogic.com/ba/examples/MakoServer/readme.html#security).
  - This allows the server to decrypt and access the encrypted secret file at runtime.
7. **Create an ECC Key Pair**
  - Generate an ECC public/private key pair following the [Signed and Encrypted ZIP files](https://realtimelogic.com/ba/doc/en/C/reference/html/SignEncZip.html) page instructions.
  - This key pair will be used to sign the ZIP files and verify their integrity.
8. **Sign the ZIP Files**
  - Use the private key to sign both xedge.zip and mako.zip.
  - Signing ensures that the files have not been tampered with.
9. **Embed the Public Key into Mako Server C Code**
  - Embed the public key into the Mako Server's C code as instructed on the [Mako Server page](https://realtimelogic.com/ba/examples/MakoServer/readme.html#security). This allows the server to verify the signatures of the ZIP files at runtime.
  - Compile the Mako Server C code



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
