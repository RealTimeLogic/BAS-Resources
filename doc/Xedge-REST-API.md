# Xedge REST and Browser Plugin API

This document describes the Xedge interface. The implementation is split
between:

- the Web File Server (WFS) mounted at `/rtl/apps/`, used for files and folders;
- the Xedge command endpoint at `/rtl/private/command.lsp`, used for IDE and
  application-management operations; and
- the browser and Lua plugin APIs, used to extend Xedge without modifying its
  core UI or command dispatcher.

The implementation is defined by [wfs.lua](../src/core/.lua/wfs.lua),
[xedge.lua](../src/xedge/.lua/xedge.lua), [command.lsp](../src/xedge/private/command.lsp),
and [xedge.js](../src/xedge/assets/xedge.js). This reference covers the shared
Xedge management interface; platform plugins extend it separately.

## Common request conventions

- Clients authenticate the same way as the Xedge UI: a session cookie or HTTP
  authentication when configured. An unconfigured installation may allow access
  without credentials; these endpoints do not provide a separate API-token scheme.
- Requests to `private/command.lsp` must include
  `X-Requested-With: XMLHttpRequest`. A request without this header receives
  `404 Not Found`. The handler checks header presence, not its value.
- WFS mutation requests should include the same header to select JSON success
  and error responses.
- The Xedge browser client uses `fetch()` and `URLSearchParams`. Normal command
  requests are GET requests with URL-encoded query parameters. WFS POST commands
  use URL-encoded form data. File PUT requests carry the raw file contents.
- A `401 Unauthorized` response causes the Xedge client to open its login UI and
  retry the original request after successful authentication.
- `private/command.lsp` rejects requests whose `Sec-Fetch-Site` header is
  `cross-site`, returning `404 Not Found`.

## Xedge file API

### Resource paths

File requests use this form:

```text
/rtl/apps/{io-or-app-name}/{path}
```

The first path segment is a string selecting an Xedge I/O root or installed application. The
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

Commands are supplied through the string `cmd` parameter. Directory URLs should end in
`/`. The methods below are client conventions: the directory dispatcher accepts
these commands through either GET or non-multipart POST. Parameters are strings
unless specified otherwise; repeated `n` parameters select multiple resources.

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

- **string n**: resource name;
- **number s**: file size in bytes, or `-1` for a directory; and
- **number t**: modification time as Unix seconds.

These fields must not change because other clients, including NetIo, consume
them. If session URLs are available, the `lj`
response also includes `BaWfsSes: 1`. For a file session URL, request `sesuri`
from its parent directory and append the encoded file name to the returned URI.

`getlocks` returns entries shaped as `{"n":"name","l":false}` or
`{"n":"name","l":"owner"}`. `getlock` returns
`{"owner":"name","time":unixTime}` when locked. Here `owner`, `n`, and a
locked `l` are strings; `time` is a number of Unix seconds; `notlocked` and an
unlocked `l` are booleans. `getlocks` omits directories and missing files.

`lock` ignores missing files, directories, already locked files, and expiration
times that are not in the future. Its `ok: true` does not confirm that every
requested file was locked. `unlock` also succeeds for files without a lock.
The `sesuri` result contains **string uri** and **number tmo** (seconds); `tmo`
is zero when no session URL was created.

### WFS errors

JSON errors contain **string err** (error code) and **string emsg** (description):

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

### Application Configuration Resources

Application configuration is exposed as a virtual `.appcfg` JSON resource
through WFS. GET `/rtl/apps/{app}/.appcfg` returns configuration with the live
**boolean running** state. This is distinct from **boolean autostart**, which
controls startup after a host restart.

PUT replaces the configuration, rather than merging individual fields. Read
the configuration first and retain settings that are not being changed. To
create an application, write `.appcfg` beneath its source directory in an I/O
root. The directory path supplies the default source URL.

- **string name**: application name; required for a complete configuration.
- **string url**: source path or NET IO URL; defaults to the containing source
  path when omitted.
- **boolean running**: requested running state; defaults to false.
- **boolean autostart**: optional; false prevents automatic launch at startup.
- **number startprio**: optional startup ordering value; lower values start
  first, and omission sorts as 100.
