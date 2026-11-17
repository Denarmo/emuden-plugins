-- SPDX-FileCopyrightText: Copyright 2026 EmuDEN contributors
-- SPDX-License-Identifier: GPL-3.0-or-later

-- Lossless Scaling frame generation on Linux, through lsfg-vk 2 (lsfg-vk.dev): a Vulkan layer
-- that runs Lossless Scaling's own frame generation, which the user must own on Steam. The
-- layer is downloaded from the project's build server and installed by EmuDEN
-- (den.mods.layer); per game it is switched on with environment variables in the game's Steam
-- launch options (launch.lua, den.steam.set). On Windows Lossless Scaling is its own program
-- and this page only says so.

local launch = den.include("launch.lua")
local release = den.include("release.lua")

-- `release` is here for the tests, which give it a checksum.
local plugin = { actions = {}, release = release }

local LOSSLESS = "993090" -- Lossless Scaling on Steam
local LAYER = "lsfg-vk"
local COVER = "https://shared.steamstatic.com/store_item_assets/steam/apps/%s/library_600x900.jpg"
local FLOWS = { 1.0, 0.85, 0.75, 0.6, 0.5, 0.4, 0.25 }
local TITLE = "LSFG"

local info, steam = nil, nil
local setup = nil  -- { owned, library, layer }
local filter = ""
local game = nil   -- { appid, name, options, now, choice }
local working = false

local function linux() return den.device.platform == "linux" end

local function look()
  setup = { owned = false, library = false, layer = den.mods.layer_state(LAYER) }
  for _, app in ipairs(steam.apps or {}) do
    if app.appid == LOSSLESS and not app.shortcut then setup.owned = true end
  end
  if setup.owned then
    local found = den.mods.find{ appid = LOSSLESS, names = { "lsfg-vk.dll" } }
    setup.library = found ~= nil and #found > 0
  end
  setup.ready = setup.owned and setup.library and setup.layer ~= nil and setup.layer.intact ~= false
end

local function windows_page()
  return { title = TITLE, body = {
    { type = "empty", title = "On Windows, Lossless Scaling is its own program",
      text = "Start Lossless Scaling from Steam, choose LSFG there and press its Scale hotkey in the game. It works over any game's window by itself, and EmuDEN cannot set it up or switch it on from here.\n\nOn Linux and SteamOS this page installs lsfg-vk and switches frame generation on per game." },
  } }
end

