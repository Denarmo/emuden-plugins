# Example plugins

Templates for each kind of plugin, as a third party (`jdoe`) would publish them. They are not in
`index.json` and EmuDEN does not install them by itself. `python -I tools/plugin_tool.py validate
examples/*` checks them all; `tests/tool_test.py` keeps them valid.

| Folder | Kind | What it shows |
|---|---|---|
| `jdoe.wiiu-cemu` | console | A console whose core is an engine app (an ECP build of Cemu, Windows and Linux), with a setting applied as an engine setting |
| `jdoe.xbox360-xenia` | console | The same with one desktop platform and a single-file download |
| `jdoe.hello-feature` | feature | A page, a counter kept in `den.storage`, one HTTP request; offline test in `tests/jdoe.hello-feature/` |
| `jdoe.sync.webdav` | feature | A sync provider for a server the player enters (GET, PUT and DELETE only); offline test in `tests/jdoe.sync.webdav/` |
| `jdoe.neon-shelf` | interface | Colours and motion for the `carousel` Home layout |

Before publishing one:

1. Change the id, `publisher` and every engine app's `ecp.id` to your own namespace.
2. For a console: point the downloads at real files and replace each `sha256` (all zeros here) and
   `size` (1 here) with the file's. EmuDEN refuses a download that does not match, so the
   examples as they are install nothing. The engine app must really speak the Emulator Control
   Protocol ([docs/engines.md](../docs/engines.md)).
3. `python -I tools/plugin_tool.py test examples/<id>` for a feature plugin.

To try one first, copy its folder into the developer folder (see
[getting-started.md](../docs/getting-started.md)).
