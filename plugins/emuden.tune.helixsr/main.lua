-- SPDX-FileCopyrightText: Copyright 2026 EmuDEN contributors
-- SPDX-License-Identifier: GPL-3.0-or-later

-- Helix SR's "FSR drop-in": a Steam game that ships AMD's FSR 3.1 upscaler library gets it
-- replaced by Helix SR's prebuilt HLX FSR 4 library. Helix SR is closed freeware that may only
-- be passed on unmodified, so it is downloaded from its official release (release.lua) and
-- never part of this package. EmuDEN copies the file after the user agreed, keeps the game's
-- own library and puts it back on Remove (den.mods).

local release = den.include("release.lua")

-- `release` is here for the tests, which shrink its sizes.
local plugin = { actions = {}, release = release }

local COVER = "https://shared.steamstatic.com/store_item_assets/steam/apps/%s/library_600x900.jpg"
local FSR = "amd_fidelityfx_upscaler_dx12.dll"
local FSR_OLD = "amd_fidelityfx_dx12.dll" -- FSR 3.0, one library: not enough for the drop-in

-- den.mods.find takes 16 names, each with one `*`.
local GUARDS = {
  { "easyanticheat*", "Easy Anti-Cheat" }, { "start_protected_game.exe", "Easy Anti-Cheat" },
  { "*_eac.exe", "Easy Anti-Cheat" },
  { "battleye*", "BattlEye" }, { "beservice*", "BattlEye" }, { "beclient*", "BattlEye" }, { "*_be.exe", "BattlEye" },
  { "equ8*", "EQU8" }, { "faceit*", "FACEIT" },
  { "vanguard*", "Vanguard" }, { "vgk.sys", "Vanguard" },
  { "eaanticheat*", "EA anticheat" }, { "javelin*", "EA Javelin" },
  { "gameguard.des", "nProtect GameGuard" }, { "xigncode*", "XIGNCODE3" }, { "anticheatexpert*", "Anti-Cheat Expert" },
}

local steam = nil
local filter = ""
local game = nil -- { appid, name, targets, old, guard, guard_file, state, changed, error }
local working = false

local function base_name(path) return (path:match("[^/]+$") or path):lower() end

local function matches(pattern, name)
  local before, after = pattern:match("^(.-)%*(.*)$")
  if not before then return name == pattern end
  return #name >= #before + #after and name:sub(1, #before) == before and name:sub(#name - #after + 1) == after
end

-- nil, or the record with `changed` set when a file is no longer the one EmuDEN wrote.
local function mod_state(appid)
  local state = den.mods.state(appid)
  if not state then return nil end
  state.changed = false
  for _, file in ipairs(state.files or {}) do
    if not file.intact then state.changed = true end
  end
  return state
end

