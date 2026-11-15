-- SPDX-FileCopyrightText: Copyright 2026 EmuDEN contributors
-- SPDX-License-Identifier: GPL-3.0-or-later

-- Sync with a RomM server (docs/sync.md section 7.2): saves and states go to the RomM saves
-- and states of the matching ROM; the server's ROMs can be downloaded into the library.
-- EmuDEN's sync engine decides what moves; this script only stores and fetches files.

-- One client for the page and the provider: den.include runs a script anew each time, and
-- RomM's refresh tokens are single use.
local provider = den.include("provider.lua")
local romm = provider.romm

local plugin = { actions = {}, provider = provider }

local SHOWN = 50
local message = nil          -- the last error or note, shown on the first page
local user_name = ""         -- typed on the page; the password is only held until sign-in
local password = nil
local platform_page = nil    -- { platform, roms, offset, total }

local SYSTEM_NAMES = {
  nes = "NES", snes = "Super Nintendo", gb = "Game Boy", gbc = "Game Boy Color",
  gba = "Game Boy Advance", n64 = "Nintendo 64", nds = "Nintendo DS", gamecube = "GameCube",
  wii = "Wii", genesis = "Mega Drive / Genesis", psx = "PlayStation", ps2 = "PlayStation 2",
  psp = "PSP", saturn = "Saturn", dreamcast = "Dreamcast", switch2 = "Nintendo Switch 2",
}

