local const = require("opcua.const")
local tools = require("opcua.tools")
local nodeId = require("opcua.node_id")
local compat = require("opcua.compat")

local AttributeId = const.AttributeId
local NodeClass = const.NodeClass
local VariantType = const.VariantType

local tins = table.insert
local strmatch = string.match
local fmt = string.format

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
  local nId = aliases[dt] or DefaultAliases[dt] or dt
  return nId
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

local LocalizedTextAttributeParser = {
  text = function (self, text)
    self.Text = self.Text and self.Text .. text or text
  end,
  done = function (self)
    local value = trim_spaces(self.Text or "")
    local node = self.Model.Nodes[self.NodeId]
    if node.Attrs[self.AttrId] and node.Attrs[self.AttrId].Text ~= value then
      return "Error: Attribute " .. self.AttrId .. " already exists"
    end
    node.Attrs[self.AttrId] = {Text=value}
  end,
}

local function newLocalizedTextAttributeParser(nId, model, attrId)
  local parser = { NodeId = nId, Model=model, AttrId = attrId}
  setmetatable(parser, {__index = LocalizedTextAttributeParser})
  return parser
end

--[[
local QualifiedNameAttributeParser = {
  text = function (self, text)
    local value = trim_spaces(text)
    local node = self.Model.Nodes[self.NodeId]
    if node.Attrs[self.AttrId] and node.Attrs[self.AttrId] ~= value then
      return "Error: Attribute " .. self.AttrId .. " already exists"
    end
    node.Attrs[self.AttrId] = {Name=value}
  end,
}

local function newQualifiedNameAttributeParser(nId, model, attrId)
  local parser = { NodeId = nId, Model=model, AttrId = attrId}
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
    self.Value = self.Value and self.Value .. text or text
  end,
  done = function(self)
    local value = trim_spaces(self.Value or "")
    local aliases = self.model.Aliases
    if aliases[self.Alias] and aliases[self.Alias] ~= value then
      return "Alias " .. self.Alias .. " already exists with the value " .. aliases[self.Alias]
    end

    aliases[self.Alias] = value
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
    self.Models[self.Model.ModelUri] =  self.Model
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

local NamespaceUriParser = {
  text = function (self, text)
    self.Uri = trim_spaces(text)
  end,
  done = function (self)
    if self.Uri == nil or self.Uri == "" then
      error("Invalid namespace URI")
    end
    local index = self.UaNodeset.NsIndex + 1
    self.UaNodeset.NsIndex = index

    local namespace = {
      Index = index,
      NewIndex = index,
      NamespaceUri = self.Uri,
    }
    self.UaNodeset.Namespaces[index] = namespace
    self.UaNodeset.Namespaces[self.Uri] = namespace
  end,
}
local function newNamespaceUriParser(uaNodeset)
  local parser = {
    UaNodeset = uaNodeset
  }
  setmetatable(parser, {__index = NamespaceUriParser})
  return parser
end


local NamespacesParser = {
  createParser = function (self, tagname)
    if tagname == "Uri" then
      return nil, newNamespaceUriParser(self.UaNodeset)
    end
  end,
}

local function newNamespacesParser(uaNodeset)
  local parser = {
    UaNodeset = uaNodeset
  }

  setmetatable(parser, {__index = NamespacesParser})
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
      DataType = GetDatatype(attribs.DataType or "Variant",self.Model.Aliases),
      Value = tonumber(attribs.Value),
      ValueRank = tonumber(attribs.ValueRank)
    }

    -- Fields of current DataType. Full definition includes
    -- fields also from parent ua. Because of this full
    -- definition will be composed later
    local node = self.Model.Nodes[self.NodeId]
    if node.Attrs[AttributeId.DataTypeDefinition] == nil then
      node.Attrs[AttributeId.DataTypeDefinition] = {}
    end

    for _,f in ipairs(node.Attrs[AttributeId.DataTypeDefinition]) do
      if f.Name == field.Name then
        return
      end
    end

    tins(node.Attrs[AttributeId.DataTypeDefinition], field)
  end,
}

