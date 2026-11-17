-- Offline test of emuden.sync.syncthing: a fake `den` and a fake Syncthing REST API.
-- Run from the repository root: python -I tools/plugin_tool.py test plugins/emuden.sync.syncthing
local DIR = "plugins/emuden.sync.syncthing/"
local ME = "MEMEMEM-AAAAAAA-BBBBBBB-CCCCCCC-DDDDDDD-EEEEEEE-FFFFFFF-GGGGGGG"
local LAPTOP = "LAPTOPX-AAAAAAA-BBBBBBB-CCCCCCC-DDDDDDD-EEEEEEE-FFFFFFF-GGGGGGG"
local RETROID = "RETROID-AAAAAAA-BBBBBBB-CCCCCCC-DDDDDDD-EEEEEEE-FFFFFFF-GGGGGGG"
local KEY = "goodkey123"

local failures, checks = 0, 0
local function check(ok, what)
  checks = checks + 1
  if not ok then
    failures = failures + 1
    print("FAIL: " .. what)
  end
end

local function copy(value)
  if type(value) ~= "table" then return value end
  local out = {}
  for k, v in pairs(value) do out[k] = copy(v) end
  return out
end

-- den.json: values travel as tokens, so the test needs no JSON parser but still sees that the
-- plugin encodes what it sends and decodes what it receives.
local json_store = {}
local json = { null = setmetatable({}, { __name = "null" }) }
function json.encode(value)
  json_store[#json_store + 1] = copy(value)
  return "<json#" .. #json_store .. ">"
end
function json.decode(text)
  local n = tonumber(tostring(text):match("^<json#(%d+)>$"))
  return n and copy(json_store[n]) or nil
end

-- The fake Syncthing.
local st
local function reset_syncthing()
  st = {
    up = true, tls = false, port = "8384", requests = {},
    devices = { { deviceID = ME, name = "PC" }, { deviceID = LAPTOP, name = "Laptop" },
                { deviceID = RETROID, name = "" } },
    folders = { { id = "default", label = "Default Folder", path = "/home/u/Sync",
                  type = "sendreceive", rescanIntervalS = 3600, devices = { { deviceID = ME } } } },
    stats = {},
  }
end

local function find_folder(id)
  for i, folder in ipairs(st.folders) do
    if folder.id == id then return folder, i end
  end
end

local function answer(status, value, headers)
  return { status = status, body = value ~= nil and json.encode(value) or "", headers = headers or {} }
end

local function syncthing_request(req)
  local scheme, host, port, path = req.url:match("^(https?)://([^/:]+):(%d+)/rest/(.*)$")
  if not scheme or (host ~= "127.0.0.1" and host ~= "localhost") then
    error("plugin reached past http.local: " .. req.url)
  end
  if not st.up or port ~= st.port then return nil, "connection refused" end
  local method = req.method or "GET"
  st.requests[#st.requests + 1] = method .. " " .. scheme .. " " .. path
  if st.tls and scheme == "http" then
    return answer(307, nil, { location = "https://" .. host .. ":" .. port .. "/rest/" .. path })
  end
  if req.headers["X-API-Key"] ~= KEY then return answer(403, nil) end
  local body = req.body and json.decode(req.body)
  local route, query = path:match("^([^?]*)%??(.*)$")
  if method == "GET" and route == "system/status" then
    return answer(200, { myID = ME, tilde = "/home/u", pathSeparator = "/" })
  elseif method == "GET" and route == "config/devices" then
    return answer(200, st.devices)
  elseif method == "GET" and route == "config/folders" then
    return answer(200, st.folders)
  elseif method == "POST" and route == "config/folders" then
    local folder = { rescanIntervalS = 3600, fsWatcherEnabled = true }   -- Syncthing's defaults
    for k, v in pairs(body) do folder[k] = v end
    local _, at = find_folder(folder.id)
    st.folders[at or #st.folders + 1] = folder
    return answer(200, nil)
  elseif route:match("^config/folders/") then
    local folder = find_folder(route:match("^config/folders/(.*)$"))
    if not folder then return { status = 404, body = "No folder with given ID\n", headers = {} } end
    if method == "GET" then return answer(200, folder) end
    if method == "PATCH" then
      for k, v in pairs(body) do folder[k] = v end
      return answer(200, nil)
    end
  elseif method == "GET" and route == "db/completion" then
    local device = query:match("device=([^&]+)")
    if device == RETROID then return answer(200, { completion = 0, needBytes = 0, remoteState = "unknown" }) end
    return answer(200, { completion = device and 100 or 87.5, needBytes = device and 0 or 3 * 1048576,
                         remoteState = device and "valid" or "unknown" })
  elseif method == "GET" and route == "stats/folder" then
    return answer(200, st.stats)
  end
  return answer(404, nil)
end

-- The fake den.
local page, toasts, storage, secrets, use_folder_calls, host_folder, picker, sync_runs
local run_conflicts = 0
local function reset_den(platform)
  page, toasts, storage, secrets, use_folder_calls, host_folder = nil, {}, {}, {}, {}, nil
  picker, sync_runs = "/home/u/Elsewhere", 0
  return platform
end

local function make_env(platform)
  local env = { pairs = pairs, ipairs = ipairs, type = type, tostring = tostring,
                tonumber = tonumber, setmetatable = setmetatable, string = string,
                table = table, math = math, error = error, pcall = pcall, select = select }
  local den = {
    api = 1, plugin = { id = "emuden.sync.syncthing", version = "1.0.0" },
    device = { platform = platform }, json = json, log = function() end,
    now = function() return 1763200000 end,
    language = function() return "en" end,
    tr = function(text, ...)
      local values, out, i, n = table.pack(...), {}, 1, 0
      while i <= #text do
        local two = text:sub(i, i + 1)
        if two == "{{" or two == "}}" then out[#out + 1] = two:sub(1, 1); i = i + 2
        elseif two == "{}" then n = n + 1; out[#out + 1] = tostring(values[n]); i = i + 2
        else out[#out + 1] = text:sub(i, i); i = i + 1 end
      end
      return table.concat(out)
    end,
    sleep = function() end,
    storage = { get = function(k) return copy(storage[k]) end,
                set = function(k, v) storage[k] = copy(v) end,
                remove = function(k) storage[k] = nil end },
    secrets = { get = function(k) return secrets[k] end,
                set = function(k, v) secrets[k] = v end,
                remove = function(k) secrets[k] = nil end },
    http = { request = syncthing_request },
    ui = { set = function(p) page = p end, toast = function(t) toasts[#toasts + 1] = t end },
    sync = {
      folder = function() return host_folder end,
      status = function()
        local s = { active = host_folder ~= nil, running = false, last_sync = 1763200000 - 300,
                    uploaded = 1, downloaded = 0, conflicts = run_conflicts, waiting = 0, errors = {} }
        s.folder = host_folder
        return s
      end,
      now = function()
        if not host_folder then return nil, "This plugin is not the active sync provider" end
        sync_runs = sync_runs + 1
        return true
      end,
      use_folder = function(path)
        use_folder_calls[#use_folder_calls + 1] = path or "<picker>"
        if path == nil then
          if not picker then return nil, "no folder was chosen" end
          host_folder = picker
          return host_folder
        end
        host_folder = path:gsub("^~", platform:find("android") and "/storage/emulated/0" or "/home/u")
        return host_folder
      end,
    },
  }
  function den.include(name)
    local chunk = assert(loadfile(DIR .. name, "t", env))
    return chunk()
  end
  env.den = den
  return env
end

local function start(platform)
  reset_den(platform)
  local env = make_env(platform)
  local plugin = assert(loadfile(DIR .. "main.lua", "t", env))()
  plugin.open({})
  return plugin
end

local function find(pred)
  for _, el in ipairs(page and page.body or {}) do
    if pred(el) then return el end
  end
end
local function has_text(fragment)
  return find(function(el)
    for _, field in ipairs({ "text", "label", "value" }) do
      if type(el[field]) == "string" and el[field]:find(fragment, 1, true) then return true end
    end
  end) ~= nil
end
local function button(action)
  return find(function(el) return el.type == "button" and el.action == action end)
end
local function count(prefix)
  local n = 0
  for _, r in ipairs(st.requests) do if r:sub(1, #prefix) == prefix then n = n + 1 end end
  return n
end

-- 1. First open, nothing set up: folder choice and how to get Syncthing; no request made.
reset_syncthing()
local p = start("windows-x86_64")
check(page and page.title == "Syncthing", "page shown")
check(button("use_default") and has_text("Use Sync/EmuDEN"), "default folder offered")
check(has_text("your home folder"), "desktop default described as the home folder")
check(has_text("Syncthing, from syncthing.net") and has_text("Syncthing-Fork"), "where to get Syncthing")
check(#st.requests == 0, "no request without an API key")
check(not page.busy, "page not busy after open")

-- 2. The default folder goes through den.sync.use_folder.
p.actions.use_default()
check(use_folder_calls[1] == "~/Sync/EmuDEN", "use_folder gets ~/Sync/EmuDEN")
check(has_text("/home/u/Sync/EmuDEN"), "chosen folder shown")
check(storage.folder == nil, "the host keeps the folder, not the plugin")
check(has_text("5 minutes ago") and button("sync_now"), "EmuDEN's last sync and Sync now shown")
run_conflicts = 1
p.actions.sync_now()
check(sync_runs == 1 and toasts[#toasts] == "Syncing through the folder", "Sync now starts a run")
check(has_text("1 conflicts. Settings > Sync lists them."), "the run's conflicts shown after it")
run_conflicts = 0
picker = nil
p.actions.choose_folder()
check(#toasts == 1 and host_folder == "/home/u/Sync/EmuDEN", "closing the picker changes nothing")
picker = "/home/u/Elsewhere"

-- 3. A wrong key is refused and forgotten.
p.actions.set_key(nil, "  wrong ")
check(secrets.api_key == nil, "refused key removed from den.secrets")
check(has_text("refused the API key"), "refused key reported")
check(not has_text(ME), "no device id without a working key")

-- 4. The right key connects: device id, other devices, add button.
p.actions.set_key(nil, " " .. KEY .. "\n")
check(secrets.api_key == KEY, "key kept in den.secrets, trimmed")
check(storage.api_key == nil, "key not in den.storage")
check(has_text(ME), "this device's id shown")
check(find(function(el) return el.action == "toggle_device" and el.arg == LAPTOP end), "laptop listed")
check(find(function(el) return el.action == "toggle_device" and el.arg == RETROID
                                and el.label == "RETROID" end), "unnamed device shown by its id")
check(not find(function(el) return el.action == "toggle_device" and el.arg == ME end), "own device not listed")
check(has_text("Add the EmuDEN folder to Syncthing"), "add button")
check(not has_text("syncthing.net"), "get-Syncthing part hidden once connected")
check(count("GET http db/status") == 0, "expensive db/status never called")

-- 5. Share with the laptop and add the folder; the other folder is not touched.
p.actions.toggle_device(LAPTOP)
check(find(function(el) return el.arg == LAPTOP and el.value == "Shared" end), "laptop ticked")
local before_default = copy(st.folders[1])
p.actions.save_folder()
local added = find_folder("emuden")
check(added and added.label == "EmuDEN" and added.type == "sendreceive"
      and added.path == "/home/u/Sync/EmuDEN", "folder added with id, label, path, type")
check(added and added.rescanIntervalS == 3600, "new folder keeps Syncthing's defaults")
check(added and #added.devices == 2 and added.devices[1].deviceID == ME
      and added.devices[2].deviceID == LAPTOP, "shared with this device and the laptop")
check(count("PUT") == 0 and count("DELETE") == 0, "no PUT or DELETE")
local same = true
for k, v in pairs(before_default) do
  if type(v) ~= "table" and st.folders[1][k] ~= v then same = false end
end
check(same and #st.folders == 2, "other folders untouched")
check(toasts[#toasts]:find("in Syncthing now", 1, true), "added toast")
check(has_text("This device: 87 %, 3.0 MiB to get"), "local completion shown")
check(find(function(el) return el.label == "Laptop" and el.value == "100 %" end), "laptop completion")
check(has_text("Not yet"), "no file synced yet")

-- 6. Last sync from stats/folder; a new folder path and another device patch the folder.
st.stats = { emuden = { lastScan = "2026-11-15T10:20:00+01:00",
                        lastFile = { filename = "saves/gba/Metroid.srm", at = "2026-11-15T10:22:31.5+01:00" } } }
added.devices[2].introducedBy = RETROID
p.actions.refresh()
check(has_text("2026-11-15 10:22  saves/gba/Metroid.srm"), "last synced file shown")
check(has_text("2026-11-15 10:20"), "last scan shown")
p.actions.choose_folder()
check(use_folder_calls[2] == "<picker>", "choose opens the host's picker")
check(has_text("Save the changes in Syncthing"), "path change marks the folder as changed")
check(has_text("Update it to use /home/u/Elsewhere"), "path mismatch explained")
p.actions.toggle_device(RETROID)
local patches = count("PATCH")
p.actions.save_folder()
check(count("PATCH") == patches + 1 and count("POST") == 1, "existing folder patched, not re-added")
local patched = find_folder("emuden")
check(patched.path == "/home/u/Elsewhere", "path patched")
check(#patched.devices == 3 and patched.devices[2].introducedBy == RETROID, "device entries kept")
check(patched.rescanIntervalS == 3600, "other settings of the folder kept")
check(find(function(el) return el.label == "RETROID" and el.value == "not connected" end),
      "not connected device shown")

-- 7. Unticking removes the share; devices Syncthing does not list stay.
patched.devices[#patched.devices + 1] = { deviceID = "UNKNOWN-DEVICE", introducedBy = "" }
p.actions.refresh()
p.actions.toggle_device(LAPTOP)
p.actions.save_folder()
local ids = {}
for _, d in ipairs(find_folder("emuden").devices) do ids[d.deviceID] = true end
check(ids[ME] and ids[RETROID] and not ids[LAPTOP] and ids["UNKNOWN-DEVICE"], "unticked device unshared")

-- 8. A folder Syncthing already syncs at the chosen path is refused.
st.folders[1].path = "/home/u/Elsewhere/"
p.actions.save_folder()
check(toasts[#toasts]:find("Default Folder", 1, true), "path clash with another folder refused")
st.folders[1].path = "/home/u/Sync"

-- 9. Address: only loopback; a port change is used.
p.actions.set_address(nil, "192.168.1.5:8384")
check(toasts[#toasts]:find("Only Syncthing on this device", 1, true), "LAN address refused")
check(storage.address == nil, "refused address not stored")
st.port = "8385"
p.actions.set_address(nil, "http://localhost:8385/")
check(storage.address == "localhost:8385" and has_text(ME), "loopback address with port used")

-- 10. Syncthing not running: message, retry, get-Syncthing part; key kept.
st.up = false
p.actions.refresh()
check(has_text("does not answer at localhost:8385"), "not running reported")
check(button("refresh") and has_text("syncthing.net"), "retry and get-Syncthing shown")
check(secrets.api_key == KEY, "key kept while Syncthing is down")

-- 11. Android: shared storage default, Syncthing-Fork's key hint, TLS-only GUI reached over https.
reset_syncthing()
st.tls = true
st.folders[2] = { id = "emuden", label = "Old", path = "/storage/emulated/0/Sync/EmuDEN",
                  type = "sendonly", devices = { { deviceID = ME } } }
p = start("android-arm64")
check(has_text("shared storage"), "android default described as shared storage")
check(has_text("Syncthing options > API key"), "Syncthing-Fork key hint")
p.actions.use_default()
check(host_folder == "/storage/emulated/0/Sync/EmuDEN", "android default path")
p.actions.set_key(nil, KEY)
check(has_text(ME), "connected over https")
check(count("GET http ") == 1 and count("GET https system/status") == 1, "https remembered after the redirect")
check(has_text("Update the folder in Syncthing"), "existing folder found")
p.actions.save_folder()
local fixed = find_folder("emuden")
check(fixed.label == "EmuDEN" and fixed.type == "sendreceive", "existing folder set to label and type")

-- 12. Forget the key.
p.actions.disconnect()
check(secrets.api_key == nil and not has_text(ME), "key forgotten")

print(string.format("%d checks, %d failed", checks, failures))
if failures > 0 then error("tests failed", 0) end
