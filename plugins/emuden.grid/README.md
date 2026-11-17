# Grid

An interface plugin for EmuDEN's Home screen. Pick it under Settings, Interface.

- Covers in rows that scroll, as many per row as fit the screen. The selected cover grows a
  little; its cover, name, console and records are in a panel beside the grid (under it on a
  tall screen).
- The pad moves through the grid; Up from the top row reaches the tabs, Down from the last row
  the other screens. L and R change console, A starts the game.
- A finger scrolls the grid, a tap selects a cover and a tap on the selected one starts it.
- Only the rows on the screen are drawn and their covers loaded, so a library of thousands of
  games scrolls as smoothly as a few.

It holds no code: EmuDEN's "grid" layout draws it from `plugin.json`. An EmuDEN without that
layout says so when it is picked and keeps its own Home. See `docs/interface-plugins.md`.
