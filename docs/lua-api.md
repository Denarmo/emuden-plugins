# The `den` Lua API (api 1)

Reference of what a feature plugin's script can call. A feature plugin (kind `feature`, see
[feature-plugins.md](feature-plugins.md) for the manifest) is a package of Lua 5.4 scripts. The
app runs them in a sandbox on a worker thread of their own and they reach the app only through
the global table `den`. This page is written from the app's code; where the code and this page
differ, the code wins and this page is to be fixed.

## 1. The sandbox

| | |
|---|---|
| Libraries | base, `string`, `table`, `math`, `utf8`, `coroutine` |
| Not there | `os`, `io`, `package`, `debug`, `require`, `dofile`, `loadfile`, `string.dump` |
| Changed | `load(text, name?, mode?, env?)` compiles text only, never bytecode, whatever `mode` says. `collectgarbage()` runs a full collection and `collectgarbage("count")` gives the KiB in use; any other argument is an error. `print` is `den.log` (its first argument only) |
| Other files of the package | `den.include("name.lua")` (section 3, `den`); there is no `require` |
| Memory | The Lua state stops at `limits.memory_mb` (8 to 64, default 32); past it Lua raises "not enough memory" |
| Time | A callback is stopped after about 200 million VM instructions with "the plugin ran too long without a pause and was stopped". Time spent waiting in a `den` call does not count; the budget is per callback |
| Script size | The entry script and each included script at most 1 MiB |

## 2. How the script runs

