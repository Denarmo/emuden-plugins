-- Offline test of emuden.tune.emuready: device ranking, the mapping of listing settings onto
-- core options, and the page's Apply and Undo over a fake `den` and a fake EmuReady API.
-- Run from the repository root with a plain Lua 5.4: lua tests/emuden.tune.emuready/test.lua
local DIR = "plugins/emuden.tune.emuready/"

local failures, checks = 0, 0
local function check(ok, what)
  checks = checks + 1
  if not ok then
    failures = failures + 1
    print("FAIL: " .. what)
  end
end

local match = dofile(DIR .. "match.lua")
local NOW = 1794700000

local DUO = { name = "Retroid Pocket Duo", model = "Retroid Pocket Duo", soc = "CQ7790S", gpu = "Adreno (TM) 722",
              os = "android", cpu_cores = 8 }
local DUO_ENTRY = { id = "duo", brandName = "Retroid", modelName = "Pocket Duo", socName = "Dragonwing Q-7790" }
local DUO_SOC = { id = "q7790", name = "Dragonwing Q-7790", gpuModel = "Adreno 722", cpuCores = 8 }

local function listing(id, brand, model, soc, gpu, emulator, rank, label, created)
  return { id = id, createdAt = created or "2026-09-21T05:08:23.242Z", notes = "notes " .. id,
           device = { modelName = model, brand = { name = brand }, soc = { name = soc, gpuModel = gpu } },
           emulator = { name = emulator }, performance = { rank = rank, label = label } }
end

local LISTINGS = {
  listing("a", "Samsung", "Galaxy S20 FE (SD)", "Snapdragon 865", "Adreno 650", "NethersX2", 2, "Great"),
  listing("b", "Retroid", "Pocket 5", "Snapdragon 865", "Adreno 650", "NethersX2", 1, "Perfect"),
  listing("c", "Ayaneo", "Pocket S", "Snapdragon G3x Gen 2", "Adreno A32", "AetherSX2", 1, "Perfect"),
  listing("d", "Retroid", "Pocket Duo", "Dragonwing Q-7790", "Adreno 722", "NethersX2", 3, "Playable"),
  listing("e", "Xiaomi", "Redmi 9", "Helio G80", "Mali-G52 MC2", "NethersX2", 5, "Unplayable", "2023-01-01T00:00:00.000Z"),
}

local function field(name, value, label)
  return { value = value, customFieldDefinition = { name = name, label = label or name } }
end

