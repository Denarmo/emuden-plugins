-- SPDX-FileCopyrightText: Copyright 2026 EmuDEN contributors
-- SPDX-License-Identifier: GPL-3.0-or-later

-- RetroAchievements: the sign-in, the settings, the user's profile and the progress of each
-- game. The achievements themselves are checked by EmuDEN's player while a game runs
-- (den.achievements, docs/feature-plugins.md section 4.3 of the app); this script is their
-- pages. The password typed here goes to RetroAchievements once and is not kept: the app
-- keeps the token that comes back, in this plugin's secrets.

local plugin = { actions = {} }

local user_name = ""   -- typed on the page
local password = nil   -- held only until the sign-in
local message = nil    -- the last error, shown on the first page
local system_shown = nil

local SYSTEMS = {
  { "gb", "Game Boy" }, { "gbc", "Game Boy Color" }, { "gba", "Game Boy Advance" },
  { "nds", "Nintendo DS" }, { "nes", "NES" }, { "snes", "Super Nintendo" }, { "n64", "Nintendo 64" },
  { "gamecube", "GameCube" }, { "wii", "Wii" }, { "virtualboy", "Virtual Boy" },
  { "pokemini", "Pokemon Mini" }, { "psx", "PlayStation" }, { "ps2", "PlayStation 2" },
  { "psp", "PSP" }, { "genesis", "Mega Drive / Genesis" }, { "sms", "Master System" },
  { "gg", "Game Gear" }, { "32x", "32X" }, { "sg1000", "SG-1000" }, { "saturn", "Saturn" },
  { "dreamcast", "Dreamcast" }, { "pce", "PC Engine" }, { "atari2600", "Atari 2600" },
  { "atari5200", "Atari 5200" }, { "atari7800", "Atari 7800" }, { "jaguar", "Jaguar" },
  { "lynx", "Lynx" }, { "ngp", "Neo Geo Pocket" }, { "ngpc", "Neo Geo Pocket Color" },
  { "msx", "MSX" }, { "vectrex", "Vectrex" }, { "wonderswan", "WonderSwan" },
  { "wsc", "WonderSwan Color" }, { "arcade", "Arcade" },
}

local function system_name(id)
  for _, s in ipairs(SYSTEMS) do
    if s[1] == id then return s[2] end
  end
  return id
end

local function on_off(value)
  return value and "On" or "Off"
end

local function number(n)
  local text = tostring(math.floor(tonumber(n) or 0))
  local out = text:reverse():gsub("(%d%d%d)", "%1,"):reverse()
  return (out:gsub("^,", ""))
end

