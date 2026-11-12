# Engines

A plugin picks one of two engines.

## `libretro`

Games run inside EmuDEN in a libretro core. The console gets EmuDEN's player: save states, rewind,
fast-forward, run-ahead, cheats, shaders, borders, achievements and playing together.

`capabilities` says which of those the console offers: `save_states`, `rewind`, `fast_forward`,
`run_ahead`, `cheats`, `netplay`, `achievements`. What you claim is cut down to what the engine can
do: playing together is off for a core with `"gpu": "opengl"`, because such cores do not stay in
step on two PCs.

A core is loaded into EmuDEN's own process, so its licence must be compatible with the GPL.

## `external`

Games run in a standalone emulator that EmuDEN downloads, unpacks into its own folder and starts.
It offers none of the player features; `capabilities` must be empty. Play time is measured from
how long the emulator ran.

### The launch template

```json
"launch": {
  "executable": { "windows-x86_64": "Cemu.exe", "linux-x86_64": "Cemu.AppImage" },
  "user_provided_setting": "own_copy",
  "args": ["-g", "{rom}"],
  "working_dir": "{emulator_dir}",
  "env": { "CEMU_DATA": "{data_dir}" },
  "create_files": [{ "path": "portable/.keep", "content": "" }]
}
```

- `args` is the argument list, one argument per element. No shell is involved: a game called
  `a "b" & c.wua` stays one argument, and nothing in it is interpreted.
- Variables: `{rom}`, `{rom_dir}`, `{rom_name}`, `{emulator_dir}`, `{data_dir}`, `{save_dir}`,
  `{bios_dir}`, `{platform}`, `{setting:<key>}`. An unknown one is an error. A variable expands
  inside its element and never splits it.
- `{emulator_dir}` is where the download was unpacked. `{data_dir}` is
  `<EdenDir>/emuden/plugin-data/<plugin id>/`, the place for the emulator's own files.
- `executable` is a path inside `{emulator_dir}`. Absolute paths, `..` and `{rom}` are refused.
  With `user_provided_setting`, the player may point at their own copy of the emulator in a file
  dialog; that choice is stored on the device only.
- `working_dir` is `{emulator_dir}` (default), `{data_dir}` or `{rom_dir}`.
- `env` names are upper case (`^[A-Z][A-Z0-9_]{0,63}$`) and may not be `PATH`, `HOME`,
  `USERPROFILE`, `APPDATA`, `LOCALAPPDATA`, `TEMP`, `TMP`, `SHELL`, `COMSPEC`, `IFS`, or start with
  `LD_`, `DYLD_`, `XDG_`, `QT_`, `STEAM_`, `WINE`, `PROTON`, `PYTHON`, `SDL_`, `VK_`, `__`,
  `EMUDEN_`.
- `create_files` writes small text files (64 KiB at most) at install, inside `{emulator_dir}` or
  `{data_dir}`. A file that exists is left alone.

Settings reach the emulator through the `args`, `args_if_true`, `args_if_false`, `env` and
`launch_var` forms of [settings.md](settings.md).

## Why there is no third engine

Anything else would be code from a plugin running inside EmuDEN. A core is the one exception, and
it is checked against a checksum before every load.
