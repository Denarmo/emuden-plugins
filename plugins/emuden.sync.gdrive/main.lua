-- SPDX-FileCopyrightText: Copyright 2026 EmuDEN contributors
-- SPDX-License-Identifier: GPL-3.0-or-later

-- Sync provider: Google Drive (docs/sync.md section 7.1 in the EmuDEN repository).
-- EmuDEN's sync engine decides what moves; this plugin only stores and fetches files in the
-- EmuDEN folder of the user's Drive, and shows the sign-in and status page.

local util = den.include("util.lua")
local auth = den.include("auth.lua")
local drive = den.include("drive.lua")(auth)

local plugin = { actions = {} }

local signing = nil     -- the device code being entered: { user_code, verification_url, ... }
local attempt = 0       -- moves on every sign-in start and cancel; an older wait stops
local account = nil     -- drive.status() of the last check
local problem = nil     -- the last error to show on the page

local CATEGORY_LABEL = { saves = "Saves", states = "Save states", config = "Settings",
                         games = "Games", bios = "BIOS" }

-- The entry points the sync engine calls (docs/sync.md section 5). Nothing goes out unless
-- the plugin is set up and signed in.
local function ready()
  if not auth.configured() then return nil, "Sync with Google Drive is not set up yet." end
  if not auth.signed_in() then return nil, "Not signed in to Google Drive." end
  return true
end

local function guarded(fn)
  return function(...)
    local ok, why = ready()
    if not ok then return nil, why end
    return fn(...)
  end
end

plugin.provider = {
  list = guarded(drive.list),
  get = guarded(function(path, local_path, progress)
    local refused = util.refused(path)
    if refused then return nil, refused end
    return drive.get(path, local_path, progress)
  end),
  put = guarded(drive.put),
  delete = guarded(function(path)
    local refused = util.refused(path)
    if refused then return nil, refused end
    return drive.delete(path)
  end),
  status = guarded(drive.status),
}

-- Page ----------------------------------------------------------------------------------------

