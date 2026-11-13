# Feature plugins

A plugin of kind `feature` adds a page to the Plugins section of EmuDEN. It is a package of
Lua 5.4 scripts that the app runs in a sandbox: no `os`, `io`, `require` or native code, only
the `den.*` calls its permissions allow. The full contract (host API, UI model, lifecycle,
trust rules) is `docs/feature-plugins.md` in the EmuDEN repository.

## Manifest

The common fields are those of every plugin. `needs` must list `kind.feature` and
`feature.lua.1` (and `feature.web.1` with the `browse` permission), so an EmuDEN without feature plugins refuses the plugin and keeps the rest of
the list. A feature plugin has no `engine`, `systems`, `components` or `settings`.

| `feature` field | Meaning |
|---|---|
| `entry` | The script to run, a relative path ending in `.lua` |
| `icon` | A square PNG of the package |
| `permissions` | `http`, `download`, `open-url`, `browse`, `files.import`, `downloads.watch`, `library.read`, `patch`, `library.write` |
| `http.hosts` | Exact https hosts, with `http` or `download`; at most 8 |
| `open_hosts` | Hosts `den.open_url` may show, with `open-url` |
| `browse_hosts` | Sites `den.web.open` may show in the app's browser page, with `browse`: exact names, at most 8 |
| `file_types` | Extensions the plugin takes from the picker and the Downloads folder |
| `systems` | Console ids the plugin may see; `["*"]` only for EmuDEN's own plugins |
| `limits` | `memory_mb` (8 to 64), `storage_mb` (up to 4096) |

A third-party plugin may not use `downloads.watch` or `["*"]`.

## Package

Only `.json`, `.lua`, `.png`, `.jpg`, `.txt` and `.md` files, at most 200 files and 8 MiB.
Scripts are text; compiled Lua is refused.

## Shared libraries

Lua used by several plugins is kept once, in `shared/<name>/`. A plugin folder that holds a
file `.shared` (one library name a line) gets that library's files copied into its package by
`plugin_tool.py` (`pack`, `index`); a file of the plugin's own folder with the same name wins.
`plugin_tool.py assemble plugins/<id> -o <folder>` writes the same files to a folder, for
EmuDEN's developer folder (`<data>/plugins-dev/<id>`).

## Index

`plugin_tool.py index` writes a feature plugin's entry with `permissions`, `http_hosts`,
`open_hosts`, `browse_hosts` and `feature_systems`, so EmuDEN shows what the plugin asks for
before any download. The entry's `systems` stays an empty list of console objects for older
readers, which refuse the entry by its `needs` and keep the rest of the list.

## ROM Hacks, one plugin per site

| Plugin | Site | Start page |
|---|---|---|
| `emuden.romhacks` ("ROM Hacks: hackdex.app") | hackdex.app | `https://www.hackdex.app/discover` |
| `emuden.romhacks-whackahack` | whackahack.com | `https://whackahack.com/foro/` |
| `emuden.romhacks-pokeharbor` | pokeharbor.com | `https://www.pokeharbor.com/` |
| `emuden.romhacks-romhacking` | romhacking.net | `https://www.romhacking.net/` |

All four are `shared/romhacks/` (`main.lua`, `pages.lua`) plus a `site.lua` and a README that
records what was found about the site. The player browses the real site in EmuDEN's browser
page and presses its download button; the plugin is handed the patch file, finds the base
game in the library (by the patch's checksum, or the player chooses), patches a copy and adds
the hack to the library. The plugins have no `http` permission: they never read, search or
fetch a site, and they take patch files only (`bps ips ups xdelta vcdiff aps ppf`, or a `zip`
holding one; `7z` and `rar` cannot be opened by the app yet). A ROM image is always refused,
also inside a zip and also when it is pre-patched. A link that leaves the site's hosts (a file
host, for instance) is opened only after the app asked the player. None of the plugins is
affiliated with its site; "Hackdex" is a name its project reserves, so that plugin is named by
the domain. `bases.json` of `emuden.romhacks` comes from the Hackdex website's source under the
MIT licence (`NOTICE.txt`).
