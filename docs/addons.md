# Switch 2 add-ons

An add-on is a `.emuaddon` file: a zip with `addon.json` at its root and the folders of an
ordinary mod. Add-ons are data. They hold no programs and no scripts.

```
addon.json
exefs/  romfs/  romfslite/  romfs_ext/  cheats/
blobs/*.bin                          bytes of code patches
font/, data/                         inputs of transforms
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
| `needs` | yes | Empty for file mods; see the layers below |
| `layers` | yes | One entry per folder: `{"type": "romfs", "dir": "romfs"}`. `type` is `exefs`, `romfs`, `romfslite`, `romfs_ext` or `cheats`, and `dir` is the same word. Or a `nso-patch` or `transform` layer |
| `legacy_name` | no | The name the add-on was switched off under before it had an id |
| `replaces` | no | Ids of add-ons that are skipped once this one is applied |
| `enable_when` | no | `{"setting": "aspect_ratio", "not_in": ["16:9", "window"]}`: applied only while the Aspect Ratio setting is none of these (`16:9`, `4:3`, `21:9`, `16:10`, `window`) |
| `summary`, `authors` | no | Shown in the list |
| `builds` | no | `[{"module": "main", "build_id": "<40 hex>", "game_version": "1.0.0"}]` when the add-on fits one version of the game |
| `default_enabled` | no | `false` installs it switched off |
| `order` | no | Lower applies first; 500 when missing |

A package may hold nothing else at its root, no links and no paths that leave it.

## Code patches: `nso-patch`

Byte patches to one build of one module of the game. `needs` lists `addon.code_patch`.

```json
{ "type": "nso-patch", "module": "main",
  "build_id": "E0F3CCFAF50065AE4EA01EB5AEB13B1A45DA3348",
  "state": { "offset": "0x4E9FE00", "size": 16, "expect": "zero-bss" },
  "records": [
    { "offset": "0x6E6CC4", "bytes": "4F7DD594", "expect_bytes": "2818201E" },
    { "offset": "0x3C46200", "bytes_file": "blobs/03C46200.bin", "expect": "zero-exec-padding" }
  ],
  "literals": [{ "offset": "0x3C462A8", "type": "f32", "from": "scene_aspect" }] }
```

| Field | Meaning |
|---|---|
| `module`, `build_id` | The module (`main`, `subsdk0`, ...) and its build id. The game log's `Patching NSO for name=main, build_id=...` line shows it |
| `records[].offset` | Offset in the module, after its header, as a hex string |
| `records[].bytes` or `bytes_file` | The new bytes as hex, or a file in `blobs/` |
| `records[].expect_bytes` | The bytes the game has there; anything else skips the add-on |
| `records[].expect` | `zero-exec-padding`: the range is empty space after the code, before the next page. `zero-bss`: it is zero-filled BSS |
| `state` | A range of BSS the patch uses as memory; it must be zero-filled |
| `literals` | A 32-bit float written after the records. `scene_aspect` is the Aspect Ratio setting as width / height, and needs `addon.literal.scene_aspect`; the add-on is skipped while that setting is 16:9 or the window's |

All records of a layer apply or none. A layer is skipped, with the reason in the log
(`Skipping add-on "<name>": ...`), when the add-on is off, an applied add-on replaces it, the
build id differs, `enable_when` does not hold, a check above fails or another patch already
changed the same bytes.

## Transforms: `transform`

A change to one file of the game that EmuDEN computes, so that the package does not carry the
game's file. One exists: `bfotf_add_glyphs` (needs `addon.transform.bfotf_add_glyphs`) adds
glyphs to Ocarina of Time's interface font.

```json
{ "type": "transform", "transform": "bfotf_add_glyphs",
  "target": "romfs:/Font2/Scalable/External.Nin_Ounce_NVN2.bfotf.zs",
  "glyphs_file": "font/glyphs.json", "charstrings_file": "font/charstrings.bin" }
```

`font/glyphs.json` is `{"glyphs": [{"codepoint": "0xE144", "advance": 720, "lsb": 55,
"offset": 0, "size": 364}]}`: each glyph's code point, metrics and where its Type 2 charstring
lies in `charstrings.bin`. One add-on changes the font: the first in the list, and none while
the built-in Controls add-on is on or a mod replaces the font file.

## Publishing an add-on

1. Put the folder at `addons/<program id>/<add-on id>/` with `addon.json` in it.
2. The first time for a game, add it to `titles` in `addons.json`. `tags` of an entry are kept
   when you edit them there.
3. `python -I tools/plugin_tool.py validate addons/<program id>/<add-on id>`
4. `python -I tools/plugin_tool.py index --sequence <next>` packs every add-on into
   `packages/<id>-<version>.emuaddon` and rewrites its entry in `addons.json`; then `sign`.
5. Commit `addons/`, `packages/`, `addons.json`, `index.json` and `index.json.sig`.

`pack addons/<program id>/<add-on id>` writes one package without touching the lists, for
"Install from a file".

The eight Ocarina of Time add-ons that are part of EmuDEN are listed the same way
(`emuden.oot.*`). EmuDEN still applies them itself; installing the package marks them as
provided by it. Their folders are written by `tools/nx2/oot_controls/gen_package.py` in the
EmuDEN source tree.

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

A Switch 2 game's details page has "Add-ons", and so has Settings > Consoles > Nintendo Switch 2.
Installed lists the add-ons that come with EmuDEN, the installed packages and the mods copied in
by hand, each with on or off; a package can also be moved up or down, updated and removed. Later
add-ons win where two change the same file. Browse lists what your plugin sources offer for the
game, each with its version, the game build it is for and Install, Update or Remove. "Install
from a file" takes a `.emuaddon` from the device. The Add-Ons tab of a game's properties has
"Get more add-ons", which opens the same screen.
