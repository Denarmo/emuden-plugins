# Wheel

An interface plugin for EmuDEN's Home screen. Pick it under Settings, Interface.

- Game names on an arc at the right that turns as you move, the selected name large in the
  middle, and the selected game's cover filling the rest of the screen with its records under
  it. On a narrow screen the names take the whole width over the art.
- Up and Down turn the wheel by one game, Left and Right by a wheelful, L and R change
  console, A starts the game. A finger turns the wheel, and it comes to rest on a name.

It holds no code: EmuDEN's "wheel" layout draws it from `plugin.json`. An EmuDEN without that
layout says so when it is picked and keeps its own Home. See `docs/interface-plugins.md`.
