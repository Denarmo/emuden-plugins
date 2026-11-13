-- SPDX-FileCopyrightText: Copyright 2026 EmuDEN contributors
-- SPDX-License-Identifier: GPL-3.0-or-later

-- ROM hacks from one web site. The user browses the real site in EmuDEN's browser page and
-- presses its download button; the app hands this script the patch file, and the script finds
-- the base game in the library, patches a copy and adds the hack to the library.
-- The script never sees the page, requests nothing and takes patch files only.
-- Shared by every "ROM Hacks: <site>" plugin; site.lua says which site.

local site = den.include("site.lua")
local pages = den.include("pages.lua")(site)

local plugin = { actions = {} }

local PATCH_TYPES = { "bps", "ips", "ups", "xdelta", "vcdiff", "aps", "ppf" }
-- An archive is opened by the app, which hands over the patch in it (7z: EmuDEN builds
-- with a 7z reader; older ones leave it out of the list by themselves).
local DOWNLOAD_TYPES = { "bps", "ips", "ups", "xdelta", "vcdiff", "aps", "ppf", "zip", "7z" }
-- Consoles a patch without a base checksum can be for, by its format.
local DISC = { psx = true, ps2 = true, psp = true, saturn = true, dreamcast = true,
               gamecube = true, wii = true }
local IPS_LIMIT = 16777216

-- The base games the site's hacks are made for, when the package lists them: by CRC32.
local known_bases = {}
for _, base in ipairs(den.json.decode(den.files.read("package/bases.json") or "[]") or {}) do
  known_bases[base.crc32:lower()] = base
end

local tab = "browse"
local busy = false     -- the browser page is open for this plugin
local pending = nil    -- the patch being installed
local update = nil     -- the patch that updates an installed hack

