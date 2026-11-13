-- SPDX-FileCopyrightText: Copyright 2026 EmuDEN contributors
-- SPDX-License-Identifier: GPL-3.0-or-later

-- ROM Hacks: the user downloads a patch in their own browser (for instance on Hackdex), this
-- plugin finds the base game in the library by the patch's checksum and installs the hack.
-- It makes no request to any site, never downloads a game and holds no patches.

local pages = den.include("pages.lua")

local plugin = { actions = {} }

-- The base games hacks are made for (bases.json), by CRC32 and by id.
local bases = den.json.decode(den.files.read("package/bases.json") or "[]") or {}
local base_by_crc, base_by_id = {}, {}
for _, base in ipairs(bases) do
  base_by_crc[base.crc32] = base
  base_by_id[base.id] = base
end

local tab = "install"
local home_on_top = false  -- false once a page was pushed; the user's Back is not reported
local pending = nil        -- the patch being installed
local update = nil         -- the patch that updates an installed hack

local function crc_text(number)
  return string.format("%08X", number)
end

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

-- The address of a hack's Hackdex page from what the user typed, or nil.
local function page_url(text)
  text = trim(text)
  local slug = text:match("hackdex%.app/hack/([%w%-_]+)") or text:match("^([%w%-_]+)$")
  return slug and ("https://www.hackdex.app/hack/" .. slug:lower()) or nil
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

-- What this plugin notes about its hacks: id -> { page, patch, description }.
local function metas()
  local stored = den.storage.get("hacks")
  return type(stored) == "table" and stored or {}
end

local function set_meta(id, meta)
  local all = metas()
  all[id] = meta
  den.storage.set("hacks", all)
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

local function push(page)
  home_on_top = false
  return den.ui.push(page)
end

