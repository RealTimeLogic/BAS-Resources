local types = require("opcua.types")
local tools = require("opcua.binary.tools")

local AttributeId = types.AttributeId
local NodeClass = types.NodeClass

local tins = table.insert
local strmatch = string.match

local HasSubtype = "i=45"

local DefaultAliases <const> = {
  ["HasComponent"] = "i=47",
  ["HasProperty"] = "i=46",
  ["Organizes"] = "i=35",
  ["HasEventSource"] = "i=36",
  ["HasNotifier"] = "i=48",
  ["HasSubtype"] = "i=45",
  ["HasTypeDefinition"] = "i=40",
  ["HasModellingRule"] = "i=37",
  ["HasEncoding"] = "i=38",
  ["HasDescription"] = "i=39",
  ["HasCause"] = "i=53",
  ["ToState"] = "i=52",
  ["FromState"] = "i=51",
  ["HasEffect"] = "i=54",
  ["HasTrueSubState"] = "i=9004",
  ["HasFalseSubState"] = "i=9005",
  ["HasDictionaryEntry"] = "i=17597",
  ["HasCondition"] = "i=9006",
  ["HasGuard"] = "i=15112",
  ["HasAddIn"] = "i=17604",
  ["HasInterface"] = "i=17603",

  ["Boolean"] = "i=1",
  ["SByte"] = "i=2",
  ["Byte"] = "i=3",
  ["Int16"] = "i=4",
  ["UInt16"] = "i=5",
  ["Int32"] = "i=6",
  ["UInt32"] = "i=7",
  ["Int64"] = "i=8",
  ["UInt64"] = "i=9",
  ["Float"] = "i=10",
  ["Double"] = "i=11",
  ["String"] = "i=12",
  ["DateTime"] = "i=13",
  ["Guid"] = "i=14",
  ["ByteString"] = "i=15",
  ["XmlElement"] = "i=16",
  ["NodeId"] = "i=17",
  ["ExpandedNodeId"] = "i=18",
  ["StatusCode"] = "i=19",
  ["QualifiedName"] = "i=20",
  ["LocalizedText"] = "i=21",
  ["Structure"] = "i=22",
  ["DataValue"] = "i=23",
  ["BaseDataType"] = "i=24",
  ["Variant"] = "i=24",
  ["DiagnosticInfo"] = "i=25",
  ["Number"] = "i=26",
  ["Integer"] = "i=27",
  ["ExtensionObject"] = "i=22",
  ["UtcTime"] = "i=294",
}

local function GetDatatype(dt, aliases)
  local nodeId = aliases[dt] or DefaultAliases[dt] or dt
  return nodeId
end


local trim_spaces = function(s)
  return strmatch(s,"^%s*(.-)%s*$")
end

local function pushParser(context, tagname, parser)
  local len = context.len + 1
  context.len = len
  context.stack[len] = tagname
  context.parsers[len] = parser
end

local NilParser = {
}

function NilParser.createParser (--[[self, tagname]])
  return nil, NilParser
end

local StringElementParser = {
  text = function (self, text)
    self.text = trim_spaces(text)
  end,
  done = function (self)
    tins(self.array, self.text)
  end,
}
local function newStringElementParser(array)
  local parser = { array = array}
  setmetatable(parser, {__index = StringElementParser})
  return parser
end
--[[
local StringAttributeParser = {
  text = function (self, text)
    local value = trim_spaces(text)
    local node = self.Model.Nodes[self.NodeId]
    if node.attrs[self.AttrId] and node.attrs[self.AttrId] ~= value then
      return "Error: Attribute " .. self.AttrId .. " already exists"
    end
    node.attrs[self.AttrId] = value
  end,
}

local function newStringAttributeParser(nodeId, model, attrId)
  local parser = { NodeId = nodeId, Model=model, AttrId = attrId}
  setmetatable(parser, {__index = StringAttributeParser})
  return parser
end
]]