local function home_page(progress)
  local body = {}
  if not steam.installed then
    body[#body + 1] = { type = "empty", title = "No Steam here", text = steam.note }
    return { title = TITLE, body = body }
  end
  local layer = setup.layer
  body[#body + 1] = { type = "row", id = "lossless", label = "Lossless Scaling", value = setup.owned and "Installed" or "Not installed" }
  body[#body + 1] = { type = "row", id = "library", label = "Its lsfg-vk library (beta \"lsfg-vk\")",
                      value = setup.library and "Found" or "Missing" }
  body[#body + 1] = { type = "row", id = "layer", label = "lsfg-vk " .. release.version,
                      value = layer and (layer.intact == false and "Changed: install again" or "Installed") or "Not installed" }
  if not setup.owned then
    body[#body + 1] = { type = "text", style = "warning", text =
        "lsfg-vk runs Lossless Scaling's own frame generation, so you need Lossless Scaling: buy it on Steam and install it on this device. Then, in Steam, open its Properties > Betas and choose \"lsfg-vk\"." }
  elseif not setup.library then
    body[#body + 1] = { type = "text", style = "warning", text =
        "Lossless Scaling is installed, but not the version lsfg-vk 2 reads (lsfg-vk.dll is missing). In Steam, open Lossless Scaling's Properties > Betas, choose \"lsfg-vk\" and let Steam update it." }
  end
  if progress then
    body[#body + 1] = { type = "progress", id = "progress", label = progress, fraction = -1 }
  elseif setup.owned and setup.library and not setup.ready then
    if release.sha256 == "" then
      body[#body + 1] = { type = "text", style = "warning", text =
          den.tr("This version of the plugin has no checksum for lsfg-vk {} yet, so it does not download it. Update the plugin.", release.version) }
    else
      body[#body + 1] = { type = "button", id = "install", label = den.tr("Install lsfg-vk {}", release.version), action = "install" }
      body[#body + 1] = { type = "text", style = "caption", text =
          "Downloaded from builds.lsfg-vk.dev, the project's own build server, and checked against a pinned SHA-256. EmuDEN installs it as a Vulkan layer for your user; it does nothing in a game until it is switched on below." }
    end
  end
  if not setup.ready and not progress then
    body[#body + 1] = { type = "button", id = "again", label = "Check again", action = "check" }
  end
  if setup.ready then
    body[#body + 1] = { type = "text", style = "heading", text = "Games" }
    local shown = 0
    for _, app in ipairs(steam.apps) do
      if not app.shortcut and app.appid ~= LOSSLESS and (filter == "" or app.name:lower():find(filter:lower(), 1, true)) then
        local kept = den.storage.get("game:" .. app.appid)
        body[#body + 1] = { type = "row", id = "app-" .. app.appid, label = app.name, value = kept and kept.label or "Off",
                            action = "game", arg = app.appid }
        shown = shown + 1
      end
    end
    if shown == 0 then
      body[#body + 1] = { type = "empty", title = "No Steam games", text = "Install a game in Steam, then open this page again." }
    end
    body[#body + 1] = { type = "text", style = "caption", text =
        "For games that draw with Vulkan, which Proton games (DXVK, VKD3D) do. Generated frames are paced to the display's refresh rate." }
  end
  if layer and not progress then
    body[#body + 1] = { type = "button", id = "remove", label = "Remove lsfg-vk", action = "remove" }
  end
  body[#body + 1] = { type = "text", style = "caption", text =
      "lsfg-vk by PancakeTAS (lsfg-vk.dev), CC BY-NC-ND 4.0: downloaded as published, not part of this plugin. Lossless Scaling by THS." }
  local page = { title = TITLE, subtitle = "Lossless Scaling frame generation, per game", body = body }
  if setup.ready then page.search = { placeholder = "Find a game", value = filter, action = "search" } end
  return page
end

local function copy_settings(s)
  return { on = s.on, multiplier = s.multiplier, flow_scale = s.flow_scale, performance = s.performance }
end

-- The launch options the choice gives, and whether ENABLE_GAMESCOPE_WSI=0 is added to them.
local function wanted()
  local kept = den.storage.get("game:" .. game.appid)
  return launch.merge(game.options, game.choice, { gamescope_wsi = info.steamos == true, wsi_mine = kept ~= nil and kept.wsi == true })
end

local function game_page()
  local choice = game.choice
  local text, why = wanted()
  local changed = text ~= nil and text ~= game.options
  local facts = {
    { label = "Frame generation now", value = launch.describe(game.now) },
    { label = "Launch options now", value = game.options ~= "" and game.options or "None" },
  }
  if changed then
    facts[#facts + 1] = { label = "After Apply", value = text ~= "" and text or "None" }
  end
  local buttons = {}
  if changed and steam.can_change then buttons[1] = { label = "Apply", action = "apply" } end
  local body = {
    { type = "detail", id = "game", title = game.name, subtitle = "lsfg-vk " .. release.version,
      image = string.format(COVER, game.appid), aspect = 0.667, facts = facts,
      text = choice.on and den.tr("{}x: {} generated for every frame the game draws.", choice.multiplier, choice.multiplier - 1)
          or "Off: the game runs without frame generation.",
      buttons = buttons },
  }
  if choice.on then
    body[#body + 1] = { type = "row", id = "flow", label = "Flow scale", value = string.format("%d %%", math.floor(choice.flow_scale * 100 + 0.5)),
                        action = "flow" }
    body[#body + 1] = { type = "text", style = "caption", text = "The size motion is measured at. Lower is faster and less exact; press to change." }
    body[#body + 1] = { type = "row", id = "performance", label = "Performance mode", value = choice.performance and "On" or "Off",
                        action = "performance" }
    body[#body + 1] = { type = "text", style = "caption", text = "A lighter model: faster, with a little more artefacts." }
  end
  if not text then
    body[#body + 1] = { type = "text", style = "warning", text = why }
  elseif changed and not steam.can_change then
    body[#body + 1] = { type = "text", style = "warning", text = steam.note }
    body[#body + 1] = { type = "text", style = "caption", text = "Or enter the options above yourself: the game's Properties > General > Launch options in Steam." }
  elseif not changed then
    body[#body + 1] = { type = "text", style = "caption", text = "Steam already has these settings." }
  end
  body[#body + 1] = { type = "text", style = "caption", text =
      "Start from a steady frame rate: cap the game to half (2x), a third (3x) or a quarter (4x) of the display's refresh rate. Anything else in the game's launch options is kept." }
  local items = { { id = "0", label = "Off", selected = not choice.on } }
  for n = 2, 4 do
    items[#items + 1] = { id = tostring(n), label = n .. "x", selected = choice.on and choice.multiplier == n }
  end
  return { title = game.name, chips = { action = "multiplier", items = items }, body = body }
end

local function unpacked(file, layers)
  local entries = {}
  for _, layer in ipairs(layers) do
    entries[#entries + 1] = layer.manifest
    entries[#entries + 1] = layer.library
  end
  local ok, paths, why = pcall(den.mods.unpack, { file = file, entries = entries })
  if not ok then return nil, paths end
  if not paths then return nil, why end
  local out = {}
  for i, layer in ipairs(layers) do
    out[i] = { manifest = paths[layer.manifest], library = paths[layer.library] }
    if not out[i].manifest or not out[i].library then return nil, den.tr("the build has no {}", layer.library) end
  end
  return out
end

local function install()
  if release.sha256 == "" then return "lsfg-vk is not downloaded without a checksum." end
  den.ui.set(home_page(den.tr("Downloading lsfg-vk {}", release.version)))
  local file, why = den.download{ url = release.url, name = release.name, sha256 = release.sha256,
                                  on_progress = function(fraction) den.ui.patch("progress", { fraction = fraction }) end }
  if not file then return den.tr("lsfg-vk could not be downloaded: {}", tostring(why)) end
  if den.files.size(file) ~= release.size then
    den.files.remove(file)
    return den.tr("The download is not the lsfg-vk {} this plugin knows (another size). Nothing was installed.", release.version)
  end
  local layers, unpack_why = unpacked(file, release.layers)
  if not layers then
    -- A build without the 32-bit layer still serves every 64-bit game.
    local needed = {}
    for _, layer in ipairs(release.layers) do
      if not layer.optional then needed[#needed + 1] = layer end
    end
    if #needed < #release.layers then layers = unpacked(file, needed) end
  end
  den.files.remove(file)
  if not layers then return den.tr("lsfg-vk could not be unpacked: {}", tostring(unpack_why)) end
  den.ui.patch("progress", { label = "Waiting for your answer" })
  local ok, layer_why = den.mods.layer{ name = LAYER, layers = layers }
  if not ok then return layer_why ~= "cancelled" and den.tr("lsfg-vk could not be installed: {}", tostring(layer_why)) or nil end
  den.ui.toast("lsfg-vk is installed. Switch it on for a game below.")
end

function plugin.open()
  if not linux() then
    den.ui.set(windows_page())
    return
  end
  den.ui.set{ title = TITLE, busy = true, body = {} }
  info = den.device.info() or {}
  steam = den.steam.status() or { installed = false, apps = {}, note = "" }
  look()
  den.ui.set(home_page())
end

function plugin.actions.check()
  if not linux() or working then return end
  steam = den.steam.status() or steam
  look()
  den.ui.set(home_page())
end

function plugin.actions.search(_, value)
  if not steam then return end
  filter = value or ""
  den.ui.set(home_page())
end

function plugin.actions.install()
  if not linux() or working or not setup or not (setup.owned and setup.library) then return end
  working = true
  local ok, why = pcall(install)
  working = false
  if not ok then error(why, 0) end
  if why then den.ui.toast(why) end
  look()
  den.ui.set(home_page())
end

function plugin.actions.remove()
  if not linux() or working or not setup or not setup.layer then return end
  local ok, why = den.mods.remove_layer(LAYER)
  if ok then
    den.ui.toast("lsfg-vk is removed. Games still set to use it run without frame generation.")
  elseif why ~= "cancelled" then
    den.ui.toast(why)
  end
  look()
  den.ui.set(home_page())
end

function plugin.actions.game(appid)
  if not setup or not setup.ready then return end
  local name = appid
  for _, app in ipairs(steam.apps) do
    if app.appid == appid then name = app.name end
  end
  if den.ui.depth() > 1 then den.ui.pop() end
  den.ui.push{ title = name, busy = true, body = {} }
  local config = den.steam.config(appid) or {}
  game = { appid = appid, name = name, options = config.launch_options or "" }
  game.now = launch.read(game.options)
  game.choice = copy_settings(game.now)
  den.ui.set(game_page())
end

function plugin.actions.multiplier(_, value)
  if not game then return end
  local n = math.tointeger(tonumber(value)) or 0
  game.choice.on = n >= 2
  if n >= 2 then game.choice.multiplier = n end
  den.ui.set(game_page())
end

function plugin.actions.flow()
  if not game then return end
  -- The next smaller step, and from the smallest back to 100 %.
  local nearest = FLOWS[1]
  for _, flow in ipairs(FLOWS) do
    if flow < game.choice.flow_scale - 0.001 then
      nearest = flow
      break
    end
  end
  game.choice.flow_scale = nearest
  den.ui.set(game_page())
end

function plugin.actions.performance()
  if not game then return end
  game.choice.performance = not game.choice.performance
  den.ui.set(game_page())
end

function plugin.actions.apply()
  if not game then return end
  local text, added = wanted()
  if not text then
    den.ui.toast(added)
    return
  end
  if text == game.options then return end
  local ok, why = den.steam.set{ appid = game.appid, name = game.name, launch_options = text }
  if not ok then
    if why ~= "cancelled" then den.ui.toast(why) end
    return
  end
  local key = "game:" .. game.appid
  if game.choice.on then
    local kept = den.storage.get(key)
    den.storage.set(key, { label = launch.describe(game.choice), wsi = added or (kept ~= nil and kept.wsi == true) })
  else
    den.storage.remove(key)
  end
  -- Steam reports a change a moment later, so the page shows what was set.
  game.options = text
  game.now = launch.read(text)
  game.choice = copy_settings(game.now)
  den.ui.toast(game.now.on and "Set in Steam. Start the game from Steam to use it." or "Frame generation is off for this game.")
  den.ui.set(game_page())
end

return plugin
