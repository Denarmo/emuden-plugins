-- SPDX-FileCopyrightText: Copyright 2026 EmuDEN contributors
-- SPDX-License-Identifier: GPL-3.0-or-later

-- An offline `den` for feature plugin tests, in plain Lua 5.4. docs/lua-api.md is the API it
-- copies; den_mock_json.lua and den_mock_apis.lua are parts of it. Run a test from the
-- repository root:
--   LUA_PATH="tests/?.lua;tests/<id>/?.lua;<plugin folder>/?.lua;;" DEN_PLUGIN_DIR=<plugin folder> lua tests/<id>/test.lua
--
--   local mock = require("den_mock")
--   local plugin = mock.load(os.getenv("DEN_PLUGIN_DIR") or "examples/jdoe.hello-feature", opts)
--
-- mock.load(dir, opts) reads <dir>/plugin.json, refuses it as the app would (unknown permission,
-- a permission without its `needs` capability or hosts, official-only permissions outside
-- emuden.*), runs the entry script in a sandbox (no os, io, package, debug, require, dofile,
-- loadfile, string.dump; load takes text only; print is den.log) and returns its table.
-- opts: now (Unix seconds), platform, strict (a call without its permission raises instead of
-- returning nil, message), user_server ("http://host:port", as if confirmed before), keep
-- (keep mock.storage, mock.secrets, mock.files and the server of the last load: a new start).
--
-- Running the plugin (every call runs in a fresh coroutine, as in the app):
--   mock.open(args)              plugin.open(args or {})
--   mock.action(name, arg, value) plugin.actions[name](arg, value), as if the user pressed it
--   mock.call("a.b", ...)        any entry point; returns true, results... or false, message
--   mock.provider(name, ...)     plugin.provider[name](...) as the sync engine calls it:
--                                true, results as JSON values, or false, message (an error,
--                                or nil, message returned); get/put also get a progress
--                                function (calls in mock.progress). list("") passes nil, as
--                                the app does today.
--   mock.lend(content) -> "sync:N"  a host file lent for one provider call; mock.lent[token]
--   mock.den, mock.manifest      the plugin's den table (call it from the test) and plugin.json
-- The world (all plain tables, change them freely):
--   mock.storage, mock.secrets   what den.storage and den.secrets hold
--   mock.files                   the plugin's data folder: { ["downloads/a.bin"] = content }
--   mock.http_route(pattern, response | function(req), method?)  answers den.http.* for URLs
--       matching the Lua pattern (the newest route first). A response is {status, body,
--       headers} or a body text; a function may return nil, message for "no answer".
--   mock.allow_methods("PROPFIND", ...)  lets methods through that the app refuses (experiments only)
--   mock.requests                every request: {kind, url, method, headers, body, upload, ...}
--   mock.answer(v, ...)          answers for the next asks, in order: confirm (true/false),
--                                set_server/use_folder (true/false or a folder), files.import
--                                ({name, content} or false). mock.asks records each ask.
--   mock.page(), mock.pages, mock.find(id), mock.toasts, mock.opened (URLs), mock.logs
--   mock.games, mock.hacks, mock.device_info, mock.game_settings, mock.steam,
--   mock.achievements, mock.web_files, mock.bookmarks, mock.downloads (device Downloads),
--   mock.sync_status, mock.sync_folder, mock.user_server, mock.clock
-- Checking: mock.check(cond, what); mock.finish() prints a summary and exits 1 when a check
-- failed, a plugin call failed (mock.errors), a call lacked its permission (mock.refusals) or a
-- request had no route (mock.unrouted). Clear those lists after a failure the test expects.

local M = {}
local unpack = table.unpack
local real_string_dump = string.dump
string.dump = nil -- strings share one metatable: plugins must not reach dump through it

local JSON = require("den_mock_json")
local json_encode, json_decode, NULL = JSON.encode, JSON.decode, JSON.null
M.null = NULL
M.json = { encode = json_encode, decode = json_decode, null = NULL }
local function copy(v) if v == nil then return nil end return (json_decode(json_encode(v))) end -- as values cross into the host