local LocalizedTextAttributeParser = {
  text = function (self, text)
    local value = trim_spaces(text)
    local node = self.Model.Nodes[self.NodeId]
    if node.attrs[self.AttrId] and node.attrs[self.AttrId] ~= value then
      return "Error: Attribute " .. self.AttrId .. " already exists"
    end
    node.attrs[self.AttrId] = {Text=value}
  end,
}

local function newLocalizedTextAttributeParser(nodeId, model, attrId)
  local parser = { NodeId = nodeId, Model=model, AttrId = attrId}
  setmetatable(parser, {__index = LocalizedTextAttributeParser})
  return parser
end

--[[
local QualifiedNameAttributeParser = {
  text = function (self, text)
    local value = trim_spaces(text)
    local node = self.Model.Nodes[self.NodeId]
    if node.attrs[self.AttrId] and node.attrs[self.AttrId] ~= value then
      return "Error: Attribute " .. self.AttrId .. " already exists"
    end
    node.attrs[self.AttrId] = {Name=value}
  end,
}

local function newQualifiedNameAttributeParser(nodeId, model, attrId)
  local parser = { NodeId = nodeId, Model=model, AttrId = attrId}
  setmetatable(parser, {__index = QualifiedNameAttributeParser})
  return parser
end
]]
---------------------------------------------------------
--- Aliases
---------------------------------------------------------

local AliasParser = {
  createParser = function (--[[self, tagname]])
    return "ERROR"
  end,
  attribs = function(self, attribs)
    self.Alias = attribs.Alias
  end,
  text = function(self, text)
    self.Value = trim_spaces(text)
  end,
  done = function(self)
    local aliases = self.model.Aliases
    if aliases[self.Alias] and aliases[self.Alias] ~= self.Value then
      return "Alias " .. self.Alias .. " already exists with the value " .. aliases[self.Alias]
    end

    aliases[self.Alias] = self.Value
    self.Alias = nil
    self.Value = nil
  end,
}

local function newAliasParser(model)
  local parser = {
    model = model
  }

  setmetatable(parser, {__index = AliasParser})
  return parser
end

local AliasesParser = {
  createParser = function (self, tagname)
    if tagname == "Alias" then
      return nil, newAliasParser(self.model)
    end
  end,
}

local function newAliasesParser(model)
  local parser = {
    model = model
  }

  setmetatable(parser, {__index = AliasesParser})
  return parser
end

-------------------------------------------------------------
-- Models
-------------------------------------------------------------

local RequiredModelParser = {
  createParser = function(--[[self, tagName]])
    return "RequiredModel cannot have children"
  end,
  attribs = function(self, attribs)
    self.Model = {
      ModelUri = attribs.ModelUri,
      Version = attribs.Version,
      PublicationDate = attribs.PublicationDate
    }
  end,
  done = function(self)
    tins(self.models, self.Model)
  end
}

local function newRequiredModelParser(models)
  local parser = {
    models = models
  }

  setmetatable(parser, {__index = RequiredModelParser})
  return parser
end

local ModelParser = {
  createParser = function(self, tagname)
    if tagname == "RequiredModel" then
      return nil, newRequiredModelParser(self.Model.RequiredModels)
    end
  end,
  attribs = function(self, attribs)
    self.Model.ModelUri = attribs.ModelUri
    self.Model.Version = attribs.Version
    self.Model.PublicationDate = attribs.PublicationDate
    self.Model.XmlSchemaUri = attribs.XmlSchemaUri
  end,
  done = function(self)
    -- for _,model in ipairs(self.Models) do
    --   if model.ModelUri == self.Model.ModelUri then
    --     return "Model '" .. self.Model.ModelUri .. "' already exists"
    --   end
    -- end

    for _, requiredModel in ipairs(self.Model.RequiredModels) do
      local model
      for _,m in ipairs(self.Models) do
        if m.ModelUri == requiredModel.ModelUri then
          model = m
          break
        end
      end

      if not model then
        return "Required ModelUri " .. requiredModel.ModelUri .. " not found"
      end
    end

    tins(self.Models, self.Model)
  end
}

