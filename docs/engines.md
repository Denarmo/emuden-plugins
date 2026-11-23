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

## Switch 2: EmuDEN's own engine

The Switch 2 console (`emuden.switch2`) is in the official list like every other console. Its
engine, built from https://github.com/Denarmo/emuden-switch2, is a pinned download of its `engine`
component, installed on the console's page (Settings > Consoles > Nintendo Switch 2 > Install) or
when a game is first started, like a core:

```json
{ "id": "nx2", "type": "engine", "name": "Switch 2 engine", "version": "2026.11.23",
  "delivery": { "windows-x86_64": "download", "linux-x86_64": "download" },
  "downloads": { "windows-x86_64": { "url": "https://github.com/Denarmo/emuden-plugins/releases/download/...",
                                     "sha256": "...", "size": 1234567, "archive": "zip" } },
  "executable": { "windows-x86_64": "bin/emuden-switch2.exe", "linux-x86_64": "bin/emuden-switch2" } }
```

- `delivery` says per platform how the engine comes: `download` (then `downloads` and
  `executable` are required for that platform) or `manual` (the player brings it). A platform
  with neither is not offered. Android has no download: EmuDEN starts no engine program there.
- A zip without an `entry` is unpacked whole into the app's `engines/switch2/` folder (unpacked
  over, so the player's own files there stay); `entry: "Name/"` unpacks one folder of it.
  EmuDEN records the executable's checksum and offers an update when the list pins another download.
- The program the player chose (Settings > Consoles > Nintendo Switch 2 > Engine program,
  `engine.switch2.path`, never synced) still comes first, so a build of their own keeps working.
- The downloads are built and packed in the engine's repository (`tools/package.py`), uploaded to a
  release of this repository (`engines-switch2-<date>`) and written into the manifest by
  `tools/publish_plugin.py` there; then `index` and `sign` as for any release.

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
console. EmuDEN reads `netplay` (false: its games cannot be played together), `achievements`
(false: no RetroAchievements), `save_states` (false: no states, and no resume state either),
`rewind`, `fast_forward` and `cheats` (false: no cheats page, and no cheats are given to the core
or the engine). A feature on here is still only offered when the core or the engine can do it
(an engine needs the ECP `cheats` capability). `run_ahead` is not read: EmuDEN has no run-ahead yet.
