# Quick Layouts

Other layouts for the quick settings that EmuDEN shows on a second screen while a game plays
(the Retroid Pocket Duo's lower screen, a second window on a PC). Pick one under Settings,
Interface, "Quick settings layout"; "EmuDEN (standard)" there brings the usual one back.

- **Grid**: big touch tiles, the cover small in a corner. Pause, the states and the speed
  come first.
- **Compact**: one row per action with its icon, so more fits without scrolling; the volume
  sliders are right in the list. Two columns on a wide screen.
- **Dock**: the game's cover large with its newest save state, and a bar of five actions
  under it (pause, rewind, fast-forward, states, exit). "More" opens the rest.
- **Split**: the controls on one side and the save state slots on the other, so saving or
  loading is one tap. On an upright screen the slots go below.
- **Performance**: how the game runs on top (the frame rate now and over the last minute, a
  graph of each frame's time with the slow ones marked, the sound queue) and the actions as
  small tiles below it.

Every layout reaches the same things as EmuDEN's own: states, screen size and picture, swap
screens, frame rate counter, black frame insertion, core options, buttons, apps and volumes.

It holds no code: EmuDEN draws these layouts from `plugin.json`. See
`docs/quick-settings.md` to make your own.
