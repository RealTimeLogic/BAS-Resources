local tins = table.insert
local tconcat = table.concat
local fmt = string.format

local types = require("opcua.types")
local nodeId = require("opcua.node_id")

local T = {}
T.__index = T

function T.makeString(arr)
  if type(arr) == "string" then return arr end

  local data = {}
  for _, val in pairs(arr) do
    local b = string.char(val)
    tins(data, b)
  end
  return tconcat(data)
end

function T.index(v, idx)
  if type(v) == "string" then
    return string.byte(v, idx)
  end
  return idx > #v and nil or v[idx]
end

function T.makeTable(str)
  local data = {}
  for i = 1,#str do
    local b = T.index(str, i)
    tins(data, b)
  end
  return data
end


local function s(b)
  local num = tonumber(b)
  if num < 0x20 or num > 0x7F then
    return ' '
  end
  return string.char(b)
end

function T.hexPrint(d, f)
  local eol = ''
  if f == nil then
    f = io.write
    eol = '\n'
  end

  local x = T.index

  local len = #d
  for i=1,len-(len%16),16 do
    local v1 = x(d,i)
    local v2 = x(d,i+1)
    local v3 = x(d,i+2)
    local v4 = x(d,i+3)
    local v5 = x(d,i+4)
    local v6 = x(d,i+5)
    local v7 = x(d,i+6)
    local v8 = x(d,i+7)
    local v9 = x(d,i+8)
    local v10 = x(d,i+9)
    local v11 = x(d,i+10)
    local v12 = x(d,i+11)
    local v13 = x(d,i+12)
    local v14 = x(d,i+13)
    local v15 = x(d,i+14)
    local v16 = x(d,i+15)

    local text= fmt(
        "%04X | 0x%02X, 0x%02X, 0x%02X, 0x%02X,  0x%02X, 0x%02X, 0x%02X, 0x%02X,  0x%02X, 0x%02X, 0x%02X, 0x%02X,  0x%02X, 0x%02X, 0x%02X, 0x%02X, |%s%s%s%s%s%s%s%s %s%s%s%s%s%s%s%s|%s",
        i-1,
        v1,v2,v3,v4,v5,v6,v7,v8,v9,v10,v11,v12,v13,v14,v15,v16,
        s(v1),s(v2),s(v3),s(v4),s(v5),s(v6),s(v7),s(v8),s(v9),s(v10),s(v11),s(v12),s(v13),s(v14),s(v15),s(v16),
        eol
      )
    f(text)
  end

  -- print symbols for corresponding bytes
  if (len%16) ~= 0 then
    local tail = {}
    local off = len - (len%16)
    tins(tail, fmt("%04X | ", off))
    for i=1,16 do
      if i == 5 or i == 9 or i == 13 then
        tins(tail, " ")
      end

      if off+i <= len then
        local v = x(d,off+i)
        tins(tail, fmt("0x%02X, ", v))
      else
        tins(tail, "      ")
      end
    end

    tins(tail, "|")

    for i=1,17 do
      if off+i <= len then
        local v = x(d,off+i)
        tins(tail, s(v))
      else
        tins(tail, " ")
      end
    end

    tins(tail, "|")
    tins(tail, eol)
    f(table.concat(tail, ""))
  end
end

function T.browseNameValid(browseName)
  return type(browseName) == 'table' and
    (browseName.ns == nil or type(browseName.ns) == 'number') and
    type(browseName.Name) == 'string'
end

function T.nodeClassValid(cls)
  return type(cls) == 'number' and
  (cls == 1 or cls == 2 or cls == 4 or cls == 8 or cls == 16 or cls == 32)
end

function T.booleanValid(v)
  return v == 1 or v == 0 or v == true or v == false
end

function T.numberValid(v, mn, mx)
  return type(v) == 'number' and v >= mn and v <= mx
end

function T.sbyteValid(v)
  return T.numberValid(v, -128, 127)
end

function T.byteValid(v)
  return T.numberValid(v, 0, 255)
end

function T.int16Valid(v)
 return T.numberValid(v, -32768, 32767)
end

function T.uint16Valid(v)
  return T.numberValid(v, 0, 65535)
end

function T.int32Valid(v)
  return T.numberValid(v, -2147483648, 2147483647)
end

function T.uint32Valid(v)
  return T.numberValid(v, 0, 4294967295)
end

