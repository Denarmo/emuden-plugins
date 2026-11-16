-- SPDX-FileCopyrightText: Copyright 2026 EmuDEN contributors
-- SPDX-License-Identifier: GPL-3.0-or-later

-- Ranks EmuReady listings by how close their device is to this one (the same device, the
-- same SoC, then a GPU of a similar class) and maps a listing's settings onto the core
-- options of the core EmuDEN plays the game with. Plain Lua, no den calls (tests run it).

local M = {}

-- EmuDEN console id -> EmuReady system key.
M.SYSTEMS = {
  ps2 = "sony_playstation_2", psp = "sony_playstation_portable", psx = "sony_playstation",
  nds = "nintendo_ds", n64 = "nintendo_64", gamecube = "nintendo_gamecube", wii = "nintendo_wii",
  dreamcast = "sega_dreamcast", saturn = "sega_saturn",
}

-- EmuDEN core -> the EmuReady emulators whose settings mean the same.
local FAMILIES = {
  densx2 = { "Play!" }, -- DenSX2 is based on Play!
  pcsx2 = { "NethersX2", "AetherSX2", "ARMSX2", "PCSX2", "XBSX2" },
  ["psx2-ecp"] = { "NethersX2", "AetherSX2", "ARMSX2", "PCSX2", "XBSX2" },
  ppsspp = { "PPSSPP" },
  melonds = { "melonDS" }, melondsds = { "melonDS" },
  dolphin = { "Dolphin" },
  flycast = { "Flycast", "Redream" },
  pcsx_rearmed = { "DuckStation", "RetroArch" },
  mupen64plus_next = { "RetroArch", "Lemuroid" }, parallel_n64 = { "RetroArch", "Lemuroid" },
  yabause = { "Yaba Sanshiro" },
}

local function lower(text)
  return string.lower(text or "")
end

-- "Pokémon: Explorers of Sky (USA)" -> "pokemon explorers of sky".
function M.plain(title)
  local text = lower(title):gsub("%b()", " "):gsub("%b[]", " ")
  text = text:gsub("\195[\160-\166]", "a"):gsub("\195[\168-\171]", "e"):gsub("\195[\172-\175]", "i")
             :gsub("\195[\178-\182]", "o"):gsub("\195[\185-\188]", "u"):gsub("\195\177", "n")
  text = text:gsub("[^%w]+", " "):gsub("^%s+", ""):gsub("%s+$", "")
  return text
end

