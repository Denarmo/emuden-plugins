-- Syncthing's REST API on this device (http.local). Checked against Syncthing v2.1.7
-- (lib/api/api.go, lib/api/confighandler.go) and docs.syncthing.net/dev/rest.html.
local M = {}

M.DEFAULT_ADDRESS = "127.0.0.1:8384"
M.FOLDER_ID = "emuden"
M.FOLDER_LABEL = "EmuDEN"

-- http.local reaches only the loopback names, on any port.
function M.check_address(text)
  local address = (text or ""):gsub("^%s+", ""):gsub("%s+$", ""):gsub("^https?://", "")
      :gsub("/+$", "")
  local host, port = address:match("^([%w%.]+):(%d+)$")
  if not host then
    host, port = address:match("^([%w%.]+)$"), "8384"
  end
  host = host and host:lower()
  if host ~= "127.0.0.1" and host ~= "localhost" then
    return nil, "Only Syncthing on this device: 127.0.0.1 or localhost, with its port."
  end
  local number = tonumber(port)
  if not number or number < 1 or number > 65535 then
    return nil, "That port is not a number from 1 to 65535."
  end
  return host .. ":" .. number
end

local function header(response, name)
  for key, value in pairs(response.headers or {}) do
    if key:lower() == name then return value end
  end
end

local Client = {}
Client.__index = Client

-- request is den.http.request, json is den.json.
function M.new(address, key, request, json)
  return setmetatable({ address = address, key = key, request = request, json = json }, Client)
end

-- Syncthing-Fork on Android serves its GUI over TLS; plain http then answers with a 307 to
-- https. The scheme that worked is remembered for the client's later calls.
function Client:call(method, path, body)
  local schemes = self.scheme and { self.scheme } or { "http", "https" }
  local failure
  for _, scheme in ipairs(schemes) do
    local headers = { ["X-API-Key"] = self.key, ["Accept"] = "application/json" }
    local text
    if body ~= nil then
      text = self.json.encode(body)
      headers["Content-Type"] = "application/json"
    end
    local response, err = self.request{ url = scheme .. "://" .. self.address .. "/rest/" .. path,
                                        method = method, headers = headers, body = text }
    if response then
      local location = header(response, "location") or ""
      local redirected = response.status >= 300 and response.status < 400
      if not (redirected and scheme == "http" and location:match("^https://")) then
        self.scheme = scheme
        return response
      end
      failure = "Syncthing only answers over https"
    else
      failure = err
    end
  end
  return nil, failure
end

-- Decoded JSON of a 2xx answer, or nil, message (and the status, for callers that need it).
function Client:json_call(method, path, body)
  local response, err = self:call(method, path, body)
  if not response then
    return nil, "Syncthing does not answer at " .. self.address .. " (" .. tostring(err) .. ")."
  end
  local status = response.status
  if status == 401 or status == 403 then
    return nil, "Syncthing refused the API key.", status
  elseif status < 200 or status >= 300 then
    local why = (response.body or ""):gsub("%s+$", "")
    return nil, "Syncthing answered " .. status .. (why ~= "" and (": " .. why) or "") .. ".",
           status
  end
  if not response.body or response.body == "" then return {} end
  local value = self.json.decode(response.body)
  if value == nil then return nil, "Syncthing sent something that is not JSON." end
  return value
end

local function text(value)
  return type(value) == "string" and value or ""
end

-- { id, home }: this device's id and the home folder Syncthing runs in; on failure also the
-- HTTP status, so a refused key can be told from Syncthing not running.
function Client:system()
  local status, err, code = self:json_call("GET", "system/status")
  if not status then return nil, err, code end
  if text(status.myID) == "" then return nil, "Syncthing did not say which device this is." end
  return { id = status.myID, home = text(status.tilde) }
end

