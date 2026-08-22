local native = require("opcua_ns0")
local exporter = require("opcua.model.export_packed")

local function open(source)
  return native.open(source)
end

local function pack(model, namespaceURIs)
  local chunks = {}
  exporter(model, function(chunk)
    chunks[#chunks + 1] = chunk
  end, namespaceURIs)
  return table.concat(chunks)
end

local function openBuiltin(name)
  return native.openBuiltin(name)
end

return {
  open = open,
  openBuiltin = openBuiltin,
  pack = pack,
}