------------------------------------------------------------------------------------- state
local function reset()
  M.storage, M.secrets, M.files, M.lent = {}, {}, {}, {}
  M.logs, M.requests, M.asks, M.answers, M.toasts, M.opened = {}, {}, {}, {}, {}, {}
  M.pages, M.routes = {}, {}
  M.extra_methods = {}
  M.games, M.hacks, M.patch_facts, M.game_settings = {}, {}, {}, {}
  M.device_info = { name = "Test PC", known = true, os = "windows", cpu_cores = 8, ram_mb = 16384, handheld = false }
  M.steam = { installed = false, can_change = false, note = "", apps = {}, tools = {}, config = {} }
  M.achievements = { signed_in = false, hardcore = false, sound = true, screenshot = false, playing = "", games = {} }
  M.web_files, M.bookmarks, M.downloads, M.setups, M.games_downloaded = {}, {}, {}, {}, {}
  M.web_in_app, M.sync_folder, M.sync_categories, M.sync_now_calls = true, nil, nil, 0
  M.sync_status = { active = true, running = false, last_sync = 0, done = 0, total = 0, uploaded = 0,
                    downloaded = 0, conflicts = 0, waiting = 0, errors = {} }
end
reset()
-- Kept over mock.load, which starts the rest anew.
M.checks, M.failures, M.errors, M.refusals, M.unrouted = 0, 0, {}, {}, {}

function M.check(cond, what)
  M.checks = M.checks + 1
  if not cond then M.failures = M.failures + 1 print("FAIL: " .. tostring(what)) end
  return cond
