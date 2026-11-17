# Quick settings layouts

While a game plays, EmuDEN's second screen (the lower screen of a dual-screen handheld, a
second window on a PC) shows the quick settings: pause, rewind, fast-forward, exit, the save
states with their pictures, the screen and picture, the apps, the volumes. An interface plugin
can offer other layouts for them. Like a Home interface ([interface-plugins.md](interface-plugins.md))
it is data only: EmuDEN draws one of its own layouts, and the plugin picks it, orders or hides
its actions and sets its colours. It runs nothing and asks for no permission.

The user picks one under Settings > Interface, "Quick settings layout", independently of the
Home interface. "EmuDEN (standard)" stays the default and is always one choice away. A plugin
listed by a source can be picked before it is installed: EmuDEN downloads it first and uses its
first layout. `plugins/emuden.quick-layouts` offers every layout below.

## The manifest

A plugin of kind `interface` with a `quick_settings` object and `quick_settings.1` in `needs`.
It may have a Home look (`interface`, with `interface.1`) too; one without `interface` is not
listed as a Home interface.

```json
{
  "manifest_version": 1,
  "id": "jdoe.big-buttons",
  "name": "Big Buttons",
  "version": "1.0.0",
  "kind": "interface",
  "publisher": "J. Doe",
  "license": "CC-BY-4.0",
  "summary": "Quick settings as big tiles.",
  "api": 1,
  "needs": ["kind.interface", "quick_settings.1"],
  "quick_settings": {
    "icon": "icon.png",
    "layouts": [
      { "id": "tiles", "name": "Tiles", "layout": "grid", "columns": 4,
        "actions": ["pause", "states", "exit"], "hidden": ["fps"],
        "colors": { "background": "#101218", "accent": "#4f8cff66" } },
      { "id": "list", "name": "List", "layout": "compact", "tile_size": 0.9 }
    ]
  }
}
```

Each entry of `layouts` is one choice in Settings ("Big Buttons: Tiles", "Big Buttons: List";
just the plugin's name when it has one). Without `layouts`, the fields of a layout go in
`quick_settings` itself and the plugin offers that one layout. Every field is optional; anything
missing or out of range takes the default.

| Field | Meaning |
|---|---|
| `icon` | A PNG of the package, shown in the plugin list (`quick_settings` only, not per layout). |
| `id` | The choice's id, `a-z`, `0-9`, `_` and `-`, up to 32 characters; the layout's name when missing. Each once per plugin: Settings remembers the choice by it. |
| `name` | Up to 40 characters; the layout's name ("Grid") when missing. |
| `layout` | `standard`: EmuDEN's own, a card with the cover, the play time and the controls (pause, rewind, fast-forward, exit), then one row per section. `grid`: big touch tiles, three to five a row by the screen's shape, the cover small in a corner. `compact`: one row per action with its icon, so more fits; the volume sliders inline; two columns on a wide screen. `dock`: the game's cover large with its newest save state, a bar of the first actions under it and "More" for the rest. `split`: the actions on one side and the state slots (with Load and Save) on the other; on an upright screen the slots go below. A choice whose layout this EmuDEN does not have is not listed. |
| `colors` | `#rrggbb` or `#rrggbbaa`: `background`, `text`, `dim` (secondary text), `panel` (tiles and rows), `accent` (what is on or chosen: rewinding, a toggle that is on). Only for this page; missing ones are the app's theme, which may be light or dark, so set `text` and `dim` with `background`. |
| `actions` | The order: these ids first, then the layout's others in its own order. Ids this EmuDEN does not know are skipped. |
| `hidden` | Ids never shown. Hiding `exit` or `pause` leaves them in the pause menu of the main screen. |
| `tile_size` | 0.75 to 1.5: the tiles and rows larger or smaller. |
| `columns` | `grid`: 2 to 6 tiles a row; 0 (the default) picks by the screen's shape. |
| `dock` | `dock`: 3 to 7 actions in the bar (5). |
| `cover` | `false` leaves the game's cover out. |

## Actions

| Id | What it is |
|---|---|
| `pause` | Pause (or Resume): the pause menu on the main screen. |
| `rewind`, `fast_forward` | On or off; only with a core that can. |
| `exit` | Saves and leaves the game. |
| `states` | The ten state slots with their pictures, to load or save. In `split` it is the half with the slots. |
| `screen` | Screen and picture: the size, the picture presets as a carousel of previews, Swap screens, the frame rate counter, widescreen. |
| `swap` | Swap screens: the game on the second display, the settings on the main one. |
| `fps` | The frame rate counter: off, on, with a graph. |
| `bfi` | Black frame insertion, or why it cannot be had. |
| `controls` | Controls and core: a section with Core options and Buttons. |
| `options`, `buttons` | Those pages of the pause menu, directly. |
| `cheats` | The game's cheats, in EmuDEN versions that have them. |
| `apps` | Other apps, beside the game. |
| `volume` | The game's volume (and the system's while an app plays beside it). Sliders in a list; a tile opens them. |

An action is only shown while it applies (rewind needs a core that rewinds, swap a second
display). The default orders: `standard` pause, rewind, fast_forward, exit, states, screen,
bfi, controls, cheats, apps, volume. `grid`, `compact` and `split` pause, rewind,
fast_forward, exit, states, screen, swap, fps, bfi, options, buttons, cheats, apps, volume.
`dock` the same with states before exit, so the bar holds pause, rewind, fast_forward,
states, exit.

Every layout is used by touch and fits any shape of screen: EmuDEN lays the page out in units
600 high and as wide as the screen's shape makes it, and builds it again when that shape
changes (a window resized, the settings swapped to the main display).

## Checking it

`python -I tools/plugin_tool.py validate <folder>` checks `quick_settings` against the schema
and that each choice's id is used once. Try it from the developer folder like any interface
plugin ([getting-started.md](getting-started.md#an-interface-plugin)).

## New layouts

A layout is code in EmuDEN (`app/screens/companion/`), so a new one comes with an EmuDEN
release and a new value for `layout`. The actions and fields above stay the same across them.
