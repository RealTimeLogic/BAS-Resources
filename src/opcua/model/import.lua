local trace = require("opcua.trace")

local traceI = trace.inf
local fmt = string.format

local PACKED_MAGIC = "UAPB"
local READ_SIZE = 4096

local Model <const> = {}

Model.loadXml = function(self, ...)
  local provider = self.Nodes.provider
  local encodeValues = provider.encodeValues

  -- XML values are static model data and may be much larger than the fixed
  -- runtime DataValue buffer. Keep them raw during import. Later writes still
  -- use the provider's normal binary encoding.
  provider.encodeValues = false
  local result = table.pack(pcall(
    require("opcua.model.load_xml"), self, ...))
  provider.encodeValues = encodeValues

  if not result[1] then
    error(result[2], 0)
  end
  return table.unpack(result, 2, result.n)
end

local function createOutput(output)
  if type(output) == "function" then
    return output
  end

  local file = output
  local owned = false
  if type(output) == "string" then
    local err
    file, err = io.open(output, "wb")
    if not file then
      error("could not open output file '" .. output .. "': " ..
        tostring(err), 0)
    end
    owned = true
  elseif io.type(output) ~= "file" then
    error("output must be a filename, file handle, or function", 0)
  end

  local function write(chunk)
    local result, err = file:write(chunk)
    if result == nil then
      error(err or "could not write output", 0)
    end
  end
  return write, owned and file or nil
end

local function exportModel(self, exporter, output, namespaceURIs)
  local write, ownedFile = createOutput(output)
  local result = table.pack(pcall(
    exporter, self, write, namespaceURIs))

  if ownedFile then
    local closed, closeError = ownedFile:close()
    if result[1] and not closed then
      result = table.pack(false,
        closeError or "could not close output file")
    end
  end

  if not result[1] then
    error(result[2], 0)
  end
  return table.unpack(result, 2, result.n)
end

function Model:exportXml(output, namespaceURIs)
  return exportModel(
    self, require("opcua.model.export_xml"), output, namespaceURIs)
end

function Model:exportPacked(output, namespaceURIs)
  return exportModel(
    self, require("opcua.model.export_packed"), output, namespaceURIs)
end

function Model:loadPacked(source)
  local provider = require("opcua.model.packed_provider").open(source)
  self.Nodes:addReadonlyProvider(provider)
  return provider
end

Model.validate = function(...)
  return require("opcua.model.validate")(...)
end

function Model:browse(parentNodeId)
  local browser = require("opcua.model.browse")
  return browser.newBrowser(self, self.Nodes, parentNodeId)
end

function Model:edit()
  local browser = require("opcua.model.browse")
  return browser.newEditor(self)
end

function Model:newNodeId()
  self.NextNodeIdentifier = self.NextNodeIdentifier + 1
  return "ns=1;i=" .. self.NextNodeIdentifier
end

function Model:createBinaryEncoder(bta)
  local encoder = require("opcua.binary.encoder")
  local serializer = encoder.new(bta)

  return require("opcua.model.encoding").CreateEncoder(
    self, serializer, "Binary")
end

function Model:createBinaryDecoder(bta)
  local decoder = require("opcua.binary.decoder")
  local serializer = decoder.new(bta)

  return require("opcua.model.encoding").CreateDecoder(
    self, serializer, "Binary")
end

function Model:createJsonEncoder(bta)
  local encoder = require("opcua.json.encoder")
  local serializer = encoder.new(bta)

  return require("opcua.model.encoding").CreateEncoder(
    self, serializer, "Json")
end

function Model:createJsonDecoder(bta)
  local decoder = require("opcua.json.decoder")
  local serializer = decoder.new(bta)

  return require("opcua.model.encoding").CreateDecoder(
    self, serializer, "Json")
end

function Model:commit()
  self:validate()
end

local function streamReader(source)
  if type(source) == "function" then
    return source
  end
  return function()
    return source:read(READ_SIZE)
  end
end

