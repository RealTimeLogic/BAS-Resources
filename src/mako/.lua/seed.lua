
local function seed()
   local ab=require"acme/bot"
   local http=require"http".create(ab.getproxy{shark=ba.sharkclient()})
   local ok,err=
      http:request{trusted=true,url="https://beacon.nist.gov/beacon/2.0/pulse/last"}
   if ok and http:status() == 200 then
      ba.rndseed(ba.crypto.hash("hmac","sha256",ba.clock())(http:read"*a")(true,"binary"))
   end
end
local function thseed() return ba.thread.run(seed) end
thseed()
return {seed=thseed}


