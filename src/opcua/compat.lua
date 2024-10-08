if ba then
  return require("opcua.compat_rtl")
else
  return require("opcua.compat_lua")
end
