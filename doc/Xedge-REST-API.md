# Xedge REST and Browser Plugin API

Status: Draft

This document describes the Xedge interface. The implementation is split
between:

- the Web File Server (WFS) mounted at `/rtl/apps/`, used for files and folders;
- the Xedge command endpoint at `/rtl/private/command.lsp`, used for IDE and
  application-management operations; and
- the browser and Lua plugin APIs, used to extend Xedge without modifying its
  core UI or command dispatcher.

The relevant implementation files are `src/core/.lua/wfs.lua`,
`src/xedge/.lua/xedge.lua`, `src/xedge/private/command.lsp`, and
`src/xedge/assets/xedge.js`.

## Common request conventions

- Clients authenticate the same way as the Xedge UI: a session cookie or HTTP
  authentication.
- Requests to `private/command.lsp` must include
  `X-Requested-With: XMLHttpRequest`. A request without this header receives
  `404 Not Found`.
- WFS mutation requests should include the same header to select JSON success
  and error responses.
- The Xedge browser client uses `fetch()` and `URLSearchParams`. Normal command
  requests are GET requests with URL-encoded query parameters. WFS POST commands
  use URL-encoded form data. File PUT requests carry the raw file contents.
- A `401 Unauthorized` response causes the Xedge client to open its login UI and
  retry the original request after successful authentication.
- `private/command.lsp` rejects requests whose `Sec-Fetch-Site` header is
  `cross-site`.

## Xedge file API

### Resource paths

File requests use this form:

```text
/rtl/apps/{io-or-app-name}/{path}
```

The first path segment selects an Xedge I/O root or installed application. The
remaining segments identify a resource inside that root. Encode individual path
segments when constructing a URL; do not encode `/` separators.

### HTTP methods

#### `HEAD /rtl/apps/{io}/{path}`

Returns metadata without downloading the resource.

- `200 OK` includes `Content-Length`, `HttpResMgr: V2.1`, and `Etag`.
- A directory has `Content-Length: 0` and `BaIsDir: true`.
- A file has a content type inferred from its extension.
- A missing resource returns `404 Not Found`.

The Xedge editor uses HEAD to reject directories, unsupported types, and files
that are too large before issuing GET.

#### `GET /rtl/apps/{io}/{file}`

Streams the file contents. Add `download=1` to request an attachment response.

#### `GET /rtl/apps/{io}/{directory}/`

With `cmd`, executes one of the JSON directory commands below. Without `cmd`,
the Xedge WFS mount serves the standalone SPA Web File Manager. The directory
command API itself never generates the old Web File Manager HTML.

#### `PUT /rtl/apps/{io}/{file}`

Creates or replaces a file using the raw request body. An empty body creates an
empty file. Existing WebDAV locks and authorization rules are enforced.

With `X-Requested-With`, success is:

```json
{"ok":true}
```

#### `POST /rtl/apps/{io}/{path}`

A URL-encoded request executes a directory command. A multipart request is
handled as an upload.

#### `DELETE /rtl/apps/{io}/{path}`

Deletes a file or recursively deletes a directory. Authorization and locks are
checked for each affected resource.

### Directory commands

Commands are supplied through the `cmd` parameter. Directory URLs should end in
`/`.

| Command | Method | Parameters | Response |
| --- | --- | --- | --- |
| `lj` | GET | none | JSON array of directory entries |
| `mkdirt` | POST | `dir` | `{"ok":true}` |
| `mv` | GET | `from`, `to` | `{"ok":true}` |
| `rmt` | POST | `file` | `{"ok":true}` |
| `sesuri` | GET | none | `{"uri":"...","tmo":seconds}` |
| `getlock` | GET | `name` | Lock owner/time or `{"notlocked":true}` |
| `getlocks` | GET | repeated `n` | `{"files":[...]}` |
| `lock` | POST | repeated `n`, Unix expiration `time` | `{"ok":true}` |
| `unlock` | POST | repeated `n` | `{"ok":true}` |