local function show_bases()
  den.ui.set(pages.bases_tab(nil))
  local rows = {}
  for _, base in ipairs(bases) do
    local owned = den.library.find{ system = base.system, crc32 = base.crc32 }
    rows[#rows + 1] = { base = base, owned = owned ~= nil }
  end
  if tab == "bases" and home_on_top then
    den.ui.set(pages.bases_tab(rows))
  end
end

local function show_home()
  home_on_top = true
  if tab == "installed" then
    den.ui.set(pages.installed_tab(den.library.hacks() or {}))
  elseif tab == "bases" then
    show_bases()
  elseif tab == "about" then
    den.ui.set(pages.about_tab(den.plugin.version))
  else
    local installed = {}
    for _, meta in pairs(metas()) do
      if meta.patch then
        installed[meta.patch] = true
      end
    end
    den.ui.set(pages.install_tab(den.files.inbox() or {}, installed))
  end
end

-- Back to the first page from whatever this plugin pushed on it.
local function back_home(pushed)
  for _ = 1, pushed do
    den.ui.pop()
  end
  show_home()
end

local function inspect(path)
  local info, why = den.patch.inspect(path)
  if not info then
    den.files.remove(path)
    den.ui.toast(why or "This file is not a patch.")
  end
  return info
end

local function begin_install(path)
  local info = inspect(path)
  if not info then
    return
  end
  local name = path:match("([^/]+)$") or path
  local title, version = title_of(name)
  pending = { path = path, name = name, info = info, title = title, version = version,
              description = "", verified = false }
  if not info.source_crc32 then
    -- A format without a checksum of its base (xdelta, ips): the user says which game.
    return push(pages.choose_base(den.library.games() or {}))
  end
  local base = den.library.find{ crc32 = info.source_crc32, size = info.source_size }
  if not base then
    local crc = crc_text(info.source_crc32)
    pending = nil
    den.files.remove(path)
    return push(pages.missing_base(info, base_by_crc[crc:lower()], crc))
  end
  pending.base = base
  pending.verified = true
  push(pages.install(pending))
end

function plugin.open()
  show_home()
end

function plugin.resume()
  if home_on_top and tab == "install" then
    show_home()
  end
end

function plugin.file(path)
  begin_install(path)
end

function plugin.actions.tab(_, value)
  if value and value ~= "" then
    tab = value:match("^[^,]+")
  end
  show_home()
end

function plugin.actions.refresh()
  show_home()
end

function plugin.actions.browse()
  den.open_url(pages.SITE)
end

function plugin.actions.import()
  local path = den.files.import{ title = "Choose a patch file" }
  if path then
    begin_install(path)
  end
end

function plugin.actions.take(token)
  local path, why = den.files.take(token)
  if not path then
    return den.ui.toast(why)
  end
  begin_install(path)
end

function plugin.actions.base(id)
  local base = base_by_id[id]
  if base then
    push(pages.base(base, den.library.find{ system = base.system, crc32 = base.crc32 }))
  end
end

-- The game chosen for a patch that names none.
function plugin.actions.choose(id)
  local game = game_of(id)
  if not game then
    return
  end
  if pending and not pending.base then
    pending.base = game
    den.ui.set(pages.install(pending))
  end
end

function plugin.actions.set(field, value)
  if not pending or type(field) ~= "string" then
    return
  end
  value = trim(value)
  if field == "title" then
    if value == "" then
      return
    end
    pending.title = value
  elseif field == "page" then
    pending.page = page_url(value)
    if value ~= "" and not pending.page then
      den.ui.toast("That is not a Hackdex hack page: hackdex.app/hack/<name>")
    end
  elseif field == "version" or field == "description" then
    pending[field] = value
  end
  den.ui.set(pages.install(pending))
end

function plugin.actions.cover()
  if not pending then
    return
  end
  local picture = den.files.import{ title = "Choose a cover picture",
                                    extensions = { "png", "jpg", "jpeg" } }
  if picture then
    if pending.cover and pending.cover ~= picture then
      den.files.remove(pending.cover)
    end
    pending.cover = picture
    den.ui.set(pages.install(pending))
  end
end

function plugin.actions.install()
  if not pending or not pending.base then
    return
  end
  den.ui.patch("status", { label = "Patching " .. pending.base.name, fraction = -1 })
  local made, why = den.patch.apply{
    patch = pending.path, game = pending.base.id, title = pending.title,
    version = pending.version, description = pending.description, cover = pending.cover,
    source = pending.page or "file",
  }
  if not made then
    den.ui.patch("status", { label = why, fraction = 0 })
    return den.ui.toast(why)
  end
  set_meta(made.game.id, { page = pending.page, patch = pending.name,
                           description = pending.description })
  den.files.remove(pending.path)
  if pending.cover then
    den.files.remove(pending.cover)
  end
  local page = pending.page
  pending = nil
  tab = "installed"
  back_home(1)
  push(pages.done(made.game, page))
end

function plugin.actions.play(id)
  den.app.open_game(id)
end

function plugin.actions.hack(id)
  local hack = hack_of(id)
  if hack then
    push(pages.hack(hack, metas()[id] or {}, game_of(hack.base), date_text(hack.installed)))
  end
end

function plugin.actions.rename(id, value)
  value = trim(value)
  if value ~= "" then
    local ok, why = den.library.update(id, { title = value })
    den.ui.toast(ok and "Renamed." or why)
  end
end

function plugin.actions.link(id, value)
  local meta = metas()[id] or {}
  meta.page = page_url(value)
  if trim(value) ~= "" and not meta.page then
    return den.ui.toast("That is not a Hackdex hack page: hackdex.app/hack/<name>")
  end
  set_meta(id, meta)
  local hack = hack_of(id)
  if hack then
    den.ui.set(pages.hack(hack, meta, game_of(hack.base), date_text(hack.installed)))
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
  set_meta(id, nil)
  back_home(1)
end

-- A patch file for an installed hack: checked against the hack's base game, then offered.
local function begin_update(hack, path, pushed)
  local info = inspect(path)
  if not info then
    return
  end
  if info.source_crc32 then
    local base = den.library.find{ crc32 = info.source_crc32, size = info.source_size }
    if not base or base.id ~= hack.base then
      den.files.remove(path)
      return den.ui.toast("This patch is for another base game than " .. hack.name .. ".")
    end
  elseif not game_of(hack.base) then
    den.files.remove(path)
    return den.ui.toast("The base game of " .. hack.name .. " is no longer in your library.")
  end
  local name = path:match("([^/]+)$") or path
  local _, version = title_of(name)
  update = { hack = hack, path = path, name = name, info = info, version = version,
             pushed = pushed + 1 }
  push(pages.update(update))
end

function plugin.actions.update(id)
  local hack = hack_of(id)
  local path = hack and den.files.import{ title = "Choose the newer patch file" }
  if path then
    begin_update(hack, path, 1)
  end
end

function plugin.actions.update_from(arg)
  local hack = type(arg) == "table" and hack_of(arg.id)
  if not hack then
    return
  end
  local path, why = den.files.take(arg.token)
  if not path then
    return den.ui.toast(why)
  end
  begin_update(hack, path, 1)
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
  local hack, meta = update.hack, metas()[update.hack.id] or {}
  den.ui.patch("status", { label = "Patching", fraction = -1 })
  local made, why = den.patch.apply{
    patch = update.path, game = hack.base, title = hack.name, version = update.version,
    description = meta.description, source = meta.page or "file", keep_old = keep_old == true,
  }
  if not made then
    den.ui.patch("status", { label = why, fraction = 0 })
    return den.ui.toast(why)
  end
  meta.patch = update.name
  set_meta(made.game.id, meta)
  den.files.remove(update.path)
  local pushed = update.pushed
  update = nil
  tab = "installed"
  back_home(pushed)
  den.ui.toast("Updated " .. made.game.name .. ".")
end

-- Patch files in Downloads whose name starts like an installed hack and that are not the
-- file it was installed from.
function plugin.actions.updates()
  local hacks, all = den.library.hacks() or {}, metas()
  local found = {}
  for _, file in ipairs(den.files.inbox() or {}) do
    local name = plain(title_of(file.name))
    for _, hack in ipairs(hacks) do
      local title = plain(hack.name)
      local meta = all[hack.id] or {}
      if title ~= "" and name:sub(1, #title) == title and meta.patch ~= file.name then
        found[#found + 1] = { hack = hack, file = file }
      end
    end
  end
  push(pages.updates(found, hacks, all))
end

return plugin
