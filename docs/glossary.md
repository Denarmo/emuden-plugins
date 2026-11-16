# Paths and menus

The names the other pages use, in one place.

## Folders

`<data>` is EmuDEN's data folder, shown under Settings > System > Data folder:

| Platform | `<data>` |
|---|---|
| Portable (a `user` folder beside the program, or beside the AppImage) | that `user` folder |
| Windows | `%APPDATA%\EmuDEN\` |
| Linux, SteamOS | `~/.local/share/EmuDEN/` |
| Android | the app's own storage |

| Path | What is there |
|---|---|
| `<data>/plugins/<id>/` | Installed console plugins (`plugin.json`), and feature and interface plugins by version (`<id>/<version>/`) |
| `<data>/plugins-dev/<id>/` | The developer folder: one folder per plugin, named after its id, of any kind |
| `<data>/plugins-local/<id>/` | Unsigned console plugins installed from a file (signed ones go to `<data>/plugins/<id>/`) |
| `<data>/plugin-data/<id>/` | A feature plugin's own data: `den.storage`, its files, what the player granted |
| `<data>/cores/` | Installed libretro cores and `cores.json`, the record of their checksums |
| `<data>/engines/` | Installed engine apps (desktop) |
| `<data>/bios/` | The BIOS folder: BIOS files and system files, where cores look for them |
| `<data>/settings.json` | EmuDEN's settings, console settings of plugins included (`console.<system>.<key>`) |
| `<data>/log.txt` | The log; plugin warnings start with `plugins:` |

## Menus

| Name in these pages | Where it is |
|---|---|
| Settings > Plugins | The plugin sources (Add a source, Check now, one row per source), Install a console from a file, and Developer mode with Open developer folder and Reload developer plugins |
| Settings > Consoles | Every console, and Install a console from a file; a console's page installs, updates or removes its core (or, for an engine console, its engine program), picks the core and shows its settings |
| Install a console from a file | Picks an `.emuplugin` or a folder's `plugin.json`, shows what it is and whether EmuDEN signed it, installs it, and asks for the engine program when it needs one |
| Settings > Interface | The Home interface, EmuDEN's own or an interface plugin |
| Settings > System | Version, data folder |
| Plugins (on the rail) | Feature and interface plugins: installed, then offered; a plugin's page installs, opens, updates or removes it |
| Pause menu | The menu over a game while it plays |

## Words

| Word | Meaning |
|---|---|
| Source | A signed plugin list: EmuDEN's own (official) or one the player added |
| Namespace | The start of every plugin id a source may publish: its GitHub owner (`jdoe.`) or host |
| Official | EmuDEN's own plugins: `emuden.*` from the official source, compiled into the app, or a file signed with EmuDEN's key |
| Manual plugin | One in no list, installed from a file: `manual/<id>/`, packed and signed as `manual/<id>.emuplugin` (Switch 2) |
| Core | Anything that plays a console: a libretro core or an engine app |
| Engine app | A standalone emulator that speaks the Emulator Control Protocol |
| Capability | A name in `needs`: a host feature the plugin uses ([compatibility.md](compatibility.md)) |
| Permission | What a feature plugin's script may reach ([lua-api.md](lua-api.md)) |
