-- SPDX-FileCopyrightText: Copyright 2026 EmuDEN contributors
-- SPDX-License-Identifier: GPL-3.0-or-later

-- Offline test of emuden.tune.lsfg's launch.lua: lsfg-vk's variables merged into a game's Steam
-- launch options and taken out again, with everything else kept. Plain Lua 5.4, no den.

local DIR = os.getenv("DEN_PLUGIN_DIR") or "plugins/emuden.tune.lsfg"
local launch = dofile(DIR .. "/launch.lua")

local failures, checks = 0, 0
local function check(ok, what)
  checks = checks + 1
  if not ok then
    failures = failures + 1
    print("FAIL: " .. tostring(what))
  end
end
local function same(got, want, what)
  check(got == want, what .. ": got " .. tostring(got) .. ", want " .. tostring(want))
end

local X2 = { on = true, multiplier = 2, flow_scale = 1.0, performance = false }
local X3 = { on = true, multiplier = 3, flow_scale = 0.75, performance = true }
local OFF = { on = false, multiplier = 2, flow_scale = 1.0, performance = false }
local ON2 = "LSFGVK_ENV=1 LSFGVK_MULTIPLIER=2 LSFGVK_FLOW_SCALE=1.0 LSFGVK_PERFORMANCE_MODE=0"
local ON3 = "LSFGVK_ENV=1 LSFGVK_MULTIPLIER=3 LSFGVK_FLOW_SCALE=0.75 LSFGVK_PERFORMANCE_MODE=1"

-- What EmuDEN's own check of launch options allows before %command%: plain NAME=value words of
-- letters, digits and _-.,=:/+@ only. (Whether a variable's name is allowed is the app's list.)
local function plain(text)
  if text:find("[^%w_%-%.,=:/+@%% ]") then return false end
  local before = text:match("^(.-)%%command%%") or ""
  for word in before:gmatch("[^ ]+") do
    if word:sub(1, 6) == "LSFGVK" or word:sub(1, 20) == "ENABLE_GAMESCOPE_WSI" then
      if not word:match("^[%u_]+=[%w%.]+$") then return false end
    end
  end
  return true
end

-- Switching on.
same(launch.merge("", X2), ON2 .. " %command%", "empty options")
same(launch.merge(nil, X2), ON2 .. " %command%", "no options at all")
same(launch.merge("%command%", X3), ON3 .. " %command%", "%command% alone")
same(launch.merge("-dx11 -nointro", X2), ON2 .. " %command% -dx11 -nointro", "game arguments go behind %command%")
same(launch.merge("%command% -dx11", X2), ON2 .. " %command% -dx11", "arguments behind %command% stay")
same(launch.merge("PROTON_LOG=1 DXVK_ASYNC=1 %command%", X2), ON2 .. " PROTON_LOG=1 DXVK_ASYNC=1 %command%", "other variables stay")
same(launch.merge("gamemoderun %command% -windowed", X2), ON2 .. " gamemoderun %command% -windowed", "a wrapper stays behind the variables")
same(launch.merge("MANGOHUD=1 gamescope -w 1280 -h 800 -f -- %command% -novid", X3),
     ON3 .. " MANGOHUD=1 gamescope -w 1280 -h 800 -f -- %command% -novid", "a wrapper with its flags")
same(launch.merge("  PROTON_LOG=1   %command%  ", X2), ON2 .. " PROTON_LOG=1 %command%", "extra spaces go")

-- Changing: the old values are replaced, never doubled, wherever they stood.
same(launch.merge(ON2 .. " %command%", X3), ON3 .. " %command%", "2x to 3x")
same(launch.merge("PROTON_LOG=1 LSFGVK_MULTIPLIER=4 LSFGVK_ENV=1 gamemoderun %command%", X2),
     ON2 .. " PROTON_LOG=1 gamemoderun %command%", "values in another order and place")
