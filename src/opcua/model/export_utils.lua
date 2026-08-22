local function selectedNamespaces(model, namespaceURIs)
  assert(type(model) == "table", "model must be a table")
  assert(type(model.Namespaces) == "table",
    "model.Namespaces must be a table")

  local result = {}
  if namespaceURIs == nil then
    local indexes = {}
    for index, namespace in pairs(model.Namespaces) do
      if type(index) == "number" and namespace then
        indexes[#indexes + 1] = index
      end
    end
    table.sort(indexes)
    for _, index in ipairs(indexes) do
      result[#result + 1] = model.Namespaces[index]
    end
    return result
  end

  assert(type(namespaceURIs) == "table",
    "namespaceURIs must be a list")
  for _, namespaceURI in ipairs(namespaceURIs) do
    assert(type(namespaceURI) == "string",
      "namespace URI must be a string")
    local namespace = model.Namespaces[namespaceURI]
    if namespace == nil then
      error("unknown namespace URI: " .. namespaceURI)
    end
    result[#result + 1] = namespace
  end
  return result
end

local function namespaceIndexes(model, namespaceURIs)
  local indexes = {}
  for _, namespace in ipairs(
    selectedNamespaces(model, namespaceURIs))
  do
    indexes[namespace.Index] = true
  end
  return indexes
end

return {
  selectedNamespaces = selectedNamespaces,
  namespaceIndexes = namespaceIndexes,
}
