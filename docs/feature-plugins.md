# Feature plugins

A plugin of kind `feature` adds a page to the Plugins section of EmuDEN. It is a package of
Lua 5.4 scripts that the app runs in a sandbox: no `os`, `io`, `require` or native code, only
the `den.*` calls its permissions allow. Every call, with its permission and capability, is in
[lua-api.md](lua-api.md); the design notes are `docs/feature-plugins.md` in the EmuDEN
repository. Start from `examples/jdoe.hello-feature` (a page) or `examples/jdoe.sync.webdav`
(a sync provider).

## Manifest

The common fields are those of every plugin. `needs` must list `kind.feature` and
`feature.lua.1`, and each permission's capability ([compatibility.md](compatibility.md)):
`feature.web.1` with `browse`, `feature.tune.1` with `device.info`, `game.settings` or `steam`,
`feature.achievements.1` with `achievements`, `feature.browser.1` with `browse.any` or
`downloads.setup`, `feature.mods.1` with `game.files`. EmuDEN refuses a permission whose capability is missing, and an EmuDEN
without feature plugins refuses the plugin and keeps the rest of the list. A feature plugin has no `engine`, `systems`, `components` or `settings`.

| `feature` field | Meaning |
|---|---|
| `entry` | The script to run, a relative path ending in `.lua` |
| `icon` | A square PNG of the package |
| `permissions` | `http`, `download`, `open-url`, `browse`, `files.import`, `downloads.watch`, `library.read`, `patch`, `library.write`, `sync`, `http.local` (`http://127.0.0.1:<port>`, `localhost`), `http.user_host` (one server the user enters), `device.info`, `game.settings` (with `systems`), `steam`, `achievements` (`den.achievements`: RetroAchievements sign-in and progress; EmuDEN's own plugins only, since the runtime signs in with `emuden.retroachievements` alone), `browse.any` and `downloads.setup` (with `feature.browser.1`: the browser for any site and the setup of its downloads; EmuDEN's own plugins only), `game.files` (with `feature.mods.1`: `den.mods`, files of a Steam game's folder and Vulkan layers, set up by the app after the user agreed; EmuDEN's own plugins only) |
| `http.hosts` | Exact https hosts, with `http` or `download`; at most 8 |
| `open_hosts` | Hosts `den.open_url` may show, with `open-url` |
| `browse_hosts` | Sites `den.web.open` may show in the app's browser page, with `browse`: exact names, at most 8 |
| `file_types` | Extensions the plugin takes from the picker and the Downloads folder |
| `systems` | Console ids the plugin may see; `["*"]` only for EmuDEN's own plugins |
| `sync` | With `sync`: `{"categories": [...], "listing": "category"}`. `categories` of `saves`, `states`, `config`, `games`, `bios`; `listing` how `list(prefix)` behaves: `category` (default; one listing per category), `all` (any listing returns everything, so a run lists once with prefix `""`), `per_folder` (as `all`, and a system folder such as `saves/gba/` is listed quickly, so syncing one game lists only its folders). The plugin is a sync provider ([lua-api.md](lua-api.md#5-sync-providers)) |
| `limits` | `memory_mb` (8 to 64), `storage_mb` (up to 4096) |

Only EmuDEN's own plugins (`emuden.*` from the official source) may use `downloads.watch`,
`browse.any`, `downloads.setup`, `achievements`, `game.files` or `systems: ["*"]`; an added source's plugins
and the developer folder's are refused with them.

## Package

Only `.json`, `.lua`, `.png`, `.jpg`, `.txt` and `.md` files, at most 200 files and 8 MiB.
Scripts are text; compiled Lua is refused.

## Shared libraries

Lua used by several plugins is kept once, in `shared/<name>/`. A plugin folder that holds a
file `.shared` (one library name a line) gets that library's files copied into its package by
`plugin_tool.py` (`pack`, `index`); a file of the plugin's own folder with the same name wins.
`plugin_tool.py assemble plugins/<id> -o <folder>` writes the same files to a folder, for
EmuDEN's developer folder (`<data>/plugins-dev/<id>`, Settings > Plugins > Developer mode).

## Tests

`plugin_tool.py test [folder...]` runs `tests/<id>/*test.lua` with a Lua 5.4 interpreter (`--lua`,
`$LUA`, or `lua5.4`/`lua54`/`lua` on the path), from the repository root. `tests/den_mock.lua` is
a shared offline `den`: it loads the plugin as the app does, grants only its permissions, and
fakes storage, secrets, HTTP, the UI and the other namespaces ([lua-api.md](lua-api.md#7-testing-offline)).

## Index

`plugin_tool.py index` writes a feature plugin's entry with `permissions`, `http_hosts`,
`open_hosts`, `browse_hosts` and `feature_systems`, so EmuDEN shows what the plugin asks for
before any download. The entry's `systems` stays an empty list of console objects for older
readers, which refuse the entry by its `needs` and keep the rest of the list.

## RetroAchievements

`emuden.retroachievements` is the switch, sign-in, settings and pages of RetroAchievements;
EmuDEN's player runs the achievements (rcheevos) while a game plays. It uses
`den.achievements` (EmuDEN's `docs/feature-plugins.md` section 4.3): `status()`,
`sign_in{user, password}` (the token that comes back goes to the plugin's `den.secrets`, the
password is not kept), `sign_out()`, `set{hardcore, sound, screenshot}` and `game(id)`. Sign-in,
sign-out and settings work only inside `plugin.actions.*`. The runtime only signs in while the
plugin is installed; removing it with its data deletes the token.

## Tuning plugins

`emuden.tune.protondb` and `emuden.tune.emuready` set games up from community reports of
machines like this one. They use `den.device.info`, `den.game` (a game's own core options)
and `den.steam` (launch options and Proton version), EmuDEN's `docs/feature-plugins.md`
section 4.2. A change is made only after the user pressed Apply and accepted EmuDEN's own
question listing every change; both plugins keep the old values for Undo.

| Plugin | Data | Applies to |
|---|---|---|
| `emuden.tune.protondb` | [Denarmo/protondb-reports](https://github.com/Denarmo/protondb-reports) (ProtonDB's ODbL dump, one file a game) and ProtonDB's public summary | Steam games: Proton and launch options on SteamOS; shown only on Windows |
| `emuden.tune.emuready` | EmuReady's public mobile API (100 requests in 3 minutes, cached) | Library games: resolution, renderer, frame skip and similar core options, for that game |

`emuden.tune.helixsr` and `emuden.tune.lsfg` set a mod up for a Steam game with `den.mods`
(EmuDEN's `docs/game-mods-api.md`). Neither mod may be bundled, so each is downloaded from its
official release, pinned by SHA-256 in the plugin's `release.lua`.

| Plugin | Mod | Does |
|---|---|---|
| `emuden.tune.helixsr` | [Helix SR](https://github.com/lonewolf0622/HelixSR) 3.4.0 (closed freeware) | Replaces a game's FSR 3.1 library with HLX FSR 4; games with anti-cheat files are refused; Windows and Linux |
| `emuden.tune.lsfg` | [lsfg-vk](https://lsfg-vk.dev) 2.0.0 (CC BY-NC-ND 4.0) | Installs the Vulkan layer and sets `LSFGVK_...` in a game's launch options; needs Lossless Scaling from Steam; Linux (on Windows a page that says so) |