function T.int64Valid(v)
  return T.numberValid(v, -9223372036854775808, 9223372036854775807)
end

function T.uint64Valid(v)
  return T.numberValid(v, 0, math.maxinteger)
end

function T.floatValid(v)
  return type(v) == 'number'
end

function T.doubleValid(v)
  return type(v) == 'number'
end

function T.guidValid(v)
  return type(v) == "string" and string.match(v, "^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$") ~= nil
end

function T.localizedTextValid(v)
  return type(v) == 'table' and
         (v.Locale == nil or type(v.Locale) == 'string') and
         type(v.Text) == 'string'
end

function T.qualifiedNameValid(v)
  return type(v) == 'table' and (v.ns == nil or T.uint16Valid(v.ns)) and type(v.Name) == 'string'
end

function T.byteStringValid(v)
  if type(v) == 'table' then
    if #v == 0 then
      return true;
    end
    for _,b in ipairs(v) do
      if not T.byteValid(b) then
        return false
      end
    end
    return true
  else
    return type(v) == 'string'
  end
end

function T.stringValid(v)
  return type(v) == 'string'
end

T.xmlElementValid = T.stringValid

function T.nodeIdValid(v)
  return nodeId.isValid(v)
end

function T.diagnosticInfoValid(v)
  if type(v) ~= 'table' then
    return false
  end

  if v.SymbolicId ~= nil and not T.int32Valid(v.SymbolicId) then
    return false
  end
  if v.NsUri ~= nil and not T.int32Valid(v.NsUri) then
    return false
  end
  if v.Locale ~= nil and not T.int32Valid(v.Locale) then
    return false
  end
  if v.LocalizedText ~= nil and not T.int32Valid(v.LocalizedText) then
    return false
  end
  if v.AdditionalInfo ~= nil and not T.stringValid(v.AdditionalInfo) then
    return false
  end
  if v.InnerStatusCode ~= nil and not T.uint32Valid(v.InnerStatusCode) then
    return false
  end
  if v.InnerDiagnosticInfo ~= nil and not T.diagnosticInfoValid(v.InnerDiagnosticInfo) then
    return false
  end
  return true
end

local function variantDataValid(data, f, sz)
  if type(data) == "table" and #data > 0 then
    if sz ~= nil and #data ~= sz then
      return false
    end
    for _,el in ipairs(data) do
      if not f(el) then
        return false
      end
    end
    return true
  else
    if sz ~= nil then
      return false
    end
    return f(data)
  end
end

