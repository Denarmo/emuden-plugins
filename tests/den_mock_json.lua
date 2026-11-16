-- SPDX-FileCopyrightText: Copyright 2026 EmuDEN contributors
-- SPDX-License-Identifier: GPL-3.0-or-later

-- den.json for den_mock.lua, as the app converts: a table with a first element (or none at all)
-- is an array, other tables are objects with text keys (number keys become text); JSON null is
-- `null` (in the app a light userdata, here a table); whole numbers decode as integers.

local NULL = setmetatable({}, { __name = "den.json.null", __tostring = function() return "null" end,
                                __newindex = function() error("den.json.null is read only", 2) end })
local ESC = { ['"'] = '\\"', ["\\"] = "\\\\", ["\b"] = "\\b", ["\f"] = "\\f", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }

local function encode(v, depth, out)
  local t = type(v)
  if v == nil or v == NULL then out[#out + 1] = "null"
  elseif t == "boolean" then out[#out + 1] = tostring(v)
  elseif t == "number" then
    if v ~= v or v == math.huge or v == -math.huge then error("a number that is not finite has no JSON form", 0) end
    if math.type(v) == "integer" then out[#out + 1] = tostring(v)
    elseif v == math.floor(v) and math.abs(v) < 2 ^ 53 then out[#out + 1] = string.format("%.0f", v)
    else out[#out + 1] = string.format("%.17g", v) end
  elseif t == "string" then
    out[#out + 1] = '"' .. v:gsub('[%c"\\]', function(c) return ESC[c] or string.format("\\u%04x", c:byte()) end) .. '"'
  elseif t == "table" then
    if depth >= 32 then error("the table is nested too deeply", 0) end
    local n = rawlen(v)
    if n > 0 or next(v) == nil then -- the app: a first element, or nothing at all, is an array
      out[#out + 1] = "["
      for i = 1, n do
        if i > 1 then out[#out + 1] = "," end
        encode(rawget(v, i), depth + 1, out)
      end
      out[#out + 1] = "]"
    else
      out[#out + 1] = "{"
      local first = true
      for k, item in pairs(v) do
        if type(k) ~= "string" and type(k) ~= "number" then error("a table key that is not text has no JSON form", 0) end
        if not first then out[#out + 1] = "," end
        first = false
        encode(tostring(k), depth + 1, out)
        out[#out + 1] = ":"
        encode(item, depth + 1, out)
      end
      out[#out + 1] = "}"
    end
  else error("a " .. t .. " has no JSON form", 0) end
end

local function json_encode(v)
  local out = {}
  encode(v, 0, out)
  return table.concat(out)
end

local function json_decode(text)
  local pos = 1
  local function fail() error({ json = true }, 0) end
  local function ws() pos = text:find("[^ \t\r\n]", pos) or #text + 1 end
  local value
  local function str()
    local out = {}
    pos = pos + 1
    while true do
      local c = text:sub(pos, pos)
      if c == "" then fail() elseif c == '"' then pos = pos + 1 return table.concat(out)
      elseif c == "\\" then
        local e = text:sub(pos + 1, pos + 1)
        local simple = ({ b = "\b", f = "\f", n = "\n", r = "\r", t = "\t", ['"'] = '"', ["\\"] = "\\", ["/"] = "/" })[e]
        if simple then out[#out + 1] = simple pos = pos + 2
        elseif e == "u" then
          local code = tonumber(text:sub(pos + 2, pos + 5), 16) or fail()
          pos = pos + 6
          if code >= 0xd800 and code < 0xdc00 and text:sub(pos, pos + 1) == "\\u" then
            local low = tonumber(text:sub(pos + 2, pos + 5), 16) or fail()
            code = 0x10000 + (code - 0xd800) * 0x400 + (low - 0xdc00)
            pos = pos + 6
          end
          out[#out + 1] = utf8.char(code)
        else fail() end
      else
        local s, e = text:find('^[^"\\]+', pos)
        out[#out + 1] = text:sub(s, e)
        pos = e + 1
      end
    end
  end
  function value()
    ws()
    local c = text:sub(pos, pos)
    if c == "{" then
      local obj = {}
      pos = pos + 1 ws()
      if text:sub(pos, pos) == "}" then pos = pos + 1 return obj end
      while true do
        ws()
        if text:sub(pos, pos) ~= '"' then fail() end
        local k = str() ws()
        if text:sub(pos, pos) ~= ":" then fail() end
        pos = pos + 1
        obj[k] = value() ws()
        local d = text:sub(pos, pos) pos = pos + 1
        if d == "}" then return obj elseif d ~= "," then fail() end
      end
    elseif c == "[" then
      local arr = {}
      pos = pos + 1 ws()
      if text:sub(pos, pos) == "]" then pos = pos + 1 return arr end
      while true do
        arr[#arr + 1] = value() ws()
        local d = text:sub(pos, pos) pos = pos + 1
        if d == "]" then return arr elseif d ~= "," then fail() end
      end
    elseif c == '"' then return str()
    elseif text:sub(pos, pos + 3) == "true" then pos = pos + 4 return true
    elseif text:sub(pos, pos + 4) == "false" then pos = pos + 5 return false
    elseif text:sub(pos, pos + 3) == "null" then pos = pos + 4 return NULL
    else
      local s, e = text:find("^-?%d+%.?%d*[eE]?[-+]?%d*", pos)
      if not s then fail() end
      local n = tonumber(text:sub(s, e)) or fail()
      pos = e + 1
      if n == math.floor(n) and math.abs(n) < 9e15 then return math.tointeger(n) end
      return n
    end
  end
  local ok, result = pcall(function() local v = value() ws() if pos <= #text then fail() end return v end)
  if ok then return result end
  if type(result) == "table" and result.json then return nil, "the text is not JSON" end
  error(result, 0)
end
return { encode = json_encode, decode = json_decode, null = NULL }
