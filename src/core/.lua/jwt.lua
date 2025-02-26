local b64enc, jenc = ba.b64urlencode, ba.json.encode
local b64dec, jdec = ba.b64decode, ba.json.decode
local function table2B64(t) return b64enc(jenc(t)) end

local function shallowCopy(t)
   local newTable = {}
   for k, v in pairs(t) do newTable[k] = v end
   return newTable
end

local function sign(payload, secret, options)
   options = options and shallowCopy(options) or {alg="HS256"}
   options.typ = "JWT"
   if options.kid then options.kid = tostring(options.kid) end
   local signature, err
   local header = table2B64(options)
   payload = type(payload) == "table" and table2B64(payload) or b64enc(payload)
   local data = header .. "." .. payload
   local alg,htype=options.alg:sub(1,2),options.alg:sub(3)
   if "HS" == alg then
      signature = b64enc(ba.crypto.hash("hmac", "sha"..htype, secret)(data)(true))
   else
      local hash = ba.crypto.hash("sha"..htype)(data)(true)
      signature, err = ba.crypto.sign(hash, secret)
      if not signature then return nil, err end
      if "ES" == alg then
	 local r, s = ba.crypto.sigparams(signature)
	 if not r or not s then return nil, "Unknown ECDSA signature" end
	 signature = b64enc(r .. s)
      elseif "RS" == alg then
	 signature = b64enc(signature)
      end
   end
   if not signature then
      return nil,"Unsupported algorithm"
   end
   return header .. "." .. payload .. "." .. signature, {
      header = header,
      payload = payload,
      signature = signature
   }
end

local function verify(jwt, secret, kid)
   local headerB64, payloadB64, signatureB64 = jwt:match("([^.]*)%.([^.]*)%.([^.]*)")
   if not (headerB64 and payloadB64 and signatureB64) then
      return nil, "Invalid JWT format"
   end
   local header = jdec(b64dec(headerB64))
   if not header or not header.alg then
      return nil, "Invalid JWT header"
   end
   if true == kid then
      kid=header.kid
      if not kid then return nil, "no kid in payload" end
      secret=secret[kid]
      if not secret then return nil, "Secret not found for kid: "..tostring(kid) end
   end
   local data = headerB64 .. "." .. payloadB64
   local signature = b64dec(signatureB64)
   local alg,htype=header.alg:sub(1,2),header.alg:sub(3)
   if "HS" == alg then
      local expectedSig = ba.crypto.hash("hmac", "sha"..htype, secret)(data)(true)
      return expectedSig == signature, jdec(b64dec(payloadB64))
   else
      local hash = ba.crypto.hash("sha"..htype)(data)(true)
      if "ES" == alg then
	 local mid=#signature//2
	 local r,s = signature:sub(1,mid),signature:sub(mid+1)
	 signature=ba.crypto.sigparams(r,s)
	 if not signature then return nil,"Invalid signature" end
      end
      local isValid
      if "table" == type(secret) then
	 local op=secret
	 if not ((op.x and op.y) or (op.n and op.e)) then
	    error("Missing keyparams",2)
	 end
	 isValid=ba.crypto.verify(signature, hash, op)
      else
	 isValid=ba.crypto.verify(signature, secret, hash)
      end
      return isValid, header, jdec(b64dec(payloadB64))
   end
end

return {
   sign=sign,
   verify=verify
}
