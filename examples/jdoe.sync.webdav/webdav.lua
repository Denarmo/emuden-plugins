-- SPDX-FileCopyrightText: Copyright 2026 J. Doe
-- SPDX-License-Identifier: MIT

-- A small WebDAV client and the sync provider over it (plugin.provider), with GET, PUT and
-- DELETE only. Every file lies flat in the one folder the user entered, its portable path
-- percent-encoded into one name (saves/gba/x.srm -> saves%2Fgba%2Fx.srm), and the index file
-- emuden-index.json there lists them: path -> {size, modified, rev}. Untested against real
-- servers; see README.md.

local dav = {}
local provider = {}
dav.provider = provider

local INDEX = "emuden-index.json"

local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local function base64(text)
  return (text:gsub("..?.?", function(group)
    local a, b, c = group:byte(1, 3)
    local n = (a << 16) | ((b or 0) << 8) | (c or 0)
    local out = ""
    for shift = 18, 0, -6 do
      local i = ((n >> shift) & 63) + 1
      out = out .. B64:sub(i, i)
    end
    return out:sub(1, #group + 1) .. string.rep("=", 3 - #group)
  end))
end
dav.base64 = base64

-- Percent-encodes everything but unreserved characters, "/" included.
local function encode(text)
  return (text:gsub("[^%w%-%._~]", function(c) return string.format("%%%02X", c:byte()) end))
end

-- The remote file's name for a portable path. In the URL the name is encoded once more, so
-- the server keeps the "%" signs as they are and never sees a "/".
function dav.name_of(path)
  return encode(path)
end

local function unquote(etag)
  return (tostring(etag or ""):gsub("^W/", ""):gsub('"', ""))
end

-- The folder the user entered, ending in "/", or nil.
function dav.base()
  return den.storage.get("base")
end

-- "nas.local:8080/dav/EmuDEN" -> "https://nas.local:8080/dav/EmuDEN/"; nil for no address.
function dav.normalize(url)
  url = tostring(url or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if url == "" then return nil end
  if not url:match("^https?://") then url = "https://" .. url end
  if not url:match("^https?://[%w%.%-]+:?%d*/?") or url:find("[%s?#]") then return nil end
  return url:sub(-1) == "/" and url or url .. "/"
end

-- One request for the remote file `name`; the user and password go as Basic authentication.
function dav.request(method, name, options)
  local base = dav.base()
  if not base then return nil, "The server is not set up." end
  local request = options or {}
  request.method, request.url = method, base .. encode(name)
  request.headers = request.headers or {}
  local user, password = den.storage.get("user"), den.secrets.get("password")
  if user and password then
    request.headers.Authorization = "Basic " .. base64(user .. ":" .. password)
  end
  local answer, why = den.http.request(request)
  if not answer then return nil, "The server could not be reached: " .. tostring(why) end
  if answer.status == 401 or answer.status == 403 then
    return nil, "The server refused the user name or password."
  end
  return answer
end

-- The index: { version = 1, files = { [path] = {size, modified, rev} } }. A missing index is
-- an empty one.
function dav.read_index()
  local answer, why = dav.request("GET", INDEX)
  if not answer then return nil, why end
  if answer.status == 404 then return { version = 1, files = {} } end
  if answer.status ~= 200 then return nil, "The server answered " .. answer.status .. " for the index." end
  local index = den.json.decode(answer.body)
  if type(index) ~= "table" or type(index.files) ~= "table" then
    return nil, "The index on the server cannot be read."
  end
  return index
end

function dav.write_index(index)
  local answer, why = dav.request("PUT", INDEX, {
    headers = { ["Content-Type"] = "application/json" }, body = den.json.encode(index) })
  if not answer then return nil, why end
  if answer.status == 404 or answer.status == 409 then
    return nil, "The folder is not on the server; make it there first."
  end
  if answer.status < 200 or answer.status > 204 then
    return nil, "The server answered " .. answer.status .. " when writing the index."
  end
  return true
end

-- The provider contract (docs/lua-api.md, "Sync providers"). list(nil) and list("") are
-- everything; otherwise prefix is a folder such as "saves/" or "saves/gba/".
function provider.list(prefix)
  local index, why = dav.read_index()
  if not index then return nil, why end
  prefix = prefix or ""
  local files = {}
  for path, entry in pairs(index.files) do
    if type(entry) == "table" and path:sub(1, #prefix) == prefix then
      files[#files + 1] = { path = path, size = entry.size, modified = entry.modified, rev = entry.rev }
    end
  end
  table.sort(files, function(a, b) return a.path < b.path end)
  return files
end

function provider.get(path, local_path, progress)
  local answer, why = dav.request("GET", dav.name_of(path), { to_file = local_path, on_progress = progress })
  if not answer then return nil, why end
  if answer.status == 404 then return nil, path .. " is not on the server." end
  if answer.status ~= 200 then return nil, "The server answered " .. answer.status .. "." end
  return true
end

-- The rev is the server's ETag when it gives one, else size and time. A put over another rev
-- than the index holds is a conflict.
function provider.put(path, local_path, rev, modified, progress)
  local index, why = dav.read_index()
  if not index then return nil, why end
  local known = index.files[path]
  if rev and type(known) == "table" and tostring(known.rev) ~= tostring(rev) then
    return nil, "conflict"
  end
  local size = den.files.size(local_path) or 0
  local answer
  answer, why = dav.request("PUT", dav.name_of(path), {
    headers = { ["Content-Type"] = "application/octet-stream" }, body_file = local_path, on_progress = progress })
  if not answer then return nil, why end
  if answer.status == 404 or answer.status == 409 then
    return nil, "The folder is not on the server; make it there first."
  end
  if answer.status < 200 or answer.status > 204 then return nil, "The server answered " .. answer.status .. "." end
  local new_rev = unquote(answer.headers.etag)
  if new_rev == "" then new_rev = string.format("%d@%d", size, modified or 0) end
  index.files[path] = { size = size, modified = modified or 0, rev = new_rev }
  local ok
  ok, why = dav.write_index(index)
  if not ok then return nil, why end
  return new_rev
end

function provider.delete(path)
  local answer, why = dav.request("DELETE", dav.name_of(path))
  if not answer then return nil, why end
  if answer.status ~= 200 and answer.status ~= 204 and answer.status ~= 404 then
    return nil, "The server answered " .. answer.status .. "."
  end
  local index
  index, why = dav.read_index()
  if not index then return nil, why end
  if index.files[path] ~= nil then
    index.files[path] = nil
    local ok
    ok, why = dav.write_index(index)
    if not ok then return nil, why end
  end
  return true
end

function provider.status()
  return { server = dav.base(), user = den.storage.get("user") }
end

-- For the page: whether the folder answers; writes an empty index when there is none.
function dav.check()
  local answer, why = dav.request("GET", INDEX)
  if not answer then return nil, why end
  if answer.status == 200 then return "Connected." end
  if answer.status ~= 404 then return nil, "The server answered " .. answer.status .. "." end
  local ok
  ok, why = dav.write_index({ version = 1, files = {} })
  if not ok then return nil, why end
  return "Connected. The index was made."
end

return dav
