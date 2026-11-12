# The manifest (`plugin.json`)

UTF-8 JSON, at most 1 MiB. Paths use `/`, are relative and never contain `..`.
`schema/plugin.schema.json` describes the same format for editors.

## Top level

| Field | Type | Required | Meaning |
|---|---|---|---|
| `manifest_version` | int | yes | 1 |
| `id` | string | yes | `<namespace>.<name>`, lower case letters, digits, `-`, `_`. The namespace is your GitHub name; `emuden` is reserved |
| `name`, `version` | string | yes | `version` is `major.minor.patch` |
| `kind` | string | yes | `console` |
| `engine` | string | yes | `libretro` or `external` ([engines.md](engines.md)) |
| `publisher`, `license` | string | yes | `license` is the SPDX id of the manifest and its pictures |
| `homepage`, `summary` | string | no | |
| `api` | int | yes | The lowest host API the plugin works with; 1 today |
| `needs` | string[] | yes | The host features it uses ([compatibility.md](compatibility.md)) |
| `platforms` | string[] | no | `windows-x86_64`, `linux-x86_64`, `linux-aarch64`, `macos-arm64`, `android-arm64` or `any` (the default) |
| `depends` | object[] | no | `{"id": "...", "version": ">=1.0.0"}` |
| `systems` | object[] | yes | Below |
| `components` | object[] | no | Below |
| `capabilities` | object | no | [engines.md](engines.md) |
| `settings` | object[] | no | [settings.md](settings.md) |
| `sync` | object | no | Below |

## `systems[]`

| Field | Required | Meaning |
|---|---|---|
| `id`, `name` | yes | `id` is the ROM folder name and the key of saves and settings. Never change it |
| `short_name` | no | A compact label |
| `group` | yes | `nintendo`, `sega`, `sony`, `microsoft`, `pc`, `other`, or your own heading |
| `order` | yes | Place among the home groups. EmuDEN's consoles use 100, 200, ... |
| `content` | yes | Which files are games ([content.md](content.md)) |
| `presentation` | yes | `cover_aspect` (width over height), `handheld`, `right_stick_holds`, `native_size` (`[width, height]`), `buttons` (below) |
| `artwork` | no | `libretro_thumbnails` (folder on the thumbnail server), `rdb` (libretro database name) |
| `achievements` | no | `{"rcheevos_console": 7}` |
| `cores` | libretro | Component ids, best first |
| `emulator` | external | Component id |
| `bios` | no | Below |

`presentation.buttons` names the buttons of the console's own pad, for the button mapping screen
and the hints: `[{"pad": "b", "label": "Cross"}, {"pad": "a", "label": "Circle"}]`. `pad` is a
RetroPad button (`b`, `y`, `select`, `start`, `a`, `x`, `l`, `r`, `l2`, `r2`, `l3`, `r3`, or
`up`, `down`, `left`, `right`); buttons you leave out are not offered for the console. The D-pad
is added for you. Without `buttons` the RetroPad's own names are shown.

## `components[]`

| Field | Required | Meaning |
|---|---|---|
| `id` | yes | For a core, the library's base name: `fceumm` is `fceumm_libretro.dll` |
| `type` | yes | `libretro-core` or `external-emulator`; `system-files` in EmuDEN's own plugins (below) |
| `name` | yes | Shown to the player |
| `version`, `license`, `homepage` | no | |
| `gpu` | no | `none` (default) or `opengl`: the core draws with the graphics card |
| `forced_core_options` | no | Core option to value, always applied unless the player chose otherwise |
| `downloads` | no | Platform key (or `any`) to a download |
| `launch` | external | [engines.md](engines.md) |

A download:

| Field | Required | Meaning |
|---|---|---|
| `url` | yes | `https://`, no user name, no query string |
| `sha256` | yes | 64 hex digits of the file |
| `size` | yes | Its exact size in bytes |
| `archive` | yes | `zip` or `none` |
| `entry` | cores | The library inside the zip; for system files the folder to unpack, as `Name/` |
| `strip_components` | no | Leading folders to drop when a whole zip is unpacked |
| `rename` | no | The name a single file is stored under |
| `executable_bit` | no | Mark the program executable (AppImage) |

Unknown keys in a download, in `launch`, `bios`, `sync` and a setting's `apply` are errors. There is
no 7z support and no installer is ever run.

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

Only the official source may carry one. An EmuDEN that does not know a component type leaves the
component alone, and the console still plays.

## `bios`

```json
"bios": [{ "label": "PlayStation BIOS", "any_one": false,
           "files": [{ "path": "scph5501.bin", "optional": true }] }]
```

Paths are relative to `<EdenDir>/emuden/bios`; a trailing slash means a folder that must hold
something. BIOS files are never downloaded: a `url` here is an error.

## `sync`

```json
"sync": { "saves": true, "states": true, "settings": true, "cheats": true,
          "paths": [{ "id": "mlc-saves", "path": "mlc01/usr/save", "toggle": "saves" }] }
```

`saves` and `cheats` let the console's folders under `saves/` and `cheats/` go to the player's
Google Drive when they turned that on. `paths` is for standalone emulators: folders inside
`<EdenDir>/emuden/plugin-data/<plugin id>/`, each behind one of the player's switches (`saves`,
`play-data`, `captures`, `settings`). A plugin cannot name any other place.
