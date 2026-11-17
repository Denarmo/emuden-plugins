# Home Layouts

Four other ways for EmuDEN's Home screen to show your games. Pick one under Settings,
Interface, "Home interface"; "EmuDEN (standard)" there brings the usual one back. Tapping the
plugin on the Plugins screen opens that setting.

- **Grid**: covers in rows that scroll, as many per row as fit the screen, the selected game's
  cover, name, console and records in a panel beside the grid (under it on a tall screen).
  Made for big libraries: only the rows on the screen are drawn.
- **List**: one row per game with a small cover, its console, when it was last played and for
  how long; the selected game's cover large beside the list.
- **Wheel**: game names on an arc at the right that turns as you move, in the style of an
  arcade cabinet, with the selected game's art filling the rest of the screen.
- **Hero**: the selected game large across the screen (in Continue, the picture of the moment
  you left it), with a thin row of covers along the bottom to pick the next.

In every layout L and R change console and A starts the game; a finger scrolls, a tap selects
and a tap on the selection starts it.

It holds no code: EmuDEN's layouts draw these looks from `plugin.json`. It replaces the
separate Grid, List, Wheel and Hero plugins. See `docs/interface-plugins.md`.