local function newModelParser(models)
  local parser = {
    Models = models,
    Model = {
      RequiredModels = {}
    }
  }

  setmetatable(parser, {__index = ModelParser})
  return parser
end


local ModelsParser = {
  createParser = function(self, tagname)
    if tagname == "Model" then
      return nil, newModelParser(self.Models)
    end
  end
}
local function newModelsParser(models)
  local parser = {
    Models = models
  }

  setmetatable(parser, {__index = ModelsParser})
  return parser
end

-------------------------------------------------------------
-- NamespaceUris
-------------------------------------------------------------

local NamespaceUriesParser = {
  createParser = function (self, tagname)
    if tagname == "Uri" then
      return nil, newStringElementParser(self.NamespaceUris)
    end
  end,
}

local function newNamespaceUriesParser(namespaceUris)
  local parser = {
    NamespaceUris = namespaceUris
  }

  setmetatable(parser, {__index = NamespaceUriesParser})
  return parser
end

-------------------------------------------------------------
-- Definition
-------------------------------------------------------------

local FieldParser = {
  attribs = function(self, attribs)
    if attribs.Value then
      if not string.match(attribs.Value, "^%d+$") then
        error("value not a number: " .. attribs.Value)
      end
    end

    if attribs.Name == "Value" and attribs.DataType == nil then
      attribs.DataType = "DataValue"
    end

    local field = {
      Name = attribs.Name,
      DataType = GetDatatype(attribs.DataType,self.Model.Aliases),
      Value = tonumber(attribs.Value),
      ValueRank = tonumber(attribs.ValueRank)
    }

    -- Fields of current DataType. Full definition includes
    -- fields also from parent types. Because of this full
    -- definition will be composed later
    local node = self.Model.Nodes[self.NodeId]
    if node.fields == nil then
      node.fields = {}
    end

    for _,f in ipairs(node.fields) do
      if f.Name == field.Name then
        return
      end
    end

    tins(node.fields, field)
  end,
}

local function newFieldParser(nodeId, model)
  local parser = {
    NodeId = nodeId,
    Model = model
  }
  setmetatable(parser, {__index = FieldParser})
  return parser
end


local DefinitionParser = {
  createParser = function(self, tagname)
    if tagname == "Field" then
      return nil, newFieldParser(self.NodeId, self.Model);
    end
  end,
}

local function newDefinitionParser(nodeId, model)
  local parser = {
    NodeId = nodeId,
    Model = model,
  }
  setmetatable(parser, {__index = DefinitionParser})
  return parser
end


-------------------------------------------------------------
-- References
-------------------------------------------------------------

local function addReference(refs, newRef)
  for _,ref in ipairs(refs) do
    if ref.target == newRef.target and ref.type == newRef.type and ref.isForward == newRef.isForward then
      return
    end
  end
  tins(refs, newRef)
end

local ReferenceParser = {
  attribs = function(self, attribs)
    self.RefType = GetDatatype(attribs.ReferenceType, self.Model.Aliases)
    assert(attribs.IsForward == nil or attribs.IsForward == "true" or attribs.IsForward == "false")
    self.IsForward = attribs.IsForward == "true" or attribs.IsForward == nil
  end,
  text = function(self, text)
    self.TargetId = trim_spaces(text)
  end,
  done = function(self)
    local node = self.Model.Nodes[self.NodeId]
    if not node then
      return "Node " .. self.NodeId .. " not found"
    end
    addReference(node.refs, {target=self.TargetId, type=self.RefType, isForward=self.IsForward})

    local targetNode = self.Model.Nodes[self.TargetId]
    if targetNode == nil then
      targetNode = {refs={}, attrs={target=self.TargetId}}
      self.Model.Nodes[self.TargetId] = targetNode
    end
    addReference(targetNode.refs, {target=self.NodeId, type=self.RefType, isForward=(self.IsForward == false)})

    self.RefType = nil
    self.TargetId = nil
    self.IsForward = nil
  end
}