The entry script (`feature.entry`) runs once when the plugin starts and **returns a table of
entry points**. It may not wait while it loads ("The script may not wait while it loads; do
that in plugin.open."). The app looks entry points up by name, without running script code,
and calls each one in a fresh coroutine:

| Entry point | Called when | Arguments |
|---|---|---|
| `plugin.open(args)` | The user opens the plugin and it shows no page yet, or before `plugin.file` | `args`: an empty table |
| `plugin.resume()` | The user comes back to a plugin that still shows its pages | - |
| `plugin.close()` | 60 s after the plugin's page left the screen (not on a developer "Reload") | - |
| `plugin.file(path)` | A file of `file_types` was opened with EmuDEN (needs `files.import`) | `"inbox/<name>"`, a copy in the plugin's folder |
| `plugin.actions.<name>(arg, value)` | The user pressed an element whose `action` is `<name>` (section 6) | `arg`: the element's `arg` (nil when it has none); `value`: the text of an input or search, the selected chip ids joined with `,`, else `""` |
| `plugin.provider.<fn>(...)` | The sync engine needs a file (section 5) | see section 5 |

A missing entry point is skipped (a missing action is logged). Calls run one at a time on the
plugin's thread, in the order they were posted.

**Waiting calls.** Calls marked *(wait)* below suspend the calling coroutine until the app has
the answer (a network reply, the user's answer to a question, a file being patched); the script
reads like blocking code and the screen never waits. Other entry points may run while one
waits. A waiting call must be made from the entry point's own coroutine: from a coroutine the
script created itself it raises "a den call that waits must be made from the plugin's own
function, not from a coroutine of the script". A coroutine that yields outside a `den` call
fails with "The script paused outside a den call."

**User calls.** Some calls work only inside `plugin.actions.*`, after something the user
pressed: `den.open_url`, `den.game.set`, `den.steam.set` and the changing calls of
`den.achievements`. Elsewhere they return `nil, message`.

**Errors.** A `den` call that is refused returns `nil, message`, and so does a call without
its permission ("the plugin has no permission to ..."): check the first result. Wrong argument
types, a failed `den.include` and a waiting call from the wrong coroutine raise a Lua error.
An entry point that raises (or the app stopping it) fails: the page shows the message with
"Close" and "Try again", and three failures in a row stop the plugin until it is opened again.

**Values.** What crosses between the script and the app is JSON-like: tables, strings, numbers,
booleans and `den.json.null`. A table with a first element (or none at all) is an array, others
are objects with text keys. Functions and other values cannot cross (an error).

**Paths.** File paths are relative to the plugin's data folder `<data>/plugin-data/<id>/`;
`package/<path>` names a file of the installed package (read only). `..`, absolute paths and
links that lead out of the folder are refused. A path `sync:<token>` is a file the sync engine
lent for the current provider call only.

## 3. Namespaces

"Permission" is the `feature.permissions` entry the call needs ("-": none). "Needs" is the
capability that permission requires in the manifest's `needs` (every feature plugin lists
`kind.feature` and `feature.lua.1`). *(wait)* marks waiting calls, *(user)* calls that work
only in `plugin.actions.*`.

### `den`

| Function | Arguments | Returns | Permission | Needs |
|---|---|---|---|---|
| `den.api` | - | `1` | - | - |
| `den.plugin.id`, `den.plugin.version` | - | the manifest's id and version | - | - |
| `den.device.platform` | - | the app's platform name | - | - |
| `den.log(text)` | any value (shown with `tostring`) | - ; to the app log, the last 200 lines shown for developer plugins, cut at 4000 bytes | - | - |
| `den.now()` | - | Unix seconds | - | - |
| `den.sleep(ms)` *(wait)* | 0 to 600000 | - | - | - |
| `den.include(name)` | a `.lua` file of the package (`"lib/util.lua"`) | the value the script returns. It runs anew on every call (no cache), in the same environment, and may wait | - | - |
| `den.download{url, name, sha256?, on_progress?}` *(wait)* | https URL of `http.hosts`; a plain file name; a hex SHA-256 to check; `on_progress(fraction)` | `"downloads/<name>"`; at most 256 MiB and the folder's quota | `download` | - |
| `den.open_url(url)` *(user)* | https URL of `open_hosts` | `true`; the user's browser opens it | `open-url` | - |

### `den.json`

| Function | Arguments | Returns | Permission | Needs |
|---|---|---|---|---|
| `den.json.encode(value)` | a JSON-like value | compact JSON text. An empty table is `[]`; whole numbers have no fraction; nesting at most 32 levels and 200000 parts | - | - |
| `den.json.decode(text)` | JSON text | the value, or `nil, "the text is not JSON"`. Arrays are tables 1..n, `null` is `den.json.null` (inside objects too), whole numbers below 9e15 are integers. `{}` decodes to an empty table, which encodes back as `[]`: give an object at least one key | - | - |
| `den.json.null` | - | the value JSON `null` stands for | - | - |

### `den.storage` and `den.secrets`

| Function | Arguments | Returns | Permission | Needs |
|---|---|---|---|---|
| `den.storage.get(key)` | text | the stored value, or nil | - | - |
| `den.storage.set(key, value)` | key of 1 to 200 bytes; a JSON-like value | `true`, or `nil, message` when all values together pass 1 MiB. Written to `storage.json` at once (atomically) | - | - |
| `den.storage.remove(key)` | text | whether there was such a key | - | - |
| `den.storage.keys()` | - | the keys, in the order they were first set | - | - |
| `den.secrets.get(name)` | up to 64 letters, digits, `.`, `_`, `-` | the value, or nil | - | - |
| `den.secrets.set(name, value)` | as above; a value of at most 2 KiB as JSON | `true`, or `nil, message`; at most 32 names per plugin | - | - |
| `den.secrets.remove(name)` | as above | `true` | - | - |

Secrets live in the platform's credential store (Windows Credential Manager, an
Android-Keystore-encrypted file, a 0600 file on Linux), are never synced and go when the plugin
is removed with its data. Use them for tokens and passwords, never `den.storage`.

### `den.ui` and `den.app`