function T.variantValid(val)
  if type(val) ~= 'table' or val == {} then
    return false
  end

  local sz
  if val.IsArray then
    if type(val.Value) ~= "table" or val.Value[1] == nil then
      return false
    end
    sz = #val.Value
  end

  if val.ArrayDimensions then
    if type(val.ArrayDimensions) ~= "table" or val.ArrayDimensions[1] == nil then
      return false
    end

    local lsz = 1
    for _,el in ipairs(val.ArrayDimensions) do
      lsz = lsz * el
    end
    if sz == nil then
      sz = lsz
    elseif lsz ~= sz then
      return false
    end
  end

  if val.Type == types.VariantType.Boolean then
    return variantDataValid(val.Value, T.booleanValid, sz)
  elseif val.Type == types.VariantType.SByte then
    return variantDataValid(val.Value, T.sbyteValid, sz)
  elseif val.Type == types.VariantType.Byte then
    return variantDataValid(val.Value, T.byteValid, sz)
  elseif val.Type == types.VariantType.Int16 then
    return variantDataValid(val.Value, T.int16Valid, sz)
  elseif val.Type == types.VariantType.UInt16 then
    return variantDataValid(val.Value, T.uint16Valid, sz)
  elseif val.Type == types.VariantType.Int32 then
    return variantDataValid(val.Value, T.int32Valid, sz)
  elseif val.Type == types.VariantType.UInt32 then
    return variantDataValid(val.Value, T.uint32Valid, sz)
  elseif val.Type == types.VariantType.Int64 then
    return variantDataValid(val.Value, T.int64Valid, sz)
  elseif val.Type == types.VariantType.UInt64 then
    return variantDataValid(val.Value, T.uint64Valid, sz)
  elseif val.Type == types.VariantType.Float then
    return variantDataValid(val.Value, T.floatValid, sz)
  elseif val.Type == types.VariantType.Double then
    return variantDataValid(val.Value, T.doubleValid, sz)
  elseif val.Type == types.VariantType.String then
    return variantDataValid(val.Value, T.stringValid, sz)
  elseif val.Type == types.VariantType.DateTime then
    return variantDataValid(val.Value, T.doubleValid, sz)
  elseif val.Type == types.VariantType.Guid then
    return variantDataValid(val.Value, T.guidValid, sz)
  elseif val.Type == types.VariantType.ByteString then
    if type(val.Value) == 'table' then
      if #val.Value == 0 then
        return true
      end
      if type(val.Value[1]) == 'table' or type(val.Value[1]) == 'string' then
        if sz ~= nil and #val.Value ~= sz then
          return false
        end
        for _,b in ipairs(val.Value) do
          if T.byteStringValid(b) == false then
            return false
          end
        end
        return true
      else
        return T.byteStringValid(val.Value)
      end
    end
    return type(val.Value) == 'string'
  elseif val.Type == types.VariantType.XmlElement then
    return variantDataValid(val.Value, T.xmlElementValid, sz)
  elseif val.Type == types.VariantType.NodeId then
    return variantDataValid(val.Value, T.nodeIdValid, sz)
  elseif val.Type == types.VariantType.ExpandedNodeId then
    return variantDataValid(val.Value, T.nodeIdValid, sz)
  elseif val.Type == types.VariantType.StatusCode then
    return variantDataValid(val.Value, T.uint32Valid, sz)
  elseif val.Type == types.VariantType.QualifiedName then
    return variantDataValid(val.Value, T.qualifiedNameValid, sz)
  elseif val.Type == types.VariantType.LocalizedText then
    return variantDataValid(val.Value, T.localizedTextValid, sz)
  elseif val.Type == types.VariantType.ExtensionObject then
    return variantDataValid(val.Value, T.extensionObjectValid, sz)
  elseif val.Type == types.VariantType.DataValue then
    return variantDataValid(val.Value, T.dataValueValid, sz)
  elseif val.Type == types.VariantType.Variant then
    return variantDataValid(val.Value, T.variantValid, sz)
  elseif val.Type == types.VariantType.DiagnosticInfo then
    return variantDataValid(val.Value, T.diagnosticInfoValid, sz)
  end

  return false
end


function T.getVariantTypeId(val)
  local t = val.Type
  if t == types.VariantType.Boolean then
    return "i=1"
  elseif t == types.VariantType.SByte then
    return "i=2"
  elseif t == types.VariantType.Byte then
    return "i=3"
  elseif t == types.VariantType.Int16 then
    return "i=4"
  elseif t == types.VariantType.UInt16 then
    return "i=5"
  elseif t == types.VariantType.Int32 then
    return "i=6"
  elseif t == types.VariantType.UInt32 then
    return "i=7"
  elseif t == types.VariantType.Int64 then
    return "i=8"
  elseif t == types.VariantType.UInt64 then
    return "i=9"
  elseif t == types.VariantType.Float then
    return "i=10"
  elseif t == types.VariantType.Double then
    return "i=11"
  elseif t == types.VariantType.String then
    return "i=12"
  elseif t == types.VariantType.DateTime then
    return "i=13"
  elseif t == types.VariantType.Guid then
    return "i=14"
  elseif t == types.VariantType.ByteString then
    return "i=15"
  elseif t == types.VariantType.XmlElement then
    return "i=16"
  elseif t == types.VariantType.NodeId then
    return "i=17"
  elseif t == types.VariantType.ExpandedNodeId then
    return "i=18"
  elseif t == types.VariantType.StatusCode then
    return "i=19"
  elseif t == types.VariantType.QualifiedName then
    return "i=20"
  elseif t == types.VariantType.LocalizedText then
    return "i=21"
  elseif t == types.VariantType.ExtensionObject then
    return "i=22"
  elseif t == types.VariantType.DataValue then
    return "i=23"
  elseif t == types.VariantType.Variant then
    return "i=24"
  elseif t == types.VariantType.DiagnosticInfo then
    return "i=25"
  end

  error("unknown variant type".. tostring(t))
end

