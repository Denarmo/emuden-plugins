-- SPDX-FileCopyrightText: Copyright 2026 EmuDEN contributors
-- SPDX-License-Identifier: GPL-3.0-or-later

-- A small JSON codec standing in for den.json in offline tests.

local json = { null = setmetatable({}, { __tostring = function() return "null" end }) }

local escapes = { ['"'] = '\\"', ["\\"] = "\\\\", ["\b"] = "\\b", ["\f"] = "\\f",
                  ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }

local function is_array(t)
  local n = 0
  for k in pairs(t) do
    if type(k) ~= "number" then
      return false
    end
    n = n + 1
  end
  return n == #t
end

function json.encode(v)
  local kind = type(v)
  if v == nil or v == json.null then
    return "null"
  elseif kind == "boolean" then
    return tostring(v)
  elseif kind == "number" then
    return math.type(v) == "integer" and tostring(v) or string.format("%.14g", v)
  elseif kind == "string" then
    return '"' .. v:gsub('[%c"\\]', function(c)
      return escapes[c] or string.format("\\u%04x", c:byte())
    end) .. '"'
  elseif kind == "table" then
    local parts = {}
    if next(v) == nil or is_array(v) then
      for i = 1, #v do
        parts[i] = json.encode(v[i])
      end
      return "[" .. table.concat(parts, ",") .. "]"
    end
    local keys = {}
    for k in pairs(v) do
      keys[#keys + 1] = tostring(k)
    end
    table.sort(keys)
    for _, k in ipairs(keys) do
      parts[#parts + 1] = json.encode(k) .. ":" .. json.encode(v[k])
    end
    return "{" .. table.concat(parts, ",") .. "}"
  end
  error("cannot encode " .. kind)
end

function json.decode(text)
  local pos = 1
  local function space()
    pos = text:find("[^ \t\r\n]", pos) or #text + 1
  end
  local value
  local function str()
    local out = {}
    pos = pos + 1
    while true do
      local c = text:sub(pos, pos)
      if c == '"' then
        pos = pos + 1
        return table.concat(out)
      elseif c == "\\" then
        local e = text:sub(pos + 1, pos + 1)
        local map = { b = "\b", f = "\f", n = "\n", r = "\r", t = "\t" }
        if e == "u" then
          out[#out + 1] = utf8.char(tonumber(text:sub(pos + 2, pos + 5), 16))
          pos = pos + 6
        else
          out[#out + 1] = map[e] or e
          pos = pos + 2
        end
      elseif c == "" then
        error("unterminated string")
      else
        out[#out + 1] = c
        pos = pos + 1
      end
    end
  end
  function value()
    space()
    local c = text:sub(pos, pos)
    if c == "{" then
      local t = {}
      pos = pos + 1
      space()
      if text:sub(pos, pos) == "}" then
        pos = pos + 1
        return t
      end
      while true do
        space()
        local k = str()
        space()
        pos = pos + 1   -- :
        t[k] = value()
        space()
        local d = text:sub(pos, pos)
        pos = pos + 1
        if d == "}" then
          return t
        end
      end
    elseif c == "[" then
      local t = {}
      pos = pos + 1
      space()
      if text:sub(pos, pos) == "]" then
        pos = pos + 1
        return t
      end
      while true do
        t[#t + 1] = value()
        space()
        local d = text:sub(pos, pos)
        pos = pos + 1
        if d == "]" then
          return t
        end
      end
    elseif c == '"' then
      return str()
    elseif text:sub(pos, pos + 3) == "true" then
      pos = pos + 4
      return true
    elseif text:sub(pos, pos + 4) == "false" then
      pos = pos + 5
      return false
    elseif text:sub(pos, pos + 3) == "null" then
      pos = pos + 4
      return json.null
    end
    local num = text:match("^-?%d+%.?%d*[eE]?[-+]?%d*", pos)
    if not num then
      error("bad JSON at " .. pos)
    end
    pos = pos + #num
    return math.tointeger(tonumber(num)) or tonumber(num)
  end
  local ok, result = pcall(value)
  if not ok then
    return nil
  end
  return result
end

return json
