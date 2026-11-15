# Browser (`emuden.browser`)

A feature plugin for EmuDEN: a web browser inside the app for any site, with no code for a
particular site. The player browses as in any browser; every file they download lands in
EmuDEN's Downloads folder (`<data>/downloads`), and the app sets it up:

- **Games**: the console is found from the extension, the file's first bytes (cartridge
  headers, disc volume descriptors, CHD track metadata) or the folders and names around it.
  The file goes into that console's folder of the library and is added with its box art.
- **Archives** (zip, 7z): unpacked, then each file is looked at. A cue sheet stays with its
  tracks and the discs of one game share a folder. rar is not opened.
- **ROM hack patches** (IPS, BPS, UPS, xdelta, APS, PPF): applied to a copy of the player's own
  game, found by the checksum the patch carries, else by the name of the hack (from the page's
  title and the file name), else picked by the player. The hack is its own game with the base
  game's box art. A newer version of the same hack replaces the old one and keeps its saves.
- **BIOS files** are never used: they stay in Downloads with that message. Unknown files stay
  in Downloads too.

The Downloads tab lists every setup with undo (games go back to Downloads, hacks are removed;
saves stay).

Permissions: `browse.any` and `downloads.setup`, which EmuDEN grants to official plugins only.
Needs `feature.browser.1` (the app's host API, `docs/feature-plugins.md` in the app's
repository). The plugin never reads a page; it does not see cookies or sign-ins, which stay in
the device's web engine.

Players download only what they have the right to; the plugin is not affiliated with any site.