function T.dataValueValid(v)
  if type(v) ~= 'table' then
    return false
  end
  if not T.variantValid(v) then
    return false
  end
  if v.StatusCode ~= nil and not T.uint32Valid(v.StatusCode) then
    return false
  end
  if v.SourceTimestamp ~= nil and not T.doubleValid(v.SourceTimestamp) then
    return false
  end
  if v.ServerTimestamp ~= nil and not T.doubleValid(v.ServerTimestamp) then
    return false
  end
  if v.SourcePicoseconds ~= nil and not T.uint16Valid(v.SourcePicoseconds) then
    return false
  end
  if v.ServerPicoseconds ~= nil and not T.uint16Valid(v.ServerPicoseconds) then
    return false
  end

  return true
end


function T.extensionObjectValid(v)
  return type(v) == 'table' and T.nodeIdValid(v.TypeId) and (v.Body == nil or T.byteStringValid(v.Body))
end

function T.valueRankValid(v)
  return T.int32Valid(v) and v >=-3 and v <= 2
end


local function scalarValid(val, arrayDimensions)
  return val == nil or (arrayDimensions == nil or arrayDimensions[1] == -1 or arrayDimensions[1] == nil) and (type(val) ~= 'table' or #val == 0 or T.byteStringValid(val))
end

local function oneDimensionValid(val, arrayDimensions)
  if type(arrayDimensions) ~= 'table' or #arrayDimensions ~= 1 then
    return false
  end
  if type(val) ~= 'table' then
    return false
  end
  return #val == arrayDimensions[1]
end

function T.arrayDimensionsValid(value, arrayDimensions, valueRank)
  if value.ArrayDimensions and not arrayDimensions then
    return false
  end
  -- if not value.ArrayDimensions and arrayDimensions then
  --   return false
  -- end
  if value.ArrayDimensions and arrayDimensions then
    if #value.ArrayDimensions ~= #arrayDimensions then
      return false
    end
    for i=1,#value.ArrayDimensions do
      if value.ArrayDimensions[i] ~= arrayDimensions[i] then
        return false
      end
    end
  end

  -- Search for the value field: it can be any except ArraySimensions
  local val= value.Value
  if valueRank == types.ValueRank.Scalar then
    return scalarValid(val, arrayDimensions, valueRank)
  elseif valueRank == types.ValueRank.OneDimension then
    return oneDimensionValid(val, arrayDimensions, valueRank)
  elseif valueRank == types.ValueRank.ScalarOrOneDimension then
    return scalarValid(val, arrayDimensions, valueRank) or oneDimensionValid(val, arrayDimensions, valueRank)
  end

  return false
end


local function comp(a,b)
  return tostring(a) < tostring(b)
end

function T.printTable(name, v, f, idents)
  if not idents then idents = '' end
  if not f then f = print end

  if type(v) == 'table' then
    if name and name ~= "" then
      f(idents..name.." = {")
    else
      f(idents.."{")
    end
    local keys = {}
    for k,_ in pairs(v) do
      table.insert(keys, k)
    end
    table.sort(keys, comp)
    for _,k in ipairs(keys) do
      if type(k) == 'string' then
        T.printTable(k, v[k], f, idents.."  ")
      else
        T.printTable("", v[k], f, idents.."  ")
      end
    end
    local line = idents.."}"
    if idents ~= '' then
      line = line..","
    end
    f(line)
  else
    local line
    if name and name ~= "" then
      line = idents..name.." = "
    else
      line = idents
    end

    if type(v) == 'string' then
      line = line..'"'..v..'"'
    else
      line = line..tostring(v)
    end
    f(line..",")
  end
end

function T.copy(src)
  local result
  if type(src) == 'table' then
    result = {}
    for k,val in pairs(src) do
      result[k] = T.copy(val)
    end
    return result
  else
    result = src
  end

  return result
end


function T.createAnonymousToken(policyId)
  return {
    TypeId = "i=319",
    Body = {
      PolicyId = policyId
    }
  }
end

function T.createUsernameToken(policyId, username, password, encryptionAlgorithm)
  return {
    TypeId = "i=322",
    Body = {
      PolicyId = policyId,
      UserName = username,
      Password = password,
      EncryptionAlgorithm = encryptionAlgorithm
    }
  }
end

function T.createX509Token(policyId, cert)
  return {
    TypeId = "i=325",
    Body = {
      PolicyId = policyId,
      CertificateData = cert
    }
  }
end

function T.createIssuedToken(policyId, token, encryptionAlgorithm)
  return {
    TypeId = "i=938",
    Body = {
      PolicyId = policyId,
      TokenData = token,
      EncryptionAlgorithm = encryptionAlgorithm
    }
  }
end


return T
