local engine = {
  crypto = ba and require("opcua.sharkssl") or require("opcua.openssl"),
  crypto_engine = ba and "sharkssl" or "openssl"
}

return engine