- **string dirname**: optional LSP mount path; omission disables LSP, and an
  empty string selects the server root.
- **string domainname**: optional virtual host name for an LSP application.
- **number priority**: optional LSP mount priority; defaults to zero.

Changing the running state starts or stops the application. Updating other
settings while retaining the same name and running state does not force a
restart. Stop and start the application to apply settings that require one.
A successful PUT acknowledges configuration processing; check `getappsstat`
and TraceLogger for application startup results. DELETE of an installed
application's `.appcfg` removes its registration and stops it; it does not
delete the source files.

### `.xlua` hot reload

When a running application's `.xlua` file is replaced through WFS, closing the
write handle invokes Xedge's `manageXLuaFile` flow so the program is reloaded.
The upload response does not report the Lua program's execution result; errors
are reported through TraceLogger.

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
failure. For a JSON application error it calls `callback(false, response)`;
transport or JSON decoding failures call `callback(false)`. An `ok: false`
value alone is passed to the callback as a normal response, so callers must
check it. Authentication failures are retried after login.

### Built-in commands

#### `acme`

Certificate management uses the required **string acmd** selector. These
commands require writable ACME I/O. They complete asynchronously through a
deferred HTTP response.

**Parameters for `available` and `auto`**

- **string name**: requested device name; required for `available`. For `auto`,
  omission retains the saved name, which must exist.
- **string email**: account email for `auto`; omission retains the saved value,
  which must exist.
- **string manualIdentity**: `"true"` selects custom portal credentials;
  omission or another value selects the compiled identity.
- **string portalUrl**: custom portal URL; omission retains the saved value.
- **string zoneKey**, **string secret**: custom portal credentials; omitted or
  empty values retain the saved values. These are not returned by `isreg`.
- **string revcon**: `"true"` enables reverse connections for `auto`;
  omission or another value disables them.
- **string staging**: `"true"` selects the staging certificate authority;
  another supplied value selects production. Omission retains the selection.

`available` returns **boolean ok**, **boolean available**, and **string name**
on success, or **string err** on failure.

`auto` saves settings, closes the preceding runtime, and starts the selected
configuration. It returns `{"ok":true}` or `{"ok":true,"pending":true}` when
activation awaits clock readiness or a scheduled retry. **boolean pending**
does not mean that a certificate is installed. Failure returns **string err**.
Use `isreg` to retrieve subsequent state.

**Return values for `isreg`**

- **boolean ok**: true for the status response.
- **boolean isreg**: whether the portal confirmed registration; false also
  covers an unavailable confirmation and does not alone prove deletion.
- **string name**, **string email**: optional saved/confirmed device name
  (first DNS label) and configured email.
- **string sockname**: optional local address of the connection to the portal.
  It is not the local address of the browser connection.
- **string wan**: optional public address observed by the portal.
- **string connectionError**: optional registration or WAN lookup error.
- **string portal**, **string compiledPortal**: selected and compiled portal
  identities; empty when unavailable.
- **boolean compiledIdentity**, **boolean manualIdentity**: availability of a
  compiled identity and selection of custom credentials, respectively.
- **boolean staging**, **boolean revcon**: selected staging and reverse modes.
- **object reverseStatus**: **boolean enabled**, **boolean connected**,
  **number status** (native connection status), and **number connections**
  (established-connection count).
- **boolean certificateRetrying**: a runtime startup retry is scheduled.
- **boolean certificateWorking**: clock readiness or runtime work is pending.
- **boolean certificateReady**: at least one reported certificate has a future
  expiration time and `certificateWorking` is false. This is not a browser
  trust check; a staging certificate can also satisfy it.

#### `getconfig`

Returns `config`, a base64url-encoded JSON object containing application
configuration (`{"apps":{...}}`). This supports browser persistence when disk configuration is
unavailable.

#### `getionames`

Accepts optional **string xedgeconfig**, the encoded configuration from
`getconfig`. It is used only when disk configuration is unavailable and no
application configuration has been loaded. Returns **boolean ok**, **array of
strings ios**, and **boolean nodisk**. I/O names are not sorted:


```json
{"ok":true,"ios":["disk","home","net"],"nodisk":false}
```

During startup this command also establishes the authentication boundary before
the client creates its tree and loads plugins.

#### `getappsstat`

Returns **boolean ok** and **object apps**, mapping application names to live
running values. A stopped application whose internal state is nil is omitted
from this object. Read its `.appcfg` to obtain an explicit boolean state.

#### `gethost`

Returns **boolean ok** and **string ip**, the request domain from
`cmd:domain()` for NET IO setup. Despite the field name, this can be a host
name and is not an interface-address discovery operation.

#### `getintro`

Returns **boolean ok** and **string intro**, containing welcome-page HTML.

#### `getmac`

The default implementation returns **boolean ok** false. A platform plugin may
override it and return **boolean ok** true and **string mac**.

#### `gettemplate`

Accepts optional **string ext**. Returns **boolean ok** and **string data**,
the matching new-file template, or a newline
when no template exists.

#### `credentials`

- With no `name`, returns **boolean ok** and **object data** with **string name**,
  one configured user or an empty
  string.
- With required **string name** and **string pwd**, creates or updates the user's digest credential. An
  empty password removes the user. The update response is `{"ok":true}`.

#### `pn2url`

Requires **string fn**. Returns **boolean ok** and **string url**, the launch URL for a running LSP-enabled application, or
**string err** when the application is missing, stopped, or not LSP-enabled.

#### `pn2info`

Requires **string fn**. For application resources, returns **boolean ok**,
**boolean isapp**, **boolean lsp**, optional **boolean running**, and optional
**string url**. A nil internal running state is omitted; treat an absent
`running` as stopped. The URL is omitted for `.xlua` resources. For non-application resources it returns `{"ok":true}`.

#### `run`

Requires **string fn**. Runs a selected `.xlua` resource when its owning
application is running. The `{"ok":true}` response is also returned if the
application is missing or stopped; it does not report execution success.
Execution errors are reported through TraceLogger.

#### `smtp`

- With no fields other than `cmd`, returns SMTP and email-log configuration.
- With string fields **email**, **server**, **port**, **user**, **password**,
  and **connsec**, validates
  and stores SMTP settings. Complete settings trigger a test email; incomplete
  settings disable SMTP. `connsec="tls"` selects implicit TLS;
  `connsec="starttls"` selects STARTTLS. Other nonempty values leave both
  options disabled. `port` must be numeric text for the completeness check.
  Send all six fields when updating. Unchanged enabled settings do not send
  another test email. A failed test returns **boolean ok** false and optional
  **string err**, retaining the previous settings.

The read response places SMTP settings and email-log fields directly in the
response object alongside **boolean ok**, including the configured password.
`enablelog` and `smtp` are booleans; `maxbuf` and `maxtime` are numbers;
`subject` and the SMTP fields are strings.

#### `openid`

With no fields other than `cmd`, returns **boolean ok** and **object data**,
containing stored Microsoft Entra OpenID settings or an empty object. This is
an administrative response that includes the configured secret.

To configure SSO, supply these strings:

- **string tenant** and **string client_id**: required, each longer than
  20 characters.
- **string client_secret**: required, longer than 10 characters.
- **string client_secret_expires**: required valid expiration date. A
  `YYYY-MM-DD` date means the end of that day in UTC.

The server derives `redirect_uri` from the request origin plus `/rtl/login/`.
HTTPS is required except for `http://localhost` development. The redirect URI
must also be registered in Microsoft Entra. Initialization or save failure
returns **boolean ok** false and **string err**, restoring the prior in-memory
configuration. Success returns `{"ok":true}`.

To disable SSO, send `tenant`, `client_id`, and `client_secret` together as
empty strings. An empty secret by itself does not remove the configuration.
Login-page credential recovery is handled separately by
[ms-sso.lua](../src/xedge/.lua/ms-sso.lua) and
[login/index.lsp](../src/xedge/login/index.lsp).

#### `elog`

Requires integer-form strings **maxbuf** (buffer size in bytes) and
**maxtime** (hours), **string enablelog** (`"true"` enables logging), and
**string subject** (empty selects `"Xedge Log"`).
Stores email-log settings and returns `{"ok":true}`.