local function newReferenceParser(nodeId, model)
  local parser = {
    NodeId = nodeId,
    Model = model
  }
  setmetatable(parser, {__index = ReferenceParser})
  return parser
end


local ReferencesParser = {
  createParser = function(self, tagname)
    if tagname == "Reference" then
      return nil, newReferenceParser(self.NodeId, self.Model);
    end
  end,
}

local function newReferencesParser(nodeId, model)
  local parser = {
    NodeId = nodeId,
    Model = model,
  }
  setmetatable(parser, {__index = ReferencesParser})
  return parser
end


-------------------------------------------------------------
-- Value Attribute Parser
-------------------------------------------------------------

-- local function hexs(s)
--   return tonumber(s, 16)
-- end

local function toguid(str)
  if not tools.guidValid(str) then
    error("Invalid GUID: " .. str)
  end
  return str
end

local function toboolean(val)
  assert(val == "true" or val == "false")
  return val == "true"
end

local function todatetime(str)
  local dt,ns = ba.datetime(str):ticks()
  return dt+ns/1000000000
end

local function PutValue(variant, typeName, val, isArray)
  if isArray then
    if type(variant[typeName]) ~= "table" then
      variant[typeName] = {}
    end
    tins(variant[typeName], val)
  else
    variant[typeName] = val
  end
end

local StringValueParser = {
  text = function (self, text)
    PutValue(self.Value, "String", trim_spaces(text), self.IsArray)
  end,
}

local function newStringValueParser(value, isarray)
  local parser = {
    IsArray = isarray,
    Value = value
  }
  setmetatable(parser, {__index = StringValueParser})
  return parser
end

local ByteStringValueParser = {
  text = function (self, text)
    local str = string.gsub(text,"[%s\t\n\r]", "")
    self.Text = self.Text..str
  end,
  done = function (self)
    local b64 = ba.b64decode(self.Text)
    PutValue(self.Value, "ByteString", b64, self.IsArray)
  end,
}

local function newByteStringValueParser(value, isArray)
  local parser = {
    IsArray = isArray,
    Text = "",
    Value = value
  }
  setmetatable(parser, {__index = ByteStringValueParser})
  return parser
end

local NumberValueParser = {
  text = function (self, text)
    local str = trim_spaces(text)
    local val = self.Conv(str)
    PutValue(self.Value, self.TypeName, val, self.IsArray)
  end,
}

local function newNumberValueParser(value, typeName, isArray, conv)
  local parser = {
    Conv = conv,
    IsArray = isArray,
    TypeName = typeName,
    Value = value
  }
  setmetatable(parser, {__index = NumberValueParser})
  return parser
end

local LocalizedTextValueParser = {
  createParser = function (self, tagname)
    if tagname == "Text" then
      return nil, newStringValueParser(self.TextValue, false)
    elseif tagname == "Locale" then
      return nil, newStringValueParser(self.LocaleValue, false)
    else
      return "Unknown tag for LocalizedText: " .. tagname
    end
  end,
  done = function (self)
    PutValue(self.Value, "LocalizedText", {Text=self.TextValue.String, Locale=self.LocaleValue.String}, self.IsArray)
  end,
}

local function newLocalizedTextValueParser(value, isArray)
  local parser = {
    IsArray = isArray,
    LocaleValue = {},
    TextValue = {},
    Value = value
  }
  setmetatable(parser, {__index = LocalizedTextValueParser})
  return parser
end