local function megabytes(bytes)
  bytes = bytes or 0
  if bytes < 1048576 then
    return string.format("%d KB", (bytes + 1023) // 1024)
  end
  if bytes < 1073741824 then
    return string.format("%.1f MB", bytes / 1048576)
  end
  return string.format("%.2f GB", bytes / 1073741824)
end

local function when(seconds)
  if type(seconds) ~= "number" or seconds <= 0 then
    return "Never"
  end
  local ago = den.now() - seconds
  if ago < 90 then
    return "Just now"
  elseif ago < 5400 then
    return string.format("%d minutes ago", ago // 60)
  elseif ago < 129600 then
    return string.format("%d hours ago", ago // 3600)
  end
  return string.format("%d days ago", ago // 86400)
end

-- "romm.local:8080" -> "http://romm.local:8080"; nil for what is no server address.
local function normalize(url)
  url = (url or ""):gsub("^%s+", ""):gsub("%s+$", ""):gsub("/+$", "")
  if url == "" then
    return nil
  end
  if not url:match("^https?://") then
    url = "http://" .. url
  end
  if not url:match("^https?://[%w%.%-]+:?%d*$") and not url:match("^https?://%[[%x:]+%]:?%d*$") then
    return nil
  end
  return url
end

-- den.sync.status() (docs/sync.md section 5).
local function sync_rows(body)
  local status = den.sync.status()
  if type(status) ~= "table" then
    return
  end
  if status.active == false then
    body[#body + 1] = { type = "text", style = "caption", text =
        "RomM is not the sync provider on this device; choose it under Settings > Sync." }
  end
  body[#body + 1] = { type = "row", label = "Last sync",
                      value = status.running and "Syncing now" or when(status.last_sync) }
  local current = status.current
  if type(current) == "table" and current.path then
    body[#body + 1] = { type = "progress", id = "current", label = tostring(current.path),
                        fraction = tonumber(current.fraction) or -1 }
  end
  local conflicts = tonumber(status.conflicts) or 0
  if conflicts > 0 then
    body[#body + 1] = { type = "text", style = "warning", text = string.format(
        "%d conflicts. Settings > Sync lists them.", conflicts) }
  end
  local errors = type(status.errors) == "table" and #status.errors or 0
  if errors > 0 then
    body[#body + 1] = { type = "text", style = "warning", text = string.format(
        "%d files could not be synced; they are tried again on the next sync. %s",
        errors, tostring(status.error or status.errors[1])) }
  end
end

local function home_page()
  local server = romm.server()
  local body = {}
  if message then
    body[#body + 1] = { type = "text", id = "message", style = "warning", text = message }
  end
  if not server then
    body[#body + 1] = { type = "text", style = "body", text =
        "Sync your saves and save states with your RomM server, and download its games " ..
        "into your library. Enter the server's address, as you open it in a browser." }
    body[#body + 1] = { type = "input", id = "server", label = "Server address",
                        value = "", action = "set_server" }
    body[#body + 1] = { type = "text", style = "caption", text =
        "For example http://192.168.1.20:8080. A server on your home network is usually " ..
        "plain http: what is sent to it is not encrypted. RomM " .. romm.TESTED ..
        " or newer." }
    return { title = "RomM", subtitle = "Not set up", body = body }
  end
  body[#body + 1] = { type = "row", label = "Server", value = server, action = "change_server" }
  if not romm.signed_in() then
    body[#body + 1] = { type = "text", style = "body", text =
        "Sign in with your RomM user. EmuDEN keeps a sign-in token, never your password." }
    body[#body + 1] = { type = "input", id = "user", label = "User name", value = user_name,
                        action = "set_user" }
    body[#body + 1] = { type = "input", id = "password", label = "Password", value = "",
                        action = "set_password", secret = true }
    body[#body + 1] = { type = "button", id = "sign_in", label = "Sign in", action = "sign_in" }
    return { title = "RomM", subtitle = "Not signed in", body = body }
  end
  local status = provider.status()
  body[#body + 1] = { type = "row", label = "Signed in as", value = status.user or "?" }
  if status.version then
    body[#body + 1] = { type = "row", label = "RomM version", value = status.version }
  end
  sync_rows(body)
  body[#body + 1] = { type = "button", id = "sync_now", label = "Sync now", action = "sync_now" }
  body[#body + 1] = { type = "button", id = "games", label = "Games on the server",
                      action = "games" }
  body[#body + 1] = { type = "text", style = "caption", text =
      "Saves and save states go to the RomM game of the same console and file name. " ..
      "Settings and BIOS files are not synced to RomM. Which of these sync is chosen in " ..
      "Settings > Sync." }
  body[#body + 1] = { type = "button", id = "sign_out", label = "Sign out", action = "sign_out" }
  return { title = "RomM", subtitle = status.user and (status.user .. " on " .. server) or server,
           body = body }
end

local function show_home()
  while den.ui.depth() > 1 do
    den.ui.pop()
  end
  den.ui.set(home_page())
end

local function show(page)
  if den.ui.depth() > 1 then
    den.ui.set(page)
  else
    den.ui.push(page)
  end
end

local function platforms_page(platforms)
  local body = {}
  for _, p in ipairs(platforms) do
    body[#body + 1] = { type = "row", label = p.name, value = string.format("%d games", p.rom_count),
                        action = "platform", arg = p.id }
  end
  if #body == 0 then
    body[1] = { type = "empty", title = "No games for EmuDEN's consoles",
                text = "The server has no platform EmuDEN can play." }
  end
  return { title = "Games on the server", subtitle = romm.server(), body = body }
end

local function roms_page()
  local p = platform_page
  local body = {}
  for i = 1, math.min(#p.roms, p.shown) do
    local rom = p.roms[i]
    local files = #rom.files > 1 and string.format(", %d files", #rom.files) or ""
    body[#body + 1] = { type = "row", id = "rom" .. rom.id, label = rom.name,
                        value = megabytes(rom.size) .. files, action = "download", arg = rom.id }
  end
  if p.shown < #p.roms then
    body[#body + 1] = { type = "button", id = "more", label = "Show more", action = "more" }
  end
  if #body == 0 then
    body[1] = { type = "empty", title = "No games", text = "RomM lists no games here." }
  end
  return { title = p.platform.name,
           subtitle = (SYSTEM_NAMES[p.platform.system] or p.platform.system) ..
               string.format(" - %d games", #p.roms),
           body = body }
end

function plugin.open()
  den.ui.set(home_page())
end

function plugin.resume()
  if den.ui.depth() == 1 then
    den.ui.set(home_page())
  end
end

function plugin.actions.set_server(_, text)
  local url = normalize(text)
  if not url then
    return den.ui.toast("Enter the server's address, like http://192.168.1.20:8080.")
  end
  den.ui.patch("server", { enabled = false })
  -- The host asks the user to confirm the host and grants it to this plugin; only then can
  -- the script reach it to read its version.
  local version, why = den.sync.set_server(url)
  if not version then
    why = why == "declined" and "The server was not confirmed." or why
  else
    version, why = romm.check_version(url)
  end
  if not version then
    message = why
    return den.ui.set(home_page())
  end
  if romm.server() ~= url then
    romm.sign_out()
    provider.forget()
  end
  den.storage.set("server", url)
  message = nil
  den.ui.set(home_page())
end

function plugin.actions.change_server()
  local yes = den.ui.confirm{ title = "Change server",
                              message = "Sign out of " .. romm.server() .. " and enter another server?",
                              yes = "Change" }
  if yes then
    romm.sign_out()
    provider.forget()
    den.storage.remove("server")
    message = nil
    den.ui.set(home_page())
  end
end

function plugin.actions.set_user(_, text)
  user_name = text or ""
end

function plugin.actions.set_password(_, text)
  password = text
end

function plugin.actions.sign_in()
  if user_name == "" or not password or password == "" then
    return den.ui.toast("Enter your RomM user name and password.")
  end
  den.ui.patch("sign_in", { enabled = false, label = "Signing in..." })
  local secret = password
  password = nil
  local ok, why = romm.sign_in(user_name, secret)
  secret = nil
  message = not ok and why or nil
  if ok then
    provider.forget()
    den.ui.toast("Signed in. Your saves sync with RomM from now on.")
  end
  den.ui.set(home_page())
end

function plugin.actions.sign_out()
  local yes = den.ui.confirm{ title = "Sign out", message =
      "EmuDEN stops syncing with RomM on this device. Your files stay on both sides.",
      yes = "Sign out" }
  if yes then
    romm.sign_out()
    provider.forget()
    den.ui.set(home_page())
  end
end

function plugin.actions.sync_now()
  den.sync.now()
  den.ui.toast("Syncing with RomM")
  den.ui.set(home_page())
end

function plugin.actions.games()
  show({ title = "Games on the server", body = { { type = "progress", id = "loading",
         label = "Asking RomM", fraction = -1 } }, busy = true })
  local platforms, why = romm.platforms()
  if not platforms then
    den.ui.toast(why)
    return show_home()
  end
  den.ui.set(platforms_page(platforms))
end

function plugin.actions.platform(id)
  local platforms, why = romm.platforms()
  local platform
  for _, p in ipairs(platforms or {}) do
    if p.id == id then
      platform = p
    end
  end
  if not platform then
    return den.ui.toast(why or "RomM no longer lists this platform.")
  end
  den.ui.push({ title = platform.name, body = { { type = "progress", id = "loading",
                label = "Asking RomM", fraction = -1 } }, busy = true })
  local roms
  roms, why = romm.all_roms(platform.id)
  if not roms then
    den.ui.pop()
    return den.ui.toast(why)
  end
  platform_page = { platform = platform, roms = roms, shown = SHOWN }
  den.ui.set(roms_page())
end

function plugin.actions.more()
  if platform_page then
    platform_page.shown = platform_page.shown + SHOWN
    den.ui.set(roms_page())
  end
end

-- Hands the game's files to the host (den.sync.download_game), which fetches them with
-- provider.get into the device's games folder and adds the game to the library.
function plugin.actions.download(id)
  local rom
  for _, r in ipairs(platform_page and platform_page.roms or {}) do
    if r.id == id then
      rom = r
    end
  end
  if not rom then
    return
  end
  local paths = {}
  for _, f in ipairs(rom.files) do
    paths[#paths + 1] = "games/" .. platform_page.platform.system .. "/" .. f.name
  end
  -- download_game waits until every file is in; the row says so meanwhile.
  den.ui.patch("rom" .. rom.id, { value = "Downloading...", enabled = false })
  den.ui.toast("Downloading " .. rom.name)
  local ok, why = den.sync.download_game(paths)
  den.ui.toast(ok and (rom.name .. " is in your library.")
               or ("The download of " .. rom.name .. " failed: " .. tostring(why)))
  if platform_page and den.ui.depth() > 1 then
    den.ui.set(roms_page())
  end
end

return plugin
