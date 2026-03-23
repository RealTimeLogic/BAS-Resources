local const = require("opcua.const")
local StatusCode = require("opcua.status_codes")
local address_space_create = require("opcua.model.address_space")
local tools = require("opcua.tools")

local tins = table.insert
local tremove = table.remove

local BadBrowseNameInvalid = StatusCode.BadBrowseNameInvalid
local BadNodeClassInvalid = StatusCode.BadNodeClassInvalid
local BadReferenceTypeIdInvalid = StatusCode.BadReferenceTypeIdInvalid
local BadInternalError = StatusCode.BadInternalError
local BadNodeIdUnknown = StatusCode.BadNodeIdUnknown
local BadNodeAttributesInvalid = StatusCode.BadNodeAttributesInvalid
local BadTypeDefinitionInvalid = StatusCode.BadTypeDefinitionInvalid
local BadAttributeIdInvalid = StatusCode.BadAttributeIdInvalid

local VariantType = const.VariantType
local NodeClass = const.NodeClass
local ValueRank = const.ValueRank
local AccessLevel = const.AccessLevel
local AttributeId = const.AttributeId
local DataTypeId = const.DataTypeId

local HasTypeDefinition = "i=40"
local HasProperty = "i=46"
local HasComponent = "i=47"
local Organizes = "i=35"
local HasSubtype = "i=45"
local HasEncoding = "i=38"

local BaseObjectTypeNodeId = "i=58"
local BaseDataVariableType = "i=63"
local RootNodeId = "i=84"
local FolderTypeId = "i=61"

local PropertyTypeIdNodeId = "i=68"
local ArgumentTypeNodeId = "i=296"

local function createQualifiedName(name)
  if type(name) == "string" then
    name = {Name = name}
  elseif not tools.qualifiedNameValid(name) then
    error(BadBrowseNameInvalid)
  end
  return name
end

local function createBaseNode(model, nodes, nodeClass, browseName, nodeId)
  nodeId = nodeId or model:newNodeId()
  browseName = createQualifiedName(browseName)

  local node = nodes:newNode(nodeId, nodeClass)
  node.Attrs.BrowseName = browseName
  node.Attrs.DisplayName = {Text = browseName.Name}
  return node
end

local function getVariableDataTypeId(variant)
  if not variant then
    return BaseDataVariableType
  end
  if variant.Type == VariantType.ExtensionObject then
    if variant.IsArray and variant.Value and variant.Value[1] then
      return variant.Value[1].TypeId
    elseif variant.Value then
      return variant.Value.TypeId
    end
    return BaseDataVariableType
  end
  return tools.getVariantTypeId(variant)
end

local function getNode(nodes, nodeId)
  local node = nodes[nodeId]
  if node == nil then
    error(BadNodeIdUnknown)
  end

  return node
end

local function toNode(nodes, obj, default)
  if type(obj) == "string" then
    return getNode(nodes, obj)
  elseif type(obj) == "table" then
    if obj.Node ~= nil then
      return obj.Node
    elseif obj.Attrs ~= nil then
      return obj
    end
  elseif obj == nil and default ~= nil then
    return toNode(nodes, default)
  end

  error(BadInternalError)
end

local function toClassNode(nodes, obj, default, class)
  local node = toNode(nodes, obj, default)
  if (node.Attrs.NodeClass & class) == 0 then
    error(BadNodeClassInvalid)
  end
  return node
end

local function toRefTypeNode(nodes, obj, default)
  local node = toNode(nodes, obj, default)
  if node.Attrs.NodeClass ~= NodeClass.ReferenceType then
    error(BadReferenceTypeIdInvalid)
  end
  return node
end

local function toObjectTypeNode(nodes, obj, default)
  return toClassNode(nodes, obj, default, NodeClass.ObjectType)
end

local function toVariableTypeNode(nodes, obj, default)
  return toClassNode(nodes, obj, default, NodeClass.VariableType)
end

