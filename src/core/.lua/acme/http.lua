-- Shared ACME transport defaults. Set trust before starting client runtimes.
local M,shark={}
function M.setCertStore(store)
   shark=store and ba.create.sharkssl(store) or nil
end
function M.options(options)
   local op={}
   for k,v in pairs(options or {}) do op[k]=v end
   if op.shark==nil then op.shark=shark or ba.sharkclient() end
   return op
end
function M.create(options)
   return require"httpc".create(M.options(options))
end
return M
