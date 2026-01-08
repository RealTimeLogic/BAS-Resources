local types = require("opcua.types")
local tins = table.insert
local AttributeId = types.AttributeId
local NodeClass = types.NodeClass
local HasEncoding <const> = "i=38"
local HasSubtype <const> = "i=45"

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
      if node.attrs[AttributeId.NodeClass] ~= NodeClass.DataType then
        error("Node is not a data type: " .. curDataTypeId)
      end
      if node.attrs[AttributeId.IsAbstract] == nil then
        error("No IsAbstract attribute for node: " .. curDataTypeId)
      end
    end

    if encodeTypes[curDataTypeId] then
      return encodeTypes[curDataTypeId]
    end

    local parentTypeId = nil
    for _, ref in pairs(node.refs) do
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
  for dataTypeId, node in pairs(self.Nodes) do
    if node.attrs[AttributeId.NodeClass] ~= NodeClass.DataType then
      goto continue
    end

    -- Search function for encoding base type node
    local baseId = self:getBaseDatatype(dataTypeId)
    local extObj = {
      baseId = baseId,
      dataTypeId = dataTypeId
    }

    self.ExtObjects[dataTypeId] = extObj

    -- Search IDs for encoding extention objects: binary, xml etc.
    -- Each extension object contains body in a some format. Each
    -- structrue has an ID and corresponsing ID for encoding format
    -- For example: ServerStatusDataType has own ID i=862 and following encoders:
    --  * ID i=863 for XML encoding
    --  * ID i=864 for binary encoding
    --  * ID i=15367 for JSON encoding

    for _, ref in pairs(node.refs) do
      if ref.type == HasEncoding and ref.isForward then
        local targetId = ref.target
        local encodingNode = self.Nodes[targetId];
        if encodingNode == nil then
          error("No node for id: " .. targetId)
        end
        local encoding = encodingNode.attrs[AttributeId.BrowseName]
        if encoding.Name == "Default Binary" then
          extObj.binaryId = targetId
          self.ExtObjects[targetId] = extObj
        end
        if encoding.Name == "Default JSON" then
          extObj.jsonId = targetId
          self.ExtObjects[targetId] = extObj
        end
      end
    end
    ::continue::
  end
end

function Model:fillInheritedDefinitions()
  for _,node in pairs(self.Nodes) do
    local definitions = {}
    local type = node
    -- Collect all superTypes
    while type and
          type.attrs[AttributeId.NodeClass] == NodeClass.DataType and
          type.attrs[AttributeId.NodeId] ~= "i=24"
    do
      -- Every DataType contain part of definition
      -- To construct full definition we need also collect
      -- fields from parent types and compose full definition.
      tins(definitions, type.fields)
      local superType
      for _,ref in ipairs(type.refs) do
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

      node.definition = fullDefinition
    end
  end
end


Model.loadXml = require("opcua.model.load_xml")
Model.exportC = require("opcua.model.export_c")
Model.exportJS = require("opcua.model.export_js")
Model.validate = require("opcua.model.validate")

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
      f = require"httpc".create()
      tmp,err=f:request{url=path, method="GET"}
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
  for _, uri in ipairs(self.NamespaceUris) do
    if uri == namespaceUri then
      error("Namespace with URI " .. namespaceUri .. " already exists")
    end
  end

  local index = #self.NamespaceUris + 1
  self.NamespaceUris[index] = namespaceUri
  return index
end

local function createModel()
  local model = {
    Nodes = {},
    ExtObjects = {},
    Models = {},
    NamespaceUris = {},
    Aliases = {},
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

  local model = createModel()
  model.Nodes = require("opcua.model.address_space")()
  model.Models = {
    {
      ModelUri="http://opcfoundation.org/UA/",
      Version="1.05.01"
    }
  }
  model.NamespaceUris = {
    [0] = "http://opcfoundation.org/UA/",
    [1] = config.applicationUri
  }

  model:commit()

  return model
end

return {
  getBaseModel = getBaseModel,
  createModel = createModel
}