| Function | Arguments | Returns | Permission | Needs |
|---|---|---|---|---|
| `den.ui.set(page)` | a page (section 6) | - ; replaces the top page (or shows the first) | - | - |
| `den.ui.push(page)` | a page | `true`, or `nil, message` at 8 pages | - | - |
| `den.ui.pop()` | - | - ; back to the page below; from the first page, out of the plugin | - | - |
| `den.ui.depth()` | - | how many pages are shown (the user's Back takes one away without telling the script) | - | - |
| `den.ui.patch(id, fields)` | an element id; the fields to change | whether an element with that id was found (top page first) | - | - |
| `den.ui.toast(text)` | any value | - | - | - |
| `den.ui.confirm{title, message, yes}` *(wait)* | texts; `yes` is the button's label | `true` or `false` | - | - |
| `den.app.open_game(id)` | a library id | - ; opens the game's page | - | - |

### `den.http`

| Function | Arguments | Returns | Permission | Needs |
|---|---|---|---|---|
| `den.http.get{url, headers?, cache_seconds?}` *(wait)* | https URL of `http.hosts`; at most 16 headers; cache time 0 to 30 days, default 3600 | `{status, body, headers = {}, cached}`; body at most 8 MiB | `http` | - |
| `den.http.request{...}` *(wait)* | the table below | `{status, body, headers}` for any answer, 4xx and 5xx included; `nil, message` only without an answer | `http`, `http.user_host` or `http.local` | - |

`den.http.request` fields:

| Field | Meaning |
|---|---|
| `url` | required; where it may go is below |
| `method` | `GET` (default), `POST`, `PUT`, `PATCH`, `DELETE`, `HEAD`; any letter case. These are all: other methods (WebDAV's `PROPFIND`, `MKCOL`, ...) are refused, as Android's HTTP client cannot send them |
| `headers` | name = value, at most 32. `Authorization` may be set; `User-Agent`, `Cookie`, `Referer`, `Host`, `Content-Length` are the app's |
| `body` | text (binary is fine), at most 8 MiB |
| `body_file`, `body_offset`, `body_length` | upload a file of the plugin's folder or a lent `sync:` file, or `body_length` bytes from `body_offset` (absent or 0: to the end) |
| `multipart` | at most 16 parts `{name, value}` or `{name, file, filename?, content_type?}`, each with optional `headers`; `body`/`body_file` are taken for `value`/`file`. The app builds the body and sets `Content-Type` |
| `multipart_type` | `form-data` (default), `related` or `mixed` |
| `to_file` | a 2xx answer's body goes to this file instead of `body` (in the plugin's folder it counts against `storage_mb`, a lent file has no limit) |
| `on_progress` | `function(fraction)`, 0..1, negative when the size is unknown |

Give one of `body`, `body_file` and `multipart`. Answer header names are lower case; a header
sent several times is one value joined with `", "`. Timeouts: 60 s, 300 s with a file.

Where requests may go:

- `http.hosts` (with `http`): https on port 443, exact names, at most 8. Redirects are followed
  only inside these hosts, at most two requests are in flight per plugin, there is a pause
  between requests to one host (`http.min_interval_ms`, default and minimum 500, 100 for a
  plugin with `sync`), and after a 429 the host is blocked for 15 minutes.
- `http.user_host`: the one server the user confirmed with `den.sync.set_server(url)`, http or
  https, any path of that scheme, host and port.
- `http.local`: `http://` and `https://` to `127.0.0.1:<port>` and `localhost:<port>` (the port
  is required); any certificate is accepted there.
- The user's server and this device get no pause and their redirects come back as they are
  (`headers.location`). Every request carries `User-Agent: EmuDEN/<app> (plugin <id>/<version>)`,
  no cookies and no referer.

### `den.files`

| Function | Arguments | Returns | Permission | Needs |
|---|---|---|---|---|
| `den.files.list(dir?)` | a folder of the data folder or `package/...`; default the data folder | `{ {name, dir, size} }` | - | - |
| `den.files.exists(path)` | a path | boolean | - | - |
| `den.files.read(path)` | a path, `package/...` or a lent `sync:` file | the content (binary-safe); at most 4 MiB, 8 MiB for a lent file | - | - |
| `den.files.size(path)` | a path or a lent `sync:` file | bytes, of any size | - | - |
| `den.files.remove(path)` | a file under `downloads/`, `inbox/` or `cache/` | boolean | - | - |
| `den.files.import{title?, extensions?}` *(wait)* | the picker's title; extensions (default `file_types`) | `"inbox/<name>"` after the user picked a file, or nil | `files.import` | - |
| `den.files.inbox()` | - | `{ {name, size, modified, token} }`: files of `file_types` in the device's Downloads folder, newest first, 50 at most | `downloads.watch` (official only) | - |
| `den.files.take(token)` | a token of the last `inbox()` | `"inbox/<name>"`, a copy | `downloads.watch` (official only) | - |

There is no call that writes a file directly: files arrive through `den.download`,
`den.http.request{to_file}`, `den.files.import`, `den.files.take` and `den.web.open`.

### `den.library` and `den.patch`

Only games of the manifest's `systems` are seen.

| Function | Arguments | Returns | Permission | Needs |
|---|---|---|---|---|
| `den.library.find{system?, crc32?, sha1?, md5?, size?}` *(wait)* | one hash at least; `crc32` as a number or hex text | `{id, name, system, size, cover, hack_of?}` or nil; hashes candidates once and remembers them | `library.read` | - |
| `den.library.games{system?}` | - | `{ {id, name, system, size, cover, hack_of?} }`; `cover` is `"game:<id>"` | `library.read` | - |
| `den.library.hacks()` | - | the hacks this plugin made: `{ {id, name, base, version, source, installed} }` | - | - |
| `den.library.update(id, {title?, description?, cover?})` | own hack; `cover` a file of the plugin's folder | `true` or `nil, message` | `library.write` | - |
| `den.library.remove(id)` | own hack | `true` or `nil, message`; the patched file is deleted | `library.write` | - |
| `den.patch.inspect(path)` *(wait)* | a patch in the plugin's folder | `{format, source_size?, source_crc32?, target_size?, target_crc32?}` | `patch` | - |
| `den.patch.apply{patch, game, title, version?, description?, cover?, source?, keep_old?}` *(wait)* | the patch file; the base game's id; title up to 200 bytes | `{game, path}`: the new library entry and its file name | `patch` | - |

### `den.web` and `den.downloads`

| Function | Arguments | Returns | Permission | Needs |
|---|---|---|---|---|
| `den.web.available()` | - | `true, "in-app"` or `false, "browser"` (`open` works either way) | - | - |
| `den.web.open{url, hosts?, title?, extensions?}` *(wait)* | https URL; hosts out of `browse_hosts` (default all); patch extensions (default `file_types`, cut to `bps ips ups aps ppf xdelta xdelta3 vcdiff zip 7z`) | the next file the user downloads there: `{path = "inbox/<name>", name, source_host, page_title}`; `nil, "closed"` once the user closed the page. Call it again for the next file | `browse` | `feature.web.1` |
| `den.web.open{any = true, url?, title?}` *(wait)* | https URL, default a search page | `{download, name, source_host, page_title, path}`; every file is kept in EmuDEN's Downloads folder | `browse.any` (official only) | `feature.browser.1` |
| `den.web.close()` | - | - ; takes the page away | - | - |
| `den.web.bookmarks()` | - | `{ {title, url} }` | `browse.any` (official only) | `feature.browser.1` |
| `den.downloads.folder()` | - | the Downloads folder's path | `downloads.setup` (official only) | `feature.browser.1` |
| `den.downloads.files()` | - | `{ {name, size, modified} }`, newest first | `downloads.setup` | `feature.browser.1` |
| `den.downloads.setup{file, page_title?, source_host?, base?}` *(wait)* | a plain name in the Downloads folder | `{id, outcome, message, download, console, time, replaced, undone, games, choices}` | `downloads.setup` | `feature.browser.1` |
| `den.downloads.history()` | - | the setups, newest first | `downloads.setup` | `feature.browser.1` |
| `den.downloads.undo(id)` *(wait)* | a setup id | `true` or `nil, message` | `downloads.setup` | `feature.browser.1` |

The plugin never sees the browser page, its address, cookies or text. A developer plugin may
open `http://127.0.0.1:<port>/...` when `browse_hosts` lists `127.0.0.1`. `den.downloads` is
absent (nil) without `downloads.setup`. `outcome` is one of `added`, `hack_added`,
`needs_base`, `missing_base`, `waiting`, `bios`, `unknown`, `failed`.

### `den.device`, `den.game`, `den.steam`

| Function | Arguments | Returns | Permission | Needs |
|---|---|---|---|---|
| `den.device.info()` *(wait)* | - | `{name, known, manufacturer, model, soc, os, os_version, os_name, steamos, cpu_cores, ram_mb, gpu, handheld, form, tier, screen = {width, height, refresh_hz}}` | `device.info` | `feature.tune.1` |
| `den.game.settings(id)` *(wait)* | a library id of `systems` | `{id, name, system, core, core_name, known, options = { {key, label, value, values, own} }}` | `game.settings` | `feature.tune.1` |
| `den.game.set(id, {key = value or den.json.null})` *(wait, user)* | up to 64 options; values are text, `den.json.null` gives the console's value back | the game's own values before (`den.json.null` for none), after the app asked the user; `nil, "cancelled"` on no | `game.settings` | `feature.tune.1` |
| `den.steam.status()` *(wait)* | - | `{installed, can_change, note, apps = { {appid, name, shortcut} }, tools = { {name, display} }}` | `steam` | `feature.tune.1` |
| `den.steam.config(appid)` *(wait)* | text | `{launch_options, compat_tool, compat_tool_display, compat_tool_chosen}` | `steam` | `feature.tune.1` |
| `den.steam.set{appid, name?, launch_options?, compat_tool?}` *(wait, user)* | `compat_tool = ""` gives the choice back to Steam; launch options must pass the app's check (no shell syntax, no `LD_PRELOAD`) | `true` after the app asked the user; `nil, "cancelled"` on no | `steam` | `feature.tune.1` |

### `den.achievements` (RetroAchievements)

| Function | Arguments | Returns | Permission | Needs |
|---|---|---|---|---|
| `status()` *(wait)* | - | `{signed_in, signing_in, user = {name, display_name, avatar, score, softcore_score, messages}, hardcore, sound, screenshot, playing}` | `achievements` (official only) | `feature.achievements.1` |
| `sign_in{user, password}` *(wait, user)* | the RA user and password | true; the token RA returns is kept as the secret `login` = `{user, token}`, the password nowhere | `achievements` | `feature.achievements.1` |
| `sign_out()` *(user)* | - | true | `achievements` | `feature.achievements.1` |
| `set{hardcore?, sound?, screenshot?}` *(user)* | booleans | `true` | `achievements` | `feature.achievements.1` |
| `game(library_id)` *(wait)* | a library id | `{id, name, ra_id, title, image, total, unlocked, points_total, points_unlocked, hardcore, mastered, playing, note, achievements = [{id, title, description, badge, points, unlocked, progress, percent, rarity}]}` | `achievements` | `feature.achievements.1` |

### `den.sync` (sync providers)

Present (not nil) only with the `sync` permission.

| Function | Arguments | Returns | Permission | Needs |
|---|---|---|---|---|
| `den.sync.status()` | - | the table below | `sync` | - |
| `den.sync.now()` | - | `true`, or `nil, message` (not the active provider) | `sync` | - |
| `den.sync.enabled_categories()` | - | the categories on for this provider on this device, `{"saves", ...}` | `sync` | - |
| `den.sync.folder()` | - | the folder store's absolute path, or nil | `sync` | - |
| `den.sync.use_folder(path?)` *(wait)* | none: the folder picker; `"~/..."`: under the home (shared storage on Android); else absolute | the path, or `nil, message` (`"declined"`, `"no folder was chosen"`). The user confirms a path the plugin names. Refused: a drive's root, EmuDEN's data, a game folder | `sync` | - |
| `den.sync.set_server(url)` *(wait)* | http or https URL | `true` once the user confirmed it (at once when it is the server already confirmed), or `nil, "declined"`. Keeps scheme, host and port only | `sync` and `http.user_host` | - |
| `den.sync.download_game(paths)` *(wait)* | portable names under `games/` (a list or one text): the index file and its members | `true`, or `nil, message`; the app calls `provider.get` for each and adds the game to the library | `sync` | - |

`den.sync.status()`: `{active, running, last_sync, done, total, uploaded, downloaded,
conflicts, waiting, errors = {...}, error?, current = {path, fraction}?, folder?, stopping?}`.
Skip fields you do not know; `stopping` is set while a run is being stopped.

## 4. Permissions, capabilities and trust

| Permission | Needs | Official plugins only |
|---|---|---|
| `http`, `download` (with `http.hosts`), `open-url` (with `open_hosts`), `files.import`, `library.read`, `patch`, `library.write` (with `systems`), `sync` (with `feature.sync.categories`), `http.user_host`, `http.local` | - | no |
| `browse` (with `browse_hosts`) | `feature.web.1` | no |
| `device.info`, `steam`, `game.settings` (with `systems`) | `feature.tune.1` | no |
| `achievements` | `feature.achievements.1` | yes |
| `browse.any`, `downloads.setup` | `feature.browser.1` | yes |
| `downloads.watch` (with `file_types`) | - | yes |

A permission whose capability is missing from `needs` is refused. Official means a plugin of
EmuDEN's own source with an `emuden.` id; `systems: ["*"]` is official only as well. A plugin
in the developer folder (`<data>/plugins-dev/<id>/`, shown when Settings > Plugins > Developer
mode is on) is loaded unsigned and may use everything except what is official only.

## 5. Sync providers

A feature plugin with the `sync` permission and `feature.sync` is a provider:

```json
"sync": { "categories": ["saves", "states", "config"], "listing": "category" }
```

`categories` is required: some of `saves`, `states`, `config`, `games`, `bios`, none twice.
`listing` (optional) says how the provider lists:

| `listing` | The app | `list` must |
|---|---|---|
| `category` (default) | lists each category it syncs: `"saves/"`, `"states/"`, ... | return the files under the folder it is given |
| `all` | lists once per run, with prefix `""`: any listing returns everything | return every file for `""` |
| `per_folder` | a run lists once with `""`; a game's own sync before and after play lists only that game's system folders (`"saves/gba/"`, `"states/gba/"`) | return every file for `""`, and list one system folder quickly |

The script returns `plugin.provider` beside its other entry points. The engine calls these
from its own job, one call at a time per provider, without opening the plugin's page (the
script is started for it and kept 60 s after the last call):

