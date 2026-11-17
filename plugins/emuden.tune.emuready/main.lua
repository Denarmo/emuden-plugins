-- SPDX-FileCopyrightText: Copyright 2026 EmuDEN contributors
-- SPDX-License-Identifier: GPL-3.0-or-later

-- EmuReady tuning: for a game of the library, the EmuReady compatibility listings of the
-- devices closest to this one (the same device, the same chip, then similar graphics), and
-- their settings mapped onto the core options of the core EmuDEN plays the game with. Apply
-- sets them for this game only, after EmuDEN asked; Undo puts the old values back.
-- EmuReady's public mobile API (emuready.com/docs/api): 100 requests in 3 minutes, so every
-- answer is cached.

local match = den.include("match.lua")

local plugin = { actions = {} }

local API = "https://www.emuready.com/api/mobile/trpc/"
local DAY = 86400
local SHOWN = 8

local info, me = nil, nil
local filter = ""
local current = nil  -- { game, settings, er_game, ranked, chosen, details = {}, changes }
local candidates = nil

local SYSTEM_NAMES = {
  ps2 = "PlayStation 2", psp = "PSP", psx = "PlayStation", nds = "Nintendo DS", n64 = "Nintendo 64",
  gamecube = "GameCube", wii = "Wii", dreamcast = "Dreamcast", saturn = "Saturn",
}

local escape = den.include("urlencode.lua")

-- JSON null becomes nil, so a missing chip or rating reads like an absent field.
local function strip_nulls(value, depth)
  if type(value) ~= "table" or (depth or 0) > 20 then return value end
  for key, item in pairs(value) do
    if item == den.json.null then
      value[key] = nil
    else
      strip_nulls(item, (depth or 0) + 1)
    end
  end
  return value
end

local function call(procedure, input, cache_seconds)
  local url = API .. procedure
  if input then url = url .. "?input=" .. escape(den.json.encode({ json = input })) end
  local answer, why = den.http.get{ url = url, cache_seconds = cache_seconds or DAY }
  if not answer then return nil, why end
  if answer.status == 429 then return nil, "EmuReady asks to wait a little; try again in a few minutes." end
  if answer.status ~= 200 then return nil, den.tr("EmuReady answered {}", tostring(answer.status)) end
  local body = den.json.decode(answer.body)
  local data = body and body.result and body.result.data
  if not data then return nil, "EmuReady's answer could not be read" end
  return strip_nulls(data.json)
end