#### `execLua`

Accepts **string code**, defaulting to empty source. Compiles the Lua source and schedules it asynchronously. A
compile failure returns `{"ok":false,"err":"..."}`. Success returns
`{"ok":true}` after scheduling; runtime errors appear in TraceLogger and
are not returned in this response.

#### `lsPlugins`

Returns an alphabetically sorted JSON **array of strings** containing client
plugin paths.

#### `getPlugin`

Requires a **string name**, ending in `.js`, returned by `lsPlugins`. Streams JavaScript rather than
JSON and returns 404 when the plugin is unavailable. The native client requests
plugins with `cache: "no-store"` and executes them sequentially in the returned
order.

#### `startApp`

Requires **string name**, the uploaded ZIP name under `home` on Mako or `disk` on
standalone Xedge. The optional **string deploy** selects the mode: `deploy=false` unpacks the ZIP into developer mode; other
values retain deployed ZIP mode.

The response contains:

- **boolean ok**: installation success;
- **boolean upgrade**: whether an existing deployed application was replaced;
- **string info**: optional text returned by an install or upgrade hook; and
- **string err**: failure details when `ok` is false.

### Plugin-defined commands

Lua plugins under `.lua/XedgePlugins` receive the command table and may add or
override handlers. Such commands are platform-specific and are not part of the
built-in list. For example, the application-update plugin adds the raw PUT
command `uploadfw`; Xedge32 plugins may add firmware and device commands.

A plugin handler is responsible for validating its method, headers, body, and
parameters, and for sending or aborting the response.

## Browser plugin API

Client plugins are classic scripts loaded after authentication, I/O discovery,
and tree initialization. The Xedge shell itself is an ES module. Its supported plugin functions are
exposed on `window` (the shell also exposes login integration hooks):

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
// Add a configuration-menu entry after Xedge has initialized its UI.
ideCfgCB.push((menu, nodisk) => {
  const item = el("li", {text: "My Plugin"});
  item.onclick = () => createEditor("My Plugin", null, null, el("div", {text: "Ready"}));
  menu.append(item);
});
```

The callback receives an **HTMLUListElement menu** and **boolean nodisk**. Its
return value is ignored.
Plugins that mutate applications or files should call `createTree()` after the
server operation succeeds.

Browser and Lua plugins execute with Xedge management privileges. Treat plugin
files as trusted code, validate all external input on the server, and do not
expose secrets to browser plugins.

### Browser Function Contracts

- `el(string tag, object properties, ...children)` returns an **HTMLElement**.
  Children are DOM nodes or text; `html` is trusted HTML, not escaped text.
- `mkForm(array description, object elements?, HTMLElement parent?)` returns
  the parent **HTMLElement** (a new form container by default). The supplied
  `elements` object is populated by element ID, not by name. Description
  objects use `el` for the tag, `children` for nested descriptions, and `html`
  for trusted HTML. Form entries can use `label` as the element ID, `name` as
  display text, and `description` as tooltip text.
- `createEditor(string name, string|null value, function|null saveCallback,
  HTMLElement content?, function closeCallback?)` returns a **string editor ID**,
  or **undefined** if that editor already has unsaved changes. Use `value=null`
  with `content` to open a plugin panel. The optional save callback receives
  the data and a completion function; call completion with `{ok:true}` on
  success. A boolean `true` alone does not clear the modified indicator.
  The optional close callback takes no arguments and releases plugin resources.
- `closeEditor(string id)` returns **undefined** and invokes the registered
  close callback. It closes directly without the tab button's unsaved-change
  confirmation.
- `sendCmd(string command, function callback, object data?)` returns
  **undefined**, adds `cmd` to the supplied data object, and performs a GET.
  Its callback receives the JSON response or the failure arguments described
  under the command API. This function does not return a Promise.
- `createTree()` returns **undefined** and starts an asynchronous tree rebuild.
  `log(...)`, `logR(...)`, and `alertErr(...)` report output and return
  **undefined**; their return values do not indicate server-operation success.
