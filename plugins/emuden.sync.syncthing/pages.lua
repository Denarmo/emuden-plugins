-- The plugin's page, built from the state main.lua keeps.
local syncthing = den.include("syncthing.lua")

local M = {}

M.DEFAULT_FOLDER = "Sync/EmuDEN"

local function android()
  return tostring(den.device.platform):find("android", 1, true) ~= nil
end

local function size(bytes)
  if bytes >= 1024 * 1024 * 1024 then return string.format("%.1f GiB", bytes / 1073741824) end
  if bytes >= 1024 * 1024 then return string.format("%.1f MiB", bytes / 1048576) end
  if bytes >= 1024 then return string.format("%.0f KiB", bytes / 1024) end
  return string.format("%d bytes", bytes)
end

local function short_id(id)
  return id:match("^([^-]+)") or id
end

local function folder_part(state, body)
  body[#body + 1] = { type = "text", style = "heading", text = "Sync folder" }
  if state.folder then
    body[#body + 1] = { type = "row", id = "folder", label = "Folder", value = state.folder }
    body[#body + 1] = { type = "text", text = "EmuDEN keeps your synced files here. Any program " ..
                        "that copies this folder between your devices syncs EmuDEN; Syncthing " ..
                        "does it without a server." }
    body[#body + 1] = { type = "button", label = "Choose another folder", action = "choose_folder" }
  else
    local where = android() and den.tr("your device's shared storage") or den.tr("your home folder")
    body[#body + 1] = { type = "text", text = den.tr("Pick the folder EmuDEN syncs through. The " ..
                        "usual one is {} in {}.", M.DEFAULT_FOLDER, where) }
    body[#body + 1] = { type = "button", label = den.tr("Use {}", M.DEFAULT_FOLDER),
                        action = "use_default" }
    body[#body + 1] = { type = "button", label = "Choose a folder", action = "choose_folder" }
  end
end

local function ago(seconds)
  local d = den.now() - seconds
  if d < 90 then return "just now" end
  if d < 5400 then return den.tr("{} minutes ago", math.floor(d // 60)) end
  if d < 129600 then return den.tr("{} hours ago", math.floor(d // 3600)) end
  return den.tr("{} days ago", math.floor(d // 86400))
end

-- EmuDEN's own side: den.sync.status() (docs/sync.md section 5).
local function emuden_part(state, body)
  local status = state.sync
  if not state.folder or type(status) ~= "table" then return end
  if status.active == false then
    body[#body + 1] = { type = "text", style = "caption", text = "Syncthing is not the sync " ..
                        "provider on this device yet; choose it under Settings > Sync." }
    return
  end
  local last = tonumber(status.last_sync) or 0
  body[#body + 1] = { type = "row", id = "emuden-sync", label = "EmuDEN last synced the folder",
                      value = status.running and "Syncing now" or last > 0 and ago(last) or "Never" }
  if (tonumber(status.conflicts) or 0) > 0 then
    body[#body + 1] = { type = "text", style = "warning", text = den.tr(
                        "{} conflicts. Settings > Sync lists them.", math.floor(tonumber(status.conflicts))) }
  end
  if type(status.error) == "string" then
    body[#body + 1] = { type = "text", style = "warning", text = status.error }
  end
  body[#body + 1] = { type = "button", label = "Sync now", action = "sync_now" }
end

local function device_rows(state, body)
  local others = 0
  for _, device in ipairs(state.devices or {}) do
    if device.id ~= state.my_id then
      others = others + 1
      local name = device.name ~= "" and device.name or short_id(device.id)
      body[#body + 1] = { type = "row", id = "device-" .. device.id, label = name,
                          value = state.ticked[device.id] and "Shared" or "Not shared",
                          action = "toggle_device", arg = device.id }
    end
  end
  if others == 0 then
    body[#body + 1] = { type = "text", style = "caption", text = "Syncthing knows no other " ..
                        "device yet. Add your other devices in Syncthing (with this device's " ..
                        "id), then press Refresh." }
  end
end

local function remote_state(state)
  if state == "unknown" then return "not connected" end
  if state == "notSharing" then return "has not accepted the folder yet" end
  if state == "paused" then return "paused" end
end

local function status_rows(state, body)
  local local_done = state.completion
  if local_done then
    local percent = math.floor(local_done.percent)
    local label = local_done.need_bytes > 0
                  and den.tr("This device: {} %, {} to get", percent, size(local_done.need_bytes))
                  or den.tr("This device: {} %", percent)
    body[#body + 1] = { type = "progress", id = "completion", label = label,
                        fraction = local_done.percent / 100 }
  end
  for _, device in ipairs(state.devices or {}) do
    local done = state.remote and state.remote[device.id]
    if done then
      local name = device.name ~= "" and device.name or short_id(device.id)
      local why = remote_state(done.state)
      body[#body + 1] = { type = "row", id = "remote-" .. device.id, label = name,
                          value = why or string.format("%d %%", math.floor(done.percent)) }
    end
  end
  local last = state.last or {}
  body[#body + 1] = { type = "row", id = "last-sync", label = "Last file synced",
                      value = syncthing.when(last.at) and
                              (syncthing.when(last.at) .. (last.file ~= "" and ("  " .. last.file) or ""))
                              or "Not yet" }
  if syncthing.when(last.scan) then
    body[#body + 1] = { type = "row", id = "last-scan", label = "Folder last checked",
                        value = syncthing.when(last.scan) }
  end
end

local function connect_part(state, body)
  body[#body + 1] = { type = "text", style = "heading", text = "Connect to Syncthing on this device" }
  body[#body + 1] = { type = "text", text = "Optional. With Syncthing's API key EmuDEN adds the " ..
                      "folder to Syncthing for you and shows how far it has synced." }
  body[#body + 1] = { type = "input", id = "address", label = "Syncthing address",
                      value = state.address, action = "set_address" }
  body[#body + 1] = { type = "input", id = "api_key", secret = true, action = "set_key",
                      label = state.has_key and "API key (saved; enter a new one to replace it)"
                                             or "API key" }
  if android() then
    body[#body + 1] = { type = "text", style = "caption", text = "Syncthing-Fork shows the API " ..
                        "key under Settings > Syncthing options > API key; tap it to copy." }
  else
    body[#body + 1] = { type = "text", style = "caption", text = den.tr("In Syncthing's web page ({}): " ..
                        "Actions > Settings > General > API Key.", syncthing.DEFAULT_ADDRESS) }
  end
  if state.error then
    body[#body + 1] = { type = "text", style = "warning", id = "error", text = state.error }
  end
  if not state.connected then
    if state.has_key then
      body[#body + 1] = { type = "button", label = "Try again", action = "refresh" }
      body[#body + 1] = { type = "button", label = "Forget the API key", action = "disconnect" }
    end
    return
  end

  body[#body + 1] = { type = "row", id = "my-id", label = "This device's id", value = state.my_id }
  body[#body + 1] = { type = "text", style = "caption", text = "Enter this id in Syncthing on " ..
                      "your other devices to pair them with this one." }
  body[#body + 1] = { type = "text", style = "heading", text = "Share the folder with" }
  device_rows(state, body)
  if not state.folder then
    body[#body + 1] = { type = "text", style = "caption", text = "Pick the sync folder first." }
  else
    local in_syncthing = state.syncthing_folder
    local label = not in_syncthing and "Add the EmuDEN folder to Syncthing" or
                  state.dirty and "Save the changes in Syncthing" or "Update the folder in Syncthing"
    body[#body + 1] = { type = "button", id = "save_folder", label = label, action = "save_folder" }
    if in_syncthing and not syncthing.same_path(in_syncthing.path, state.folder) then
      body[#body + 1] = { type = "text", style = "warning", text = den.tr("Syncthing's EmuDEN folder " ..
                          "is {}. Update it to use {}.", tostring(in_syncthing.path), state.folder) }
    end
  end
  if state.syncthing_folder then
    body[#body + 1] = { type = "text", style = "heading", text = "Sync status" }
    status_rows(state, body)
  end
  body[#body + 1] = { type = "button", label = "Refresh", action = "refresh" }
  body[#body + 1] = { type = "button", label = "Forget the API key", action = "disconnect" }
end

local function get_syncthing_part(body)
  body[#body + 1] = { type = "text", style = "heading", text = "Getting Syncthing" }
  body[#body + 1] = { type = "text", text = "Syncthing is free and open source. EmuDEN does not " ..
                      "install it; get it from its makers:" }
  body[#body + 1] = { type = "row", label = "Windows, Linux, macOS",
                      value = "Syncthing, from syncthing.net (Downloads); on Linux also your " ..
                              "distribution's package or apt.syncthing.net" }
  body[#body + 1] = { type = "row", label = "Android",
                      value = "Syncthing-Fork, from F-Droid (com.github.catfriend1.syncthingfork) " ..
                              "or github.com/researchxxl/syncthing-android" }
  body[#body + 1] = { type = "text", style = "caption", text = "Without Syncthing the folder " ..
                      "still works: anything that copies it between devices will do." }
end

function M.home(state)
  local body = {}
  folder_part(state, body)
  emuden_part(state, body)
  connect_part(state, body)
  if not state.connected then get_syncthing_part(body) end
  return { title = "Syncthing", subtitle = "Sync saves, states, settings and games through a folder",
           busy = state.busy, body = body }
end

return M