local function when(t)
  if not t then return "" end
  local days = (den.now() - t) // DAY
  if days < 31 then return den.tr("{} days ago", string.format("%d", math.max(days, 0))) end
  if days < 365 then return den.tr("{} months ago", string.format("%d", days // 30)) end
  return den.tr("{} years ago", string.format("%.1f", days / 365))
end

-- This device as EmuReady knows it: its entry, chip and graphics (cached for a month).
local function load_device()
  if me then return end
  info = den.device.info() or {}
  local entry, soc = nil, nil
  local wanted = match.plain(info.name)
  for _, search in ipairs({ info.model, info.name }) do
    if not entry and search and search ~= "" then
      local found = call("devices.get", { search = search:gsub("^Retroid ", ""):gsub("^AYN ", ""), limit = 50 }, 30 * DAY)
      for _, device in ipairs(found and found.devices or {}) do
        if match.plain((device.brandName or "") .. " " .. (device.modelName or "")) == wanted then entry = device end
      end
    end
  end
  if entry and entry.socName then
    local socs = call("devices.socs", { limit = 500 }, 30 * DAY)
    for _, item in ipairs(type(socs) == "table" and socs or {}) do
      if item.name == entry.socName then
        soc = call("socs.getById", { id = item.id }, 30 * DAY)
      end
    end
  end
  me = match.me(info, entry, soc)
  me.listed = entry ~= nil
end

local function device_line()
  local parts = { me.name }
  if me.soc and me.soc ~= "" then parts[#parts + 1] = me.soc end
  if me.gpu and me.gpu ~= "" then parts[#parts + 1] = me.gpu end
  return table.concat(parts, " · ")
end

local function supported_games()
  local out = {}
  for _, game in ipairs(den.library.games{} or {}) do
    if match.SYSTEMS[game.system] and not game.hack_of then out[#out + 1] = game end
  end
  table.sort(out, function(a, b) return a.name:lower() < b.name:lower() end)
  return out
end

local function home_page()
  local body = { { type = "text", style = "caption", text = device_line() } }
  if not me.listed then
    body[#body + 1] = { type = "text", style = "caption", text =
        "EmuReady has no entry for this device; listings of devices with similar graphics are used." }
  end
  local shown = 0
  for _, game in ipairs(supported_games()) do
    if filter == "" or game.name:lower():find(filter:lower(), 1, true) then
      body[#body + 1] = { type = "row", id = "game-" .. game.id, label = game.name,
                          value = SYSTEM_NAMES[game.system] or game.system, action = "game", arg = game.id }
      shown = shown + 1
    end
  end
  if shown == 0 then
    body[#body + 1] = { type = "empty", title = "No games to tune",
                        text = "Add PlayStation, PSP, DS, N64, GameCube, Wii, Dreamcast or Saturn games to the library." }
  end
  body[#body + 1] = { type = "text", style = "caption", text = "Listings: EmuReady (emuready.com) community reports." }
  return { title = "EmuReady", subtitle = "Settings from players with devices like yours",
           search = { placeholder = "Find a game", value = filter, action = "search" }, body = body }
end

local function system_id(system)
  local key = match.SYSTEMS[system]
  for _, item in ipairs(call("general.systems", nil, 30 * DAY) or {}) do
    if item.key == key then return item.id end
  end
  return nil
end

-- The games of the first search that finds any.
local function search_games(name, system)
  for _, search in ipairs(match.searches(name)) do
    local found, why = call("games.get", { search = search, systemId = system_id(system), limit = 10 }, 7 * DAY)
    if not found then return nil, why end
    if #(found.games or {}) > 0 then return found.games end
  end
  return {}
end

local function find_game(game)
  local saved = den.storage.get("match:" .. game.id)
  if saved then return saved end
  local found, why = search_games(game.name, game.system)
  if not found then return nil, why end
  candidates = found
  local same = match.same_game(game.name, candidates)
  if same then
    local chosen = { id = same.id, title = same.title }
    den.storage.set("match:" .. game.id, chosen)
    return chosen
  end
  return nil
end

local function details(entry)
  if entry.details == nil then
    entry.details = call("listings.byId", { id = entry.listing.id }, 7 * DAY) or false
  end
  return entry.details or nil
end

local function core_unknown()
  return current.settings and not current.settings.known
end

local function refresh_changes()
  current.changes = {}
  current.source = nil
  if not current.ranked or #current.ranked == 0 or not current.settings then return end
  local entry = current.ranked[current.chosen or 1]
  local d = details(entry)
  current.source = entry
  current.changes = d and match.changes(current.settings, d.customFieldValues) or {}
end

local function listing_line(entry)
  local l = entry.listing
  local soc = l.device and l.device.soc and l.device.soc.name
  return string.format("%s%s · %s · %s · %s", match.device_name(l), soc and (" (" .. soc .. ")") or "",
                       l.emulator and l.emulator.name or "?", l.performance and l.performance.label or "?",
                       when(match.time(l.createdAt)))
end

local function game_page()
  local g, s = current.game, current.settings or {}
  local undo = den.storage.get("undo:" .. g.id)
  local lines = {}
  for _, change in ipairs(current.changes or {}) do
    lines[#lines + 1] = string.format("%s: %s -> %s", den.tr(change.label), change.from ~= "" and change.from or den.tr("default"), change.to)
  end
  local source -- its own block below, so the page's outcome is never cut off
  if current.source then
    local d = current.source.details
    local said = d and match.settings_text(d.customFieldValues) or ""
    source = den.tr("From {} (match {}%)", listing_line(current.source), string.format("%d", current.source.score))
        .. (said ~= "" and ("\n" .. den.tr("It used {}", said)) or "")
  end
  if #(current.ranked or {}) == 0 then
    lines[#lines + 1] = den.tr("EmuReady has no listings for this game yet.")
  elseif #(current.changes or {}) == 0 and not core_unknown() then
    lines[#lines + 1] = den.tr("Nothing to change: the listing's settings are what {} uses already, or it gives none EmuDEN's core has.",
                               s.core_name or den.tr("the core"))
  end
  local buttons = {}
  if #(current.changes or {}) > 0 and not core_unknown() then
    buttons[#buttons + 1] = { label = "Apply", action = "apply" }
  end
  if undo then buttons[#buttons + 1] = { label = "Undo", action = "undo" } end
  if current.chosen then buttons[#buttons + 1] = { label = "Best match", action = "choose", arg = 0 } end
  buttons[#buttons + 1] = { label = "Another EmuReady game", action = "rematch" }
  local body = {
    { type = "detail", id = "game", title = g.name, subtitle = den.tr("Suggested for {}", me.name), image = "game:" .. g.id,
      facts = { { label = "Core", value = s.core_name or "None" },
                { label = "EmuReady game", value = current.er_game.title },
                { label = "Listings", value = tostring(#(current.ranked or {})) } },
      text = table.concat(lines, "\n"), buttons = buttons },
  }
  if source then body[#body + 1] = { type = "text", text = source } end
  if core_unknown() then
    body[#body + 1] = { type = "text", style = "warning", text = den.tr(
        "Start {} once, so EmuDEN learns the options of {}; then come back to apply these.", g.name, s.core_name or den.tr("its core")) }
  end
  if #(current.ranked or {}) > 0 then
    body[#body + 1] = { type = "text", style = "heading", text = "Closest listings" }
  end
  for i = 1, math.min(SHOWN, #(current.ranked or {})) do
    local entry = current.ranked[i]
    body[#body + 1] = { type = "row", id = "listing-" .. i, label = listing_line(entry),
                        value = string.format("%d%%", entry.score), action = "choose", arg = i }
    local notes = entry.listing.notes and entry.listing.notes ~= "" and entry.listing.notes or nil
    local reasons = {}
    for k, reason in ipairs(entry.why) do reasons[k] = den.tr(reason) end
    local why = #reasons > 0 and den.tr("Close by: {}", table.concat(reasons, ", ")) or nil
    local text = table.concat({ why or "", notes or "" }, why and notes and "\n" or "")
    if text ~= "" then body[#body + 1] = { type = "text", style = "caption", text = text } end
  end
  body[#body + 1] = { type = "text", style = "caption", text =
      "Choose a listing to use its settings. Listings: EmuReady contributors (emuready.com)." }
  return { title = g.name, body = body }
end

local function choice_page(game)
  local body = { { type = "text", text = den.tr("Which EmuReady game is {}?", game.name) } }
  for i, item in ipairs(candidates or {}) do
    body[#body + 1] = { type = "row", id = "pick-" .. i, label = item.title,
                        value = den.tr("{} listings", string.format("%d", item._count and item._count.listings or 0)),
                        action = "pick", arg = i }
  end
  if not candidates or #candidates == 0 then
    body[#body + 1] = { type = "empty", title = "EmuReady has no game of this name" }
  end
  body[#body + 1] = { type = "input", id = "name", label = "Search EmuReady for", value = game.name, action = "research" }
  return { title = game.name, body = body }
end

local function show_game(game, er_game)
  den.ui.set{ title = game.name, busy = true, body = { { type = "progress", label = "Reading EmuReady", fraction = -1 } } }
  local listings, why = call("listings.get", { gameIds = { er_game.id }, limit = 50, page = 1 }, DAY / 2)
  if not listings then
    den.ui.set{ title = game.name, body = { { type = "empty", title = "EmuReady could not be read", text = why } } }
    return
  end
  current = { game = game, er_game = er_game, settings = den.game.settings(game.id) }
  current.ranked = match.rank(me, listings.listings or {}, current.settings and current.settings.core, den.now())
  refresh_changes()
  den.ui.set(game_page())
end

function plugin.open()
  den.ui.set{ title = "EmuReady", busy = true, body = {} }
  load_device()
  den.ui.set(home_page())
end

function plugin.actions.search(_, value)
  filter = value or ""
  den.ui.set(home_page())
end

local function library_game(id)
  for _, game in ipairs(den.library.games{} or {}) do
    if game.id == id then return game end
  end
  return nil
end

function plugin.actions.game(id)
  local game = library_game(id)
  if not game then return end
  if den.ui.depth() > 1 then den.ui.pop() end
  den.ui.push{ title = game.name, busy = true, body = { { type = "progress", label = "Finding the game", fraction = -1 } } }
  local er_game, why = find_game(game)
  if er_game then return show_game(game, er_game) end
  if why then
    den.ui.set{ title = game.name, body = { { type = "empty", title = "EmuReady could not be read", text = why } } }
    return
  end
  current = { game = game }
  den.ui.set(choice_page(game))
end

function plugin.actions.pick(index)
  local item = candidates and candidates[index]
  if not item or not current then return end
  local chosen = { id = item.id, title = item.title }
  den.storage.set("match:" .. current.game.id, chosen)
  show_game(current.game, chosen)
end

function plugin.actions.research(_, value)
  if not current or not value or value == "" then return end
  candidates = search_games(value, current.game.system) or {}
  den.ui.set(choice_page(current.game))
end

function plugin.actions.rematch()
  if not current then return end
  den.storage.remove("match:" .. current.game.id)
  plugin.actions.research(nil, current.game.name:gsub("%b()", ""):gsub("%s+$", ""))
end

function plugin.actions.choose(index)
  if not current or not current.ranked then return end
  current.chosen = (index and index > 0) and index or nil
  refresh_changes()
  den.ui.set(game_page())
end

function plugin.actions.apply()
  if not current or #(current.changes or {}) == 0 then return end
  local values = {}
  for _, change in ipairs(current.changes) do values[change.key] = change.to end
  local before, why = den.game.set(current.game.id, values)
  if not before then
    if why ~= "cancelled" then den.ui.toast(why) end
    return
  end
  if not den.storage.get("undo:" .. current.game.id) then
    den.storage.set("undo:" .. current.game.id, before)
  end
  current.settings = den.game.settings(current.game.id)
  refresh_changes()
  den.ui.toast(den.tr("Set for {}. It takes effect the next time it starts.", current.game.name))
  den.ui.set(game_page())
end

function plugin.actions.undo()
  if not current then return end
  local before = den.storage.get("undo:" .. current.game.id)
  if not before then return end
  local ok, why = den.game.set(current.game.id, before)
  if not ok then
    if why ~= "cancelled" then den.ui.toast(why) end
    return
  end
  den.storage.remove("undo:" .. current.game.id)
  current.settings = den.game.settings(current.game.id)
  refresh_changes()
  den.ui.toast(den.tr("{} has its earlier settings again.", current.game.name))
  den.ui.set(game_page())
end

return plugin
