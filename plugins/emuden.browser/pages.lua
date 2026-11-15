-- SPDX-FileCopyrightText: Copyright 2026 EmuDEN contributors
-- SPDX-License-Identifier: GPL-3.0-or-later

-- The Browser plugin's pages as UI models: the app draws them.

local pages = {}

local STATUS = {
  added = "Added", hack_added = "Hack added", needs_base = "Choose the game",
  missing_base = "Game missing", waiting = "Waiting", bios = "BIOS, not used",
  unknown = "Left in Downloads", failed = "Failed",
}

local function date_text(seconds)
  local z = seconds // 86400 + 719468
  local era = z // 146097
  local doe = z - era * 146097
  local yoe = (doe - doe // 1460 + doe // 36524 - doe // 146096) // 365
  local doy = doe - (365 * yoe + yoe // 4 - yoe // 100)
  local mp = (5 * doy + 2) // 153
  local day = doy - (153 * mp + 2) // 5 + 1
  local month = mp < 10 and mp + 3 or mp - 9
  local year = yoe + era * 400 + (month <= 2 and 1 or 0)
  return string.format("%04d-%02d-%02d", year, month, day)
end

local function size_text(bytes)
  if bytes < 1048576 then
    return string.format("%d KB", (bytes + 1023) // 1024)
  end
  return string.format("%.1f MB", bytes / 1048576)
end

local function home(current, body)
  local items = {}
  for _, tab in ipairs{ { "browse", "Browse" }, { "downloads", "Downloads" }, { "about", "About" } } do
    items[#items + 1] = { id = tab[1], label = tab[2], selected = tab[1] == current }
  end
  return { title = "Browser", subtitle = "Any website; downloads are set up for you",
           chips = { action = "tab", items = items }, body = body }
end

function pages.browse_tab(in_app, bookmarks)
  local body = {
    { type = "input", id = "address", label = "Address or search", action = "go" },
    { type = "button", id = "home", label = "Open the browser", action = "home" },
    { type = "text", style = "body", text =
        "Browse any site and download a game or a ROM hack patch the way you would in any " ..
        "browser. EmuDEN looks at every file you download: games go into your library with " ..
        "their box art, patches are applied to a copy of your own game. You see a message " ..
        "for each, and the Downloads tab lists them, with undo." },
  }
  if #bookmarks > 0 then
    body[#body + 1] = { type = "text", style = "heading", text = "Bookmarks" }
    for i, bookmark in ipairs(bookmarks) do
      body[#body + 1] = { type = "row", id = "bookmark-" .. i, label = bookmark.title ~= "" and bookmark.title or bookmark.url,
                          value = bookmark.url:gsub("^https?://", ""):gsub("/$", ""), action = "bookmark", arg = bookmark.url }
    end
  else
    body[#body + 1] = { type = "text", style = "caption", text =
        "Bookmarks: in the browser, press Start (Menu) and choose \"Bookmark this page\"." }
  end
  body[#body + 1] = { type = "text", style = "caption", text =
      "In the browser: the left stick moves the pointer, A clicks, the right stick scrolls, " ..
      "X types into the page, Y is the address bar, LB and RB go back and forward, Start " ..
      "opens the menu, B goes back. Touch works too." }
  if not in_app then
    body[#body + 1] = { type = "text", style = "warning", text =
        "This device shows no web pages inside EmuDEN: sites open in your own browser, and " ..
        "files that then appear in your Downloads folder are offered here." }
  end
  return home("browse", body)
end

function pages.downloads_tab(history, files)
  local body = {}
  if #history == 0 then
    body[#body + 1] = { type = "empty", title = "Nothing downloaded yet",
                        text = "What you download in the browser is listed here." }
  end
  for _, record in ipairs(history) do
    local status = record.undone and "Undone" or (STATUS[record.outcome] or record.outcome)
    body[#body + 1] = { type = "row", id = "record-" .. record.id, label = record.message,
                        value = status .. ", " .. date_text(record.time), action = "record", arg = record.id }
  end
  -- Files of the Downloads folder that no setup took (left there, or put there by hand).
  local listed = {}
  for _, record in ipairs(history) do
    listed[record.download] = true
  end
  local loose = {}
  for _, file in ipairs(files) do
    if not listed[file.name] then
      loose[#loose + 1] = file
    end
  end
  if #loose > 0 then
    body[#body + 1] = { type = "text", style = "heading", text = "Also in Downloads" }
    for i, file in ipairs(loose) do
      body[#body + 1] = { type = "row", id = "file-" .. i, label = file.name, value = size_text(file.size) .. ", set up",
                          action = "again", arg = file.name }
    end
  end
  return home("downloads", body)
end

function pages.record_page(record)
  local body = {
    { type = "text", style = "body", text = record.message },
    { type = "text", style = "caption", text = "File: " .. record.download .. ", " .. date_text(record.time) },
  }
  for i, game in ipairs(record.games or {}) do
    body[#body + 1] = { type = "row", id = "game-" .. i, label = game.name, value = "Play", image = game.cover,
                        action = "play", arg = game.id }
  end
  if record.undone then
    body[#body + 1] = { type = "text", style = "caption", text = "This was undone." }
  elseif record.outcome == "added" or record.outcome == "hack_added" then
    body[#body + 1] = { type = "button", id = "undo", label = "Undo", action = "undo", arg = record.id }
  elseif record.outcome == "needs_base" then
    body[#body + 1] = { type = "button", id = "choose", label = "Choose the game", action = "choose", arg = record.id }
  elseif record.outcome ~= "bios" then
    body[#body + 1] = { type = "button", id = "again", label = "Try again", action = "again", arg = record.download }
  end
  return { title = STATUS[record.outcome] or "Download", body = body }
end

function pages.undo_question(record)
  if record.outcome == "hack_added" then
    return "Remove " .. ((record.games[1] or {}).name or "the hack") .. " from your library? Its saves stay; " ..
        "the patch stays in Downloads." .. (record.replaced and " The earlier version it replaced is not brought back." or "")
  end
  return "Take " .. ((record.games[1] or {}).name or record.download) .. " out of your library and put its files " ..
      "back in Downloads? Its saves stay."
end

function pages.choose_page(done)
  local body = {
    { type = "text", style = "body", text = done.message ..
        " The patch does not say which game it was made for. Choose your copy of it; the " ..
        "original stays as it is." },
    { type = "progress", id = "status", label = "", fraction = 0 },
  }
  for i, game in ipairs(done.choices or {}) do
    if i > 60 then
      break
    end
    body[#body + 1] = { type = "row", id = "choice-" .. i, label = game.name, image = game.cover,
                        action = "base", arg = { file = done.download, game = game.id } }
  end
  return { title = "Choose the game", body = body }
end

function pages.about_tab(version, folder)
  return home("about", {
    { type = "text", style = "body", text =
        "Browser " .. version .. ". One browser for every site: EmuDEN looks at the files you " ..
        "download, not at the pages, so it needs nothing made for a particular site." },
    { type = "text", style = "body", text =
        "Games: the console comes from the file's extension, its first bytes or the folders it " ..
        "came in. Zip and 7z archives are unpacked; a cue sheet stays with its tracks and the " ..
        "discs of one game stay together. Patches (IPS, BPS, UPS, xdelta, APS, PPF) are applied " ..
        "to a copy of your game: the one the patch names by its checksum, else the one whose " ..
        "name fits the hack's, else the one you pick. A newer version of the same hack replaces " ..
        "the old one and keeps its saves." },
    { type = "text", style = "body", text =
        "Left in Downloads: files EmuDEN does not know, rar archives, and BIOS files (EmuDEN " ..
        "doesn't use BIOS files)." },
    { type = "text", style = "caption", text = "Downloads folder: " .. folder },
    { type = "text", style = "caption", text =
        "Download only games and patches you have the right to. Sign-ins, passwords and " ..
        "cookies stay in the device's web engine; the plugin never sees a page." },
  })
end

return pages
