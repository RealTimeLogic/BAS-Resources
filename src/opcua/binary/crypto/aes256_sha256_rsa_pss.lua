-- DerivedSignatureKeyLength: 256 bits
-- MinAsymmetricKeyLength: 2048 bits
-- MaxAsymmetricKeyLength: 4096 bits
-- SecureChannelNonceLength: 32 bytes

local ua = require("opcua.api") -- REMOVE, Not used in encryption

return {
  policyUri = ua.SecurityPolicy.Aes256_Sha256_RsaPss,
  aEncryptionAlgorithm = "http://www.w3.org/2001/04/xmlenc#rsa-oaep",
  aSignatureUri = "http://opcfoundation.org/UA/security/rsa-pss-sha2-256",
  rsaParams = {padding="oaep", hash="sha256"},
  asymmetricSign = ua.crypto.rsaPssSha2_256Sign,
  asymmetricVerify = ua.crypto.rsaPssSha2_256Verify,
  hmacSum = ua.crypto.hmacSha256,
  aPaddingSize = 66,
  nonceSize = 32,
  minKeySize = 256,
  maxKeySize = 512,
  hmacSize = 32,
  symmetricBlockSize = 32,
  siningKeyLength = 32,
  encryptingKeyLength = 32,
  encryptingBlockSize = 32,
}