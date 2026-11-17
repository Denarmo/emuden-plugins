# Español

EmuDEN in Spanish: every text of the app (menus, settings, dialogs, messages). Choose it under
Settings, Language, or accept the offer EmuDEN makes at the first start when the system speaks
Spanish. Removing the plugin brings English back.

The games follow it too: a console whose core has a language option (Nintendo DS, for one) is
started in Spanish, unless you picked a language for that core yourself.

`strings.json` holds the texts by key. A key is a dotted name (`common.ok`) or the English text
itself (`Check for updates`); a text missing here stays English. Keep the `{}` fields of the
English text, in any order the sentence needs. `python -I tools/plugin_tool.py validate` checks it.
