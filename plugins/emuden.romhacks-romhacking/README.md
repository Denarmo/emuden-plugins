# ROM Hacks: romhacking.net (`emuden.romhacks-romhacking`)

A feature plugin for EmuDEN. It shows romhacking.net in the app's browser page, where the player
browses the real site. When the player presses a download button there, the app receives the
file like a browser's download manager would and hands it to the plugin, which installs it as
a hack of a game the player owns.

What it does **not** do: it never reads, searches, scrapes or fetches the site (it has no
`http` permission and never sees a page, its address or its cookies), it downloads nothing the
player did not press, it never touches a sign-in, and it takes patch files only (`bps`, `ips`,
`ups`, `xdelta`, `vcdiff`, `aps`, `ppf`, or a `zip` holding one). A ROM image is always
refused, also inside an archive and also when it is pre-patched.

Not affiliated with romhacking.net.

## What the site offers (read 2026-11-13)

- The largest archive of ROM hacks and fan translations, for many consoles (NES, SNES, Genesis,
  Game Boy family, N64, PlayStation and more).
- Status: on 2024-08-01 the site closed submissions and became read-only (news only); its
  database and files were handed to the Internet Archive. The live site still answers:
  `robots.txt` was served on 2026-11-13 and names `/download/` as its download path. The front
  page answered 403 to a plain (non-browser) client, so how it looks today was only seen in the
  app's browser page (see the app's `docs/status.md`).
- Downloads: `www.romhacking.net/download/...` on the site itself; the Internet Archive's copy
  is on `archive.org` (its files come from `*.archive.org` storage hosts through a redirect,
  which the browser page lets through for a download).
- Formats: mostly `ips` and `bps`, `xdelta` and `ppf` for large or disc games, nearly always
  inside a `zip`, `7z` or `rar` together with a readme.
- **zip works** (the app unpacks the first patch file in it and refuses a zip holding a game).
  **7z and rar are not supported**: the app has no reader for them, tells the player so and
  takes nothing. Unpack such a file by hand and use "Choose a patch file".
- `ips`, `xdelta` and `ppf` carry no checksum of their base game: the player chooses the game,
  and the choice is remembered for that file name.

## Hosts

| Host | Why |
|---|---|
| `www.romhacking.net`, `romhacking.net` | the site and its downloads |
| `archive.org`, `www.archive.org` | the Internet Archive's copy of the site's files |

Start page: `https://www.romhacking.net/`.

## Files

`plugin.json`, `site.lua` (the site's address and wording), `icon.png`, this file. The flow and
the pages are `shared/romhacks/` of this repository, copied into the package by
`tools/plugin_tool.py` (the folder's `.shared` file names the library).
