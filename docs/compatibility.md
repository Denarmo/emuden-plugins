# Compatibility

Three fields decide whether a copy of EmuDEN can use a plugin.

| Field | Meaning | When it does not fit |
|---|---|---|
| `manifest_version` | The file format: 1 | "Needs a newer EmuDEN" |
| `api` | The lowest host API the plugin works with: 1 | "Needs a newer EmuDEN" |
| `needs` | The host features the plugin uses | "Needs a newer EmuDEN", naming the feature |

Features a plugin can ask for today: `engine.libretro`, `engine.external`, `settings.v1`,
`content.multi_file`, `content.magic`. A plugin must list the engine it uses, `settings.v1` when it
has settings, and the `content.` name of each of those two content fields it uses. New features get new names;
an older EmuDEN then says so instead of misreading the plugin.

`platforms` says where the plugin works. Elsewhere it is listed as "Not available on this device".

## Unknown fields

- In most places an unknown field is ignored, so a newer manifest still loads in an older EmuDEN.
- In the **strict objects** an unknown field is an error: a download, `launch`, `bios`, `sync`,
  `depends`, `create_files` and a setting's `apply`. These decide what is downloaded, started and
  synced, where guessing would be unsafe. A new field there always comes with a new `needs` name.

## Versions

`version` is `major.minor.patch`. `depends` and revocations use ranges made of `=`, `>`, `>=`, `<`,
`<=` separated by spaces (`">=1.2.0 <2.0.0"`), or `*`.

## Ids are for ever

A system's `id` is the ROM folder name and the key of saves, states, cheats and settings. Changing
it would orphan the player's data, so it never changes; neither does a plugin's `id`.
