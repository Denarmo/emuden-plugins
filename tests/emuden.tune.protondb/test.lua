-- Offline test of emuden.tune.protondb: the ranking, the suggestion, and the page's Apply and
-- Undo over a fake `den`. Run from the repository root with a plain Lua 5.4:
--   lua tests/emuden.tune.protondb/test.lua
local DIR = "plugins/emuden.tune.protondb/"

local failures, checks = 0, 0
local function check(ok, what)
  checks = checks + 1
  if not ok then
    failures = failures + 1
    print("FAIL: " .. what)
  end
end

local rank = dofile(DIR .. "rank.lua")
local NOW = 1794700000
local YEAR = 365 * 86400

local LEGION = { name = "Legion Go S", soc = "AMD Ryzen Z2 Go w/ Radeon 780M Graphics", gpu = "AMD Radeon 780M (RADV PHOENIX)",
                 os = "linux", steamos = true, ram_mb = 15872, handheld = true }
local WINDOWS_PC = { name = "DENA-PC", soc = "AMD Ryzen 9 5900X 12-Core Processor", gpu = "NVIDIA GeForce RTX 3080",
                     os = "windows", steamos = false, ram_mb = 32768 }

local REPORTS = {
  { t = NOW - 30 * 86400, verdict = "yes", device = "pc", os = "CachyOS", cpu = "AMD Ryzen 5 5600X 6-Core",
    gpu = "NVIDIA GeForce RTX 3060 Ti", ram = "32 GB", proton = "10.0-3", launch = "PROTON_ENABLE_NVAPI=1 %command%" },
  { t = NOW - 200 * 86400, verdict = "yes", device = "pc", os = "SteamOS Holo", cpu = "AMD Ryzen Z2 Go",
    gpu = "AMD Radeon 780M (radv, phoenix)", ram = "16 GB", proton = "Experimental",
    launch = "gamemoderun %command% -dx11", notes = "Smooth at 800p" },
  { t = NOW - 2 * YEAR, verdict = "yes", device = "steamDeck", os = "SteamOS Holo", cpu = "AMD Custom APU 0405",
    gpu = "AMD Custom GPU 0405 (vangogh, LLVM 15)", ram = "15 GB", proton = "9.0-4" },
  { t = NOW - 10 * 86400, verdict = "no", device = "pc", os = "Fedora", cpu = "Intel Core i7-12700K",
    gpu = "Intel Arc A770", ram = "32 GB", proton = "GE-Proton9-20", launch = "rm -rf ~; %command%" },
}

local TOOLS = { { name = "proton_11", display = "Proton 11.0" }, { name = "proton_experimental", display = "Proton Experimental" },
                { name = "GE-Proton9-20", display = "GE-Proton9-20" } }

-- Ranking on the Legion Go S: the Z2 Go report first, then the Deck, the NVIDIA PC last but one.
do
  local me = rank.me(LEGION)
  check(me.class == "z2 go", "the Legion Go S is a Z2 Go handheld")
  check(me.steamos and me.gpu_vendor == "amd", "SteamOS on AMD")
  local ranked = rank.rank(me, REPORTS, NOW)
  check(ranked[1].report == REPORTS[2], "the same handheld ranks first")
  check(ranked[2].report == REPORTS[3], "a Steam Deck ranks second")
  check(ranked[1].score > ranked[2].score and ranked[2].score > ranked[3].score, "scores fall")
  local why = table.concat(ranked[1].why, ",")
  check(why:find("same handheld") and why:find("same graphics") and why:find("SteamOS"), "reasons: " .. why)
  check(rank.describe(REPORTS[2]) == "Legion Go S / Z2 Go", "a Z2 Go report reads as the Legion Go S")
  check(rank.describe(REPORTS[3]) == "Steam Deck", "a Deck report")
  check(rank.describe(REPORTS[1]) == "NVIDIA GeForce RTX 3060 Ti", "a PC by its graphics")

  local s = rank.suggest(me, ranked, TOOLS)
  check(s.tool and s.tool.name == "proton_experimental" and s.tool.installed, "Proton from the closest working reports")
  check(s.launch == "gamemoderun %command% -dx11", "launch options of the closest report that has some")
  check(s.from.report == REPORTS[2], "the suggestion names its report")

  -- A chosen report gives its own settings.
  local deck = nil
  for _, entry in ipairs(ranked) do
    if entry.report == REPORTS[3] then deck = entry end
  end
  local chosen = rank.suggest(me, ranked, TOOLS, deck)
  check(chosen.tool.name == "proton_9" and not chosen.tool.installed and chosen.tool.official, "Proton 9 is fetched by Steam")
  check(chosen.launch == nil, "the Deck report has no launch options")
end

-- NVIDIA-only variables are not suggested to an AMD device; shell syntax never.
do
  local me = rank.me(LEGION)
  check(rank.launch_for(me, REPORTS[1]) == nil, "PROTON_ENABLE_NVAPI is for NVIDIA only")
  check(rank.launch_for(me, REPORTS[4]) == nil, "shell syntax is dropped")
  check(rank.launch_for(rank.me(WINDOWS_PC), REPORTS[1]) == "PROTON_ENABLE_NVAPI=1 %command%", "NVIDIA keeps it")
