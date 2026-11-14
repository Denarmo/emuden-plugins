# Interface plugins

An interface plugin changes how EmuDEN's Home screen looks. It is data only: a `plugin.json`
of kind `interface` and the pictures it names. EmuDEN draws it with one of its own layouts; the
plugin picks the layout and sets its colours, art and motion. It runs nothing and asks for no
permission, so installing one from any source you added is safe in the same way as a theme.

The user picks it under Settings, Interface ("Home interface"). EmuDEN's standard Home stays the
default and is always one choice away. An interface listed by a source can be picked before it
is installed: EmuDEN downloads it first.

## The manifest

```json
{
  "manifest_version": 1,
  "id": "jdoe.neon-shelf",
  "name": "Neon Shelf",
  "version": "1.0.0",
  "kind": "interface",
  "publisher": "J. Doe",
  "license": "CC-BY-4.0",
  "summary": "Dark tabs, bright covers.",
  "api": 1,
  "needs": ["kind.interface", "interface.1"],
  "interface": {
    "layout": "carousel",
    "icon": "icon.png",
    "colors": { "background": "#0b0b12", "text": "#ffffff", "dim": "#a0a0b8",
                "accent": "#ff3fa4", "panel": "#ffffff20" },
    "backdrop": { "art": "console", "tint": 0.4, "wallpaper": "art/back.jpg" },
    "covers": { "height": 0.62, "side_scale": 0.72, "side_dim": 0.45, "spacing": 28,
                "reflection": 0.18, "bob": 4, "speed": 12 },
    "tabs": { "recent": true, "all": true },
    "launch": { "animation": "zoom", "seconds": 0.32 },
    "consoles": {
      "*": { "color": "#4a4f66" },
      "group:nintendo": { "color": "#c8323c" },
      "gba": { "color": "#5440a6", "label": "GBA", "wallpaper": "art/gba.jpg" }
    }
  }
}
```

Every field of `interface` is optional; anything missing or out of range takes the default.

| Field | Meaning |
|---|---|
| `layout` | The layout that draws it. `carousel`: consoles as tabs along the top (L and R step through them), one row of covers that glides, the selected one large in the middle, and its name and records under it. An EmuDEN without the layout refuses the plugin and keeps its own Home. |
| `icon` | A PNG of the package, shown in the plugin list. |
| `colors` | `#rrggbb` or `#rrggbbaa`. `background` behind everything, `text`, `dim` (secondary text), `accent` (used when a console has no colour), `panel` (tabs and buttons). |
| `backdrop.art` | `cover`: the selected game's cover, blurred. `console`: the console's wallpaper, else the package's `wallpaper`. `plain`: the background colour only. |
| `backdrop.tint` | 0 to 1: how much of the console's colour washes over the backdrop. |
| `covers` | `height` (0.3 to 0.9 of the row), `side_scale` (0.4 to 1), `side_dim` (0 to 0.9), `spacing` (0 to 120), `reflection` (0 to 0.6, 0 = none), `bob` (0 to 16: how far the selected cover floats), `speed` (4 to 40: how fast the row glides). |
| `tabs` | `recent`: a Recent tab first when something was played. `all`: an All tab with every game. |
| `launch` | `animation`: `zoom` (the cover grows into the console's colour before the game starts) or `none`; `seconds` 0.1 to 1. |
| `consoles` | By system id (`gba`), by group (`group:nintendo`), or `*`. `color`, `label` (up to 16 characters on the tab; else the console's short name) and `wallpaper` (a PNG or JPEG of the package). The tabs Recent and All are looked up as `recent` and `all`. |

Pictures are paths inside the package: no `..`, no leading slash. A package holds `.json`,
`.png`, `.jpg`, `.txt` and `.md` files only, at most 200 files and 8 MiB.

## Controls

The layouts are made for a pad first. In `carousel`: Left and Right move along the row, L and
R change console, Up reaches the tabs and the other screens (Library, Search, Settings...),
Confirm starts the game, the Details and Favourite buttons of the hint bar work as on EmuDEN's
own Home, and Start opens Settings. On a touch
screen a tap on a side cover selects it, a swipe beside the selected cover scrolls the row and
a tap on the selected cover starts it. On a device with a second screen, that screen shows the
selected game's page as with EmuDEN's own Home.

## Publishing

Interface plugins are published like any other: `validate`, `index`, `sign`, `verify`
(`publishing.md`). A third-party source's interfaces use its namespace (`jdoe.*`); `emuden.*`
is EmuDEN's. Don't use other launchers' or console makers' logos, names or artwork unless you
have the right to.

## New layouts

A layout is code in EmuDEN (`app/screens/interface/`), so a new one comes with an EmuDEN
release and a new value for `layout`. Ask for one in an issue with what it should show; the
data a plugin can give stays the same across layouts where it can.