local function trim(text)
  return ((text or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

-- "Some_Hack-v1.2.bps" -> "Some Hack", "1.2"
local function title_of(name)
  local stem = name:gsub("%.[%w]+$", "")
  local version = stem:match("[%s_%-]+[vV]?(%d+%.[%d%.]*%d)$") or stem:match("[%s_%-]+[vV](%d+)$")
  if version then
    stem = stem:gsub("[%s_%-]+[vV]?[%d%.]+$", "")
  end
  stem = trim(stem:gsub("[_]+", " "))
  return stem ~= "" and stem or "Hack", version or ""
end

-- Letters and digits only, lower case: how file names and titles are compared.
local function plain(text)
  return (text:lower():gsub("[^%w]", ""))
end

local function date_text(seconds)
  local z = seconds // 86400 + 719468
  local era = z // 146097
  local doe = z - era * 146097
  local yoe = (doe - doe // 1460 + doe // 36524 - doe // 146096) // 365
  local doy = doe - (365 * yoe + yoe // 4 - yoe // 100)
  local mp = (5 * doy + 2) // 153
  local day = doy - (153 * mp + 2) // 5 + 1
  local month = mp < 10 and mp + 3 or mp - 9
  local year = yoe + era * 400 + (month <= 2 and 1 or 0)
  return string.format("%04d-%02d-%02d", year, month, day)
end

-- Stored tables: "hacks" (id -> { patch }), "choices" (patch file name -> game id).
local function stored(key)
  local value = den.storage.get(key)
  return type(value) == "table" and value or {}
end

local function store(key, name, value)
  local all = stored(key)
  all[name] = value
  den.storage.set(key, all)
end

local function hack_of(id)
  for _, hack in ipairs(den.library.hacks() or {}) do
    if hack.id == id then
      return hack
    end
  end
end

local function game_of(id)
  for _, game in ipairs(den.library.games() or {}) do
    if game.id == id then
      return game
    end
  end
end

local function show_home()
  if tab == "installed" then
    den.ui.set(pages.installed_tab(den.library.hacks() or {}))
  elseif tab == "about" then
    den.ui.set(pages.about_tab(den.plugin.version))
  else
    den.ui.set(pages.browse_tab(den.web.available()))
  end
end

-- Shows a page above the first one: one at a time, so going back always lands on the tabs.
-- (The user's Back takes a page away without telling the script, so the depth is asked.)
local function show(page)
  if den.ui.depth() > 1 then
    den.ui.set(page)
  else
    den.ui.push(page)
  end
end

local function back_home()
  while den.ui.depth() > 1 do
    den.ui.pop()
  end
  show_home()
end

local function drop(path)
  if path then
    den.files.remove(path)
  end
end

local function inspect(path)
  local info, why = den.patch.inspect(path)
  if not info then
    drop(path)
    den.ui.toast(why or "This file is not a patch.")
  end
  return info
end

-- The user's games a patch that names no base game can be for: by format and size, the
-- game chosen last time for this file first, then the names closest to the file's.
local function candidates(info, name)
  local remembered = stored("choices")[name]
  local wanted = plain(title_of(name))
  local list = {}
  for _, game in ipairs(den.library.games() or {}) do
    local fits = not game.hack_of
    if info.format == "ppf" then
      fits = fits and DISC[game.system] == true
    elseif info.format == "aps" then
      fits = fits and game.system == "gba"
    elseif info.format == "ips" then
      fits = fits and not DISC[game.system] and (game.size or 0) <= IPS_LIMIT
    end
    if fits and info.source_size and game.size and game.size > 0 and game.size ~= info.source_size then
      fits = false
    end
    if fits then
      local title = plain(game.name)
      local score = 0
      if game.id == remembered then
        score = 3
      elseif title ~= "" and (wanted:find(title, 1, true) or title:find(wanted, 1, true)) then
        score = 2
      elseif #title >= 4 and wanted:find(title:sub(1, 4), 1, true) then
        score = 1
      end
      list[#list + 1] = { game = game, score = score, remembered = game.id == remembered }
    end
  end
  table.sort(list, function(a, b)
    if a.score ~= b.score then
      return a.score > b.score
    end
    return a.game.name:lower() < b.game.name:lower()
  end)
  return list
end

local function begin_install(path, origin)
  local info = inspect(path)
  if not info then
    return
  end
  if pending and pending.path ~= path then
    drop(pending.path)
  end
  local name = path:match("([^/]+)$") or path
  local title, version = title_of(name)
  pending = { path = path, name = name, info = info, title = title, version = version,
              origin = origin or "file", verified = false }
  if not info.source_crc32 then
    -- A format without a checksum of its base (ips, xdelta, aps, ppf): the user says which.
    local list = candidates(info, name)
    if list[1] and list[1].remembered then
      pending.base = list[1].game
      pending.remembered = true
      return show(pages.install(pending))
    end
    return show(pages.choose_base(list, pending))
  end
  local base = den.library.find{ crc32 = info.source_crc32, size = info.source_size }
  if not base then
    local crc = string.format("%08X", info.source_crc32)
    pending = nil
    drop(path)
    return show(pages.missing_base(info, known_bases[crc:lower()], crc, name))
  end
  pending.base = base
  pending.verified = true
  show(pages.install(pending))
end

-- A patch file for an installed hack: checked against the hack's base game, then offered.
local function begin_update(hack, path)
  local info = inspect(path)
  if not info then
    return
  end
  if info.source_crc32 then
    local base = den.library.find{ crc32 = info.source_crc32, size = info.source_size }
    if not base or base.id ~= hack.base then
      drop(path)
      return den.ui.toast("This patch is for another base game than " .. hack.name .. ".")
    end
  elseif not game_of(hack.base) then
    drop(path)
    return den.ui.toast("The base game of " .. hack.name .. " is no longer in your library.")
  end
  local name = path:match("([^/]+)$") or path
  local _, version = title_of(name)
  update = { hack = hack, path = path, name = name, info = info, version = version }
  show(pages.update(update))
end

-- Shows the site and waits for the user to download a patch there. The page is taken away
-- once a file arrived; nil when the user closed it without one.
local function fetch_from_site()
  if busy then
    return nil
  end
  busy = true
  local file, why = den.web.open{ url = site.url, title = site.title, extensions = DOWNLOAD_TYPES }
  busy = false
  if not file then
    if why and why ~= "closed" then
      den.ui.toast(why)
    end
    return nil
  end
  den.web.close()
  return file
end

function plugin.open()
  show_home()
end

function plugin.file(path)
  begin_install(path, "file")
end

function plugin.actions.tab(_, value)
  if value and value ~= "" then
    tab = value:match("^[^,]+")
  end
  show_home()
end

function plugin.actions.browse()
  local file = fetch_from_site()
  if file then
    begin_install(file.path, file.source_host)
  end
end

function plugin.actions.import()
  local path = den.files.import{ title = "Choose a patch file", extensions = PATCH_TYPES }
  if path then
    begin_install(path, "file")
  end
end

-- The game chosen for a patch that names none; remembered for this file name.
function plugin.actions.choose(id)
  local game = game_of(id)
  if game and pending then
    pending.base = game
    pending.remembered = false
    store("choices", pending.name, game.id)
    show(pages.install(pending))
  end
end

function plugin.actions.choose_again()
  if pending and not pending.verified then
    pending.base = nil
    show(pages.choose_base(candidates(pending.info, pending.name), pending))
  end
end

function plugin.actions.set(field, value)
  if not pending or type(field) ~= "string" then
    return
  end
  value = trim(value)
  if field == "title" and value ~= "" then
    pending.title = value
  elseif field == "version" then
    pending.version = value
  end
  show(pages.install(pending))
end

function plugin.actions.install()
  if not pending or not pending.base then
    return
  end
  den.ui.patch("status", { label = "Patching " .. pending.base.name, fraction = -1 })
  local made, why = den.patch.apply{
    patch = pending.path, game = pending.base.id, title = pending.title,
    version = pending.version, source = site.name .. " (" .. pending.origin .. ")",
  }
  if not made then
    den.ui.patch("status", { label = why, fraction = 0 })
    return den.ui.toast(why)
  end
  store("hacks", made.game.id, { patch = pending.name })
  drop(pending.path)
  pending = nil
  tab = "installed"
  back_home()
  show(pages.done(made.game))
end

function plugin.actions.play(id)
  den.app.open_game(id)
end

function plugin.actions.hack(id)
  local hack = hack_of(id)
  if hack then
    show(pages.hack(hack, stored("hacks")[id] or {}, game_of(hack.base), date_text(hack.installed)))
  end
end

function plugin.actions.rename(id, value)
  value = trim(value)
  if value ~= "" then
    local ok, why = den.library.update(id, { title = value })
    den.ui.toast(ok and "Renamed." or why)
    local hack = ok and hack_of(id)
    if hack then
      show(pages.hack(hack, stored("hacks")[id] or {}, game_of(hack.base),
                            date_text(hack.installed)))
    end
  end
end

function plugin.actions.remove(id)
  if not den.ui.confirm{ title = "Remove this hack?", yes = "Remove", message =
      "Its patched file is deleted. Your own game stays." } then
    return
  end
  local ok, why = den.library.remove(id)
  if not ok then
    return den.ui.toast(why)
  end
  store("hacks", id, nil)
  tab = "installed"
  back_home()
end

function plugin.actions.update_site(id)
  local hack = hack_of(id)
  local file = hack and fetch_from_site()
  if file then
    begin_update(hack, file.path)
  end
end

function plugin.actions.update_file(id)
  local hack = hack_of(id)
  local path = hack and den.files.import{ title = "Choose the newer patch file",
                                          extensions = PATCH_TYPES }
  if path then
    begin_update(hack, path)
  end
end

function plugin.actions.set_update_version(_, value)
  if update then
    update.version = trim(value)
    den.ui.patch("version", { value = update.version })
  end
end

function plugin.actions.apply_update(keep_old)
  if not update then
    return
  end
  local hack = update.hack
  den.ui.patch("status", { label = "Patching", fraction = -1 })
  local made, why = den.patch.apply{
    patch = update.path, game = hack.base, title = hack.name, version = update.version,
    source = site.name, keep_old = keep_old == true,
  }
  if not made then
    den.ui.patch("status", { label = why, fraction = 0 })
    return den.ui.toast(why)
  end
  store("hacks", made.game.id, { patch = update.name })
  drop(update.path)
  update = nil
  tab = "installed"
  back_home()
  den.ui.toast("Updated " .. made.game.name .. ".")
end

return plugin
