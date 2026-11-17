-- SPDX-FileCopyrightText: Copyright 2026 EmuDEN contributors
-- SPDX-License-Identifier: GPL-3.0-or-later

-- plugin.provider (docs/sync.md section 5) on RomM: portable names map to the saves and
-- states of the ROM found by platform plus file name, and to the ROMs' own files.
--   saves/<system>/<stem>.<ext>            a RomM save of that ROM named <stem>.<ext>
--   states/<system>/<stem>.slot<N>.state   a RomM state of that ROM (also .resume.state)
--   states/<system>/<stem>.slot<N>.png     the screenshot RomM keeps with that state
--   games/<system>/<file name>             a game file of the ROM (download only)
-- rev is the remote updated_at (the id when it has none). RomM's updated_at is when the file
-- reached the server, so the time put() was given is kept here per file and rev, and list()
-- gives it back while the rev is still the same.

local names = den.include("names.lua")
local romm = den.include("romm.lua")
local value = romm.value

local provider = { romm = romm }

local INDEX_SECONDS = 120
local index = nil      -- { built, version, platforms, by_stem[system][stem], by_id[id] }
local remote = {}      -- lower-case path -> { kind, id, rom_id, rev, file }
local kept = nil       -- lower-case path -> { rev, modified }, while list() runs

local function rev_of(item)
  return value(item.updated_at) or tostring(item.id)
end

local function file_times()
  local times = den.storage.get("modified")
  return type(times) == "table" and times or {}
end

local function keep_time(path, rev, modified)
  local times = file_times()
  times[path:lower()] = tonumber(modified) and { rev = rev, modified = tonumber(modified) } or nil
  den.storage.set("modified", next(times) and times or den.json.decode("{}"))
end