local function createVariableNode(model, nodes, browseName, value, variableTypeNode, nodeId)
  -- Only mandatory Variable attributes
  local rank = ValueRank.Any
  local dataType
  local arrayDimensions = nil

  if value ~= nil then
    if not tools.dataValueValid(value) then
      error(BadNodeAttributesInvalid)
    end
    if value.IsArray then
      if value.ArrayDimensions and value.ArrayDimensions[1] ~= nil and value.ArrayDimensions[2] == nil then
        rank = ValueRank.OneDimension
      else
        rank = ValueRank.Any
      end
      if value.ArrayDimensions then
        arrayDimensions = value.ArrayDimensions
      end
    else
      rank = ValueRank.Scalar
    end
    dataType = getVariableDataTypeId(value)
  end

  if variableTypeNode ~= nil then
    local dtype
    if variableTypeNode.Attrs.NodeClass == NodeClass.VariableType then
      dtype = variableTypeNode.Attrs.DataType
    elseif variableTypeNode.Attrs.NodeClass == NodeClass.DataType then
      dtype = variableTypeNode.Attrs.NodeId
    else
      error(BadInternalError)
    end
    if dataType ~= nil and dtype ~= nil and dataType ~= dtype then
      error(BadInternalError)
    end
    dataType = dtype
  end

  local node = createBaseNode(model, nodes, NodeClass.Variable, browseName, nodeId)
  -- Confiuring attribute before setting value: value is checked against other attributes
  node.Attrs.DataType = dataType or BaseDataVariableType
  node.Attrs.Rank = rank
  node.Attrs.Value = value
  node.Attrs.ArrayDimensions = arrayDimensions
  node.Attrs.Historizing = false
  node.Attrs.AccessLevel = AccessLevel.CurrentReadWrite
  node.Attrs.UserAccessLevel = AccessLevel.CurrentReadWrite
  return node
end

local function createVariableTypeNode(model, nodes, browseName, value, nodeId)
  -- Only mandatory Variable attributes
  local node = createBaseNode(model, nodes, NodeClass.VariableType, browseName, nodeId)
  if value then
    node.Attrs.Value = value
  end
  node.Attrs.DataType = getVariableDataTypeId(value)
  node.Attrs.Rank = ValueRank.Any
  node.Attrs.IsAbstract = false
  return node
end

local function createObjectNode(model, nodes, browseName, nodeId)
  local node = createBaseNode(model, nodes, NodeClass.Object, browseName, nodeId)
  node.Attrs.EventNotifier = 0
  return node
end

local function createObjectTypeNode(model, nodes, browseName, nodeId)
  local node = createBaseNode(model, nodes, NodeClass.ObjectType, browseName, nodeId)
  node.Attrs.IsAbstract = false
  return node
end

local function createMethodNode(model, nodes, browseName, func, nodeId)
  local node = createBaseNode(model, nodes, NodeClass.Method, browseName, nodeId)
  node.Attrs.Executable = true
  node.Attrs.UserExecutable = true
  node.Attrs.NodeCallback = func
  return node
end

local function createDataTypeNode(model, nodes, browseName, nodeId)
  local node = createBaseNode(model, nodes, NodeClass.DataType, browseName, nodeId)
  node.Attrs.IsAbstract = false
  return node
end

local browser = {}

local function newBrowser(model, nodes, node)
  assert(nodes, "Address space empty")

  if node == nil then
    node = nodes[RootNodeId]
  elseif type(node) == "string" then
    node = nodes[node]
  end

  if not node then
    error(BadNodeIdUnknown)
  end

  assert(node, "No root node")

  local obj = {
    Model = model,
    Nodes = nodes,
    Node = node,
    Attrs = node.Attrs
  }

  setmetatable(obj, {__index=browser})

  return obj
end

function browser:children()
  local children = {}
  for _, ref in ipairs(self.Node.Refs) do
    if ref.isForward then
      local targetNode = self.Nodes[ref.target]
      if targetNode then
        tins(children, newBrowser(self.Model, self.Nodes, targetNode))
      end
    end
  end
  return children
end

function browser:path(names)
  local node = self.Nodes:resolvePath(self.Node.Attrs[AttributeId.NodeId], names)
  return newBrowser(self.Model, self.Nodes, node)
end

function browser:getNode(nodeId)
  local node = getNode(self.Nodes, nodeId)
  return newBrowser(self.Model, self.Nodes, node)
end

function browser:objectsFolder()
  return self:getNode("i=85")
end

function browser:typesFolder()
  return self:getNode("i=86")
end


local function addReference(sourceNode, targetNode, referenceTypeId)
  tins(sourceNode.Refs, {
    isForward = true,
    target = targetNode.Attrs.NodeId,
    type = referenceTypeId,
  })

  tins(targetNode.Refs, {
    isForward = false,
    target = sourceNode.Attrs.NodeId,
    type = referenceTypeId,
  })
end

