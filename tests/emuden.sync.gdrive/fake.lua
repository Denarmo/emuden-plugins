-- SPDX-FileCopyrightText: Copyright 2026 EmuDEN contributors
-- SPDX-License-Identifier: GPL-3.0-or-later

-- A fake `den` host and a fake Google (OAuth device flow and Drive v3) for test.lua.

local fake = {}

-- JSON ------------------------------------------------------------------------------------------

local null = setmetatable({}, { __tostring = function() return "null" end })
-- Like the host: an empty table encodes as [], unless it came from decoding {}.
local OBJECT = {}

local function encode(v)
  local t = type(v)
  if v == null or v == nil then return "null" end
  if t == "boolean" or t == "number" then return tostring(v) end
  if t == "string" then
    return '"' .. v:gsub('[%c"\\]', function(c)
      local map = { ['"'] = '\\"', ['\\'] = '\\\\', ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t' }
      return map[c] or string.format("\\u%04x", c:byte())
    end) .. '"'
  end
  if next(v) == nil then return getmetatable(v) == OBJECT and "{}" or "[]" end
  if #v > 0 then
    local out = {}
    for i = 1, #v do out[i] = encode(v[i]) end
    return "[" .. table.concat(out, ",") .. "]"
  end
  local keys, out = {}, {}
  for k in pairs(v) do keys[#keys + 1] = tostring(k) end
  table.sort(keys)
  for _, k in ipairs(keys) do out[#out + 1] = encode(k) .. ":" .. encode(v[k]) end
  return "{" .. table.concat(out, ",") .. "}"
end

local function decode(text)
  local pos = 1
  local function ws() pos = text:find("[^ \t\r\n]", pos) or #text + 1 end
  local value
  local function str()
    local out = {}
    pos = pos + 1
    while true do
      local c = text:sub(pos, pos)
      if c == '"' then pos = pos + 1; return table.concat(out) end
      if c == "\\" then
        local e = text:sub(pos + 1, pos + 1)
        if e == "u" then
          out[#out + 1] = utf8.char(tonumber(text:sub(pos + 2, pos + 5), 16)); pos = pos + 6
        else
          out[#out + 1] = ({ n = "\n", r = "\r", t = "\t", b = "\b", f = "\f" })[e] or e
          pos = pos + 2
        end
      else
        out[#out + 1] = c; pos = pos + 1
      end
    end
  end
  function value()
    ws()
    local c = text:sub(pos, pos)
    if c == "{" then
      local obj = setmetatable({}, OBJECT); pos = pos + 1; ws()
      if text:sub(pos, pos) == "}" then pos = pos + 1; return obj end
      while true do
        ws(); local k = str(); ws(); pos = pos + 1
        obj[k] = value(); ws()
        local d = text:sub(pos, pos); pos = pos + 1
        if d == "}" then return obj end
      end
    elseif c == "[" then
      local arr = {}; pos = pos + 1; ws()
      if text:sub(pos, pos) == "]" then pos = pos + 1; return arr end
      while true do
        arr[#arr + 1] = value(); ws()
        local d = text:sub(pos, pos); pos = pos + 1
        if d == "]" then return arr end
      end
    elseif c == '"' then return str()
    elseif text:sub(pos, pos + 3) == "true" then pos = pos + 4; return true
    elseif text:sub(pos, pos + 4) == "false" then pos = pos + 5; return false
    elseif text:sub(pos, pos + 3) == "null" then pos = pos + 4; return null
    else
      local num = text:match("^-?[%d.eE+-]+", pos); pos = pos + #num; return tonumber(num)
    end
  end
  local ok, result = pcall(value)
  return ok and result or nil
end

-- Fake Google -----------------------------------------------------------------------------------

local FOLDER = "application/vnd.google-apps.folder"

function fake.google()
  local g = { files = {}, next_id = 1, page_size = 2, log = {}, faults = {}, valid = {},
              refresh_tokens = {}, polls = 0, quota = { limit = "16106127360", usage = "5368709120" },
              sessions = {}, uploads = {} }

  local function new_id() g.next_id = g.next_id + 1; return "id" .. g.next_id end
  local function stamp(now) return string.format("2026-11-15T10:%02d:%02d.000Z", now // 60 % 60, now % 60) end
  local function reply(status, body, headers)
    return { status = status, body = body and encode(body) or "", headers = headers or {} }
  end
  local function unq(s) return (s:gsub("\\(.)", "%1")) end
  local function params(url)
    local out = {}
    for k, v in (url:match("%?(.*)$") or ""):gmatch("([^&=]+)=([^&]*)") do
      out[k] = v:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end)
    end
    return out
  end
  local function view(f)
    return { id = f.id, name = f.name, mimeType = f.mimeType, parents = f.parents,
             size = f.mimeType ~= FOLDER and tostring(#(f.content or "")) or nil,
             modifiedTime = f.modifiedTime, version = tostring(f.version), trashed = f.trashed }
  end
  local function matches(f, q)
    if f.trashed then return false end
    if q == "trashed = false" then return true end
    local name, parent, op, mime = q:match("^name = '(.-[^\\])' and '(.-)' in parents and "
      .. "trashed = false and mimeType (!?=) '(.-)'$")
    assert(name, "unexpected q: " .. q)
    name = unq(name)
    local in_parent = false
    for _, p in ipairs(f.parents or {}) do
      if p == parent or (parent == "root" and p == "myroot") then in_parent = true end
    end
    return f.name == name and in_parent and ((op == "=") == (f.mimeType == mime))
  end
  local function write(f, meta, content, now)
    for k, v in pairs(meta or {}) do f[k] = v end
    if content then f.content = content end
    f.version = (f.version or 0) + 1
    f.modifiedTime = meta and meta.modifiedTime or stamp(now)
  end

  function g.handle(req, fs, now)
    local url, method = req.url, req.method or "GET"
    g.log[#g.log + 1] = method .. " " .. url
    local fault = table.remove(g.faults, 1)
    if fault then return reply(fault.status, fault.body, fault.headers) end

    -- OAuth
    if url == "https://oauth2.googleapis.com/device/code" then
      assert(req.body:find("scope=https%%3A%%2F%%2Fwww.googleapis.com%%2Fauth%%2Fdrive.file"), req.body)
      return reply(200, { device_code = "DEV", user_code = "ABCD-EFGH", expires_in = 1800,
                          interval = 5, verification_url = "https://www.google.com/device" })
    elseif url == "https://oauth2.googleapis.com/token" then
      local form = params("?" .. req.body)
      if form.grant_type == "urn:ietf:params:oauth:grant-type:device_code" then
        g.polls = g.polls + 1
        if g.polls == 1 then return reply(428, { error = "authorization_pending" }) end
        if g.polls == 2 then return reply(403, { error = "slow_down" }) end
        if g.deny then return reply(403, { error = "access_denied" }) end
        g.refresh_tokens["R1"] = true
        local token = "A" .. g.polls; g.valid[token] = true
        return reply(200, { access_token = token, expires_in = 3599, refresh_token = "R1",
                            token_type = "Bearer", scope = "https://www.googleapis.com/auth/drive.file" })
      elseif form.grant_type == "refresh_token" then
        if not g.refresh_tokens[form.refresh_token] then return reply(400, { error = "invalid_grant" }) end
        local token = "B" .. new_id(); g.valid[token] = true
        return reply(200, { access_token = token, expires_in = 3599 })
      end
      return reply(400, { error = "unsupported_grant_type" })
    elseif url == "https://oauth2.googleapis.com/revoke" then
      g.refresh_tokens[params("?" .. req.body).token] = nil
      g.revoked = true
      return reply(200)
    end

    -- Drive: every call needs a valid access token
    local auth = (req.headers or {})["Authorization"] or ""
    if not g.valid[auth:match("^Bearer (.+)$") or ""] then
      return reply(401, { error = { code = 401, message = "Invalid Credentials" } })
    end
    local p = params(url)
    local session = url:match("^https://www.googleapis.com/upload/drive/v3/session/(%w+)$")
    if session then
      local s = g.sessions[session]
      if not s then return reply(404, { error = { code = 404, message = "Not Found" } }) end
      local range = req.headers["Content-Range"]
      if range and range:match("^bytes %*/") then
        g.status_queries = (g.status_queries or 0) + 1
        assert(range == "bytes */" .. s.total, "status query names the total: " .. range)
        if #s.received == 0 then return reply(308) end
        return reply(308, nil, { range = "bytes=0-" .. (#s.received - 1) })
      end
      local content = assert(fs[req.body_file], "no such body_file")
      local offset = req.body_offset or 0
      assert(#content == s.total, "X-Upload-Content-Length is the file's size")
      assert(offset == #s.received, "resumed at " .. offset .. ", Google has " .. #s.received)
      local length = (req.body_length or 0) > 0 and req.body_length or s.total - offset
      if offset > 0 or length < s.total then
        assert(range == string.format("bytes %d-%d/%d", offset, offset + length - 1, s.total),
               "Content-Range of the chunk: " .. tostring(range))
      end
      if offset > 0 then g.resumed = offset end
      local chunk = content:sub(offset + 1, offset + length)
      if g.cut then
        s.received = s.received .. chunk:sub(1, g.cut)
        g.cut = nil
        return nil, "the connection was reset"
      end
      s.received = s.received .. chunk
      g.chunks = (g.chunks or 0) + 1
      if #s.received < s.total then
        return reply(308, nil, { range = "bytes=0-" .. (#s.received - 1) })
      end
      g.uploads[#g.uploads + 1] = "resumable"
      local f = s.id and g.files[s.id] or { id = new_id() }
      g.files[f.id] = f
      write(f, s.meta, s.received, now)
      g.sessions[session] = nil
      return reply(200, view(f))
    end
    local api = url:find("/upload/drive/v3/", 1, true) and "upload" or "api"
    local id = url:match("/drive/v3/files/(%w+)") or ""
    if url:find("/drive/v3/about", 1, true) then
      return reply(200, { user = { displayName = "Test User", emailAddress = "test@example.com" },
                          storageQuota = g.quota })
    end
    if api == "upload" then
      local meta, content
      if p.uploadType == "multipart" then
        assert(req.multipart_type == "related" and req.body == nil and req.body_file == nil,
               "multipart/related built by the host")
        local parts = req.multipart
        assert(#parts == 2 and parts[1].content_type:find("application/json", 1, true))
        assert(parts[1].value:sub(1, 1) == "{", "metadata is a JSON object: " .. parts[1].value)
        meta = decode(parts[1].value)
        assert(parts[2].file and parts[2].content_type, "the file is the second part")
        content = assert(fs[parts[2].file], "no such part file")
        g.uploads[#g.uploads + 1] = "multipart"
      elseif p.uploadType == "resumable" then
        local key = new_id()
        g.sessions[key] = { meta = decode(req.body), id = id ~= "" and id or nil, received = "",
                            total = tonumber(req.headers["X-Upload-Content-Length"]) }
        return reply(200, nil, { location = "https://www.googleapis.com/upload/drive/v3/session/" .. key })
      end
      local f = id ~= "" and g.files[id] or { id = new_id() }
      g.files[f.id] = f
      write(f, meta, content, now)
      return reply(200, view(f))
    end
    if id == "" and method == "GET" then
      local list = {}
      for _, f in pairs(g.files) do if matches(f, p.q) then list[#list + 1] = f end end
      table.sort(list, function(a, b) return a.id < b.id end)
      local start = tonumber(p.pageToken or "1")
      local out = {}
      for i = start, math.min(#list, start + g.page_size - 1) do out[#out + 1] = view(list[i]) end
      local more = start + g.page_size <= #list and tostring(start + g.page_size) or nil
      return reply(200, { files = out,nextPageToken = more })
    elseif id == "" and method == "POST" then
      local meta = decode(req.body)
      local f = { id = new_id(), parents = meta.parents or { "myroot" } }
      meta.parents = nil
      write(f, meta, nil, now)
      g.files[f.id] = f
      return reply(200, view(f))
    end
    local f = g.files[id]
    if not f then return reply(404, { error = { code = 404, message = "File not found" } }) end
    if method == "GET" and p.alt == "media" then
      fs[req.to_file] = f.content
      if req.on_progress then req.on_progress(1) end
      return reply(200)
    elseif method == "GET" then
      return reply(200, view(f))
    elseif method == "PATCH" then
      write(f, decode(req.body), nil, now)
      return reply(200, view(f))
    end
    return reply(400)
  end
  return g
end

-- Fake den --------------------------------------------------------------------------------------

function fake.den(plugin_dir, google, opts)
  opts = opts or {}
  local d = { api = 1, plugin = { id = "emuden.sync.gdrive", version = "1.0.0" },
              device = { platform = "windows" } }
  local clock = 1763200000
  local storage, secrets, data_files = {}, {}, opts.data_files or {}
  d.fs = opts.fs or {}               -- temporary files the host hands the plugin
  d.pages, d.toasts, d.logs, d.slept, d.requests = {}, {}, {}, 0, 0
  d.sync_now_calls = 0
  d.storage_table, d.secrets_table = storage, secrets

  d.json = { encode = encode, decode = decode, null = null }
  d.log = function(text) d.logs[#d.logs + 1] = text end
  d.now = function() return clock end
  d.sleep = function(ms) d.slept = d.slept + ms; clock = clock + ms // 1000 end
  d.storage = { get = function(k) return storage[k] end, set = function(k, v) storage[k] = v end,
                remove = function(k) storage[k] = nil end }
  d.secrets = { get = function(k) return secrets[k] end, set = function(k, v) secrets[k] = v end,
                remove = function(k) secrets[k] = nil end }
  local function size_of(path)
    local s = data_files[path] or d.fs[path]
    if not s then return nil, "no such file" end
    return #s
  end
  local function read_file(path)
    local f = assert(io.open(path, "rb")); local s = f:read("a"); f:close(); return s
  end
  d.files = {
    read = function(path)
      if path:sub(1, 8) == "package/" then
        if opts.no_package_client and path == "package/oauth_client.json" then
          return nil, "no such file"
        end
        return read_file(plugin_dir .. path:sub(9))
      end
      local s = data_files[path] or d.fs[path]
      if not s then return nil, "no such file" end
      local limit = path:sub(1, 5) == "sync:" and 8 or 4
      if #s > limit * 1024 * 1024 then return nil, "file too large" end
      return s
    end,
    size = size_of,
    exists = function(path) return data_files[path] ~= nil or d.fs[path] ~= nil end,
  }
  d.include = function(path)
    return assert(loadfile(plugin_dir .. path, "t"))()
  end
  d.ui = {
    set = function(page) d.pages[#d.pages + 1] = page end,
    toast = function(text) d.toasts[#d.toasts + 1] = text end,
    confirm = function() return true end,
  }
  d.sync = {
    status = function()
      return { active = true, running = false, stopping = d.stopping and d.stopping() or false, last_sync = clock - 120, done = 4, total = 4,
               uploaded = 3, downloaded = 1, conflicts = 2, waiting = 0,
               errors = { "saves/gba/A.srm: no connection", "saves/gba/B.srm: no connection" },
               error = "saves/gba/A.srm: no connection" }
    end,
    now = function() d.sync_now_calls = d.sync_now_calls + 1; return true end,
    enabled_categories = function() return { "saves", "states" } end,
  }
  d.http = {
    request = function(req)
      d.requests = d.requests + 1
      assert(req.url:match("^https://oauth2%.googleapis%.com/") or req.url:match("^https://www%.googleapis%.com/"),
             "host not declared: " .. req.url)
      return google.handle(req, d.fs, clock)
    end,
  }
  return d
end

fake.null = null
return fake
