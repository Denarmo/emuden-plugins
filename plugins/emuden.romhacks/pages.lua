-- SPDX-FileCopyrightText: Copyright 2026 EmuDEN contributors
-- SPDX-License-Identifier: GPL-3.0-or-later

-- The pages of ROM Hacks as UI models. No colours, sizes or positions: the app draws them.

local pages = {}

pages.SITE = "https://www.hackdex.app/discover"

local SYSTEM_NAMES = { gb = "Game Boy", gbc = "Game Boy Color", gba = "Game Boy Advance",
                       nds = "Nintendo DS" }

local function megabytes(bytes)
  bytes = bytes or 0
  if bytes < 1048576 then
    return string.format("%d KB", (bytes + 1023) // 1024)
  end
  return string.format("%.1f MB", bytes / 1048576)
end

-- The tabs of the first page, as chips.
local function tabs(current)
  local items = {}
  for _, tab in ipairs{ { "install", "Install" }, { "installed", "Installed" },
                        { "bases", "Base games" }, { "about", "About" } } do
    items[#items + 1] = { id = tab[1], label = tab[2], selected = tab[1] == current }
  end
  return { action = "tab", items = items }
end

local function home(current, body, busy)
  return { title = "ROM Hacks", subtitle = "Patches for games you own", chips = tabs(current),
           body = body, busy = busy or false }
end

-- inbox: the patch files in Downloads; installed: file names already installed.
function pages.install_tab(inbox, installed)
  local body = {
    { type = "text", style = "body", text =
        "1. Find a hack on Hackdex in your own browser and press Download Patch there.\n" ..
        "2. Come back: the patch shows under Found in Downloads, or choose the file.\n" ..
        "3. The hack is made from your own copy of the base game and added to your library." },
    { type = "text", style = "caption", text = "Hackdex: " .. pages.SITE },
    { type = "button", label = "Show the Hackdex address", action = "browse" },
    { type = "button", label = "Choose a patch file", action = "import" },
    { type = "button", label = "Look in Downloads again", action = "refresh" },
  }
  if #inbox > 0 then
    local tiles = {}
    for _, file in ipairs(inbox) do
      tiles[#tiles + 1] = { title = file.name, action = "take", arg = file.token,
                            subtitle = installed[file.name] and "Installed" or megabytes(file.size),
                            badge = installed[file.name] and "Installed" or nil }
    end
    body[#body + 1] = { type = "shelf", title = "Found in Downloads", items = tiles }
  else
    body[#body + 1] = { type = "empty", title = "No patch files in Downloads",
                        text = "Files ending in .bps, .xdelta, .ups or .ips appear here." }
  end
  return home("install", body)
end

function pages.installed_tab(hacks)
  local body = {}
  if #hacks == 0 then
    body[1] = { type = "empty", title = "No hacks yet",
                text = "Hacks you install appear here and in your library." }
    return home("installed", body)
  end
  local tiles = {}
  for _, hack in ipairs(hacks) do
    tiles[#tiles + 1] = { title = hack.name, subtitle = hack.version ~= "" and hack.version or nil,
                          image = "game:" .. hack.id, badge = "Hack", action = "hack",
                          arg = hack.id }
  end
  body[1] = { type = "button", label = "Look for newer patches in Downloads", action = "updates" }
  body[2] = { type = "grid", items = tiles }
  return home("installed", body)
end

-- rows: { base, owned } for every known base game; nil while they are looked up.
function pages.bases_tab(rows)
  if rows == nil then
    return home("bases", { { type = "text", text = "Looking through your library..." } }, true)
  end
  local body = {
    { type = "text", style = "caption", text =
        "The base games Hackdex's hacks are made for. A hack needs your own copy of its base " ..
        "game, with exactly this checksum. This plugin never downloads games." },
  }
  local system = nil
  for _, row in ipairs(rows) do
    if row.base.system ~= system then
      system = row.base.system
      body[#body + 1] = { type = "text", style = "heading", text = SYSTEM_NAMES[system] or system }
    end
    body[#body + 1] = { type = "row", label = row.base.name,
                        value = row.owned and "In your library" or "Missing",
                        action = "base", arg = row.base.id }
  end
  return home("bases", body)
end

function pages.about_tab(version)
  return home("about", {
    { type = "text", style = "heading", text = "What this plugin does" },
    { type = "text", text =
        "It installs ROM hack patches (.bps, .xdelta, .ups, .ips) on games you own. It reads " ..
        "the patch, finds the base game in your library by its checksum, patches a copy and " ..
        "adds the result to your library as a hack. Your own game is only read." },
    { type = "text", style = "heading", text = "What you do by hand, and why" },
    { type = "text", text =
        "Hackdex (hackdex.app) lists the hacks, but its terms of service (1.1.0, section 8) " ..
        "do not allow apps, bots or scripts to read the site or download from it without " ..
        "written permission, and the site blocks clients that are not a browser. So this " ..
        "plugin makes no request to Hackdex at all: it cannot browse, search or download " ..
        "there. You open Hackdex in your browser, choose a hack, press Download Patch on its " ..
        "page (no account is needed; some creators only allow patching on the site itself), " ..
        "and the plugin picks the file up from your Downloads folder." },
    { type = "text", text =
        "Covers and descriptions are not fetched either. On the install page you can type " ..
        "the description, note the hack's Hackdex page and choose a cover picture you saved." },
    { type = "text", style = "heading", text = "Updates" },
    { type = "text", text =
        "The plugin cannot ask Hackdex for new versions. Download the newer patch there, then " ..
        "use Look for newer patches in Downloads, or Update from a file on the hack's page. " ..
        "The hack keeps its place in your library, its saves and its play time." },
    { type = "text", style = "heading", text = "Games" },
    { type = "text", style = "warning", text =
        "This plugin never downloads games and holds no patches. A missing base game is " ..
        "named with its checksum so you can add your own copy." },
    { type = "text", style = "heading", text = "Credits" },
    { type = "text", style = "caption", text =
        "Hacks are the work of their authors; see each hack's page on Hackdex for credits. " ..
        "The list of base games comes from the Hackdex website's source (MIT licence, " ..
        "Copyright (c) 2025 The Hackdex Project; see NOTICE.txt in this plugin). This plugin " ..
        "is not made or endorsed by Hackdex. ROM Hacks " .. version .. ", GPL-3.0-or-later." },
  })
end

function pages.base(base, owned)
  return {
    title = base.name,
    body = {
      { type = "detail", title = base.name,
        subtitle = owned and "You have the base game" or "Base game missing",
        image = owned and owned.cover or nil,
        facts = {
          { label = "Console", value = SYSTEM_NAMES[base.system] or base.system },
          { label = "Region", value = base.region },
          { label = "CRC32", value = base.crc32:upper() },
          { label = "SHA-1", value = base.sha1 },
          { label = "In your library", value = owned and owned.name or "No" },
        }, buttons = {} },
      { type = "text", style = "caption", text = owned and
          "Patches made for this game can be installed." or
          "Add your own copy of this game to your library. Its checksum must match exactly." },
    },
  }
end

function pages.install(pending)
  local facts = {
    { label = "Base game", value = pending.base.name },
    { label = "Patch file", value = pending.name },
    { label = "Format", value = pending.info.format },
  }
  if pending.info.target_size then
    facts[#facts + 1] = { label = "Size", value = megabytes(pending.info.target_size) }
  end
  facts[#facts + 1] = { label = "Cover",
                        value = pending.cover and "Your picture" or "The base game's" }
  return {
    title = "Install a hack",
    body = {
      { type = "detail", id = "summary", title = pending.title,
        subtitle = pending.verified and "You have the base game" or
                   "This patch does not name its base game: you chose it",
        image = pending.cover and ("plugin:" .. pending.cover) or pending.base.cover,
        facts = facts,
        buttons = { { label = "Install", action = "install" },
                    { label = "Choose a cover picture", action = "cover" } } },
      { type = "progress", id = "status", label = "Not started", fraction = 0 },
      { type = "input", id = "title", label = "Name", value = pending.title, action = "set",
        arg = "title" },
      { type = "input", id = "version", label = "Version", value = pending.version,
        action = "set", arg = "version" },
      { type = "input", id = "page", label = "Hackdex page (address or its last part)",
        value = pending.page or "", action = "set", arg = "page" },
      { type = "input", id = "description", label = "Description", value = pending.description,
        action = "set", arg = "description" },
      { type = "text", style = "caption", text =
          "The name, version, description and cover are yours to fill in: this plugin does " ..
          "not read them from Hackdex." },
    },
  }
end

-- known: the base game of bases.json with that checksum, or nil.
function pages.missing_base(info, known, crc)
  local name = known and known.name or "a game this plugin does not know"
  local facts = { { label = "CRC32", value = crc } }
  if known then
    facts[#facts + 1] = { label = "Console", value = SYSTEM_NAMES[known.system] or known.system }
    facts[#facts + 1] = { label = "Region", value = known.region }
    facts[#facts + 1] = { label = "SHA-1", value = known.sha1 }
  end
  if info.source_size then
    facts[#facts + 1] = { label = "Size", value = tostring(info.source_size) .. " bytes" }
  end
  return {
    title = "Base game missing",
    body = {
      { type = "text", style = "warning", text = "Base game missing: " .. name .. " (" .. crc .. ")" },
      { type = "detail", title = name, subtitle = "Not in your library", facts = facts,
        buttons = {} },
      { type = "text", text =
          "Add your own copy of this game to your library, then choose the patch again. The " ..
          "checksum must match exactly: another region or revision will not do. This plugin " ..
          "never downloads games." },
    },
  }
end

function pages.choose_base(games, title)
  local rows = {
    { type = "text", text = "This kind of patch does not say which game it is for. Choose it." },
  }
  for _, game in ipairs(games) do
    if not game.hack_of then
      rows[#rows + 1] = { type = "row", label = game.name, value = SYSTEM_NAMES[game.system] or
                          game.system, image = game.cover, action = "choose", arg = game.id }
    end
  end
  if #rows == 1 then
    rows[2] = { type = "empty", title = "No games yet",
                text = "Add your own Game Boy, Game Boy Advance or DS games to the library." }
  end
  return { title = title or "Which game is this patch for?", body = rows }
end

function pages.done(game, page)
  local body = {
    { type = "detail", title = game.name, subtitle = "Installed. It is in your library.",
      image = "game:" .. game.id,
      buttons = { { label = "Play", action = "play", arg = game.id } } },
  }
  if page then
    body[#body + 1] = { type = "text", style = "caption", text = "Listed on Hackdex: " .. page }
  end
  return { title = "Hack installed", body = body }
end

-- hack: an entry of den.library.hacks(); meta: what this plugin noted; base: its game or nil.
function pages.hack(hack, meta, base, installed)
  local facts = {
    { label = "Version", value = hack.version ~= "" and hack.version or "Not noted" },
    { label = "Base game", value = base and base.name or "No longer in your library" },
    { label = "Installed", value = installed },
  }
  if meta.patch then
    facts[#facts + 1] = { label = "Patch file", value = meta.patch }
  end
  local body = {
    { type = "detail", title = hack.name, subtitle = "Hack", image = "game:" .. hack.id,
      text = meta.description, facts = facts,
      buttons = {
        { label = "Play", action = "play", arg = hack.id },
        { label = "Update from a file", action = "update", arg = hack.id },
        { label = "Remove", action = "remove", arg = hack.id },
      } },
    { type = "text", style = "caption", text = meta.page and
        ("Listed on Hackdex: " .. meta.page .. "\nHacks are the work of their authors; the " ..
         "credits are on that page.") or
        "Its Hackdex page is not noted. Type it below to keep the link with the hack." },
    { type = "input", id = "rename", label = "Rename", value = hack.name, action = "rename",
      arg = hack.id },
    { type = "input", id = "link", label = "Hackdex page (address or its last part)",
      value = meta.page or "", action = "link", arg = hack.id },
  }
  return { title = hack.name, body = body }
end

function pages.update(update)
  return {
    title = "Update " .. update.hack.name,
    body = {
      { type = "detail", title = update.hack.name, subtitle = "A newer patch for this hack",
        image = "game:" .. update.hack.id,
        facts = {
          { label = "Installed version", value = update.hack.version ~= "" and
                                                 update.hack.version or "Not noted" },
          { label = "Patch file", value = update.name },
          { label = "Format", value = update.info.format },
        },
        buttons = {
          { label = "Update", action = "apply_update", arg = false },
          { label = "Update and keep the old version", action = "apply_update", arg = true },
        } },
      { type = "progress", id = "status", label = "Not started", fraction = 0 },
      { type = "input", id = "version", label = "New version", value = update.version,
        action = "set_update_version" },
      { type = "text", style = "caption", text =
          "Update keeps the hack's saves and play time. Keep the old version when the new " ..
          "patch says it breaks saves: the old one stays as its own game." },
    },
  }
end

-- found: { {hack, file} } patch files in Downloads that look like a newer patch of a hack.
function pages.updates(found, hacks, metas)
  local body = {
    { type = "text", style = "caption", text =
        "This plugin cannot ask Hackdex for new versions. Download the newer patch on the " ..
        "hack's page; it is matched here by its file name." },
  }
  for _, item in ipairs(found) do
    body[#body + 1] = { type = "row", label = item.hack.name, value = item.file.name,
                        action = "update_from", arg = { id = item.hack.id, token = item.file.token } }
  end
  if #found == 0 then
    body[#body + 1] = { type = "empty", title = "No newer patch files in Downloads" }
  end
  local linked = false
  for _, hack in ipairs(hacks) do
    local meta = metas[hack.id]
    if meta and meta.page then
      if not linked then
        body[#body + 1] = { type = "text", style = "heading", text = "Where to look" }
        linked = true
      end
      body[#body + 1] = { type = "row", label = hack.name, value = meta.page }
    end
  end
  return { title = "Updates", body = body }
end

return pages
