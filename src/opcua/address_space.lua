local ns0 = require("opcua_ns0")
local address_space = {}
function address_space:getNode(nodeId)
  assert(self ~= nil)
  assert(type(nodeId) == 'string')

  -- get node from ns0
  local node1 = self.n[nodeId]
  local node = ns0[nodeId]
  if node == nil then
    return node1
  end

  if node1 == nil then
    return node
  end

  for key,val in pairs(node1.attrs) do
    node.attrs[key] = val
  end

  for key,val in pairs(node1.refs) do
    node.refs[key] = val
  end

  return node
end

function address_space:saveNode(node)
  assert(self ~= nil)
  local id = node.attrs[1]
  self.n[id] = node
end

local function create()
  local space ={
    n = {}
  }
  setmetatable(space, {__index = address_space})
  return space
end

return create
