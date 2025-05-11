local fmt = string.format

local function checkRefs(self, callback)
  local unreferencedNodes = {}
  for nodeId in pairs(self.Nodes) do
    unreferencedNodes[nodeId] = true
  end

  for nodeId, node in pairs(self.Nodes) do
    -- Check if node has nodeID
    if node.attrs[1] == nil then
      callback(fmt("Node '%s' is absent", nodeId))
    end

    for i, ref in ipairs(node.refs) do
      if ref.target == nil then
        callback(fmt("Node '%s' Reference #%s target is nil", nodeId, i))
      else
        local tagetNode = self.Nodes[ref.target]
        if tagetNode == nil then
          callback(fmt("Node '%s' Reference %s target node '%s' absent", nodeId, i, ref.target))
        else
          unreferencedNodes[ref.target] = nil
        end
      end
    end
  end

  for nodeId, _ in pairs(unreferencedNodes) do
    callback(fmt("Node '%s' is unreferenced", nodeId))
  end
end

local function validate(self, callback)
  local err = {}
  callback = callback or function(e) table.insert(err, e) end
  checkRefs(self, callback)
  return err
end

return validate