local function expandHierarchy(startNode, rootNode, model, nodes)
  local newNodes = {}
  local stack = { {type=rootNode, object=startNode} }

  -- Depth-first search around fields of object type
  while #stack > 0 do
    local item = tremove(stack)
    local typeNode = item.type
    local objectNode = item.object

    for _, ref in ipairs(typeNode.Refs) do
      if not ref.isForward and ref.target ~= typeNode.Attrs.NodeId then
        goto continue
      end

      local refNode = nodes[ref.target]
      if not refNode then
        error(BadNodeIdUnknown)
      end

      if ref.type == HasTypeDefinition then
        addReference(objectNode, refNode, ref.type)
      elseif ref.type == HasProperty or ref.type == HasComponent then
        local objectField = nodes:newNode(model:newNodeId(), refNode.Attrs)
        addReference(objectNode, objectField, ref.type)
        tins(newNodes, objectField)
        tins(stack, {type=refNode, object=objectField})
      end

      ::continue::
    end
  end

  for _, node in ipairs(newNodes) do
    nodes:saveNode(node)
  end

end

local addProperty
local addVariable
local addObject
local addMethod
local addField
local setValues
local setInputArguments
local setOutputArguments

local newObject
local newObjectType
local newVariable
local newVariableType
local newMethod
local newReferenceType
local newStructure
local newEnum
local newEditNode
local newDataType


local function getChild(self, propertyName, referenceTypeId, nodeClassMask)
  local element = {
    TargetName = {Name=propertyName},
    ReferenceTypeId = referenceTypeId,
    IsInverse = false,
    IncludeSubtypes = false,
  }

  local node = self.Nodes:resolvePath(self.Node, {element})
  if (node.Attrs.NodeClass & nodeClassMask) == 0 then
    error(BadNodeClassInvalid)
  end
  return node
end

local function getProperty(self, propertyName)
  local node = getChild(self, propertyName, HasProperty, NodeClass.Variable)
  return newEditNode(self, node)
end

local function getComponent(self, propertyName)
  local node = getChild(self, propertyName, HasComponent, NodeClass.Variable | NodeClass.Object)
  return newEditNode(self, node)
end

local function getMethod(self, propertyName)
  local node = getChild(self, propertyName, HasComponent, NodeClass.Method)
  return newEditNode(self, node)
end


addObject = function (self, browseName, objectType, nodeId, refType)
  local objectTypeNode = toObjectTypeNode(self.Nodes, objectType, BaseObjectTypeNodeId)
  local refTypeNode = toRefTypeNode(self.Nodes, refType, HasComponent)

  local newObjectNode = createObjectNode(self.Model, self.Nodes, browseName, nodeId)
  expandHierarchy(newObjectNode, objectTypeNode, self.Model, self.Nodes)
  addReference(self.Node, newObjectNode, refTypeNode.Attrs.NodeId)
  addReference(newObjectNode, objectTypeNode, HasTypeDefinition)

  self.Nodes:saveNode(newObjectNode)
  self.Nodes:saveNode(self.Node)

  return newObject(newObjectNode, self.Model, self.Nodes)
end

addVariable = function (self, browseName, value, variableType, nodeId, refType)
  -- Only mandatory Variable attributes
  local refTypeNode = toRefTypeNode(self.Nodes, refType, HasComponent)
  local variableTypeNode = variableType and toVariableTypeNode(self.Nodes, variableType)
  local newNode = createVariableNode(self.Model, self.Nodes, browseName, value, variableTypeNode, nodeId)

  if variableType ~= nil then
    expandHierarchy(newNode, variableTypeNode, self.Model, self.Nodes)
    addReference(newNode, variableTypeNode, HasTypeDefinition)
  end

  addReference(self.Node, newNode, refTypeNode.Attrs.NodeId)

  self.Nodes:saveNode(newNode)

  return newVariable(newNode, self.Model, self.Nodes)
end

addProperty = function (self, browseName, value, variableType, nodeId, refType)
  assert(self.Node.Attrs.NodeClass == NodeClass.Object or self.Node.Attrs.NodeClass == NodeClass.ObjectType, "Properties can be added only to objects")

  local variableTypeNode = variableType and toClassNode(self.Nodes, variableType, nil, NodeClass.VariableType | NodeClass.DataType)
  local newNode = createVariableNode(self.Model, self.Nodes, browseName, value, variableTypeNode, nodeId)

  local propertyTypeNode = toVariableTypeNode(self.Nodes, PropertyTypeIdNodeId)
  addReference(newNode, propertyTypeNode, HasTypeDefinition)
  local refTypeNode = toRefTypeNode(self.Nodes, refType, HasProperty)
  addReference(self.Node, newNode, refTypeNode.Attrs.NodeId)

  self.Nodes:saveNode(newNode)
  self.Nodes:saveNode(propertyTypeNode)

  return newVariable(newNode, self.Model, self.Nodes)
