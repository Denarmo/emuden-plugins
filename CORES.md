# Mirrored cores

The emulator cores this source installs are unmodified nightly builds from the libretro buildbot
(https://buildbot.libretro.com/nightly/), copied into this repository's releases so each download has a fixed
checksum. `cores.lock.json` records where each file came from, when, and its checksum.

Each core is the work of its own authors and is distributed under its own licence. Source code for every core
is linked from https://github.com/libretro (repository names follow the core names below) and from
https://docs.libretro.com/.

| Core | Licence | Builds |
|---|---|---|
| a5200 | GPL-2.0-only | Windows, Linux, Android |
| bsnes | GPL-3.0-only | Windows, Linux, Android |
| desmume | GPL-2.0-only | Windows, Linux, Android |
| dolphin | GPL-2.0-or-later | Windows, Linux, Android |
| fbneo | LicenseRef-FBNeo-NonCommercial | Windows, Linux, Android |
| fceumm | GPL-2.0-only | Windows, Linux, Android |
| flycast | GPL-2.0-only | Windows, Linux, Android |
| fmsx | LicenseRef-fMSX | Windows, Linux, Android |
| freeintv | GPL-3.0-only | Windows, Linux, Android |
| gambatte | GPL-2.0-only | Windows, Linux, Android |
| gearcoleco | GPL-3.0-only | Windows, Linux, Android |
| genesis_plus_gx | LicenseRef-Genesis-Plus-GX | Windows, Linux, Android |
| handy | Zlib | Windows, Linux, Android |
| mame2003_plus | LicenseRef-MAME-NonCommercial | Windows, Linux, Android |
| mednafen_lynx | GPL-2.0-only | Windows, Linux, Android |
| mednafen_ngp | GPL-2.0-only | Windows, Linux, Android |
| mednafen_pce | GPL-2.0-only | Windows, Linux, Android |
| mednafen_pce_fast | GPL-2.0-only | Windows, Linux, Android |
| mednafen_pcfx | GPL-2.0-only | Windows, Linux, Android |
| mednafen_psx | GPL-2.0-only | Windows, Linux, Android |
| mednafen_saturn | GPL-2.0-only | Windows, Linux, Android |
| mednafen_vb | GPL-2.0-only | Windows, Linux, Android |
| mednafen_wswan | GPL-2.0-only | Windows, Linux, Android |
| melonds | GPL-3.0-only | Windows, Linux, Android |
| melondsds | GPL-3.0-only | Windows, Linux, Android |
| mesen | GPL-3.0-only | Windows, Linux, Android |
| mgba | MPL-2.0 | Windows, Linux, Android |
| mupen64plus_next | GPL-2.0-only | Windows, Linux, Android |
| nestopia | GPL-2.0-or-later | Windows, Linux, Android |
| opera | LicenseRef-Opera-NonCommercial | Windows, Linux, Android |
| parallel_n64 | GPL-2.0-only | Windows, Linux, Android |
| pcsx2 | GPL-3.0-or-later | Windows, Linux, Android |
| pcsx_rearmed | GPL-2.0-only | Windows, Linux, Android |
| picodrive | LicenseRef-PicoDrive | Windows, Linux, Android |
| pokemini | GPL-3.0-only | Windows, Linux, Android |
| ppsspp | GPL-2.0-or-later | Windows, Linux, Android |
| prosystem | GPL-2.0-only | Windows, Linux, Android |
| retro8 | GPL-3.0-only | Windows, Linux, Android |
| sameboy | MIT | Windows, Linux, Android |
| snes9x | LicenseRef-Snes9x | Windows, Linux, Android |
| stella | GPL-2.0-only | Windows, Linux, Android |
| swanstation | GPL-3.0-only | Windows, Linux, Android |
| vba_next | GPL-2.0-only | Windows, Linux, Android |
| vecx | GPL-3.0-only | Windows, Linux, Android |
| virtualjaguar | GPL-3.0-only | Windows, Linux, Android |
| yabause | GPL-2.0-only | Windows, Linux, Android |

- Windows and the first Linux builds are in the release `cores-2026-11-12`; the Android (arm64-v8a) builds and
  the Linux builds of the alternative cores are in `cores-android-2026-11-13`. The cores added for the Atari,
  NEC, SNK, Bandai, Sega CD/32X/SG-1000, Virtual Boy, Pokémon mini, 3DO, ColecoVision, Intellivision, Vectrex,
  MSX and arcade consoles, and the Windows builds of the alternative cores, are in `cores-2026-11-14`.
- On Android `mupen64plus_next` is the buildbot's `mupen64plus_next_gles3` build.
- `fake08` (PICO-8) has no buildbot build for any platform, so it has no download.
- `fbneo`, `mame2003_plus`, `opera` and `fmsx` are licensed for non-commercial use only. They are mirrored
  unmodified and free of charge.

## PPSSPP assets

`ppsspp-assets-v1.20.4.zip` (release `cores-android-2026-11-13`) is the unmodified `assets` directory of
https://github.com/hrydgard/ppsspp at the tag `v1.20.4`, zipped under `PPSSPP/`. EmuDEN unpacks it into the
BIOS folder when the PPSSPP core is installed; the core reads its fonts and `ppge_atlas.zim` from there.
PPSSPP and its assets are GPL-2.0-or-later.
