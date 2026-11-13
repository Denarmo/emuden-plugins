-- SPDX-FileCopyrightText: Copyright 2026 EmuDEN contributors
-- SPDX-License-Identifier: GPL-3.0-or-later

-- The pages of a "ROM Hacks: <site>" plugin as UI models. No colours, sizes or positions:
-- the app draws them. Shared by every such plugin; `site` is the plugin's site.lua.

local SYSTEM_NAMES = {
  gb = "Game Boy", gbc = "Game Boy Color", gba = "Game Boy Advance", nds = "Nintendo DS",
  nes = "NES", snes = "Super Nintendo", n64 = "Nintendo 64", genesis = "Mega Drive / Genesis",
  sms = "Master System", gg = "Game Gear", psx = "PlayStation", ps2 = "PlayStation 2",
  psp = "PSP", saturn = "Saturn", dreamcast = "Dreamcast", gamecube = "GameCube", wii = "Wii",
}

local function megabytes(bytes)
  bytes = bytes or 0
  if bytes < 1048576 then
    return string.format("%d KB", (bytes + 1023) // 1024)
  end
  return string.format("%.1f MB", bytes / 1048576)
end

local function system_name(id)
  return SYSTEM_NAMES[id] or id
end

return function(site)
  local pages = {}

  -- The tabs of the first page, as chips.
  local function home(current, body)
    local items = {}
    for _, tab in ipairs{ { "browse", "Browse" }, { "installed", "Installed" },
                          { "about", "About" } } do
      items[#items + 1] = { id = tab[1], label = tab[2], selected = tab[1] == current }
    end
    return { title = site.title, subtitle = "Patches for games you own",
             chips = { action = "tab", items = items }, body = body }
  end

  -- in_app: the site shows inside EmuDEN; otherwise it opens in the user's browser.
  function pages.browse_tab(in_app)
    local where = in_app and "inside EmuDEN" or "in your browser"
    local body = {
      { type = "text", style = "body", text =
          "1. Browse " .. site.name .. " " .. where .. " and press the download button of a " ..
          "hack's patch there, as you would in any browser.\n" ..
          "2. EmuDEN takes the patch file, finds the base game in your library and asks for " ..
          "the hack's name.\n" ..
          "3. The hack is made from your own copy of the base game and added to your library." },
      { type = "button", id = "browse", label = "Browse " .. site.name, action = "browse" },
      { type = "button", id = "import", label = "Choose a patch file", action = "import" },
      { type = "text", style = "caption", text = "Patch files only: " .. site.formats ..
          ". A full game file is always refused." },
    }
    if site.warning then
      body[#body + 1] = { type = "text", style = "warning", text = site.warning }
    end
    if not in_app then
      body[#body + 1] = { type = "text", style = "caption", text =
          "This device shows no web pages inside EmuDEN. The site opens in your browser; a " ..
          "patch you download there is offered here from your Downloads folder." }
    end
    return home("browse", body)
  end

  function pages.installed_tab(hacks)
    if #hacks == 0 then
      return home("installed", { { type = "empty", title = "No hacks yet",
               text = "Hacks you install with this plugin appear here and in your library." } })
    end
    local tiles = {}
    for _, hack in ipairs(hacks) do
      tiles[#tiles + 1] = { id = "hack-" .. hack.id, title = hack.name,
                            subtitle = hack.version ~= "" and hack.version or nil,
                            image = "game:" .. hack.id, badge = "Hack", action = "hack",
                            arg = hack.id }
    end
    return home("installed", { { type = "grid", items = tiles } })
  end

  function pages.about_tab(version)
    local body = {
      { type = "text", style = "heading", text = "What this plugin does" },
      { type = "text", text =
          "It shows " .. site.name .. " in EmuDEN's browser page, where you browse the real " ..
          "site yourself. When you press a download button there, EmuDEN receives the file " ..
          "the way a browser's download manager would. If it is a patch (" .. site.formats ..
          "), the plugin reads it, finds the base game in your library (by the checksum in " ..
          "the patch, or you choose the game when the patch has none), patches a copy and " ..
          "adds the result to your library's Hacks folder. Your own game is only read." },
      { type = "text", style = "heading", text = "What it does not do" },
      { type = "text", text =
          "It does not read, search, scrape or fetch the site: it never sees the pages, " ..
          "their addresses, your cookies or your sign-in, and it requests nothing by itself. " ..
          "It downloads nothing you did not press. It takes patch files only: a game image " ..
          "is refused, also inside an archive and also when it is already patched. It never " ..
          "downloads games and holds no patches." },
      { type = "text", style = "heading", text = "Leaving the site" },
      { type = "text", text =
          "The browser page stays on " .. site.name .. ". When a link goes somewhere else, " ..
          "for instance to a file host, EmuDEN asks before opening it, each time for a new " ..
          "host; your answer lasts until you close the page. If the site asks you to sign " ..
          "in, you do that yourself in the page." },
    }
    for _, note in ipairs(site.about or {}) do
      body[#body + 1] = { type = "text", style = "heading", text = note[1] }
      body[#body + 1] = { type = "text", style = note[3], text = note[2] }
    end
    body[#body + 1] = { type = "text", style = "heading", text = "Credits" }
    body[#body + 1] = { type = "text", style = "caption", text =
        "Hacks are the work of their authors; see each hack's page for its credits. " ..
        (site.credits and (site.credits .. " ") or "") ..
        "Not affiliated with " .. site.name .. ". " .. site.title .. " " .. version ..
        ", GPL-3.0-or-later." }
    return home("about", body)
  end

  function pages.install(pending)
    local facts = {
      { label = "Base game", value = pending.base.name },
      { label = "Console", value = system_name(pending.base.system) },
      { label = "Patch file", value = pending.name },
      { label = "Format", value = pending.info.format },
    }
    if pending.info.source_crc32 then
      facts[#facts + 1] = { label = "Base CRC32",
                            value = string.format("%08X", pending.info.source_crc32) }
    end
    if pending.info.target_size then
      facts[#facts + 1] = { label = "Size", value = megabytes(pending.info.target_size) }
    end
    local buttons = { { id = "install", label = "Install", action = "install" } }
    local subtitle = "You have the base game"
    if not pending.verified then
      subtitle = pending.remembered and "This patch names no base game: you chose this one last time"
                 or "This patch names no base game: you chose it"
      buttons[2] = { id = "choose-again", label = "Choose another game", action = "choose_again" }
    end
    return {
      title = "Install a hack",
      body = {
        { type = "detail", id = "summary", title = pending.title, subtitle = subtitle,
          image = pending.base.cover, facts = facts, buttons = buttons },
        { type = "progress", id = "status", label = "Not started", fraction = 0 },
        { type = "input", id = "title", label = "Name", value = pending.title, action = "set",
          arg = "title" },
        { type = "input", id = "version", label = "Version", value = pending.version,
          action = "set", arg = "version" },
      },
    }
  end

  -- known: the base game of the package's bases.json with that checksum, or nil.
  function pages.missing_base(info, known, crc, file)
    local name = known and known.name or "a game with this checksum"
    local facts = { { label = "CRC32", value = crc }, { label = "Patch file", value = file } }
    if known then
      facts[#facts + 1] = { label = "Console", value = system_name(known.system) }
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
            "Add your own copy of this game to your library, then download the patch again. " ..
            "The checksum must match exactly: another region or revision will not do. This " ..
            "plugin never downloads games." },
      },
    }
  end

  -- list: { game, score, remembered } from the likeliest down.
  function pages.choose_base(list, pending)
    local rows = {
      { type = "text", text = "This " .. pending.info.format:upper() .. " patch does not say " ..
          "which game it is for. Choose the game " .. pending.name .. " was made for; the " ..
          "choice is remembered for this file name." },
    }
    for _, item in ipairs(list) do
      rows[#rows + 1] = { type = "row", id = "game-" .. item.game.id, label = item.game.name,
                          value = item.remembered and "Chosen last time" or system_name(item.game.system),
                          image = item.game.cover, action = "choose", arg = item.game.id }
    end
    if #list == 0 then
      rows[2] = { type = "empty", title = "No game of yours fits this patch",
                  text = "Add your own copy of the base game to the library first." }
    end
    return { title = "Which game is this patch for?", body = rows }
  end

  function pages.done(game)
    return { title = "Hack installed", body = {
      { type = "detail", title = game.name, subtitle = "Installed. It is in your library.",
        image = "game:" .. game.id,
        buttons = { { id = "play", label = "Play", action = "play", arg = game.id } } },
    } }
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
    return { title = hack.name, body = {
      { type = "detail", title = hack.name, subtitle = "Hack", image = "game:" .. hack.id,
        facts = facts,
        buttons = {
          { id = "play", label = "Play", action = "play", arg = hack.id },
          { id = "update-site", label = "Update from " .. site.name, action = "update_site",
            arg = hack.id },
          { id = "update-file", label = "Update from a file", action = "update_file", arg = hack.id },
          { id = "remove", label = "Remove", action = "remove", arg = hack.id },
        } },
      { type = "input", id = "rename", label = "Rename", value = hack.name, action = "rename",
        arg = hack.id },
      { type = "text", style = "caption", text =
          "To update, download the hack's newer patch: it replaces the file and the hack keeps " ..
          "its place in your library, its saves and its play time." },
    } }
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
            { id = "update", label = "Update", action = "apply_update", arg = false },
            { id = "update-keep", label = "Update and keep the old version",
              action = "apply_update", arg = true },
          } },
        { type = "progress", id = "status", label = "Not started", fraction = 0 },
        { type = "input", id = "version", label = "New version", value = update.version,
          action = "set_update_version" },
        { type = "text", style = "caption", text =
            "Update keeps the hack's saves and play time. Keep the old version when the new " ..
            "patch breaks saves: the old one stays as its own game." },
      },
    }
  end

  return pages
end