same(launch.merge("LSFGVK_ENV=1 LSFGVK_ENV=1 LSFGVK_FLOW_SCALE=0.3 %command%", X2), ON2 .. " %command%", "doubled variables")
same(launch.merge(launch.merge("PROTON_LOG=1 %command% -dx11", X2), X2), ON2 .. " PROTON_LOG=1 %command% -dx11", "applying twice changes nothing")

-- Switching off takes only lsfg-vk's variables out.
same(launch.merge(ON2 .. " %command%", OFF), "", "only ours: nothing is left")
same(launch.merge(ON3 .. " %command%", nil), "", "no settings is off")
same(launch.merge(ON2 .. " PROTON_LOG=1 gamemoderun %command% -dx11", OFF), "PROTON_LOG=1 gamemoderun %command% -dx11", "the rest stays")
same(launch.merge(ON2 .. " %command% -dx11", OFF), "%command% -dx11", "arguments stay behind %command%")
same(launch.merge("-dx11 -nointro", OFF), "-dx11 -nointro", "off without ours changes nothing")
same(launch.merge("PROTON_LOG=1 %command%", OFF), "PROTON_LOG=1 %command%", "off without ours, with %command%")
same(launch.merge("", OFF), "", "off on empty options")
same(launch.merge("LSFG_LEGACY=1 LSFGVK_PROFILE=x LSFGVK_ENV=1 %command%", OFF), "LSFG_LEGACY=1 LSFGVK_PROFILE=x %command%",
     "variables this plugin does not write are not its own")
same(launch.merge("%command% LSFGVK_ENV=1", OFF), "%command% LSFGVK_ENV=1", "words behind %command% are the game's")
same(launch.merge("LSFGVK_ENV=1", OFF), "LSFGVK_ENV=1", "without %command% every word is the game's argument")

-- A round trip gives the options back as they were.
for _, before in ipairs({ "", "-dx11", "%command% -dx11", "PROTON_LOG=1 %command%", "gamemoderun %command% -x", "DXVK_ASYNC=1 mangohud %command%" }) do
  local on = launch.merge(before, X3)
  local off = launch.merge(on, OFF)
  local want = before == "-dx11" and "%command% -dx11" or before
  same(off, want, "on and off again from \"" .. before .. "\"")
  check(plain(on), "plain words only: " .. on)
end

-- ENABLE_GAMESCOPE_WSI=0 on SteamOS: added once, taken out only when this plugin added it.
do
  local text, added = launch.merge("PROTON_LOG=1 %command%", X2, { gamescope_wsi = true })
  same(text, ON2 .. " ENABLE_GAMESCOPE_WSI=0 PROTON_LOG=1 %command%", "added on SteamOS")
  check(added == true, "and reported as added")
  local again, added_again = launch.merge(text, X3, { gamescope_wsi = true, wsi_mine = true })
  same(again, ON3 .. " ENABLE_GAMESCOPE_WSI=0 PROTON_LOG=1 %command%", "kept once on a change")
  check(added_again == false, "not added twice")
  same(launch.merge(again, OFF, { gamescope_wsi = true, wsi_mine = true }), "PROTON_LOG=1 %command%", "off takes the plugin's own out")
  same(launch.merge(again, OFF, { gamescope_wsi = true }), "ENABLE_GAMESCOPE_WSI=0 PROTON_LOG=1 %command%", "off keeps one the user set")

  local own, own_added = launch.merge("ENABLE_GAMESCOPE_WSI=1 %command%", X2, { gamescope_wsi = true })
  same(own, ON2 .. " ENABLE_GAMESCOPE_WSI=1 %command%", "the user's own value is not overridden")
  check(own_added == false, "and is not the plugin's")
  same(launch.merge(own, OFF, { gamescope_wsi = true, wsi_mine = true }), "ENABLE_GAMESCOPE_WSI=1 %command%",
       "a value the user changed is theirs, also when the plugin once added the variable")
  local desktop, desktop_added = launch.merge("%command%", X2, {})
  same(desktop, ON2 .. " %command%", "not added outside SteamOS")
  check(desktop_added == false, "nothing added")
  same(launch.merge(ON2 .. " ENABLE_GAMESCOPE_WSI=0 %command%", OFF, { wsi_mine = true }), "", "everything of the plugin gone: nothing is left")
