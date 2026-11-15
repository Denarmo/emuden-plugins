-- SPDX-FileCopyrightText: Copyright 2026 EmuDEN contributors
-- SPDX-License-Identifier: GPL-3.0-or-later

-- Ranks ProtonDB reports by how close the reporter's machine is to this device, and picks
-- the Proton version and launch options to suggest. Plain Lua, no den calls (tests run it).

local R = {}

local CODENAMES = {
  vangogh = true, sephiroth = true, rembrandt = true, phoenix = true, hawkpoint = true,
  strix = true, krackan = true, raphael = true, renoir = true, cezanne = true, lucienne = true,
  navi = true, polaris = true, vega = true, picasso = true, aerith = true,
}

local IGNORED = {
  amd = true, radeon = true, graphics = true, llvm = true, drm = true, mesa = true, custom = true,
  gpu = true, apu = true, nvidia = true, geforce = true, intel = true, radv = true, core = true,
  ryzen = true, with = true, processor = true, ["(tm)"] = true, gen = true, mobile = true,
}

local function lower(text)
  return string.lower(text or "")
end

-- Words that tell models apart: those holding a digit ("7800", "z2", "680m") and codenames.
local function tokens(text)
  local out = {}
  for word in lower(text):gsub("%b()", function(inner) return " " .. inner .. " " end):gmatch("[%w%-]+") do
    if not IGNORED[word] and not word:match("^%d+%.%d") and (word:match("%d") or CODENAMES[word]) then
      if #word >= 2 and not word:match("^%d$") then
        out[word] = true
      end
    end
  end
  return out
end

local function overlap(a, b)
  local n = 0
  for word in pairs(a) do
    if b[word] then n = n + 1 end
  end
  return n
end

local function vendor(text)
  text = lower(text)
  if text:find("nvidia") or text:find("geforce") or text:find("rtx") or text:find("gtx") then
    return "nvidia"
  elseif text:find("intel") or text:find("iris") or text:find(" arc") or text:find("uhd") then
    return "intel"
  elseif text:find("amd") or text:find("radeon") or text:find("radv") or text:find("ryzen")
      or text:find("vangogh") or text:find("navi") then
    return "amd"
  end
  return nil
end

-- The handheld a processor or graphics name belongs to, when it is one.
local function handheld_class(cpu, gpu, kernel)
  local all = lower(cpu) .. " " .. lower(gpu) .. " " .. lower(kernel)
  if all:find("apu 0405") or all:find("apu 0932") or all:find("gpu 0405") or all:find("gpu 0932")
      or all:find("vangogh") or all:find("sephiroth") or all:find("neptune") or all:find("galileo") then
    return "steam deck"
  elseif all:find("z2 go") then
    return "z2 go"
  elseif all:find("z2 extreme") then
    return "z2 extreme"
  elseif all:find("z1 extreme") then
    return "z1 extreme"
  elseif all:find("z1") then
    return "z1"
  elseif all:find("z2") then
    return "z2"
  end
  return nil
end

local DEVICE_NAMES = {
  ["steam deck"] = "Steam Deck", ["z2 go"] = "Legion Go S / Z2 Go", ["z2 extreme"] = "Z2 Extreme handheld",
  ["z1 extreme"] = "ROG Ally / Legion Go", ["z1"] = "ROG Ally (Z1)", ["z2"] = "Z2 handheld",
}

local function gigabytes(text)
  local n = tonumber(tostring(text or ""):match("(%d+%.?%d*)"))
  return n
end

-- This device, from den.device.info().
function R.me(info)
  info = info or {}
  local cpu, gpu = info.soc or "", info.gpu or ""
  local class = handheld_class(cpu, gpu, "")
  if not class and lower(info.name):find("steam deck") then class = "steam deck" end
  return {
    name = info.name or "This device",
    class = class,
    handheld = class ~= nil or info.handheld == true,
    gpu_vendor = vendor(gpu) or vendor(cpu),
    gpu_tokens = tokens(gpu),
    cpu_vendor = vendor(cpu),
    cpu_tokens = tokens(cpu),
    steamos = info.steamos == true,
    linux = info.os == "linux",
    windows = info.os == "windows",
    ram_gb = info.ram_mb and info.ram_mb > 0 and info.ram_mb / 1024 or nil,
  }
