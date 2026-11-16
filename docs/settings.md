# Settings

A console plugin describes its console's settings; EmuDEN draws the rows on the console's page
(Settings > Consoles > the console), stores the values and hands them to the core. Needs
`"settings.v1"` in `needs`.

```json
"settings": [
  { "key": "fast_boot", "label": "Skip the boot logo", "type": "toggle", "scope": "console",
    "section": "System", "default": true, "when_core": "swanstation",
    "apply": { "core_option": "swanstation_BIOS_PatchFastBoot", "map": { "true": "true", "false": "false" } } }
]
```

| Field | Required | Meaning |
|---|---|---|
| `key` | yes | `^[a-z][a-z0-9_]{0,47}$`, unique in the plugin |
| `label`, `help` | label | A setting without a label is not shown |
| `section` | no | The heading it is shown under on the console's page; without one, "Settings" |
| `type` | yes | `toggle`, `choice`, `range`, `text`, `path` |
| `choices` | choice | `[{"value": "...", "label": "..."}]` |
| `min`, `max`, `step`, `suffix` | range | |
| `path_kind` | path | `file` or `folder`. A path is chosen by the player on their device: its `default` must be `""` |
| `default` | yes | |
| `scope` | yes | `console`. `game` is accepted but not read yet: the value is the console's |
| `systems` | no | The systems of the plugin it is shown for; default all |
| `platforms` | no | The platform keys it is shown on; default all |
| `when_core` | no | A component id: shown, and applied, only while that core plays the console |
| `live` | no | Not read yet (the pause menu does not show plugin settings) |
| `inherit` | no | Not read yet |
| `apply` | yes | One of the forms below; unknown keys are errors |

## `apply`

| Form | Read | Effect |
|---|---|---|
| `{"core_option": "<key>", "map": {"true": "enabled", "false": "disabled"}}` | yes | The value goes to that core option when a game starts (for an engine app: to that engine setting). `map` turns the stored value into the option's; a value it does not list is passed as it is |
| `{"core_option_contains": "screen_layout"}` | not yet | Meant for the first option of the running core whose key contains the text |
| `{"player": "<key>"}` | not yet | Meant for one of the player's own settings |
| `{"native_setting": "<key>"}` | not yet | EmuDEN's own Switch 2 engine |

## Which value wins

For a core option: the player's own value for that option (set in the game's core options),
then the console's value from this setting, then the component's `forced_core_options`, then the
core's default. A setting's own value is the console's, else its `default`.

## Where values are kept

In EmuDEN's settings file, as `console.<system id>.<key>` (`true`/`false` for a toggle, the number
for a range).
