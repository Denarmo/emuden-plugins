-- SPDX-FileCopyrightText: Copyright 2026 EmuDEN contributors
-- SPDX-License-Identifier: GPL-3.0-or-later

-- Offline test of emuden.tune.lsfg over tests/den_mock.lua: the Windows page, the checks for
-- Lossless Scaling, installing the layer, and a game's settings through den.steam.set.

local mock = require("den_mock")
local DIR = os.getenv("DEN_PLUGIN_DIR") or "plugins/emuden.tune.lsfg"
local check = mock.check

local MANIFEST = '{"file_format_version":"1.1.0","layer":{"name":"VK_LAYER_LSFGVK_frame_generation",' ..
                 '"library_path":"liblsfg-vk-layer.so","type":"GLOBAL","disable_environment":{"DISABLE_LSFGVK":"1"}}}'
local TARBALL = string.rep("t", 32)
local SHA = string.rep("ab", 32)
local ON2 = "LSFGVK_ENV=1 LSFGVK_MULTIPLIER=2 LSFGVK_FLOW_SCALE=1.0 LSFGVK_PERFORMANCE_MODE=0"
local release

-- The release as shipped.
do
  local shipped = dofile(DIR .. "/release.lua")
  check(shipped.url == "https://builds.lsfg-vk.dev/lsfg-vk-2.0.0.tar.xz" and shipped.name == "lsfg-vk-2.0.0.tar.xz", "the official build")
  check(shipped.sha256 == "" or (#shipped.sha256 == 64 and shipped.sha256:match("^[0-9a-f]+$") ~= nil), "a full SHA-256 or none")
  check(#shipped.layers == 2 and not shipped.layers[1].optional and shipped.layers[2].optional, "the 64-bit layer, and the 32-bit one when there")
end

-- world: { lossless, library, steamos, sha256, x86, can_change }
local function start(world, opts)
  world, opts = world or {}, opts or {}
  opts.platform = opts.platform or "linux"
  local plugin = mock.load(DIR, opts)
  release = plugin.release
  release.sha256, release.size = world.sha256 or SHA, #TARBALL
  mock.device_info = { name = "Legion Go S", os = "linux", steamos = world.steamos == true, handheld = true }
  local apps = { { appid = "100", name = "Alpha Quest", shortcut = false }, { appid = "200", name = "Beta Racer", shortcut = false },
                 { appid = "4105511571", name = "EmuDEN", shortcut = true } }
  mock.game_files = { ["100"] = { ["a.exe"] = "exe" }, ["200"] = { ["b.exe"] = "exe" } }
  if world.lossless ~= false then
    apps[#apps + 1] = { appid = "993090", name = "Lossless Scaling", shortcut = false }
    mock.game_files["993090"] = { ["LosslessScaling.exe"] = "exe", ["Lossless.dll"] = "dll" }
    if world.library ~= false then mock.game_files["993090"]["lsfg-vk.dll"] = "the lsfg-vk library" end
  end
  mock.steam = { installed = true, can_change = world.can_change ~= false, note = "Steam's local port is off.", tools = {}, apps = apps,
                 config = { ["100"] = { launch_options = "" }, ["200"] = { launch_options = "PROTON_LOG=1 gamemoderun %command% -dx11" } } }
  local archive = {}
  for i, layer in ipairs(release.layers) do
    if i == 1 or world.x86 ~= false then
      archive[layer.manifest], archive[layer.library] = MANIFEST, "ELF " .. i
    end
  end
  mock.archives["downloads/" .. release.name] = archive
  mock.http_route("^https://builds%.lsfg%-vk%.dev/lsfg%-vk%-2%.0%.0%.tar%.xz$", { status = 200, body = TARBALL })
  if world.layer then mock.layers["lsfg-vk"] = { time = 1, manifests = { "emuden-emuden.tune.lsfg-x.json" }, intact = world.layer ~= "changed" } end
  check(mock.open(), "plugin.open runs")
  return plugin
end

local function texts(style)
  local out = {}
  for _, e in ipairs(mock.page().body) do
    if e.type == "text" and (not style or e.style == style) then out[#out + 1] = e.text end
  end
  return table.concat(out, "\n")
end
local function downloads()
  local n = 0
  for _, r in ipairs(mock.requests) do
    if r.kind == "download" then n = n + 1 end
  end
  return n
end
local function fact(label)
  for _, f in ipairs(mock.find("game").facts or {}) do
    if f.label == label then return f.value end
  end
end
local function has_apply() return #(mock.find("game").buttons or {}) > 0 end

-- Windows: one page, nothing asked of Steam or of the game folders.
do
  start({}, { platform = "windows" })
  local page = mock.page()
  check(#page.body == 1 and page.body[1].type == "empty" and page.body[1].title:find("its own program"), "the Windows page")
  mock.action("install")
  mock.action("check")
  mock.action("game", "100")
  check(#mock.requests == 0 and #mock.asks == 0 and #mock.pages == 1, "nothing can be done there")
end

-- Without Lossless Scaling: the explanation, no install.
do
  start({ lossless = false })
  check(mock.find("lossless").value == "Not installed" and mock.find("install") == nil, "no Lossless Scaling, no install")
  check(texts("warning"):find("buy it on Steam") and texts("warning"):find("Betas"), "the page says what to do")
  check(mock.find("app-100") == nil, "no games are offered yet")
  mock.action("install")
  check(downloads() == 0, "Install does nothing without Lossless Scaling")
end

-- Lossless Scaling without its lsfg-vk beta.
do
  start({ library = false })
  check(mock.find("lossless").value == "Installed" and mock.find("library").value == "Missing", "installed, but not the beta")
  check(texts("warning"):find("Properties > Betas") and mock.find("install") == nil, "the page names the beta branch")
  -- The user switches the branch in Steam and comes back.
  mock.game_files["993090"]["lsfg-vk.dll"] = "the lsfg-vk library"
  mock.action("check")
  check(mock.find("library").value == "Found" and mock.find("install") ~= nil, "Check again finds the library")
end

-- Without a checksum the build is not downloaded.
do
  start({ sha256 = "" })
  release.sha256 = ""
  mock.action("check")
  check(mock.find("install") == nil and texts("warning"):find("no checksum"), "no checksum, no install button")
  mock.action("install")
  check(downloads() == 0 and mock.layers["lsfg-vk"] == nil, "and no download")
  mock.toasts = {}
end

-- Installing the layer.
do
  start()
  check(mock.find("layer").value == "Not installed" and mock.find("install") ~= nil, "everything is there but the layer")
  mock.answer(false)
  mock.action("install")
  check(downloads() == 1 and mock.layers["lsfg-vk"] == nil, "No to EmuDEN's question installs nothing")
  check(mock.requests[#mock.requests].sha256 == SHA and mock.requests[#mock.requests].url == release.url, "the download is pinned")
  check(mock.files["downloads/" .. release.name] == nil, "the tarball is not kept")

  mock.answer(true)
  mock.action("install")
  local layer = mock.layers["lsfg-vk"]
  check(layer and #layer.manifests == 2, "both layers are installed")
  check(layer.manifests[1] == "emuden-emuden.tune.lsfg-VkLayer_LSFGVK_frame_generation.json"
        and layer.manifests[2] == "emuden-emuden.tune.lsfg-VkLayer_LSFGVK_frame_generation.x86.json", "under EmuDEN's names")
  check(mock.find("layer").value == "Installed" and mock.find("install") == nil, "the page shows it installed")
  check(mock.find("app-100") and mock.find("app-200"), "games are offered now")
  check(mock.find("app-993090") == nil and mock.find("app-4105511571") == nil, "not Lossless Scaling itself, not shortcuts")
  check(mock.find("app-100").value == "Off", "a game starts as Off")

  mock.answer(false)
  mock.action("remove")
  check(mock.layers["lsfg-vk"] ~= nil, "No to Remove keeps the layer")
  mock.answer(true)
  mock.action("remove")
  check(mock.layers["lsfg-vk"] == nil and mock.find("layer").value == "Not installed" and mock.find("app-100") == nil, "Remove takes the layer away")
end

-- A build without the 32-bit layer, a wrong download, a failed one, a changed layer.
do
  start({ x86 = false })
  mock.answer(true)
  mock.action("install")
  check(mock.layers["lsfg-vk"] and #mock.layers["lsfg-vk"].manifests == 1, "the 64-bit layer alone is installed")

  start()
  mock.http_route("builds%.lsfg%-vk%.dev", { status = 200, body = "another file" })
  mock.action("install")
  check(mock.layers["lsfg-vk"] == nil and mock.toasts[#mock.toasts]:find("another size"), "a download of another size is refused")
  mock.http_route("builds%.lsfg%-vk%.dev", { status = 503, body = "" })
  mock.action("install")
  check(mock.toasts[#mock.toasts]:find("could not be downloaded") and mock.find("install") ~= nil, "a failed download is reported")

  start({ layer = "changed" })
  check(mock.find("layer").value == "Changed: install again" and mock.find("install") ~= nil and mock.find("app-100") == nil,
        "a changed layer is installed again before games are offered")
end

-- A game: choose, Apply, change, Off. The game's other launch options stay.
do
  start({ layer = true })
  mock.action("game", "200")
  check(fact("Frame generation now") == "Off" and fact("Launch options now") == "PROTON_LOG=1 gamemoderun %command% -dx11", "the game as it is")
  check(not has_apply() and mock.find("flow") == nil, "nothing to apply while Off")
  check(mock.page().chips.items[1].selected == true and #mock.page().chips.items == 4, "Off, 2x, 3x, 4x")

  mock.action("multiplier", nil, "2")
  check(mock.page().chips.items[2].selected == true and has_apply(), "2x chosen")
  check(fact("After Apply") == ON2 .. " PROTON_LOG=1 gamemoderun %command% -dx11", "the page shows the options it would set")
  mock.answer(false)
  mock.action("apply")
  check(mock.steam.config["200"].launch_options == "PROTON_LOG=1 gamemoderun %command% -dx11", "No changes nothing")
  mock.answer(true)
  mock.action("apply")
  check(mock.steam.config["200"].launch_options == ON2 .. " PROTON_LOG=1 gamemoderun %command% -dx11", "2x is set in front of the game's own options")
  check(fact("Frame generation now") == "2x" and not has_apply(), "the page shows it set")
  check(mock.storage["game:200"].label == "2x" and mock.storage["game:200"].wsi == false, "remembered for the list")

  mock.action("multiplier", nil, "4")
  mock.action("flow")
  mock.action("flow")
  mock.action("performance")
  check(mock.find("flow").value == "75 %" and mock.find("performance").value == "On", "flow scale and performance mode")
  mock.answer(true)
  mock.action("apply")
  check(mock.steam.config["200"].launch_options ==
        "LSFGVK_ENV=1 LSFGVK_MULTIPLIER=4 LSFGVK_FLOW_SCALE=0.75 LSFGVK_PERFORMANCE_MODE=1 PROTON_LOG=1 gamemoderun %command% -dx11",
        "4x at 75 % in performance mode replaces 2x")
  check(mock.storage["game:200"].label == "4x at 75 %, performance mode", "the list's label follows")
  for _ = 1, 5 do mock.action("flow") end
  check(mock.find("flow").value == "100 %", "the flow scale comes round to 100 %")

  mock.action("multiplier", nil, "0")
  mock.answer(true)
  mock.action("apply")
  check(mock.steam.config["200"].launch_options == "PROTON_LOG=1 gamemoderun %command% -dx11", "Off gives the game's own options back")
  check(mock.storage["game:200"] == nil and fact("Frame generation now") == "Off", "and the game is forgotten")

  if mock.den.ui.depth() > 1 then mock.den.ui.pop() end
  mock.action("game", "100")
  mock.action("multiplier", nil, "3")
  mock.answer(true)
  mock.action("apply")
  check(mock.steam.config["100"].launch_options == "LSFGVK_ENV=1 LSFGVK_MULTIPLIER=3 LSFGVK_FLOW_SCALE=1.0 LSFGVK_PERFORMANCE_MODE=0 %command%",
        "a game without launch options gets %command%")
  mock.action("multiplier", nil, "0")
  mock.answer(true)
  mock.action("apply")
  check(mock.steam.config["100"].launch_options == "", "and has none again after Off")
end

-- SteamOS: ENABLE_GAMESCOPE_WSI=0 comes with it and goes with it, but not the user's own.
do
  start({ layer = true, steamos = true })
  mock.action("game", "100")
  mock.action("multiplier", nil, "2")
  mock.answer(true)
  mock.action("apply")
  check(mock.steam.config["100"].launch_options == ON2 .. " ENABLE_GAMESCOPE_WSI=0 %command%", "added on SteamOS")
  check(mock.storage["game:100"].wsi == true, "and remembered as the plugin's")

  -- A new start, a change, then Off: the plugin still knows the variable is its own.
  start({ layer = true, steamos = true }, { keep = true })
  mock.steam.config["100"].launch_options = ON2 .. " ENABLE_GAMESCOPE_WSI=0 %command%"
  mock.action("game", "100")
  check(fact("Frame generation now") == "2x" and mock.find("app-100", mock.pages[1]).value == "2x", "the state is read back")
  mock.action("multiplier", nil, "3")
  mock.answer(true)
  mock.action("apply")
  check(mock.steam.config["100"].launch_options ==
        "LSFGVK_ENV=1 LSFGVK_MULTIPLIER=3 LSFGVK_FLOW_SCALE=1.0 LSFGVK_PERFORMANCE_MODE=0 ENABLE_GAMESCOPE_WSI=0 %command%", "kept once on a change")
  check(mock.storage["game:100"].wsi == true, "still the plugin's")
  mock.action("multiplier", nil, "0")
  mock.answer(true)
  mock.action("apply")
  check(mock.steam.config["100"].launch_options == "", "Off takes it out again")

  start({ layer = true, steamos = true })
  mock.steam.config["100"].launch_options = "ENABLE_GAMESCOPE_WSI=0 %command%"
  mock.action("game", "100")
  mock.action("multiplier", nil, "2")
  mock.answer(true)
  mock.action("apply")
  mock.action("multiplier", nil, "0")
  mock.answer(true)
  mock.action("apply")
  check(mock.steam.config["100"].launch_options == "ENABLE_GAMESCOPE_WSI=0 %command%", "the user's own ENABLE_GAMESCOPE_WSI stays")
end

-- Launch options EmuDEN would refuse, and a Steam that cannot be changed.
do
  start({ layer = true })
  mock.steam.config["100"].launch_options = 'PROTON_LOG=1 "%command%"'
  mock.action("game", "100")
  mock.action("multiplier", nil, "2")
  check(not has_apply() and texts("warning"):find("a quote"), "options with a quote are left alone, with the reason")
  mock.action("apply")
  check(#mock.asks == 0 and mock.steam.config["100"].launch_options == 'PROTON_LOG=1 "%command%"', "and Apply does nothing")
  mock.toasts = {}

  start({ layer = true, can_change = false })
  mock.action("game", "100")
  mock.action("multiplier", nil, "2")
  check(not has_apply() and texts("warning"):find("local port") and fact("After Apply") == ON2 .. " %command%",
        "a Steam that cannot be changed: the options are shown to enter by hand")
end

mock.finish()