end

local function addFolder(self, browseName, nodeId)
  return self:addObject(browseName, FolderTypeId, nodeId, Organizes)
end

local function newArgumentsValue(_, arguments)
  local inputValues = {}
  for _, argument in ipairs(arguments) do
    tins(inputValues, {
        TypeId = ArgumentTypeNodeId,
        Body = {
          Name = argument.Name,
          DataType = argument.DataType,
          ValueRank = argument.ValueRank or ValueRank.Any,
          Description = argument.Description or {},
          ArrayDimensions = argument.ArrayDimensions or {}
        }
    })
  end

  local inputArgumentsValue = {
    Type = VariantType.ExtensionObject,
    IsArray=true,
    Value = inputValues
  }

  return inputArgumentsValue
end

addMethod = function(self, browseName, func, inputArguments, outputArguments, nodeId)
  assert(type(func) == "function", "no function provided")

  local methodNode = createMethodNode(self.Model, self.Nodes, browseName, func, nodeId)

  local propertyTypeNode = toNode(self.Nodes, PropertyTypeIdNodeId)

  local inputArgumentsValue = newArgumentsValue(self, inputArguments)
  local outputArgumentsValue = newArgumentsValue(self, outputArguments)

  local inputArgumentsNode = createVariableNode(self.Model, self.Nodes, "InputArguments", inputArgumentsValue)
  inputArgumentsNode.Attrs.Rank = ValueRank.OneDimension
  inputArgumentsNode.Attrs.ArrayDimensions = {1}
  addReference(inputArgumentsNode, propertyTypeNode, HasTypeDefinition)

  local outputArgumentsNode = createVariableNode(self.Model, self.Nodes, "OutputArguments", outputArgumentsValue)
  outputArgumentsNode.Attrs.Rank = ValueRank.OneDimension
  outputArgumentsNode.Attrs.ArrayDimensions = {1}
  addReference(outputArgumentsNode, propertyTypeNode, HasTypeDefinition)

  addReference(methodNode, inputArgumentsNode, HasProperty)
  addReference(methodNode, outputArgumentsNode, HasProperty)
  addReference(self.Node, methodNode, HasComponent)

  self.Nodes:saveNode(inputArgumentsNode)
  self.Nodes:saveNode(outputArgumentsNode)
  self.Nodes:saveNode(methodNode)

  return newMethod(methodNode, self.Model, self.Nodes)
end

function setInputArguments(self, inputArguments)
  local value = newArgumentsValue(self, inputArguments)
  local inputArgumentsNode = self:path{"InputArguments"}
  inputArgumentsNode.Attrs.Value = value
  self.Nodes:saveNode(inputArgumentsNode)
end

function setOutputArguments(self, outputArguments)
  local value = newArgumentsValue(self, outputArguments)
  local outputArgumentsNode = self:path{"OutputArguments"}
  outputArgumentsNode.Attrs.Value = value
  self.Nodes:saveNode(outputArgumentsNode)
end

addField = function (self, browseName, dataType, rank, _) -- luacheck: ignore 212
  -- Only mandatory Variable attributes
  local node = self.Node
  local definition = node.Attrs.DataTypeDefinition or {}
  for _, field in ipairs(definition) do
    if field.Name == browseName then
      error(BadAttributeIdInvalid)
    end
  end

  tins(definition, {
    Name = browseName,
    DisplayName = {Text = browseName.Name},
    DataType = dataType,
    ValueRank = rank,
    IsOptional = false,
  })

  node.Attrs.DataTypeDefinition = definition

  self.Nodes:saveNode(node)
end

local function setFields(self, fields)
  local definition = {}
  for _, field in ipairs(fields) do
    tins(definition, field)
  end
  self.Node.Attrs.DataTypeDefinition = definition
  self.Nodes:saveNode(self.Node)
end

local function getField(self, fieldName)
  local definition = self.Node.Attrs.DataTypeDefinition
  for _, field in ipairs(definition) do
    if field.Name == fieldName then
      return field
    end
  end
  error(BadAttributeIdInvalid)
end

local function getFields(self)
  return self.Node.Attrs.DataTypeDefinition
end