local function detectFormat(data)
  if data:sub(1, #PACKED_MAGIC) == PACKED_MAGIC then
    return "packed"
  end

  if data:sub(1, 3) == "\239\187\191" then
    data = data:sub(4)
  end
  local first = data:match("^%s*(.)")
  if first == "<" then
    return "xml"
  end
end

local function formatMayBeIncomplete(data)
  if #data < #PACKED_MAGIC and
     PACKED_MAGIC:sub(1, #data) == data then
    return true
  end

  local byteOrderMark = "\239\187\191"
  if #data < #byteOrderMark and
     byteOrderMark:sub(1, #data) == data then
    return true
  end
  if data:sub(1, #byteOrderMark) == byteOrderMark then
    data = data:sub(#byteOrderMark + 1)
  end
  return data:match("^%s*$") ~= nil
end

local function loadStream(self, source, modelName)
  local read = streamReader(source)
  local chunks = {}
  local format

  while format == nil do
    local chunk = read()
    if chunk == nil or #chunk == 0 then
      break
    end
    chunks[#chunks + 1] = chunk
    local data = table.concat(chunks)
    format = detectFormat(data)

    if format == nil and not formatMayBeIncomplete(data) then
      break
    end
  end

  if format == "packed" then
    while true do
      local chunk = read()
      if chunk == nil or #chunk == 0 then
        break
      end
      chunks[#chunks + 1] = chunk
    end
    return self:loadPacked(table.concat(chunks))
  elseif format == "xml" then
    local initial = table.concat(chunks)
    return self:loadXml(function()
      if initial ~= nil then
        local chunk = initial
        initial = nil
        return chunk
      end
      return read()
    end)
  end

  error("Unsupported model format: " .. modelName)
end

local function loadUrl(self, path)
  local ok, httpc = pcall(require, "httpc")
  if ok then
    local source = httpc.create()
    local _, err = source:request{url=path, method="GET"}
    if err then
      error(err)
    end
    return loadStream(self, source, path)
  end

  local http = require("socket.http")
  local content, code = http.request(path)
  if code ~= 200 then
    error("Failed to load model: " .. path .. " (code: " .. code .. ")")
  end
  return loadStream(self, function()
    local result = content
    content = nil
    return result
  end, path)
end

local function loadFile(self, path)
  local source, err = io.open(path, "rb")
  if not source then
    error(err)
  end

  local result = table.pack(pcall(loadStream, self, source, path))
  source:close()
  if not result[1] then
    error(result[2], 0)
  end
  return table.unpack(result, 2, result.n)
end

function Model:loadModels(modelSources)
  local infOn = self.config.logging.services.infOn

  for index, source in ipairs(modelSources) do
    local modelName
    local load
    local sourceType = type(source)
    if sourceType == "string" and
       (source:sub(1, 7) == "http://" or
        source:sub(1, 8) == "https://") then
      modelName = source
      load = function()
        return loadUrl(self, source)
      end
    elseif sourceType == "string" and detectFormat(source) ~= nil then
      modelName = fmt("content #%d", index)
      load = function()
        return loadStream(self, function()
          local result = source
          source = nil
          return result
        end, modelName)
      end
    elseif sourceType == "string" then
      modelName = source
      load = function()
        return loadFile(self, source)
      end
    elseif sourceType == "function" or
           ((sourceType == "table" or sourceType == "userdata") and
            type(source.read) == "function") then
      modelName = fmt("stream #%d", index)
      load = function()
        return loadStream(self, source, modelName)
      end
    else
      error(fmt("Invalid model source #%d", index))
    end

    if infOn then traceI(fmt("Loading model from: %s", modelName)) end
    load()
    if infOn then traceI(fmt("Model from %s loaded successfully", modelName)) end
  end
end

function Model:createNamespace(namespaceUri)
  for _, namespace in ipairs(self.Namespaces) do
    if namespaceUri == namespace.NamespaceUri then
      error("Namespace with URI " .. namespaceUri .. " already exists")
    end
  end

  local index = namespaceUri == "http://opcfoundation.org/UA/" and 0 or #self.Namespaces + 1
  self.Namespaces[index] = {
    Index = index,
    NamespaceUri = namespaceUri,
    Version = "1.0.0",
  }
  return index
end

local function createModel(config)
  assert(config, "config is required")
  assert(config.applicationUri, "config.ApplicationUri is required")

  local infOn = config.logging.services.infOn
  if infOn then traceI("loading address space") end
  local model = {
    Nodes = require("opcua.model.address_space")({}, {
      encodeValues = config.encodeValues,
    }),
    Models = {}, -- ModelUri -> model
    Namespaces = {}, -- array of namespaces, index starts from 0, and map namespaceUri to Namespace
    Aliases = {},
    NextNodeIdentifier = math.floor(os.time()),
    config = config,
  }

  local ns1 = {
    Index = 1,
    NamespaceUri = config.applicationUri,
    ModelUri = config.applicationUri,
    Version = "1.0.0"
  }

  model.Namespaces[1] = ns1
  model.Namespaces[ns1.NamespaceUri] = ns1

  model.Models[config.applicationUri] = {
    ModelUri = config.applicationUri,
    Version = "1.0.0"
  }

  setmetatable(model, {
    __index = Model,
    __newindex = function()
      error("Model is read-only")
    end
  })
  model.Nodes:setModel(model)

  return model
end

local function getBaseModel(config)
  assert(config, "config is required")
  assert(config.applicationUri, "config.ApplicationUri is required")

  local infOn = config.logging.services.infOn
  if infOn then traceI("Loading base model") end

  local model = createModel(config)

  local ns = {
    Index = 0,
    NamespaceUri = "http://opcfoundation.org/UA/",
    ModelUri = "http://opcfoundation.org/UA/",
    Version = "1.05.01"
  }

  model.Namespaces[0] = ns
  model.Namespaces[ns.NamespaceUri] = ns

  model.Models["http://opcfoundation.org/UA/"] = {
    ModelUri="http://opcfoundation.org/UA/",
    Version="1.05.01"
  }

  if infOn then traceI("Loading NS0 namespace") end
  local ns0 =
    require("opcua.model.packed_provider").openBuiltin("ns0")
  if infOn then traceI("Loading address space") end
  local as = require("opcua.model.address_space")
  if infOn then traceI("Creating address space") end
  model.Nodes = as(ns0)
  model.Nodes:setModel(model)
  if infOn then traceI("Base model loaded") end

  return model
end

return {
  getBaseModel = getBaseModel,
  createModel = createModel
}
