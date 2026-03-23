-- TODO
-- * Load ExtensionObject as just recursive value, check exporting
-- * check node ns=1;i=6525 - it loaded wrong
-- * change ns for QualifiedNames

local compat = require("opcua.compat")

local const = require("opcua.const")
local NodeId = require("opcua.node_id")
local NodeClass = const.NodeClass
local VariantType = const.VariantType

local fmt = string.format
local tins = table.insert

local function exportNamespaceUris(self, output, context)
  output('  <NamespaceUris>\n')
  for index = 0,#self.Namespaces do
    local nsUri = self.Namespaces[index].NamespaceUri
    if context.namespaces[nsUri] then
      output('    <NamespaceUri>'..nsUri..'</NamespaceUri>\n')
    end
  end
  output('  </NamespaceUris>\n')
end

local function formatModelString(tagName,model, closed)
  local str = fmt('<%s ModelUri="%s"', tagName, model.ModelUri)
  if model.Version then
    str = str .. fmt(' Version="%s"', model.Version)
  end
  if model.PublicationDate then
    str = str .. fmt(' PublicationDate="%s"', model.PublicationDate)
  end
  if closed then
    str = str .. '/'
  end
  str = str .. '>'
  return str
end

local function changeNs(nid, context)
  local id = NodeId.fromString(nid)
  local newIndex = context.nsIndexMap[id.ns]
  if id.ns == newIndex then
    return nid
  end

  id.ns = newIndex
  return NodeId.toString(id)
end

local function exportAliases(self, output, context)
  output('  <Aliases>\n')
  for alias, nid in pairs(self.Aliases) do
    local id = changeNs(nid, context)
    if id then
      output(fmt('    <Alias Alias="%s">%s</Alias>\n', alias, id))
    end
  end
  output('  </Aliases>\n')
end

local function getSortedModelUries(models)
  local modelUries = {}
  for modelUri in pairs(models) do
    table.insert(modelUries, modelUri)
  end
  table.sort(modelUries)
  return modelUries
end

local function xmlText(text)
  if text == nil then
    return ""
  end
  text = string.gsub(text, "&", "&amp;")
  text = string.gsub(text, "<", "&lt;")
  text = string.gsub(text, ">", "&gt;")
  text = string.gsub(text, '"', "&quot;")
  text = string.gsub(text, "'", "&apos;")
  return text
end

local function browseName(name)
  if name.ns ~= nil  and name.ns ~= 0 then
    return xmlText(name.ns .. ":" .. name.Name)
  end
  return xmlText(name.Name)
end

local function exportModels(self, output, context)
  output('  <Models>\n')

  for _, modelUri in ipairs(getSortedModelUries(self.Models)) do
    if not context.namespaces[modelUri] then
      goto continue
    end
    local model = self.Models[modelUri]
    output("    ")
    output(formatModelString("Model", model, false))
    output("\n")

    if model.RequiredModels then
      for _, requiredUri in ipairs(getSortedModelUries(model.RequiredModels)) do
        if requiredUri == nil then
          error("Model " .. modelUri .. " requires itself")
        end
        output("      ")
        output(formatModelString("RequiredModel", model.RequiredModels[requiredUri], true))
        output("\n")
      end
    end
    output("    </Model>\n")

    ::continue::
  end
  output('  </Models>\n')
end