`mv` is the legacy NetIo-compatible rename/move command. `from` is relative to
the requested directory. `to` is a destination path prefixed by the WFS base
URI, such as `/rtl/apps/disk/new/path.txt`.

`rmt` is retained for compatibility. New clients may use DELETE directly.

The `lj` response is an array with one object per resource:

```json
[
  {"n":"main.xlua","s":421,"t":1785657600},
  {"n":"www","s":-1,"t":1785657600}
]
```

The compatibility fields are:

- `n`: resource name;
- `s`: file size in bytes, or `-1` for a directory; and
- `t`: modification time.

These fields must not change because other clients, including NetIo, consume
them. Future versions may add fields. If session URLs are available, the `lj`
response also includes `BaWfsSes: 1`. For a file session URL, request `sesuri`
from its parent directory and append the encoded file name to the returned URI.

`getlocks` returns entries shaped as `{"n":"name","l":false}` or
`{"n":"name","l":"owner"}`. `getlock` returns
`{"owner":"name","time":unixTime}` when locked.

### WFS errors

JSON errors use this shape:

```json
{"err":"noaccess","emsg":"Cannot delete file: No file system access."}
```

Common status mappings are:

- `400`: invalid command or name;
- `403`: authorization or lock failure;
- `404`: resource not found;
- `405`: destination already exists;
- `409`: missing path or non-empty directory;
- `503`: storage or capacity failure.

### `.xlua` hot reload

When a running application's `.xlua` file is replaced through WFS, closing the
write handle invokes Xedge's `manageXLuaFile` flow so the program is reloaded.

## Xedge command API

### Endpoint

```text
GET /rtl/private/command.lsp?cmd={command}&...
```

Unless noted otherwise, parameters are URL-encoded strings and responses are
JSON. A successful response normally contains `ok: true`. Some discovery
commands intentionally return an array instead of an object.

An unknown command returns:

```json
{"err":"Unknown command 'name'"}
```

The native Xedge request wrapper treats a non-2xx HTTP response, `err`, or
`emsg` as failure. Its callback receives the response on success and `false` on
failure. Authentication failures are retried after login.

### Built-in commands

#### `acme`

Certificate management selected by `acmd`:

- `isreg`: returns registration status, email/name when known, WAN and socket
  addresses, portal URL, and reverse-connection state.
- `available`: requires `name`; returns `available`.
- `auto`: accepts `revcon` and, for registration, `email` and `name`; returns
  `ok` or an error.

#### `getconfig`

Returns `config`, a base64url-encoded JSON object containing application
configuration. This supports browser persistence when disk configuration is
unavailable.

#### `getionames`

Accepts optional `xedgeconfig`. Returns:

```json
{"ok":true,"ios":["disk","home","net"],"nodisk":false}
```

During startup this command also establishes the authentication boundary before
the client creates its tree and loads plugins.

#### `getappsstat`

Returns `apps`, an object mapping application names to running booleans.

#### `gethost`

Returns the request host address as `ip` for NET IO application setup.

#### `getintro`

Returns the welcome-page HTML in `intro`.

#### `getmac`

The default implementation returns `{"ok":false}`. A platform plugin may
override it and return `{"ok":true,"mac":"..."}`.

#### `gettemplate`

Requires `ext`. Returns the matching new-file template as `data`, or a newline
when no template exists.

#### `credentials`

- With no `name`, returns `data.name`, the first configured user or an empty
  string.
- With `name` and `pwd`, creates or updates the user's digest credential. An
  empty password removes the user. The update response is `{"ok":true}`.

#### `pn2url`

Requires `fn`. Returns the launch URL for a running LSP-enabled application, or
`err` when the application is missing, stopped, or not LSP-enabled.

#### `pn2info`

Requires `fn`. For application resources, returns `isapp`, `running`, `lsp`,
and an optional `url`. For non-application resources it returns `{"ok":true}`.

