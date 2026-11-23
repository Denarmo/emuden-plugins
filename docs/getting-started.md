# Getting started

EmuDEN has three kinds of plugin you can publish:

| Kind | What it is | Start from |
|---|---|---|
| `console` | Data: which files are a console's games, how they look, which core plays them | `examples/jdoe.wiiu-cemu` (an engine app), `plugins/emuden.nes` (libretro cores) |
| `feature` | A Lua script with a page of its own, run in a sandbox ([feature-plugins.md](feature-plugins.md), [lua-api.md](lua-api.md)) | `examples/jdoe.hello-feature`, `examples/jdoe.sync.webdav` (a sync provider) |
| `interface` | Data: looks for the Home screen ([interface-plugins.md](interface-plugins.md)), layouts of the second screen's quick settings ([quick-settings.md](quick-settings.md)) and/or themes for the whole app ([themes.md](themes.md)) | `examples/jdoe.neon-shelf`, `plugins/emuden.home-layouts`, `plugins/emuden.quick-layouts`, `plugins/emuden.themes` |

Paths and menu names used below are listed in [glossary.md](glossary.md).

## A console

A console plays its games with one of its cores, best first:

- a **libretro core** (`libretro-core`), loaded into EmuDEN's player; or
- an **engine app** (`engine-app`), a standalone emulator that speaks the Emulator Control
  Protocol (ECP): EmuDEN downloads it (desktop) or installs its APK (Android), starts it with the
  game and drives it (pause menu, save states, fast-forward) over the protocol
  ([engines.md](engines.md)).

Both use `"engine": "libretro"`; the core's `type` decides how it runs. There is no other way
to run a program: an emulator that does not speak ECP cannot be a core.

### 1. Write the manifest

Make a folder named after your plugin id and put a `plugin.json` in it. The id is
`<your GitHub name>.<something>`, lower case. `examples/jdoe.wiiu-cemu/plugin.json` is a complete
console with an engine app:

```json
{
  "manifest_version": 1,
  "id": "jdoe.wiiu-cemu",
  "name": "Wii U (Cemu ECP)",
  "version": "1.0.0",
  "kind": "console",
  "engine": "libretro",
  "publisher": "jdoe",
  "license": "MIT",
  "api": 1,
  "needs": ["engine.libretro", "core.engine-app.1"],
  "platforms": ["windows-x86_64", "linux-x86_64"],
  "systems": [{
    "id": "wiiu", "name": "Wii U", "group": "nintendo", "order": 1150,
    "content": { "extensions": ["wua", "wud", "wux"], "folder_aliases": ["wii u"], "zip": "no" },
    "presentation": { "cover_aspect": 0.71 },
    "cores": ["cemu"]
  }],
  "components": [{
    "id": "cemu", "type": "engine-app", "name": "Cemu (ECP)", "version": "2.6-ecp1",
    "ecp": { "id": "io.github.jdoe.cemu", "level": 2, "capabilities": ["pause", "menu", "states"] },
    "executable": { "windows-x86_64": "Cemu/Cemu.exe" },
    "downloads": {
      "windows-x86_64": {
        "url": "https://github.com/jdoe/cemu-ecp/releases/download/v2.6-ecp1/cemu-ecp-2.6-windows-x64.zip",
        "sha256": "<64 hex digits of that file>", "size": 12345678,
        "archive": "zip", "entry": "Cemu/" }
    }
  }]
}
```

`sha256` and `size` are those of the exact file at `url`. EmuDEN stops a download that is larger
and refuses one whose checksum differs. The engine app's `ecp.id` (and its Android `package`)
must be in your namespace: `jdoe.`, `io.github.jdoe.`, or your host reversed for an https source
([engines.md](engines.md#the-namespace-rule)).

### 2. Check it

```
python -I tools/plugin_tool.py validate path/to/jdoe.wiiu-cemu
```

Every problem is printed with the place in the file and the reason; the app runs the same checks.
A `warning: not read by EmuDEN yet` line names fields the schema allows but this EmuDEN ignores
([manifest.md](manifest.md#fields-not-read-yet)).

### 3. Try it in EmuDEN

1. Turn on **Settings > Plugins > Developer mode**.
2. Choose **Open developer folder** there and copy your plugin folder into it
   (`<data>/plugins-dev/jdoe.wiiu-cemu/plugin.json`).
3. Choose **Reload developer plugins**. The console is listed under Settings > Consoles; its page
   says "Developer folder". Install its core from that page and put a game in a folder named like
   the console (`wiiu/`) inside one of your game folders.

In the developer folder a download may name a file on your device in place of `url`, so nothing
has to be hosted while you work. `sha256` and `size` are then optional:

```json
"windows-x86_64": { "file": "C:/build/cemu-ecp.zip", "archive": "zip", "entry": "Cemu/" }
```

A plugin of the developer folder is not signed and replaces an installed plugin of the same id
while developer mode is on. It follows the rules of an added source except the namespace: no
Switch 2 engine, no scanner, no `@` BIOS entries, and none of the official-only permissions.

### Or install it from a file

**Settings > Plugins > Install a console from a file** takes a console plugin without a source or
developer mode: an `.emuplugin` package (`plugin_tool.py pack`), or the `plugin.json` of a plugin
folder. EmuDEN shows its name, version, publisher and consoles first. A file signed with EmuDEN's
key (`plugin.json.sig` beside `plugin.json`) is installed as one of EmuDEN's own; any other is
unsigned, EmuDEN says that nobody checked it, and it keeps the rules above (no `emuden.` id). It
goes to `<data>/plugins-local/<id>/` and stays until the console is removed. (The Switch 2
console is no longer installed this way: it is in the list, [engines.md](engines.md#switch-2-dennx-emudens-own-engine).)

## A feature plugin

`examples/jdoe.hello-feature` is a page with a counter and one web request;
`examples/jdoe.sync.webdav` is a sync provider. Read [feature-plugins.md](feature-plugins.md)
for the manifest and [lua-api.md](lua-api.md) for every `den.*` call.

```
python -I tools/plugin_tool.py validate examples/jdoe.hello-feature
python -I tools/plugin_tool.py test examples/jdoe.hello-feature --lua <a Lua 5.4 program>
python -I tools/plugin_tool.py assemble examples/jdoe.hello-feature -o <data>/plugins-dev/jdoe.hello-feature
```

`test` runs `tests/<id>/*test.lua` offline with the shared mock `tests/den_mock.lua`
([lua-api.md](lua-api.md#7-testing-offline)). `assemble` writes the plugin's files, shared
libraries included, into the developer folder; then choose Reload developer plugins. The plugin
appears under Plugins marked "Developer", and its page has **Reload the script**.

## An interface plugin

Copy `examples/jdoe.neon-shelf` into the developer folder the same way and pick it under
Settings > Interface. An interface whose `layout` this EmuDEN does not have installs, but picking
it says so and the standard Home stays. Quick settings layouts (`quick_settings`) are picked on
the same page, under "Quick settings layout" ([quick-settings.md](quick-settings.md)); themes
under Settings > Display ([themes.md](themes.md)).

## Publish it

See [publishing.md](publishing.md).