-- What to search EmuReady for: the plain title, then with its last words dropped, since the
-- search wants every word ("explorers of skies" finds nothing, "... explorers of" finds "Sky").
function M.searches(name)
  local words = {}
  for word in M.plain(name):gmatch("%S+") do words[#words + 1] = word end
  local out = {}
  for n = #words, math.max(1, #words - 3), -1 do
    if n == 1 and #words[1] < 4 and #words > 1 then break end
    out[#out + 1] = table.concat(words, " ", 1, n)
  end
  return out
end

-- The EmuReady game that is this one: an equal title, else nothing (the page asks).
function M.same_game(name, games)
  local wanted = M.plain(name)
  for _, game in ipairs(games or {}) do
    if M.plain(game.title) == wanted then return game end
  end
  return nil
end

-- A rough class of mobile GPUs, so a device nobody listed yet borrows from similar ones.
local ADRENO = {
  [610] = 1, [612] = 2, [613] = 2, [616] = 2, [618] = 2, [619] = 2, [620] = 3, [630] = 3, [640] = 4,
  [642] = 4, [643] = 4, [644] = 4, [650] = 5, [660] = 6, [710] = 3, [720] = 5, [722] = 5, [725] = 5,
  [730] = 6, [732] = 6, [735] = 7, [740] = 7, [750] = 8, [810] = 6, [825] = 7, [829] = 8, [830] = 9, [840] = 10,
}

function M.gpu_class(gpu)
  local text = lower(gpu)
  local adreno = tonumber(text:match("adreno[^%d]*(%d%d%d)"))
  if adreno then
    if ADRENO[adreno] then return ADRENO[adreno] end
    return math.max(1, math.min(10, (adreno // 100 - 5) * 2 + (adreno % 100) // 25))
  end
  if text:find("xclipse") then return 6 end
  local mali = text:match("mali%-?(%w+)")
  if mali then
    if mali:find("^g7[12]") or mali:find("^g6") then return mali:find("^g72") and 3 or 2 end
    if mali:find("^g7[678]") then return 4 end
    if mali:find("^g71[05]") or mali:find("^g720") or mali:find("^g925") then return 6 end
    return 2
  end
  if text:find("immortalis") then return 7 end
  if text:find("powervr") then return 1 end
  return nil
end

local function same_name(a, b)
  return a ~= nil and b ~= nil and M.plain(a) ~= "" and M.plain(a) == M.plain(b)
end

-- This device, from den.device.info() and EmuReady's entry of it (nil when it has none).
function M.me(info, entry, soc)
  info = info or {}
  return {
    name = info.name or "This device",
    soc = (entry and entry.socName) or (soc and soc.name) or info.soc,
    gpu = (soc and soc.gpuModel) or info.gpu,
    gpu_class = M.gpu_class((soc and soc.gpuModel) or info.gpu),
    cores = info.cpu_cores,
  }
end

function M.device_name(listing)
  local device = listing.device or {}
  local brand = device.brand and device.brand.name or device.brandName or ""
  return (brand ~= "" and (brand .. " ") or "") .. (device.modelName or "?")
end

-- How close a listing is, 0..100, and why. `core` is the EmuDEN core id.
function M.score(me, listing, core, now)
  local device = listing.device or {}
  local soc = device.soc or {}
  local score, why = 0, {}
  if same_name(M.device_name(listing), me.name) then
    score = score + 45
    why[#why + 1] = "same device"
  end
  if same_name(soc.name or device.socName, me.soc) then
    score = score + 25
    why[#why + 1] = "same chip"
  else
    local class = M.gpu_class(soc.gpuModel)
    if me.gpu_class and class then
      local near = math.max(0, 18 - 6 * math.abs(class - me.gpu_class))
      if near > 0 then
        score = score + near
        why[#why + 1] = class == me.gpu_class and "similar graphics" or "near graphics"
      end
    end
  end
  local family = FAMILIES[core] or {}
  local emulator = listing.emulator and listing.emulator.name or ""
  for _, name in ipairs(family) do
    if lower(name) == lower(emulator) then
      score = score + 12
      why[#why + 1] = "same emulator"
      break
    end
  end
  local rank = listing.performance and tonumber(listing.performance.rank)
  if rank then
    score = score + math.max(0, 10 - 2 * (rank - 1))
  end
  local t = M.time(listing.createdAt)
  if t and now then
    local age = (now - t) / (365 * 86400)
    if age < 2 then score = score + math.floor(8 * (1 - math.max(age, 0) / 2) + 0.5) end
  end
  return math.min(score, 100), why
end

-- "2026-09-21T05:08:23.242Z" -> Unix seconds.
function M.time(text)
  local y, mo, d, h, mi, s = tostring(text or ""):match("^(%d+)%-(%d+)%-(%d+)T(%d+):(%d+):(%d+)")
  if not y then return nil end
  y, mo, d = tonumber(y), tonumber(mo), tonumber(d)
  -- Days from the civil date (Howard Hinnant's algorithm).
  y = mo <= 2 and y - 1 or y
  local era = (y >= 0 and y or y - 399) // 400
  local yoe = y - era * 400
  local doy = (153 * (mo + (mo > 2 and -3 or 9)) + 2) // 5 + d - 1
  local doe = yoe * 365 + yoe // 4 - yoe // 100 + doy
  local days = era * 146097 + doe - 719468
  return days * 86400 + tonumber(h) * 3600 + tonumber(mi) * 60 + tonumber(s)
end

function M.rank(me, listings, core, now)
  local out = {}
  for index, listing in ipairs(listings or {}) do
    local score, why = M.score(me, listing, core, now)
    out[#out + 1] = { listing = listing, score = score, why = why, index = index }
  end
  table.sort(out, function(a, b)
    if a.score ~= b.score then return a.score > b.score end
    return a.index < b.index
  end)
  return out
end

-- What an EmuReady field is about.
local SEMANTIC = {
  resolution_scale = "resolution", upscale_multiplier = "resolution", upscale = "resolution",
  internal_resolution = "resolution", rendering_resolution = "resolution", resolution = "resolution",
  renderer = "renderer", backend = "renderer", graphics_backend = "renderer", gpu_api = "renderer",
  frame_skipping = "frameskip", frameskip = "frameskip", frame_skip = "frameskip",
  ee_cycle_rate = "ee_cycle_rate", ee_cycle_skip = "ee_cycle_skip",
  threaded_rendering = "threaded",
}

M.LABELS = { resolution = "Resolution", renderer = "Renderer", frameskip = "Frame skip",
             ee_cycle_rate = "EE cycle rate", ee_cycle_skip = "EE cycle skip", threaded = "Threaded rendering" }

-- The core option a meaning goes to: the first option whose key matches.
local TARGETS = {
  resolution = { "res_multi", "upscale_multiplier", "internal_resolution", "opengl_resolution", "render_scale",
                 "efb_scale", "resolution", "neon_enhancement_enable" },
  renderer = { "emuden_renderer", "_renderer$", "_backend$" },
  frameskip = { "frameskip$", "frameskip_interval" },
  ee_cycle_rate = { "ee_cycle_rate" },
  ee_cycle_skip = { "ee_cycle_skip" },
  threaded = { "threaded_render" },
}

local function find_option(options, meaning)
  for _, pattern in ipairs(TARGETS[meaning] or {}) do
    for _, option in ipairs(options) do
      local key = lower(option.key)
      if key:find(pattern) and not (meaning == "renderer" and key:find("thread")) then
        return option
      end
    end
  end
  return nil
end

-- The scale a choice stands for: "2x" -> 2, "x2 (1280 x 1056)" -> 2, "960x544" -> 960 / base.
local function scale_of(text, base)
  local t = lower(text)
  if t:find("native") and not t:find("%dx") and not t:find("x%d") then return 1 end
  local w = tonumber(t:match("^(%d+)%s*x%s*%d%d+"))
  if w and w >= 100 and base then return w / base end
  local n = tonumber(t:match("^x?%s*(%d+%.?%d*)%s*x?"))
  return n
end

local function choose_scale(option, wanted)
  local base
  for _, value in ipairs(option.values) do
    local w = tonumber(lower(value):match("^(%d+)%s*x%s*%d%d+"))
    if w and w >= 100 and (not base or w < base) then base = w end
  end
  local best, distance
  for _, value in ipairs(option.values) do
    local s = scale_of(value, base)
    if s and (not distance or math.abs(s - wanted) < distance) then
      best, distance = value, math.abs(s - wanted)
    end
  end
  return best
end

local function choose_word(option, words)
  for _, word in ipairs(words) do
    for _, value in ipairs(option.values) do
      if lower(value):find(word, 1, true) then return value end
    end
  end
  return nil
end

local function bool_of(value)
  local v = lower(value)
  if v == "true" or v == "1" or v == "yes" or v == "on" or v == "enabled" then return true end
  if v == "false" or v == "0" or v == "no" or v == "off" or v == "disabled" then return false end
  return nil
end

-- The core's value for what the listing gives for one meaning, or nil.
function M.value_for(option, meaning, given)
  given = tostring(given or "")
  if given == "" then return nil end
  if meaning == "resolution" then
    local wanted = tonumber(lower(given):match("(%d+%.?%d*)"))
    if not wanted or wanted <= 0 or wanted > 16 then return nil end
    -- An on/off high-resolution mode (PCSX ReARMed's enhancement doubles it).
    if bool_of(option.values[1] or "") ~= nil and #option.values == 2 then
      return choose_word(option, { wanted >= 2 and "enabled" or "disabled" })
    end
    return choose_scale(option, wanted)
  elseif meaning == "renderer" then
    local g = lower(given)
    if g:find("vulkan") then return choose_word(option, { "vulkan" }) end
    if g:find("opengl") or g:find("gles") or g:find("open gl") then return choose_word(option, { "opengl", "gl" }) end
    if g:find("software") then return choose_word(option, { "software" }) end
    if g:find("auto") then return choose_word(option, { "auto" }) end
    return nil
  elseif meaning == "frameskip" then
    local n = tonumber(given:match("(%d+)"))
    if not n then return nil end
    if n == 0 then return choose_word(option, { "disabled", "off", "0" }) end
    for _, value in ipairs(option.values) do
      if tonumber(value) == n then return value end
    end
    return nil
  elseif meaning == "ee_cycle_rate" then
    local percent = given:match("(%d+)%%")
    return percent and choose_word(option, { percent .. "%" }) or nil
  elseif meaning == "ee_cycle_skip" then
    local g = lower(given)
    if g:find("normal") or g:find("%(0%)") then return choose_word(option, { "disabled", "normal" }) end
    local word = g:match("^(%a+)")
    return word and choose_word(option, { word }) or nil
  elseif meaning == "threaded" then
    local b = bool_of(given)
    if b == nil then return nil end
    return choose_word(option, { b and "enabled" or "disabled" })
  end
  return nil
end

-- The changes a listing's settings make to the game's core options:
-- { { key, label, from, to, field, given } }, only where the value differs.
function M.changes(game, custom_values)
  local out, seen = {}, {}
  for _, item in ipairs(custom_values or {}) do
    local definition = item.customFieldDefinition or {}
    local meaning = SEMANTIC[lower(definition.name)]
    if meaning and not seen[meaning] then
      local option = find_option(game.options or {}, meaning)
      local value = option and M.value_for(option, meaning, item.value)
      if value then
        seen[meaning] = true
        if value ~= option.value then
          out[#out + 1] = { key = option.key, label = M.LABELS[meaning], from = option.value, to = value,
                            field = definition.label or definition.name, given = tostring(item.value) }
        end
      end
    end
  end
  return out
end

-- What a listing's settings say, for the page ("Resolution: 2", "Renderer: Vulkan").
function M.settings_text(custom_values)
  local parts = {}
  for _, item in ipairs(custom_values or {}) do
    local definition = item.customFieldDefinition or {}
    if SEMANTIC[lower(definition.name)] and tostring(item.value or "") ~= "" then
      parts[#parts + 1] = (definition.label or definition.name) .. ": " .. tostring(item.value)
    end
  end
  return table.concat(parts, ", ")
end

return M
