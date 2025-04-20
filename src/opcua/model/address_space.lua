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

-- iterator over nodes
function address_space:__pairs()
  assert(self ~= nil)
  local n,nn = pairs(self.n)
  local n0,nn0 = pairs(ns0)
  local k = nil
  return function()
    local v
    if n then
      k,v = n(nn,k)
      if k then
        return k,v
      end
      n = nil
      nn = nil
    end

    k,v = n0(nn0,k)
    return k,v
  end
end

function address_space:saveNode(node)
  assert(self ~= nil)
  local id = node.attrs[1]
  self.n[id] = node
end

local function create()
  local space ={
    n = {},
    saveNode = address_space.saveNode
  }
  setmetatable(space, {
    __newindex = function(self, id, node)
      assert(self ~= nil)
      self.n[id] = node
    end,
    __index = address_space.getNode,
    __pairs = address_space.__pairs,
  })
  return space
end

return create
