# The console manifest (`plugin.json`)

UTF-8 JSON, at most 1 MiB. Paths use `/`, are relative and never contain `..`.
`schema/plugin.schema.json` describes the same format for editors. Feature and interface
plugins have their own pages ([feature-plugins.md](feature-plugins.md),
[interface-plugins.md](interface-plugins.md), [quick-settings.md](quick-settings.md),
[themes.md](themes.md)).

## Top level

| Field | Type | Required | Meaning |
|---|---|---|---|
| `manifest_version` | int | yes | 1 |
| `id` | string | yes | `<namespace>.<name>`, lower case letters, digits, `-`, `.`. The namespace is your source's ([publishing.md](publishing.md)); `emuden` is reserved |
| `name`, `version` | string | yes | `version` is `major.minor.patch` |
| `kind` | string | yes | `console` |
| `engine` | string | yes | `libretro` (`switch2` is EmuDEN's own) ([engines.md](engines.md)) |
| `publisher`, `license` | string | yes | `license` is the SPDX id of the manifest and its pictures |
| `homepage`, `summary` | string | no | |
| `api` | int | yes | The lowest host API the plugin works with; 1 today |
| `needs` | string[] | yes | The host features it uses ([compatibility.md](compatibility.md)) |
| `platforms` | string[] | no | `windows-x86_64`, `linux-x86_64`, `linux-aarch64`, `macos-arm64`, `android-arm64` or `any` (the default). Elsewhere the console has no core to install |
| `depends` | object[] | no | `{"id": "...", "version": ">=1.0.0"}`: another console plugin that must be installed, in that range; until it is, this plugin's consoles are not shown |
| `systems` | object[] | yes | Below |
| `components` | object[] | no | Below |
| `capabilities` | object | no | [engines.md](engines.md#capabilities) |
| `settings` | object[] | no | [settings.md](settings.md) |
| `sync` | object | no | `saves`, `states`, `settings`: false keeps that part of the plugin's consoles off sync (default true). `cheats` is not read yet: cheats stay on the device |

## `systems[]`

| Field | Required | Meaning |
|---|---|---|
| `id`, `name` | yes | `id` is the ROM folder name and the key of saves and settings. Never change it |
| `short_name` | no | A compact label |
| `group` | yes | `nintendo`, `sega`, `sony`, `microsoft`, `pc`, `other`, or your own heading |
| `order` | yes | Place among the home groups. EmuDEN's consoles use 100, 200, ... |
| `content` | yes | Which files are games ([content.md](content.md)) |
| `presentation` | yes | `cover_aspect` (width over height), `handheld`, `right_stick_holds`, `buttons`, `layout`, `digital_only`, `media`, `screens` (below) |
| `artwork` | no | `libretro_thumbnails` (folder on the thumbnail server), `rdb` (libretro database name), `launchbox` (LaunchBox platform), `cover_by_id` (cover addresses with `{id}`) |
| `achievements` | no | `{"rcheevos_console": 7}` |
| `capabilities` | no | Wins over the manifest's ([engines.md](engines.md#capabilities)) |
| `platforms` | no | As the top-level field, for this system only |
| `cores` | yes | Component ids, best first |
| `default_core` | no | The core chosen until the player picks one; the first of `cores` that has a download when it is left out |
| `bios` | no | Below |

`presentation.buttons` names the buttons of the console's own pad, for the button mapping screen
and the hints: `[{"pad": "b", "label": "Cross"}, {"pad": "a", "label": "Circle"}]`. `pad` is a
RetroPad button (`b`, `y`, `select`, `start`, `a`, `x`, `l`, `r`, `l2`, `r2`, `l3`, `r3`, or
`up`, `down`, `left`, `right`); buttons you leave out are not offered for the console. The D-pad
is added for you. Without `buttons` the RetroPad's own names are shown. Needs
`presentation.buttons`.

The rest of `presentation` says how the console's games look and play. A field left out is
filled from EmuDEN's own tables for the consoles it knows, and otherwise as the defaults say:

| Field | Default | Meaning |
|---|---|---|
| `layout` | `other` | `nintendo`: the console's own pad has A on the right and B below it, so a pad lettered the other way round (Xbox) presses the button of the same letter |
| `digital_only` | false | The console has no stick: the left stick works as the D-pad too |
| `media` | a plain cartridge | How the standard Home and the boot screen draw a game: `{"shape": "card", "style": "hucard", "aspect": 0.64, "disc": false, "umd": false}`. `shape` is `cartridge`, `card`, `case`, `jewel` or `disc`; `style` one of EmuDEN's moulds (`pocket`, `pocket_wide`, `nes`, `snes`, `n64`, `megadrive`, `mastersystem`, `gamegear`, `32x`, `mycard`, `hucard`, `lynx`, `neogeopocket`, `wonderswan`, `virtualboy`, `pokemini`, `atari`, `atari5200`, `jaguar`, `vectrex`, `colecovision`, `intellivision`); `aspect` is width over height; `disc` puts a disc in a case or jewel case, `umd` a UMD |
| `screens` | one screen | A picture of several screens, below |

`screens` lists the shapes a core's picture may have and which part of it each screen is. A
shape applies when the picture's width over its height is that of `frame` (any multiple, so a
core drawing at twice the size still matches); each screen's `rect` is `[x, y, w, h]` of the
picture, 0 to 1 with row 0 at the top, and `touch` says presses on it reach the game. The
player then lays the screens out on one display or puts one on the device's second screen:

```json
"screens": [{ "frame": [256, 384],
              "screens": [{ "rect": [0, 0, 1, 0.5] }, { "rect": [0, 0.5, 1, 0.5], "touch": true }] }]
```

A core can have `presentation.screens` of its own (below), which win over the console's. Give
the core options that make the core draw that shape as the core's `option_hints`.

## `components[]`

| Field | Required | Meaning |
|---|---|---|
| `id` | yes | For a core, the library's base name: `fceumm` is `fceumm_libretro.dll` |
| `type` | yes | `libretro-core` or `engine-app` ([engines.md](engines.md)); `system-files` in EmuDEN's own plugins (below) |
| `name` | yes | Shown to the player |
| `version`, `license`, `homepage` | no | |
| `gpu` | no | `none` (default) or `opengl`: the core draws with the graphics card |
| `forced_core_options` | no | Core option to value, always applied unless the player chose otherwise |
| `language` | no | The core option that sets the language of a game and its value for each app language code: `{"option": "melonds_language", "values": {"en": "English", "es": "Spanish", "*": "English"}}`. The player gives it the app's language (`es-MX` tries `es-MX`, then `es`, then `*`) before `option_hints`, `forced_core_options` and the player's own values, so any of those wins. Cores that ask the frontend's language (libretro's GET_LANGUAGE) are told it without this |
| `option_hints` | no | Core option to value, applied before `forced_core_options` and the player's own values: what makes the core draw the shape its `screens` describe |
| `presentation` | no | `{"screens": [...]}`: the screens of this core's picture, as the system's `presentation.screens` |
| `netplay` | no | How the core plays a game together with another device (below) |
| `options_name` | no | The name the core reports for itself (`dolphin-emu`), whose letters and digits key its stored option values; the component id when left out |
| `tuning` | no | Core option values chosen by device (below) |
| `widescreen` | no | `{"options": {...}, "restart": false}`: the core options that make the picture widescreen |
| `games` | no | `{"offset": 172, "length": 4, "codes": [...]}`: games this core plays instead of the console's chosen one, by the code in their header |
| `downloads` | yes | Platform key (or `any`) to a download |
| `ecp`, `executable`, `android` | engine app | [engines.md](engines.md#engine-app) |

`netplay` gives the Together page the core that plays the console's games linked, the way
the real consoles linked (Game Boys by cable, DS by local wireless). The first core of the
console that has one is used; without one, the console's chosen core plays in lockstep, one
console with a controller on each device:

```json
"netplay": { "mode": "link",
             "description": "Local wireless between two DS. Each device plays its own game and save." }
```

| Field | Meaning |
|---|---|
| `mode` | `link`: each device plays its own game and save, linked. `lockstep`: both run the same emulation |
| `subsystem` | Non-zero: the game is loaded twice through this libretro subsystem (TGB Dual's 257, two linked Game Boys) |
| `description` | What it does, shown before the player starts |
| `host`, `guest` | Per side: `save_memory`, the libretro memory its own battery save is kept in (with a subsystem the other side's is the peer's), and `options`, core option values for that session only |

`tuning` picks a core option's value by the device: the tier EmuDEN classified it as (`low`,
`mid`, `high`, `very_high`), the height of its main screen and its processor cores. Each option
lists cases; the first one the device meets is installed as the default the player can change:

```json
"tuning": { "ppsspp_internal_resolution": [
  { "min_tier": "high", "min_screen_height": 907, "value": "1920x1088", "describe": "PSP 4x" },
  { "min_tier": "mid", "min_screen_height": 605, "value": "1440x816", "describe": "PSP 3x" },
  { "value": "480x272", "describe": "PSP 1x" } ] }
```

`describe` is shown on the setup page's summary; a case without it is not. A case with a tier
this EmuDEN does not know is left out.

A download:

| Field | Required | Meaning |
|---|---|---|
| `url` | yes | `https://`, no user name |
| `sha256` | yes | 64 hex digits of the file |
| `size` | yes | Its exact size in bytes |
| `archive` | yes | `zip` or `none` |
| `entry` | zip | The member inside the zip; a folder to unpack whole as `Name/` |
| `file` | developer folder | A file on this device in place of `url`; `sha256` and `size` are then optional ([getting-started.md](getting-started.md)) |

Unknown keys in a download, in `bios`, `depends` and a setting's `apply` are errors. There is no
7z support and no installer is ever run (Android's system installer, which the player confirms,
installs an engine app's APK).

### System files

Some cores need data of their own beside the BIOS files (PPSSPP its fonts and `ppge_atlas.zim`).
A `system-files` component is a zip whose folder `entry` is unpacked into the BIOS folder, keeping
its path, when one of the cores in `cores` is installed (every core of the plugin when `cores` is
left out):

```json
{ "id": "ppsspp-assets", "type": "system-files", "name": "PPSSPP assets", "cores": ["ppsspp"],
  "downloads": { "any": { "url": "https://...", "sha256": "...", "size": 11038871,
                          "archive": "zip", "entry": "PPSSPP/" } } }
```

`plugin_tool.py` allows them in EmuDEN's own plugins only. An EmuDEN that does not know a
component type leaves the component alone, and the console still plays.

## `bios`

```json
"bios": [{ "label": "PlayStation BIOS", "any_one": false, "cores": ["swanstation"],
           "files": [{ "path": "scph5501.bin", "optional": true }] }]
```

Paths are relative to the BIOS folder ([glossary.md](glossary.md)); a trailing slash means a
folder that must hold something. `cores` limits the set to those cores. BIOS files are never
downloaded: a `url` here is an error. `@firmware` and `@keys` are answered by the Switch 2 engine
only.

## Fields not read yet

The schema has these fields, and `plugin_tool.py validate` accepts them, but this EmuDEN ignores
them. `validate` prints a `warning: not read by EmuDEN yet` line for each one a manifest uses, so
nobody relies on them:

| Field | What happens instead |
|---|---|
| `sync.cheats` | Cheats stay on the device |
| `capabilities.run_ahead` | EmuDEN has no run-ahead yet |
| `systems[].content.hash_variants` | Games are looked up by their whole file |
| `systems[].presentation.native_size`, `systems[].romm_slugs` | |
| `settings[].scope` `"game"`, `live`, `inherit` | Every setting is the console's and shown on its page only ([settings.md](settings.md)) |
| `settings[].apply` other than `core_option` | The row is shown; nothing applies the value |
| A download's `strip_components`, `rename`, `executable_bit` | |
