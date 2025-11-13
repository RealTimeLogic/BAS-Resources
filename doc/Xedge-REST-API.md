## Draft

# Xedge File REST API

The Xedge IDE uses the built-in Web File Server (WFS) to read and update application files.  This API is also available to external tools that authenticate the same way as the IDE (session cookie or HTTP authentication).  Requests target resources beneath `/rtl/apps/`, where the first path segment selects an IO root or installed app and the remainder is the file path inside that root.【F:src/xedge/assets/xedge.js†L586-L615】

For JSON-formatted success and error payloads on write operations, send the header `X-Requested-With: XMLHttpRequest`.  The IDE always does this through its jQuery helper and the server switches to JSON responses when that header is present.【F:src/core/.lua/wfs.lua†L576-L585】【F:src/core/.lua/wfs.lua†L150-L169】

## Operations

### `HEAD /rtl/apps/{io-root}/{path}`
Retrieves metadata without downloading the file.  The IDE uses this to verify the MIME type and size before fetching editor content.【F:src/xedge/assets/xedge.js†L791-L827】

**Response**
- `200 OK` with `Content-Length` (0 for directories) and `Content-Type` derived from the file extension.  Directories include the header `BaIsDir: true`; all responses include `HttpResMgr` and `Etag` headers for cache-aware clients.【F:src/core/.lua/wfs.lua†L589-L605】
- `404 Not Found` if the file does not exist.【F:src/core/.lua/wfs.lua†L589-L595】
- `401 Unauthorized` if authentication is required.

### `GET /rtl/apps/{io-root}/{path}`
Downloads the selected resource.  The IDE issues a plain GET for editable files after the HEAD check.【F:src/xedge/assets/xedge.js†L818-L824】  Directory GET requests accept the query parameter `cmd` for Web File Server commands such as `cmd=lj` (list JSON) that populate the file tree.【F:src/xedge/assets/xedge.js†L618-L643】

**Response**
- Files stream their raw content with a MIME type inferred from the extension.  Supplying the query parameter `download=1` forces a `Content-Disposition` attachment header.【F:src/core/.lua/wfs.lua†L607-L624】
- Directories run the requested WFS command and respond with JSON (for AJAX callers) or HTML, depending on the command.
- Errors return JSON objects `{"err": "code", "emsg": "message"}` for AJAX callers, or HTML error pages otherwise.【F:src/core/.lua/wfs.lua†L150-L208】

### `PUT /rtl/apps/{io-root}/{path}`
Creates or replaces the target file.  The IDE sends the editor contents in the request body with no transformation (`processData: false`) and lets the browser pick the `Content-Type`.【F:src/xedge/assets/xedge.js†L612-L615】

**Request body**
- Raw file data.  Text files should be UTF-8 encoded; binary files are accepted as-is.

**Response**
- On success, the server returns `{"ok": true}` to AJAX callers.【F:src/core/.lua/wfs.lua†L576-L585】【F:src/core/.lua/wfs.lua†L150-L169】
- Failures emit JSON errors `{"err": "code", "emsg": "message"}` detailing the reason (invalid name, permission denied, out of space, etc.).【F:src/core/.lua/wfs.lua†L170-L208】
- The server enforces existing WebDAV locks before accepting the upload.【F:src/core/.lua/wfs.lua†L576-L585】

## `.xlua` hot-reload behavior
When a `.xlua` script is saved through this API while its owning app is running, closing the write handle automatically reloads the script by invoking `manageXLuaFile`.  This mirrors the IDE's "Save & Run" behavior for Lua automation files.【F:src/core/.lua/wfs.lua†L556-L568】【F:src/xedge/.lua/xedge.lua†L530-L568】

## Example sequence
1. `HEAD /rtl/apps/myapp/myfile.xlua` – confirm the file is below 100 KB and text-based.
2. `GET /rtl/apps/myapp/myfile.xlua` – fetch the current source to present in an editor.
3. `PUT /rtl/apps/myapp/myfile.xlua` with the updated script in the body and the header `X-Requested-With: XMLHttpRequest` – the server stores the file, responds with `{ "ok": true }`, and restarts the script if `myapp` is running.

Clients can reuse these operations for any other file types under `/rtl/apps/`, combining them with the directory commands (e.g., `cmd=lj`, `cmd=mkdirt`, `cmd=rmt`) when they need to browse, create, or delete resources.


# Xedge Editor REST API

- The Xedge IDE front end interacts with the backend by issuing AJAX requests to `private/command.lsp` , always including a `cmd` field that selects a handler from the backend `commands` table; additional data fields are sent alongside as query parameters or form data, and responses are expected in JSON unless otherwise noted.

- On the server, `xedge.command` rejects cross-site callers, parses the request body, dispatches to `commands[cmd]` , and falls back to returning `{err: "Unknown command"}` for unsupported operations.


## Command reference

### `acme`

Handles certificate provisioning via nested `acmd` actions; the front end supplies `acmd` in addition to standard parameters.

- `acmd=isreg` : no extra fields; returns ACME registration status ( `isreg` ), WAN address, socket name, suggested device name, portal URL, and reverse-connection status, all wrapped in `{ok:true,...}` .

