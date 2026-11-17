-- SPDX-FileCopyrightText: Copyright 2026 EmuDEN contributors
-- SPDX-License-Identifier: GPL-3.0-or-later

-- den.mods of den_mock.lua (permission game.files, capability feature.mods.1): files of a
-- Steam game's folder and Vulkan layers. The world is mock.game_files, mock.archives,
-- mock.mods and mock.layers; see the header of den_mock.lua.

return function(den, h)
  local M, perms, manifest = h.M, h.perms, h.manifest
  local wait, refuse, denied, take_answer, copy, safe_path = h.wait, h.refuse, h.denied, h.take_answer, h.copy, h.safe_path

  local function allowed() return perms["game.files"] end
  local NO = "the plugin has no permission to change game files (game.files)"

  -- The folder of an installed Steam game, never of a shortcut.
  local function folder_of(appid)
    for _, app in ipairs(M.steam.apps or {}) do
      if app.appid == appid and not app.shortcut then return M.game_files[appid] end
    end
  end
  local function content_of(file) return type(file) == "table" and (file.content or "") or file end
  -- Not SHA-256: a stand-in that differs when the content does. A file given as a table keeps
  -- its own `sha256` and `size`.
  local function digest(file)
    if type(file) == "table" and file.sha256 then return file.sha256 end
    local text, sum = content_of(file), 5381
    for i = 1, #text do sum = (sum * 33 + text:byte(i)) % 4294967296 end
    return string.rep(string.format("%08x", sum), 8)
  end
  local function plugin_file(path, roots)
    if not safe_path(path) then return nil end
    for _, root in ipairs(roots) do
      if path:sub(1, #root) == root and M.files[path] ~= nil then return M.files[path] end
    end
  end
  local function user(what)
    if not h.user() then return refuse(what .. " only when the user asks for it") end
    return true
  end
  local function undo(appid)
    local record, files = M.mods[appid], M.game_files[appid]
    if not record then return end
    for _, f in ipairs(record.files) do
      if files and content_of(files[f.to]) == f.written then files[f.to] = f.original end
    end
    M.mods[appid] = nil
  end

  den.mods = {
    find = function(o)
      if not allowed() then return denied(NO) end
      local files = type(o) == "table" and folder_of(o.appid)
      if not files then return refuse("there is no such Steam game") end
      if type(o.names) ~= "table" or #o.names == 0 or #o.names > 16 then return refuse("find takes 1 to 16 file names") end
      local wanted = {}
      for _, name in ipairs(o.names) do
        local _, stars = tostring(name):gsub("%*", "")
        if type(name) ~= "string" or name == "" or name:find("[/\\]") or stars > 1 then
          return refuse("a name is a file name with at most one *")
        end
        local before, after = name:lower():match("^(.-)%*(.*)$")
        wanted[#wanted + 1] = before and { before, after } or { name:lower() }
      end
      wait()
      local paths, out = {}, {}
      for path in pairs(files) do paths[#paths + 1] = path end
      table.sort(paths)
      for _, path in ipairs(paths) do
        local name = path:match("[^/]+$"):lower()
        local _, depth = path:gsub("/", "")
        local hit = false
        for _, w in ipairs(wanted) do
          if w[2] then
            hit = hit or (#name >= #w[1] + #w[2] and name:sub(1, #w[1]) == w[1] and name:sub(#name - #w[2] + 1) == w[2])
          else
            hit = hit or name == w[1]
          end
        end
        if hit and depth <= 8 and #out < 64 then
          local file = files[path]
          out[#out + 1] = { path = path, size = type(file) == "table" and file.size or #content_of(file), sha256 = digest(file) }
        end
      end
      return out
    end,

    unpack = function(o)
      if not allowed() then return denied(NO) end
      if type(o) ~= "table" or not plugin_file(o.file, { "downloads/" }) then return refuse("there is no such archive in downloads") end
      local archive = M.archives[o.file]
      if not archive then return refuse("the file is not a zip or tar.xz archive") end
      if type(o.entries) ~= "table" or #o.entries == 0 or #o.entries > 32 then return refuse("unpack takes 1 to 32 entries") end
      local stem = o.file:match("[^/]+$"):gsub("%.tar%.xz$", ""):gsub("%.zip$", "")
      wait()
      local out = {}
      for _, entry in ipairs(o.entries) do
        if not safe_path(entry) then error("unpack: the entry " .. tostring(entry) .. " leaves the archive", 2) end
        if archive[entry] == nil then return refuse("the archive has no " .. entry) end
        out[entry] = "cache/mods/" .. stem .. "/" .. entry
        M.files[out[entry]] = archive[entry]
      end
      return out
    end,

    apply = function(o)
      if not allowed() then return denied(NO) end
      local ok, why = user("a game's files are changed")
      if not ok then return nil, why end
      local files = type(o) == "table" and folder_of(o.appid)
      if not files then return refuse("there is no such Steam game") end
      if type(o.name) ~= "string" or o.name == "" then return refuse("apply needs the mod's name") end
      if type(o.files) ~= "table" or #o.files == 0 or #o.files > 64 then return refuse("apply takes 1 to 64 files") end
      local asked = {}
      for _, f in ipairs(o.files) do
        if not plugin_file(f.from, { "cache/", "downloads/" }) then return refuse("there is no file " .. tostring(f.from) .. " in cache or downloads") end
        if not safe_path(f.to) then return refuse(tostring(f.to) .. " leaves the game's folder") end
        asked[#asked + 1] = { to = f.to, replaced = files[f.to] ~= nil }
      end
      wait()
      if not take_answer({ kind = "confirm", title = "Add " .. o.name .. " to this game?", appid = o.appid, files = asked }) then
        return refuse("cancelled")
      end
      undo(o.appid)
      local record = { name = o.name, time = M.clock, files = {} }
      for _, f in ipairs(o.files) do
        record.files[#record.files + 1] = { to = f.to, written = M.files[f.from], original = files[f.to] }
        files[f.to] = M.files[f.from]
      end
      M.mods[o.appid] = record
      return true
    end,

    state = function(appid)
      if not allowed() then return denied(NO) end
      local record, files = M.mods[appid], M.game_files[appid] or {}
      if not record then return nil end
      wait()
      local out = { name = record.name, time = record.time, files = {} }
      for _, f in ipairs(record.files) do
        out.files[#out.files + 1] = { to = f.to, intact = content_of(files[f.to]) == f.written }
      end
      return out
    end,

    remove = function(appid)
      if not allowed() then return denied(NO) end
      local ok, why = user("a game's files are changed")
      if not ok then return nil, why end
      if not M.mods[appid] then return true, {} end
      wait()
      if not take_answer({ kind = "confirm", title = "Remove " .. M.mods[appid].name .. " from this game?", appid = appid }) then
        return refuse("cancelled")
      end
      undo(appid)
      return true
    end,

    layer = function(o)
      if not allowed() then return denied(NO) end
      local ok, why = user("a Vulkan layer is installed")
      if not ok then return nil, why end
      if den.device.platform ~= "linux" then return refuse("Vulkan layers are installed on Linux only") end
      if type(o) ~= "table" or type(o.name) ~= "string" or not o.name:match("^[%w%._%-]+$") then return refuse("layer needs a name") end
      if type(o.layers) ~= "table" or #o.layers == 0 then return refuse("layer needs manifests and their libraries") end
      local manifests = {}
      for _, l in ipairs(o.layers) do
        local text = plugin_file(l.manifest, { "cache/" })
        if not text or not plugin_file(l.library, { "cache/" }) then return refuse("a layer's manifest and library are files under cache") end
        local json = M.json.decode(text)
        local layer = type(json) == "table" and json.layer
        if type(layer) ~= "table" or type(layer.library_path) ~= "string" then return refuse("that is not a Vulkan layer manifest") end
        if type(layer.disable_environment) ~= "table" or next(layer.disable_environment) == nil then
          return refuse("a layer without disable_environment could not be switched off per game")
        end
        manifests[#manifests + 1] = "emuden-" .. manifest.id .. "-" .. l.manifest:match("[^/]+$")
      end
      wait()
      if not take_answer({ kind = "confirm", title = "Install the Vulkan layer " .. o.name .. "?", manifests = manifests }) then
        return refuse("cancelled")
      end
      M.layers[o.name] = { time = M.clock, manifests = manifests, intact = true }
      return true
    end,

    layer_state = function(name)
      if not allowed() then return denied(NO) end
      if not M.layers[name] then return nil end
      wait()
      return copy(M.layers[name])
    end,

    remove_layer = function(name)
      if not allowed() then return denied(NO) end
      local ok, why = user("a Vulkan layer is removed")
      if not ok then return nil, why end
      if not M.layers[name] then return refuse("this plugin installed no such layer") end
      wait()
      if not take_answer({ kind = "confirm", title = "Remove the Vulkan layer " .. name .. "?" }) then return refuse("cancelled") end
      M.layers[name] = nil
      return true
    end,
  }
end
