# EmuDEN plugins

A console in EmuDEN is a plugin: a `plugin.json` that says which files are its games, how they are
shown, which core plays them and which settings the console has. A console plugin holds no code:
it names libretro cores or engine apps (emulators that speak the Emulator Control Protocol) that
EmuDEN downloads, checks and runs. Feature plugins add pages written in sandboxed Lua, and
interface plugins give the Home screen another look.

This folder is a complete plugin source. EmuDEN ships with a copy of it built in, so every console
below works before any source is added.

| Path | What it is |
|---|---|
| `index.json` | The list of plugins; the only file the app polls |
| `index.json.sig`, `keys/source.pub` | The list's signature and the public key it is made with. Not in this folder yet: whoever publishes it makes them (below) |
| `addons.json` | The add-on catalogue; `index` rewrites its entries |
| `addons/<program id>/<id>/` | One folder per Switch 2 add-on |
| `plugins/<id>/plugin.json` | One folder per plugin |
| `manual/<id>/plugin.json`, `manual/<id>.emuplugin` | Console plugins in no list, installed by hand from the signed package (Switch 2: [docs/engines.md](docs/engines.md#switch-2-installed-by-hand)) |
| `shared/<name>/` | Lua shared by several feature plugins, copied into their packages (`docs/feature-plugins.md`) |
| `packages/` | The packed plugins and add-ons the lists point at |
| `schema/` | JSON Schemas for the manifest, the list and the add-on files, and `capabilities.json` |
| `tools/plugin_tool.py` | `validate`, `test`, `pack`, `assemble`, `index`, `sign`, `verify`, `keygen`, `pin-cores` |
| `examples/` | Templates of each plugin kind |
| `tests/` | Offline Lua tests (`tests/<id>/`), the shared mock `den_mock.lua`, and `tool_test.py` |
| `docs/` | The developer guide; [glossary.md](docs/glossary.md) names the paths and menus |

Start with [docs/getting-started.md](docs/getting-started.md); the Lua API is
[docs/lua-api.md](docs/lua-api.md). To publish your own plugins read
[docs/publishing.md](docs/publishing.md); what EmuDEN checks and refuses is in
[docs/security.md](docs/security.md).

## Publishing this folder as the EmuDEN source

The copy built into the app needs no signature. A copy on GitHub does, and it is only the
official source for builds that carry its public key. Nobody but the owner should hold that
key, so none is shipped here.

1. Create the repository (for example `Denarmo/emuden-plugins`) and copy this whole folder into
   its root.
2. Make the key, once, on a machine you trust, outside the repository:
   `python -I tools/plugin_tool.py keygen --key /somewhere/safe/emuden-source.key`.
   It writes `keys/source.pub`. Make a second key the same way into another folder and keep it
   apart: it is the spare for the day the first is lost.
3. `python -I tools/plugin_tool.py validate --all --trust bundled`
4. `python -I tools/plugin_tool.py index --trust official --sequence <higher than last time> --days 120`
5. `python -I tools/plugin_tool.py sign --key /somewhere/safe/emuden-source.key`, then `verify`.
   `sign` also signs the packages in `manual/`.
6. Commit and push `index.json`, `index.json.sig`, `keys/source.pub`, `packages/` and the rest.
7. Build EmuDEN with the source and the keys (the content of `keys/source.pub`, and of the
   spare's, separated by a comma):
   `-DEMUDEN_PLUGIN_SOURCE=github:Denarmo/emuden-plugins@main -DEMUDEN_PLUGIN_PUBKEYS=<key>,<spare key>`.
   A build with the keys but no source accepts the repository as official when its address is
   typed under Settings > Plugins > Add a source. A build without the keys offers it as any
   other source, and refuses it because `emuden.*` plugins are EmuDEN's.

The list must be signed again before it expires (`--days`, 120 at most), with a higher
`--sequence` each time.

Files here are signed and hashed byte for byte. `.gitattributes` turns line-ending conversion off;
keep it.