-- Ranking: the same device first, then similar graphics, a weak phone last.
do
  local me = match.me(DUO, DUO_ENTRY, DUO_SOC)
  check(me.gpu_class == 5, "Adreno 722 is class 5")
  check(match.gpu_class("Adreno 650") == 5 and match.gpu_class("Adreno 740") == 7, "Adreno classes")
  check(match.gpu_class("Mali-G52 MC2") == 2, "Mali-G52")
  local ranked = match.rank(me, LISTINGS, "pcsx2", NOW)
  check(ranked[1].listing.id == "d", "the same device first")
  check(ranked[2].listing.id == "b", "then the Snapdragon 865 handheld with the better rating")
  check(ranked[#ranked].listing.id == "e", "the weak phone last")
  local why = table.concat(ranked[1].why, ",")
  check(why:find("same device") and why:find("same chip") and why:find("same emulator"), "reasons: " .. why)
  -- A device EmuReady does not know: only graphics count.
  local unknown = match.me({ name = "Some Handheld", gpu = "Adreno (TM) 722" }, nil, nil)
  local r2 = match.rank(unknown, LISTINGS, "play", NOW)
  check(r2[1].listing.id == "b" or r2[1].listing.id == "d", "similar graphics first without a device entry")
  check(match.time("2026-09-21T05:08:23.242Z") == 1789967303, "listing dates")
end

-- Titles.
do
  check(match.plain("Pokémon Mystery Dungeon: Explorers of Sky (USA)") == "pokemon mystery dungeon explorers of sky", "plain titles")
  local games = { { id = 1, title = "Gran Turismo 4: Spec II" }, { id = 2, title = "Gran Turismo 2" } }
  check(match.same_game("Gran Turismo 2", games).id == 2, "an equal title")
  check(match.same_game("Gran Turismo 4", games) == nil, "a mod of the game is not the game")
end

-- Mapping onto core options.
local PLAY = { core = "play", core_name = "Play!", known = true, options = {
  { key = "play_res_multi", label = "Resolution", value = "1x", values = { "1x", "2x", "4x", "8x" } },
  { key = "play_presentation_mode", value = "Fill Screen", values = { "Fill Screen", "Fit Screen" } },
  { key = "emuden_renderer", value = "Auto", values = { "Auto", "OpenGL", "Vulkan" } },
} }
local PCSX2 = { core = "pcsx2", known = true, options = {
  { key = "pcsx2_renderer", value = "Auto", values = { "Auto", "OpenGL", "Vulkan", "paraLLEl-GS", "Software (HW)" } },
  { key = "pcsx2_upscale_multiplier", value = "1x (Native)", values = { "1x (Native)", "2x", "4x", "8x" } },
  { key = "pcsx2_ee_cycle_rate", value = "100% (Normal Speed)", values = { "50% (Underclock)", "100% (Normal Speed)", "130% (Overclock)" } },
  { key = "pcsx2_ee_cycle_skip", value = "disabled", values = { "disabled", "Mild Underclock", "Moderate Underclock" } },
} }
local PPSSPP = { core = "ppsspp", known = true, options = {
  { key = "ppsspp_internal_resolution", value = "480x272", values = { "480x272", "960x544", "1440x816", "1920x1088" } },
  { key = "ppsspp_frameskip", value = "disabled", values = { "disabled", "1", "2", "3" } },
  { key = "ppsspp_backend", value = "auto", values = { "auto", "opengl", "vulkan" } },
} }
local MELON = { core = "melonds", known = true, options = {
  { key = "melonds_threaded_renderer", value = "enabled", values = { "disabled", "enabled" } },
} }
do
  local nether = { field("resolution_scale", "2", "Resolution Scale"), field("renderer", "Vulkan (Recommended)", "Renderer"),
                   field("ee_cycle_rate", "130% (1)"), field("ee_cycle_skip", "Mild Underclock (1)"),
                   field("average_fps", "60"), field("youtube", "") }
  local play = match.changes(PLAY, nether)
  check(#play == 2, "Play! takes resolution and renderer: " .. #play)
  check(play[1].key == "play_res_multi" and play[1].to == "2x", "2 -> 2x")
  check(play[2].key == "emuden_renderer" and play[2].to == "Vulkan", "Vulkan")
  local pcsx2 = match.changes(PCSX2, nether)
  local by = {}
  for _, c in ipairs(pcsx2) do by[c.key] = c.to end
  check(by.pcsx2_upscale_multiplier == "2x" and by.pcsx2_renderer == "Vulkan", "pcsx2 resolution and renderer")
  check(by.pcsx2_ee_cycle_rate == "130% (Overclock)" and by.pcsx2_ee_cycle_skip == "Mild Underclock", "pcsx2 EE cycles")
  local ppsspp = match.changes(PPSSPP, { field("rendering_resolution", "3"), field("frame_skipping", "1"),
                                         field("backend", "OpenGL (Android/PC)") })
  by = {}
  for _, c in ipairs(ppsspp) do by[c.key] = c.to end
  check(by.ppsspp_internal_resolution == "1440x816", "PSP 3x by width")
  check(by.ppsspp_frameskip == "1" and by.ppsspp_backend == "opengl", "PSP frame skip and backend")
  check(#match.changes(MELON, { field("threaded_rendering", "true") }) == 0, "an equal value changes nothing")
  check(match.changes(MELON, { field("threaded_rendering", "false") })[1].to == "disabled", "melonDS threads off")
  check(#match.changes(PLAY, { field("resolution_scale", "1") }) == 0, "1x is what Play! has")
  check(#match.changes(PLAY, { field("resolution_scale", "720p") }) == 0, "a pixel height is not a scale")
end

-- The page over a fake den and a fake EmuReady.
do
  local json = {}
  local function decode(text) return json[text] end
  local storage, toasts, sets, page, depth = {}, {}, {}, nil, 1
  local own = {}
  local requests = {}
  local function answer(value)
    json[#json + 1] = { result = { data = { json = value } } }
    return { status = 200, body = #json }
  end
  local DETAILS = { id = "d", customFieldValues = { field("resolution_scale", "2", "Resolution Scale"),
                                                     field("renderer", "Vulkan (Recommended)", "Renderer") } }
  den = {
    now = function() return NOW end,
    log = function() end,
    include = function(name) return dofile(DIR .. name) end,
    json = { null = setmetatable({}, { __name = "null" }), decode = decode,
             encode = function(v) json[#json + 1] = v return "J" .. #json end },
    device = { info = function() return DUO end },
    library = { games = function() return {
      { id = "ps2:gt4", name = "Gran Turismo 4", system = "ps2" },
      { id = "gb:tetris", name = "Tetris", system = "gb" },
    } end },
    game = {
      settings = function(id)
        local s = { id = id, core = "play", core_name = "Play!", known = true, options = {} }
        for _, o in ipairs(PLAY.options) do
          s.options[#s.options + 1] = { key = o.key, value = own[o.key] or o.value, values = o.values, own = own[o.key] ~= nil }
        end
        return s
      end,
      set = function(id, values)
        sets[#sets + 1] = values
        local before = {}
        for k, v in pairs(values) do
          before[k] = own[k] or den.json.null
          own[k] = (v ~= den.json.null) and v or nil
        end
        return before
      end,
    },
    http = { get = function(request)
      requests[#requests + 1] = request.url
      local procedure = request.url:match("/trpc/([%w%.]+)")
      local input = request.url:match("%?input=J(%d+)")
      input = input and json[tonumber(input)] and json[tonumber(input)].json
      if procedure == "devices.get" then return answer({ devices = { DUO_ENTRY } }) end
      if procedure == "devices.socs" then return answer({ { id = "q7790", name = "Dragonwing Q-7790" } }) end
      if procedure == "socs.getById" then return answer(DUO_SOC) end
      if procedure == "general.systems" then return answer({ { id = "sys-ps2", key = "sony_playstation_2" } }) end
      if procedure == "games.get" then
        check(input.systemId == "sys-ps2", "the search names the console")
        return answer({ games = { { id = "er-gt4s2", title = "Gran Turismo 4: Spec II", _count = { listings = 5 } } } })
      end
      if procedure == "listings.get" then
        -- As EmuReady sends them: a listing without a chip, rating or notes has JSON nulls.
        local odd = listing("f", "Odin", "2", "x", "x", "NethersX2", 1, "Perfect")
        odd.device.soc, odd.performance, odd.notes = den.json.null, den.json.null, den.json.null
        local all = {}
        for i, l in ipairs(LISTINGS) do all[i] = l end
        all[#all + 1] = odd
        return answer({ listings = all })
      end
      if procedure == "listings.byId" then return answer(DETAILS) end
      return { status = 404, body = "" }
    end },
    storage = {
      get = function(k) return storage[k] end,
      set = function(k, v) storage[k] = v return true end,
      remove = function(k) storage[k] = nil return true end,
    },
    ui = {
      depth = function() return depth end,
      set = function(p) page = p end, push = function(p) page = p depth = depth + 1 end, pop = function() depth = depth - 1 end,
      toast = function(t) toasts[#toasts + 1] = t end,
    },
  }
  -- den.json.encode of the input must not hide it from the fake: keep the URL's token readable.
  local escape_free = den.json.encode
  den.json.encode = function(v) return escape_free(v) end
  local plugin = dofile(DIR .. "main.lua")
  plugin.open()
  local rows = {}
  for _, e in ipairs(page.body) do if e.type == "row" then rows[#rows + 1] = e.label end end
  check(#rows == 1 and rows[1] == "Gran Turismo 4", "only consoles EmuReady covers are listed")
  check(page.body[1].text:find("Dragonwing Q%-7790") and page.body[1].text:find("Adreno 722"), "the device as EmuReady knows it")
  plugin.actions.game("ps2:gt4")
  check(page.body[1].text:find("Which EmuReady game"), "a title that is not equal is asked about")
  plugin.actions.pick(1)
  check(storage["match:ps2:gt4"].id == "er-gt4s2", "the choice is kept")
  local detail = page.body[1]
  check(detail.type == "detail", "the game's page")
  check(detail.text:find("Resolution: 1x %-> 2x") and detail.text:find("Renderer: Auto %-> Vulkan"), "the changes: " .. detail.text)
  check(detail.text:find("Retroid Pocket Duo"), "from the same device's listing")
  check(detail.buttons[1].label == "Apply", "Apply")
  plugin.actions.apply()
  check(#sets == 1 and sets[1].play_res_multi == "2x" and sets[1].emuden_renderer == "Vulkan", "applied")
  check(storage["undo:ps2:gt4"].play_res_multi == den.json.null, "undo remembers there was no own value")
  check(page.body[1].buttons[1].label == "Undo", "then Undo")
  plugin.actions.undo()
  check(own.play_res_multi == nil and own.emuden_renderer == nil, "Undo removes the game's own values")
  check(storage["undo:ps2:gt4"] == nil, "and forgets them")
  local before = #requests
  plugin.actions.choose(2)
  check(#requests == before + 1, "a chosen listing's details are read once")
  plugin.actions.choose(2)
  check(#requests == before + 1, "and kept")
end

print(string.format("%d checks, %d failed", checks, failures))
os.exit(failures == 0 and 0 or 1)
