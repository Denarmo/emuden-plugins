-- SPDX-FileCopyrightText: Copyright 2026 EmuDEN contributors
-- SPDX-License-Identifier: GPL-3.0-or-later

-- Small helpers: URL and form encoding, Drive query quoting, RFC 3339 times, headers, the
-- PC/Steam guard.

local util = {}

function util.urlencode(text)
  return (tostring(text):gsub("[^%w%-%._~]", function(c)
    return string.format("%%%02X", c:byte())
  end))
end

-- application/x-www-form-urlencoded, keys sorted so requests are reproducible.
function util.form(fields)
  local keys, parts = {}, {}
  for key in pairs(fields) do keys[#keys + 1] = key end
  table.sort(keys)
  for _, key in ipairs(keys) do
    parts[#parts + 1] = util.urlencode(key) .. "=" .. util.urlencode(fields[key])
  end
  return table.concat(parts, "&")
end

function util.query(fields)
  return "?" .. util.form(fields)
end

-- A string literal inside a Drive `q` expression.
function util.quote(text)
  return "'" .. text:gsub("\\", "\\\\"):gsub("'", "\\'") .. "'"
end

-- Response header by name, whatever case the host gives it in.
function util.header(response, name)
  local headers = response and response.headers
  if not headers then return nil end
  if headers[name] then return headers[name] end
  local wanted = name:lower()
  for key, value in pairs(headers) do
    if type(key) == "string" and key:lower() == wanted then return value end
  end
  return nil
end

local function days_from_civil(y, m, d)
  y = m <= 2 and y - 1 or y
  local era = (y >= 0 and y or y - 399) // 400
  local yoe = y - era * 400
  local doy = (153 * (m + (m > 2 and -3 or 9)) + 2) // 5 + d - 1
  local doe = yoe * 365 + yoe // 4 - yoe // 100 + doy
  return era * 146097 + doe - 719468
end

local function civil_from_days(z)
  z = z + 719468
  local era = (z >= 0 and z or z - 146096) // 146097
  local doe = z - era * 146097
  local yoe = (doe - doe // 1460 + doe // 36524 - doe // 146096) // 365
  local y = yoe + era * 400
  local doy = doe - (365 * yoe + yoe // 4 - yoe // 100)
  local mp = (5 * doy + 2) // 153
  local d = doy - (153 * mp + 2) // 5 + 1
  local m = mp < 10 and mp + 3 or mp - 9
  return m <= 2 and y + 1 or y, m, d
end

-- "2026-11-15T10:20:30.123Z" (or with an offset) -> Unix seconds.
function util.parse_time(text)
  if type(text) ~= "string" then return nil end
  local y, mo, d, h, mi, s, rest = text:match("^(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)(.*)$")
  if not y then return nil end
  local t = days_from_civil(tonumber(y), tonumber(mo), tonumber(d)) * 86400
      + tonumber(h) * 3600 + tonumber(mi) * 60 + tonumber(s)
  local sign, oh, om = rest:match("([+-])(%d%d):?(%d%d)$")
  if sign then
    local offset = tonumber(oh) * 3600 + tonumber(om) * 60
    t = sign == "+" and t - offset or t + offset
  end
  return t
end

function util.format_time(seconds)
  seconds = math.floor(seconds)
  local days, rest = seconds // 86400, seconds % 86400
  local y, m, d = civil_from_days(days)
  return string.format("%04d-%02d-%02dT%02d:%02d:%02d.000Z", y, m, d,
                       rest // 3600, rest % 3600 // 60, rest % 60)
end

function util.bytes(n)
  n = tonumber(n)
  if not n then return "?" end
  local units = { "bytes", "KB", "MB", "GB", "TB" }
  local i = 1
  while n >= 1000 and i < #units do n, i = n / 1000, i + 1 end
  return i == 1 and string.format("%d %s", n, units[i]) or string.format("%.1f %s", n, units[i])
end

local MIME = { json = "application/json", png = "image/png", txt = "text/plain" }

function util.mime(path)
  return MIME[(path:match("%.([%w]+)$") or ""):lower()] or "application/octet-stream"
end

-- The categories of docs/sync.md section 1, as remote folders.
util.CATEGORIES = { "saves", "states", "config", "games", "bios" }
local CATEGORY = {}
for _, name in ipairs(util.CATEGORIES) do CATEGORY[name] = true end

-- Consoles of group "pc" (Steam and other PC launchers). Google Drive never receives their data
-- in any form, whatever the host sends (owner's decision, 2026-11-12). The host refuses them too.
util.PC_SYSTEMS = { steam = true, pc = true, windows = true, linux = true, macos = true,
                    gog = true, epic = true, heroic = true, lutris = true, itch = true,
                    droiddeck = true }

-- Folder names of Steam's own data, refused anywhere in a name.
local PC_WORDS = { "steamapps", "compatdata", "steamuserdata" }

-- nil when the portable name may go to Drive, else the reason it may not.
function util.refused(path)
  if type(path) ~= "string" or path == "" or path:find("\\", 1, true)
      or path:sub(1, 1) == "/" or path:find("//", 1, true) then
    return "not a portable name"
  end
  for part in path:gmatch("[^/]+") do
    if part == "." or part == ".." then return "not a portable name" end
  end
  local category = path:match("^([^/]+)/")
  if not category or not CATEGORY[category] then return "not a sync category" end
  local system = category == "config" and path:match("^config/games/([^/]+)/")
      or (category ~= "config" and category ~= "bios" and path:match("^[^/]+/([^/]+)/"))
  if system and util.PC_SYSTEMS[system:lower()] then
    return "PC and Steam data never goes to Google Drive"
  end
  local lower = path:lower()
  for _, word in ipairs(PC_WORDS) do
    if lower:find("%f[%w]" .. word .. "%f[^%w]") then
      return "PC and Steam data never goes to Google Drive"
    end
  end
  return nil
end

return util
