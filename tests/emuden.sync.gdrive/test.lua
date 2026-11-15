-- SPDX-FileCopyrightText: Copyright 2026 EmuDEN contributors
-- SPDX-License-Identifier: GPL-3.0-or-later

-- Offline test of emuden.sync.gdrive against a fake host and a fake Google. Plain Lua 5.4, from
-- the repository root:  lua tests/emuden.sync.gdrive/test.lua

local here = arg[0]:match("^(.*[/\\])") or "./"
local fake = dofile(here .. "fake.lua")
local plugin_dir = here .. "../../plugins/emuden.sync.gdrive/"

local CLIENT = '{"client_id": "123-abc.apps.googleusercontent.com", "client_secret": "s3"}'
local passed, failed = 0, 0

local function check(cond, what)
  if cond then passed = passed + 1 else failed = failed + 1; print("FAIL: " .. what) end
end

local function start(google, opts)
  den = fake.den(plugin_dir, google, opts)
  local plugin = assert(loadfile(plugin_dir .. "main.lua", "t"))()
  return plugin, den
end

local function texts(page)
  local out = {}
  local function walk(list)
    for _, e in ipairs(list or {}) do
      out[#out + 1] = table.concat({ e.title or "", e.text or "", e.label or "", e.value or "" }, " | ")
      walk(e.items)
    end
  end
  walk(page.body)
  return page.title .. "\n" .. table.concat(out, "\n")
end

local function find(page, needle)
  return texts(page):find(needle, 1, true) ~= nil
end

-- util ----------------------------------------------------------------------------------------
do
  local google = fake.google()
  local _, d = start(google)
  local util = d.include("util.lua")
  check(util.parse_time("1970-01-01T00:00:00Z") == 0, "epoch")
  check(util.parse_time("2026-11-15T10:20:30.123Z") == 1794738030, "parse_time")
  check(util.parse_time("2026-11-15T12:20:30+02:00") == 1794738030, "parse_time offset")
  check(util.format_time(1794738030) == "2026-11-15T10:20:30.000Z", "format_time")
  check(util.parse_time(util.format_time(951782400)) == 951782400, "leap day round trip")
  check(util.quote("it's a\\b") == [['it\'s a\\b']], "quote")
  check(util.form{ b = "x y", a = "é/&" } == "a=%C3%A9%2F%26&b=x%20y", "form")
  check(util.refused("saves/gba/Game.srm") == nil, "gba save allowed")
  check(util.refused("config/settings.json") == nil, "settings allowed")
  check(util.refused("bios/scph5501.bin") == nil, "bios allowed")
  check(util.refused("saves/steam/x.sav") ~= nil, "steam save refused")
  check(util.refused("config/games/steam/x.json") ~= nil, "steam game settings refused")
  check(util.refused("games/STEAM/x") ~= nil, "steam case refused")
  check(util.refused("games/pc/steamapps/x") ~= nil, "pc refused")
  check(util.refused("saves/gba/../x") ~= nil, "dot-dot refused")
  check(util.refused("other/x") ~= nil, "unknown category refused")
  check(util.refused("saves/pce/Steam Heart's.srm") == nil, "a game named Steam is a game")
end

-- not set up --------------------------------------------------------------------------------
do
  local google = fake.google()
  local plugin, d = start(google, { no_package_client = true })
  plugin.open()
  check(find(d.pages[#d.pages], "not set up"), "page says not set up")
  local list, err = plugin.provider.list(nil)
  check(list == nil and err:find("not set up"), "provider refuses before setup")
  check(d.requests == 0, "no request before setup")
end

-- sign in, then sync ---------------------------------------------------------------------------
local google = fake.google()
local plugin, d = start(google, { data_files = { ["oauth_client.json"] = CLIENT } })
plugin.open()
check(find(d.pages[#d.pages], "Sign in with Google"), "signed-out page")
check(select(2, plugin.provider.list(nil)):find("Not signed in"), "provider refuses signed out")

local coroutine_page
local co = coroutine.wrap(function() plugin.actions.sign_in() end)
-- den.sleep does not yield in the fake: the whole poll runs at once. Read the page it showed.
co()
for _, page in ipairs(d.pages) do if find(page, "ABCD-EFGH") then coroutine_page = page end end
check(coroutine_page and find(coroutine_page, "google.com/device"), "code page shows the URL and code")
check(google.polls == 3, "polled through pending and slow_down (" .. google.polls .. ")")
check(d.slept >= 5000 + 5000 + 10000, "slow_down added 5 s to the interval")
check(d.secrets_table["google.refresh_token"] == "R1", "refresh token kept in den.secrets")
check(d.storage_table["google.refresh_token"] == nil, "refresh token not in den.storage")
check(d.sync_now_calls == 1, "sync started after sign-in")
local page = d.pages[#d.pages]
check(find(page, "test@example.com"), "account shown")
check(find(page, "5.4 GB of 16.1 GB used"), "quota shown: " .. texts(page))
check(find(page, "Saves, Save states"), "categories shown")
check(find(page, "Sync now") and find(page, "Sign out"), "buttons shown")
check(find(page, "3 up, 1 down"), "files of the last run shown")
check(find(page, "2 (Settings > Sync lists them)"), "conflicts shown")
check(find(page, "saves/gba/A.srm: no connection (and 1 more)"), "first error shown")

d.fs["sync:1"] = "SAVE-1"
local rev, err = plugin.provider.put("saves/gba/Pokemon Emerald.srm", "sync:1", nil)
check(rev == "1", "first upload gives version 1: " .. tostring(rev) .. " " .. tostring(err))
check(google.uploads[#google.uploads] == "multipart", "small file goes multipart")

local root
for _, f in pairs(google.files) do
  if f.name == "EmuDEN" then check(root == nil, "one EmuDEN folder"); root = f end
end
check(root and root.parents[1] == "myroot", "EmuDEN folder is in My Drive")
local names = {}
for _, f in pairs(google.files) do
  if f.parents and f.parents[1] == root.id then names[f.name] = true end
end
check(names.saves and names.states and names.config and names.games and names.bios,
      "one subfolder per category")

d.fs["sync:2"] = "STATE"
d.fs["sync:3"] = "{\"a\":1}"
d.fs["sync:4"] = "it's"
plugin.provider.put("states/gba/Pokemon Emerald.slot1.state", "sync:2", nil)
plugin.provider.put("config/games/gba/Pokemon Emerald.json", "sync:3", nil)
plugin.provider.put("saves/gba/It's a game.srm", "sync:4", nil, 1763100000)

local list = assert(plugin.provider.list(nil))
check(#list == 4, "list sees four files over pages of two (" .. #list .. ")")
local by = {}
for _, e in ipairs(list) do by[e.path] = e end
local e = by["saves/gba/Pokemon Emerald.srm"]
check(e and e.rev == "1" and e.size == 6 and type(e.modified) == "number", "list entry fields")
check(by["saves/gba/It's a game.srm"] and by["saves/gba/It's a game.srm"].modified == 1763100000,
      "modified time passed to put is kept")
local saves = plugin.provider.list("saves/")
check(#saves == 2, "prefix filters")

-- conflict and update
d.fs["sync:1"] = "SAVE-2"
local r, why = plugin.provider.put("saves/gba/Pokemon Emerald.srm", "sync:1", nil)
check(r == nil and why == "conflict", "unknown rev over an existing file is a conflict")
r, why = plugin.provider.put("saves/gba/Pokemon Emerald.srm", "sync:1", "0")
check(r == nil and why == "conflict", "older rev is a conflict")
r = plugin.provider.put("saves/gba/Pokemon Emerald.srm", "sync:1", "1")
check(r == "2", "update with the current rev gives version 2")
d.fs["sync:out"] = nil
local fractions = {}
check(plugin.provider.get("saves/gba/Pokemon Emerald.srm", "sync:out",
                          function(done, total) fractions[#fractions + 1] = { done, total } end) == true
      and d.fs["sync:out"] == "SAVE-2", "get writes the file")
check(#fractions == 1 and fractions[1][1] == 1, "get passes the host's progress on")
d.fs["sync:empty"] = ""
check(plugin.provider.put("bios/empty.bin", "sync:empty", nil) == "1", "an empty file uploads")

-- large file goes resumable, also on update
local big = string.rep("x", 6 * 1024 * 1024)
d.fs["sync:big"] = big
r = plugin.provider.put("games/gba/Big.gba", "sync:big", nil)
check(r == "1" and google.uploads[#google.uploads] == "resumable", "large file goes resumable")
d.fs["sync:big"] = big .. "y"
r = plugin.provider.put("games/gba/Big.gba", "sync:big", "1")
check(r == "2" and google.uploads[#google.uploads] == "resumable", "large update goes resumable")
check(plugin.provider.get("games/gba/Big.gba", "sync:bigout") and d.fs["sync:bigout"] == big .. "y",
      "large file comes back intact")

-- a cut resumable upload goes on from where Google stopped, in the same session
local huge = string.rep("z", 10 * 1024 * 1024) .. "end"
d.fs["sync:huge"] = huge
google.cut = 3 * 1024 * 1024
r, why = plugin.provider.put("games/gba/Huge.gba", "sync:huge", nil, 1763100000)
check(r == "1", "cut upload finished: " .. tostring(r) .. " " .. tostring(why))
check(google.resumed == 3 * 1024 * 1024 and google.status_queries == 1,
      "resumed at the offset Google reported")
check(plugin.provider.get("games/gba/Huge.gba", "sync:hugeout") and d.fs["sync:hugeout"] == huge,
      "resumed file comes back intact")

-- expired access token: refreshed once
google.valid = {}
local before = #google.log
check(plugin.provider.get("saves/gba/Pokemon Emerald.srm", "sync:out") == true, "401 refreshes")
local refreshes = 0
for i = before + 1, #google.log do
  if google.log[i]:find("oauth2.googleapis.com/token", 1, true) then refreshes = refreshes + 1 end
end
check(refreshes == 1, "one refresh after 401")

-- rate limits back off and retry
local slept = d.slept
google.faults = {
  { status = 429, body = { error = { code = 429, errors = { { reason = "rateLimitExceeded" } } } } },
  { status = 403, body = { error = { code = 403, errors = { { reason = "userRateLimitExceeded" } } } } },
  { status = 503, headers = { ["retry-after"] = "7" } },
}
check(plugin.provider.get("saves/gba/Pokemon Emerald.srm", "sync:out") == true, "retried after 429/403/503")
check(d.slept - slept >= 1000 + 2000 + 7000, "backed off, honouring Retry-After")
google.faults = { { status = 403, body = { error = { code = 403, message = "nope",
                                                    errors = { { reason = "insufficientPermissions" } } } } } }
local ok, msg = plugin.provider.get("saves/gba/Pokemon Emerald.srm", "sync:out")
check(ok == nil and msg:find("403"), "other 403 fails at once")
google.faults = { { status = 403, body = { error = { code = 403, errors = { { reason = "storageQuotaExceeded" } } } } } }
d.fs["sync:5"] = "x"
ok, msg = plugin.provider.put("saves/gba/Full.srm", "sync:5", nil)
check(ok == nil and msg:find("full"), "full Drive is reported")

-- PC and Steam never go out
local n = d.requests
d.fs["sync:steam"] = "s"
check(plugin.provider.put("saves/steam/game.sav", "sync:steam", nil) == nil, "steam put refused")
check(plugin.provider.put("config/games/steam/game.json", "sync:steam", nil) == nil, "steam config refused")
check(plugin.provider.get("saves/steam/game.sav", "sync:x") == nil, "steam get refused")
check(d.requests == n, "nothing sent for PC data")

-- delete trashes
check(plugin.provider.delete("states/gba/Pokemon Emerald.slot1.state") == true, "delete")
local trashed = false
for _, f in pairs(google.files) do
  if f.name == "Pokemon Emerald.slot1.state" then trashed = f.trashed end
end
check(trashed == true, "delete moves to the trash")
check(plugin.provider.delete("states/gba/missing.state") == true, "delete of a missing file is fine")
list = plugin.provider.list("states/")
check(#list == 0, "trashed file no longer listed")

-- status
local st = plugin.provider.status()
check(st.account == "test@example.com" and st.free == 16106127360 - 5368709120, "status")

-- second device: finds the same EmuDEN folder
local plugin2, d2 = start(google, { data_files = { ["oauth_client.json"] = CLIENT } })
d2.secrets_table["google.refresh_token"] = "R1"
local list2 = assert(plugin2.provider.list("saves/"))
check(#list2 == 2, "second device sees the files")
local roots = 0
for _, f in pairs(google.files) do if f.name == "EmuDEN" then roots = roots + 1 end end
check(roots == 1, "second device made no second EmuDEN folder")

-- sign-in ended at Google
google.refresh_tokens = {}
google.valid = {}
ok, msg = plugin2.provider.list(nil)
check(ok == nil and msg:find("Sign in again"), "invalid_grant signs out")
check(d2.secrets_table["google.refresh_token"] == nil, "refresh token removed")

-- sign out (device 1)
den = d
google.refresh_tokens = { R1 = true }
plugin.actions.sign_out()
check(google.revoked, "sign out revokes the token")
check(d.secrets_table["google.refresh_token"] == nil, "sign out forgets the token")
check(find(d.pages[#d.pages], "Sign in with Google"), "signed-out page after sign out")

-- sign-in refused by the user
do
  local g = fake.google()
  g.deny = true
  local p, dd = start(g, { data_files = { ["oauth_client.json"] = CLIENT } })
  p.actions.sign_in()
  check(find(dd.pages[#dd.pages], "refused"), "denied sign-in is explained")
  check(dd.secrets_table["google.refresh_token"] == nil, "no token after denial")
end

print(string.format("%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
