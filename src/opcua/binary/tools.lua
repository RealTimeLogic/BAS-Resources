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
    type(browseName.name) == 'string'
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
  return
  type(v) == 'table' and
  T.uint32Valid(v.data1) and
  T.uint16Valid(v.data2) and
  T.uint16Valid(v.data3) and
  T.byteValid(v.data4) and
  T.byteValid(v.data5) and
  T.byteValid(v.data6) and
  T.byteValid(v.data7) and
  T.byteValid(v.data8) and
  T.byteValid(v.data9) and
  T.byteValid(v.data10) and
  T.byteValid(v.data11)
end

function T.localizedTextValid(v)
  return type(v) == 'table' and
  (v.locale == nil or type(v.locale) == 'string') and
  type(v.text) == 'string'
end

function T.qualifiedNameValid(v)
  return type(v) == 'table' and T.uint16Valid(v.ns) and  type(v.name) == 'string'
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

  if v.value == nil then
    return false
  end

  return type(v.value) == 'string'
end

function T.nodeIdValid(v)
  return nodeId.isValid(v)
end

function T.dataValueValid(v)
  if type(v) ~= 'table' then
    return false
  end
  if not T.variantValid(v.value) then
    return false
  end
  if v.statusCode ~= nil and not T.uint32Valid(v.statusCode) then
    return false
  end
  if v.sourceTimestamp ~= nil and not T.doubleValid(v.sourceTimestamp) then
    return false
  end
  if v.serverTimestamp ~= nil and not T.doubleValid(v.serverTimestamp) then
    return false
  end
  if v.sourcePicoseconds ~= nil and not T.uint16Valid(v.sourcePicoseconds) then
    return false
  end
  if v.serverPicoseconds ~= nil and not T.uint16Valid(v.serverPicoseconds) then
    return false
  end

  return true
end

function T.diagnosticInfoValid(v)
  if type(v) ~= 'table' then
    return false
  end

  if v.symbolicId ~= nil and not T.int32Valid(v.symbolicId) then
    return false
  end
  if v.nsUri ~= nil and not T.int32Valid(v.nsUri) then
    return false
  end
  if v.locale ~= nil and not T.int32Valid(v.locale) then
    return false
  end
  if v.localizedText ~= nil and not T.int32Valid(v.localizedText) then
    return false
  end
  if v.additionalInfo ~= nil and not T.stringValid(v.additionalInfo) then
    return false
  end
  if v.innerStatusCode ~= nil and not T.uint32Valid(v.innerStatusCode) then
    return false
  end
  if v.innerDiagnosticInfo ~= nil and not T.diagnosticInfoValid(v.innerDiagnosticInfo) then
    return false
  end
  return true
end

local function variantDataValid(data, f)
  if type(data) == "table" and #data > 0 then
    for _,el in ipairs(data) do
      if not f(el) then
        return false
      end
    end
    return true
  else
    return f(data)
  end
end

function T.variantValid(val)
  if type(val) ~= 'table' or val == {} then
    return false
  end

  if val.boolean ~= nil then
    return variantDataValid(val.boolean, T.booleanValid)
  elseif val.sbyte ~= nil then
    return variantDataValid(val.sbyte, T.sbyteValid)
  elseif val.byte ~= nil then
    return variantDataValid(val.byte, T.byteValid)
  elseif val.int16 ~= nil then
    return variantDataValid(val.int16, T.int16Valid)
  elseif val.uint16 ~= nil then
    return variantDataValid(val.uint16, T.uint16Valid)
  elseif val.int32 ~= nil then
    return variantDataValid(val.int32, T.int32Valid)
  elseif val.uint32 ~= nil then
    return variantDataValid(val.uint32, T.uint32Valid)
  elseif val.int64 ~= nil then
    return variantDataValid(val.int64, T.int64Valid)
  elseif val.uint64 ~= nil then
    return variantDataValid(val.uint64, T.uint64Valid)
  elseif val.float ~= nil then
    return variantDataValid(val.float, T.floatValid)
  elseif val.double ~= nil then
    return variantDataValid(val.double, T.doubleValid)
  elseif val.string ~= nil then
    return variantDataValid(val.string, T.stringValid)
  elseif val.dateTime ~= nil then
    return variantDataValid(val.dateTime, T.doubleValid)
  elseif val.guid ~= nil then
    return variantDataValid(val.guid, T.guidValid)
  elseif val.byteString ~= nil then
    if type(val.byteString) ~= 'table' then
      return false
    end
    if #val.byteString == 0 then
      return true
    end
    if type(val.byteString[1]) == 'table' then
      for _,b in ipairs(val.byteString) do
        if T.byteStringValid(b) == false then
          return false
        end
      end
      return true
    else
      return T.byteStringValid(val.byteString)
    end
  elseif val.xmlElement ~= nil then
    return variantDataValid(val.xmlElement, T.xmlElementValid)
  elseif val.nodeId ~= nil then
    return variantDataValid(val.nodeId, T.nodeIdValid)
  elseif val.expandedNodeId ~= nil then
    return variantDataValid(val.expandedNodeId, T.nodeIdValid)
  elseif val.statusCode ~= nil then
    return variantDataValid(val.statusCode, T.uint32Valid)
  elseif val.qualifiedName ~= nil then
    return variantDataValid(val.qualifiedName, T.qualifiedNameValid)
  elseif val.localizedText ~= nil then
    return variantDataValid(val.localizedText, T.localizedTextValid)
  elseif val.extensionObject ~= nil then
    return variantDataValid(val.extensionObject, T.extensionObjectValid)
  elseif val.dataValue ~= nil then
    return variantDataValid(val.dataValue, T.dataValueValid)
  elseif val.variant ~= nil then
    return variantDataValid(val.variant, T.variantValid)
  elseif val.diagnosticInfo ~= nil then
    return variantDataValid(val.diagnosticInfo, T.diagnosticInfoValid)
  end

  return false