local function applied() return den.storage.get("applied") or {} end
local function remember(appid, on)
  local list, found = {}, false
  for _, id in ipairs(applied()) do
    if id == appid then found = true end
    if id ~= appid or on then list[#list + 1] = id end
  end
  if on and not found then list[#list + 1] = appid end
  den.storage.set("applied", list)
end

local function inspect(appid)
  local out = { targets = {}, old = false }
  local found, why = den.mods.find{ appid = appid, names = { FSR, FSR_OLD } }
  if not found then return nil, why end
  for _, file in ipairs(found) do
    local name = base_name(file.path)
    if name == FSR then out.targets[#out.targets + 1] = file.path end
    if name == FSR_OLD then out.old = true end
  end
  local names = {}
  for i, guard in ipairs(GUARDS) do names[i] = guard[1] end
  local guards, guard_why = den.mods.find{ appid = appid, names = names }
  if not guards then return nil, guard_why end
  for _, file in ipairs(guards) do
    for _, guard in ipairs(GUARDS) do
      if not out.guard and matches(guard[1], base_name(file.path)) then
        out.guard, out.guard_file = guard[2], file.path
      end
    end
  end
  return out
end

local function home_page()
  local body = {}
  if not steam.installed then
    body[#body + 1] = { type = "empty", title = "No Steam here", text = steam.note }
    return { title = "Helix SR", body = body }
  end
  local states = {}
  for _, appid in ipairs(applied()) do
    local state = mod_state(appid)
    if state then
      states[appid] = state.changed and "Changed by a game update" or "Installed"
    else
      remember(appid, false)
    end
  end
  local shown = 0
  for _, app in ipairs(steam.apps) do
    if not app.shortcut and (filter == "" or app.name:lower():find(filter:lower(), 1, true)) then
      body[#body + 1] = { type = "row", id = "app-" .. app.appid, label = app.name, value = states[app.appid] or "Check",
                          action = "game", arg = app.appid }
      shown = shown + 1
    end
  end
  if shown == 0 then
    body[#body + 1] = { type = "empty", title = "No Steam games", text = "Install a game in Steam, then open this page again." }
  end
  body[#body + 1] = { type = "text", style = "caption", text =
      "Helix SR " .. release.version .. " by lonewolf0622, freeware. It is downloaded from github.com/lonewolf0622/HelixSR when you install it in a game; nothing of it is part of this plugin." }
  return { title = "Helix SR", subtitle = "FSR 4 upscaling for games with FSR 3.1",
           search = { placeholder = "Find a game", value = filter, action = "search" }, body = body }
end

local function game_page(progress)
  local facts, lines, buttons, body = {}, {}, {}, {}
  local state = game.state
  local can_install = false
  if game.error then
    lines[1] = "The game's folder could not be read: " .. game.error
  else
    facts[#facts + 1] = { label = "FSR 3.1 library", value = #game.targets > 0 and table.concat(game.targets, ", ") or "Not found" }
    facts[#facts + 1] = { label = "Anti-cheat", value = game.guard and (game.guard .. " (" .. game.guard_file .. ")") or "None found" }
    facts[#facts + 1] = { label = "Helix SR", value = state and (state.changed and "Changed by a game update" or "Installed") or "Not installed" }
    if game.guard then
      lines[#lines + 1] = "This game ships " .. game.guard .. ". A changed library in a protected game can get an account banned, so Helix SR is not installed here."
    elseif state and not state.changed then
      lines[#lines + 1] = "HLX FSR 4 is in place of the game's FSR library. Pick AMD FSR in the game's graphics settings to use it."
    elseif state then
      lines[#lines + 1] = "A game update put the game's own library back. Install again to use Helix SR, or Remove to forget it."
      can_install = #game.targets > 0
    elseif #game.targets > 0 then
      lines[#lines + 1] = "This game has FSR 3.1. Install replaces " .. FSR .. " with HLX FSR 4; the game's own file is kept and Remove puts it back."
      can_install = true
    elseif game.old then
      lines[#lines + 1] = "This game has FSR 3 as one library (" .. FSR_OLD .. "). The drop-in needs " .. FSR .. ", which games have from FSR 3.1 on."
    else
      lines[#lines + 1] = "No FSR 3.1 library (" .. FSR .. ") was found in this game's folder. The drop-in works only in Direct3D 12 games that ship it."
    end
  end
  if can_install and not progress then
    buttons[#buttons + 1] = { label = state and "Install again" or "Install", action = "install" }
  end
  if state and not progress then
    buttons[#buttons + 1] = { label = "Remove", action = "remove" }
  end
  body[#body + 1] = { type = "detail", id = "game", title = game.name, subtitle = "Helix SR " .. release.version .. ", FSR drop-in",
                      image = string.format(COVER, game.appid), aspect = 0.667,
                      facts = facts, text = table.concat(lines, "\n"), buttons = buttons }
  if progress then
    body[#body + 1] = { type = "progress", id = "progress", label = progress, fraction = -1 }
  end
  if can_install then
    body[#body + 1] = { type = "text", style = "warning", text =
        "Use it in single-player games. An online game may treat a changed library as cheating, also where no anti-cheat file was found." }
  end
  body[#body + 1] = { type = "text", style = "caption", text =
      "A game update or Steam's \"Verify integrity of game files\" brings the game's own library back; this page then offers to install again." }
  return { title = game.name, body = body }
end

local function load_game(appid, name)
  game = { appid = appid, name = name, targets = {}, old = false }
  local found, why = inspect(appid)
  if found then
    game.targets, game.old, game.guard, game.guard_file = found.targets, found.old, found.guard, found.guard_file
  else
    game.error = why or "unknown"
  end
  game.state = mod_state(appid)
end

-- The HLX FSR 4 library in the plugin's cache, downloaded and unpacked when it is not there.
local function library()
  local kept = den.storage.get("library")
  if kept and kept.version == release.version and den.files.exists(kept.path)
      and den.files.size(kept.path) == release.library_size then
    return kept.path
  end
  local megabytes = math.floor(release.size / 1048576 + 0.5)
  if not den.ui.confirm{ title = "Download Helix SR " .. release.version .. "?",
                         message = string.format("%d MB from github.com/lonewolf0622/HelixSR, the project's own release. It is checked against its published SHA-256 and kept for your other games.", megabytes),
                         yes = "Download" } then
    return nil
  end
  den.ui.set(game_page("Downloading Helix SR " .. release.version))
  local zip, why = den.download{ url = release.url, name = release.name, sha256 = release.sha256,
                                 on_progress = function(fraction) den.ui.patch("progress", { fraction = fraction }) end }
  if not zip then return nil, "Helix SR could not be downloaded: " .. tostring(why) end
  if den.files.size(zip) ~= release.size then
    den.files.remove(zip)
    return nil, "The download is not the Helix SR " .. release.version .. " this plugin knows (another size). Nothing was installed."
  end
  den.ui.patch("progress", { label = "Unpacking HLX FSR 4", fraction = -1 })
  local unpacked, unpack_why = den.mods.unpack{ file = zip, entries = { release.library } }
  den.files.remove(zip)
  local path = unpacked and unpacked[release.library]
  if not path then return nil, "Helix SR could not be unpacked: " .. tostring(unpack_why) end
  if den.files.size(path) ~= release.library_size then
    return nil, "The unpacked library is not the one this plugin knows (another size). Nothing was installed."
  end
  den.storage.set("library", { version = release.version, path = path })
  return path
end

function plugin.open()
  den.ui.set{ title = "Helix SR", busy = true, body = {} }
  steam = den.steam.status() or { installed = false, apps = {}, note = "" }
  den.ui.set(home_page())
end

function plugin.resume()
  if steam and den.ui.depth() == 1 then den.ui.set(home_page()) end
end

function plugin.actions.search(_, value)
  filter = value or ""
  den.ui.set(home_page())
end

function plugin.actions.game(appid)
  local name = appid
  for _, app in ipairs(steam.apps) do
    if app.appid == appid then name = app.name end
  end
  if den.ui.depth() > 1 then den.ui.pop() end
  den.ui.push{ title = name, busy = true, body = { { type = "progress", label = "Looking at the game's files", fraction = -1 } } }
  load_game(appid, name)
  den.ui.set(game_page())
end

local function install()
  -- The files may have changed since the page was drawn.
  load_game(game.appid, game.name)
  local allowed = not game.error and not game.guard and #game.targets > 0 and (not game.state or game.state.changed)
  local path, why
  if allowed then path, why = library() end
  if path then
    local files = {}
    -- The game's own library stays beside it under the name HLX FSR 4 falls back to.
    for i, target in ipairs(game.targets) do
      files[i] = { from = path, to = target, keep_as = "amd_fidelityfx_upscaler_dx12.amd.dll" }
    end
    den.ui.set(game_page("Waiting for your answer"))
    local ok, apply_why = den.mods.apply{ appid = game.appid, name = "Helix SR " .. release.version .. " (HLX FSR 4)", files = files }
    if ok then
      remember(game.appid, true)
      den.ui.toast("Installed. Pick AMD FSR in the game's graphics settings.")
    elseif apply_why ~= "cancelled" then
      why = apply_why
    end
  end
  if why then den.ui.toast(why) end
  load_game(game.appid, game.name)
  den.ui.set(game_page())
end

function plugin.actions.install()
  if not game or working then return end
  working = true
  local ok, why = pcall(install)
  working = false
  if not ok then error(why, 0) end
end

function plugin.actions.remove()
  if not game or working then return end
  local ok, why = den.mods.remove(game.appid)
  if ok then
    remember(game.appid, false)
    den.ui.toast("Removed. The game has its own FSR library again.")
  elseif why ~= "cancelled" then
    den.ui.toast(why)
  end
  load_game(game.appid, game.name)
  den.ui.set(game_page())
end

return plugin