-- { {id, name} } of the devices Syncthing knows, this one included.
function Client:devices()
  local list, err = self:json_call("GET", "config/devices")
  if not list then return nil, err end
  local devices = {}
  for _, device in ipairs(list) do
    if text(device.deviceID) ~= "" then
      devices[#devices + 1] = { id = device.deviceID, name = text(device.name) }
    end
  end
  return devices
end

function Client:folders()
  return self:json_call("GET", "config/folders")
end

-- The folder "emuden" as Syncthing has it, false when there is none.
function Client:folder()
  local folder, err, status = self:json_call("GET", "config/folders/" .. M.FOLDER_ID)
  if folder then return folder end
  if status == 404 then return false end
  return nil, err
end

-- Folder paths compared the way they name the same place on the device.
function M.same_path(a, b)
  local function norm(path)
    path = text(path):gsub("\\", "/"):gsub("/+$", "")
    if path:match("^%a:") then path = path:lower() end
    return path
  end
  return norm(a) ~= "" and norm(a) == norm(b)
end

-- Another of the user's folders already at path: its label or id.
function Client:folder_at(path)
  local folders = self:folders()
  for _, folder in ipairs(folders or {}) do
    if folder.id ~= M.FOLDER_ID and M.same_path(folder.path, path) then
      return text(folder.label) ~= "" and folder.label or folder.id
    end
  end
end

-- The device list of the folder: this device and the ones ticked, keeping what Syncthing
-- recorded for each (introducedBy, encryptionPassword) and the entries of devices the page
-- does not list, which the user had no way to untick.
function M.folder_devices(existing, my_id, ticked, known)
  local old, listed, result, seen = {}, {}, {}, {}
  for _, entry in ipairs(existing or {}) do old[entry.deviceID] = entry end
  for _, device in ipairs(known or {}) do listed[device.id] = true end
  local function add(id)
    if seen[id] then return end
    seen[id] = true
    local entry = old[id]
    result[#result + 1] = { deviceID = id, introducedBy = entry and entry.introducedBy or "",
                            encryptionPassword = entry and entry.encryptionPassword or "" }
  end
  add(my_id)
  for _, device in ipairs(known or {}) do
    if ticked[device.id] then add(device.id) end
  end
  for _, entry in ipairs(existing or {}) do
    if not listed[entry.deviceID] then add(entry.deviceID) end
  end
  return result
end

-- Adds the folder "emuden" or updates its label, path, type and devices. Other folders and
-- the folder's other settings are left as they are: a new folder takes Syncthing's folder
-- defaults (POST fills in from them), an existing one is patched field by field.
function Client:save_folder(path, my_id, ticked, known)
  local current, err = self:folder()
  if current == nil then return nil, err end
  local other = self:folder_at(path)
  if other then
    return nil, "Syncthing already syncs this folder as \"" .. other .. "\". Choose another " ..
                "folder, or remove that one from Syncthing first."
  end
  local fields = { label = M.FOLDER_LABEL, path = path, type = "sendreceive",
                   devices = M.folder_devices(current and current.devices, my_id, ticked, known) }
  local ok
  if current then
    ok, err = self:json_call("PATCH", "config/folders/" .. M.FOLDER_ID, fields)
  else
    fields.id = M.FOLDER_ID
    ok, err = self:json_call("POST", "config/folders", fields)
  end
  if not ok then return nil, err end
  return current and "updated" or "added"
end

-- Completion of the folder on a device (nil: this one): {percent, need_bytes, state}.
function Client:completion(device)
  local query = "db/completion?folder=" .. M.FOLDER_ID
  if device then query = query .. "&device=" .. device end
  local result, err = self:json_call("GET", query)
  if not result then return nil, err end
  return { percent = tonumber(result.completion) or 0, need_bytes = tonumber(result.needBytes) or 0,
           state = text(result.remoteState) }
end

-- When Syncthing last synced a file of the folder and which: {at, file, scan}.
-- stats/folder is cheap, unlike db/status, which the docs call expensive.
function Client:last_sync()
  local stats, err = self:json_call("GET", "stats/folder")
  if not stats then return nil, err end
  local folder = stats[M.FOLDER_ID]
  if type(folder) ~= "table" then return {} end
  local last = type(folder.lastFile) == "table" and folder.lastFile or {}
  return { at = text(last.at), file = text(last.filename), scan = text(folder.lastScan) }
end

-- "2026-11-15T10:22:31.12+01:00" -> "2026-11-15 10:22"; Syncthing's zero time is "never".
function M.when(stamp)
  local date, clock = text(stamp):match("^(%d%d%d%d%-%d%d%-%d%d)T(%d%d:%d%d)")
  if not date or date:sub(1, 4) == "0001" then return nil end
  return date .. " " .. clock
end

return M
