# Hero

An interface plugin for EmuDEN's Home screen. Pick it under Settings, Interface.

- The selected game large across the screen: its cover (or, in Continue, the picture of the
  moment you left it), its console, name and records. A thin row of covers along the bottom
  keeps the selection in the middle.
- Left and Right move along the row, L and R change console, Up reaches the tabs, A starts the
  game. A swipe along the row scrolls it; a tap on the large picture starts the game.

It holds no code: EmuDEN's "hero" layout draws it from `plugin.json`. An EmuDEN without that
layout says so when it is picked and keeps its own Home. See `docs/interface-plugins.md`.
