# The console manifest (`plugin.json`)

UTF-8 JSON, at most 1 MiB. Paths use `/`, are relative and never contain `..`.
`schema/plugin.schema.json` describes the same format for editors. Feature and interface
plugins have their own pages ([feature-plugins.md](feature-plugins.md),
[interface-plugins.md](interface-plugins.md)).

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
| `sync` | object | no | Not read yet (below) |

## `systems[]`

| Field | Required | Meaning |
|---|---|---|
| `id`, `name` | yes | `id` is the ROM folder name and the key of saves and settings. Never change it |
| `short_name` | no | A compact label |
| `group` | yes | `nintendo`, `sega`, `sony`, `microsoft`, `pc`, `other`, or your own heading |
| `order` | yes | Place among the home groups. EmuDEN's consoles use 100, 200, ... |
| `content` | yes | Which files are games ([content.md](content.md)) |
| `presentation` | yes | `cover_aspect` (width over height), `handheld`, `right_stick_holds`, `buttons` (below) |
| `artwork` | no | `libretro_thumbnails` (folder on the thumbnail server), `rdb` (libretro database name), `launchbox` (LaunchBox platform), `cover_by_id` (cover addresses with `{id}`) |
| `achievements` | no | `{"rcheevos_console": 7}` |
| `capabilities` | no | Wins over the manifest's ([engines.md](engines.md#capabilities)) |
| `platforms` | no | As the top-level field, for this system only |
| `cores` | yes | Component ids, best first |
| `bios` | no | Below |

`presentation.buttons` names the buttons of the console's own pad, for the button mapping screen
and the hints: `[{"pad": "b", "label": "Cross"}, {"pad": "a", "label": "Circle"}]`. `pad` is a
RetroPad button (`b`, `y`, `select`, `start`, `a`, `x`, `l`, `r`, `l2`, `r2`, `l3`, `r3`, or
`up`, `down`, `left`, `right`); buttons you leave out are not offered for the console. The D-pad
is added for you. Without `buttons` the RetroPad's own names are shown. Needs
`presentation.buttons`.

## `components[]`

| Field | Required | Meaning |
|---|---|---|
| `id` | yes | For a core, the library's base name: `fceumm` is `fceumm_libretro.dll` |
| `type` | yes | `libretro-core` or `engine-app` ([engines.md](engines.md)); `system-files` in EmuDEN's own plugins (below) |
| `name` | yes | Shown to the player |
| `version`, `license`, `homepage` | no | |
| `gpu` | no | `none` (default) or `opengl`: the core draws with the graphics card |
| `forced_core_options` | no | Core option to value, always applied unless the player chose otherwise |
| `widescreen` | no | `{"options": {...}, "restart": false}`: the core options that make the picture widescreen |
| `games` | no | `{"offset": 172, "length": 4, "codes": [...]}`: games this core plays instead of the console's chosen one, by the code in their header |
| `downloads` | yes | Platform key (or `any`) to a download |
| `ecp`, `executable`, `android` | engine app | [engines.md](engines.md#engine-app) |

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
| `sync` (`saves`, `states`, `settings`, `cheats`) | Every console syncs alike, as the player set up sync |
| `capabilities.save_states`, `rewind`, `fast_forward`, `run_ahead`, `cheats` | The player asks the core or the engine |
| `systems[].content.magic`, `hash_variants` | The scanner goes by extension and folder; games are looked up by their whole file |
| `systems[].presentation.native_size`, `systems[].romm_slugs` | |
| `settings[].scope` `"game"`, `live`, `inherit` | Every setting is the console's and shown on its page only ([settings.md](settings.md)) |
| `settings[].apply` other than `core_option` | The row is shown; nothing applies the value |
| A download's `strip_components`, `rename`, `executable_bit` | |