local function ago(seconds)
  local d = den.now() - seconds
  if d < 60 then return "just now" end
  if d < 3600 then return string.format("%d min ago", d // 60) end
  if d < 86400 then return string.format("%d h ago", d // 3600) end
  return string.format("%d days ago", d // 86400)
end

-- den.sync.status() (docs/sync.md section 5).
local function sync_rows(body)
  local status = den.sync.status()
  if type(status) ~= "table" then return end
  if status.active == false then
    body[#body + 1] = { type = "text", style = "caption", text = "Google Drive is not the "
        .. "sync provider on this device; choose it under Settings > Sync." }
  end
  local last = tonumber(status.last_sync) or 0
  body[#body + 1] = { type = "row", label = "Last sync",
                      value = status.running and "Syncing now" or last > 0 and ago(last) or "Never" }
  local up, down = tonumber(status.uploaded) or 0, tonumber(status.downloaded) or 0
  if up > 0 or down > 0 then
    body[#body + 1] = { type = "row", label = "Files", value = string.format("%d up, %d down", up, down) }
  end
  local conflicts = tonumber(status.conflicts) or 0
  if conflicts > 0 then
    body[#body + 1] = { type = "row", label = "Conflicts",
                        value = string.format("%d (Settings > Sync lists them)", conflicts) }
  end
  if (tonumber(status.waiting) or 0) > 0 then
    body[#body + 1] = { type = "row", label = "Waiting for a game to end",
                        value = tostring(status.waiting) }
  end
  if type(status.error) == "string" then
    local more = type(status.errors) == "table" and #status.errors > 1
                 and string.format(" (and %d more)", #status.errors - 1) or ""
    body[#body + 1] = { type = "text", style = "warning", text = status.error .. more }
  end
  local current = status.current
  if type(current) == "table" and current.path then
    body[#body + 1] = { type = "progress", id = "current", label = current.path,
                        fraction = tonumber(current.fraction) or -1 }
  end
end

local function categories_row(body)
  local enabled = den.sync.enabled_categories()
  if type(enabled) ~= "table" then return end
  local names = {}
  for _, id in ipairs(enabled) do names[#names + 1] = CATEGORY_LABEL[id] or id end
  body[#body + 1] = { type = "row", label = "What syncs",
                      value = #names > 0 and table.concat(names, ", ") or "Nothing yet" }
end

local function not_set_up_page()
  return { title = "Google Drive", body = {
    { type = "empty", title = "Sync is not set up",
      text = "Sync with Google Drive is not set up yet in this version of EmuDEN. "
          .. "Use another sync provider for now." } } }
end

local function signed_out_page()
  local body = {
    { type = "text", text = "Keep your saves, save states and settings in a folder named "
        .. "EmuDEN in your Google Drive, and get them on your other devices." },
    { type = "text", style = "caption", text = "EmuDEN only sees the files it created there. "
        .. "Steam and PC games are never sent to Google Drive." },
  }
  if problem then body[#body + 1] = { type = "text", style = "warning", text = problem } end
  body[#body + 1] = { type = "button", id = "sign_in", label = "Sign in with Google",
                      action = "sign_in" }
  return { title = "Google Drive", body = body }
end

local function signing_page()
  local url = signing.verification_url:gsub("^https?://", ""):gsub("^www%.", "")
  local minutes = math.max(1, (signing.expires_at - den.now()) // 60)
  return { title = "Sign in with Google", body = {
    { type = "text", text = "On your phone or computer, go to" },
    { type = "text", style = "heading", text = url },
    { type = "text", text = "and enter this code:" },
    { type = "text", id = "code", style = "heading", text = signing.user_code },
    { type = "progress", id = "wait", label = "Waiting for Google", fraction = -1 },
    { type = "text", style = "caption",
      text = string.format("The code works for %d more minutes.", minutes) },
    { type = "button", id = "cancel", label = "Cancel", action = "cancel" },
  } }
end

local function signed_in_page()
  local body = {}
  if account then
    body[#body + 1] = { type = "row", label = "Signed in as",
                        value = account.account or account.name or "Google account" }
    if account.used then
      body[#body + 1] = { type = "row", label = "Storage", value = account.total
          and (util.bytes(account.used) .. " of " .. util.bytes(account.total) .. " used")
          or (util.bytes(account.used) .. " used") }
    end
  end
  categories_row(body)
  sync_rows(body)
  if problem then body[#body + 1] = { type = "text", style = "warning", text = problem } end
  body[#body + 1] = { type = "button", id = "sync_now", label = "Sync now", action = "sync_now" }
  body[#body + 1] = { type = "button", id = "refresh", label = "Refresh", action = "refresh" }
  body[#body + 1] = { type = "button", id = "sign_out", label = "Sign out", action = "sign_out" }
  body[#body + 1] = { type = "text", style = "caption", text = "Files are in the EmuDEN folder "
      .. "of your Google Drive. Steam and PC games are never sent there." }
  return { title = "Google Drive", subtitle = account and account.name or nil, body = body }
end

local function page()
  if not auth.configured() then return not_set_up_page() end
  if signing then return signing_page() end
  if not auth.signed_in() then return signed_out_page() end
  return signed_in_page()
end

local function show()
  den.ui.set(page())
end

local function check_account()
  if not auth.configured() or not auth.signed_in() then return end
  local status, err = drive.status()
  if status then
    account, problem = status, nil
  else
    problem = err
  end
end

function plugin.open()
  show()
  if auth.configured() and auth.signed_in() and not signing then
    local p = page()
    p.busy = true
    den.ui.set(p)
    check_account()
    show()
  end
end

function plugin.resume()
  if not signing then show() end
end

function plugin.actions.sign_in()
  if not auth.configured() or signing then return end
  attempt = attempt + 1
  local mine = attempt
  problem = nil
  local device, err = auth.start()
  if not device then
    problem = err
    return show()
  end
  signing = device
  show()
  local ok, why = auth.wait(device, function() return attempt == mine end)
  if attempt ~= mine then return end
  signing = nil
  if ok then
    drive.forget()
    check_account()
    den.ui.toast("Signed in to Google Drive")
    den.sync.now()
  elseif why == "denied" then
    problem = "The sign-in was refused on Google's page."
  elseif why == "expired" then
    problem = "The code ran out. Sign in again for a new one."
  elseif why ~= "cancelled" then
    problem = why
  end
  show()
end

function plugin.actions.cancel()
  attempt = attempt + 1
  signing = nil
  show()
end

function plugin.actions.sync_now()
  if not auth.signed_in() then return show() end
  local ok, err = den.sync.now()
  if ok == nil and err then
    den.ui.toast(err)
  else
    den.ui.toast("Syncing with Google Drive")
  end
  show()
end

function plugin.actions.refresh()
  check_account()
  show()
end

function plugin.actions.sign_out()
  local yes = den.ui.confirm{ title = "Sign out of Google Drive?",
    message = "Sync with Google Drive stops on this device. The files stay in your Drive.",
    yes = "Sign out" }
  if not yes then return end
  auth.sign_out()
  drive.forget()
  account, problem = nil, nil
  show()
end

return plugin
