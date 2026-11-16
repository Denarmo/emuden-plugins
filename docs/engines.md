# Engines and cores

A console plugin says `"engine": "libretro"`, and each of its systems lists its `cores`, best
first. A core is one of two component types:

| `type` | Runs | Player features |
|---|---|---|
| `libretro-core` | inside EmuDEN's player, loaded from a pinned download | all of EmuDEN's: save states, rewind, fast-forward, run-ahead, cheats, shaders, borders, achievements, playing together |
| `engine-app` | as a standalone emulator app that speaks the [Emulator Control Protocol](https://github.com/Denarmo/emulator-control-protocol) (ECP); EmuDEN starts it with the game and drives it | what the engine offers over ECP: pause menu, save states, fast-forward, reset, its settings, screenshots |

The player picks a console's core on its page (Settings > Consoles > the console > Core); a game
may have its own. `"engine": "switch2"` is EmuDEN's own engine and only for its own plugins.
There is no engine for other programs: an emulator that does not speak ECP cannot be a core, and
no plugin starts anything else.

## Switch 2: installed by hand

The Switch 2 console (`emuden.switch2`) is neither built into EmuDEN nor in any list, and no
engine is downloaded for it. It is in `manual/emuden.switch2/` and packed, signed, as
`manual/emuden.switch2.emuplugin`. A player who has the engine program installs the console:

1. Download `manual/emuden.switch2.emuplugin` from this repository.
2. In EmuDEN choose **Settings > Plugins > Install a console from a file** (also on Settings >
   Consoles) and pick the file. EmuDEN shows what it is and that EmuDEN signed it; install it.
3. If EmuDEN does not find the engine program, it asks for it at once (later: Settings >
   Consoles > Nintendo Switch 2 > Engine program). The path is kept on this device only
   (`engine.switch2.path`, never synced) and is the first place EmuDEN looks.

Until then Switch 2 shows nowhere: no console, no Home tab, and a `SWITCH 2` folder is no
console's folder. Its engine component says `"delivery": {"<platform>": "manual"}`: the player
brings it. A device that had Switch 2 before EmuDEN stopped building it in keeps it when its
library has Switch 2 games (the app fetches the signed `manual/` package once); a new install
never gets it. Removing the console on its page removes the plugin; games and the engine stay.

## `libretro-core`

```json
{ "id": "fceumm", "type": "libretro-core", "name": "FCEUmm", "version": "2024.1",
  "downloads": { "windows-x86_64": { "url": "https://...", "sha256": "...", "size": 1234567,
                                     "archive": "zip", "entry": "fceumm_libretro.dll" } } }
```

The `id` is the library's base name. The file is hashed again before every load. A core is loaded
into EmuDEN's own process, so its licence must be compatible with the GPL. `"gpu": "opengl"`
marks a core that draws with OpenGL; playing together is off for such cores.

## `engine-app`

```json
{
  "id": "cemu", "type": "engine-app", "name": "Cemu (ECP)", "version": "2.6-ecp1",
  "ecp": { "id": "io.github.jdoe.cemu", "level": 2,
           "capabilities": ["pause", "menu", "states", "reset", "fast_forward", "settings"],
           "needs": ["keys"] },
  "executable": { "windows-x86_64": "Cemu/Cemu.exe", "linux-x86_64": "Cemu/Cemu.AppImage" },
  "downloads": {
    "windows-x86_64": { "url": "https://...", "sha256": "...", "size": 12345678,
                        "archive": "zip", "entry": "Cemu/" }
  },
  "android": {
    "package": "io.github.jdoe.cemu", "cert_sha256": "AB:CD:...:EF", "min_version_code": 12,
    "apk": { "url": "https://...", "sha256": "...", "size": 34567890, "archive": "none" },
    "store": "https://play.google.com/store/apps/details?id=io.github.jdoe.cemu"
  }
}
```

- `ecp` is the engine's descriptor: its stable `id`, the protocol `level` (1 or 2), the
  `capabilities` it has and what the player sets up inside it (`needs`: `bios`, `keys`,
  `firmware`). It is shown before the engine runs; at run time the engine's hello decides.
- **Desktop:** `downloads` as for a libretro core, and `executable`, the program inside them per
  platform. A zip `entry` ending in `/` is a folder unpacked whole. EmuDEN unpacks it into its
  own engines folder, records the executable's SHA-256 and checks it before each start; it runs
  the program as `<executable> --ecp stdio`.
- **Android:** `package` and `cert_sha256` (the SHA-256 of the signing certificate) are required,
  then `apk` (a pinned file EmuDEN hands to the system installer; the player confirms) or `store`
  (`https://` or `market://`), or both. An installed package is used only when its certificate is
  the pinned one and its version code is at least `min_version_code`.
- List `core.engine-app.1` in `needs`: an EmuDEN without engine apps then refuses the plugin
  instead of offering a console it cannot play.
- Settings of the manifest with `apply.core_option` reach the engine as setting values in its
  launch, after the engine's own defaults ([settings.md](settings.md)).

### The namespace rule

An engine app is a program EmuDEN starts outside itself, so a source offers only its own. For a
source added as `jdoe/consoles` (namespace `jdoe`) the engine's `ecp.id` and Android `package`
must start with one of:

- `jdoe.`
- `io.github.jdoe.`
- for an https source, its host reversed: `org.example.` for `https://example.org/emu/`.

A plugin that names another engine is refused with "the engine app ... is not in this source's
namespace". To offer someone else's emulator, publish your own ECP build of it under your name,
or ask its authors to publish the plugin from their own source.

## Capabilities

`capabilities` (of the manifest, or of one system, which wins) may switch features off for a
console. EmuDEN reads `netplay` (false: its games cannot be played together) and `achievements`
(false: no RetroAchievements). `save_states`, `rewind`, `fast_forward`, `run_ahead` and `cheats`
are not read yet: the player asks the core or the engine what it can do.
