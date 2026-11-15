-- SPDX-FileCopyrightText: Copyright 2026 EmuDEN contributors
-- SPDX-License-Identifier: GPL-3.0-or-later

-- ProtonDB tuning: for a Steam game of this computer, the community reports of machines
-- closest to this one, and the Proton version and launch options they used. On SteamOS (or
-- Linux with Steam's local port on) they are set on the game after the user agreed; on
-- Windows the page only shows them. Reports come from Denarmo/protondb-reports, a copy of
-- ProtonDB's open data dump (ODbL); the rating from ProtonDB's public summary.

local rank = den.include("rank.lua")

local plugin = { actions = {} }

local DATA = "https://raw.githubusercontent.com/Denarmo/protondb-reports/main/data/apps/"
local SUMMARY = "https://www.protondb.com/api/v1/reports/summaries/"
local COVER = "https://shared.steamstatic.com/store_item_assets/steam/apps/%s/library_600x900.jpg"
local SHOWN = 8

local me, info = nil, nil
local steam = nil        -- den.steam.status()
local filter = ""
local game = nil         -- { appid, name, ranked, total, tier, config, suggestion, chosen }

local function when(t)
  if type(t) ~= "number" or t <= 0 then return "" end
  local days = (den.now() - t) // 86400
  if days < 31 then return string.format("%d days ago", math.max(days, 0)) end
  if days < 365 then return string.format("%d months ago", days // 30) end
  return string.format("%.1f years ago", days / 365)
end

local OS_NAMES = { windows = "Windows", linux = "Linux", macos = "macOS", android = "Android" }

local function trim(text)
  return (tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s%s+", " "))
end

local function device_line()
  local parts = { trim(info.name) ~= "" and trim(info.name) or "This device" }
  for _, part in ipairs({ trim(info.gpu), trim(info.soc) }) do
    if part ~= "" then parts[#parts + 1] = part end
  end
  if info.ram_mb and info.ram_mb > 0 then parts[#parts + 1] = string.format("%d GB", (info.ram_mb + 512) // 1024) end
  parts[#parts + 1] = info.steamos and "SteamOS"
      or (trim(info.os_name) ~= "" and trim(info.os_name) or OS_NAMES[info.os] or info.os or "")
  return table.concat(parts, " · ")
end

local function load_device()
  if info then return end
  info = den.device.info() or {}
  me = rank.me(info)
  steam = den.steam.status() or { installed = false, apps = {}, tools = {} }
end

local function home_page()
  local body = {
    { type = "text", style = "caption", text = device_line() },
  }
  if not steam.installed then
    body[#body + 1] = { type = "empty", title = "No Steam here", text = steam.note }
    return { title = "ProtonDB", body = body }
  end
  if me.windows then
    body[#body + 1] = { type = "text", style = "caption", text =
        "On Windows games run without Proton: this page shows what the reports say, and only the game's own launch arguments apply here." }
  elseif not steam.can_change then
    body[#body + 1] = { type = "text", style = "warning", text = steam.note }
  end
  local shown = 0
  for _, app in ipairs(steam.apps) do
    if not app.shortcut and (filter == "" or app.name:lower():find(filter:lower(), 1, true)) then
      body[#body + 1] = { type = "row", id = "app-" .. app.appid, label = app.name, value = "Reports",
                          action = "game", arg = app.appid }
      shown = shown + 1
    end
  end
  if shown == 0 then
    body[#body + 1] = { type = "empty", title = "No Steam games", text = "Install a game in Steam, then open this page again." }
  end
  body[#body + 1] = { type = "text", style = "caption", text =
      "Reports: ProtonDB (protondb.com) community data, under the Open Database License." }
  return { title = "ProtonDB", subtitle = "Settings from players with machines like yours",
           search = { placeholder = "Find a game", value = filter, action = "search" }, body = body }
end

local function fetch_reports(appid)
  local folder = string.format("%02d", tonumber(appid:sub(-2)) or 0)
  local answer, why = den.http.get{ url = DATA .. folder .. "/" .. appid .. ".json", cache_seconds = 7 * 86400 }
  if not answer then return nil, why end
  if answer.status == 404 then return { reports = {}, total = 0 } end
  if answer.status ~= 200 then return nil, "the report data answered " .. answer.status end
  return den.json.decode(answer.body) or { reports = {}, total = 0 }
end

local function fetch_tier(appid)
  local answer = den.http.get{ url = SUMMARY .. appid .. ".json", cache_seconds = 86400 }
  if answer and answer.status == 200 then
    local summary = den.json.decode(answer.body)
    return summary and summary.tier
  end
  return nil
end

local function report_text(entry)
  local r = entry.report
  local lines = {}
  local proton = r.custom_proton or r.proton
  if proton then lines[#lines + 1] = "Proton: " .. proton end
  if r.launch then lines[#lines + 1] = "Launch options: " .. r.launch end
  if r.faults then lines[#lines + 1] = "Problems: " .. table.concat(r.faults, ", ") end
  if r.notes then lines[#lines + 1] = r.notes end
  return table.concat(lines, "\n")
end

-- What Apply would change, against what Steam has now.
local function changes()
  local s, config, out = game.suggestion, game.config or {}, {}
  if s.tool and not me.windows and s.tool.name ~= config.compat_tool then
    out.compat_tool = s.tool.name
  end
  local launch = s.launch
  if me.windows then launch = rank.windows_args(launch) end
  if launch and launch ~= config.launch_options then
    out.launch_options = launch
  end
  return out
end

local function game_page()
  local s, config = game.suggestion, game.config or {}
  local facts = {
    { label = "ProtonDB rating", value = game.tier and (game.tier:sub(1, 1):upper() .. game.tier:sub(2)) or "Not rated" },
    { label = "Reports", value = string.format("%d (%d kept, closest first)", game.total or 0, #game.ranked) },
    { label = "Proton now", value = config.compat_tool_display ~= "" and config.compat_tool_display
                                     or (config.compat_tool ~= "" and config.compat_tool or "Steam's choice") },
    { label = "Launch options now", value = (config.launch_options or "") ~= "" and config.launch_options or "None" },
  }
  local body = {}
  local change = changes()
  local buttons = {}
  local lines = {}
  if s.tool and me.windows then
    lines[#lines + 1] = "Reports used " .. s.tool.display
  elseif s.tool then
    lines[#lines + 1] = "Proton: " .. s.tool.display
        .. (s.tool.installed and "" or (s.tool.official and " (Steam downloads it)" or " (not installed)"))
  end
  local launch = me.windows and rank.windows_args(s.launch) or s.launch
  if launch then lines[#lines + 1] = "Launch options: " .. launch end
  if s.from then
    lines[#lines + 1] = string.format("From %s, %s (match %d%%)", rank.describe(s.from.report), when(s.from.report.t), s.from.score)
  end
  if #lines == 0 then
    lines[1] = #game.ranked == 0 and "There are no reports for this game yet."
        or "The closest working reports change nothing: the game runs with Steam's default."
  end
  local can_apply = steam.can_change and next(change) ~= nil and not (s.tool and not s.tool.installed and not s.tool.official and change.compat_tool)
  if can_apply then
    buttons[#buttons + 1] = { label = "Apply", action = "apply" }
  end
  local undo = den.storage.get("undo:" .. game.appid)
  if undo and steam.can_change then
    buttons[#buttons + 1] = { label = "Undo", action = "undo" }
  end
  if game.chosen then
    buttons[#buttons + 1] = { label = "Best match", action = "choose", arg = 0 }
  end
  body[#body + 1] = { type = "detail", id = "game", title = game.name, subtitle = "Suggested for " .. me.name,
                      image = string.format(COVER, game.appid), aspect = 0.667,
                      facts = facts, text = table.concat(lines, "\n"), buttons = buttons }
  if next(change) == nil and #game.ranked > 0 and (s.tool or s.launch) then
    body[#body + 1] = { type = "text", style = "caption", text = "Steam already has these settings." }
  elseif me.windows and next(change) ~= nil then
    body[#body + 1] = { type = "text", style = "caption", text =
        "Enter them in Steam: the game's Properties > General > Launch options." }
  elseif not steam.can_change and next(change) ~= nil then
    body[#body + 1] = { type = "text", style = "warning", text = steam.note }
  end
  if s.tool and not s.tool.installed and not s.tool.official and not me.windows then
    body[#body + 1] = { type = "text", style = "warning", text =
        s.tool.display .. " is not installed. Install it (ProtonUp-Qt, or Decky's Wine Cellar), then open this game again." }
  end
  if #game.ranked > 0 then
    body[#body + 1] = { type = "text", style = "heading", text = "Closest reports" }
  end
  local function add(i)
    local entry = game.ranked[i]
    local r = entry.report
    body[#body + 1] = { type = "row", id = "report-" .. i,
                        label = string.format("%s · %s · %s", rank.describe(r), r.verdict == "yes" and "Works" or "Does not work", when(r.t)),
                        value = string.format("%d%%", entry.score), action = "choose", arg = i }
    local why = #entry.why > 0 and ("Close by: " .. table.concat(entry.why, ", ") .. "\n") or ""
    body[#body + 1] = { type = "text", style = "caption", text = why .. report_text(entry) }
  end
  for i = 1, math.min(SHOWN, #game.ranked) do
    add(i)
  end
  -- Most reports name no Proton version and no launch options: the closest ones that do.
  local more = 0
  for i = SHOWN + 1, #game.ranked do
    local r = game.ranked[i].report
    if more < SHOWN and r.verdict == "yes" and (r.proton or r.custom_proton or rank.launch_for(me, r)) then
      if more == 0 then
        body[#body + 1] = { type = "text", style = "heading", text = "Reports with settings" }
      end
      add(i)
      more = more + 1
    end
  end
  body[#body + 1] = { type = "text", style = "caption", text =
      "Choose a report to use its settings. Data: ProtonDB contributors, Open Database License." }
  return { title = game.name, body = body }
end

local function suggest()
  game.suggestion = rank.suggest(me, game.ranked, steam.tools, game.chosen and game.ranked[game.chosen])
end

function plugin.open()
  den.ui.set{ title = "ProtonDB", busy = true, body = {} }
  load_device()
  den.ui.set(home_page())
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
  den.ui.push{ title = name, busy = true, body = { { type = "progress", label = "Reading reports", fraction = -1 } } }
  local data, why = fetch_reports(appid)
  if not data then
    den.ui.set{ title = name, body = { { type = "empty", title = "The reports could not be read", text = why } } }
    return
  end
  game = { appid = appid, name = name, total = data.total or #(data.reports or {}),
           ranked = rank.rank(me, data.reports or {}, den.now()), tier = fetch_tier(appid) }
  game.config = den.steam.config(appid) or { launch_options = "", compat_tool = "", compat_tool_display = "" }
  suggest()
  den.ui.set(game_page())
end

function plugin.actions.choose(index)
  if not game then return end
  game.chosen = (index and index > 0) and index or nil
  suggest()
  den.ui.set(game_page())
end

function plugin.actions.apply()
  if not game then return end
  local change = changes()
  if next(change) == nil then return end
  -- A tool Steam picked by itself is given back to Steam on Undo, not pinned.
  local before = { launch_options = game.config.launch_options or "",
                   compat_tool = game.config.compat_tool_chosen and game.config.compat_tool or "" }
  local ok, why = den.steam.set{ appid = game.appid, name = game.name,
                                 launch_options = change.launch_options, compat_tool = change.compat_tool }
  if not ok then
    if why ~= "cancelled" then den.ui.toast(why) end
    return
  end
  if not den.storage.get("undo:" .. game.appid) then
    den.storage.set("undo:" .. game.appid, before)
  end
  game.config = den.steam.config(game.appid) or game.config
  den.ui.toast("Set in Steam. Start the game from Steam to use it.")
  den.ui.set(game_page())
end

function plugin.actions.undo()
  if not game then return end
  local before = den.storage.get("undo:" .. game.appid)
  if not before then return end
  local ok, why = den.steam.set{ appid = game.appid, name = game.name,
                                 launch_options = before.launch_options, compat_tool = before.compat_tool }
  if not ok then
    if why ~= "cancelled" then den.ui.toast(why) end
    return
  end
  den.storage.remove("undo:" .. game.appid)
  game.config = den.steam.config(game.appid) or game.config
  den.ui.toast("Steam has the game's earlier settings again.")
  den.ui.set(game_page())
end

return plugin
