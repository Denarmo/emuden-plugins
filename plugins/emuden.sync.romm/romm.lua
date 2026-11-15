-- SPDX-FileCopyrightText: Copyright 2026 EmuDEN contributors
-- SPDX-License-Identifier: GPL-3.0-or-later

-- A small client of RomM's REST API, checked against RomM 5.4.1 (rommapp/romm, tag 5.4.1):
-- POST /api/token (OAuth2 password and refresh_token grants), GET /api/heartbeat,
-- GET /api/users/me, GET /api/platforms, GET /api/roms (limit/offset pages),
-- GET /api/roms/{id}/content/{file name}, /api/saves and /api/states (list, add, update,
-- content, delete), GET /api/screenshots/{id}/content.
-- The password is only sent to /api/token and never kept; the refresh token is kept in
-- den.secrets. RomM's refresh tokens are single use, so each refresh stores the new one.

local names = den.include("names.lua")

local romm = {}

romm.TESTED = "5.4.1"
local MIN_VERSION = names.version(romm.TESTED)
local SCOPES = "me.read roms.read platforms.read assets.read assets.write"
local PAGE = 200
local SECRET = "refresh_token"

local access, access_until = nil, 0
local refreshing = false

local function value(v)
  if v == nil or v == den.json.null then
    return nil
  end
  return v
end
romm.value = value

function romm.server()
  return den.storage.get("server")
end

local function detail_of(response)
  local body = response.body and den.json.decode(response.body)
  local detail = type(body) == "table" and value(body.detail)
  if type(detail) == "string" then
    return detail
  end
  return "HTTP " .. tostring(response.status)
end

