# Tune: Helix SR

Puts [Helix SR](https://github.com/lonewolf0622/HelixSR)'s FSR 4 upscaler into Steam games
that ship AMD's FSR 3.1, on graphics cards that have no FSR 4 of their own.

Helix SR calls this its "FSR drop-in": the game's `amd_fidelityfx_upscaler_dx12.dll` is replaced
by Helix SR's prebuilt HLX FSR 4 library of the same name, and the game's own FSR setting then
runs HLX FSR 4. It is the same file on Windows and on Linux (Proton), and it needs no launch
options.

1. The page lists the Steam games installed on this computer (not non-Steam shortcuts).
2. Pick a game. EmuDEN looks in its folder for the FSR 3.1 library and for anti-cheat files.
3. Install. The first time, Helix SR 3.4.0 (277 MB) is downloaded from the project's GitHub
   release, after you agreed; the one library is unpacked and kept for your other games, the
   ZIP is deleted. EmuDEN then lists every file it will replace and asks.
4. In the game, pick **AMD FSR** in the graphics settings.
5. Remove puts the game's own library back.

## Which games

| The game's folder has | |
|---|---|
| `amd_fidelityfx_upscaler_dx12.dll` | FSR 3.1 or newer on Direct3D 12: Install is offered |
| only `amd_fidelityfx_dx12.dll` | FSR 3.0 as one library: not supported by this plugin |
| neither | no drop-in |
| an anti-cheat file | refused, whatever else it has |

## Anti-cheat

A game that ships Easy Anti-Cheat, BattlEye, EQU8, FACEIT, Vanguard, EA anticheat (Javelin),
nProtect GameGuard, XIGNCODE3 or Anti-Cheat Expert files is refused: a changed library in a
protected game can get an account banned. The page names the file it found.

The check goes by file names in the game's folder. It cannot see server-side checks, or
anti-cheat that is installed somewhere else.

## Risks

- **Online games.** Use it in single-player games. An online game may treat a changed library
  as cheating, also where no anti-cheat file was found.
- **Game updates undo it.** An update, or Steam's "Verify integrity of game files", brings the
  game's own library back. The page then shows "Changed by a game update" and offers to
  install again.
- **Picture and speed** depend on the game and the graphics card. If a game misbehaves, Remove.
- **No fallback.** Upstream's own instructions keep the game's library beside HLX FSR 4 as
  `amd_fidelityfx_upscaler_dx12.amd.dll`, which HLX FSR 4 falls back to when it cannot start.
  EmuDEN keeps the original outside the game's folder instead, so if FSR does not start in a
  game, Remove.

## Not included

- **The DLSS route** (HLX DLSS, HelixSR Scaler). It needs Helix SR's own setup program and
  NVIDIA's DLSS library, and EmuDEN's plugins never run a program.
- Games with only FSR 3.0, FSR on Vulkan, and games outside Steam.

## Licence

Helix SR is closed freeware by lonewolf0622 under the HelixSR Freeware License: it may be
passed on only unmodified, complete and free of charge. This plugin therefore contains nothing
of Helix SR. It downloads the official release

`https://github.com/lonewolf0622/HelixSR/releases/download/v3.4.0/HelixSR-3.4.0.zip`

pinned by size (290,684,780 bytes) and SHA-256
(`c82dcb88f789a6b0d2b6ae54b4e9fa94289da3c5e9c8167318284aa18d67e2b9`, the digest GitHub's
release API and the release's `SHA256SUMS.txt` both give), and uses one file of it as it is:
`HelixSR-3.4.0/HLX-FSR4/amd_fidelityfx_upscaler_dx12.dll`. The pin is in `release.lua`; a
newer Helix SR needs a newer version of this plugin. HLX FSR 4 contains AMD FidelityFX code
under AMD's MIT licence (the release's `THIRD_PARTY_NOTICES.md`).

The plugin's own scripts are GPL-3.0-or-later. EmuDEN and this plugin are not affiliated with
Helix SR, AMD or NVIDIA.

## How it changes a game

Through EmuDEN's `den.mods`: the plugin names the file, EmuDEN shows the list and copies after
a Yes, keeps the original with a record of what it wrote, and undoes it on Remove or when the
plugin is removed. Nothing else in the game's folder is written.

## Test

`python -I tools/plugin_tool.py test plugins/emuden.tune.helixsr` (Lua 5.4, from the repository
root).
