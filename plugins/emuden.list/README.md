# List

An interface plugin for EmuDEN's Home screen. Pick it under Settings, Interface.

- One row per game: a small cover, the name, its console, when it was last played and for how
  long. The selected game's cover is large beside the list, with its records under it; on a
  narrow screen the list takes the whole width.
- Up and Down move by one game, Left and Right by a screenful, L and R change console, A
  starts the game. A finger scrolls the list; a tap selects, a tap on the selection starts it.
- Only the rows on the screen are drawn, so very large libraries stay quick.

It holds no code: EmuDEN's "list" layout draws it from `plugin.json`. An EmuDEN without that
layout says so when it is picked and keeps its own Home. See `docs/interface-plugins.md`.