local function form(fields)
  local parts = {}
  for _, pair in ipairs(fields) do
    parts[#parts + 1] = pair[1] .. "=" .. names.urlencode(pair[2])
  end
  return table.concat(parts, "&")
end

-- The server's version, refused when older than the one this plugin was checked with.
function romm.check_version(server)
  local response, why = den.http.request{ url = server .. "/api/heartbeat" }
  if not response then
    return nil, "Could not reach " .. server .. ": " .. tostring(why)
  end
  if response.status ~= 200 then
    return nil, server .. " did not answer as a RomM server (" .. detail_of(response) .. ")."
  end
  local beat = den.json.decode(response.body or "")
  local text = type(beat) == "table" and type(beat.SYSTEM) == "table" and value(beat.SYSTEM.VERSION)
  if not text then
    return nil, server .. " did not answer as a RomM server."
  end
  local version = names.version(text)
  if not version then
    -- A build from source ("development") has no number to compare.
    den.log("RomM reports version " .. tostring(text) .. "; not checked")
    return text
  end
  if names.older(version, MIN_VERSION) then
    return nil, "This RomM server runs version " .. text .. ". EmuDEN works with RomM " ..
        romm.TESTED .. " or newer; update the server to sync with it."
  end
  return text
end

local function take_tokens(body)
  local tokens = den.json.decode(body or "")
  if type(tokens) ~= "table" or not value(tokens.access_token) then
    return nil, "RomM sent no token."
  end
  access = tokens.access_token
  access_until = den.now() + (tonumber(value(tokens.expires)) or 1800) - 60
  if value(tokens.refresh_token) then
    den.secrets.set(SECRET, tokens.refresh_token)
  end
  return true
end

local function token_request(fields)
  local server = romm.server()
  if not server then
    return nil, "No RomM server is set."
  end
  local response, why = den.http.request{
    url = server .. "/api/token", method = "POST",
    headers = { ["Content-Type"] = "application/x-www-form-urlencoded",
                Accept = "application/json" },
    body = form(fields),
  }
  if not response then
    return nil, "Could not reach " .. server .. ": " .. tostring(why)
  end
  if response.status ~= 200 then
    return nil, detail_of(response), response.status
  end
  return take_tokens(response.body)
end

-- Exchanges the user name and password for tokens. The caller forgets the password.
function romm.sign_in(user, password)
  local ok, why, status = token_request{ { "grant_type", "password" }, { "username", user },
                                         { "password", password }, { "scope", SCOPES } }
  if not ok then
    if status == 401 then
      return nil, "Wrong user name or password."
    elseif status == 403 then
      return nil, "RomM refused the sign-in: " .. why ..
          " (the user needs to see ROMs and platforms and to upload saves)."
    end
    return nil, why
  end
  local me, err = romm.get_json("/api/users/me")
  if not me then
    return nil, err
  end
  den.storage.set("user", value(me.username) or user)
  return true
end

function romm.signed_in()
  return den.secrets.get(SECRET) ~= nil
end

function romm.sign_out()
  access, access_until = nil, 0
  den.secrets.remove(SECRET)
  den.storage.remove("user")
end

local function refresh()
  while refreshing do
    den.sleep(100)
  end
  if access and den.now() < access_until then
    return true
  end
  local token = den.secrets.get(SECRET)
  if not token then
    return nil, "Not signed in to RomM."
  end
  refreshing = true
  local ok, why, status = token_request{ { "grant_type", "refresh_token" },
                                         { "refresh_token", token } }
  refreshing = false
  if not ok and (status == 401 or status == 403 or status == 400) then
    romm.sign_out()
    return nil, "RomM signed this device out. Sign in again on the RomM page."
  end
  return ok, why
end

-- One API call with the bearer token; a 401 refreshes the token once and tries again.
-- opts: method, query, json, multipart, to_file, on_progress. Returns the response.
function romm.call(path, opts)
  opts = opts or {}
  local server = romm.server()
  if not server then
    return nil, "No RomM server is set."
  end
  for attempt = 1, 2 do
    if not access or den.now() >= access_until then
      local ok, why = refresh()
      if not ok then
        return nil, why
      end
    end
    local headers = { Authorization = "Bearer " .. access, Accept = "application/json" }
    local body
    if opts.json then
      headers["Content-Type"] = "application/json"
      body = den.json.encode(opts.json)
    end
    local response, why = den.http.request{
      url = server .. path .. (opts.query and ("?" .. form(opts.query)) or ""),
      method = opts.method or "GET", headers = headers, body = body,
      multipart = opts.multipart, to_file = opts.to_file, on_progress = opts.on_progress,
    }
    if not response then
      return nil, "Could not reach " .. server .. ": " .. tostring(why)
    end
    if response.status == 401 and attempt == 1 then
      access, access_until = nil, 0
    elseif response.status >= 200 and response.status < 300 then
      return response
    else
      return nil, "RomM: " .. detail_of(response), response.status
    end
  end
  return nil, "RomM did not accept the token."
end

function romm.get_json(path, query)
  local response, why, status = romm.call(path, { query = query })
  if not response then
    return nil, why, status
  end
  local data = den.json.decode(response.body or "")
  if data == nil then
    return nil, "RomM sent an answer EmuDEN cannot read."
  end
  return data
end

-- Platforms EmuDEN has a console for: { {id, slug, name, rom_count, system} }.
function romm.platforms()
  local list, why = romm.get_json("/api/platforms")
  if not list then
    return nil, why
  end
  local out = {}
  for _, p in ipairs(list) do
    local system = names.SYSTEM_OF[value(p.slug) or ""]
    if system then
      out[#out + 1] = { id = p.id, slug = p.slug, system = system,
                        name = value(p.custom_name) or value(p.name) or p.slug,
                        rom_count = value(p.rom_count) or 0 }
    end
  end
  table.sort(out, function(a, b) return a.name:lower() < b.name:lower() end)
  return out
end

-- The game files of a ROM as RomM lists them (with_files): the top-level ones or category game.
local function game_files(rom)
  local out = {}
  for _, f in ipairs(value(rom.files) or {}) do
    local category = value(f.category)
    if category == "game" or (category == nil and f.is_top_level) then
      out[#out + 1] = { id = f.id, name = f.file_name, size = value(f.file_size_bytes) or 0,
                        updated_at = value(f.updated_at) }
    end
  end
  if #out == 0 then
    out[1] = { name = rom.fs_name, size = value(rom.fs_size_bytes) or 0,
               updated_at = value(rom.updated_at) }
  end
  return out
end

-- One page of a platform's ROMs: { {id, name, files = {...}, size, updated_at} }, total.
function romm.roms_page(platform_id, offset, limit)
  local page, why = romm.get_json("/api/roms", {
    { "platform_ids", platform_id }, { "limit", limit or PAGE }, { "offset", offset or 0 },
    { "with_files", "true" }, { "with_char_index", "false" },
    { "with_filter_values", "false" }, { "with_rom_id_index", "false" },
    { "order_by", "name" }, { "order_dir", "asc" },
  })
  if not page then
    return nil, why
  end
  local out = {}
  for _, rom in ipairs(value(page.items) or {}) do
    local files = game_files(rom)
    local size = 0
    for _, f in ipairs(files) do
      size = size + f.size
    end
    out[#out + 1] = { id = rom.id, name = value(rom.name) or rom.fs_name_no_ext,
                      fs_name = rom.fs_name, stem = value(rom.fs_name_no_ext),
                      files = files, size = size, updated_at = value(rom.updated_at) }
  end
  return out, value(page.total)
end

function romm.all_roms(platform_id)
  local all, offset = {}, 0
  while true do
    local page, total = romm.roms_page(platform_id, offset, PAGE)
    if not page then
      return nil, total
    end
    for _, rom in ipairs(page) do
      all[#all + 1] = rom
    end
    offset = offset + #page
    if #page < PAGE or (total and offset >= total) then
      return all
    end
  end
end

-- kind: "saves" or "states".
function romm.assets(kind, query)
  return romm.get_json("/api/" .. kind, query)
end

function romm.asset(kind, id)
  return romm.get_json("/api/" .. kind .. "/" .. id)
end

function romm.upload(kind, id, rom_id, field, local_path, file_name)
  local part = { { name = field, file = local_path, filename = file_name,
                   content_type = "application/octet-stream" } }
  local response, why, status
  if id then
    response, why, status = romm.call("/api/" .. kind .. "/" .. id,
                                      { method = "PUT", multipart = part })
  else
    response, why, status = romm.call("/api/" .. kind,
                                      { method = "POST", query = { { "rom_id", rom_id } },
                                        multipart = part })
  end
  if not response then
    return nil, why, status
  end
  return den.json.decode(response.body or "") or {}
end

function romm.remove(kind, id)
  local response, why, status = romm.call("/api/" .. kind .. "/delete",
                                          { method = "POST", json = { [kind] = { id } } })
  if not response and status ~= 404 then
    return nil, why
  end
  return true
end

function romm.remove_screenshot(id)
  local response, why, status = romm.call("/api/screenshots/" .. id, { method = "DELETE" })
  if not response and status ~= 404 then
    return nil, why
  end
  return true
end

function romm.download(path, query, local_path, on_progress)
  local response, why = romm.call(path, { query = query, to_file = local_path,
                                          on_progress = on_progress })
  if not response then
    return nil, why
  end
  return true
end

return romm