end

-- What machine wrote a report.
function R.machine(report)
  local class = handheld_class(report.cpu, report.gpu, report.kernel)
  if not class and report.device == "steamDeck" then class = "steam deck" end
  local os = lower(report.os)
  return {
    class = class,
    handheld = class ~= nil or report.device == "steamDeck" or report.device == "handheld",
    gpu_vendor = vendor(report.gpu) or vendor(report.cpu),
    gpu_tokens = tokens(report.gpu),
    cpu_vendor = vendor(report.cpu),
    cpu_tokens = tokens(report.cpu),
    steamos = os:find("steamos") ~= nil or os:find("holo") ~= nil,
    ram_gb = gigabytes(report.ram),
  }
end

function R.describe(report)
  local m = R.machine(report)
  if m.class then return DEVICE_NAMES[m.class] end
  local gpu = (report.gpu or ""):gsub("%s*%b()", "")
  if gpu == "" then gpu = "a PC" end
  return gpu
end

-- How close a report's machine is, 0..100, and why.
function R.score(me, report, now)
  local m = R.machine(report)
  local score, why = 0, {}
  if me.class and m.class == me.class then
    score = score + 40
    why[#why + 1] = "same handheld"
  elseif me.handheld and m.handheld then
    score = score + 18
    why[#why + 1] = "a handheld"
  end
  if me.gpu_vendor and m.gpu_vendor == me.gpu_vendor then
    score = score + 12
    if overlap(me.gpu_tokens, m.gpu_tokens) > 0 then
      score = score + 10
      why[#why + 1] = "same graphics"
    else
      why[#why + 1] = "same graphics maker"
    end
  end
  if me.cpu_vendor and m.cpu_vendor == me.cpu_vendor then
    score = score + 4
    if overlap(me.cpu_tokens, m.cpu_tokens) > 0 then
      score = score + 6
      why[#why + 1] = "same processor"
    end
  end
  if me.steamos and m.steamos then
    score = score + 10
    why[#why + 1] = "SteamOS"
  end
  if me.ram_gb and m.ram_gb and math.abs(m.ram_gb - me.ram_gb) <= me.ram_gb * 0.25 then
    score = score + 4
  end
  local age = ((now or 0) - (report.t or 0)) / (365 * 86400)
  if age < 3 then
    score = score + math.floor(10 * (1 - math.max(age, 0) / 3) + 0.5)
  end
  if report.verdict == "yes" then
    score = score + 4
  end
  return math.min(score, 100), why
end

function R.rank(me, reports, now)
  local out = {}
  for index, report in ipairs(reports or {}) do
    local score, why = R.score(me, report, now)
    out[#out + 1] = { report = report, score = score, why = why, index = index }
  end
  table.sort(out, function(a, b)
    if a.score ~= b.score then return a.score > b.score end
    if (a.report.t or 0) ~= (b.report.t or 0) then return (a.report.t or 0) > (b.report.t or 0) end
    return a.index < b.index
  end)
  return out
end

-- Steam's name of the tool a report names ("10.0-3" -> proton_10, "Experimental",
-- "GE-Proton9-20" as it is), and whether it is installed or Steam fetches it itself.
function R.tool_for(text, tools)
  text = (text or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if text == "" or lower(text) == "default" then return nil end
  local plain = text:gsub("^[Pp]roton%s*", "")
  local name
  if lower(plain):find("^experimental") or lower(plain):find("bleeding") then
    name = "proton_experimental"
  elseif lower(plain):find("^hotfix") then
    name = "proton_hotfix"
  else
    local major, minor = plain:match("^(%d+)%.(%d+)")
    if not major then major = plain:match("^(%d+)$") end
    if major then
      name = "proton_" .. major .. ((minor and minor ~= "0") and minor or "")
    end
  end
  for _, tool in ipairs(tools or {}) do
    if tool.name == (name or text) or (not name and lower(tool.display) == lower(text)) then
      return { name = tool.name, display = tool.display, installed = true, official = name ~= nil }
    end
  end
  if name then
    -- Steam downloads an official Proton the first time a game needs it.
    local display = name == "proton_experimental" and "Proton Experimental"
        or name == "proton_hotfix" and "Proton Hotfix" or ("Proton " .. plain:match("^[%d%.]+"))
    return { name = name, display = display, installed = false, official = true }
  end
  return { name = text, display = text, installed = false, official = false }
end

local WRAPPERS = { gamemoderun = true, mangohud = true, gamescope = true, ["obs-gamecapture"] = true,
                   ["prime-run"] = true }

local NVIDIA_ONLY = { "PROTON_ENABLE_NVAPI", "DXVK_ENABLE_NVAPI", "__GL_", "PROTON_HIDE_NVIDIA_GPU",
                      "VKD3D_CONFIG=dxr", "PROTON_ENABLE_NGX" }

-- Launch options a report gives that suit this device, or nil.
function R.launch_for(me, report)
  local text = (report.launch or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if text == "" or text == "%command%" then return nil end
  if text:find("[;|&$`<>\\'\"(){}%[%]*?!~#\n]") then return nil end
  -- Every word must look like an option: a variable, a flag (and its value), a known wrapper,
  -- %command%, or a game argument after it. "Ubisoft Connect" is a note, not options.
  local after, flag = false, false
  for word in text:gmatch("%S+") do
    if word == "%command%" then
      after = true
    elseif not after and not (word:find("=") or word:find("^[%-%+]") or WRAPPERS[word] or flag) then
      return nil
    end
    flag = word:find("^%-") ~= nil
  end
  local m = R.machine(report)
  if me.gpu_vendor and m.gpu_vendor and m.gpu_vendor ~= me.gpu_vendor then
    for _, marker in ipairs(NVIDIA_ONLY) do
      if text:find(marker, 1, true) then return nil end
    end
  end
  return text
end

-- What applies on Windows: the game's own arguments (after %command%, or all without it).
function R.windows_args(launch)
  if not launch then return nil end
  local after = launch:match("%%command%%%s*(.*)$")
  if after == nil then
    if launch:find("=") then return nil end
    after = launch
  end
  after = after:gsub("^%s+", ""):gsub("%s+$", "")
  return after ~= "" and after or nil
end

-- The suggestion from the ranked reports: the Proton version most of the closest working
-- reports used, and the launch options of the closest working report that gives some.
function R.suggest(me, ranked, tools, chosen)
  local out = { votes = {} }
  local pool = {}
  if chosen then
    pool = { chosen }
  else
    for _, entry in ipairs(ranked) do
      if entry.report.verdict == "yes" then pool[#pool + 1] = entry end
      if #pool >= 10 then break end
    end
  end
  if #pool == 0 then return out end
  local best = pool[1].score
  local weights, order = {}, {}
  for _, entry in ipairs(pool) do
    if entry.score >= best * 0.6 then
      local tool = R.tool_for(entry.report.custom_proton or entry.report.proton, tools)
      if tool then
        if not weights[tool.name] then
          order[#order + 1] = tool
          weights[tool.name] = 0
        end
        weights[tool.name] = weights[tool.name] + entry.score
      end
      if not out.launch then
        local launch = R.launch_for(me, entry.report)
        if launch then
          out.launch = launch
          out.launch_from = entry
        end
      end
    end
  end
  table.sort(order, function(a, b) return weights[a.name] > weights[b.name] end)
  out.tool = order[1]
  out.votes = weights
  out.from = pool[1]
  return out
end

R.tokens = tokens
return R