local function commonTags(_, output, context, node)
  local attrs = node.Attrs
  if attrs.DisplayName then
    output(fmt('    <DisplayName>%s</DisplayName>\n', xmlText(attrs.DisplayName.Text)))
  end
  if attrs.Description then
    output(fmt('    <Description>%s</Description>\n', xmlText(attrs.Description.Text)))
  end

  if node.Refs and node.Refs[1] then
    output('    <References>\n')

    local contextRefs = context.refs[node.Attrs.NodeId]
    if not contextRefs then
      contextRefs = {}
      context.refs[node.Attrs.NodeId] = contextRefs
    end

    for _, nodeRef in pairs(node.Refs) do
      -- Skip exporting reference for target node if it's already exported
      for _, ref in pairs(context.refs[nodeRef.target] or {}) do
        if ref.type == ref.type and ref.target == node.Attrs.NodeId then
          goto continue
        end
      end

      output(fmt('      <Reference ReferenceType="%s"', nodeRef.type))
      if not nodeRef.isForward then
        output(' IsForward="false"')
      end
      output('>')
      output(changeNs(nodeRef.target, context))
      output('</Reference>\n')

      tins(contextRefs, nodeRef)

      ::continue::
    end
    output('    </References>\n')
  end
end

local typeNames = {}
for k, v in pairs(VariantType) do
  typeNames[v] = k
end

local function recursiveValue(value)
  if type(value) ~= "table" then
    return value
  end
  local str = ""
  for k, v in pairs(value) do
    str = str .. fmt('      <%s>%s</%s>\n', k, recursiveValue(v), k)
  end
  return str
end

local function exportVariantValue(_, output, value, type)
  local typeName = typeNames[type]
  if not typeName then
    error("unsupported value type: " .. type)
  end

  if not value then
    value = ""
  elseif type == VariantType.LocalizedText then
    local lv = value
    value = ""
    if lv.Text then
      value = value .. "<Text>"..lv.Text.."</Text>"
    end
    if lv.Locale then
      value = value .. "<Locale>"..lv.Locale.."</Locale>"
    end
  elseif type == VariantType.QualifiedName then
    local qn = value
    value = ""
    if qn.Name then
      value = value .. "<Name>"..qn.Name.."</Name>"
    end
    if qn.NamespaceIndex then
      value = value .. "<NamespaceIndex>"..qn.NamespaceIndex.."</NamespaceIndex>"
    end
  elseif type == VariantType.NodeId or type == VariantType.ExpandedNodeId then
    value = "<Identifier>"..value.."</Identifier>"
  elseif type == VariantType.ByteString then
    value = compat.b64encode(value)
  elseif type == VariantType.ExtensionObject then
    value = value.Body and recursiveValue(value) or ""
  end

  output(fmt('      <%s>%s</%s>\n', typeName, value, typeName))
end

local function exportValue(self, output, value)
  if not value.IsArray then
    exportVariantValue(self, output, value.Value, value.Type)
    return
  end

  local typeName = typeNames[value.Type]
  output(fmt('      <ListOf%s>\n', typeName))
  for _, v in ipairs(value.Value) do
    output("  ")
    exportVariantValue(self, output, v, value.Type)
  end
  output(fmt('      </ListOf%s>\n', typeName))
end

local function exportVariable(self, output, context, nodeId, node)
  local attrs = node.Attrs
  output(fmt('  <UAVariable NodeId="%s" BrowseName="%s"', changeNs(nodeId, context), xmlText(browseName(attrs.BrowseName))))

  if attrs.DataType then
    output(fmt(' DataType="%s"', changeNs(attrs.DataType, context)))
  end
  if attrs.Rank and attrs.Rank ~= -1 then
    output(fmt(' ValueRank="%s"', attrs.Rank))
  end
  if attrs.ArrayDimensions then
    output(fmt(' ArrayDimensions="%s"', table.concat(attrs.ArrayDimensions, ",")))
  end
  if attrs.AccessLevel then
    output(fmt(' AccessLevel="%s"', attrs.AccessLevel))
  end
  if attrs.MinimumSamplingInterval then
    output(fmt(' MinimumSamplingInterval="%s"', attrs.MinimumSamplingInterval))
  end
  if attrs.Historizing then
    output(' Historizing="true"')
  end
  output('>\n')

  commonTags(self, output, context, node)


  if attrs.Value then
    output('    <Value>\n')
    exportValue(self, output, attrs.Value)
    output('    </Value>\n')
  end

  output("  </UAVariable>\n")
end

