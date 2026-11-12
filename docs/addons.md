# Switch 2 add-ons

An add-on is a `.emuaddon` file: a zip with `addon.json` at its root and the folders of an
ordinary mod. Add-ons are data. They hold no programs and no scripts.

```
addon.json
exefs/  romfs/  romfslite/  romfs_ext/  cheats/
icon.png, screenshots/*.png          optional
```

EmuDEN installs it as `<mod folder>/<title id>/<add-on id>/`, where the emulator already reads
those folders.

## `addon.json`

```json
{
  "addon_version": 1,
  "id": "jdoe.oot-hd-text",
  "name": "HD text",
  "version": "1.0.0",
  "summary": "Sharper menu text.",
  "authors": ["jdoe"],
  "program_id": "0400486024DEC000",
  "needs": [],
  "layers": [{ "type": "romfs", "dir": "romfs" }]
}
```

| Field | Required | Meaning |
|---|---|---|
| `addon_version` | yes | 1 |
| `id` | yes | Like a plugin id: `<your GitHub name>.<name>` |
| `name`, `version`, `program_id` | yes | `program_id` is the game's 16 hex digits |
| `needs` | yes | Empty for file mods |
| `layers` | yes | One entry per folder: `{"type": "romfs", "dir": "romfs"}`. `type` is `exefs`, `romfs`, `romfslite`, `romfs_ext` or `cheats`, and `dir` is the same word |
| `summary`, `authors` | no | Shown in the list |
| `builds` | no | `[{"module": "main", "build_id": "<40 hex>", "game_version": "1.0.0"}]` when the add-on fits one version of the game |
| `default_enabled` | no | `false` installs it switched off |
| `order` | no | Lower applies first; 500 when missing |

`schema/addon.schema.json` also describes `nso-patch` and `transform` layers. EmuDEN does not
install those yet: a package with one is listed as "Needs a newer EmuDEN".

A package may hold nothing else at its root, no links and no paths that leave it.

## Listing add-ons: `addons.json`

```json
{
  "catalogue_version": 1,
  "titles": [{ "program_id": "0400486024DEC000", "name": "The Legend of Zelda: Ocarina of Time" }],
  "addons": [{
    "id": "jdoe.oot-hd-text", "name": "HD text", "version": "1.0.0",
    "summary": "Sharper menu text.", "authors": ["jdoe"], "tags": ["graphics"],
    "program_id": "0400486024DEC000", "needs": [], "layer_types": ["romfs"],
    "package": { "url": "packages/jdoe.oot-hd-text-1.0.0.emuaddon", "sha256": "<64 hex>", "size": 2104 }
  }]
}
```

`package.url` is a path beside `index.json` or an `https://` address. `sha256` and `size` are
those of the `.emuaddon` file; EmuDEN refuses a download that differs. `plugin_tool.py index`
records the checksum of `addons.json` in the signed `index.json`, so run it again after every
change to the list.

## In EmuDEN

A Switch 2 game's details page has "Add-ons", and so has Settings, Consoles, Nintendo Switch 2.
Installed lists the add-ons that come with EmuDEN, the installed packages and the mods copied in
by hand, each with on or off; a package can also be moved up or down, updated and removed. Later
add-ons win where two change the same file. Browse lists what your plugin sources offer for the
game. "Install from a file" takes a `.emuaddon` from the device.
