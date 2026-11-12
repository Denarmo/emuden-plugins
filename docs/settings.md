# Settings

A plugin describes its console's settings; EmuDEN draws the rows, stores the values and hands them
to the core or the emulator. Needs `"settings.v1"` in `needs`.

```json
"settings": [
  { "key": "fullscreen", "label": "Start in fullscreen", "type": "toggle", "scope": "game",
    "default": true, "inherit": "video.fullscreen", "apply": { "args_if_true": ["-f"] } }
]
```

| Field | Required | Meaning |
|---|---|---|
| `key` | yes | `^[a-z][a-z0-9_]{0,47}$`, unique in the plugin |
| `label`, `help` | label | |
| `section` | no | Heading on the console's page |
| `type` | yes | `toggle`, `choice`, `range`, `text`, `path` |
| `choices` | choice | `[{"value": "...", "label": "..."}]` |
| `min`, `max`, `step`, `suffix` | range | |
| `path_kind` | path | `file` or `folder`. A path is chosen by the player on their device: its `default` must be `""` |
| `default` | yes | |
| `scope` | yes | `console`, or `game` (the console's value, which a game may override) |
| `live` | no | Also in the pause menu |
| `inherit` | no | A setting of EmuDEN used when neither the game nor the console has a value |
| `platforms`, `systems`, `when_core` | no | Where the row applies |
| `apply` | yes | One of the forms below; unknown keys are errors |

## `apply`

| Form | Engine | Effect |
|---|---|---|
| `{"core_option": "<key>", "map": {"true": "enabled", "false": "disabled"}}` | libretro | Sets a core option; `map` is optional |
| `{"core_option_contains": "screen_layout"}` | libretro | The first option of the running core whose key contains the text; its choices come from the core |
| `{"player": "<key>"}` | libretro | One of the player's own settings (`picture`, `fast_forward`, `run_ahead`, `screen_size`, `border`, `volume`, `mute_fast_forward`, `low_latency`) |
| `{"args": ["--flag={value}"]}` | external | Arguments added after the template's |
| `{"args_if_true": ["-f"]}`, `{"args_if_false": [...]}` | external | Arguments of a toggle |
| `{"env": "NAME"}` | external | An environment variable; names as in [engines.md](engines.md) |
| `{"launch_var": true}` | external | Only readable as `{setting:<key>}` in the template |

## Which value wins

The game's value, then the console's, then the EmuDEN setting named by `inherit`, then `default`.

## Where values are kept

In `<EdenDir>/emuden/player.ini`: group `plugin-<system id>` for the console, key `plugin/<key>` in
the game's group for a game. `path` values are kept on the device only (`local/plugins-local.ini`)
and never synced, so a synced file cannot change which program runs.
