-- SPDX-FileCopyrightText: Copyright 2026 J. Doe
-- SPDX-License-Identifier: MIT

-- A template sync provider for a WebDAV server the user enters. EmuDEN's sync engine decides
-- what moves and calls plugin.provider; this page only sets the server up.

local dav = den.include("webdav.lua")

local plugin = { actions = {}, provider = dav.provider }
local message = nil -- the last result or problem, shown at the top

local function when(seconds)
  if type(seconds) ~= "number" or seconds <= 0 then return "Never" end
  local ago = den.now() - seconds
  if ago < 90 then return "Just now" end
  if ago < 5400 then return string.format("%d minutes ago", ago // 60) end
  if ago < 129600 then return string.format("%d hours ago", ago // 3600) end
  return string.format("%d days ago", ago // 86400)
end

local function home_page()
  local body = {}
  if message then
    body[#body + 1] = { type = "text", id = "message", style = "warning", text = message }
  end
  body[#body + 1] = { type = "text", style = "body", text =
      "Keeps your saves, save states and settings in a folder of a WebDAV server: Nextcloud, " ..
      "ownCloud, a NAS or any other. Make the folder on the server first, then enter its " ..
      "address as your server shows it." }
  body[#body + 1] = { type = "input", id = "server", label = "Folder address", value = dav.base() or "",
                      action = "set_server" }
  body[#body + 1] = { type = "input", id = "user", label = "User name", value = den.storage.get("user") or "",
                      action = "set_user" }
  body[#body + 1] = { type = "input", id = "password", label = "Password",
                      value = den.secrets.get("password") and "********" or "", action = "set_password", secret = true }
  body[#body + 1] = { type = "text", style = "caption", text =
      "The password is kept in this device's credential store and never synced. On a plain " ..
      "http address it is sent unencrypted; use https outside your home network." }
  if dav.base() then
    body[#body + 1] = { type = "button", id = "check", label = "Check the connection", action = "check" }
    local status = den.sync.status()
    if type(status) == "table" then
      if status.active == false then
        body[#body + 1] = { type = "text", style = "caption", text =
            "WebDAV is not the sync provider on this device; choose it under Settings > Sync." }
      end
      body[#body + 1] = { type = "row", label = "Last sync",
                          value = status.running and "Syncing now" or when(status.last_sync) }
      if status.error then
        body[#body + 1] = { type = "text", style = "warning", text = tostring(status.error) }
      end
    end
    body[#body + 1] = { type = "button", id = "sync_now", label = "Sync now", action = "sync_now" }
    body[#body + 1] = { type = "button", id = "forget", label = "Forget this server", action = "forget" }
  end
  return { title = "WebDAV", subtitle = dav.base() or "Not set up", body = body }
end

local function show(text)
  message = text
  den.ui.set(home_page())
end

function plugin.open()
  den.ui.set(home_page())
end

function plugin.resume()
  den.ui.set(home_page())
end

-- The user confirms the server once (den.sync.set_server); only its scheme, host and port
-- count for the permission, the folder's path is kept here.
function plugin.actions.set_server(_, value)
  local url = dav.normalize(value)
  if not url then return show("That is not a server address.") end
  local ok, why = den.sync.set_server(url)
  if not ok then
    return show(why == "declined" and "The server was not confirmed." or tostring(why))
  end
  den.storage.set("base", url)
  show(nil)
end

function plugin.actions.set_user(_, value)
  value = tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if value == "" then den.storage.remove("user") else den.storage.set("user", value) end
  show(nil)
end

function plugin.actions.set_password(_, value)
  if value == "********" then return end
  if value == nil or value == "" then
    den.secrets.remove("password")
    return show(nil)
  end
  local ok, why = den.secrets.set("password", value)
  show(not ok and tostring(why) or nil)
end

function plugin.actions.check()
  local result, why = dav.check()
  show(result or why)
end

function plugin.actions.sync_now()
  local ok, why = den.sync.now()
  show(ok and "Syncing." or tostring(why))
end

function plugin.actions.forget()
  if not den.ui.confirm{ title = "Forget this server?", message =
      "The files stay on the server. EmuDEN stops syncing with it until you enter it again.",
      yes = "Forget" } then
    return
  end
  den.storage.remove("base")
  den.storage.remove("user")
  den.secrets.remove("password")
  show(nil)
end

return plugin