local function newScalarParser(value, tagname, isarray)
  if tagname == "String" then
    return newStringValueParser(value, isarray)
  elseif tagname == "ByteString" then
    return newByteStringValueParser(value, isarray)
  elseif tagname == "DateTime" then
    return newNumberValueParser(value, "DateTime", isarray, todatetime)
  elseif tagname == "Boolean" then
    return newNumberValueParser(value, "Boolean", isarray, toboolean)
  elseif tagname == "Guid" then
    return newNumberValueParser(value, "Guid", isarray, toguid)
  elseif tagname == "Byte" then
    return newNumberValueParser(value, "Byte", isarray, tonumber)
  elseif tagname == "SByte" then
    return newNumberValueParser(value, "SByte", isarray, tonumber)
  elseif tagname == "Int16" then
    return newNumberValueParser(value, "Int16", isarray, tonumber)
  elseif tagname == "UInt16" then
    return newNumberValueParser(value, "UInt16", isarray, tonumber)
  elseif tagname == "UInt32" then
    return newNumberValueParser(value, "UInt32", isarray, tonumber)
  elseif tagname == "Int32" then
    return newNumberValueParser(value, "Int32", isarray, tonumber)
  elseif tagname == "Int64" then
    return newNumberValueParser(value, "Int64", isarray, tonumber)
  elseif tagname == "UInt64" then
    return newNumberValueParser(value, "UInt64", isarray, tonumber)
  elseif tagname == "Float" then
    return newNumberValueParser(value, "Float", isarray, tonumber)
  elseif tagname == "Double" then
    return newNumberValueParser(value, "Double", isarray, tonumber)
  elseif tagname == "LocalizedText" then
    return newLocalizedTextValueParser(value, isarray)
  elseif tagname == "ExtensionObject" then
    return NilParser
    -- return newNumberValueParser(value, "Double", isarray, tonumber)
  else
    error("Unknown scalar type: " .. tagname)
  end
end

local ListValueParser = {
  createParser = function (self, tagname)
    return nil, newScalarParser(self.Value, tagname, true)
  end,
}

local function newListValueParser(value)
  local parser = {
    Value = value
  }
  setmetatable(parser, {__index = ListValueParser})
  return parser
end


local ValueAttributeParser = {
  createParser = function (self, tagname)
    if string.find(tagname, "ListOf") == 1 then
      return nil, newListValueParser(self.Value, tagname)
    else
      return nil, newScalarParser(self.Value, tagname)
    end
end,
  done = function (self)
    local node = self.Model.Nodes[self.NodeId]
    node.attrs[AttributeId.Value] = {Value=self.Value}
  end,
}

local function newValueAttributeParser(nodeId, model)
  local parser = {
    NodeId = nodeId,
    Model = model,
    Value = {}
  }
  setmetatable(parser, {__index = ValueAttributeParser})
  return parser
end

-------------------------------------------------------------
-- NodeClass
-------------------------------------------------------------

