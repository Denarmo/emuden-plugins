-- SPDX-FileCopyrightText: Copyright 2026 EmuDEN contributors
-- SPDX-License-Identifier: GPL-3.0-or-later

-- A game's Steam launch options with lsfg-vk's variables merged in or taken out. The variables
-- are environment assignments in front of %command%:
--   LSFGVK_ENV=1 LSFGVK_MULTIPLIER=<n> LSFGVK_FLOW_SCALE=<f> LSFGVK_PERFORMANCE_MODE=<0|1>
-- Whatever else the options hold stays, in its order. Plain Lua, no den: the tests load it alone.

local M = {}

-- The plugin's translation through den.tr when it runs in EmuDEN; English with {} filled in
-- order when the tests load this file alone.
local function tr(text, ...)
  if den and den.tr then return den.tr(text, ...) end
  local values, n = table.pack(...), 0
  return (text:gsub("{}", function() n = n + 1 return tostring(values[n]) end))
end

M.MAX = 1000 -- EmuDEN refuses longer launch options
M.WSI = "ENABLE_GAMESCOPE_WSI"
local OURS = { LSFGVK_ENV = true, LSFGVK_MULTIPLIER = true, LSFGVK_FLOW_SCALE = true, LSFGVK_PERFORMANCE_MODE = true }

local function words_of(text)
  local words = {}
  for word in tostring(text or ""):gmatch("[^ ]+") do words[#words + 1] = word end
  return words
end

-- The characters EmuDEN sets in launch options: no quotes, no shell syntax.
function M.safe(text)
  local bad = tostring(text or ""):match("[^%w_%-%.,=:/+@%% ]")
  if bad then return nil, bad end
  return true
end

-- The words in front of %command% (where variables and wrappers are), and those from it on.
-- Without %command% every word is an argument of the game.
local function split(text)
  local words, head, rest, command = words_of(text), {}, {}, false
  for _, word in ipairs(words) do
    if word == "%command%" and not command then
      command = true
      rest[#rest + 1] = word
    elseif command then
      rest[#rest + 1] = word
    else
      head[#head + 1] = word
    end
  end
  if not command then return {}, head, false end
  return head, rest, true
end

local function assignment(word)
  local name, value = word:match("^([%a_][%w_]*)=(.*)$")
  return name, value
end

-- "1.0", "0.85", "0.5": two decimals at most, no trailing zero.
function M.flow_text(flow)
  return (string.format("%.2f", flow):gsub("0$", ""))
end

-- What the options say now: { on, multiplier, flow_scale, performance, wsi }. `wsi` is the
-- value of ENABLE_GAMESCOPE_WSI, nil when it is not set.
function M.read(text)
  local head = split(text)
  local out = { on = false, multiplier = 2, flow_scale = 1.0, performance = false }
  for _, word in ipairs(head) do
    local name, value = assignment(word)
    if name == "LSFGVK_ENV" then
      out.on = true
    elseif name == "LSFGVK_MULTIPLIER" then
      local n = math.tointeger(tonumber(value))
      if n and n >= 2 then out.multiplier = n end
    elseif name == "LSFGVK_FLOW_SCALE" then
      local f = tonumber(value)
      if f and f >= 0.25 and f <= 1.0 then out.flow_scale = f end
    elseif name == "LSFGVK_PERFORMANCE_MODE" then
      out.performance = value == "1"
    elseif name == M.WSI then
      out.wsi = value
    end
  end
  return out
end

-- The launch options after a change.
--   settings: { on, multiplier (2 to 10), flow_scale (0.25 to 1), performance }; `on` false or
--             settings nil takes lsfg-vk's variables out and leaves the rest.
--   opts.gamescope_wsi: also set ENABLE_GAMESCOPE_WSI=0 (SteamOS), unless the options set that
--             variable already.
--   opts.wsi_mine: this plugin added ENABLE_GAMESCOPE_WSI=0 earlier, so switching off takes it
--             out again (only while it still is 0).
-- Returns the text and whether ENABLE_GAMESCOPE_WSI=0 was added, or nil and why not.
function M.merge(text, settings, opts)
  opts = opts or {}
  text = tostring(text or "")
  local ok, bad = M.safe(text)
  if not ok then
    return nil, tr("The game's launch options hold a character EmuDEN does not set ({}). Change them in Steam's Properties first.",
                   bad == "\"" and tr("a quote") or bad)
  end
  local on = settings ~= nil and settings.on == true
  if on then
    local n = math.tointeger(settings.multiplier)
    if not n or n < 2 or n > 10 then return nil, tr("The multiplier is 2 to 10.") end
    local f = tonumber(settings.flow_scale)
    if not f or f < 0.25 or f > 1.0 then return nil, tr("The flow scale is 25 % to 100 %.") end
  end

  local head, rest, command = split(text)
  local kept, has_wsi = {}, false
  for _, word in ipairs(head) do
    local name, value = assignment(word)
    local drop = name ~= nil and OURS[name]
    if name == M.WSI then
      if not on and opts.wsi_mine and value == "0" then drop = true else has_wsi = true end
    end
    if not drop then kept[#kept + 1] = word end
  end

  local out, added = {}, false
  if on then
    out = { "LSFGVK_ENV=1", "LSFGVK_MULTIPLIER=" .. math.tointeger(settings.multiplier),
            "LSFGVK_FLOW_SCALE=" .. M.flow_text(settings.flow_scale),
            "LSFGVK_PERFORMANCE_MODE=" .. (settings.performance and "1" or "0") }
    if opts.gamescope_wsi and not has_wsi then
      out[#out + 1] = M.WSI .. "=0"
      added = true
    end
    if not command then table.insert(rest, 1, "%command%") end
  end
  for _, word in ipairs(kept) do out[#out + 1] = word end
  for _, word in ipairs(rest) do out[#out + 1] = word end
  -- %command% alone says nothing.
  if #out == 1 and out[1] == "%command%" then out = {} end
  local result = table.concat(out, " ")
  if #result > M.MAX then return nil, tr("The launch options would be longer than Steam's {} characters here.", M.MAX) end
  return result, added
end

-- "Off", "2x", "3x at 75 %, performance mode".
function M.describe(settings)
  if not settings or not settings.on then return tr("Off") end
  local multiplier = tostring(settings.multiplier)
  if settings.flow_scale < 1.0 then
    local flow = string.format("%d", math.floor(settings.flow_scale * 100 + 0.5))
    if settings.performance then return tr("{}x at {} %, performance mode", multiplier, flow) end
    return tr("{}x at {} %", multiplier, flow)
  end
  if settings.performance then return tr("{}x, performance mode", multiplier) end
  return multiplier .. "x"
end

return M
