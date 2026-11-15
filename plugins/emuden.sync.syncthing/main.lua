-- Syncthing: EmuDEN syncs through a plain folder (the host's folder store) that Syncthing
-- replicates between the user's devices. The REST part only sets Syncthing up.
local syncthing = den.include("syncthing.lua")
local pages = den.include("pages.lua")

local KEY = "api_key"

local plugin = { actions = {} }
local state = { ticked = {} }

local function render()
  den.ui.set(pages.home(state))
end

local function busy(on)
  state.busy = on or nil
  render()
end

local function load()
  state.folder = den.sync.folder()
  state.sync = den.sync.status()
  state.address = den.storage.get("address") or syncthing.DEFAULT_ADDRESS
  state.has_key = den.secrets.get(KEY) ~= nil
end

local function disconnected(message)
  state.connected, state.error = false, message
  state.my_id, state.devices, state.syncthing_folder = nil, nil, nil
  state.completion, state.remote, state.last = nil, nil, nil
end

local client
local function connection()
  local key = den.secrets.get(KEY)
  if not key then return nil end
  if not client or client.key ~= key or client.address ~= state.address then
    client = syncthing.new(state.address, key, den.http.request, den.json)
  end
  return client
end

-- Asks Syncthing for everything the page shows: a handful of requests, only when the page
-- opens, comes back to the front or the user presses something.
local function refresh()
  local api = connection()
  state.has_key = api ~= nil
  if not api then return disconnected(nil) end
  local system, err, status = api:system()
  if not system then
    if status == 401 or status == 403 then
      den.secrets.remove(KEY)
      state.has_key, client = false, nil
      err = err .. " Copy the key again from Syncthing's settings."
    end
    return disconnected(err)
  end
  state.connected, state.error, state.my_id = true, nil, system.id
  state.devices, err = api:devices()
  if not state.devices then return disconnected(err) end
  local folder
  folder, err = api:folder()
  if folder == nil then return disconnected(err) end
  state.syncthing_folder = folder or nil
  if not state.dirty then
    state.ticked = {}
    for _, entry in ipairs(folder and folder.devices or {}) do
      if entry.deviceID ~= system.id then state.ticked[entry.deviceID] = true end
    end
  end
  state.completion, state.remote, state.last = nil, {}, nil
  if folder then
    state.completion = api:completion()
    for _, entry in ipairs(folder.devices or {}) do
      if entry.deviceID ~= system.id then
        state.remote[entry.deviceID] = api:completion(entry.deviceID)
      end
    end
    state.last = api:last_sync()
  end
end

-- The host keeps the folder (den.sync.folder); the user may decline it or close the picker.
local function pick(path)
  busy(true)
  local chosen, err = den.sync.use_folder(path)
  if chosen then
    if chosen ~= state.folder and state.syncthing_folder then state.dirty = true end
    state.folder = chosen
    state.sync = den.sync.status()
  elseif err and err ~= "declined" and err ~= "no folder was chosen" then
    den.ui.toast(err)
  end
  busy(false)
end

function plugin.open()
  load()
  busy(true)
  refresh()
  busy(false)
end

function plugin.resume()
  state.sync = den.sync.status()
  if state.connected then refresh() end
  render()
end

-- Starts a run and shows its outcome (conflicts, errors) once the run is over.
function plugin.actions.sync_now()
  local ok, err = den.sync.now()
  den.ui.toast(ok and "Syncing through the folder" or err)
  for _ = 1, ok and 120 or 0 do
    den.sleep(500)
    state.sync = den.sync.status()
    if not state.sync.running then break end
  end
  state.sync = den.sync.status()
  render()
end

function plugin.actions.use_default()
  pick("~/" .. pages.DEFAULT_FOLDER)
end

function plugin.actions.choose_folder()
  pick(nil)
end

function plugin.actions.set_address(_, value)
  local address, err = syncthing.check_address(value)
  if not address then
    den.ui.toast(err)
    return render()
  end
  state.address = address
  den.storage.set("address", address)
  busy(true)
  refresh()
  busy(false)
end

function plugin.actions.set_key(_, value)
  local key = tostring(value or ""):gsub("%s+", "")
  if key == "" then return end
  den.secrets.set(KEY, key)
  busy(true)
  refresh()
  busy(false)
  if state.connected then den.ui.toast("Connected to Syncthing.") end
end

function plugin.actions.refresh()
  busy(true)
  refresh()
  busy(false)
end

function plugin.actions.disconnect()
  den.secrets.remove(KEY)
  client, state.has_key, state.dirty, state.ticked = nil, false, nil, {}
  disconnected(nil)
  render()
end

function plugin.actions.toggle_device(id)
  if not state.connected or type(id) ~= "string" then return end
  state.ticked[id] = not state.ticked[id] or nil
  state.dirty = true
  render()
end

function plugin.actions.save_folder()
  local api = connection()
  if not api or not state.connected or not state.folder then return end
  busy(true)
  local done, err = api:save_folder(state.folder, state.my_id, state.ticked, state.devices)
  if done then
    state.dirty = nil
    den.ui.toast(done == "added" and "The EmuDEN folder is in Syncthing now." or
                 "Syncthing's EmuDEN folder is updated.")
  else
    den.ui.toast(err)
  end
  refresh()
  busy(false)
end

return plugin
