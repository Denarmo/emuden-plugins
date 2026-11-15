-- SPDX-FileCopyrightText: Copyright 2026 EmuDEN contributors
-- SPDX-License-Identifier: GPL-3.0-or-later

-- Portable names (docs/sync.md section 2) and RomM's platform slugs.

local names = {}

-- EmuDEN system id -> RomM platform slugs (backend/utils/platform_slugs.py, RomM 5.4.1).
-- The first slug is the usual one; the others are platforms RomM keeps apart.
names.SLUGS = {
  switch2 = { "switch-2" },
  nes = { "nes", "famicom", "fds" },
  snes = { "snes", "sfam" },
  gb = { "gb" }, gbc = { "gbc" }, gba = { "gba" }, n64 = { "n64" }, nds = { "nds" },
  gamecube = { "ngc" }, wii = { "wii" },
  sms = { "sms" }, gg = { "gamegear" }, genesis = { "genesis" }, ["32x"] = { "sega32" },
  sg1000 = { "sg1000" }, saturn = { "saturn" }, dreamcast = { "dc" },
  psx = { "psx" }, ps2 = { "ps2" }, psp = { "psp" },
  pico8 = { "pico" }, virtualboy = { "virtualboy" }, pokemini = { "pokemon-mini" },
  atari2600 = { "atari2600" }, atari5200 = { "atari5200" }, atari7800 = { "atari7800" },
  lynx = { "lynx" }, jaguar = { "jaguar" },
  pce = { "tg16", "supergrafx" },
  ngp = { "neo-geo-pocket" }, ngpc = { "neo-geo-pocket-color" },
  wonderswan = { "wonderswan" }, wsc = { "wonderswan-color" },
  vectrex = { "vectrex" },
  msx = { "msx", "msx2", "msx2plus", "msx-turbo" },
  arcade = { "arcade", "cps1", "cps2", "cps3", "neogeoaes", "neogeomvs" },
}

names.SYSTEM_OF = {}
for system, slugs in pairs(names.SLUGS) do
  for _, slug in ipairs(slugs) do
    names.SYSTEM_OF[slug] = system
  end
end

-- The categories this provider offers (config and bios have no place in RomM).
names.CATEGORIES = { saves = true, states = true, games = true }

-- "saves/gba/Game (USA).srm" -> "saves", "gba", "Game (USA).srm"
function names.parse(path)
  local category, system, file = (path or ""):match("^([%w]+)/([%w_-]+)/([^/]+)$")
  if not category or not names.CATEGORIES[category] or not names.SLUGS[system] then
    return nil
  end
  return category, system, file
end

-- The ROM stem a save or state file belongs to, and what the file is:
-- "Game.srm" -> "Game", "save"; "Game.slot2.state" -> "Game", "state";
-- "Game.slot2.png" -> "Game", "picture" (the state "Game.slot2.state");
-- "Game.resume.state" -> "Game", "state".
function names.stem_of(category, file)
  if category == "saves" then
    local stem = file:match("^(.+)%.[^.]+$")
    return stem, "save"
  end
  local stem, slot = file:match("^(.+)%.(slot%d+)%.png$")
  if stem then
    return stem, "picture", stem .. "." .. slot .. ".state"
  end
  stem = file:match("^(.+)%.slot%d+%.state$") or file:match("^(.+)%.resume%.state$")
  if stem then
    return stem, "state"
  end
  return nil
end

-- Does a remote file name belong to a ROM of this stem? (Compared case insensitively.)
function names.belongs(file, stem)
  local f, s = file:lower(), stem:lower()
  return #f > #s and f:sub(1, #s + 1) == s .. "."
end

function names.lower_ext(file)
  return (file:match("%.([^.]+)$") or ""):lower()
end

function names.urlencode(text)
  return (tostring(text):gsub("[^%w%-%._~]", function(c)
    return string.format("%%%02X", c:byte())
  end))
end

-- "2026-11-14T10:20:30.123456Z" or "...+00:00" -> Unix seconds (0 when unreadable).
function names.unix_time(iso)
  if type(iso) ~= "string" then
    return 0
  end
  local y, mo, d, h, mi, s = iso:match("^(%d+)-(%d+)-(%d+)[T ](%d+):(%d+):(%d+)")
  if not y then
    return 0
  end
  y, mo, d = tonumber(y), tonumber(mo), tonumber(d)
  local offset = 0
  local sign, oh, om = iso:match("([+-])(%d%d):?(%d%d)$")
  if sign and not iso:match("Z$") then
    offset = (tonumber(oh) * 3600 + tonumber(om) * 60) * (sign == "+" and 1 or -1)
  end
  if mo <= 2 then
    y = y - 1
  end
  local era = y // 400
  local yoe = y - era * 400
  local mp = (mo + 9) % 12
  local doy = (153 * mp + 2) // 5 + d - 1
  local doe = yoe * 365 + yoe // 4 - yoe // 100 + doy
  local days = era * 146097 + doe - 719468
  return days * 86400 + tonumber(h) * 3600 + tonumber(mi) * 60 + tonumber(s) - offset
end

-- "5.4.1", "5.5.0-alpha.1" -> { 5, 4, 1 }; nil for "development" and the like.
function names.version(text)
  local a, b, c = tostring(text or ""):match("^v?(%d+)%.(%d+)%.?(%d*)")
  if not a then
    return nil
  end
  return { tonumber(a), tonumber(b), tonumber(c) or 0 }
end

function names.older(v, than)
  for i = 1, 3 do
    if v[i] ~= than[i] then
      return v[i] < than[i]
    end
  end
  return false
end

return names
