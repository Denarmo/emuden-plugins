-- SPDX-FileCopyrightText: Copyright 2026 J. Doe
-- SPDX-License-Identifier: MIT

-- Offline test of examples/jdoe.sync.webdav: the setup page and the provider against a small
-- fake WebDAV server (one flat folder, GET, PUT and DELETE), over tests/den_mock.lua.

local mock = require("den_mock")
local DIR = os.getenv("DEN_PLUGIN_DIR") or "examples/jdoe.sync.webdav"
local plugin = mock.load(DIR)
local check = mock.check

-- Fake server: the folder /dav/EmuDEN/ exists; nothing can be made below it ----------------------

local FOLDER = "^http://nas%.local:8080/dav/EmuDEN/"
local server = { files = {}, next_tag = 0, auth = "Basic amRvZTpwYXNzd29yZA==" }

local function decode(text) return (text:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end)) end

local function handle(req)
  if req.headers.Authorization ~= server.auth then return { status = 401, body = "" } end
  local rest = req.url:match(FOLDER .. "(.*)$")
  if not rest or rest == "" then return { status = 405 } end
  if rest:find("/") then return { status = 409 } end -- a folder below this one does not exist
  local name = decode(rest)
  if req.method == "PUT" then
    server.next_tag = server.next_tag + 1
    server.files[name] = { content = req.upload or req.body or "", etag = "e" .. server.next_tag }
    return { status = 201, headers = { ETag = '"e' .. server.next_tag .. '"' } }
  elseif req.method == "GET" then
    local file = server.files[name]
    if not file then return { status = 404, body = "" } end
    return { status = 200, body = file.content }
  elseif req.method == "DELETE" then
    if not server.files[name] then return { status = 404 } end
    server.files[name] = nil
    return { status = 204 }
  end
  return { status = 405 }
end
mock.http_route("^http://nas%.local:8080/", handle)
local function index() return mock.json.decode(server.files["emuden-index.json"].content) end

-- Setup page ---------------------------------------------------------------------------------------

check(mock.open(), "plugin.open runs")
check(mock.find("server") and mock.find("server").type == "input", "the page asks for the server")
check(mock.find("check") == nil, "nothing to check before a server is entered")

mock.answer(false)
mock.action("set_server", nil, "http://nas.local:8080/dav/EmuDEN")
check(mock.user_server == nil and mock.storage.base == nil, "a declined server is not kept")
check(mock.find("message").text:find("not confirmed"), "the page says it was declined")

mock.answer(true)
mock.action("set_server", nil, "  http://nas.local:8080/dav/EmuDEN  ")
check(mock.asks[#mock.asks].value == "http://nas.local:8080", "the user confirms the server's origin")
check(mock.user_server == "http://nas.local:8080", "the confirmed server may be reached")
check(mock.storage.base == "http://nas.local:8080/dav/EmuDEN/", "the folder's address is kept")
mock.action("set_user", nil, "jdoe")
mock.action("set_password", nil, "password")
check(mock.secrets.password == "password" and mock.storage.password == nil, "the password is a secret")
check(mock.find("password").value == "********", "the page does not show the password")

mock.action("check")
check(server.files["emuden-index.json"], "Check writes an empty index")
check(mock.find("message").text:find("Connected"), "Check reports the connection")
mock.action("check")
check(mock.find("message").text == "Connected.", "a second check finds the index")
check(index().version == 1 and next(index().files) == nil, "the index is empty")

-- Provider ------------------------------------------------------------------------------------------

local SAVE = "saves/gba/My Game (USA).srm"
local NAME = "saves%2Fgba%2FMy%20Game%20%28USA%29.srm"
local ok, rev = mock.provider("put", SAVE, mock.lend("SAVE-1"), nil, 1794000000)
check(ok and rev == "e2", "put uploads a new file and returns its ETag")
check(server.files[NAME] and server.files[NAME].content == "SAVE-1", "the file lies flat under its encoded path")
check(mock.requests[#mock.requests - 1].url:find("saves%%252Fgba%%252F", 1) ~= nil, "the name is encoded once more in the URL")
local entry = index().files[SAVE]
check(entry and entry.size == 6 and entry.modified == 1794000000 and entry.rev == "e2", "the index lists the file")

check(mock.provider("put", "states/gba/My Game (USA).slot1.state", mock.lend("STATE"), nil, 1794000100), "a state goes up")
check(mock.provider("put", "config/settings.json", mock.lend("{}"), nil, 1794000200), "a settings file goes up")

local files
ok, files = mock.provider("list", "saves/")
check(ok and #files == 1, "list of saves/ has the save")
check(files[1].path == SAVE and files[1].size == 6 and files[1].rev == "e2", "path, size and rev")
check(files[1].modified == 1794000000, "modified is the time put gave")
ok, files = mock.provider("list", "saves/gba/")
check(ok and #files == 1, "a system folder lists too")
ok, files = mock.provider("list", "")
check(ok and #files == 3, "list of everything has the three files")

local into = mock.lend("")
ok = mock.provider("get", SAVE, into)
check(ok and mock.lent[into] == "SAVE-1", "get writes the file the host lent")
local why
ok, why = mock.provider("get", "saves/gba/Missing.srm", mock.lend(""))
check(not ok and why:find("not on the server"), "a missing file is a failure")

ok, rev = mock.provider("put", SAVE, mock.lend("SAVE-2"), "e2", 1794000300)
check(ok and rev ~= "e2" and index().files[SAVE].rev == rev, "put over the version the index holds")
ok, why = mock.provider("put", SAVE, mock.lend("SAVE-3"), "e2", 1794000400)
check(not ok and why == "conflict", "put over a newer remote version is a conflict")
check(server.files[NAME].content == "SAVE-2", "the newer version stays")

ok = mock.provider("delete", SAVE)
check(ok and server.files[NAME] == nil and index().files[SAVE] == nil, "delete removes the file and its entry")
check(mock.provider("delete", SAVE), "deleting a file that is gone is fine")

ok, files = mock.provider("status")
check(ok and files.server == "http://nas.local:8080/dav/EmuDEN/" and files.user == "jdoe", "status names server and user")

for _, req in ipairs(mock.requests) do
  check(req.method == "GET" or req.method == "PUT" or req.method == "DELETE", "only GET, PUT and DELETE: " .. req.method)
end

server.auth = "Basic changed"
ok, why = mock.provider("list", "saves/")
check(not ok and why:find("refused the user name"), "a refused password is reported")

-- Only the confirmed server: any other address is refused before it is asked.
local answer = mock.den.http.request{ url = "https://other.example.com/dav/" }
check(answer == nil, "other servers are refused")

mock.answer(true)
mock.action("forget")
check(mock.storage.base == nil and mock.secrets.password == nil, "Forget removes the setup")

mock.finish()