local NodeParser = {
  createParser = function(self, tagname)
    if tagname == "DisplayName" then
      return nil, newLocalizedTextAttributeParser(self.NodeId, self.Model, AttributeId.DisplayName)
    elseif tagname == "InverseName" then
      return nil, newLocalizedTextAttributeParser(self.NodeId, self.Model, AttributeId.InverseName)
    elseif tagname == "Description" then
      return nil, newLocalizedTextAttributeParser(self.NodeId, self.Model, AttributeId.Description)
    elseif tagname == "References" then
      return nil, newReferencesParser(self.NodeId, self.Model);
    elseif tagname == "Value" then
      return nil, newValueAttributeParser(self.NodeId, self.Model);
    elseif tagname == "Definition" then
      return nil, newDefinitionParser(self.NodeId, self.Model);
    end
  end,
  attribs = function(self, attribs)
    self.NodeId = attribs.NodeId
    local node = self.Model.Nodes[attribs.NodeId]
    if not node then
      node = {refs = {}, attrs = {}}
      self.Model.Nodes[attribs.NodeId] = node
    end

    node.attrs[AttributeId.NodeId] = attribs.NodeId
    node.attrs[AttributeId.NodeClass] = self.NodeClass
    node.attrs[AttributeId.BrowseName] = {Name=attribs.BrowseName}

    local isAbstract = false
    if attribs.IsAbstract then
      isAbstract = attribs.IsAbstract == "true" or false
    end
    if self.NodeClass == NodeClass.ObjectType then
      node.attrs[AttributeId.IsAbstract] = isAbstract
    elseif self.NodeClass == NodeClass.DataType then
      node.attrs[AttributeId.IsAbstract] = isAbstract
    elseif self.NodeClass == NodeClass.VariableType then
      node.attrs[AttributeId.IsAbstract] = isAbstract
      node.attrs[AttributeId.Rank] = tonumber(attribs.ValueRank)
      node.attrs[AttributeId.DataType] = GetDatatype(attribs.DataType, self.Model.Aliases)
      if attribs.ArrayDimensions then
        local dimensions = {}
        string.gsub(attribs.ArrayDimensions, '[^,]+', function(x) tins(dimensions, tonumber(x)) end)
        node.attrs[AttributeId.ArrayDimensions] = dimensions
      end
      node.attrs[AttributeId.AccessLevel] = 0
      node.attrs[AttributeId.UserAccessLevel] = 0
      node.attrs[AttributeId.Historizing] = false
      if attribs.MinimumSamplingInterval then
        node.attrs[AttributeId.MinimumSamplingInterval] = tonumber(attribs.MinimumSamplingInterval)
      end

    elseif self.NodeClass == NodeClass.Variable then
      node.attrs[AttributeId.Rank] = tonumber(attribs.ValueRank)
      node.attrs[AttributeId.DataType] = GetDatatype(attribs.DataType, self.Model.Aliases)
      if attribs.ArrayDimensions then
        local dimensions = {}
        string.gsub(attribs.ArrayDimensions, '[^,]+', function(x) tins(dimensions, tonumber(x)) end)
        node.attrs[AttributeId.ArrayDimensions] = dimensions
      end
      node.attrs[AttributeId.AccessLevel] = 0
      node.attrs[AttributeId.UserAccessLevel] = 0
      node.attrs[AttributeId.Historizing] = false
      if attribs.MinimumSamplingInterval then
        node.attrs[AttributeId.MinimumSamplingInterval] = tonumber(attribs.MinimumSamplingInterval)
      end
    elseif self.NodeClass == NodeClass.Object then
      node.attrs[AttributeId.EventNotifier] = 0
    elseif self.NodeClass == NodeClass.ReferenceType then
      node.attrs[AttributeId.IsAbstract] = isAbstract
      node.attrs[AttributeId.Symmetric] = attribs.Symmetric == "true"
    elseif self.NodeClass == NodeClass.Method then
      node.attrs[AttributeId.Executable] = true
      node.attrs[AttributeId.UserExecutable] = true
    end
  end,
  done = function()
  end
}

local function newNodeParser(model, nodeClass)
  assert(model)
  local parser = {
    NodeClass = nodeClass,
    Model = model
  }
  setmetatable(parser, {__index = NodeParser})
  return parser
end


-------------------------------------------------------------
-- UANodeSet
-------------------------------------------------------------

local UANodeSetParser = {
  createParser = function(self, tagname)
    if tagname == "Models" then
      return nil, newModelsParser(self.UANodeset.Models);
    elseif tagname == "NamespaceUris" then
      return nil, newNamespaceUriesParser(self.UANodeset.NamespaceUris);
    elseif tagname == "Aliases" then
      return nil, newAliasesParser(self.UANodeset)
    elseif tagname == "UAObject" then
      return nil, newNodeParser(self.UANodeset, NodeClass.Object)
    elseif tagname == "UAObjectType" then
      return nil, newNodeParser(self.UANodeset, NodeClass.ObjectType)
    elseif tagname == "UADataType" then
      return nil, newNodeParser(self.UANodeset, NodeClass.DataType)
    elseif tagname == "UAVariableType" then
      return nil, newNodeParser(self.UANodeset, NodeClass.VariableType)
    elseif tagname == "UAVariable" then
      return nil, newNodeParser(self.UANodeset, NodeClass.Variable)
    elseif tagname == "UAReferenceType" then
      return nil, newNodeParser(self.UANodeset, NodeClass.ReferenceType)
    elseif tagname == "UAMethod" then
      return nil, newNodeParser(self.UANodeset, NodeClass.Method)
    end
  end
}