local function exportObject(self, output, context, nodeId, node)
  local attrs = node.Attrs
  local attrStr = fmt('NodeId="%s" BrowseName="%s"', changeNs(nodeId, context), xmlText(browseName(attrs.BrowseName)))

  if attrs.EventNotifier then
    attrStr = attrStr .. fmt(' EventNotifier="%s"', attrs.EventNotifier)
  end

  output(fmt('  <UAObject %s>\n', attrStr))
  commonTags(self, output, context, node)

  output("  </UAObject>\n")
end

local function exportMethod(self, output, context, nodeId, node)
  local attrs = node.Attrs
  local attrStr = fmt('NodeId="%s" BrowseName="%s"', changeNs(nodeId, context), xmlText(browseName(attrs.BrowseName)))

  output(fmt('  <UAMethod %s>\n', attrStr))
  commonTags(self, output, context, node)
  output("  </UAMethod>\n")
end

local function exportObjectType(self, output, context, nodeId, node)
  local attrs = node.Attrs
  local attrStr = fmt('NodeId="%s" BrowseName="%s"', changeNs(nodeId, context), xmlText(browseName(attrs.BrowseName)))
  if attrs.IsAbstract then
    attrStr = attrStr .. ' IsAbstract="true"'
  end

  output(fmt('  <UAObjectType %s>\n', attrStr))
  commonTags(self, output, context, node)
  output("  </UAObjectType>\n")
end

local function exportVariableType(self, output, context, nodeId, node)
  local attrs = node.Attrs
  local attrStr = fmt('NodeId="%s" BrowseName="%s"', changeNs(nodeId, context), xmlText(browseName(attrs.BrowseName)))

  if attrs.DataType then
    attrStr = attrStr .. fmt(' DataType="%s"', changeNs(attrs.DataType, context))
  end
  if attrs.Rank and attrs.Rank ~= -1 then
    attrStr = attrStr .. fmt(' ValueRank="%s"', attrs.Rank)
  end
  if attrs.ArrayDimensions then
    attrStr = attrStr .. fmt(' ArrayDimensions="%s"', table.concat(attrs.ArrayDimensions, ","))
  end
  if attrs.IsAbstract then
    attrStr = attrStr .. ' IsAbstract="true"'
  end

  output(fmt('  <UAVariableType %s>\n', attrStr))
  commonTags(self, output, context, node)


  if attrs.Value then
    output('    <Value>\n')
    exportValue(self, output, attrs.Value)
    output('    </Value>\n')
  end

  output("  </UAVariableType>\n")
end

local function exportReferenceType(self, output, context, nodeId, node)
  local attrs = node.Attrs
  local attrStr = fmt('NodeId="%s" BrowseName="%s"', changeNs(nodeId, context), xmlText(browseName(attrs.BrowseName)))

  if attrs.IsAbstract then
    attrStr = attrStr .. ' IsAbstract="true"'
  end
  if attrs.Symmetric then
    attrStr = attrStr .. ' Symmetric="true"'
  end

  output(fmt('  <UAReferenceType %s>\n', attrStr))
  commonTags(self, output, context, node)

  if attrs.InverseName then
    output(fmt('    <InverseName>%s</InverseName>\n', xmlText(attrs.InverseName.Text)))
  end

  output("  </UAReferenceType>\n")
end