function setValues(self, values)
  local definition = {}
  for i, value in ipairs(values) do
    tins(definition, {
      Name = value,
      DisplayName = {Text = value},
      Value = i - 1,
    })
  end
  self.Node.Attrs.DataTypeDefinition = definition
end


local function editPath(self, names)
  local node = self.Nodes:resolvePath(self.Node or RootNodeId, names)
  return newEditNode(self, node)
end

local function newNodeBase(node, model, nodes, base)
  local obj = {
    Node = node,
    Attrs = node.Attrs,
    Model = model,
    Nodes = nodes,
  }
  setmetatable(obj, {__index=base})
  return obj
end

local function getValues(self)
  local definition = self.Node.Attrs.DataTypeDefinition
  local values = {}
  for _, field in ipairs(definition) do
    tins(values, field.Name)
  end
  return values
end

-- All objects must have three fields:
--  Node,
--  Attrs,
--  Model

local Object = {
  addProperty = addProperty,
  addVariable = addVariable,
  addObject = addObject,
  addFolder = addFolder,
  addMethod = addMethod,

  getProperty = getProperty,
  getVariable = getProperty,
  getComponent = getComponent,
  getMethod = getMethod,
  path = editPath
}

local ObjectType = {
  addProperty = addProperty,
  addVariable = addVariable,
  addObject = addObject,
  addFolder = addFolder,
  addMethod = addMethod,

  getProperty = getProperty,
  getVariable = getProperty,
  getComponent = getComponent,
  getMethod = getMethod,
  path = editPath
}

local Variable = {
  addVariable = addVariable,
  getVariable = getProperty,
  path = editPath
}

local VariableType = {
  addVariable = addVariable,
  getVariable = getProperty,
  path = editPath
}

local ReferenceType = {
}

local Structure = {
  addField = addField,
  setFields = setFields,
  getField = getField,
  getFields = getFields,
  path = editPath,
}

local Enum = {
  setValues = setValues,
  getValues = getValues,
  path = editPath,
}

local Method = {
  setInputArguments = setInputArguments,
  setOutputArguments = setOutputArguments,
  path = editPath,
}

function Variable:setValueCallback(func)
  assert(type(func) == "function", "valueCallback must be a function")
  self.Node.Attrs.NodeCallback = func
end

newObject = function(node, model, nodes)
  return newNodeBase(node, model, nodes, Object)
end

newObjectType = function(node, model, nodes)
  return newNodeBase(node, model, nodes, ObjectType)
end

newVariable = function (node, model, nodes)
  return newNodeBase(node, model, nodes, Variable)
end

newVariableType = function(node, model, nodes)
  return newNodeBase(node, model, nodes, VariableType)
end

newMethod = function(node, model, nodes)
  return newNodeBase(node, model, nodes, Method)
end

newReferenceType = function(node, model, nodes)
  return newNodeBase(node, model, nodes, ReferenceType)
end

newStructure = function(node, model, nodes)
  return newNodeBase(node, model, nodes, Structure)
end

newEnum = function(node, model, nodes)
  return newNodeBase(node, model, nodes, Enum)
end

newDataType = function(node, model, nodes)
  if node.BaseId == "i=22" then
    return newStructure(node, model, nodes)
  elseif node.BaseId == "i=29" then
    return newEnum(node, model, nodes)
  else
    error("Unknown data type")
  end
end

local editor = {}

function editor:addObjectType(browseName)
  assert(type(browseName) == "string", "browseName must be a string")
  local objectTypeNode = createObjectTypeNode(self.Model, self.Nodes, browseName)
  local baseObjectTypeNode = toObjectTypeNode(self.Nodes, BaseObjectTypeNodeId)
  addReference(baseObjectTypeNode, objectTypeNode, HasSubtype)
  self.Nodes:saveNode(objectTypeNode)
  self.Nodes:saveNode(baseObjectTypeNode)
  return newObjectType(objectTypeNode, self.Model, self.Nodes)
end

function editor:addVariableType(browseName)
  local variableTypeNode = createVariableTypeNode(self.Model, self.Nodes, browseName)
  local baseVariableTypeNode = toVariableTypeNode(self.Nodes, BaseDataVariableType)
  addReference(baseVariableTypeNode, variableTypeNode, HasSubtype)
  self.Nodes:saveNode(variableTypeNode)
  self.Nodes:saveNode(baseVariableTypeNode)
  return newVariableType(variableTypeNode, self.Model, self.Nodes)
end

