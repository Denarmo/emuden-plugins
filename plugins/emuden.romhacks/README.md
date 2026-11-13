# ROM Hacks: hackdex.app (`emuden.romhacks`)

A feature plugin for EmuDEN. It shows hackdex.app in the app's browser page, where the player
browses the real site. When the player presses a download button there, the app receives the
file like a browser's download manager would and hands it to the plugin, which installs it as
a hack of a game the player owns.

What it does **not** do: it never reads, searches, scrapes or fetches the site (it has no
`http` permission and never sees a page, its address or its cookies), it downloads nothing the
player did not press, it never touches a sign-in, and it takes patch files only (`bps`, `ips`,
`ups`, `xdelta`, `vcdiff`, `aps`, `ppf`, or a `zip` or `7z` holding one). A ROM image is always
refused, also inside an archive and also when it is pre-patched.

Not affiliated with hackdex.app.

## What the site offers (read 2026-11-13)

- Pokemon hacks for GB, GBC, GBA and NDS base games, 39 known base dumps (`bases.json`, from the
  site's MIT-licensed source; `NOTICE.txt`).
- Patch formats: `bps` and `xdelta` only. A `.bps` names its base game by CRC32; an `.xdelta`
  does not, so the player chooses the game.
- Download: "Download Patch" on a hack's Versions page, when its creator allows it. The link
  (`/api/patches/<id>/download`) answers with a redirect to a signed address on
  `patches.hackdex.app`. No account is needed.
- Terms 1.1.0, section 8, forbid automated tools; the site sits behind a JavaScript checkpoint.
  The plugin therefore requests nothing: the player browses and presses Download.
- The site's licence reserves the name "Hackdex" for its own project: this plugin is called
  "ROM Hacks: hackdex.app" and uses no logo of the site.

## Hosts

| Host | Why |
|---|---|
| `www.hackdex.app`, `hackdex.app` | the site |
| `patches.hackdex.app` | where patch downloads are redirected to |

Start page: `https://www.hackdex.app/discover`.

## Files

`plugin.json`, `site.lua` (the site's address and wording), `icon.png`, this file. The flow and
the pages are `shared/romhacks/` of this repository, copied into the package by
`tools/plugin_tool.py` (the folder's `.shared` file names the library).
