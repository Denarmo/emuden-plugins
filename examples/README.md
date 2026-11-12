# Example plugins

Two consoles that run in a standalone emulator, as a third party would publish them. They are
not in `index.json` and EmuDEN does not install them by itself.

- `jdoe.wiiu-cemu`: Wii U through Cemu (Windows and Linux).
- `jdoe.xbox360-xenia`: Xbox 360 through Xenia Canary (Windows only).

Before publishing one:

1. Change the id and `publisher` to your GitHub name.
2. Check the download addresses, the executable name and the arguments against the emulator's
   current release.
3. Replace each `sha256` (all zeros here) and `size` (1 here) with the real values of the file.
   EmuDEN refuses a download that does not match, so the examples as they are install nothing.

To try one first, copy its folder to the developer folder (see
[getting-started.md](../docs/getting-started.md)).
