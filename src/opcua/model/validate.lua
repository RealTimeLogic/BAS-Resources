local trace = require("opcua.trace")

local fmt = string.format
local traceI = trace.inf

local function checkRefs(self, callback)
  local unreferencedNodes = {}
  for nodeId in pairs(self.Nodes) do
    unreferencedNodes[nodeId] = true
  end

  for nodeId, node in pairs(self.Nodes) do
    -- Check if node has nodeID
    if node.Attrs[1] == nil then
      callback(fmt("Node '%s' is absent", nodeId))
    end

    for i, ref in ipairs(node.Refs) do
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

local function checkEncodingNodes()
-- local function checkEncodingNodes(self, _)
  -- for nodeId, node in pairs(self.Nodes) do
  --   if node.Attrs.NodeClass == ua.NodeClass.DataType then
  --     if not node.binaryId then
  --       callback(fmt("DataType node '%s' has no binary encoding node", nodeId))
  --     end
  --     if not node.jsonId then
  --       callback(fmt("DataType node '%s' has no json encoding node", nodeId))
  --     end
  --     if not node.baseId then
  --       callback(fmt("DataType node '%s' has no base OPCUA type node", nodeId))
  --     end
  --     if not node.dataTypeId then
  --       callback(fmt("DataType node '%s' has no data type node", nodeId))
  --     end
  --   end
  -- end
end

local function validate(self, callback)
  local infOn = self.config.logging.services.infOn
  if infOn then traceI("Validating model") end

  local err = {}
  callback = callback or function(e) table.insert(err, e) end
  checkRefs(self, callback)
  checkEncodingNodes(self, callback)
  return err
end

return validate
