-- SPDX-FileCopyrightText: Copyright 2026 EmuDEN contributors
-- SPDX-License-Identifier: GPL-3.0-or-later

-- Offline test of emuden.tune.helixsr over tests/den_mock.lua: which games are offered, the
-- anti-cheat refusal, the pinned download, Install, a game update and Remove.

local mock = require("den_mock")
local DIR = os.getenv("DEN_PLUGIN_DIR") or "plugins/emuden.tune.helixsr"
local check = mock.check

local FSR = "amd_fidelityfx_upscaler_dx12.dll"
local AMD, HLX = "the game's own FSR library", "HLX FSR 4"

-- The release as shipped: a full digest, the official address, the library inside the ZIP.
do
  local shipped = dofile(DIR .. "/release.lua")
  check(shipped.version == "3.4.0" and shipped.size == 290684780, "the pinned release")
  check(#shipped.sha256 == 64 and shipped.sha256:match("^[0-9a-f]+$") ~= nil, "a full SHA-256")
  check(shipped.url == "https://github.com/lonewolf0622/HelixSR/releases/download/v3.4.0/HelixSR-3.4.0.zip", "the official release")
  check(shipped.library == "HelixSR-3.4.0/HLX-FSR4/" .. FSR and shipped.library_size == 58185808, "the library in the ZIP")
end

local ZIP = string.rep("z", 64)
local release

local function start(opts, prepare)
  local plugin = mock.load(DIR, opts)
  release = plugin.release
  release.size, release.library_size = #ZIP, #HLX -- the test's ZIP is small
  mock.steam = { installed = true, can_change = true, note = "", tools = {}, config = {},
                 apps = { { appid = "100", name = "Alpha Quest", shortcut = false },
                          { appid = "200", name = "Battle Online", shortcut = false },
                          { appid = "300", name = "Old Road", shortcut = false },
                          { appid = "400", name = "Plain Game", shortcut = false },
                          { appid = "4105511571", name = "EmuDEN", shortcut = true } } }
  mock.game_files = {
    ["100"] = { ["Alpha.exe"] = "exe", ["Engine/Binaries/Win64/" .. FSR] = AMD, ["Engine/Binaries/Win64/amd_fidelityfx_loader_dx12.dll"] = "loader" },
    ["200"] = { ["bin/" .. FSR:upper()] = AMD, ["EasyAntiCheat/EasyAntiCheat_EOS_Setup.exe"] = "eac" },
    ["300"] = { ["amd_fidelityfx_dx12.dll"] = "fsr 3.0" },
    ["400"] = { ["game.exe"] = "exe" },
  }
  mock.archives["downloads/" .. release.name] = { [release.library] = HLX, ["HelixSR-3.4.0/LICENSE"] = "licence" }
  mock.http_route("^https://github%.com/lonewolf0622/HelixSR/releases/download/", { status = 200, body = ZIP })
  if prepare then prepare() end
  check(mock.open(), "plugin.open runs")
  return plugin
end

local function detail() return mock.find("game") end
local function has_button(label)
  for _, b in ipairs(detail().buttons or {}) do
    if b.label == label then return true end
  end
  return false
end
local function fact(label)
  for _, f in ipairs(detail().facts or {}) do
    if f.label == label then return f.value end
  end
end
local function downloads()
  local n = 0
  for _, r in ipairs(mock.requests) do
    if r.kind == "download" then n = n + 1 end
  end
  return n
end

start()

-- The list: Steam games, not shortcuts.
do
  local page = mock.page()
  check(page.title == "Helix SR", "the home page")
  check(mock.find("app-100") and mock.find("app-200") and mock.find("app-400"), "Steam games are listed")
  check(mock.find("app-4105511571") == nil, "a non-Steam shortcut is not")
  check(mock.find("app-100").value == "Check", "nothing is looked at before a game is opened")
  mock.action("search", nil, "battle")
  check(mock.find("app-200") and not mock.find("app-100"), "the search narrows the list")
  mock.action("search", nil, "")
end

-- Not compatible: no FSR library, and FSR 3.0's single library.
do
  mock.action("game", "400")
  check(fact("FSR 3.1 library") == "Not found" and not has_button("Install"), "a game without FSR gets no Install")
  mock.action("game", "300")
  check(not has_button("Install") and detail().text:find("amd_fidelityfx_dx12.dll", 1, true), "FSR 3.0 alone is not enough, and the page says why")
end

-- Anti-cheat: refused with the reason, also when asked directly.
do
  mock.action("game", "200")
  check(fact("Anti-cheat"):find("Easy Anti%-Cheat") and fact("Anti-cheat"):find("EasyAntiCheat_EOS_Setup.exe", 1, true), "the anti-cheat file is named")
  check(not has_button("Install") and detail().text:find("not installed here"), "a protected game is refused with a reason")
  mock.action("install")
  check(downloads() == 0 and mock.mods["200"] == nil and #mock.asks == 0, "Install does nothing in a protected game")
end

-- Every anti-cheat marker is found by its file name, and a normal file is not.
do
  for file, label in pairs({ ["BattlEye/BEService_x64.exe"] = "BattlEye", ["Game_BE.exe"] = "BattlEye", ["start_protected_game.exe"] = "Easy Anti-Cheat",
                             ["EQU8/equ8_conf.json"] = "EQU8", ["faceit.dll"] = "FACEIT", ["vgk.sys"] = "Vanguard",
                             ["__Installer/EAAntiCheat.Installer.exe"] = "EA anticheat", ["GameGuard.des"] = "GameGuard",
                             ["BEClient_x64.dll"] = "BattlEye", ["x/xigncode.log"] = "XIGNCODE3" }) do
    mock.game_files["400"] = { ["game.exe"] = "exe", [FSR] = AMD, [file] = "guard" }
    mock.action("game", "400")
    check(not has_button("Install") and tostring(fact("Anti-cheat")):find(label, 1, true), file .. " refuses the game")
  end
  mock.game_files["400"] = { ["game.exe"] = "exe", [FSR] = AMD, ["beacon.dll"] = "a game file", ["notes_be.txt"] = "text" }
  mock.action("game", "400")
  check(has_button("Install") and fact("Anti-cheat") == "None found", "similar names of other files do not refuse a game")
  mock.game_files["400"] = { ["game.exe"] = "exe" }
end

-- Install: asks before the download, pins it, unpacks the one library and replaces the game's.
do
  local target = "Engine/Binaries/Win64/" .. FSR
  mock.action("game", "100")
  check(fact("FSR 3.1 library") == target and has_button("Install") and not has_button("Remove"), "a game with FSR 3.1 offers Install")

  mock.answer(false)
  mock.action("install")
  check(downloads() == 0 and mock.game_files["100"][target] == AMD, "No to the download changes nothing")

  mock.answer(true, false)
  mock.action("install")
  local request = mock.requests[#mock.requests]
  check(downloads() == 1 and request.url == release.url and request.sha256 == release.sha256, "the download is pinned by its SHA-256")
  check(mock.asks[#mock.asks].files[1].to == target and mock.asks[#mock.asks].files[1].replaced == true, "EmuDEN's question lists the file as replaced")
  check(mock.game_files["100"][target] == AMD and mock.mods["100"] == nil, "No to EmuDEN's question changes nothing")
  check(mock.files["downloads/" .. release.name] == nil, "the ZIP is not kept")
  check(mock.files["cache/mods/HelixSR-3.4.0/" .. release.library] == HLX, "the library is kept in the cache")

  mock.answer(true)
  mock.action("install")
  check(downloads() == 1, "the cached library is used again without a download")
  check(mock.game_files["100"][target] == HLX, "the game's library is HLX FSR 4")
  check(mock.game_files["100"]["Engine/Binaries/Win64/amd_fidelityfx_loader_dx12.dll"] == "loader", "nothing else is touched")
  check(mock.mods["100"].name == "Helix SR 3.4.0 (HLX FSR 4)", "the mod's name in EmuDEN's record")
  check(fact("Helix SR") == "Installed" and has_button("Remove") and not has_button("Install"), "the page shows it installed")
  check(mock.toasts[#mock.toasts]:find("AMD FSR"), "the user is told what to pick in the game")
  check(mock.storage.applied[1] == "100", "the game is remembered for the list")
end

-- A new start: the list shows the state, and a game update is noticed.
do
  local target = "Engine/Binaries/Win64/" .. FSR
  start({ keep = true }, function()
    mock.game_files["100"][target] = HLX
    mock.mods["100"] = { name = "Helix SR 3.4.0 (HLX FSR 4)", time = 1, files = { { to = target, written = HLX, original = AMD } } }
  end)
  check(mock.find("app-100").value == "Installed", "the list shows installed games")

  mock.game_files["100"][target] = "the game's newer FSR library"
  mock.action("search", nil, "")
  check(mock.find("app-100").value == "Changed by a game update", "the list shows a game update")
  mock.action("game", "100")
  check(fact("Helix SR") == "Changed by a game update" and has_button("Install again") and has_button("Remove"), "the page offers to install again")
  check(detail().text:find("Install again"), "and says so")

  mock.answer(true)
  mock.action("install")
  check(downloads() == 0 and mock.game_files["100"][target] == HLX and fact("Helix SR") == "Installed", "Install again puts HLX FSR 4 back")
  check(mock.mods["100"].files[1].original == "the game's newer FSR library", "the newer original is the one kept")
end

-- Remove: the game's own library comes back.
do
  local target = "Engine/Binaries/Win64/" .. FSR
  mock.answer(false)
  mock.action("remove")
  check(mock.game_files["100"][target] == HLX and has_button("Remove"), "No to Remove keeps it")
  mock.answer(true)
  mock.action("remove")
  check(mock.game_files["100"][target] == "the game's newer FSR library" and mock.mods["100"] == nil, "Remove gives the original back")
  check(fact("Helix SR") == "Not installed" and has_button("Install"), "the page offers Install again")
  check(#mock.storage.applied == 0, "the game is forgotten")
end

-- A download that is not the pinned release, and a failed download.
do
  start()
  mock.http_route("^https://github%.com/lonewolf0622/HelixSR/releases/download/", { status = 200, body = "short" })
  mock.action("game", "100")
  mock.answer(true)
  mock.action("install")
  check(mock.toasts[#mock.toasts]:find("another size") and mock.mods["100"] == nil, "a download of another size is refused")
  check(mock.files["downloads/" .. release.name] == nil, "and deleted")

  mock.http_route("^https://github%.com/lonewolf0622/HelixSR/releases/download/", { status = 404, body = "" })
  mock.answer(true)
  mock.action("install")
  check(mock.toasts[#mock.toasts]:find("could not be downloaded") and has_button("Install"), "a failed download is reported")
end

-- Several copies of the library in one game are all replaced; without Steam the page says so.
do
  start()
  mock.game_files["400"] = { ["a/" .. FSR] = AMD, ["b/" .. FSR] = AMD }
  mock.action("game", "400")
  mock.answer(true, true)
  mock.action("install")
  check(mock.game_files["400"]["a/" .. FSR] == HLX and mock.game_files["400"]["b/" .. FSR] == HLX, "every copy is replaced")

  mock.load(DIR)
  mock.steam = { installed = false, can_change = false, note = "Steam was not found.", apps = {}, tools = {}, config = {} }
  mock.open()
  check(mock.page().body[1].type == "empty" and mock.page().body[1].text == "Steam was not found.", "no Steam, no list")
end

mock.finish()
