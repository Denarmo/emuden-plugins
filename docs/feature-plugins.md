# Feature plugins

A plugin of kind `feature` adds a page to the Plugins section of EmuDEN. It is a package of
Lua 5.4 scripts that the app runs in a sandbox: no `os`, `io`, `require` or native code, only
the `den.*` calls its permissions allow. The full contract (host API, UI model, lifecycle,
trust rules) is `docs/feature-plugins.md` in the EmuDEN repository.

## Manifest

The common fields are those of every plugin. `needs` must list `kind.feature` and
`feature.lua.1`, so an EmuDEN without feature plugins refuses the plugin and keeps the rest of
the list. A feature plugin has no `engine`, `systems`, `components` or `settings`.

| `feature` field | Meaning |
|---|---|
| `entry` | The script to run, a relative path ending in `.lua` |
| `icon` | A square PNG of the package |
| `permissions` | `http`, `download`, `open-url`, `files.import`, `downloads.watch`, `library.read`, `patch`, `library.write` |
| `http.hosts` | Exact https hosts, with `http` or `download`; at most 8 |
| `open_hosts` | Hosts `den.open_url` may show, with `open-url` |
| `file_types` | Extensions the plugin takes from the picker and the Downloads folder |
| `systems` | Console ids the plugin may see; `["*"]` only for EmuDEN's own plugins |
| `limits` | `memory_mb` (8 to 64), `storage_mb` (up to 4096) |

A third-party plugin may not use `downloads.watch` or `["*"]`.

## Package

Only `.json`, `.lua`, `.png`, `.jpg`, `.txt` and `.md` files, at most 200 files and 8 MiB.
Scripts are text; compiled Lua is refused.

## Index

`plugin_tool.py index` writes a feature plugin's entry with `permissions`, `http_hosts`,
`open_hosts` and `feature_systems`, so EmuDEN shows what the plugin asks for before any
download. The entry's `systems` stays an empty list of console objects for older readers.

## ROM Hacks (`emuden.romhacks`)

Installs ROM hack patches (`.bps`, `.xdelta`, `.ups`, `.ips`) on the player's own games. It
makes no network request: Hackdex's terms do not allow automated access, so the player
downloads the patch in their browser and the plugin picks it up from the Downloads folder. It
never downloads a game. `bases.json` comes from the Hackdex website's source under the MIT
licence (`NOTICE.txt`).
