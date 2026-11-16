# Compatibility

Three fields decide whether a copy of EmuDEN can use a plugin.

| Field | Meaning | When it does not fit |
|---|---|---|
| `manifest_version` | The file format: 1 | "Needs a newer EmuDEN" |
| `api` | The lowest host API the plugin works with: 1 | "Needs a newer EmuDEN" |
| `needs` | The host features the plugin uses | "Needs a newer EmuDEN", naming the feature |

## Capabilities

The names `needs` may hold are listed, with what each means, in
[`schema/capabilities.json`](../schema/capabilities.json). That file is a copy of
`contracts/capabilities.json` in the EmuDEN repository, whose tests check it against the app;
`plugin_tool.py` reads it. Today:

| Capability | For |
|---|---|
| `engine.libretro` | every console (`engine.switch2` is EmuDEN's own) |
| `settings.v1` | a console with `settings` |
| `content.multi_file`, `content.magic` | a console using those `content` fields |
| `presentation.buttons` | `presentation.buttons` |
| `core.engine-app.1` | a core of type `engine-app` |
| `kind.feature`, `feature.lua.1` | every feature plugin |
| `feature.web.1` | the `browse` permission |
| `feature.tune.1` | `device.info`, `game.settings`, `steam` |
| `feature.achievements.1` | `achievements` (EmuDEN's own plugins only) |
| `feature.browser.1` | `browse.any`, `downloads.setup` (EmuDEN's own plugins only) |
| `kind.interface`, `interface.1` | every interface plugin |

A plugin must list the engine it uses, `settings.v1` when it has settings, the `content.` name
of each of those content fields it uses, and the capability of each permission (EmuDEN refuses a
feature plugin with a permission whose capability is missing). List `presentation.buttons` and
`core.engine-app.1` too when you use them, so an older EmuDEN refuses the plugin instead of
showing it half-working. New features get new names; an older EmuDEN then says so instead of
misreading the plugin.

`platforms` says where a console plugin works. Elsewhere its console has no core to install.

## Unknown fields

- In most places an unknown field is ignored, so a newer manifest still loads in an older EmuDEN.
  Fields the schema has but this EmuDEN ignores are listed in
  [manifest.md](manifest.md#fields-not-read-yet); `validate` warns about them.
- In the **strict objects** an unknown field is an error: a download, `depends` and a setting's
  `apply` in the app, and `bios` in `plugin_tool.py`. These decide what is downloaded, started
  and applied, where guessing would be unsafe. A new field there always comes with a new `needs`
  name.

## Versions

`version` is `major.minor.patch`. `depends` and revocations use ranges made of `=`, `>`, `>=`, `<`,
`<=` separated by spaces (`">=1.2.0 <2.0.0"`), or `*`.

## Ids are for ever

A system's `id` is the ROM folder name and the key of saves, states, cheats and settings. Changing
it would orphan the player's data, so it never changes; neither does a plugin's `id`.
