-- SPDX-FileCopyrightText: Copyright 2026 EmuDEN contributors
-- SPDX-License-Identifier: GPL-3.0-or-later

-- A web browser inside EmuDEN for any site. Every file the user downloads there lands in
-- EmuDEN's Downloads folder and is set up by the app: a game goes into its console's folder
-- of the library, a ROM hack patch is applied to a copy of the user's own game, anything
-- else stays in Downloads with the reason. No code per site: the app looks at the file, not
-- at the page. The script never reads a page or a file; it names files by their name.

local pages = den.include("pages.lua")

local plugin = { actions = {} }

local tab = "browse"
local browsing = false -- the browser page is open
local asked = false    -- a patch waits for the user to pick its game

-- Stored: "pending" (file name -> { title, host }) for patches that wait for a choice.
local function stored(key)
  local value = den.storage.get(key)
  return type(value) == "table" and value or {}
end

local function remember(name, value)
  local all = stored("pending")
  all[name] = value
  den.storage.set("pending", all)
end

local function show_home()
  if tab == "downloads" then
    den.ui.set(pages.downloads_tab(den.downloads.history() or {}, den.downloads.files() or {}))
  elseif tab == "about" then
    den.ui.set(pages.about_tab(den.plugin.version, den.downloads.folder() or ""))
  else
    den.ui.set(pages.browse_tab(den.web.available(), den.web.bookmarks() or {}))
  end
end

-- Shows a page above the tabs, one at a time.
local function show(page)
  if den.ui.depth() > 1 then
    den.ui.set(page)
  else
    den.ui.push(page)
  end
end

local function back_home()
  while den.ui.depth() > 1 do
    den.ui.pop()
  end
  show_home()
end

-- "example.com" -> https://example.com, words -> a search. nil for nothing.
local function address_of(text)
  text = (text or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if text == "" then
    return nil
  end
  if text:lower():match("^https://") then
    return text
  end
  if text:lower():match("^http://") then
    return "https://" .. text:sub(8)
  end
  if not text:find("%s") and text:match("^[%w%-]+%.[%w%-%.]+") then
    return "https://" .. text
  end
  local query = text:gsub("[^%w%-_%.~ ]", function(c) return string.format("%%%02X", c:byte()) end)
  return "https://duckduckgo.com/?q=" .. query:gsub(" ", "+")
end

-- Sets one file of the Downloads folder up and tells the user what became of it.
local function set_up(name, title, host, base)
  local done, why = den.downloads.setup{ file = name, page_title = title, source_host = host, base = base }
  if not done then
    den.ui.toast(name .. ": " .. tostring(why))
    return nil
  end
  if done.outcome == "needs_base" then
    remember(name, { title = title or "", host = host or "" })
    asked = true
    if browsing then
      den.ui.toast(done.message .. " Choose the game on the Browser's Downloads page.")
    end
  else
    if stored("pending")[name] then
      remember(name, nil)
    end
    den.ui.toast(done.message)
  end
  return done
end

-- The browser: every file that arrives is set up while the user browses on.
local function browse(url)
  if browsing then
    return
  end
  browsing = true
  asked = false
  local first = url
  while true do
    local file = den.web.open{ any = true, url = first, title = "Browser" }
    first = nil
    if not file then
      break
    end
    set_up(file.download, file.page_title, file.source_host)
  end
  browsing = false
  if asked then
    tab = "downloads"
  end
  back_home()
end

local function record_of(id)
  for _, record in ipairs(den.downloads.history() or {}) do
    if record.id == id then
      return record
    end
  end
end

function plugin.open()
  show_home()
end

function plugin.resume()
  if not browsing and den.ui.depth() == 1 then
    show_home()
  end
end

function plugin.actions.tab(_, value)
  if value and value ~= "" then
    tab = value:match("^[^,]+")
  end
  show_home()
end

function plugin.actions.home()
  browse(nil)
end

function plugin.actions.go(_, value)
  local url = address_of(value)
  if url then
    browse(url)
  end
end

function plugin.actions.bookmark(url)
  browse(url)
end

function plugin.actions.record(id)
  local record = record_of(id)
  if record then
    show(pages.record_page(record))
  end
end

function plugin.actions.play(id)
  den.app.open_game(id)
end

function plugin.actions.undo(id)
  local record = record_of(id)
  if not record then
    return
  end
  local sure = den.ui.confirm{ title = "Undo", yes = "Undo", message = pages.undo_question(record) }
  if not sure then
    return
  end
  local ok, why = den.downloads.undo(id)
  den.ui.toast(ok and "Done: the files are back in Downloads" or tostring(why))
  back_home()
end

-- The games a patch that names no game may be for.
function plugin.actions.choose(id)
  local record = record_of(id)
  if not record then
    return
  end
  -- Setting it up again lists the games, best first.
  local pending = stored("pending")[record.download] or {}
  local done = den.downloads.setup{ file = record.download, page_title = pending.title,
                                    source_host = pending.host }
  if not done then
    den.ui.toast("That file is not in Downloads any more")
    return back_home()
  end
  if done.outcome ~= "needs_base" then
    den.ui.toast(done.message)
    return back_home()
  end
  show(pages.choose_page(done))
end

function plugin.actions.base(arg)
  local pending = stored("pending")[arg.file] or {}
  den.ui.patch("status", { label = "Patching", fraction = -1 })
  set_up(arg.file, pending.title, pending.host, arg.game)
  back_home()
end

function plugin.actions.again(name)
  local pending = stored("pending")[name] or {}
  set_up(name, pending.title, pending.host)
  show_home()
end

return plugin
