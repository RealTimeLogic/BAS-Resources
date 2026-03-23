local const = require("opcua.const")
local trace = require("opcua.trace")

local tins = table.insert
local NodeClass = const.NodeClass
local HasEncoding <const> = "i=38"
local HasSubtype <const> = "i=45"

local traceI = trace.inf

local Model <const> = {}

local encodeTypes = {
  ["i=1"] = "i=1",
  ["i=2"] = "i=2",
  ["i=3"] = "i=3",
  ["i=4"] = "i=4",
  ["i=5"] = "i=5",
  ["i=6"] = "i=6",
  ["i=7"] = "i=7",
  ["i=8"] = "i=8",
  ["i=9"] = "i=9",
  ["i=10"] = "i=10",
  ["i=11"] = "i=11",
  ["i=13"] = "i=13",
  ["i=12"] = "i=12",
  ["i=14"] = "i=14",
  ["i=15"] = "i=15",
  ["i=16"] = "i=16",
  ["i=17"] = "i=17",
  ["i=18"] = "i=18",
  ["i=19"] = "i=19",
  ["i=20"] = "i=20",
  ["i=21"] = "i=21",
  ["i=22"] = "i=22",
  ["i=23"] = "i=23",
  ["i=25"] = "i=25",
  ["i=29"] = "i=29",
}

function Model.getBaseDatatype(self, dataTypeId)
  local nodes = self.Nodes
  local curDataTypeId = dataTypeId
  while curDataTypeId do
    local node <const> = nodes[curDataTypeId]
    if not node then
      error("No node for id: " .. curDataTypeId)
    end
    if curDataTypeId ~= "i=22" then
      if node.Attrs.NodeClass ~= NodeClass.DataType then
        error("Node is not a data type: " .. curDataTypeId)
      end
      if node.Attrs.IsAbstract == nil then
        error("No IsAbstract attribute for node: " .. curDataTypeId)
      end
    end

    if encodeTypes[curDataTypeId] then
      return encodeTypes[curDataTypeId]
    end

    local parentTypeId = nil
    for _, ref in pairs(node.Refs) do
      -- Find reference to base data type
      if ref.type == HasSubtype and not ref.isForward then
        parentTypeId = ref.target
        break
      end
    end

    if not parentTypeId then
      encodeTypes[curDataTypeId] = curDataTypeId
      return curDataTypeId
    end

    curDataTypeId = parentTypeId
  end
end

function Model:fillExtensionObjects()
  local infOn = self.config.logging.services.infOn
  if infOn then traceI("Filling extension objects") end

  for dataTypeId, node in pairs(self.Nodes) do
    if node.Attrs.NodeClass ~= NodeClass.DataType then
      goto continue
    end

    -- Search function for encoding base type node
    local baseId = self:getBaseDatatype(dataTypeId)

    node.BaseId = baseId

    -- Search IDs for encoding extention objects: binary, xml etc.
    -- Each extension object contains body in a some format. Each
    -- structrue has an ID and corresponsing ID for encoding format
    -- For example: ServerStatusDataType has own ID i=862 and following encoders:
    --  * ID i=863 for XML encoding
    --  * ID i=864 for binary encoding
    --  * ID i=15367 for JSON encoding

    for _, ref in pairs(node.Refs) do
      if ref.type == HasEncoding and ref.isForward then
        local targetId = ref.target
        local encodingNode = self.Nodes[targetId];
        if encodingNode == nil then
          error("No node for id: " .. targetId)
        end
        local encoding = encodingNode.Attrs.BrowseName
        if encoding.Name == "Default Binary" then
          node.BinaryId = targetId
          node.DataTypeId = dataTypeId
          self.Nodes[targetId].BinaryId = targetId
          self.Nodes[targetId].BaseId = baseId
          self.Nodes[targetId].DataTypeId = dataTypeId
        end
        if encoding.Name == "Default JSON" then
          node.JsonId = targetId
          node.DataTypeId = dataTypeId
          self.Nodes[targetId].JsonId = targetId
          self.Nodes[targetId].BaseId = baseId
          self.Nodes[targetId].DataTypeId = dataTypeId
        end
      end
    end
    ::continue::
  end
end

function Model:fillInheritedDefinitions()
  local infOn = self.config.logging.services.infOn
  if infOn then traceI("Expanding inherited data type definitions") end

  for _,node in pairs(self.Nodes) do
    local definitions = {}
    local type = node
    -- Collect all superTypes
    while type and
          type.Attrs.NodeClass == NodeClass.DataType and
          type.Attrs.NodeId ~= "i=24"
    do
      -- Every DataType contain part of definition
      -- To construct full definition we need also collect
      -- fields from parent types and compose full definition.
      tins(definitions, type.Attrs.DataTypeDefinition)
      local superType
      for _,ref in ipairs(type.Refs) do
        -- Search HasSubtype reference
        if ref.type == HasSubtype and ref.isForward == false then
          superType = self.Nodes[ref.target]
          break
        end
      end
      type = superType
    end

    if #definitions >= 1 then
      local fullDefinition = {}
      for i = #definitions, 1, -1 do
        local definition = definitions[i]
        for _,field in ipairs(definition) do
          tins(fullDefinition, field)
        end
      end

      node.Attrs.DataTypeDefinition = fullDefinition
    end
  end
end

Model.loadXml = function(...)
  return require("opcua.model.load_xml")(...)
end

Model.exportXml = function(...)
  return require("opcua.model.export_xml")(...)
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

  return require("opcua.model.encoding").CreateEncoder(self, serializer)
end

function Model:createBinaryDecoder(bta)
  local decoder = require("opcua.binary.decoder")
  local serializer = decoder.new(bta)

  return require("opcua.model.encoding").CreateDecoder(self, serializer)
end

function Model:createJsonEncoder(bta)
  local encoder = require("opcua.json.encoder")
  local serializer = encoder.new(bta)

  return require("opcua.model.encoding").CreateEncoder(self, serializer)
end

function Model:createJsonDecoder(bta)
  local decoder = require("opcua.json.decoder")
  local serializer = decoder.new(bta)

  return require("opcua.model.encoding").CreateDecoder(self, serializer)
end

function Model:commit()
  self:fillInheritedDefinitions()
  self:validate()
  self:fillExtensionObjects()
end

function Model:loadXmlModels(modelFiles)
  for _,path in ipairs(modelFiles) do
    local f, err,tmp
    if path:sub(1, 7) == "http://" or path:sub(1, 8) == "https://" then
      local ok, httpc = pcall(require, "httpc")
      if ok then
        f = httpc.create()
        tmp,err=f:request{url=path, method="GET"}
      else
        local socket = require("socket.http")
        local http = require("socket.http")
        local code
        f, code = http.request(path)
        if code ~= 200 then
          error("Failed to load model: " .. path .. " (code: " .. code .. ")")
        end
      end
    elseif path:sub(1, 1) == "<?xml" then
      f = path -- this is the content of the file
    else
      f, err = io.open(path, "r")
    end

    if err then
      error(err)
    end

    self:loadXml(f)
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
    Nodes = require("opcua.model.address_space")({}),
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
  local ns0 = require("opcua_ns0")
  if infOn then traceI("Loading address space") end
  local as = require("opcua.model.address_space")
  if infOn then traceI("Creating address space") end
  model.Nodes = as(ns0)
  if infOn then traceI("Base model loaded") end

  return model
end

return {
  getBaseModel = getBaseModel,
  createModel = createModel
}
