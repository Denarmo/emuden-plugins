-- SPDX-FileCopyrightText: Copyright 2026 EmuDEN contributors
-- SPDX-License-Identifier: GPL-3.0-or-later

-- Offline test of emuden.sync.romm: a fake `den` and a fake RomM 5.4.1 server.
-- Run from the repository root with a plain Lua 5.4:
--   lua tests/emuden.sync.romm/provider_test.lua

local here = arg[0]:match("^(.*)[/\\]") or "."
local root = here .. "/../../plugins/emuden.sync.romm/"
local json = dofile(here .. "/json.lua")

-- Fake RomM --------------------------------------------------------------------------------

local server = { version = "5.4.1", clock = 0, next_id = 1000, requests = {} }
local function stamp()
  server.clock = server.clock + 1
  return string.format("2026-11-14T%02d:%02d:%02dZ", server.clock // 3600 % 24,
                       server.clock // 60 % 60, server.clock % 60)
end
local function new_id()
  server.next_id = server.next_id + 1
  return server.next_id
end

local valid_access, valid_refresh = {}, {}
local function issue()
  local a, r = "access-" .. new_id(), "refresh-" .. new_id()
  valid_access[a], valid_refresh[r] = true, true
  return json.encode{ access_token = a, refresh_token = r, token_type = "bearer",
                      expires = 1800, refresh_expires = 604800 }
end

local platforms = {
  { id = 1, slug = "gba", fs_slug = "gba", name = "Game Boy Advance", rom_count = 252 },
  { id = 2, slug = "psx", fs_slug = "psx", name = "PlayStation", rom_count = 1 },
  { id = 3, slug = "amiga", fs_slug = "amiga", name = "Amiga", rom_count = 4 },
}
local function rom(id, platform, fs, files, extra)
  local r = { id = id, platform_id = platform, fs_name = fs, fs_name_no_ext = fs:gsub("%.%w+$", ""),
              fs_size_bytes = 0, name = fs, updated_at = stamp(), files = {} }
  for i, f in ipairs(files) do
    r.files[i] = { id = id * 10 + i, rom_id = id, file_name = f[1], file_size_bytes = f[2],
                   is_top_level = f[3] ~= false, category = f[4] or json.null,
                   updated_at = r.updated_at }
    r.fs_size_bytes = r.fs_size_bytes + f[2]
  end
  for k, v in pairs(extra or {}) do r[k] = v end
  return r
end
local roms = {
  rom(10, 1, "Golden Sun (USA).gba", { { "Golden Sun (USA).gba", 8388608 } }),
  rom(11, 1, "Metroid Fusion (USA).gba", { { "Metroid Fusion (USA).gba", 8388608 } }),
  rom(20, 2, "Final Fantasy VII (USA)", {
    { "Final Fantasy VII (USA).m3u", 100, false, "game" },
    { "Final Fantasy VII (USA) (Disc 1).cue", 200, false, "game" },
    { "Final Fantasy VII (USA) (Disc 1).bin", 700000000, false, "game" },
    { "Manual.pdf", 5000, false, "manual" } }, { name = "Final Fantasy VII" }),
  rom(30, 3, "Lemmings.adf", { { "Lemmings.adf", 901120 } }),
}
for i = 1, 250 do  -- more than one page of 200
  roms[#roms + 1] = rom(100 + i, 1, string.format("Filler %03d.gba", i), { { string.format("Filler %03d.gba", i), 4 } })
end

local assets = { saves = {}, states = {}, screenshots = {} }
local content = {}   -- "saves/<id>" -> bytes
local function add_asset(kind, rom_id, file_name, bytes, extra)
  local a = { id = new_id(), rom_id = rom_id, user_id = 1, file_name = file_name,
              file_size_bytes = #bytes, updated_at = stamp(), slot = json.null,
              emulator = json.null }
  for k, v in pairs(extra or {}) do a[k] = v end
  assets[kind][#assets[kind] + 1] = a
  content[kind .. "/" .. a.id] = bytes
  return a
end
add_asset("saves", 10, "Golden Sun (USA).srm", "GS-SAVE-1")
add_asset("saves", 10, "Golden Sun (USA) [2026-11-01].srm", "TAGGED", { slot = "main" })
add_asset("saves", 10, "Other name.srm", "OTHER")
add_asset("saves", 30, "Lemmings.sav", "AMIGA")
add_asset("states", 11, "Metroid Fusion (USA).slot1.state", "MF-STATE")
add_asset("screenshots", 11, "Metroid Fusion (USA).slot1.png", "PNG1")

local function screenshot_of(state)
  local stem = state.file_name:gsub("%.[^.]+$", "")
  for _, s in ipairs(assets.screenshots) do
    if s.rom_id == state.rom_id and s.file_name:gsub("%.[^.]+$", "") == stem then
      return s
    end
  end
  return json.null
end
local function view(kind, a)
  if kind ~= "states" then return a end
  local copy = {}
  for k, v in pairs(a) do copy[k] = v end
  copy.screenshot = screenshot_of(a)
  return copy
end
local function find(kind, id)
  for i, a in ipairs(assets[kind]) do
    if a.id == id then return a, i end
  end
end

local files = {}     -- the fake device's files: path -> bytes
local function query_of(url)
  local q = {}
  for k, v in (url:match("%?(.*)$") or ""):gmatch("([^&=]+)=([^&]*)") do
    q[k] = v:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end)
  end
  return q
end
local function reply(status, body) return { status = status, body = body, headers = {} } end
local function ok(value) return reply(200, json.encode(value)) end

local function handle(req)
  local method = req.method or "GET"
  local path = req.url:match("^https?://[^/]+(/[^?]*)")
  local q = query_of(req.url)
  server.requests[#server.requests + 1] = method .. " " .. path
  if path == "/api/heartbeat" then
    return ok{ SYSTEM = { VERSION = server.version, SHOW_SETUP_WIZARD = false } }
  elseif path == "/api/token" then
    local form = query_of("?" .. req.body)
    if form.grant_type == "password" then
      if form.username ~= "alice" or form.password ~= "hunter2" then
        return reply(401, json.encode{ detail = "Invalid username or password" })
      end
      server.scope = form.scope
      return reply(200, issue())
    elseif form.grant_type == "refresh_token" and valid_refresh[form.refresh_token] then
      valid_refresh[form.refresh_token] = nil   -- single use, as RomM does
      return reply(200, issue())
    end
    return reply(401, json.encode{ detail = "Invalid refresh token" })
  end
  local token = (req.headers or {}).Authorization
  if not token or not valid_access[token:gsub("^Bearer ", "")] then
    return reply(401, json.encode{ detail = "Unauthorized" })
  end
  if path == "/api/users/me" then
    return ok{ id = 1, username = "alice" }
  elseif path == "/api/platforms" then
    return ok(platforms)
  elseif path == "/api/roms" then
    local items, pid = {}, tonumber(q.platform_ids)
    for _, r in ipairs(roms) do
      if r.platform_id == pid then items[#items + 1] = r end
    end
    local page, offset, limit = {}, tonumber(q.offset), tonumber(q.limit)
    for i = offset + 1, math.min(#items, offset + limit) do page[#page + 1] = items[i] end
    return ok{ items = page, total = #items, limit = limit, offset = offset }
  end
  local rom_id, name = path:match("^/api/roms/(%d+)/content/(.+)$")
  if rom_id then
    local wanted = tonumber(q.file_ids)
    for _, r in ipairs(roms) do
      for _, f in ipairs(r.files) do
        if r.id == tonumber(rom_id) and f.id == wanted then
          files[req.to_file] = "ROM:" .. f.file_name
          if req.on_progress then req.on_progress(f.file_size_bytes, f.file_size_bytes) end
          return reply(200, nil)
        end
      end
    end
    return reply(404, json.encode{ detail = "not found" })
  end
  local kind, id, rest = path:match("^/api/(%a+)/?(%d*)(.*)$")
  id = tonumber(id)
  if not assets[kind] then
    return reply(404, json.encode{ detail = "no route " .. path })
  end
  if rest == "/content" then
    files[req.to_file] = content[kind .. "/" .. id]
    return reply(200, nil)
  elseif rest == "delete" and method == "POST" then
    for _, gone in ipairs(json.decode(req.body)[kind]) do
      local _, i = find(kind, gone)
      table.remove(assets[kind], i)
    end
    return ok(json.decode(req.body)[kind])
  elseif method == "DELETE" then
    local _, i = find(kind, id)
    table.remove(assets[kind], i)
    return reply(204, "")
  elseif method == "GET" and id then
    return ok(view(kind, find(kind, id)))
  elseif method == "GET" then
    local out = {}
    for _, a in ipairs(assets[kind]) do
      if not q.rom_id or a.rom_id == tonumber(q.rom_id) then out[#out + 1] = view(kind, a) end
    end
    return ok(out)
  end
  local part = req.multipart[1]
  local bytes = files[part.file]
  if method == "POST" then
    local a = add_asset(kind, tonumber(q.rom_id), part.filename, bytes)
    return ok(view(kind, a))
  end
  local a = find(kind, id)
  if part.name == "screenshotFile" then
    local shot = screenshot_of(a)
    if shot == json.null then
      shot = add_asset("screenshots", a.rom_id, part.filename, bytes)
    else
      shot.updated_at, content["screenshots/" .. shot.id] = stamp(), bytes
    end
  else
    a.updated_at, a.file_size_bytes, content[kind .. "/" .. a.id] = stamp(), #bytes, bytes
  end
  return ok(view(kind, a))
end

-- Fake den ---------------------------------------------------------------------------------

local storage, secrets, ui, log = {}, {}, { stack = {}, toasts = {} }, {}
local sync = { downloads = {}, synced = 0 }
local now = 1763100000
den = {
  api = 1, plugin = { id = "emuden.sync.romm", version = "1.0.0" },
  log = function(text) log[#log + 1] = text end,
  now = function() return now end,
  language = function() return "en" end,
  tr = function(text, ...)
    local values, out, i, n = table.pack(...), {}, 1, 0
    while i <= #text do
      local two = text:sub(i, i + 1)
      if two == "{{" or two == "}}" then out[#out + 1] = two:sub(1, 1); i = i + 2
      elseif two == "{}" then n = n + 1; out[#out + 1] = tostring(values[n]); i = i + 2
      else out[#out + 1] = text:sub(i, i); i = i + 1 end
    end
    return table.concat(out)
  end,
  sleep = function(ms) now = now + ms / 1000 end,
  json = { encode = json.encode, decode = json.decode, null = json.null },
  storage = { get = function(k) return storage[k] end, set = function(k, v) storage[k] = v end,
              remove = function(k) storage[k] = nil end },
  secrets = { get = function(k) return secrets[k] end, set = function(k, v) secrets[k] = v end,
              remove = function(k) secrets[k] = nil end },
  http = { request = function(req)
    assert(req.url:match("^http://romm%.lan:8080/"), "request to another host: " .. req.url)
    return handle(req)
  end },
  sync = {
    set_server = function(url)
      if sync.decline then return nil, "declined" end
      sync.server = url
      return true
    end,
    now = function() sync.synced = sync.synced + 1; return true end,
    status = function()
      return { active = true, running = false, last_sync = now - 600, done = 2, total = 2,
               uploaded = 1, downloaded = 1, conflicts = 1, waiting = 0,
               errors = { "saves/gba/X.srm: RomM: HTTP 500" }, error = "saves/gba/X.srm: RomM: HTTP 500" }
    end,
    enabled_categories = function() return { "saves", "states" } end,
    download_game = function(paths) sync.downloads[#sync.downloads + 1] = paths; return true end,
  },
  ui = {
    set = function(p) ui.stack[math.max(#ui.stack, 1)] = p end,
    push = function(p) ui.stack[#ui.stack + 1] = p end,
    pop = function() ui.stack[#ui.stack] = nil end,
    depth = function() return #ui.stack end,
    patch = function() end,
    toast = function(t) ui.toasts[#ui.toasts + 1] = t end,
    confirm = function() return true end,
  },
}
function den.include(name)
  local f = io.open(root .. name, "rb") or assert(io.open(here .. "/../../shared/urlencode/" .. name, "rb"))
  local chunk = assert(load(f:read("a"), "=" .. name, "t"))
  f:close()
  return chunk()
end

-- Checks -------------------------------------------------------------------------------------

local passed = 0
local function check(cond, what)
  if not cond then error("FAILED: " .. what, 2) end
  passed = passed + 1
end
local function page() return ui.stack[#ui.stack] end
local function find_el(p, field, v)
  for _, el in ipairs(p.body) do
    if el[field] == v then return el end
  end
end
local function by_path(list)
  local t = {}
  for _, item in ipairs(list) do t[item.path] = item end
  return t
end

local plugin = den.include("main.lua")
local P = plugin.provider

plugin.open()
check(find_el(page(), "id", "server"), "first page asks for the server")

server.version = "5.3.2"
plugin.actions.set_server(nil, "romm.lan:8080/")
check(storage.server == nil, "an old server is refused")
check(find_el(page(), "id", "message").text:find("5.4.1 or newer", 1, true), "old version message")

server.version = "5.4.1"
sync.decline = true
plugin.actions.set_server(nil, "romm.lan:8080/")
check(storage.server == nil and find_el(page(), "id", "message").text == "The server was not confirmed.",
      "a declined server is not kept")
sync.decline = nil
plugin.actions.set_server(nil, "romm.lan:8080/")
check(storage.server == "http://romm.lan:8080" and sync.server == storage.server, "server set")
check(find_el(page(), "id", "password").secret == true, "password input is secret")

plugin.actions.set_user(nil, "alice")
plugin.actions.set_password(nil, "wrong")
plugin.actions.sign_in()
check(find_el(page(), "id", "message").text == "Wrong user name or password.", "bad password")

plugin.actions.set_password(nil, "hunter2")
plugin.actions.sign_in()
check(secrets.refresh_token and storage.user == "alice", "signed in, refresh token kept")
check(server.scope:find("assets.write", 1, true), "asks for the assets scopes")
local everything = json.encode(storage) .. json.encode(secrets)
check(not everything:find("hunter2", 1, true), "the password is never stored")
check(find_el(page(), "id", "sync_now") and find_el(page(), "label", "Signed in as").value == "alice",
      "status page")
local warned = {}
for _, el in ipairs(page().body) do
  if el.style == "warning" then warned[#warned + 1] = el.text end
end
check(warned[1] == "1 conflicts. Settings > Sync lists them." and
      warned[2]:find("saves/gba/X.srm: RomM: HTTP 500", 1, true), "conflicts and the first error shown")

-- list
local saves = by_path(assert(P.list("saves/")))
check(saves["saves/gba/Golden Sun (USA).srm"], "save of a matching ROM listed")
check(saves["saves/gba/Golden Sun (USA).srm"].rev == assets.saves[1].updated_at, "rev is updated_at")
check(saves["saves/gba/Golden Sun (USA).srm"].modified > 1700000000, "modified is Unix time")
local n = 0
for _ in pairs(saves) do n = n + 1 end
check(n == 1, "slot saves, other names and unmapped platforms are left out")
local states = by_path(assert(P.list("states/")))
check(states["states/gba/Metroid Fusion (USA).slot1.state"], "state listed")
check(states["states/gba/Metroid Fusion (USA).slot1.png"], "its picture listed")
check(#assert(P.list("config/")) == 0 and #assert(P.list("bios/")) == 0, "config and bios empty")
local games = by_path(assert(P.list("games/")))
check(games["games/psx/Final Fantasy VII (USA) (Disc 1).cue"], "multi-file game members listed")
check(not games["games/psx/Manual.pdf"], "manuals are not game files")
check(games["games/gba/Filler 250.gba"], "second page of ROMs read")
check(not games["games/amiga/Lemmings.adf"], "unmapped platform left out")

-- get
check(P.get("saves/gba/golden sun (usa).srm", "tmp/1"), "get save, any case")
check(files["tmp/1"] == "GS-SAVE-1", "save bytes written")
P.get("states/gba/Metroid Fusion (USA).slot1.png", "tmp/2")
check(files["tmp/2"] == "PNG1", "picture fetched")
local progress = {}
P.get("games/psx/Final Fantasy VII (USA) (Disc 1).bin", "tmp/3", function(done, total)
  progress[#progress + 1] = { done, total }
end)
check(files["tmp/3"] == "ROM:Final Fantasy VII (USA) (Disc 1).bin", "game file fetched by file id")
check(#progress == 1 and progress[1][2] == 700000000, "progress reported")

-- put
files["local/save"] = "GS-SAVE-2"
local old = saves["saves/gba/Golden Sun (USA).srm"].rev
local rev = assert(P.put("saves/gba/Golden Sun (USA).srm", "local/save", old, 1763000000))
check(rev ~= old and content["saves/" .. assets.saves[1].id] == "GS-SAVE-2", "update with known rev")
local listed = by_path(assert(P.list("saves/")))["saves/gba/Golden Sun (USA).srm"]
check(listed.rev == rev and listed.modified == 1763000000, "list gives back the time put() was given")
local r, why = P.put("saves/gba/Golden Sun (USA).srm", "local/save", old)
check(r == nil and why == "conflict", "stale rev is a conflict")
r, why = P.put("saves/gba/Golden Sun (USA).srm", "local/save", nil)
check(r == nil and why == "conflict", "unknown remote file is a conflict")
files["local/new"] = "MF-SAVE"
rev = assert(P.put("saves/gba/Metroid Fusion (USA).sav", "local/new", nil))
check(assets.saves[#assets.saves].file_name == "Metroid Fusion (USA).sav", "new save uploaded")
r, why = P.put("saves/gba/Unknown Game.srm", "local/new", nil)
check(r == nil and why:find("no gba game named Unknown Game", 1, true), "no ROM, clear message")
r, why = P.put("states/gba/Golden Sun (USA).slot2.png", "local/new", nil)
check(r == nil and why:find("not on RomM yet", 1, true), "picture before its state refused")
files["local/state"] = "GS-STATE"
assert(P.put("states/gba/Golden Sun (USA).slot2.state", "local/state", nil))
files["local/png"] = "PNG2"
rev = assert(P.put("states/gba/Golden Sun (USA).slot2.png", "local/png", nil))
check(content["screenshots/" .. assets.screenshots[#assets.screenshots].id] == "PNG2", "picture uploaded")
r, why = P.put("games/gba/Golden Sun (USA).gba", "local/new", nil)
check(r == nil and why:find("does not upload games", 1, true), "games are download only")
r, why = P.put("config/settings.json", "local/new", nil)
check(r == nil, "config refused")

-- token refresh: an expired access token is refreshed once, with the new refresh token kept
local before = secrets.refresh_token
for k in pairs(valid_access) do valid_access[k] = nil end
check(P.list("saves/"), "list after the access token expired")
check(secrets.refresh_token ~= before and valid_refresh[secrets.refresh_token], "rotated refresh token kept")

-- a save changed on the server: its rev moves, so RomM's own time counts again
local gs = assets.saves[1]
gs.updated_at = "2026-11-20T00:00:00Z"
listed = by_path(assert(P.list("saves/")))["saves/gba/Golden Sun (USA).srm"]
check(listed.modified ~= 1763000000, "a kept time is dropped once the rev changed")

-- delete
check(P.delete("states/gba/Golden Sun (USA).slot2.png"), "delete picture")
check(P.delete("saves/gba/Metroid Fusion (USA).sav"), "delete save")
check(not by_path(P.list("saves/"))["saves/gba/Metroid Fusion (USA).sav"], "deleted save gone")
check(P.delete("saves/gba/Metroid Fusion (USA).sav"), "deleting a missing file is fine")

-- server-side version bump below the minimum stops listing
P.forget()
server.version = "5.0.0"
r, why = P.list(nil)
check(r == nil and why:find("update the server", 1, true), "old server refused on sync")
server.version = "5.5.0-alpha.1"
P.forget()
check(P.list(nil), "pre-release of a newer version accepted")

-- games browser
plugin.actions.sync_now()
check(sync.synced == 1, "Sync now")
plugin.actions.games()
check(#ui.stack == 2 and find_el(page(), "label", "PlayStation"), "platforms listed")
check(not find_el(page(), "label", "Amiga"), "unmapped platforms hidden")
plugin.actions.platform(2)
check(find_el(page(), "arg", 20).value:find("3 files", 1, true), "multi-file game shown")
plugin.actions.download(20)
local d = sync.downloads[1]
check(#d == 3 and d[1] == "games/psx/Final Fantasy VII (USA).m3u", "download hands all files")
check(ui.toasts[#ui.toasts] == "Final Fantasy VII is in your library.", "download done once it returns")
plugin.actions.platform(1)
check(find_el(page(), "id", "more"), "long list is paged")

-- sign out forgets the token and the user
plugin.actions.sign_out()
check(secrets.refresh_token == nil and storage.user == nil and storage.server, "signed out")
r, why = P.list("saves/")
check(r == nil and why:find("Not signed in", 1, true), "provider refuses when signed out")

print(string.format("ok: %d checks, %d requests", passed, #server.requests))