- `acmd=available` : requires `name` ; returns `{ok:true, available:<bool>}` to indicate whether the device name is available.

- `acmd=auto` : accepts `revcon` ( `"true"` / `"false"` ) and, when registering, `email` and `name` . Updates stored reverse-connection preference, optionally registers/renews with ACME, and responds `{ok:true}` or `{ok:false, err}` on validation failure.


### `getconfig`

No inputs. Returns `{ok:true, config:<base64url JSON>}` holding serialized app configuration. The UI stores this in localStorage when persistent storage is unavailable.

### `getionames`

Optionally accepts `xedgeconfig` (browser-stored configuration blob). When running without disk config, the backend uses it to initialize apps, then returns `{ok:true, ios:[...], nodisk:<bool>}` to enumerate known I/O roots and note disk availability.

### `getappsstat`

No parameters. Responds `{ok:true, apps:{<appName>:<runningBool>,...}}` , allowing the UI to mark running apps in the tree.

### `gethost`

No parameters. Returns `{ok:true, ip:<host-address>}` so the UI can prefill NET IO app URLs.

### `getintro`

No parameters. Loads `.lua/intro.html` and returns `{ok:true, intro:<html>}` for the welcome editor when no apps exist.

### `getmac`

No parameters. Default implementation responds `{ok:false}` and is intended to be overridden by plugins to return `{ok:true, mac}` used when suggesting certificate names.

### `gettemplate`

Requires `ext` (file extension). Returns `{ok:true, data:<template-content>}` , falling back to a newline if no template exists; used when creating new files.

### `credentials`

- Without `name` : returns `{ok:true, data:{name:<firstUserOrEmpty>}}` so the UI can populate the authentication dialog.

- With `name` and `pwd` : stores a hashed password (or deletes the user when `pwd` is empty), persists config, reinstalls authentication, and responds `{ok:true}` followed by the standard data payload for convenience.


### `pn2url`

Requires `fn` (path). When the referenced app is running and exposes an LSP endpoint ( `dirname` or `domainname` configured), returns `{ok:true, url:<http-path>}` ; otherwise responds `{err:<message>}` explaining the failure (app missing, not running, or LSP disabled).

### `pn2info`

Requires `fn` . For app-owned paths, returns `{ok:true, isapp:true, running:<bool>, lsp:<bool>, url:<optional launch URL>}` ; for non-app resources, it still returns `{ok:true}` so callers can enable/disable UI actions without error handling.

### `run`

Requires `fn` . When the owning app is running, triggers `manageXLuaFile` to execute `.xlua` scripts, then returns `{ok:true}` . No additional output.

### `smtp`

- Retrieval (no payload): merges stored SMTP credentials with email-log settings and returns them together in the response object (including `ok:true` ).

- Update: expects trimmed fields `email` , `server` , `port` , `user` , `password` , `connsec` . If the configuration changes, the backend optionally sends a test email (requiring non-empty server/user/password/email and numeric port) and persists the settings. Responses include `{ok:true}` on success or `{ok:false, err}` when the mail test fails.


### `openid`

- Retrieval (empty payload): returns `{ok:true, data:<storedOpenIDConfig or {}>}` for the UI dialog.

- Update: accepts `tenant` , `client_id` , `client_secret` (empty `client_secret` removes it). Validates via `ms-sso` , updates the stored OpenID settings, and reinstalls authentication. On validation error it returns `{ok:false, err}` (with `desc` when available).


### `elog`

Requires numeric `maxbuf` and `maxtime` , plus `enablelog` and optional `subject` . Updates email-log limits and subject (defaulting to "Xedge Log") and replies `{ok:true}` when the numeric conversion succeeds.

### `execLua`

Requires `code` (Lua source). Compiles and executes the code asynchronously; on success responds `{ok:true}` , otherwise logs the error and returns `{ok:false, err:<message>}` .

### `lsPlugins`

No inputs. Returns a JSON array of plugin filenames so the front end can dynamically load additional scripts.

### `getPlugin`

Requires `name` (must end in `.js` ). Streams the plugin file if found; otherwise emits HTTP 404. This endpoint writes raw content and aborts the normal JSON response pipeline, so callers should expect JavaScript, not JSON.

### `startApp`

Expects `name` pointing to an uploaded ZIP under the active storage ( `disk` or `home` ) and optional `deploy` ( `"false"` to unpack into a directory). The backend opens the ZIP, optionally expands it to a directory, executes the app's `.config` (capturing optional `name` , `autostart` , `dirname` , `domainname` , `startprio` , and lifecycle hooks), and either installs a new app or upgrades an existing one. Responses include:

- `ok` : success indicator ( `false` when the ZIP can't be opened or unpacked),

- `upgrade` : `true` when an existing app was replaced,

- `err` : error message when `ok=false` ,

- `info` : hook-returned details (empty string by default).


### Default error handling

If no handler is found, the backend logs and returns `{err:"Unknown command '<name>'"}` ; the front end surfaces errors via `jsonReq` , triggering login on 401 responses or displaying the message. This applies to all commands above.