| Function | Arguments | Returns |
|---|---|---|
| `list(prefix)` | a category or system folder (`"saves/"`, `"saves/gba/"`), or nil for everything | `{ {path, size, modified, rev} }`: portable paths (`saves/<system>/<rom stem>.srm`, ...), bytes, the time `put` gave (Unix seconds, not the upload time), a revision (text or number) |
| `get(path, local_path, progress)` | the portable path; a lent `sync:` file to write (use `den.http.request{to_file = local_path}`); `progress(done, total)` | anything but nil on success |
| `put(path, local_path, rev, modified, progress)` | the portable path; a lent file to upload (`body_file`, `den.files.size`, `den.files.read`); the rev the journal knows (nil for a new file); the local file's time; `progress(done, total)` | the new rev (text or number; `""` or nothing: the app uses `<size>@<modified>`). `nil, "conflict"` when the remote has a newer version than `rev` |
| `delete(path)` | the portable path | anything but nil |
| `status()` | - | optional; a table, e.g. `{account, server, free}` |

- `nil, message` or an error fails that file; it is tried again on the next run. The engine
  gives a call up after 2 hours.
- `progress` also takes a single fraction, so it can be passed as `on_progress` as it is.
- A long upload should look at `den.sync.status().stopping` between its steps and return
  `nil, "cancelled"`; the engine goes on with it in a later run.
