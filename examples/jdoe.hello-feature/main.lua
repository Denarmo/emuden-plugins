-- SPDX-FileCopyrightText: Copyright 2026 J. Doe
-- SPDX-License-Identifier: MIT

-- An example feature plugin: one page with a heading, a text, a button that counts presses in
-- den.storage and a list of the latest tags of the Lua repository on GitHub.

local TAGS_URL = "https://api.github.com/repos/lua/lua/tags?per_page=5"

local plugin = { actions = {} }
local tags = nil    -- { {name, sha} } once loaded
local problem = nil -- why the tags could not be loaded

local function pressed_label()
  local count = den.storage.get("presses") or 0
  return count == 1 and "Pressed once" or string.format("Pressed %d times", count)
end

local function page()
  local body = {
    { type = "text", style = "heading", text = "Hello from a plugin" },
    { type = "text", style = "body", text =
        "This page is a Lua script. The button counts how often it was pressed; the count is " ..
        "kept in the plugin's storage, so it is still there the next time you open the page." },
    { type = "button", id = "press", label = pressed_label(), action = "press" },
    { type = "text", style = "heading", text = "Latest Lua tags on GitHub" },
  }
  if tags then
    for _, tag in ipairs(tags) do
      body[#body + 1] = { type = "row", label = tag.name, value = tag.sha }
    end
    if #tags == 0 then
      body[#body + 1] = { type = "text", style = "caption", text = "GitHub lists no tags." }
    end
  elseif problem then
    body[#body + 1] = { type = "text", style = "warning", text = problem }
  else
    body[#body + 1] = { type = "progress", id = "loading", label = "Loading", fraction = -1 }
  end
  body[#body + 1] = { type = "button", id = "refresh", label = "Refresh", action = "refresh" }
  return { title = "Hello", subtitle = "An example feature plugin", body = body }
end

-- Reads the tags; den.http.get waits for the answer without blocking the app.
local function load_tags(fresh)
  local answer, why = den.http.get{ url = TAGS_URL, headers = { Accept = "application/vnd.github+json" },
                                    cache_seconds = fresh and 0 or 3600 }
  if not answer then
    tags, problem = nil, "GitHub could not be reached: " .. tostring(why)
    return
  end
  if answer.status ~= 200 then
    tags, problem = nil, "GitHub answered " .. answer.status .. "."
    return
  end
  local list = den.json.decode(answer.body)
  if type(list) ~= "table" then
    tags, problem = nil, "GitHub's answer could not be read."
    return
  end
  tags, problem = {}, nil
  for _, item in ipairs(list) do
    if type(item) == "table" and type(item.name) == "string" then
      local sha = type(item.commit) == "table" and type(item.commit.sha) == "string" and item.commit.sha or ""
      tags[#tags + 1] = { name = item.name, sha = sha:sub(1, 7) }
    end
  end
end

function plugin.open()
  den.ui.set(page())
  if not tags then
    load_tags(false)
    den.ui.set(page())
  end
end

function plugin.resume()
  den.ui.set(page())
end

function plugin.actions.press()
  local ok, why = den.storage.set("presses", (den.storage.get("presses") or 0) + 1)
  if not ok then
    return den.ui.toast(why)
  end
  den.ui.patch("press", { label = pressed_label() })
end

function plugin.actions.refresh()
  tags, problem = nil, nil
  den.ui.set(page())
  load_tags(true)
  den.ui.set(page())
end

return plugin
