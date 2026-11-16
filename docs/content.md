# Which files are games

`systems[].content` tells the library scanner what belongs to the console.

| Field | Default | Meaning |
|---|---|---|
| `extensions` | `[]` | Lower case, without the dot |
| `compound_extensions` | `[]` | Checked first: `p8.png` |
| `folder_aliases` | `[]` | Folder names besides the system id (`"wii u"` for `wiiu`); case and spacing do not matter |
| `folder_only_extensions` | `[]` | Extensions that count only inside the console's folder (`md` is far more often Markdown than a Mega Drive ROM) |
| `zip` | `unpack` | `unpack`: a zipped game is unpacked for the emulator. `pass`: the emulator gets the zip. `no`: zips are not games |
| `multi_file` | none | Disc games, below. Needs `content.multi_file` |
| `magic` | `[]` | `[{"offset": 28, "bytes": "C2339F3D"}]`: bytes that tell whose file a shared extension is. Read and checked today; the scanner does not use it yet. Needs `content.magic` |
| `header_title` | `[]` | `[{"offset": 308, "length": 16}]`: where the ROM header holds the game's name; the first that is not empty is used |
| `hash_variants` | `[]` | `[{"skip_bytes": 16, "min_size": 17}]`: also look the game up by its checksum without a header. Not read yet |
| `cover_is_rom` | false | The file is its own picture (PICO-8 carts) |

## How a file finds its console

1. A file inside `roms/<system id>/` or one of its aliases belongs to that console when it has one
   of its extensions.
2. A file anywhere else belongs to the console that is the only one with its extension. An
   extension two consoles share (`iso`, `chd`, `bin`) names nobody outside a system folder, and
   `folder_only_extensions` never do.

Keep `id` and the aliases stable: the folder name is how players' games are found, and the id is
the key of their saves.

## Disc games

```json
"multi_file": { "index": ["cue", "m3u", "chd"], "members": ["bin"],
                "loose_members": true, "track_naming": "redump" }
```

The index file is the game; the files it names are not listed beside it. With `loose_members` a
member without an index is a game too (a `.bin` without its cue sheet still plays). `track_naming`
picks one of EmuDEN's own rules for "(Track 2)" files; `redump` is the only one. Manifests cannot
supply patterns of their own.
