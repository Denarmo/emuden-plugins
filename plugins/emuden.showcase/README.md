# Showcase

An interface plugin for EmuDEN's Home screen. Pick it under Settings, Interface.

- Consoles are tabs along the top. L and R step through them; Up reaches them too.
- One row of covers glides left and right; the selected cover is large, floats a little and
  has a mirror image under it. A to start, which zooms the cover into the console's colour.
- The selected game's blurred cover sits behind everything, washed in the console's colour.
- On a device with a second screen, that screen shows the selected game's page as usual.

It holds no code: EmuDEN's "carousel" layout draws it from `plugin.json`. See
`docs/interface-plugins.md` to make your own.
