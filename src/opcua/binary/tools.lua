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
  if type(v) == "string" then
    local m = string.match(v, "^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$")
    return m == v
  end

  return
  type(v) == 'table' and
  T.uint32Valid(v.Data1) and
  T.uint16Valid(v.Data2) and
  T.uint16Valid(v.Data3) and
  T.byteValid(v.Data4) and
  T.byteValid(v.Data5) and
  T.byteValid(v.Data6) and
  T.byteValid(v.Data7) and
  T.byteValid(v.Data8) and
  T.byteValid(v.Data9) and
  T.byteValid(v.Data10) and
  T.byteValid(v.Data11)
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

function T.xmlElementValid(v)
  if type(v) ~= 'table' then
    return false
  end

  if v.Value == nil then
    return false
  end

  return type(v.Value) == 'string'
end

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
  if val.ArrayDimensions then
    if type(val.ArrayDimensions) ~= "table" or val.ArrayDimensions[1] == nil then
      return false
    else
      sz = 1
      for _,el in ipairs(val.ArrayDimensions) do
        sz = sz * el
      end
    end
    if sz == 0 then
      return false
    end
  end

  if val.Boolean ~= nil then
    return variantDataValid(val.Boolean, T.booleanValid, sz)
  elseif val.SByte ~= nil then
    return variantDataValid(val.SByte, T.sbyteValid, sz)
  elseif val.Byte ~= nil then
    return variantDataValid(val.Byte, T.byteValid, sz)
  elseif val.Int16 ~= nil then
    return variantDataValid(val.Int16, T.int16Valid, sz)
  elseif val.UInt16 ~= nil then
    return variantDataValid(val.UInt16, T.uint16Valid, sz)
  elseif val.Int32 ~= nil then
    return variantDataValid(val.Int32, T.int32Valid, sz)
  elseif val.UInt32 ~= nil then
    return variantDataValid(val.UInt32, T.uint32Valid, sz)
  elseif val.Int64 ~= nil then
    return variantDataValid(val.Int64, T.int64Valid, sz)
  elseif val.UInt64 ~= nil then
    return variantDataValid(val.UInt64, T.uint64Valid, sz)
  elseif val.Float ~= nil then
    return variantDataValid(val.Float, T.floatValid, sz)
  elseif val.Double ~= nil then
    return variantDataValid(val.Double, T.doubleValid, sz)
  elseif val.String ~= nil then
    return variantDataValid(val.String, T.stringValid, sz)
  elseif val.DateTime ~= nil then
    return variantDataValid(val.DateTime, T.doubleValid, sz)
  elseif val.Guid ~= nil then
    return variantDataValid(val.Guid, T.guidValid, sz)
  elseif val.ByteString ~= nil then
    if type(val.ByteString) == 'table' then
      if #val.ByteString == 0 then
        return true
      end
      if type(val.ByteString[1]) == 'table' or type(val.ByteString[1]) == 'string' then
        if sz ~= nil and #val.ByteString ~= sz then
          return false
        end
        for _,b in ipairs(val.ByteString) do
          if T.byteStringValid(b) == false then
            return false
          end
        end
        return true
      else
        return T.byteStringValid(val.ByteString)
      end
    end
    return type(val.ByteString) == 'string'
  elseif val.XmlElement ~= nil then
    return variantDataValid(val.XmlElement, T.xmlElementValid, sz)
  elseif val.NodeId ~= nil then
    return variantDataValid(val.NodeId, T.nodeIdValid, sz)
  elseif val.ExpandedNodeId ~= nil then
    return variantDataValid(val.ExpandedNodeId, T.nodeIdValid, sz)
  elseif val.StatusCode ~= nil then
    return variantDataValid(val.StatusCode, T.uint32Valid, sz)
  elseif val.QualifiedName ~= nil then
    return variantDataValid(val.QualifiedName, T.qualifiedNameValid, sz)
  elseif val.LocalizedText ~= nil then
    return variantDataValid(val.LocalizedText, T.localizedTextValid, sz)
  elseif val.ExtensionObject ~= nil then
    return variantDataValid(val.ExtensionObject, T.extensionObjectValid, sz)
  elseif val.DataValue ~= nil then
    return variantDataValid(val.DataValue, T.dataValueValid, sz)
  elseif val.Variant ~= nil then
    return variantDataValid(val.Variant, T.variantValid, sz)
  elseif val.DiagnosticInfo ~= nil then
    return variantDataValid(val.DiagnosticInfo, T.diagnosticInfoValid, sz)
  end

  return false
end


function T.getVariantType(val)
  if val.Boolean ~= nil then
    return "i=1"
  elseif val.SByte ~= nil then
    return "i=2"
  elseif val.Byte ~= nil then
    return "i=3"
  elseif val.Int16 ~= nil then
    return "i=4"
  elseif val.UInt16 ~= nil then
    return "i=5"
  elseif val.Int32 ~= nil then
    return "i=6"
  elseif val.UInt32 ~= nil then
    return "i=7"
  elseif val.Int64 ~= nil then
    return "i=8"
  elseif val.UInt64 ~= nil then
    return "i=9"
  elseif val.Float ~= nil then
    return "i=10"
  elseif val.Double ~= nil then
    return "i=11"
  elseif val.String ~= nil then
    return "i=12"
  elseif val.DateTime ~= nil then
    return "i=13"
  elseif val.Guid ~= nil then
    return "i=14"
  elseif val.ByteString ~= nil then
    return "i=15"
  elseif val.XmlElement ~= nil then
    return "i=16"
  elseif val.NodeId ~= nil then
    return "i=17"
  elseif val.ExpandedNodeId ~= nil then
    return "i=18"
  elseif val.StatusCode ~= nil then
    return "i=19"
  elseif val.QualifiedName ~= nil then
    return "i=20"
  elseif val.LocalizedText ~= nil then
    return "i=21"
  elseif val.ExtensionObject ~= nil then
    return "i=22"
  elseif val.DataValue ~= nil then
    return "i=23"
  elseif val.Variant ~= nil then
    return "i=24"
  elseif val.DiagnosticInfo ~= nil then
    return "i=25"
  end

  error("unknown variant type"..val)
end

function T.dataValueValid(v)
  if type(v) ~= 'table' then
    return false
  end
  if not T.variantValid(v.Value) then
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
  local val
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

  for _,v in pairs(value) do
    val= v
    if val ~= nil then
      break
    end
  end

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