end

-- Tool names.
do
  check(rank.tool_for("10.0-3", TOOLS).name == "proton_10", "10.0-3")
  check(rank.tool_for("Proton 6.3-8", TOOLS).name == "proton_63", "6.3-8")
  check(rank.tool_for("Experimental", TOOLS).installed, "Experimental is installed")
  check(rank.tool_for("GE-Proton9-20", TOOLS).installed, "a custom tool that is installed")
  local missing = rank.tool_for("GE-Proton8-1", TOOLS)
  check(missing and not missing.installed and not missing.official, "a custom tool that is not")
  check(rank.tool_for("", TOOLS) == nil and rank.tool_for("Default", TOOLS) == nil, "no tool")
end

-- Windows: only the game's own arguments apply.
do
  check(rank.windows_args("gamemoderun %command% -dx11") == "-dx11", "arguments after %command%")
  check(rank.windows_args("-nointro") == "-nointro", "plain arguments")
  check(rank.windows_args("DXVK_ASYNC=1 %command%") == nil, "only variables")
  check(rank.windows_args("DXVK_ASYNC=1") == nil, "a variable alone")
end

-- The page, over a fake den: Apply asks through den.steam.set and Undo puts the old values back.
do
  local json_store = {}
  local storage, toasts, sets, page = {}, {}, {}, nil
  local steam_config = { launch_options = "", compat_tool = "proton_11", compat_tool_display = "Proton 11.0-2" }
  local data = { appid = "1145350", total = 227, reports = REPORTS }
  den = {
    now = function() return NOW end,
    log = function() end,
    include = function(name) return dofile(DIR .. name) end,
    json = {
      null = {},
      decode = function(text) return json_store[text] end,
      encode = function(v) json_store[#json_store + 1] = v return "#" .. #json_store end,
    },
    device = { info = function() return LEGION end },
    steam = {
      status = function()
        return { installed = true, can_change = true, note = "", tools = TOOLS,
                 apps = { { appid = "1145350", name = "Hades II", shortcut = false },
                          { appid = "4105511571", name = "EmuDEN", shortcut = true } } }
      end,
      config = function() return { launch_options = steam_config.launch_options, compat_tool = steam_config.compat_tool,
                                   compat_tool_display = steam_config.compat_tool_display } end,
      set = function(t)
        sets[#sets + 1] = t
        if t.launch_options then steam_config.launch_options = t.launch_options end
        if t.compat_tool then steam_config.compat_tool = t.compat_tool; steam_config.compat_tool_display = t.compat_tool end
        return true
      end,
    },
    http = {
      get = function(request)
        if request.url == "https://raw.githubusercontent.com/Denarmo/protondb-reports/main/data/apps/50/1145350.json" then
          json_store["data"] = data
          return { status = 200, body = "data" }
        elseif request.url:find("protondb.com/api/v1/reports/summaries/1145350.json", 1, true) then
          json_store["summary"] = { tier = "platinum" }
          return { status = 200, body = "summary" }
        end
        return { status = 404, body = "" }
      end,
    },
    storage = {
      get = function(k) return storage[k] end,
      set = function(k, v) storage[k] = v return true end,
      remove = function(k) storage[k] = nil return true end,
    },
    ui = {
      depth = function() return page and 2 or 1 end,
      set = function(p) page = p end, push = function(p) page = p end, pop = function() end,
      toast = function(t) toasts[#toasts + 1] = t end,
    },
  }
  local plugin = dofile(DIR .. "main.lua")
  plugin.open()
  local rows = 0
  for _, element in ipairs(page.body) do
    if element.type == "row" then rows = rows + 1 end
  end
  check(rows == 1, "shortcuts are not listed")
  plugin.actions.game("1145350")
  local detail = page.body[1]
  check(detail.type == "detail" and detail.title == "Hades II", "the game's page")
  check(detail.facts[1].value == "Platinum", "the ProtonDB rating")
  check(detail.text:find("Proton: Proton Experimental", 1, true), "suggests Proton Experimental: " .. detail.text)
  check(detail.buttons[1].label == "Apply", "Apply is offered")
  plugin.actions.apply()
  check(#sets == 1 and sets[1].compat_tool == "proton_experimental" and sets[1].launch_options == "gamemoderun %command% -dx11",
        "Apply sets both")
  check(storage["undo:1145350"].compat_tool == "proton_11" and storage["undo:1145350"].launch_options == "", "the old values are kept")
  local labels = {}
  for _, button in ipairs(page.body[1].buttons) do labels[#labels + 1] = button.label end
  check(table.concat(labels, ",") == "Undo", "after Apply only Undo: " .. table.concat(labels, ","))
  plugin.actions.undo()
  check(#sets == 2 and sets[2].compat_tool == "proton_11" and sets[2].launch_options == "", "Undo puts them back")
  check(storage["undo:1145350"] == nil, "and forgets them")
  plugin.actions.choose(2) -- the Steam Deck report
  check(page.body[1].text:find("Proton 9", 1, true), "a chosen report's Proton")
end

print(string.format("%d checks, %d failed", checks, failures))
os.exit(failures == 0 and 0 or 1)
