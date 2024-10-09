local types = require("opcua.types")
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
    if node.attrs[AttributeId.NodeClass] ~= NodeClass.DataType then
      error("Node is not a data type: " .. curDataTypeId)
    end
    if node.attrs[AttributeId.IsAbstract] == nil then
      error("No IsAbstract attribute for node: " .. curDataTypeId)
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

Model.LoadXml = require("opcua.model.load_xml")
Model.ExportC = require("opcua.model.export_c")
Model.ExportJS = require("opcua.model.export_js")
Model.Validate = require("opcua.model.validate")

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

local function getBaseModel()
  local model = createModel()
  local ns0 = require("opcua_ns0")
  model.Nodes = ns0
  model:fillExtensionObjects()

  return model
end

return {
  getBaseModel = getBaseModel,
  createModel = createModel
}
