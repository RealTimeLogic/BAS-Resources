


Xedge internal data structure:
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
