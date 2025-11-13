# Xedge Web File REST API

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
