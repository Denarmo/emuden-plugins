# Themes

An interface plugin can bring colour themes for the whole of EmuDEN: every page, row, dialog
and the selection border. The user picks one under Settings > Display ("Theme"), beside the
app's own Light, Dark and others. Like the rest of an interface plugin it is data only and
asks for no permission. Sizes, fonts and spacing stay the app's.

```json
{
  "manifest_version": 1,
  "id": "jdoe.dusk",
  "name": "Dusk",
  "version": "1.0.0",
  "kind": "interface",
  "publisher": "J. Doe",
  "license": "MIT",
  "summary": "A warm dark theme.",
  "api": 1,
  "needs": ["kind.interface", "themes.1"],
  "icon": "icon.png",
  "themes": [
    { "id": "dusk", "name": "Dusk",
      "colors": { "page": "#1f1015", "fg": "#ffe8d9", "text_dim": "#dba996",
                  "dialog": "#2e1920", "accent": "#ff8a4c" } }
  ]
}
```

Each entry of `themes` (at most 24) has:

| Field | Meaning |
|---|---|
| `id` | `a-z`, `0-9`, `-`, `_`, up to 32; each once in the plugin. |
| `name` | Up to 40 characters: what the theme picker lists. |
| `colors.page` | The page background (opaque; an alpha is ignored). Required. |
| `colors.fg` | Text and icons, and the base of the tints below. Required. |
| `colors.text_dim` | Secondary text. Default: `fg` at 62 %. |
| `colors.panel` | The soft tint of tiles, rows and the rail. Default: `fg` at 7 %. |
| `colors.panel_strong` | Pressed and filled parts, slider tracks. Default: `fg` at 16 %. |
| `colors.scrim` | Behind dialogs. Default: `#00001478`. |
| `colors.dialog` | The opaque dialog and toast surface. Default: `page`. |
| `colors.accent` | The selection border, the only place the accent is drawn. Default: EmuDEN's green. |

Colours are `#rrggbb` or `#rrggbbaa`.

Text must be readable: EmuDEN leaves out a theme whose `fg` or `text_dim` (blended onto the
page by its alpha) is under 4.5:1 contrast on `page`, and `plugin_tool.py validate` refuses it.
Aim for 4.5:1 for `fg` on `dialog` and 3:1 for `accent` on `page` too.

The setting `ui.theme` holds `<plugin>/<id>` for a plugin's theme. When that plugin is removed
EmuDEN shows Light, and the theme comes back if the plugin does. Tapping a themes-only plugin
on the Plugins screen opens Settings > Display. An EmuDEN older than `themes.1` refuses the
plugin.
