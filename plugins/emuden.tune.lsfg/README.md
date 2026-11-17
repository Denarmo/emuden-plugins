# Tune: LSFG

Lossless Scaling's frame generation for Steam games on Linux and SteamOS, through
[lsfg-vk](https://lsfg-vk.dev) 2.0.0: 2x, 3x or 4x the frames, per game.

## What you need

- **Lossless Scaling, bought on Steam and installed on this device** (app 993090). lsfg-vk
  runs Lossless Scaling's own frame generation and reads it from that installation; without
  it nothing works, and this plugin does not download any part of Lossless Scaling.
- **Its `lsfg-vk` beta branch**: in Steam, Lossless Scaling's Properties > Betas > `lsfg-vk`.
  lsfg-vk 2 reads `lsfg-vk.dll`, which that branch has. The page checks for the file and says
  so when it is missing.
- To set launch options from EmuDEN: SteamOS, or Linux with Steam's local debugging port on
  (Decky Loader turns it on), as for Tune: ProtonDB. Without it the page shows the options to
  enter by hand.

## Setting it up

1. The page shows three things: Lossless Scaling, its lsfg-vk library, and the lsfg-vk layer.
2. **Install lsfg-vk 2.0.0** downloads the project's own build and hands the layer to EmuDEN,
   which lists the files and asks, then installs it as a Vulkan layer for your user. Installed,
   it does nothing in a game until it is switched on.
3. Pick a game: Off, 2x, 3x or 4x, the flow scale (100 % to 25 %: the size motion is measured
   at) and performance mode (a lighter model). Apply; EmuDEN asks and shows the change.

Apply writes environment variables in front of `%command%` in the game's Steam launch options:

```
LSFGVK_ENV=1 LSFGVK_MULTIPLIER=2 LSFGVK_FLOW_SCALE=1.0 LSFGVK_PERFORMANCE_MODE=0 %command%
```

Whatever else the launch options hold stays, in its order. Off takes out these four variables
and nothing else. On SteamOS `ENABLE_GAMESCOPE_WSI=0` is added as well, as the Decky plugin for
lsfg-vk does, and taken out again on Off only when this plugin added it. Launch options with
quotes or other shell syntax are left alone: the page says so, change them in Steam first.

## Limits

- **Vulkan only**: games that draw with Vulkan, which Proton games do through DXVK and VKD3D.
  Not OpenGL.
- **Paced to the display**: generated frames are shown at the display's refresh rate. Cap the
  game to half (2x), a third (3x) or a quarter (4x) of it for an even picture.
- Frame generation adds input delay and needs a steady frame rate to start from.
- lsfg-vk looks for `lsfg-vk.dll` in Steam's usual library folders under your home folder. With
  Lossless Scaling in another Steam library (an SD card, a second drive), set `dll` in
  lsfg-vk's own `conf.toml` by hand; this plugin cannot.
- Removing lsfg-vk leaves the games' launch options as they are; without the layer the
  variables do nothing. Switch games Off first for clean options.
- One build is pinned (`release.lua`); a newer lsfg-vk needs a newer version of this plugin.

## On Windows

Lossless Scaling is its own program there: start it from Steam, choose LSFG and press its
Scale hotkey in the game. EmuDEN cannot drive it, and the page only says so.

## Licence

lsfg-vk is by PancakeTAS, under CC BY-NC-ND 4.0: it may be passed on unmodified and not
commercially. This plugin contains nothing of it; it downloads

`https://builds.lsfg-vk.dev/lsfg-vk-2.0.0.tar.xz`

from the project's own build server, checked against a SHA-256 pinned in `release.lua`, and
installs the layer's libraries and manifests as they are (EmuDEN sets only the manifest's
`library_path`, to where it put the library). While `release.lua` holds no checksum the plugin
downloads nothing. Lossless Scaling is by THS and is not free; this plugin is no way around
buying it.

The plugin's own scripts are GPL-3.0-or-later. EmuDEN and this plugin are not affiliated with
lsfg-vk or Lossless Scaling.

## Test

`python -I tools/plugin_tool.py test plugins/emuden.tune.lsfg` (Lua 5.4, from the repository
root): `launch_test.lua` for the merging of launch options, `test.lua` for the pages.
