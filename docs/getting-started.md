# Getting started

This walk-through adds a console that runs in a standalone emulator. A console that uses a libretro
core is the same with fewer fields; see `plugins/emuden.nes/plugin.json`.

## 1. Write the manifest

Make a folder named after your plugin id and put a `plugin.json` in it. The id is
`<your GitHub name>.<something>`, lower case.

```json
{
  "manifest_version": 1,
  "id": "jdoe.wiiu-cemu",
  "name": "Wii U (Cemu)",
  "version": "1.0.0",
  "kind": "console",
  "engine": "external",
  "publisher": "jdoe",
  "license": "MIT",
  "api": 1,
  "needs": ["engine.external", "settings.v1"],
  "platforms": ["windows-x86_64", "linux-x86_64"],
  "systems": [{
    "id": "wiiu", "name": "Wii U", "group": "nintendo", "order": 1150,
    "content": { "extensions": ["wua", "wud", "wux"], "folder_aliases": ["wii u"], "zip": "no" },
    "presentation": { "cover_aspect": 0.71 },
    "emulator": "cemu"
  }],
  "components": [{
    "id": "cemu", "type": "external-emulator", "name": "Cemu", "version": "2.6",
    "downloads": {
      "windows-x86_64": {
        "url": "https://github.com/cemu-project/Cemu/releases/download/v2.6/cemu-2.6-windows-x64.zip",
        "sha256": "<64 hex digits of that file>", "size": 12345678,
        "archive": "zip", "strip_components": 1 }
    },
    "launch": {
      "executable": { "windows-x86_64": "Cemu.exe" },
      "args": ["-g", "{rom}"]
    }
  }]
}
```

`sha256` and `size` are those of the exact file at `url`. EmuDEN stops a download that is larger and
refuses one whose checksum differs.

## 2. Check it

```
python -I tools/plugin_tool.py validate path/to/jdoe.wiiu-cemu
```

Every problem is printed with the place in the file and the reason. The app runs the same checks.

## 3. Try it in EmuDEN

1. Turn on developer mode: Settings, System, Developer mode.
2. Copy the folder to `<EdenDir>/emuden/plugins/dev/` (Settings, System, Plugin sources,
   Developer, Open developer folder).
3. Choose Reload developer plugins there. The console is listed under Settings, Consoles, marked
   "Developer, unsigned". Install its emulator from its page and put a game in a folder named
   like the console (`wiiu/`) inside one of your game folders.

`examples/` holds two manifests to start from, for Cemu and for Xenia Canary.

In the developer folder a download may say `"file": "C:/Downloads/cemu.zip"` in place of `url`, so
nothing has to be hosted while you work.

## 4. Publish it

See [publishing.md](publishing.md).