function editor:addStructure(browseName, nodeId)
  local baseDataTypeNode = self.Nodes[DataTypeId.Structure]
  if not baseDataTypeNode then
    error("BaseDataType not found")
  end

  local dataTypeNode = createDataTypeNode(self.Model, self.Nodes, browseName, nodeId)
  dataTypeNode.BaseId = DataTypeId.Structure
  dataTypeNode.JsonId = self.Model:newNodeId()
  dataTypeNode.BinaryId = self.Model:newNodeId()
  dataTypeNode.DataTypeId = dataTypeNode.Attrs.NodeId
  addReference(baseDataTypeNode, dataTypeNode, HasSubtype)

  local binaryNode = createObjectNode(self.Model, self.Nodes, "Default Binary", dataTypeNode.BinaryId)
  binaryNode.BaseId = dataTypeNode.BaseId
  binaryNode.JsonId = dataTypeNode.JsonId
  binaryNode.BinaryId = dataTypeNode.BinaryId
  binaryNode.DataTypeId = dataTypeNode.DataTypeId
  addReference(dataTypeNode, binaryNode, HasEncoding)

  local baseNodeType = self:getNode('i=76')
  addReference(binaryNode, baseNodeType.Node, HasTypeDefinition)

  local jsonNode = createObjectNode(self.Model, self.Nodes, "Default JSON", dataTypeNode.JsonId)
  binaryNode.BaseId = dataTypeNode.BaseId
  binaryNode.JsonId = dataTypeNode.JsonId
  jsonNode.BinaryId = dataTypeNode.BinaryId
  jsonNode.DataTypeId = dataTypeNode.DataTypeId
  addReference(dataTypeNode, jsonNode, HasEncoding)
  addReference(jsonNode, baseNodeType.Node, HasTypeDefinition)

  self.Nodes:saveNode(dataTypeNode)
  self.Nodes:saveNode(binaryNode)
  self.Nodes:saveNode(jsonNode)
  self.Nodes:saveNode(baseDataTypeNode)

  return newStructure(dataTypeNode, self.Model, self.Nodes)
end


function editor:addEnum(browseName, values, nodeId)
  local baseDataTypeNode = self.Nodes[DataTypeId.Enumeration]
  if not baseDataTypeNode then
    error("BaseEnum not found")
  end

  local dataTypeNode = createDataTypeNode(self.Model, self.Nodes, browseName, nodeId)
  local definition = {}
  for i, value in ipairs(values) do
    if type(value) ~= "string" then
      error(BadTypeDefinitionInvalid)
    end
    tins(definition, {
      Name = value,
      DisplayName = {Text = value},
      Value = i - 1,
    })
  end
  dataTypeNode.Attrs.DataTypeDefinition = definition

  addReference(baseDataTypeNode, dataTypeNode, HasSubtype)

  self.Nodes:saveNode(dataTypeNode)
  self.Nodes:saveNode(baseDataTypeNode)

  return newEnum(dataTypeNode, self.Model, self.Nodes)
end

function editor:addObject(browseName, objectType, nodeId, refType)
  local objects = self:path{"Objects"}
  return objects:addObject(browseName, objectType, nodeId, refType)
end

local nodeFactoryMap <const> = {
  [NodeClass.Object] = newObject,
  [NodeClass.ObjectType] = newObjectType,
  [NodeClass.Variable] = newVariable,
  [NodeClass.VariableType] = newVariableType,
  [NodeClass.Method] = newMethod,
  [NodeClass.ReferenceType] = newReferenceType,
  [NodeClass.DataType] = newDataType,
}

newEditNode = function(self, node)
  if type(node) == "string" then
    node = getNode(self.Nodes, node)
  end

  local factory = nodeFactoryMap[node.Attrs.NodeClass]
  if not factory then
    error(BadNodeIdUnknown)
  end
  self.Nodes:saveNode(node)
  return factory(node, self.Model, self.Nodes)
end

function editor:findNode(node)
  if type(node) == "string" then
    node = self.Nodes[node]
  end
  if node == nil then
    return nil
  end
  return newEditNode(self, node)
end

editor.getNode = newEditNode

editor.path = editPath

function editor:objectsFolder()
  return self:getNode("i=85")
end

function editor:typesFolder()
  return self:getNode("i=86")
end

function editor:save()
  self.Nodes:save()
end

return {
  newBrowser = newBrowser,
  newEditor = function(model)
    local newEditor = {
      Model = model,
      Nodes = address_space_create(model.Nodes),
    }
    setmetatable(newEditor, {__index=editor})
    return newEditor
  end
}