local function newFieldParser(nId, model)
  local parser = {
    NodeId = nId,
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

local function newDefinitionParser(nId, model)
  local parser = {
    NodeId = nId,
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
    self.TargetId = self.TargetId and self.TargetId .. text or text
  end,
  done = function(self)
    local targetId = trim_spaces(self.TargetId or "")
    local node = self.Model.Nodes[self.NodeId]
    if not node then
      return "Node " .. self.NodeId .. " not found"
    end
    addReference(node.Refs, {target=targetId, type=self.RefType, isForward=self.IsForward})

    self.RefType = nil
    self.TargetId = nil
    self.IsForward = nil
  end
}

local function newReferenceParser(nId, model)
  local parser = {
    NodeId = nId,
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

local function newReferencesParser(nId, model)
  local parser = {
    NodeId = nId,
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

local function PutValue(variant, vartype, val, isArray)
  variant.Type = vartype
  if isArray then
    variant.IsArray = true
    if type(variant.Value) ~= "table" then
      variant.Value = {}
    end
    tins(variant.Value, val)
  else
    variant.Value = val
  end
end

local StringValueParser = {
  text = function (self, text)
    self.Text = self.Text and self.Text .. text or text
  end,
  done = function (self)
    if not self.Text and self.Value.Type == nil then
      PutValue(self.Value, VariantType.String, nil, self.IsArray)
    elseif self.Text then
      PutValue(self.Value, VariantType.String, trim_spaces(self.Text), self.IsArray)
    end
  end
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
    local b64 = compat.b64decode(self.Text)
    PutValue(self.Value, VariantType.ByteString, b64, self.IsArray)
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
    self.Text = self.Text and self.Text .. text or text
  end,
  done = function(self)
    if self.Text then
      local str = trim_spaces(self.Text)
      local val = self.Conv(str)
      PutValue(self.Value, self.Type, val, self.IsArray)
    end
  end,
}

local function newNumberValueParser(value, type, isArray, conv)
  local parser = {
    Conv = conv,
    IsArray = isArray,
    Type = type,
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
    PutValue(self.Value, VariantType.LocalizedText, {Text=self.TextValue.Value, Locale=self.LocaleValue.Value}, self.IsArray)
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

local QualifiedNameValueParser = {
  createParser = function (self, tagname)
    if tagname == "NamespaceIndex" then
      return nil, newNumberValueParser(self.NamespaceIndex, VariantType.UInt16, false, tonumber)
    elseif tagname == "Name" then
      return nil, newStringValueParser(self.Name, false)
    else
      return "Unknown tag inside QualifiedName: " .. tagname
    end
  end,
  done = function (self)
    PutValue(self.Value, VariantType.QualifiedName, {Name=self.Name.Value, ns=self.NamespaceIndex.Value}, self.IsArray)
  end,
}

local function newQualifiedNameValueParser(value, isArray)
  local parser = {
    IsArray = isArray,
    NamespaceIndex = {},
    Name = {},
    Value = value
  }
  setmetatable(parser, {__index = QualifiedNameValueParser})
  return parser
end

local NodeIdValueParser = {
  createParser = function (self, tagname)
    if tagname == "Identifier" then
      return nil, newStringValueParser(self.NodeId, false)
    else
      return "Unknown tag inside NodeId: " .. tagname
    end
  end,
  done = function (self)
    PutValue(self.Value, VariantType.NodeId, self.NodeId.Value, self.IsArray)
  end,
}

local function newNodeIdValueParser(value, isArray)
  local parser = {
    IsArray = isArray,
    NodeId = {},
    Value = value
  }
  setmetatable(parser, {__index = NodeIdValueParser})
  return parser
end


local function newScalarParser(value, tagname, isarray)
  if tagname == "String" then
    return newStringValueParser(value, isarray)
  elseif tagname == "ByteString" then
    return newByteStringValueParser(value, isarray)
  elseif tagname == "DateTime" then
    return newNumberValueParser(value, VariantType.DateTime, isarray, compat.to_timestamp)
  elseif tagname == "Boolean" then
    return newNumberValueParser(value, VariantType.Boolean, isarray, toboolean)
  elseif tagname == "Guid" then
    return newNumberValueParser(value, VariantType.Guid, isarray, toguid)
  elseif tagname == "Byte" then
    return newNumberValueParser(value, VariantType.Byte, isarray, tonumber)
  elseif tagname == "SByte" then
    return newNumberValueParser(value, VariantType.SByte, isarray, tonumber)
  elseif tagname == "Int16" then
    return newNumberValueParser(value, VariantType.Int16, isarray, tonumber)
  elseif tagname == "UInt16" then
    return newNumberValueParser(value, VariantType.UInt16, isarray, tonumber)
  elseif tagname == "UInt32" then
    return newNumberValueParser(value, VariantType.UInt32, isarray, tonumber)
  elseif tagname == "Int32" then
    return newNumberValueParser(value, VariantType.Int32, isarray, tonumber)
  elseif tagname == "Int64" then
    return newNumberValueParser(value, VariantType.Int64, isarray, tonumber)
  elseif tagname == "UInt64" then
    return newNumberValueParser(value, VariantType.UInt64, isarray, tonumber)
  elseif tagname == "Float" then
    return newNumberValueParser(value, VariantType.Float, isarray, tonumber)
  elseif tagname == "Double" then
    return newNumberValueParser(value, VariantType.Double, isarray, tonumber)
  elseif tagname == "LocalizedText" then
    return newLocalizedTextValueParser(value, isarray)
  elseif tagname == "QualifiedName" then
    return newQualifiedNameValueParser(value, isarray)
  elseif tagname == "NodeId" then
    return newNodeIdValueParser(value, isarray)
  elseif tagname == "ExtensionObject" then
    value.Type=VariantType.ExtensionObject
    value.Value = {TypeId="i=0"}
    return NilParser
    -- return newNumberValueParser(value, "Double", isarray, tonumber)
  elseif tagname == "ListOfExtensionObject" then
    value.Type=VariantType.ExtensionObject
    value.Value = {TypeId="i=0"}
    return NilParser
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
      return nil, newListValueParser(self.Value)
    else
      return nil, newScalarParser(self.Value, tagname)
    end
end,
  done = function (self)
    local node = self.Model.Nodes[self.NodeId]
    node.Attrs[AttributeId.Value] = self.Value
  end,
}

local function newValueAttributeParser(nId, model)
  local parser = {
    NodeId = nId,
    Model = model,
    Value = {}
  }
  setmetatable(parser, {__index = ValueAttributeParser})
  return parser
end

-------------------------------------------------------------
-- NodeClass
-------------------------------------------------------------

local function parseBrowseName(name)
  local ns
  if name:find(":", 1, true) then
    ns, name = name:match("^([0-9]+):(.*)$")
    if not ns or not name then
      error("Invalid browse name: " .. name)
    end
    ns = tonumber(ns)
    if ns == 0 then
      ns = nil
    end
  end
  return {Name = name, ns = ns}
end

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
      node = {Refs = {}, Attrs = {}}
      self.Model.Nodes[attribs.NodeId] = node
    end

    node.Attrs[AttributeId.NodeId] = attribs.NodeId
    node.Attrs[AttributeId.NodeClass] = self.NodeClass
    node.Attrs[AttributeId.BrowseName] = parseBrowseName(attribs.BrowseName)

    local isAbstract = false
    if attribs.IsAbstract then
      isAbstract = attribs.IsAbstract == "true" or false
    end
    if self.NodeClass == NodeClass.ObjectType then
      node.Attrs[AttributeId.IsAbstract] = isAbstract
    elseif self.NodeClass == NodeClass.DataType then
      node.Attrs[AttributeId.IsAbstract] = isAbstract
    elseif self.NodeClass == NodeClass.VariableType then
      node.Attrs[AttributeId.IsAbstract] = isAbstract
      node.Attrs[AttributeId.Rank] = tonumber(attribs.ValueRank)
      node.Attrs[AttributeId.DataType] = GetDatatype(attribs.DataType, self.Model.Aliases)
      if attribs.ArrayDimensions then
        local dimensions = {}
        string.gsub(attribs.ArrayDimensions, '[^,]+', function(x) tins(dimensions, tonumber(x)) end)
        node.Attrs[AttributeId.ArrayDimensions] = dimensions
      end
      node.Attrs[AttributeId.AccessLevel] = 0
      node.Attrs[AttributeId.UserAccessLevel] = 0
      node.Attrs[AttributeId.Historizing] = false
      if attribs.MinimumSamplingInterval then
        node.Attrs[AttributeId.MinimumSamplingInterval] = tonumber(attribs.MinimumSamplingInterval)
      end

    elseif self.NodeClass == NodeClass.Variable then
      node.Attrs[AttributeId.Rank] = tonumber(attribs.ValueRank)
      node.Attrs[AttributeId.DataType] = GetDatatype(attribs.DataType, self.Model.Aliases)
      if attribs.ArrayDimensions then
        local dimensions = {}
        string.gsub(attribs.ArrayDimensions, '[^,]+', function(x) tins(dimensions, tonumber(x)) end)
        node.Attrs[AttributeId.ArrayDimensions] = dimensions
      end
      node.Attrs[AttributeId.AccessLevel] = 0
      node.Attrs[AttributeId.UserAccessLevel] = 0
      node.Attrs[AttributeId.Historizing] = false
      if attribs.MinimumSamplingInterval then
        node.Attrs[AttributeId.MinimumSamplingInterval] = tonumber(attribs.MinimumSamplingInterval)
      end
    elseif self.NodeClass == NodeClass.Object then
      node.Attrs[AttributeId.EventNotifier] = 0
    elseif self.NodeClass == NodeClass.ReferenceType then
      node.Attrs[AttributeId.IsAbstract] = isAbstract
      node.Attrs[AttributeId.Symmetric] = attribs.Symmetric == "true"
    elseif self.NodeClass == NodeClass.Method then
      node.Attrs[AttributeId.Executable] = true
      node.Attrs[AttributeId.UserExecutable] = true
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
      return nil, newNamespacesParser(self.UANodeset);
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

local function createLoader(xml)
  local loader
  if type(xml) == "string" then
    loader = function()
      local result = xml
      xml = nil
      return result
    end
  elseif type (xml) == "function" then
    loader = xml
  elseif type(xml) == "table" or type(xml) == "userdata" and xml.read then
    loader = function()
      local str = xml:read(4096)
      return str
    end
  else
    error("invalid loader param")
  end
  return loader
end

local function nilTrace()
end

local function createXmlHandler(context, dbgTrace)
  return {
    START_ELEMENT = function (_, tagname, attribs)
      local tagNons = string.match(tagname, "([^:]+)$")
      if dbgTrace then
        dbgTrace("START_ELEMENT "..tagname.." "..tagNons)
      end
      return xmlHandler.START_ELEMENT(context, tagNons, attribs)
    end,
    END_ELEMENT = function(_, tagname)
      local tagNons = string.match(tagname, "([^:]+)$")
      if dbgTrace then
        dbgTrace("END_ELEMENT "..tagname.." "..tagNons)
      end
      return xmlHandler.END_ELEMENT(context, tagNons)
    end,
    TEXT = function(_, text)
      if dbgTrace then
        dbgTrace("TEXT "..text)
      end
      return xmlHandler.TEXT(context, text)
    end,
    EMPTY_ELEMENT = function(_, tagname, attribs)
      local tagNons = string.match(tagname, "([^:]+)$")
      if dbgTrace then
        dbgTrace("EMPTY_ELEMENT "..tagname.." "..tagNons)
      end
      return xmlHandler.EMPTY_ELEMENT(context, tagNons, attribs)
    end,
  }
end

local function parseXml(loader, parser)
  local err, detail
  while true do
    local chunk = loader()
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

  -- Error happend
  if err then
    error(err)
  end
  if type(detail) == "string" then
    error(detail)
  end
end

local function changeNs(nid, namespaces)
  local id = nodeId.fromString(nid)
  if id.ns == 0 then
    return nid
  end

  local ns = namespaces[id.ns]
  assert(ns, fmt("not found namespace for '%s'",nid));
  if id.ns == ns.Index and id.ns ~= ns.NewIndex then
    id.ns = ns.NewIndex
    nid = nodeId.toString(id)
  end

  return nid
end

local function parseNodeSet(xml, dbgTrace)
  local uaNodeSet = {
    Models = {},
    Namespaces = {},
    NsIndex = 0,
    Nodes = {},
    Aliases = {},
  }

  local context = {
    UANodeSet = uaNodeSet,
    len = 0,
    stack = {},
    parsers = {},
  }

  local handler = createXmlHandler(context, dbgTrace)
  local parser = compat.xparser.create(handler)
  local loader = createLoader(xml)
  parseXml(loader, parser)
  return uaNodeSet
end

local function checkModelDependencies(self, uaNodeSet)
  -- Check if required models are loaded
  for _, model in pairs(uaNodeSet.Models) do
    for _, requiredModel in pairs(model.RequiredModels) do
      -- Find model in currently loaded XML file
      local mod = uaNodeSet.Models[requiredModel.ModelUri]
      -- If not found, check if model is already loaded from other XML files
      if not mod then
        mod = self.Models[requiredModel.ModelUri]
      end

      if not mod then
        error("Model " .. requiredModel.ModelUri .. " not found")
      end
    end
  end
end

local function loadModel(self, xml, dbgTrace)
  if not dbgTrace then
    dbgTrace = nilTrace
  end

  local uaNodeSet = parseNodeSet(xml, dbgTrace)

  for _, model in pairs(uaNodeSet.Models) do
    if model.ModelUri == "http://opcfoundation.org/UA/" then
      local ns = {
        Index = 0,
        NewIndex = 0,
        NamespaceUri = model.ModelUri,
        Version = model.Version,
        PublicationDate = model.PublicationDate,
      }
      uaNodeSet.Namespaces[0] = ns
      uaNodeSet.Namespaces[ns.NamespaceUri] = ns
    end
  end

  checkModelDependencies(self, uaNodeSet)

  -- We need to check indexes of namespaces in the XML file
  -- and change them to match the indexes in the model.
  -- Already loaded namespaces can have different indexes than the ones in the XML file.
  for idx = 0,(uaNodeSet.NsIndex) do
    local newNs = uaNodeSet.Namespaces[idx]
    if newNs then
      local oldNs = self.Namespaces[newNs.NamespaceUri]
      if not oldNs then
        newNs.NewIndex = self:createNamespace(newNs.NamespaceUri)
      elseif oldNs.Index ~= newNs.Index then
        newNs.NewIndex = oldNs.Index
      end
    end
  end

  for alias, nid in pairs(uaNodeSet.Aliases) do
    local newNid = changeNs(nid, uaNodeSet.Namespaces)
    local oldId = self.Aliases[alias]
    if oldId and oldId ~= newNid then
      error("Alias ".. alias .. " for node ".. nid .. " already exists.")
    end
  end

  local newNodes = {}; -- required because keys should not change in original table
  -- Change namespace index in all nodes
  for oldId,node in pairs(uaNodeSet.Nodes) do
    local newId = changeNs(oldId, uaNodeSet.Namespaces)
    if newId ~= oldId then
      dbgTrace("NodeId " .. oldId .. " changed to " .. newId)
    else
      dbgTrace("NodeId " .. oldId .. " left as is ")
    end

    local newAttrs = {}
    -- change nodeIDs in attributes
    for attrId,attrValue in pairs(node.Attrs) do
      if type(attrValue) == "string" and nodeId.isValid(attrValue) then
        local attrNodeId = changeNs(attrValue, uaNodeSet.Namespaces)
        if attrNodeId ~= attrValue then
          attrValue = attrNodeId
          dbgTrace("attribute ".. attrId .. " changed " .. attrValue .. " to " .. attrNodeId)
        end
      end

      newAttrs[attrId] = attrValue
    end
    node.Attrs = newAttrs

    for idx,ref in pairs(node.Refs) do
      local targetNodeId = changeNs(ref.target, uaNodeSet.Namespaces)
      if targetNodeId ~= ref.target then
        dbgTrace("ref #" .. idx .. " target changed " .. ref.target .. " to " .. targetNodeId)
        ref.target = targetNodeId
      end
    end
    newNodes[newId] = node
  end
  uaNodeSet.Nodes = newNodes

  for alias, nid in pairs(uaNodeSet.Aliases) do
    local newNid = changeNs(nid, uaNodeSet.Namespaces)
    -- local oldId = self.Aliases[alias]
    dbgTrace("New alias ''" .. alias .. "'' for node " .. nid .. " changed to " .. newNid)
    self.Aliases[alias] = newNid
  end

  -- Connect nodes from XML file to nodes in the address space
  for nid, node in pairs(uaNodeSet.Nodes) do
    for _,ref in ipairs(node.Refs) do
      local targetNode = uaNodeSet.Nodes[ref.target]
      if targetNode then
        addReference(targetNode.Refs, {target=nid, type=ref.type, isForward=(ref.isForward == false)})
      else
        dbgTrace(fmt("Broken reference from node '%s' to '%s'", nid, ref.target))
      end
    end
  end

  -- Connect nodes from XML file to nodes in the address space
  for nid, node in pairs(uaNodeSet.Nodes) do
    local newNode = self.Nodes[nid]
    if not newNode then
      dbgTrace("Node " .. nid .. " already exists. Adding Refs")
      newNode = self.Nodes:newNode(nid, node.Attrs, node.Refs)
      self.Nodes:saveNode(newNode)
    end
  end

  -- Add namespaces to the address space
  for _,ns in pairs(uaNodeSet.Namespaces) do
    local existingNamespace = self.Namespaces[ns.NamespaceUri]
    if existingNamespace then
      if existingNamespace.Index ~= ns.NewIndex then
        error(fmt("Namespace '%s' from XML file has invalid index", ns.NamespaceUri))
      end
      goto continue
    end

    local namespace = {
      Index = ns.NewIndex,
      NamespaceUri = ns.NamespaceUri
    }

    local model = uaNodeSet.Models[ns.NamespaceUri]
    if model then
      namespace.ModelUri = model.ModelUri
      namespace.Version = model.Version
      namespace.PublicationDate = model.PublicationDate
    end

    self.Namespaces[namespace.Index] = namespace
    self.Namespaces[namespace.NamespaceUri] = namespace

    ::continue::
  end

  for _,model in pairs(uaNodeSet.Models) do
    self.Models[model.ModelUri] = model
  end
end

return loadModel
