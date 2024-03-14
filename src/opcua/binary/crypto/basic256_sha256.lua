-- DerivedSignatureKeyLength: 256 bits
-- MinAsymmetricKeyLength: 2048 bits
-- MaxAsymmetricKeyLength: 4096 bits
-- SecureChannelNonceLength: 32 bytes

local ua = require("opcua.api") -- REMOVE, Not used in encryption

return {
  policyUri = ua.Types.SecurityPolicy.Basic256Sha256,
  aEncryptionAlgorithm = "http://www.w3.org/2001/04/xmlenc#rsa-oaep",
  aSignatureUri = "http://www.w3.org/2001/04/xmldsig-more#rsa-sha256",
  rsaParams = {padding="oaep", hash="sha1"},
  asymmetricSign = ua.crypto.rsaPkcs15Sha256Sign,
  asymmetricVerify = ua.crypto.rsaPkcs15Sha256Verify,
  hmacSum = ua.crypto.hmacSha256,
  aPaddingSize = 42,
  nonceSize = 32,
  minKeySize = 256,
  maxKeySize = 512,
  hmacSize = 32,
  symmetricBlockSize = 32,
  siningKeyLength = 32,
  encryptingKeyLength = 32,
  encryptingBlockSize = 16,
}
