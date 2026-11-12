# Mirrored cores

The emulator cores this source installs are unmodified nightly builds from the libretro buildbot
(https://buildbot.libretro.com/nightly/), copied into this repository's releases so each download has a fixed
checksum. `cores.lock.json` records where each file came from, when, and its checksum.

Each core is the work of its own authors and is distributed under its own licence. Source code for every core
is linked from https://github.com/libretro (repository names follow the core names below) and from
https://docs.libretro.com/.

| Core | Licence | Builds |
|---|---|---|
| bsnes | GPL-3.0-only | Linux, Android |
| desmume | GPL-2.0-only | Linux, Android |
| dolphin | GPL-2.0-or-later | Windows, Linux, Android |
| fceumm | GPL-2.0-only | Windows, Linux, Android |
| flycast | GPL-2.0-only | Windows, Linux, Android |
| gambatte | GPL-2.0-only | Linux, Android |
| genesis_plus_gx | LicenseRef-Genesis-Plus-GX | Windows, Linux, Android |
| mednafen_psx | GPL-2.0-only | Linux, Android |
| mednafen_saturn | GPL-2.0-only | Windows, Linux, Android |
| melonds | GPL-3.0-only | Windows, Linux, Android |
| melondsds | GPL-3.0-only | Linux, Android |
| mesen | GPL-3.0-only | Linux, Android |
| mgba | MPL-2.0 | Windows, Linux, Android |
| mupen64plus_next | GPL-2.0-only | Windows, Linux, Android |
| nestopia | GPL-2.0-or-later | Linux, Android |
| parallel_n64 | GPL-2.0-only | Linux, Android |
| pcsx2 | GPL-3.0-or-later | Windows, Linux, Android |
| pcsx_rearmed | GPL-2.0-only | Windows, Linux, Android |
| picodrive | LicenseRef-PicoDrive | Linux, Android |
| ppsspp | GPL-2.0-or-later | Windows, Linux, Android |
| retro8 | GPL-3.0-only | Linux, Android |
| sameboy | MIT | Linux, Android |
| snes9x | LicenseRef-Snes9x | Windows, Linux, Android |
| swanstation | GPL-3.0-only | Linux, Android |
| vba_next | GPL-2.0-only | Linux, Android |
| yabause | GPL-2.0-only | Linux, Android |

- Windows and the first Linux builds are in the release `cores-2026-11-12`; the Android (arm64-v8a) builds and
  the Linux builds of the alternative cores are in `cores-android-2026-11-13`.
- On Android `mupen64plus_next` is the buildbot's `mupen64plus_next_gles3` build.
- `fake08` (PICO-8) has no buildbot build for any platform, so it has no download.
- The alternative cores (gambatte, sameboy, vba_next, picodrive, parallel_n64, melondsds, desmume, nestopia,
  mesen, retro8, mednafen_psx, swanstation, yabause, bsnes) have no Windows download yet.

## PPSSPP assets

`ppsspp-assets-v1.20.4.zip` (release `cores-android-2026-11-13`) is the unmodified `assets` directory of
https://github.com/hrydgard/ppsspp at the tag `v1.20.4`, zipped under `PPSSPP/`. EmuDEN unpacks it into the
BIOS folder when the PPSSPP core is installed; the core reads its fonts and `ppge_atlas.zim` from there.
PPSSPP and its assets are GPL-2.0-or-later.