- The app currently passes `nil`, not `""`, when it lists everything: treat both alike.
- Paths outside the portable names, and files of PC consoles, are dropped from listings and
  never given to `get`, `put` or `delete`.
- A provider without a store of its own may use the app's folder store instead
  (`den.sync.use_folder`): the app then keeps the remote side as plain files in that folder
  and `list`/`get`/`put`/`delete` are not called.

## 6. The UI model

A page is a table; the app draws it with its own UI kit and owns focus, pad, touch, keyboard
and scrolling. There are no colours, sizes or positions.

```
page    = { title, subtitle?, search?, chips?, body = { element... }, busy? }
search  = { placeholder?, value?, action }      -- the action gets the typed text as value
chips   = { action, multi?, items = { {id, label, selected?} } }  -- value: selected ids, "a,b"
```

| Element `type` | Fields | Notes |
|---|---|---|
| `text` | `text`, `style?` | style: `body`, `heading`, `caption`, `warning` |
| `button` | `label`, `action`, `arg?`, `enabled?` | |
| `row` | `label`, `value?`, `image?`, `action?`, `arg?` | a settings-like list row |
| `input` | `id`, `label`, `value?`, `action`, `secret?` | opens the on-screen keyboard; the action gets the text. A secret input shows stars and starts empty |
| `progress` | `id`, `label?`, `fraction` | 0..1; negative = unknown |
| `image` | `image`, `aspect?`, `height?` | |
| `qr` | `text`, `height?` | a QR code of the text; older apps skip it |
| `empty` | `title`, `text?`, `button?` | a page with nothing to list |
| `tile` | `title`, `subtitle?`, `image?`, `aspect?`, `badge?`, `action`, `arg` | inside `shelf` and `grid` |
| `shelf` | `title`, `items = {tile...}`, `more_action?`, `arg?` | a row of tiles |
| `grid` | `items = {tile...}`, `columns?`, `more_action?` | `more_action`: the end was reached |
| `detail` | `title`, `subtitle?`, `image?`, `aspect?`, `screenshots? = {image...}`, `facts? = { {label, value} }`, `text?`, `buttons = {button...}` | a fact may also be `{label, value}` by position |

