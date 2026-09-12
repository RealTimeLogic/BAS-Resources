# ACME Token Generator Design

The generated `tokengen` C module lets Lua calculate a request proof without
returning the zone secret to Lua. Under the
[SharkTrust protocol](../../../GIT-repos/SharkTrustEx/doc/SharkTrust-Protocol.md),
C returns **32 binary bytes** from `proof(message)`. Lua converts these bytes
to **43 characters of unpadded base64url** and sends that text in the
`X-SharkTrust-Proof` HTTP header over HTTPS.

There is a separate conversion for the zone key: `info()` returns it as
**32 binary bytes**, and Lua converts it to **64 lowercase hexadecimal
characters**. The zone key, zone secret, request proof, and device credential
are different values.

## Lua Interface

`require "tokengen"` returns a Lua table for the loadable C module. An embedded
build registers the same interface as `etokengen`. The client tries
`etokengen` first, then `tokengen`.

| Call | Arguments | Synchronous return values |
| --- | --- | --- |
| `info()` | None. | Two Lua strings: the compiled portal/zone host name, without `https://`, and the 32-byte binary zone key. |
| `proof(message)` | Required string containing the exact bytes to authenticate, including any NUL bytes. | One 32-byte binary Lua string containing HMAC-SHA-256 of the message. |

Binary Lua strings can contain zero bytes. These C functions use
`lua_pushlstring()` with explicit lengths, so no bytes are lost at a NUL.
There is no secret-getter function. Invalid arguments to `proof()` raise a
Lua error rather than returning `nil, error`.

## Proof Key Derivation

The generated C reconstructs the embedded zone secret from XOR-obfuscated
data. It forms the secret's 64 **uppercase ASCII hexadecimal characters** and
derives a 32-byte key:

```text
# Key derivation used by both the generated C and a host-provided Lua proof callback.
proofKey = PBKDF2-HMAC-SHA-256(
    password   = uppercase ASCII hexadecimal zone secret,
    salt       = binary zone key (32 bytes),
    iterations = 1000,
    length     = 32 bytes
)
proofBytes = HMAC-SHA-256(proofKey, message)
```

The password input is the 64-character secret representation, not its
32-byte hexadecimal-decoded value. The salt is the decoded zone key.
PBKDF2 is the password-based key derivation function; HMAC is a keyed
message authentication code. Here the starting secret is randomly generated.

`proof()` returns only `proofBytes`. It does not return the secret or the
derived key. The generated C calls `memset()` on its temporary secret/key/proof
buffers after use. Its embedded-secret protection is obfuscation, not hardware-backed
secret storage; the reconstruction data remains in the generated code.

## Request Construction and Encoding

The client first JSON-encodes the body. It prefixes those exact bytes with
the operation context, then passes the resulting string to `proof()`.

In this table, `||` means byte concatenation, `NUL` means one zero byte,
`zoneKeyHex` is the 64-character lowercase zone key, and `credentialHex` is
the 64-character lowercase device credential returned during registration.
`body` is the exact encoded JSON string sent as the POST body.

| Operation | String passed to `proof()` |
| --- | --- |
| Check name availability | `"SHARKTRUST-AVAILABLE" || NUL || zoneKeyHex || NUL || body` |
| Register device | `"SHARKTRUST-REGISTER" || NUL || zoneKeyHex || NUL || body` |
| Enrolled-device POST command | `"SHARKTRUST-DEVICE" || NUL || credentialHex || NUL || body` |
| Reverse-connection GET | `"SHARKTRUST-DEVICE" || NUL || credentialHex || NUL` (no body) |

Lua then calls `ba.b64urlencode(proofBytes)`. This changes the representation
from binary to header-safe text. It does not encrypt the proof or hash it
again. Base64url uses `-` and `_` in place of ordinary base64's `+` and `/`,
and omits `=` padding. The 32-byte proof becomes 43 characters.

This shortened example constructs an availability request's body and headers;
it does not send a network request:

```lua
local tg = require "tokengen" -- Use "etokengen" for the embedded module.
local portal, zoneKeyBytes = tg.info()
local zoneKeyHex = zoneKeyBytes:gsub(".", function(byte)
   return string.format("%02x", byte:byte())
end)
local body = ba.json.encode{command="IsAvailable", name="controller-17"}
local message = "SHARKTRUST-AVAILABLE\0" .. zoneKeyHex .. "\0" .. body
local proofBytes = tg.proof(message)
local headers = {
   ["Content-Type"] = "application/json",
   ["X-SharkTrust-Zone-Key"] = zoneKeyHex,
   ["X-SharkTrust-Proof"] = ba.b64urlencode(proofBytes)
}
-- Send body unchanged to https://<portal>/sharktrust.lsp using trusted HTTPS.
-- Do not re-encode the JSON after calculating its proof or log these headers.
```

All local values in this example are strings except `tg` and `headers`, which
are tables. For enrolled-device requests, Lua replaces the zone-key header
with `Authorization: Bearer <credentialHex>`. The credential remains hex text;
it is not base64url-encoded. The request still needs the zone-secret-derived
proof, so the device credential alone is insufficient for authentication.

The portal decodes the proof header to 32 bytes, derives the same proof key,
recalculates the HMAC over the context and received body bytes, and compares
the binary values in constant time. HTTPS provides encryption in transit.
Neither the zone secret nor the derived proof key is transmitted.

## Local Registration Identity

At client creation, Lua also calls `proof("SHARKTRUST-IDENTITY\0" .. zoneKeyHex)`.
It hashes the concatenation of `zoneKeyHex` and those 32 proof bytes with
SHA-256, then base64url-encodes that digest to form `zoneIdentity`.
This string binds saved registration to its configured identity. It is local
state, not an additional encoding step for `X-SharkTrust-Proof` and not a
field sent in the normal portal request.

## Source references

- [Generated C template](../../../GIT-repos/SharkTrustEx/www/.lua/www/zones/cgen.html):
  `deriveZoneProofKey`, `calculateProof`, `zoneInfo`, and module registration.
- [Lua client](../src/core/.lua/acme/dns.lua): `identity`, `createClient`,
  `post`, `zonePost`, `devicePost`, and `startReverse`.
- [Portal verification](../../../GIT-repos/SharkTrustEx/www/.lua/SharkTrust.lua):
  `verifyProof`, `zoneAuthentication`, and `deviceAuthentication`.
- [Portal key derivation](../../../GIT-repos/SharkTrustEx/www/.lua/PBKDF2Cache.lua)
  and [protocol specification](../../../GIT-repos/SharkTrustEx/doc/SharkTrust-Protocol.md).

## Related Design

The [ACME mini DNS client proposal](../development/ACME-mini-DNS-proposal.md#calcproofmessage-contract-and-host-implementations) specifies a separate host-supplied proof interface. Its proposed integration is outside the scope of this token generator specification.
