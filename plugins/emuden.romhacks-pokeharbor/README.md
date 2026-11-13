# ROM Hacks: pokeharbor.com (`emuden.romhacks-pokeharbor`)

A feature plugin for EmuDEN. It shows pokeharbor.com in the app's browser page, where the player
browses the real site. When the player presses a download button there, the app receives the
file like a browser's download manager would and hands it to the plugin, which installs it as
a hack of a game the player owns.

What it does **not** do: it never reads, searches, scrapes or fetches the site (it has no
`http` permission and never sees a page, its address or its cookies), it downloads nothing the
player did not press, it never touches a sign-in, and it takes patch files only (`bps`, `ips`,
`ups`, `xdelta`, `vcdiff`, `aps`, `ppf`, or a `zip` or `7z` holding one). A ROM image is always
refused, also inside an archive and also when it is pre-patched.

Not affiliated with pokeharbor.com.

## What the site offers (read 2026-11-13)

- A WordPress site listing Pokemon hacks (GB, GBC, GBA, NDS). Entries are posts
  (`/YYYY/MM/<slug>/`), categories under `/category/roms/`.
- **It offers pre-patched ROMs, not patches.** The GBA category says "All games are pre-patched
  and are updated regularly"; an entry's section is headed "Download Pre-Patched ...". No patch
  section was found.
- Downloads are not hosted by the site ("the fan projects found on PokeHarbor are not hosted on
  it"): an entry links straight to MediaFire and MEGA, usually a `.zip` holding the game.
- Consequence: the player can browse the site in the app, but its usual downloads are refused:
  a ROM image by its name, a zip that holds one by its content, each with the message "EmuDEN
  only installs patch files; this is a full game file". Should an entry link to a real patch
  file, that one installs.
- File hosts are not declared: the app asks "This link goes to <host>. Open it?" per press.

## Hosts

| Host | Why |
|---|---|
| `www.pokeharbor.com`, `pokeharbor.com` | the site |

Start page: `https://www.pokeharbor.com/`.

## Files

`plugin.json`, `site.lua` (the site's address and wording), `icon.png`, this file. The flow and
the pages are `shared/romhacks/` of this repository, copied into the package by
`tools/plugin_tool.py` (the folder's `.shared` file names the library).