- Every element may have an `id`: `den.ui.patch` finds elements by it, and focus stays on it
  across `set`. `patch` changes the same fields a page gives (text, label, value, fraction,
  enabled, ...); the id itself stays.
- Text fields also take numbers and booleans. `arg` is any JSON-like value, handed back to the
  action untouched. Items of `shelf`/`grid` default to `tile`, `detail` buttons and the `empty`
  button to `button`.
- `image` is `"plugin:<path>"` (package or data folder), `"game:<library id>"` (that game's
  cover) or an https URL of `http.hosts`; the app fetches and caches it.
- Limits: 400 elements a page, 8 pages deep, texts cut at 4000 bytes, 64 chips. Unknown
  element types and fields are left out, so later API versions can add some.

## 7. Testing offline

`tests/den_mock.lua` is a `den` for plain Lua 5.4 that reads a plugin's `plugin.json`, refuses
it as the app would and runs its script in the same sandbox, with fake answers the test sets
up (HTTP routes, the user's answers, library games). Its header lists its functions;
`tests/jdoe.hello-feature/test.lua` and `tests/jdoe.sync.webdav/test.lua` use it:

```sh
LUA_PATH="tests/?.lua;tests/<id>/?.lua;<plugin folder>/?.lua;;" DEN_PLUGIN_DIR=<plugin folder> \
  lua tests/<id>/test.lua
```

The mock answers waiting calls at once and cannot reproduce the memory limit, the order of
calls that wait in parallel, or the app's rendering of a page.