local function signed_out_page(status)
  local body = {}
  if message then
    body[#body + 1] = { type = "text", id = "message", style = "warning", text = message }
  end
  if status.signing_in then
    body[#body + 1] = { type = "progress", id = "signing", label = "Signing in", fraction = -1 }
    return { title = "RetroAchievements", subtitle = "Signing in", body = body }
  end
  body[#body + 1] = { type = "text", style = "body", text =
      "Earn achievements in your games while you play. Sign in with your RetroAchievements " ..
      "account: EmuDEN keeps the sign-in token RetroAchievements gives it, never your password." }
  body[#body + 1] = { type = "input", id = "user", label = "User name", value = user_name,
                      action = "set_user" }
  body[#body + 1] = { type = "input", id = "password", label = "Password", value = "",
                      action = "set_password", secret = true }
  body[#body + 1] = { type = "button", id = "sign_in", label = "Sign in", action = "sign_in" }
  body[#body + 1] = { type = "text", style = "caption", text =
      "No account yet? Make one on retroachievements.org, then sign in here." }
  body[#body + 1] = { type = "row", id = "about", label = "About", action = "about" }
  return { title = "RetroAchievements", subtitle = "Not signed in", body = body }
end

local function home_page()
  local status = den.achievements.status()
  if not status.signed_in then
    return signed_out_page(status)
  end
  message = nil
  local user = status.user
  local body = {}
  body[#body + 1] = { type = "detail", id = "profile", title = user.display_name,
    image = user.avatar ~= "" and user.avatar or nil, aspect = 1,
    facts = {
      { label = "Hardcore points", value = number(user.score) },
      { label = "Softcore points", value = number(user.softcore_score) },
      { label = "Unread messages", value = number(user.messages) },
    },
    buttons = {
      { type = "button", id = "games", label = "Your games", action = "games" },
    } }
  if status.playing ~= "" then
    body[#body + 1] = { type = "row", id = "playing", label = "Now playing", value = "Progress",
                        action = "game", arg = status.playing }
  end
  body[#body + 1] = { type = "text", style = "heading", text = "While you play" }
  body[#body + 1] = { type = "row", id = "hardcore", label = "Hardcore mode", value = on_off(status.hardcore),
                      action = "toggle", arg = "hardcore" }
  body[#body + 1] = { type = "text", style = "caption", text =
      "Hardcore counts unlocks as hardcore on your profile. As RetroAchievements requires, " ..
      "loading save states, rewind, cheats and slow motion are off then, and a game that is " ..
      "running starts again when you turn it on." }
  body[#body + 1] = { type = "row", id = "sound", label = "Sound on unlock", value = on_off(status.sound),
                      action = "toggle", arg = "sound" }
  body[#body + 1] = { type = "row", id = "screenshot", label = "Screenshot on unlock",
                      value = on_off(status.screenshot), action = "toggle", arg = "screenshot" }
  body[#body + 1] = { type = "text", style = "caption", text =
      "Your progress is kept by RetroAchievements, so every device you sign in on shows it." }
  body[#body + 1] = { type = "button", id = "sign_out", label = "Sign out", action = "sign_out" }
  body[#body + 1] = { type = "row", id = "about", label = "About", action = "about" }
  return { title = "RetroAchievements", subtitle = "Signed in as " .. user.name, body = body }
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

local function games_page()
  local by_system = {}
  for _, game in ipairs(den.library.games{} or {}) do
    if not game.hack_of then
      by_system[game.system] = by_system[game.system] or {}
      table.insert(by_system[game.system], game)
    end
  end
  local chips = {}
  for _, s in ipairs(SYSTEMS) do
    if by_system[s[1]] then
      system_shown = system_shown or s[1]
      chips[#chips + 1] = { id = s[1], label = s[2], selected = s[1] == system_shown }
    end
  end
  local body = {}
  local games = by_system[system_shown or ""] or {}
  table.sort(games, function(a, b) return a.name:lower() < b.name:lower() end)
  for i, game in ipairs(games) do
    if i > 300 then break end
    body[#body + 1] = { type = "row", id = "game." .. game.id, label = game.name, image = "game:" .. game.id,
                        action = "game", arg = game.id }
  end
  if #body == 0 then
    body[1] = { type = "empty", title = "No games of these consoles",
                text = "Add games of a console RetroAchievements covers to your library." }
  end
  return { title = "Your games", subtitle = system_shown and system_name(system_shown) or nil,
           chips = #chips > 0 and { action = "system", items = chips } or nil, body = body }
end

local function game_page(game)
  local body = {}
  if game.note ~= "" then
    body[#body + 1] = { type = "text", style = game.ra_id == 0 and "warning" or "body", text = game.note }
  end
  if game.ra_id ~= 0 then
    body[#body + 1] = { type = "detail", id = "game", title = game.title,
      image = game.image ~= "" and game.image or "game:" .. game.id, aspect = 1,
      facts = {
        { label = "Unlocked", value = string.format("%d of %d", game.unlocked, game.total) },
        { label = "Points", value = string.format("%s of %s", number(game.points_unlocked), number(game.points_total)) },
        { label = "Mode", value = game.hardcore and "Hardcore" or "Softcore" },
      },
      buttons = {} }
    if game.total > 0 then
      body[#body + 1] = { type = "progress", id = "progress", label = game.mastered and "Mastered" or "Progress",
                          fraction = game.unlocked / game.total }
    end
    for _, a in ipairs(game.achievements) do
      local state
      if a.unlocked then
        state = string.format("%d points, unlocked", a.points)
      elseif a.progress ~= "" then
        state = string.format("%d points, %s", a.points, a.progress)
      else
        state = string.format("%d points", a.points)
      end
      body[#body + 1] = { type = "row", id = "a." .. a.id, label = a.title, value = state,
                          image = a.badge ~= "" and a.badge or nil, action = "achievement", arg = a.id }
    end
  end
  return { title = game.name, subtitle = game.playing and "Playing now" or system_name(game.system), body = body }
end

local shown_game = nil

function plugin.open()
  den.ui.set(home_page())
end

function plugin.resume()
  if den.ui.depth() == 1 then
    den.ui.set(home_page())
  end
end

function plugin.actions.set_user(_, text)
  user_name = (text or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

function plugin.actions.set_password(_, text)
  password = text
end

function plugin.actions.sign_in()
  if user_name == "" or not password or password == "" then
    return den.ui.toast("Enter your user name and password.")
  end
  den.ui.patch("sign_in", { enabled = false })
  local pass = password
  password = nil
  local ok, why = den.achievements.sign_in{ user = user_name, password = pass }
  pass = nil
  message = not ok and why or nil
  show_home()
  if ok then
    den.ui.toast("Signed in to RetroAchievements")
  end
end

function plugin.actions.sign_out()
  local yes = den.ui.confirm{ title = "Sign out?",
    message = "EmuDEN forgets the sign-in on this device. Your achievements stay on RetroAchievements.",
    yes = "Sign out" }
  if yes then
    den.achievements.sign_out()
    show_home()
  end
end

function plugin.actions.toggle(which)
  local status = den.achievements.status()
  if which == "hardcore" and not status.hardcore and status.playing ~= "" then
    local yes = den.ui.confirm{ title = "Turn hardcore on?",
      message = "The game that is running starts again from the beginning. Progress that is not saved is lost.",
      yes = "Turn on" }
    if not yes then return end
  end
  local change = {}
  change[which] = not status[which]
  den.achievements.set(change)
  den.ui.set(home_page())
end

function plugin.actions.games()
  show(games_page())
end

function plugin.actions.system(_, chosen)
  if type(chosen) == "string" and chosen ~= "" then
    system_shown = chosen:match("^[^,]+")
  end
  den.ui.set(games_page())
end

function plugin.actions.game(id)
  local page = { title = "Progress", body = { { type = "progress", id = "loading", label = "Asking RetroAchievements", fraction = -1 } } }
  den.ui.push(page)
  local game, why = den.achievements.game(id)
  if not game then
    den.ui.set({ title = "Progress", body = { { type = "text", style = "warning", text = why } } })
    return
  end
  for _, g in ipairs(den.library.games{} or {}) do
    if g.id == id then game.system = g.system end
  end
  shown_game = game
  den.ui.set(game_page(game))
end

function plugin.actions.achievement(id)
  if not shown_game then return end
  for _, a in ipairs(shown_game.achievements) do
    if a.id == id then
      local facts = { { label = "Points", value = tostring(a.points) } }
      if a.rarity and a.rarity > 0 then
        facts[#facts + 1] = { label = "Players who have it", value = string.format("%.1f%%", a.rarity) }
      end
      if a.progress ~= "" then
        facts[#facts + 1] = { label = "Progress", value = a.progress }
      end
      facts[#facts + 1] = { label = "State", value = a.unlocked and "Unlocked" or "Locked" }
      return den.ui.push({ title = a.title, body = { { type = "detail", title = a.title,
        image = a.badge ~= "" and a.badge or nil, aspect = 1, facts = facts, text = a.description,
        buttons = {} } } })
    end
  end
end

function plugin.actions.about()
  show({ title = "About", body = {
    { type = "text", style = "body", text =
      "Achievements come from RetroAchievements.org, made by its community. EmuDEN identifies " ..
      "the game you start by the same hash RetroAchievements uses, checks the achievements " ..
      "against the game's memory while it runs, and sends unlocks to RetroAchievements with " ..
      "your sign-in token." },
    { type = "text", style = "body", text =
      "Achievements are made for particular dumps of a game: a different version (a hack, a " ..
      "translation, another region) may have none. Games that run in an emulator app outside " ..
      "EmuDEN, and consoles RetroAchievements does not cover, have no achievements here." },
    { type = "text", style = "body", text =
      "Your password is sent to RetroAchievements once, over https, and is not kept. Signing " ..
      "out, or removing this plugin with its data, deletes the token." },
    { type = "text", style = "caption", text = "Not affiliated with RetroAchievements.org." },
  } })
end

return plugin