local function exportDataType(self, output, context, nodeId, node)
  local attrs = node.Attrs
  local attrStr = fmt('NodeId="%s" BrowseName="%s"', changeNs(nodeId, context), xmlText(browseName(attrs.BrowseName)))

  if attrs.IsAbstract then
    attrStr = attrStr .. ' IsAbstract="true"'
  end

  output(fmt('  <UADataType %s>\n', attrStr))
  commonTags(self, output, context, node)

  local definition = attrs.DataTypeDefinition
  if definition then
    output('    <Definition>\n')
    for _, field in ipairs(definition) do
      attrStr = fmt('Name="%s" DataType="%s"', field.Name, changeNs(field.DataType, context))
      if field.ValueRank then
        attrStr = attrStr .. fmt(' ValueRank="%s"', field.ValueRank)
      end
      if field.ArrayDimensions then
        attrStr = attrStr .. fmt(' ArrayDimensions="%s"', table.concat(field.ArrayDimensions, ","))
      end
      if field.Value then
        attrStr = attrStr .. fmt(' Value="%s"', field.Value)
      end
      if field.IsOptional then
        attrStr = attrStr .. ' IsOptional="true"'
      end
      if field.MaxStringLength then
        attrStr = attrStr .. fmt(' MaxStringLength="%s"', field.MaxStringLength)
      end
      if field.DisplayName then
        attrStr = attrStr .. fmt(' DisplayName="%s"', xmlText(field.DisplayName.Text))
      end
      output(fmt('      <Field %s', attrStr))
      if field.Description then
        output('>\n')
        output(fmt('        <Description>%s</Description>\n', xmlText(field.Description.Text)))
        output(fmt('      </Field>\n'))
      else
        output('/>\n')
      end
    end
    output('    </Definition>\n')
  end

  output("  </UADataType>\n")
end

local function exportView(self, output, context, nodeId, node)
  local attrs = node.Attrs
  local attrStr = fmt('NodeId="%s" BrowseName="%s"', changeNs(nodeId, context), xmlText(browseName(attrs.BrowseName)))

  if attrs.ContainsNoLoops then
    attrStr = attrStr .. ' ContainsNoLoops="true"'
  end
  if attrs.EventNotifier then
    attrStr = attrStr .. fmt(' EventNotifier="%s"', attrs.EventNotifier)
  end

  output(fmt('  <UAView %s>\n', attrStr))
  commonTags(self, output, context, node)
  output("  </UAView>\n")
end

local cls2func = {
  [NodeClass.Variable] = exportVariable,
  [NodeClass.Object] = exportObject,
  [NodeClass.Method] = exportMethod,
  [NodeClass.ObjectType] = exportObjectType,
  [NodeClass.VariableType] = exportVariableType,
  [NodeClass.ReferenceType] = exportReferenceType,
  [NodeClass.DataType] = exportDataType,
  [NodeClass.View] = exportView
}

local function exportNode(self, output, context, nodeId, node)
  local cls = node.Attrs.NodeClass
  local func = cls2func[cls]
  if not func then
    error("unsupported node class: " .. cls)
  end
  func(self, output, context, nodeId, node)
end

local function exportXml(self, output, namespaceUris)
  local context = {
    refs = {},
    namespaces = {},
    nsIndexMap = {}, -- map for changing namespace index for nodes
  }
  output('<?xml version="1.0" encoding="utf-8" ?>\n')
  output('<UANodeSet xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:uax="http://opcfoundation.org/UA/2008/02/Types.xsd" LastModified="2022-02-24T00:00:00Z" xmlns="http://opcfoundation.org/UA/2011/03/UANodeSet.xsd">\n')

  if namespaceUris then
    for i, namespace in ipairs(namespaceUris) do
      local ns = {
        NamespaceUri = namespace,
        Index = i,
      }
      context.namespaces[namespace] = ns
      context.namespaces[i] = ns
    end
  else
    context.namespaces = self.Namespaces
  end

  for _, exportNs in pairs(context.namespaces) do
    local ns= self.Namespaces[exportNs.NamespaceUri]
    if ns then
      context.nsIndexMap[ns.Index] = exportNs.Index
    end
  end

  exportNamespaceUris(self, output, context)
  exportModels(self, output, context)
  exportAliases(self, output, context)

  for nodeId,node in pairs(self.Nodes) do
    local nid = NodeId.fromString(nodeId)
    if context.nsIndexMap[nid.ns] then
      exportNode(self, output, context, nodeId, node)
    end
  end

  output('</UANodeSet>\n')
end

return exportXml
