-- SPDX-FileCopyrightText: Copyright 2026 EmuDEN contributors
-- SPDX-License-Identifier: GPL-3.0-or-later

-- The rest of den_mock.lua's den: den.files, den.library, den.patch,
-- den.device.info, den.game, den.steam, den.achievements, den.web, den.downloads.
-- Simple fakes over the tables of the mock (mock.games, mock.web_files, ...).

return function(den, h)
  local M, perms, systems, manifest, NULL = h.M, h.perms, h.systems, h.manifest, h.null
  local wait, refuse, denied, take_answer, copy = h.wait, h.refuse, h.denied, h.take_answer, h.copy
  local check_declared, safe_path, resolve = h.check_declared, h.safe_path, h.resolve
  den.files = {
    import = function(o)
      if not perms["files.import"] then return denied("the plugin has no permission to read files you choose") end
      wait()
      local a = take_answer({ kind = "import", title = o and o.title, extensions = o and o.extensions })
      if type(a) ~= "table" then return nil end
      M.files["inbox/" .. a.name] = a.content or ""
      return "inbox/" .. a.name
    end,
    inbox = function()
      if not perms["downloads.watch"] then return denied("the plugin has no permission to see your Downloads folder") end
      local out = {}
      for i, f in ipairs(M.downloads) do out[#out + 1] = { name = f.name, size = #(f.content or ""), modified = f.modified or 0, token = "d" .. i } end
      return out
    end,
    take = function(token)
      if not perms["downloads.watch"] then return denied("the plugin has no permission to see your Downloads folder") end
      local f = M.downloads[tonumber(tostring(token):match("^d(%d+)$") or 0)]
      if not f then return refuse("that file is no longer listed; call den.files.inbox again") end
      M.files["inbox/" .. f.name] = f.content or ""
      return "inbox/" .. f.name
    end,
    list = function(d)
      d = (d or ""):gsub("/$", "")
      if d ~= "" and not safe_path(d) then return refuse("the path leaves the plugin's folder") end
      local prefix, seen, out = d == "" and "" or d .. "/", {}, {}
      for path, content in pairs(M.files) do
        if path:sub(1, #prefix) == prefix then
          local name, rest = path:sub(#prefix + 1):match("^([^/]+)(.*)$")
          if name and not seen[name] then
            seen[name] = true
            out[#out + 1] = { name = name, dir = rest ~= "", size = rest ~= "" and 0 or #content }
          end
        end
      end
      table.sort(out, function(a, b) return a.name < b.name end)
      return out
    end,
    exists = function(p) local get = resolve(p, true) return get ~= nil and get() ~= nil end,
    read = function(p)
      local get, why, lent = resolve(p, true)
      if not get then return refuse(why) end
      local text = get()
      if not text or #text > (lent and 8 or 4) * 1048576 then return refuse("there is no such file of at most " .. (lent and 8 or 4) .. " MiB") end
      return text
    end,
    size = function(p)
      local get, why = resolve(p, true)
      if not get then return refuse(why) end
      local text = get()
      if not text then return refuse("there is no such file") end
      return #text
    end,
    remove = function(p)
      local ok = safe_path(p) and (p:match("^downloads/") or p:match("^inbox/") or p:match("^cache/")) and M.files[p]
      if not ok then return refuse("only files in downloads, inbox and cache can be removed") end
      M.files[p] = nil
      return true
    end,
  }

  local function sees(system) return systems["*"] or systems[system] end
  den.library = {
    find = function(o)
      if not perms["library.read"] then return denied("the plugin has no permission to see your games") end
      if not (o.crc32 or o.sha1 or o.md5) then return refuse("find needs a crc32, sha1 or md5") end
      wait()
      for _, g in ipairs(M.games) do
        if sees(g.system) and (not o.system or o.system == g.system) and (o.crc32 and g.crc32 == o.crc32 or
            o.sha1 and g.sha1 == o.sha1 or o.md5 and g.md5 == o.md5) then
          return { id = g.id, name = g.name, system = g.system, size = g.size or 0, cover = "game:" .. g.id }
        end
      end
      return nil
    end,
    games = function(o)
      if not perms["library.read"] then return denied("the plugin has no permission to see your games") end
      local out = {}
      for _, g in ipairs(M.games) do
        if sees(g.system) and (not (o and o.system) or o.system == g.system) then
          out[#out + 1] = { id = g.id, name = g.name, system = g.system, size = g.size or 0, cover = "game:" .. g.id, hack_of = g.hack_of }
        end
      end
      return out
    end,
    hacks = function() return copy(M.hacks) end,
    update = function(id, fields)
      if not perms["library.write"] then return denied("the plugin has no permission to change its hacks") end
      for _, h in ipairs(M.hacks) do if h.id == id then h.name = fields.title or h.name return true end end
      return refuse("that is not a hack of this plugin")
    end,
    remove = function(id)
      if not perms["library.write"] then return denied("the plugin has no permission to change its hacks") end
      for i, h in ipairs(M.hacks) do if h.id == id then table.remove(M.hacks, i) return true end end
      return refuse("that is not a hack of this plugin")
    end,
  }
  den.patch = {
    inspect = function(p)
      if not perms.patch then return denied("the plugin has no permission to patch games") end
      if not M.files[p] then return refuse("there is no such patch") end
      wait()
      return copy(M.patch_facts[p] or { format = p:match("%.(%w+)$") or "?" })
    end,
    apply = function(o)
      if not perms.patch then return denied("the plugin has no permission to patch games") end
      if not o.title or o.title == "" then return refuse("the hack needs a title") end
      wait()
      for _, g in ipairs(M.games) do
        if g.id == o.game and sees(g.system) then
          local id = "hack-" .. (#M.hacks + 1)
          M.hacks[#M.hacks + 1] = { id = id, name = o.title, base = g.id, version = o.version or "", source = o.source or "", installed = M.clock }
          return { game = { id = id, name = o.title, system = g.system, size = g.size or 0, cover = "game:" .. id, hack_of = g.id }, path = o.title }
        end
      end
      return refuse("there is no such game of the plugin's consoles")
    end,
  }

  den.device.info = function()
    if not perms["device.info"] then return denied("the plugin has no permission to see the device") end
    wait()
    return copy(M.device_info)
  end
  den.game = {
    settings = function(id)
      if not perms["game.settings"] then return denied("the plugin has no permission to see game settings") end
      wait()
      local g = M.game_settings[id]
      if not g or not sees(g.system) then return refuse("there is no such game") end
      return copy(g)
    end,
    set = function(id, values)
      if not perms["game.settings"] then return denied("the plugin has no permission to change game settings") end
      if not h.user() then return refuse("settings are changed only when the user asks for it") end
      local g = M.game_settings[id]
      if not g or not sees(g.system) then return refuse("there is no such game") end
      wait()
      if not take_answer({ kind = "confirm", title = "Change the settings of " .. tostring(g.name) .. "?" }) then return refuse("cancelled") end
      local before = {}
      for key, value in pairs(values) do
        local found
        for _, opt in ipairs(g.options or {}) do if opt.key == key then found = opt end end
        before[key] = found and found.own and found.value or NULL
        if found then found.value, found.own = value ~= NULL and value or found.value, value ~= NULL end
      end
      return before
    end,
  }
  local function steam_ok() if not perms.steam then return false end return true end
  den.steam = {
    status = function() if not steam_ok() then return denied("the plugin has no permission to see Steam") end wait() return copy(M.steam) end,
    config = function(appid)
      if not steam_ok() then return denied("the plugin has no permission to see Steam") end
      wait()
      return copy(M.steam.config[appid]) or refuse("there is no such app")
    end,
    set = function(o)
      if not steam_ok() then return denied("the plugin has no permission to change Steam games") end
      if not h.user() then return refuse("Steam games are changed only when the user asks for it") end
      wait()
      if not take_answer({ kind = "confirm", title = "Change " .. tostring(o.name or o.appid) .. " in Steam?" }) then return refuse("cancelled") end
      M.steam.config[o.appid] = M.steam.config[o.appid] or {}
      M.steam.config[o.appid].launch_options = o.launch_options or M.steam.config[o.appid].launch_options
      M.steam.config[o.appid].compat_tool = o.compat_tool or M.steam.config[o.appid].compat_tool
      return true
    end,
  }
  local function ach(user_only, msg)
    if not perms.achievements then return denied("the plugin has no permission for achievements") end
    if user_only and not h.user() then return refuse(msg) end
    return true
  end
  den.achievements = {
    status = function() local ok, w = ach() if not ok then return nil, w end wait() local s = copy(M.achievements) s.games = nil return s end,
    sign_in = function(o)
      local ok, w = ach(true, "sign-in starts only when the user asks for it") if not ok then return nil, w end
      wait()
      M.achievements.signed_in, M.achievements.user = true, { name = o.user, display_name = o.user, score = 0 }
      M.secrets.login = { user = o.user, token = "token" }
      return true
    end,
    sign_out = function()
      local ok, w = ach(true, "sign-out happens only when the user asks for it") if not ok then return nil, w end
      M.achievements.signed_in, M.achievements.user, M.secrets.login = false, nil, nil
      return true
    end,
    set = function(o)
      local ok, w = ach(true, "settings change only when the user asks for it") if not ok then return nil, w end
      for _, k in ipairs({ "hardcore", "sound", "screenshot" }) do if type(o[k]) == "boolean" then M.achievements[k] = o[k] end end
      return true
    end,
    game = function(id) local ok, w = ach() if not ok then return nil, w end wait() return copy(M.achievements.games[id]) or refuse("there is no such game") end,
  }

  den.web = {
    available = function() return M.web_in_app, M.web_in_app and "in-app" or "browser" end,
    open = function(o)
      local any = o.any and perms["browse.any"]
      if o.any and not any then return denied("the plugin has no permission to show any website") end
      if not any then
        if not perms.browse then return denied("the plugin has no permission to show websites") end
        local ok, why = check_declared(o.url, o.hosts or manifest.feature.browse_hosts)
        if not ok then return refuse(why) end
      end
      wait()
      local f = table.remove(M.web_files, 1)
      if not f then return refuse("closed") end
      local path = any and f.name or "inbox/" .. f.name
      if not any then M.files[path] = f.content or "" end
      return { path = path, name = f.name, source_host = f.source_host or "", page_title = f.page_title or "", download = any and f.name or nil }
    end,
    close = function() M.web_closed = true end,
    bookmarks = function()
      if not perms["browse.any"] then return denied("the plugin has no permission to show any website") end
      return copy(M.bookmarks)
    end,
  }
  if perms["downloads.setup"] then
    den.downloads = {
      folder = function() return "/downloads" end,
      files = function()
        local out = {}
        for _, f in ipairs(M.downloads) do out[#out + 1] = { name = f.name, size = #(f.content or ""), modified = f.modified or 0 } end
        return out
      end,
      setup = function(o)
        wait()
        local s = { id = "setup-" .. (#M.setups + 1), outcome = "added", message = tostring(o.file) .. " has been added to the library",
                    download = o.file, time = M.clock, games = {}, choices = {} }
        table.insert(M.setups, 1, s)
        return copy(s)
      end,
      history = function() return copy(M.setups) end,
      undo = function(id) wait() for _, s in ipairs(M.setups) do if s.id == id then s.undone = true return true end end return refuse("no such setup") end,
    }
  end
end