end

-- Values.
same(launch.flow_text(1.0), "1.0", "flow 100 %")
same(launch.flow_text(0.85), "0.85", "flow 85 %")
same(launch.flow_text(0.5), "0.5", "flow 50 %")
same(launch.flow_text(0.25), "0.25", "flow 25 %")
same(launch.merge("", { on = true, multiplier = 4.0, flow_scale = 0.5, performance = true }),
     "LSFGVK_ENV=1 LSFGVK_MULTIPLIER=4 LSFGVK_FLOW_SCALE=0.5 LSFGVK_PERFORMANCE_MODE=1 %command%", "a multiplier that came through JSON")
for _, bad in ipairs({ { on = true, multiplier = 1, flow_scale = 1 }, { on = true, multiplier = 2.5, flow_scale = 1 },
                       { on = true, multiplier = 11, flow_scale = 1 }, { on = true, multiplier = 2, flow_scale = 0.2 },
                       { on = true, multiplier = 2, flow_scale = 1.5 }, { on = true, flow_scale = 1 },
                       { on = true, multiplier = "2; rm -rf ~", flow_scale = 1 }, { on = true, multiplier = 2, flow_scale = "1 x" } }) do
  local text, why = launch.merge("%command%", bad)
  check(text == nil and type(why) == "string", "a value out of range is refused: " .. tostring(bad.multiplier) .. " / " .. tostring(bad.flow_scale))
end

-- Options EmuDEN would refuse are left alone, with the reason.
for _, text in ipairs({ 'PROTON_LOG=1 "%command%"', "FOO='a b' %command%", "%command%; rm -rf ~", "$(id) %command%", "a | b", "`id`",
                        "%command% > /tmp/x", "A=1\t%command%", "WINEDLLOVERRIDES=\"dxgi=n,b\" %command%", "~/run.sh %command%", "a && b" }) do
  local out, why = launch.merge(text, X2)
  check(out == nil and why:find("Steam") ~= nil, "refused: " .. text)
  local off, off_why = launch.merge(text, OFF)
  check(off == nil and off_why ~= nil, "refused for Off too: " .. text)
end
check(launch.safe("WINEDLLOVERRIDES=dxgi=n,b gamescope -w 1280 -- %command% -x +set a@b /c:d") == true, "everything EmuDEN allows passes")
do
  local long = string.rep("-argument ", 95)
  local out, why = launch.merge(long, X2)
  check(out == nil and why:find("longer"), "options that would pass 1000 characters are refused")
  check(launch.merge(long, OFF) ~= nil, "but can still be left as they are")
end

-- Reading the options back.
do
  local now = launch.read(ON3 .. " ENABLE_GAMESCOPE_WSI=0 PROTON_LOG=1 %command% -dx11")
  check(now.on and now.multiplier == 3 and now.flow_scale == 0.75 and now.performance == true and now.wsi == "0", "what is set")
  local off = launch.read("PROTON_LOG=1 %command%")
  check(not off.on and off.multiplier == 2 and off.flow_scale == 1.0 and off.performance == false and off.wsi == nil, "off, with the defaults")
  check(not launch.read("%command% LSFGVK_ENV=1").on and not launch.read("LSFGVK_ENV=1").on, "only in front of %command%")
  local odd = launch.read("LSFGVK_ENV=1 LSFGVK_MULTIPLIER=abc LSFGVK_FLOW_SCALE=9 %command%")
  check(odd.on and odd.multiplier == 2 and odd.flow_scale == 1.0, "values lsfg-vk would refuse read as the defaults")
  same(launch.describe(now), "3x at 75 %, performance mode", "described")
  same(launch.describe(off), "Off", "off described")
  same(launch.describe(X2), "2x", "2x described")
end

print(string.format("%d checks, %d failed", checks, failures))
os.exit(failures == 0 and 0 or 1)
