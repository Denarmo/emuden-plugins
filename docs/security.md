# What EmuDEN checks

## Before anything is installed

- **The list.** `index.json` must carry a valid Ed25519 signature by the source's key: the key built
  into EmuDEN for the official source, the key pinned when it was added for any other. The
  signature is checked before the list is read. A list with a lower `sequence` than the last one
  seen is refused, and one past its `expires` date installs nothing (what is installed keeps
  working, and its revocations still apply).
- **The package.** Its exact size and SHA-256 come from the signed list. What it may hold depends
  on its kind ([publishing.md](publishing.md#what-a-package-may-hold)); links and programs are
  refused, by name and by content.
- **The manifest.** The id and version must be the ones the list named, the id must be in the
  source's namespace, and the format rules apply. A feature plugin may not ask for more than the
  list showed, and each permission needs its capability in `needs`.
- **Every download.** HTTPS only. The file is hashed while it arrives, stopped when it grows past
  its stated size, and put in place only when the checksum matches. Archives are unpacked without
  links, absolute paths or `..`.
- **Every load or start.** A libretro core is hashed again each time before it is loaded, an engine
  app's program before it is started (on Android: its signing certificate and version), and
  refused when it is not the file that was installed or when a source blocked its checksum.

## What each kind of plugin can do

| Kind | Runs | Reaches |
|---|---|---|
| `console` | Nothing of its own. The libretro cores it names run inside EmuDEN; the engine apps it names run as programs with the player's rights | The ROM folders of its systems, the BIOS folder (read), its cores' save and state files |
| `feature` | Its Lua scripts, in EmuDEN's sandbox: no `os`, `io`, `require`, native code or bytecode; memory and storage limits | Only the `den.*` calls its permissions allow, the hosts and systems it declared, and what the player agreed to ([lua-api.md](lua-api.md)) |
| `interface` | Nothing: it is data EmuDEN's own layouts draw | Its own pictures |

No plugin can:

- start a program other than a pinned engine app, use a shell, or set environment variables;
- write outside its own data folder (a feature plugin's files), except through the `den.*` calls
  that ask the player or that its permissions name (patched copies of games, sync);
- replace another plugin's core, or a core the player or EmuDEN put there, with another build;
- use the `emuden` namespace, the Switch 2 engine, scanners or engine-answered BIOS entries;
- unless it is one of EmuDEN's own (`emuden.*` from the official source): watch the Downloads
  folder, show any website, set up downloads, sign in to RetroAchievements, or see every console
  (`systems: ["*"]`).

PC game data never reaches a sync provider, whatever a plugin says.

## What the player is told

| Source | Shown before installing |
|---|---|
| EmuDEN's own consoles | What will be downloaded and from where. Cores from the libretro buildbot are nightly builds without a fixed checksum; they are labelled so |
| The official source | The same, with checksums |
| Another source | Who publishes it and the key's fingerprint; for a console, that its cores are programs EmuDEN did not check; for a feature plugin, every permission, host and console it asks for |
| Developer folder | "Developer folder" on the console's page, "Developer" on a feature plugin; nothing is signed |

## The developer folder

Only with Settings > Plugins > Developer mode on. Its plugins are not signed, so they follow the
rules of an added source without its namespace, may name local files as downloads, and get none
of the official-only permissions. Turning developer mode off stops using them; cores installed
for them stay until removed.

## Honest limits

A checksum proves a download is the file its publisher chose, not that the file is harmless. A
libretro core runs inside EmuDEN and an engine app runs with the player's rights like any program
they start. Add sources from people you would run programs from.
