-- DerivedSignatureKeyLength: 128 bits
-- MinAsymmetricKeyLength: 1024 bits
-- MaxAsymmetricKeyLength: 2048 bits
-- SecureChannelNonceLength: 16 bytes

local const = require("opcua.const") -- REMOVE, Not used in encryption
local crypto = require("opcua.crypto")

return {
  policyUri = const.SecurityPolicy.Basic128Rsa15,
  aEncryptionAlgorithm = "http://www.w3.org/2001/04/xmlenc#rsa-1_5",
  aSignatureUri = "http://www.w3.org/2000/09/xmldsig#rsa-sha1",
  rsaParams = {padding="pkcs1", hash="sha1"},
  asymmetricSign = crypto.crypto.rsaPkcs15Sha1Sign,
  asymmetricVerify = crypto.crypto.rsaPkcs15Sha1Verify,
  hmacSum = crypto.crypto.hmacSha1,
  aPaddingSize = 20,
  nonceSize = 16,
  minKeySize = 128,
  maxKeySize = 256,
  hmacSize = 20,
  symmetricBlockSize = 16,
  siningKeyLength = 16,
  encryptingKeyLength = 16,
  encryptingBlockSize = 16,
}