end


function T.getVariantType(val)
  if val.boolean ~= nil then
    return "i=1"
  elseif val.sbyte ~= nil then
    return "i=2"
  elseif val.byte ~= nil then
    return "i=3"
  elseif val.int16 ~= nil then
    return "i=4"
  elseif val.uint16 ~= nil then
    return "i=5"
  elseif val.int32 ~= nil then
    return "i=6"
  elseif val.uint32 ~= nil then
    return "i=7"
  elseif val.int64 ~= nil then
    return "i=8"
  elseif val.uint64 ~= nil then
    return "i=9"
  elseif val.float ~= nil then
    return "i=10"
  elseif val.double ~= nil then
    return "i=11"
  elseif val.string ~= nil then
    return "i=12"
  elseif val.dateTime ~= nil then
    return "i=13"
  elseif val.guid ~= nil then
    return "i=14"
  elseif val.byteString ~= nil then
    return "i=15"
  elseif val.xmlElement ~= nil then
    return "i=16"
  elseif val.nodeId ~= nil then
    return "i=17"
  elseif val.expandedNodeId ~= nil then
    return "i=18"
  elseif val.statusCode ~= nil then
    return "i=19"
  elseif val.qualifiedName ~= nil then
    return "i=20"
  elseif val.localizedText ~= nil then
    return "i=21"
  elseif val.extensionObject ~= nil then
    return "i=22"
  elseif val.dataValue ~= nil then
    return "i=23"
  elseif val.variant ~= nil then
    return "i=24"
  elseif val.diagnosticInfo ~= nil then
    return "i=25"
  end

  error("unknown variant type"..val)
end

function T.extensionObjectValid(v)
--  return type(v) == 'table' and T.nodeIdValid(v.typeId) and T.byteStringValid(v.body)
  return type(v) == 'table' and T.nodeIdValid(v.typeId) and (v.body == nil or type(v.body) == 'table' or T.byteStringValid(v.body))
end

function T.valueRankValid(v)
  return T.int32Valid(v) and v >=-3 and v <= 2
end


local function scalarValid(val, arrayDimensions)
  return val == nil or (arrayDimensions == nil or arrayDimensions == {-1}) and (type(val) ~= 'table' or #val == 0 or T.byteStringValid(val))
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
    typeId = "i=321",
    body = {
      policyId = policyId
    }
  }
end

function T.createUsernameToken(policyId, username, password, encryptionAlgorithm)
  return {
    typeId = "i=324",
    body = {
      policyId = policyId,
      userName = username,
      password = password,
      encryptionAlgorithm = encryptionAlgorithm
    }
  }
end

function T.createX509Token(policyId, cert)
  return {
    typeId = "i=327",
    body = {
      policyId = policyId,
      certificateData = cert
    }
  }
end

function T.createIssuedToken(policyId, token, encryptionAlgorithm)
  return {
    typeId = "i=940",
    body = {
      policyId = policyId,
      tokenData = token,
      encryptionAlgorithm = encryptionAlgorithm
    }
  }
end


return T
