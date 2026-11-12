# What EmuDEN checks

## Before anything is installed

- **The list.** `index.json` must carry a valid Ed25519 signature by the source's key: the key built
  into EmuDEN for the official source, the key pinned when it was added for any other. The
  signature is checked before the list is read. A list with a lower `sequence` than the last one
  seen is refused, and one past its `expires` date installs nothing (what is installed keeps
  working, and its revocations still apply). A build of EmuDEN that cannot check signatures adds no
  sources.
- **The package.** Its exact size and SHA-256 come from the signed list. It may hold a manifest,
  pictures, a licence and a readme; links, programs and scripts are refused, by name and by
  content.
- **The manifest.** The id and version must be the ones the list named, the id must be in the
  source's namespace, and the format rules of [manifest.md](manifest.md) apply. A plugin that
  would install more than the list announced is refused.
- **Every download.** HTTPS only. The file is hashed while it arrives, stopped when it grows past
  its stated size, and put in place only when the checksum matches. Archives are unpacked without
  links, absolute paths or `..`.
- **Every load.** A libretro core is hashed again each time before it is loaded and refused when
  it is not the file that was installed, or when a source blocked its checksum.

## What a plugin cannot do

- Run code inside EmuDEN, other than a libretro core.
- Start anything but the emulator in its own folder, or the copy the player picked themselves.
- Use a shell, set `PATH`, `LD_PRELOAD` and similar variables, or write outside its emulator and
  data folders.
- Replace another plugin's emulator, or a core the player or EmuDEN put there, with another build.
- Use the `emuden` namespace, the Switch 2 or PC games engines, or tweak tools.
- Sync anything but its own data folder. PC game data never reaches Google Drive, whatever a
  manifest says.

## What the player is told

| Source | Shown before installing |
|---|---|
| EmuDEN's own consoles | What will be downloaded and from where. Cores from the libretro buildbot are nightly builds without a fixed checksum; they are labelled so |
| The official source | The same, with checksums |
| Another source | Who publishes it, the key's fingerprint, and whether the plugin brings cores or a standalone emulator, with every host it downloads from |
| Developer folder | A "Developer, unsigned" mark |

## Honest limits

A checksum proves a download is the file its publisher chose, not that the file is harmless. A
standalone emulator runs with the player's rights like any program they start. Add sources from
people you would run programs from.
