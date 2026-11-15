# Mirrored cores

The emulator cores this source installs are unmodified nightly builds from the libretro buildbot
(https://buildbot.libretro.com/nightly/), except Play! (see below), copied into this repository's releases so each download has a fixed
checksum. `cores.lock.json` records where each file came from, when, and its checksum.

Only cores that need no console BIOS are offered: each either needs none or carries its own
replacement (mGBA, melonDS, PokeMini, PCSX ReARMed, Yabause, Flycast, a5200, Play!, and blueMSX with the free C-BIOS). Consoles whose every core
needs a BIOS (Sega CD, PC Engine CD, PC-FX, Neo Geo, 3DO, ColecoVision, Intellivision) are not offered until
there is one. Files of cores no longer offered stay in the releases.

Each core is the work of its own authors and is distributed under its own licence. Source code for every core
is linked from https://github.com/libretro (repository names follow the core names below) and from
https://docs.libretro.com/.

| Core | Licence | Builds |
|---|---|---|
| a5200 | GPL-2.0-only | Windows, Linux, Android |
| bluemsx | GPL-2.0-only | Windows, Linux, Android |
| bsnes | GPL-3.0-only | Windows, Linux, Android |
| desmume | GPL-2.0-only | Windows, Linux, Android |
| dolphin | GPL-2.0-or-later | Windows, Linux, Android |
| fbneo | LicenseRef-FBNeo-NonCommercial | Windows, Linux, Android |
| fceumm | GPL-2.0-only | Windows, Linux, Android |
| flycast | GPL-2.0-only | Windows, Linux, Android |
| gbads | GPL-3.0-only | Windows, Linux, Android |
| gambatte | GPL-2.0-only | Windows, Linux, Android |
| genesis_plus_gx | LicenseRef-Genesis-Plus-GX | Windows, Linux, Android |
| handy | Zlib | Windows, Linux, Android |
| mame2003_plus | LicenseRef-MAME-NonCommercial | Windows, Linux, Android |
| mednafen_ngp | GPL-2.0-only | Windows, Linux, Android |
| mednafen_pce | GPL-2.0-only | Windows, Linux, Android |
| mednafen_pce_fast | GPL-2.0-only | Windows, Linux, Android |
| mednafen_vb | GPL-2.0-only | Windows, Linux, Android |
| mednafen_wswan | GPL-2.0-only | Windows, Linux, Android |
| melonds | GPL-3.0-only | Windows, Linux, Android |
| melondsds | GPL-3.0-only | Windows, Linux, Android |
| mesen | GPL-3.0-only | Windows, Linux, Android |
| mgba | MPL-2.0 | Windows, Linux, Android |
| mupen64plus_next | GPL-2.0-only | Windows, Linux, Android |
| nestopia | GPL-2.0-or-later | Windows, Linux, Android |
| parallel_n64 | GPL-2.0-only | Windows, Linux, Android |
| pcsx_rearmed | GPL-2.0-only | Windows, Linux, Android |
| picodrive | LicenseRef-PicoDrive | Windows, Linux, Android |
| play | BSD-2-Clause | Windows, Linux, Android |
| pokemini | GPL-3.0-only | Windows, Linux, Android |
| ppsspp | GPL-2.0-or-later | Windows, Linux, Android |
| prosystem | GPL-2.0-only | Windows, Linux, Android |
| retro8 | GPL-3.0-only | Windows, Linux, Android |
| sameboy | MIT | Windows, Linux, Android |
| snes9x | LicenseRef-Snes9x | Windows, Linux, Android |
| stella | GPL-2.0-only | Windows, Linux, Android |
| vba_next | GPL-2.0-only | Windows, Linux, Android |
| vecx | GPL-3.0-only | Windows, Linux, Android |
| virtualjaguar | GPL-3.0-only | Windows, Linux, Android |
| yabause | GPL-2.0-only | Windows, Linux, Android |

- Windows and the first Linux builds are in the release `cores-2026-11-12`; the Android (arm64-v8a) builds and
  the Linux builds of the alternative cores are in `cores-android-2026-11-13`. The cores added for the Atari,
  NEC, SNK, Bandai, Sega CD/32X/SG-1000, Virtual Boy, Pokémon mini, 3DO, ColecoVision, Intellivision, Vectrex,
  MSX and arcade consoles, and the Windows builds of the alternative cores, are in `cores-2026-11-14`.
- `play` (Play!, PS2) needs no BIOS: it carries its own implementation of the PS2 kernel and I/O modules. It is
  the one core not taken from the buildbot: it is built from the fork https://github.com/Denarmo/Play- (tag
  `emuden-0.77-35-g75bf2194`), which makes the libretro core run on Android, makes its save states load,
  reports 50 Hz for PAL games and streams draw data and texture uploads through persistent buffers, which
  makes its OpenGL renderer several times faster on Android, and fills the frame it reports (the
  frontend applies the aspect ratio). It also carries Play!'s game configs (patches and idle loops),
  which a core could not read from the app's resources. On Android it draws on a thread of its own, in an
  OpenGL context shared with the frontend's, and shows interlaced fields where they belong. It samples where the
  GS samples (no lines of wrong texels in 1:1 copies) and has a widescreen option with per-game patches (Colin McRae
  Rally 3 and Gran Turismo 4, PAL). Since GitHub Actions is off for the fork, its Linux core is built on Debian 13
  (glibc 2.38 or later, as EmuDEN's own Linux build). Its builds are in the release
  `cores-play-2026-11-14`, with the unstripped Android core for crash reports; the buildbot files stay in `cores-2026-11-14`.
- On Android `mupen64plus_next` is the buildbot's `mupen64plus_next_gles3` build.
- `fake08` (PICO-8) has no buildbot build for any platform, so it has no download.
- `fbneo`, `mame2003_plus`, `opera` and `fmsx` are licensed for non-commercial use only. They are mirrored
  unmodified and free of charge.

## PPSSPP assets

`ppsspp-assets-v1.20.4.zip` (release `cores-android-2026-11-13`) is the unmodified `assets` directory of
https://github.com/hrydgard/ppsspp at the tag `v1.20.4`, zipped under `PPSSPP/`. EmuDEN unpacks it into the
BIOS folder when the PPSSPP core is installed; the core reads its fonts and `ppge_atlas.zim` from there.
PPSSPP and its assets are GPL-2.0-or-later.

blueMSX runs MSX cartridges on C-BIOS 0.23 (BSD-2-Clause, https://cbios.sourceforge.net/). Its system files
(release cores-msx-2026-11-14) hold the blueMSX Databases folder and only the three C-BIOS machines from
libretro/blueMSX-libretro e3086eb; no proprietary MSX BIOS is included. Disk and tape games need a real BIOS and are not offered.

GBA DS (`gbads`) is built from Denarmo/gba-ds (a fork of kyannon/gba-ds, GPL-3.0, on libmgba, MPL-2.0), not
from the buildbot. It is the GBA core EmuDEN picks for the games it has a second-screen profile for (the `games`
list in the GBA plugin, by ROM header code); every other GBA game keeps mGBA.

PSX2 ECP (`psx2-ecp`) is an optional PS2 core on Android only: a standalone app, Denarmo/PSX2 (a fork of
izzy2lost/PSX2, GPL-3.0, from PCSX2), driven over the Emulator Control Protocol. It is the one core here that needs
the player's own BIOS (imported in the PSX2 ECP app); Play! stays the PS2 default and needs none. It is the worked
example for emulator developers (https://github.com/Denarmo/emulator-control-protocol).

DroidDeck (`droiddeck`, plugin `emuden.steam`) runs Steam games on Android: the unmodified app from
Droid-Deck/DroidDeck (GPL-3.0), pinned by its signing certificate and APK hash. It speaks no ECP, so it is driven at
level 0: EmuDEN hands it a game's `.steam` file (the Steam app id DroidDeck's game files sync writes) and the session
ends when EmuDEN is back in front. Covers come from Steam's public image server by that app id.
