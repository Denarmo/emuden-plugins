# Tune: EmuReady

Sets a game of the library up from [EmuReady](https://www.emuready.com) compatibility
listings of devices like this one.

1. The page lists the library's games of the consoles EmuReady covers (PlayStation, PS2, PSP,
   DS, N64, GameCube, Wii, Dreamcast, Saturn).
2. Pick a game. When EmuReady has no game of exactly that title, the page asks which of its
   games it is (a mod such as "Gran Turismo 4: Spec II" is never taken for the game by
   itself) and remembers the answer; "Another EmuReady game" asks again.
3. The closest listings are shown: device and chip, emulator, rating, age and notes. The
   suggestion comes from the closest one; choosing another listing uses its settings.
4. Apply. EmuDEN asks first and lists every change. The values are the game's own (its
   Settings page shows them, "Reset" there removes them); Undo puts the old ones back.

## How close a listing is

| Points | When |
|---|---|
| 45 | the same device (EmuReady's brand and model against EmuDEN's device name) |
| 25 | the same chip (SoC) |
| up to 18 | otherwise graphics of a similar class (Adreno, Mali, Xclipse; `match.lua`) |
| 12 | an emulator whose settings mean the same as the core's (NetherSX2 for PCSX2, PPSSPP, melonDS, Dolphin, Flycast...) |
| up to 10 | the listing's rating (Perfect, Great, ...) |
| up to 8 | newer than two years |

This device's entry, chip and graphics come from EmuReady's device list. A device it has no
entry for is ranked by its graphics alone.

## Settings it maps

Only onto options the core has, and only when the core's options are known (EmuDEN notes
them the first time a game of the core runs; until then the page says to start the game
once).

| EmuReady field | Core option (first that exists) |
|---|---|
| resolution, resolution scale, upscale, internal / rendering resolution | `densx2_res_multi`, `pcsx2_upscale_multiplier`, `ppsspp_internal_resolution`, `*_opengl_resolution`, `*_efb_scale`, ... (nearest scale) |
| renderer, backend, graphics backend | `emuden_renderer`, `*_renderer`, `*_backend` (Vulkan, OpenGL, Software, Auto) |
| frame skipping | `*_frameskip` |
| EE cycle rate, EE cycle skip | `pcsx2_ee_cycle_rate`, `pcsx2_ee_cycle_skip` |
| threaded rendering | `*_threaded_renderer` |

## Data and limits

EmuReady's public mobile API (`www.emuready.com/api/mobile/trpc/...`, documented at
`emuready.com/docs/api`), without a key. It allows 100 requests in 3 minutes from one
address, so the plugin waits a second between requests and caches: devices and chips for a
month, game searches for a week, listings for 12 hours, a listing's settings for a week. A
game page costs two to four requests. EmuReady's terms ask for no commercial use without
permission; this plugin is free.

Nothing is offered before a game's first start yet: EmuDEN has no hook for that.

## Test

`lua tests/emuden.tune.emuready/test.lua` (plain Lua 5.4, from the repository root).