#### `run`

Requires `fn`. Runs a selected `.xlua` resource when its owning application is
running and returns `{"ok":true}`.

#### `smtp`

- With no fields other than `cmd`, returns SMTP and email-log configuration.
- With `email`, `server`, `port`, `user`, `password`, and `connsec`, validates
  and stores SMTP settings. Complete settings trigger a test email; incomplete
  settings disable SMTP.

#### `openid`

- With no fields other than `cmd`, returns stored OpenID configuration in
  `data`.
- With `tenant`, `client_id`, and `client_secret`, validates and stores the
  configuration. An empty `client_secret` removes the secret.

#### `elog`

Requires integer `maxbuf` and `maxtime`, `enablelog`, and optional `subject`.
Stores email-log settings and returns `{"ok":true}`.

#### `execLua`

Requires `code`. Compiles the Lua source and schedules it asynchronously. A
compile failure returns `{"ok":false,"err":"..."}`.

#### `lsPlugins`

Returns an alphabetically sorted JSON array containing client plugin paths.

#### `getPlugin`

Requires a `.js` `name` returned by `lsPlugins`. Streams JavaScript rather than
JSON and returns 404 when the plugin is unavailable. The native client requests
plugins with `cache: "no-store"` and executes them sequentially in the returned
order.

#### `startApp`

Requires `name`, the uploaded ZIP name under `home` on Mako or `disk` on
standalone Xedge. `deploy=false` unpacks the ZIP into developer mode; other
values retain deployed ZIP mode.

The response contains:

- `ok`: installation success;
- `upgrade`: whether an existing deployed application was replaced;
- `info`: optional text returned by an install or upgrade hook; and
- `err`: failure details when `ok` is false.

### Plugin-defined commands

Lua plugins under `.lua/XedgePlugins` receive the command table and may add or
override handlers. Such commands are platform-specific and are not part of the
built-in list. For example, the application-update plugin adds the raw PUT
command `uploadfw`; Xedge32 plugins may add firmware and device commands.

A plugin handler is responsible for validating its method, headers, body, and
parameters, and for sending or aborting the response.

## Browser plugin API

Client plugins are classic scripts loaded after authentication, I/O discovery,
and tree initialization. The Xedge shell itself is an ES module, but it exposes
only this deliberate API on `window`:

| Name | Purpose |
| --- | --- |
| `el(tag, properties, ...children)` | Create a DOM element using native APIs |
| `ideCfgCB` | Array of callbacks used to add configuration-menu items |
| `log(...)` | Append normal output to TraceLogger |
| `logR(...)` | Append highlighted/error-style output without playing the error sound |
| `mkForm(description, elements?, parent?)` | Build a form and collect named elements |
| `createEditor(name, value, saveCallback, content?, closeCallback?)` | Open an editor or plugin panel |
| `closeEditor(id)` | Close an editor or plugin panel |
| `alertErr(...)` | Report an error through the Xedge error path |
| `sendCmd(command, callback, data?)` | Call `private/command.lsp` through the native request layer |
| `createTree()` | Rebuild the application/file tree after structural changes |

`el` recognizes the convenience properties `text` and `html`; other properties
are assigned to the DOM element when possible and otherwise become attributes.
Plugin code may also use normal modern-browser DOM APIs. It must not depend on
private variables inside the Xedge ES module.

Configuration plugins normally append a callback:

```js
ideCfgCB.push((menu, nodisk) => {
  const item = el("li", {text: "My Plugin"});
  item.onclick = () => createEditor("My Plugin", null, null, el("div", {text: "Ready"}));
  menu.append(item);
});
```

The callback receives the configuration-menu `<ul>` and the `nodisk` flag.
Plugins that mutate applications or files should call `createTree()` after the
server operation succeeds.

Browser and Lua plugins execute with Xedge management privileges. Treat plugin
files as trusted code, validate all external input on the server, and do not
expose secrets to browser plugins.