end
function M.answer(...) for _, v in ipairs({ ... }) do M.answers[#M.answers + 1] = v end end
function M.allow_methods(...) for _, m in ipairs({ ... }) do M.extra_methods[m:upper()] = true end end
function M.http_route(pattern, response, method) table.insert(M.routes, 1, { pattern = pattern, response = response, method = method }) end
local next_lend = 0
function M.lend(content) next_lend = next_lend + 1 local t = "sync:" .. next_lend M.lent[t] = content or "" return t end
function M.page() return M.pages[#M.pages] end

local function find_in(list, id)
  for _, e in ipairs(list or {}) do
    if e.id == id then return e end
    local inner = find_in(e.items, id) or find_in(e.buttons, id) or (e.button and find_in({ e.button }, id))
    if inner then return inner end
  end
end
function M.find(id, page) return find_in((page or M.page() or {}).body, id) end

-------------------------------------------------------------------------------- the manifest
local CAPS = { ["kind.feature"] = 1, ["feature.lua.1"] = 1, ["feature.web.1"] = 1, ["feature.tune.1"] = 1,
               ["feature.achievements.1"] = 1, ["feature.browser.1"] = 1 }
local PERMS = { http = 0, download = 0, ["open-url"] = 0, browse = "feature.web.1", ["files.import"] = 0,
                ["downloads.watch"] = 0, ["library.read"] = 0, patch = 0, ["library.write"] = 0, sync = 0,
                ["http.user_host"] = 0, ["http.local"] = 0, ["device.info"] = "feature.tune.1",
                ["game.settings"] = "feature.tune.1", steam = "feature.tune.1", achievements = "feature.achievements.1",
                ["browse.any"] = "feature.browser.1", ["downloads.setup"] = "feature.browser.1" }
local OFFICIAL_ONLY = { ["downloads.watch"] = 1, ["browse.any"] = 1, ["downloads.setup"] = 1, achievements = 1 }

local function read_file(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local text = f:read("a") f:close()
  return text
end

local function check_manifest(m)
  local function need(ok, why) if not ok then error("plugin.json refused: " .. why, 0) end end
  need(type(m) == "table" and m.kind == "feature", "kind is not feature")
  need(type(m.id) == "string" and m.id:match("^[a-z0-9][a-z0-9%-]*%.[a-z0-9%-%.]*[a-z0-9]$"), "no valid id")
  need(m.name and m.version and (m.api or 0) >= 1 and m.api <= 1, "no valid name, version or api")
  local needs = {}
  for _, n in ipairs(m.needs or {}) do need(CAPS[n], "needs a newer EmuDEN (" .. n .. ")") needs[n] = true end
  need(needs["kind.feature"] and needs["feature.lua.1"], "needs must list kind.feature and feature.lua.1")
  local f = m.feature
  need(type(f) == "table" and type(f.entry) == "string" and f.entry:match("%.lua$"), "no feature.entry script")
  local official, perms = m.id:sub(1, 7) == "emuden.", {}
  for _, p in ipairs(f.permissions or need(false, "no permissions list")) do
    need(PERMS[p], 'the permission "' .. tostring(p) .. '" is not known')
    need(PERMS[p] == 0 or needs[PERMS[p]], p .. " needs " .. tostring(PERMS[p]) .. " in needs")
    need(official or not OFFICIAL_ONLY[p], p .. " is for EmuDEN's own plugins only")
    perms[p] = true
  end
  local http = f.http or {}
  need(not (perms.http or perms.download) or #(http.hosts or {}) > 0, "http and download need http.hosts")
  need(#(http.hosts or {}) <= 8, "http.hosts must name at most 8 hosts")
  need(not perms["open-url"] or #(f.open_hosts or {}) > 0, "open-url needs open_hosts")
  need(not perms.browse or #(f.browse_hosts or {}) > 0, "browse needs browse_hosts")
  local systems = {}
  for _, s in ipairs(f.systems or {}) do need(official or s ~= "*", 'only an official plugin may use systems ["*"]') systems[s] = true end
  local library = perms["library.read"] or perms.patch or perms["library.write"] or perms["game.settings"]
  need(not library or next(systems), "the library permissions need systems")
  if perms.sync then
    local s = f.sync or {}
    need(type(s.categories) == "table" and #s.categories > 0, "sync needs feature.sync.categories")
    local seen = {}
    for _, c in ipairs(s.categories) do
      need(({ saves = 1, states = 1, config = 1, games = 1, bios = 1 })[c] and not seen[c], "bad sync category " .. tostring(c))
      seen[c] = true
    end
    need(s.listing == nil or ({ category = 1, all = 1, per_folder = 1 })[s.listing], "feature.sync.listing is category, all or per_folder")
  else need(f.sync == nil, "feature.sync needs the sync permission") end
  return perms, systems, http.hosts or {}
end

-------------------------------------------------------------------------------- the runner
local manifest, perms, systems, hosts, dir, env, plugin_table, strict
local current, loading, from_user = nil, false, false
local BUDGET = 200000000

local function refuse(msg) return nil, msg end
local function denied(msg)
  M.refusals[#M.refusals + 1] = msg
  if strict then error(msg, 3) end
  return nil, msg
end
local function wait()
  if loading then error("The script may not wait while it loads; do that in plugin.open.", 3) end
  if coroutine.running() ~= current then
    error("a den call that waits must be made from the plugin's own function, not from a coroutine of the script", 3)
  end
end
local function take_answer(ask)
  M.asks[#M.asks + 1] = ask
  if #M.answers == 0 then error("the plugin asked (" .. ask.kind .. ": " .. tostring(ask.title) .. ") and the test gave no mock.answer", 3) end
  ask.answer = table.remove(M.answers, 1)
  return ask.answer
end

-- Runs fn in a fresh coroutine with the instruction budget; true, results... or false, message.
local function run(name, user, fn, ...)
  local co = coroutine.create(fn)
  local spent = 0
  debug.sethook(co, function()
    spent = spent + 1000
    if spent > BUDGET then error("the plugin ran too long without a pause and was stopped") end
  end, "", 1000)
  local saved, saved_user = current, from_user
  current, from_user = co, user
  local result = table.pack(coroutine.resume(co, ...))
  current, from_user = saved, saved_user
  if result[1] and coroutine.status(co) == "suspended" then result = { false, "The script paused outside a den call.", n = 2 } end
  if not result[1] then M.errors[#M.errors + 1] = name .. ": " .. tostring(result[2]) end
  return unpack(result, 1, result.n)
end

local function safe_path(p)
  if type(p) ~= "string" then return false end
  if p:find("^[/\\]") or p:find(":") or p:find("\\") then return false end
  for part in p:gmatch("[^/]+") do if part == ".." then return false end end
  return true
end
-- A file of the plugin's folder or a lent one: returns a getter and a setter of its content.
local function resolve(p, package_ok)
  if type(p) == "string" and p:sub(1, 5) == "sync:" then
    if M.lent[p] == nil then return nil, "that file was lent for another call" end
    return function() return M.lent[p] end, function(c) M.lent[p] = c end, true
  end
  if not safe_path(p) then return nil, "the path leaves the plugin's folder" end
  if p:sub(1, 8) == "package/" then
    if not package_ok then return nil, "the package cannot be changed" end
    return function() return read_file(dir .. "/" .. p:sub(9)) end, nil
  end
  return function() return M.files[p] end, function(c) M.files[p] = c end
end

local function parse_url(url)
  local scheme, rest = tostring(url):match("^(%a[%w+.-]*)://(.*)$")
  if not scheme then return nil end
  local authority = rest:match("^[^/?#]*")
  if authority == "" or authority:find("@") then return nil end
  local host, port = authority:match("^(.-):(%d+)$")
  return { scheme = scheme:lower(), host = (host or authority):lower(), port = tonumber(port) }
end
local function origin_of(u)
  local o = u.scheme .. "://" .. u.host
  if u.port and u.port ~= (u.scheme == "https" and 443 or 80) then o = o .. ":" .. u.port end
  return o
end
local function check_declared(url, list)
  local u = parse_url(url)
  if not u then return nil, "that is not a web address" end
  if u.scheme ~= "https" or (u.port and u.port ~= 443) then return nil, "only https addresses are allowed" end
  for _, h in ipairs(list) do if h == u.host then return true end end
  return nil, "the plugin did not declare the host " .. u.host
end
local function declared_hosts() return (perms.http or perms.download) and hosts or {} end
local function allowed_request(url)
  local u = parse_url(url)
  if not u or (u.scheme ~= "http" and u.scheme ~= "https") then return nil, "that is not a web address" end
  if perms["http.local"] and (u.host == "127.0.0.1" or u.host == "localhost") then
    if not u.port then return nil, "an app on this device is reached with its port" end
    return "local"
  end
  if perms["http.user_host"] and M.user_server and origin_of(u) == M.user_server then return "user" end
  local ok, why = check_declared(url, declared_hosts())
  if not ok then return nil, why end
  return "declared"
end

-- Answers a recorded request from the routes.
local function answer(req)
  for _, r in ipairs(M.routes) do
    if req.url:find(r.pattern) and (not r.method or r.method:upper() == req.method) then
      local resp, why = r.response
      if type(resp) == "function" then resp, why = resp(req) end
      if resp == nil then return nil, why or "no answer from " .. parse_url(req.url).host end
      if type(resp) == "string" then resp = { status = 200, body = resp } end
      local headers = {}
      for k, v in pairs(resp.headers or {}) do headers[k:lower()] = v end
      return { status = resp.status or 200, body = resp.body or "", headers = headers }
    end
  end
  M.unrouted[#M.unrouted + 1] = req.method .. " " .. req.url
  return nil, "no answer from " .. parse_url(req.url).host .. " (the test has no mock.http_route for it)"
end

local function progress_of(fn)
  if type(fn) ~= "function" then return function() end end
  return function(f) run("on_progress", false, fn, f) end
end

local function text_headers(t)
  local out = {}
  for k, v in pairs(type(t) == "table" and t or {}) do if type(k) == "string" and type(v) == "string" then out[k] = v end end
  return out
end

---------------------------------------------------------------------------------------- den
local function build_den(opts)
  local den = { api = 1, json = M.json, plugin = { id = manifest.id, version = manifest.version },
                device = { platform = opts.platform or "windows" } }
  function den.log(text)
    local line = tostring(text):sub(1, 4000)
    M.logs[#M.logs + 1] = line
    if os.getenv("DEN_MOCK_VERBOSE") then print("[log] " .. line) end
  end
  function den.now() return M.clock end
  function den.sleep(ms) wait() M.clock = M.clock + math.max(0, math.min(ms, 600000)) // 1000 end
  function den.include(name)
    local text = name:match("%.lua$") and safe_path(name) and read_file(dir .. "/" .. name)
    for lib in (read_file(dir .. "/.shared") or ""):gmatch("[^\r\n]+") do
      text = text or (name:match("%.lua$") and read_file("shared/" .. lib .. "/" .. name))
    end
    if not text then error("include: " .. name .. " is not a script of the package", 2) end
    return assert(load(text, "@" .. name, "t", env))()
  end

  local function storage_like(name, check_key, limit, what)
    return {
      get = function(k) if not check_key(k) then return refuse("bad key") end return copy(M[name][k]) end,
      set = function(k, v)
        if not check_key(k) then return refuse(name == "secrets" and "a secret's name is up to 64 letters, digits, '.', '_' or '-'" or "the plugin's storage is full (1 MiB)") end
        local before = M[name][k]
        M[name][k] = copy(v)
        if #json_encode(M[name]) > limit then M[name][k] = before return refuse(what) end
        return true
      end,
      remove = function(k) local had = M[name][k] ~= nil M[name][k] = nil return had end,
      keys = function() local out = {} for k in pairs(M[name]) do out[#out + 1] = k end table.sort(out) return out end,
    }
  end
  den.storage = storage_like("storage", function(k) return type(k) == "string" and #k > 0 and #k <= 200 end,
                             1 << 20, "the plugin's storage is full (1 MiB)")
  den.secrets = storage_like("secrets", function(k) return type(k) == "string" and k:match("^[%w%._%-]+$") and #k <= 64 end,
                             2048 * 32, "a secret is at most 2 KiB")
  den.secrets.keys = nil
  local secret_set = den.secrets.set
  den.secrets.set = function(k, v)
    if #json_encode(v) > 2048 then return refuse("a secret is at most 2 KiB") end
    return secret_set(k, v)
  end
  den.secrets.remove = function(k) M.secrets[k] = nil return true end

  den.http = {}
  function den.http.get(o)
    if not perms.http then return denied("the plugin has no permission to connect (http)") end
    local ok, why = check_declared(o.url, hosts)
    if not ok then return refuse(why) end
    wait()
    local req = { kind = "get", url = o.url, method = "GET", headers = text_headers(o.headers), cache_seconds = o.cache_seconds }
    M.requests[#M.requests + 1] = req
    local resp, err = answer(req)
    if not resp then return refuse(err) end
    return { status = resp.status, body = resp.body, headers = {}, cached = false }
  end
  function den.http.request(o)
    if not (perms.http or perms["http.user_host"] or perms["http.local"]) then return denied("the plugin has no permission to connect") end
    local route, why = allowed_request(o.url)
    if not route then return refuse(why) end
    local method = (o.method or "GET"):upper()
    local known = { GET = 1, POST = 1, PUT = 1, PATCH = 1, DELETE = 1, HEAD = 1 }
    if not known[method] and not M.extra_methods[method] then return refuse("the method must be GET, POST, PUT, PATCH, DELETE or HEAD") end
    if o.body and #o.body > 8 << 20 then return refuse("the body is larger than 8 MiB") end
    local req = { kind = "request", url = o.url, method = method, headers = text_headers(o.headers), body = o.body,
                  body_file = o.body_file, to_file = o.to_file, route = route }
    if o.body_file then
      local get, err = resolve(o.body_file)
      if not get then return refuse(err) end
      if get() == nil then return refuse("body_file is not a file") end
      local offset, length = o.body_offset or 0, o.body_length or 0
      req.upload = get():sub(offset + 1, length > 0 and offset + length or nil)
    end
    if type(o.multipart) == "table" and #o.multipart > 0 then
      req.multipart = {}
      for i, p in ipairs(o.multipart) do
        local part = { name = p.name, value = p.value or p.body, filename = p.filename, content_type = p.content_type, headers = p.headers }
        local file = p.file or p.body_file
        if file then
          local get, err = resolve(file)
          if not get then return refuse(err) end
          part.value = get()
        end
        req.multipart[i] = part
      end
    end
    local given = (o.body and #o.body > 0 and 1 or 0) + (o.body_file and 1 or 0) + (req.multipart and 1 or 0)
    if given > 1 then return refuse("give one of body, body_file and multipart") end
    local set_file
    if o.to_file then
      local _, setter = resolve(o.to_file)
      if not setter then return refuse("the path leaves the plugin's folder") end
      set_file = setter
    end
    wait()
    M.requests[#M.requests + 1] = req
    local resp, err = answer(req)
    if not resp then return refuse(err) end
    if set_file and resp.status >= 200 and resp.status < 300 then
      set_file(resp.body)
      progress_of(o.on_progress)(1.0)
      resp.body = ""
    end
    return resp
  end

  function den.download(o)
    if not perms.download then return denied("the plugin has no permission to download files") end
    local ok, why = check_declared(o.url, hosts)
    if not ok then return refuse(why) end
    if type(o.name) ~= "string" or o.name == "" or o.name:find("[/\\]") or o.name:sub(1, 1) == "." then return refuse("name must be a plain file name") end
    wait()
    local req = { kind = "download", url = o.url, method = "GET", headers = {}, name = o.name }
    M.requests[#M.requests + 1] = req
    local resp, err = answer(req)
    if not resp then return refuse(err) end
    if resp.status < 200 or resp.status >= 300 then return refuse("the server answered " .. resp.status) end
    M.files["downloads/" .. o.name] = resp.body
    progress_of(o.on_progress)(1.0)
    return "downloads/" .. o.name
  end
  function den.open_url(url)
    if not perms["open-url"] then return denied("the plugin has no permission to open pages") end
    local ok, why = check_declared(url, manifest.feature.open_hosts or {})
    if not ok then return refuse(why) end
    if not from_user then return refuse("a page is opened in the browser only when the user asks for it") end
    M.opened[#M.opened + 1] = url
    return true
  end

  local KNOWN = { shelf = 1, grid = 1, tile = 1, detail = 1, text = 1, image = 1, button = 1, row = 1, input = 1,
                  progress = 1, empty = 1, qr = 1 }
  local function clean(list, fallback)
    local out = {}
    for _, e in ipairs(list or {}) do
      local t = e.type or fallback
      if type(e) == "table" and KNOWN[t] then
        e.type = t
        if e.items then e.items = clean(e.items, "tile") end
        if e.buttons then e.buttons = clean(e.buttons, "button") end
        if e.button then e.button = clean({ e.button }, "button")[1] end
        out[#out + 1] = e
      else print("mock: an element of unknown type " .. tostring(t) .. " is left out, as the app does") end
    end
    return out
  end
  local function page_of(p) assert(type(p) == "table", "a page is a table") p = copy(p) p.body = clean(p.body) return p end
  den.ui = {
    set = function(p) M.pages[math.max(#M.pages, 1)] = page_of(p) end,
    push = function(p)
      if #M.pages >= 8 then return refuse("the plugin already shows 8 pages on top of each other") end
      M.pages[#M.pages + 1] = page_of(p)
      return true
    end,
    pop = function() if #M.pages > 1 then M.pages[#M.pages] = nil else M.popped_out = true end end,
    depth = function() return #M.pages end,
    patch = function(id, fields)
      for i = #M.pages, 1, -1 do
        local e = M.find(id, M.pages[i])
        if e then for k, v in pairs(copy(fields)) do if k ~= "id" then e[k] = v end end return true end
      end
      return false
    end,
    toast = function(text) M.toasts[#M.toasts + 1] = tostring(text) end,
    confirm = function(o)
      wait()
      return take_answer({ kind = "confirm", title = o.title, message = o.message, yes = o.yes }) == true
    end,
  }
  den.app = { open_game = function(id) M.opened[#M.opened + 1] = "game:" .. id end }

  require("den_mock_apis")(den, { M = M, perms = perms, systems = systems, manifest = manifest, null = NULL,
    wait = wait, refuse = refuse, denied = denied, take_answer = take_answer, copy = copy,
    check_declared = check_declared, safe_path = safe_path, resolve = resolve, user = function() return from_user end })
  if perms.sync then
    den.sync = {
      status = function() return copy(M.sync_status) end,
      now = function()
        if not M.sync_status.active then return refuse("the plugin is not the active provider") end
        M.sync_now_calls = M.sync_now_calls + 1
        return true
      end,
      enabled_categories = function() return copy(M.sync_categories or manifest.feature.sync.categories) end,
      folder = function() return M.sync_folder end,
      use_folder = function(path)
        wait()
        local a = take_answer({ kind = path and "confirm" or "folder", title = path and "Keep the sync files here?" or "Choose the folder to sync", value = path })
        if not a then return refuse(path and "declined" or "no folder was chosen") end
        M.sync_folder = path or a
        return M.sync_folder
      end,
      set_server = function(url)
        if not perms["http.user_host"] then return denied("the plugin has no permission to connect to a server you enter (http.user_host)") end
        local u = parse_url(url)
        if not u or (u.scheme ~= "http" and u.scheme ~= "https") then return refuse("that is not a web address") end
        local origin = origin_of(u)
        if origin == M.user_server then return true end
        wait()
        if not take_answer({ kind = "confirm", title = "Connect to " .. u.host .. "?", value = origin }) then return refuse("declined") end
        M.user_server = origin
        return true
      end,
      download_game = function(paths)
        if type(paths) == "string" then paths = { paths } end
        if type(paths) ~= "table" or #paths == 0 then return refuse("name the game's files") end
        wait()
        M.games_downloaded[#M.games_downloaded + 1] = copy(paths)
        return true
      end,
    }
  end
  return den
end

----------------------------------------------------------------------------------- loading
local function sandbox(den)
  local e = {}
  for _, k in ipairs({ "assert", "error", "getmetatable", "ipairs", "next", "pairs", "pcall", "rawequal", "rawget",
                       "rawlen", "rawset", "select", "setmetatable", "tonumber", "tostring", "type", "xpcall", "warn", "_VERSION" }) do
    e[k] = _G[k]
  end
  for _, lib in ipairs({ "string", "table", "math", "utf8", "coroutine" }) do
    e[lib] = {}
    for k, v in pairs(_G[lib]) do e[lib][k] = v end
  end
  e.load = function(text, name, _, chunk_env)
    if type(text) ~= "string" then return nil, "load takes the script as text" end
    return load(text, name or "=(load)", "t", chunk_env or e)
  end
  e.collectgarbage = function(what)
    if what == nil then collectgarbage() return 0 end
    if what == "count" then return collectgarbage("count") end
    error("collectgarbage takes no arguments here", 2)
  end
  e.print, e.den, e._G = den.log, den, e
  return e
end

function M.load(folder, opts)
  opts = opts or {}
  local kept = opts.keep and { M.storage, M.secrets, M.files, M.user_server }
  reset()
  if kept then M.storage, M.secrets, M.files, opts.user_server = kept[1], kept[2], kept[3], opts.user_server or kept[4] end
  dir, strict = (folder or "."):gsub("[/\\]$", ""), opts.strict
  M.clock, M.user_server, M.dir = opts.now or 1794700000, opts.user_server, dir
  local text = read_file(dir .. "/plugin.json") or error("no plugin.json in " .. dir, 2)
  manifest = json_decode(text) or error("plugin.json is not JSON", 2)
  M.manifest = manifest
  perms, systems, hosts = check_manifest(manifest)
  env = sandbox(build_den(opts))
  M.den = env.den
  local script = read_file(dir .. "/" .. manifest.feature.entry) or error("the entry script cannot be read", 2)
  local chunk = assert(load(script, "@" .. manifest.feature.entry, "t", env))
  loading = true
  local ok, result = run("load", false, chunk)
  loading = false
  if not ok then error("the script did not load: " .. tostring(result), 2) end
  if type(result) ~= "table" then error("The script must return its table of entry points.", 2) end
  plugin_table = result
  return result
end

-- Entry points by dotted path; a missing function is skipped like the app does.
function M.call(path, ...)
  local fn = plugin_table
  for part in path:gmatch("[^.]+") do fn = type(fn) == "table" and rawget(fn, part) or nil end
  if type(fn) ~= "function" then return false, "the plugin has no " .. path end
  local args = table.pack(...)
  for i = 1, args.n do if args[i] ~= nil and type(args[i]) ~= "function" then args[i] = copy(args[i]) end end
  return run(path, path:sub(1, 8) == "actions.", fn, unpack(args, 1, args.n))
end
function M.open(args) return M.call("open", args or {}) end
function M.action(name, arg, value) return M.call("actions." .. name, arg, value or "") end

-- As the sync engine invokes plugin.provider.<name>: true and the values as JSON, or false and why.
function M.provider(name, ...)
  local args = table.pack(...)
  if name == "list" and args[1] == "" then args[1] = nil end
  if name == "get" or name == "put" then
    M.progress = {}
    args.n = name == "get" and 3 or 5
    args[args.n] = function(done, total) M.progress[#M.progress + 1] = { done, total } end
  end
  local result = table.pack(M.call("provider." .. name, unpack(args, 1, args.n)))
  if not result[1] then return false, result[2] end
  if result.n >= 2 and result[2] == nil then return false, type(result[3]) == "string" and result[3] or "the plugin returned nothing" end
  local values = {}
  for i = 2, result.n do values[i - 1] = copy(result[i]) end
  return true, unpack(values, 1, result.n - 1)
end

function M.finish()
  local problems = 0
  for _, list in ipairs({ { M.errors, "plugin call failed" }, { M.refusals, "call without its permission" },
                          { M.unrouted, "request without a mock.http_route" } }) do
    for _, item in ipairs(list[1]) do problems = problems + 1 print("FAIL (" .. list[2] .. "): " .. item) end
  end
  local failed = M.failures + problems
  print(string.format("%d checks, %d failed", M.checks, failed))
  string.dump = real_string_dump
  os.exit(failed == 0 and 0 or 1)
end

return M
