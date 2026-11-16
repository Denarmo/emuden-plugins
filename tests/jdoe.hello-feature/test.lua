-- SPDX-FileCopyrightText: Copyright 2026 J. Doe
-- SPDX-License-Identifier: MIT

-- Offline test of examples/jdoe.hello-feature over tests/den_mock.lua.

local mock = require("den_mock")
local plugin = mock.load(os.getenv("DEN_PLUGIN_DIR") or "examples/jdoe.hello-feature")
local check = mock.check

local TAGS = '[{"name":"v5.4.8","commit":{"sha":"1234567890abcdef"}},' ..
             '{"name":"v5.4.7","commit":{"sha":"abcdef1234567890"}}]'
mock.http_route("^https://api%.github%.com/repos/lua/lua/tags", { status = 200, body = TAGS })

check(type(plugin.open) == "function" and type(plugin.actions.press) == "function", "entry points")
check(mock.open(), "plugin.open runs")
local page = mock.page()
check(page and page.title == "Hello", "the page has its title")
check(page.body[1].type == "text" and page.body[1].style == "heading", "a heading first")
local rows = {}
for _, e in ipairs(page.body) do
  if e.type == "row" then rows[#rows + 1] = e end
end
check(#rows == 2 and rows[1].label == "v5.4.8" and rows[1].value == "1234567", "the tags are listed")
check(#mock.requests == 1 and mock.requests[1].headers.Accept == "application/vnd.github+json", "one request")
check(mock.requests[1].cache_seconds == 3600, "the first load may use the cache")

check(mock.find("press").label == "Pressed 0 times", "nothing pressed yet")
mock.action("press")
mock.action("press")
check(mock.storage.presses == 2, "presses are counted in den.storage")
check(mock.find("press").label == "Pressed 2 times", "the button shows the count")

-- A new start of the script keeps the count (the storage is the app's, not the script's).
plugin = mock.load(os.getenv("DEN_PLUGIN_DIR") or "examples/jdoe.hello-feature", { keep = true })
mock.http_route("tags", { status = 503, body = "" })
mock.open()
check(mock.find("press").label == "Pressed 2 times", "the count stays between visits")
local warned = false
for _, e in ipairs(mock.page().body) do
  warned = warned or (e.style == "warning" and e.text:find("503") ~= nil)
end
check(warned, "a failed request is shown as a warning")

mock.http_route("tags", TAGS)
mock.action("refresh")
check(mock.requests[#mock.requests].cache_seconds == 0, "Refresh skips the cache")
check(mock.find("loading") == nil, "the list replaced the loading bar")

-- The sandbox: only the declared host, no os or io.
local answer, why = mock.den.http.get{ url = "https://example.com/" }
check(answer == nil and why:find("did not declare"), "other hosts are refused")
check(mock.den.http.get{ url = "http://api.github.com/" } == nil, "plain http is refused")
local ok = mock.call("open") -- the script cannot reach os: a call of os.exit would fail here
check(ok, "plugin.open runs again")

mock.finish()