local function build_index()
  if index and den.now() - index.built < INDEX_SECONDS then
    return index
  end
  local version, why = romm.check_version(romm.server() or "")
  if not version then
    return nil, why
  end
  local platforms
  platforms, why = romm.platforms()
  if not platforms then
    return nil, why
  end
  local fresh = { built = den.now(), version = version, platforms = platforms,
                  by_stem = {}, by_id = {} }
  for _, platform in ipairs(platforms) do
    local roms
    roms, why = romm.all_roms(platform.id)
    if not roms then
      return nil, why
    end
    local stems = fresh.by_stem[platform.system] or {}
    fresh.by_stem[platform.system] = stems
    for _, rom in ipairs(roms) do
      rom.system = platform.system
      rom.stems = {}
      local seen = {}
      local candidates = { rom.stem }
      for _, f in ipairs(rom.files) do
        candidates[#candidates + 1] = f.name:match("^(.+)%.[^.]+$") or f.name
      end
      for _, stem in ipairs(candidates) do
        local key = stem and stem:lower()
        if key and not seen[key] then
          seen[key] = true
          if stems[key] and stems[key].id ~= rom.id then
            den.log("Two " .. platform.system .. " ROMs named " .. stem .. "; syncing the first")
          else
            stems[key] = rom
            rom.stems[#rom.stems + 1] = stem
          end
        end
      end
      fresh.by_id[rom.id] = rom
    end
  end
  index = fresh
  return index
end

function provider.forget()
  index, remote = nil, {}
end

function provider.index()
  return build_index()
end

-- The ROM a portable name belongs to, with the stem and kind of the file.
local function rom_for(path)
  local category, system, file = names.parse(path)
  if not category then
    return nil, den.tr("RomM keeps only saves, states and games; {} is none.", tostring(path))
  end
  if category == "games" then
    return nil, nil, category, system, file
  end
  local stem, kind, state_file = names.stem_of(category, file)
  if not stem then
    return nil, den.tr("{} is not a save state EmuDEN syncs.", file)
  end
  local idx, why = build_index()
  if not idx then
    return nil, why
  end
  local rom = (idx.by_stem[system] or {})[stem:lower()]
  if not rom then
    return nil, den.tr("RomM has no {} game named {}.", system, stem)
  end
  return rom, nil, category, system, file, kind, state_file
end

local function add(out, path, size, modified, rev, entry)
  local key = path:lower()
  if out[key] and out[key].rev >= rev then
    return    -- two remote files under one name: the newer one counts
  end
  entry.rev = rev
  remote[key] = entry
  local own = kept and kept[key]
  out[key] = { path = path, size = size or 0, rev = rev,
               modified = own and own.rev == rev and own.modified or names.unix_time(modified) }
end

local function list_assets(kind, out)
  local items, why = romm.assets(kind)
  if not items then
    return nil, why
  end
  for _, item in ipairs(items) do
    local rom = index.by_id[item.rom_id]
    local file = value(item.file_name)
    if rom and file and value(item.slot) == nil then
      for _, stem in ipairs(rom.stems) do
        if names.belongs(file, stem) and names.stem_of(kind, file) then
          local folder = kind .. "/" .. rom.system .. "/"
          add(out, folder .. file, value(item.file_size_bytes), value(item.updated_at),
              rev_of(item), { kind = kind, id = item.id, rom_id = rom.id, file = file })
          local shot = kind == "states" and value(item.screenshot)
          if shot and names.lower_ext(shot.file_name or "") == "png" then
            add(out, folder .. shot.file_name, value(shot.file_size_bytes),
                value(shot.updated_at), rev_of(shot),
                { kind = "screenshots", id = shot.id, rom_id = rom.id, state_id = item.id })
          end
          break
        end
      end
    end
  end
  return true
end

local function list_games(out)
  for _, rom in pairs(index.by_id) do
    for _, f in ipairs(rom.files) do
      add(out, "games/" .. rom.system .. "/" .. f.name, f.size, f.updated_at or rom.updated_at,
          f.updated_at or rom.updated_at or tostring(rom.id),
          { kind = "games", id = f.id, rom_id = rom.id, file = f.name })
    end
  end
end

function provider.list(prefix)
  local idx, why = build_index()
  if not idx then
    return nil, why
  end
  local wanted = prefix and prefix:match("^([%w]+)/?$")
  if prefix and not names.CATEGORIES[wanted or ""] then
    return {}
  end
  local out = {}
  kept = file_times()
  for _, kind in ipairs{ "saves", "states" } do
    if not wanted or wanted == kind then
      local ok, err = list_assets(kind, out)
      if not ok then
        kept = nil
        return nil, err
      end
    end
  end
  if not wanted or wanted == "games" then
    list_games(out)
  end
  kept = nil
  local result = {}
  for _, item in pairs(out) do
    result[#result + 1] = item
  end
  table.sort(result, function(a, b) return a.path < b.path end)
  return result
end

local function entry_of(path)
  local entry = remote[path:lower()]
  if entry then
    return entry
  end
  local category = path:match("^([%w]+)/")
  local _, why = provider.list(category and category .. "/" or nil)
  if why then
    return nil, why
  end
  return remote[path:lower()]
end

function provider.get(path, local_path, progress)
  local entry, why = entry_of(path)
  if not entry then
    return nil, why or den.tr("RomM has no {}.", path)
  end
  if entry.kind == "games" then
    return romm.download("/api/roms/" .. entry.rom_id .. "/content/" ..
                         names.urlencode(entry.file),
                         entry.id and { { "file_ids", entry.id } } or nil,
                         local_path, progress)
  end
  return romm.download("/api/" .. entry.kind .. "/" .. entry.id .. "/content", nil,
                       local_path, progress)
end

-- The save or state of this ROM named file, as RomM has it now.
local function current(kind, rom_id, file)
  local items, why = romm.assets(kind, { { "rom_id", rom_id } })
  if not items then
    return nil, why
  end
  local best
  for _, item in ipairs(items) do
    if value(item.slot) == nil and (value(item.file_name) or ""):lower() == file:lower() then
      if not best or rev_of(item) > rev_of(best) then
        best = item
      end
    end
  end
  return best or false
end

local function remember(path, entry, rev, modified)
  entry.rev = rev
  remote[path:lower()] = entry
  keep_time(path, rev, modified)
  return rev
end

-- modified is the local file's time (Unix seconds), given back by list().
function provider.put(path, local_path, rev, modified)
  local rom, why, category, _, file, kind, state_file = rom_for(path)
  if category == "games" then
    return nil, "This plugin does not upload games to RomM."
  end
  if not rom then
    return nil, why
  end
  if kind == "picture" then
    local state
    state, why = current("states", rom.id, state_file)
    if state == nil then
      return nil, why
    elseif not state then
      return nil, den.tr("The state {} is not on RomM yet; its picture follows it.", state_file)
    end
    local shot = value(state.screenshot)
    local now = shot and rev_of(shot)
    if now ~= rev then
      return nil, "conflict"
    end
    local saved
    saved, why = romm.upload("states", state.id, nil, "screenshotFile", local_path, file)
    if not saved then
      return nil, why
    end
    shot = value(saved.screenshot)
    if not shot then
      return nil, den.tr("RomM did not keep the picture of {}.", state_file)
    end
    return remember(path, { kind = "screenshots", id = shot.id, rom_id = rom.id,
                            state_id = state.id }, rev_of(shot), modified)
  end
  local existing
  existing, why = current(category, rom.id, file)
  if existing == nil then
    return nil, why
  end
  -- The journal's rev must be what RomM has now; anything else was written meanwhile.
  local now = existing and rev_of(existing) or nil
  if existing and now ~= rev then
    return nil, "conflict"
  end
  local field = category == "saves" and "saveFile" or "stateFile"
  local saved
  saved, why = romm.upload(category, existing and existing.id or nil, rom.id, field,
                           local_path, existing and existing.file_name or file)
  if not saved then
    return nil, why
  end
  return remember(path, { kind = category, id = saved.id, rom_id = rom.id,
                          file = value(saved.file_name) or file }, rev_of(saved), modified)
end

function provider.delete(path)
  local rom, why, category, _, file, kind, state_file = rom_for(path)
  if category == "games" then
    return nil, "This plugin does not delete games on RomM."
  end
  if not rom then
    return nil, why
  end
  remote[path:lower()] = nil
  keep_time(path, nil, nil)
  if kind == "picture" then
    local state
    state, why = current("states", rom.id, state_file)
    if state == nil then
      return nil, why
    end
    local shot = state and value(state.screenshot)
    if not shot then
      return true
    end
    return romm.remove_screenshot(shot.id)
  end
  local existing
  existing, why = current(category, rom.id, file)
  if existing == nil then
    return nil, why
  end
  if not existing then
    return true
  end
  return romm.remove(category, existing.id)
end

function provider.status()
  local server = romm.server()
  local user = den.storage.get("user")
  return { account = user, user = user, server = server,
           version = index and index.version or nil }
end

return provider
