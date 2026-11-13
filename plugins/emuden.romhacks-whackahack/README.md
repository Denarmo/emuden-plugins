# ROM Hacks: whackahack.com (`emuden.romhacks-whackahack`)

A feature plugin for EmuDEN. It shows whackahack.com in the app's browser page, where the player
browses the real site. When the player presses a download button there, the app receives the
file like a browser's download manager would and hands it to the plugin, which installs it as
a hack of a game the player owns.

What it does **not** do: it never reads, searches, scrapes or fetches the site (it has no
`http` permission and never sees a page, its address or its cookies), it downloads nothing the
player did not press, it never touches a sign-in, and it takes patch files only (`bps`, `ips`,
`ups`, `xdelta`, `vcdiff`, `aps`, `ppf`, or a `zip` holding one). A ROM image is always
refused, also inside an archive and also when it is pre-patched.

Not affiliated with whackahack.com.

## What the site offers (read 2026-11-13)

- A Spanish-language community for Pokemon fan games: news, a games catalogue (`/juegos/`),
  tools (`/descargas/`), a wiki and a forum (`/foro/`, XenForo-style addresses). The forum's
  front page rendered in EmuDEN's browser page on 2026-11-13.
- ROM hacks are shown in the forum, section "Exposicion de ROM Hacking"
  (`/foro/forums/exposicion-de-rom-hacking.89/`). The catalogue also holds RPG Maker fan games,
  which are not patches.
- Files: forum attachments are served by `whackahack.com` itself; many threads instead link to
  external file hosts (MediaFire, MEGA, Google Drive and others). Those hosts are not declared:
  the app asks "This link goes to <host>. Open it?" for each, per press.
- Sign-in ("Acceder") is on the same host. Whether a guest can download attachments was not
  tested; if the forum asks, the player signs in in the page. The plugin never touches
  credentials.
- Formats seen for GBA hacks in this community: `ips`, `ups`, `bps`, sometimes in a `zip`.
  Threads may also offer already patched ROMs: those are refused.
- The forum's rules are at `/foro/threads/40243/`.

## Hosts

| Host | Why |
|---|---|
| `whackahack.com`, `www.whackahack.com` | the site, its forum, its attachments, its sign-in |

Start page: `https://whackahack.com/foro/`.

## Files

`plugin.json`, `site.lua` (the site's address and wording), `icon.png`, this file. The flow and
the pages are `shared/romhacks/` of this repository, copied into the package by
`tools/plugin_tool.py` (the folder's `.shared` file names the library).