local function newUANodeSetParser(UANodeset)
  local parser = {
    UANodeset = UANodeset
  }
  setmetatable(parser, {__index = UANodeSetParser})
  return parser
end

-------------------------------------------------------------
-- XML Handler
-------------------------------------------------------------

local xmlHandler = {}
xmlHandler.START_ELEMENT = function (context, tagname, attribs)
  if tagname == "UANodeSet" then
    if context.len ~= 0 then
      return "ERROR"
    end
    pushParser(context, tagname, newUANodeSetParser(context.UANodeSet))
  else
    local curParser = context.parsers[context.len]
    local err, nextParser
    if curParser.createParser then
      err, nextParser = curParser:createParser(tagname)
    end
    if err then
      return err
    end
    if not nextParser then
      nextParser = NilParser
    end
    pushParser(context, tagname, nextParser)
    if nextParser.attribs then
      nextParser:attribs(attribs)
    end
  end
end

xmlHandler.END_ELEMENT = function(context,tagname)
  local len = context.len
  if len == 0 then
    return "ERROR"
  end

  local last = context.stack[len]
  if last ~= tagname then
    return "ERROR"
  end

  local curParser = context.parsers[len]
  if curParser.done then
    local error = curParser:done()
    if error then
      return error
    end
  end

  context.stack[len] = nil
  context.parsers[len] = nil

  len = len - 1
  context.len = len
  if len == 0 then
    return nil, context.UANodeSet
  end
end


xmlHandler.TEXT = function(context, text)
  local len = context.len
  local curParser = context.parsers[len]
  if curParser.text then
    curParser:text(text)
  end
end

xmlHandler.EMPTY_ELEMENT = function(context,tagname,attrs)
  local ret,err,x=xmlHandler.START_ELEMENT(context,tagname,attrs)
  if ret then return ret,err,x end
  return xmlHandler.END_ELEMENT(context,tagname)
end

local function fillInheritedDefinitions(model)
  for _,node in pairs(model.Nodes) do
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
          superType = model.Nodes[ref.target]
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

local function loadModel(model, xml)
  local context = {
    len = 0,
    stack = {},
    parsers = {},
    UANodeSet = model
  }

  local handler = {
    START_ELEMENT = function (_, tagname, attribs)
      return xmlHandler.START_ELEMENT(context, tagname, attribs)
    end,
    END_ELEMENT = function(_, tagname)
      return xmlHandler.END_ELEMENT(context, tagname)
    end,
    TEXT = function(_, text)
      return xmlHandler.TEXT(context, text)
    end,
    EMPTY_ELEMENT = function(_, tagname, attribs)
      return xmlHandler.EMPTY_ELEMENT(context, tagname, attribs)
    end,
  }

  local parser=xparser.create(handler)

  local err, detail
  if type(xml) == "function" then
    while true do
      local chunk = xml()
      if not chunk then
        break
      end

      err, detail = parser:parse(chunk)
      if err ~= true and detail ~= false then
        if err then
          break
        end
        if detail then
          break
        end
      end
    end
  else
    err, detail = parser:parse(xml)
  end

  -- Error happend
  if err then
    return err
  end
  if type(detail) == "string" then
    return detail
  end

  fillInheritedDefinitions(model)

  return err
end

return loadModel
