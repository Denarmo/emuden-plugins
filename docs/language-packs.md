# Language packs

A language pack is an interface plugin that holds the app's texts in one language. English is
built into EmuDEN; every other language is a pack that the player downloads, from EmuDEN's own
source or from one you publish.

```
plugins/jdoe.lang-pt-br/
  plugin.json
  strings.json
  icon.png         optional
```

```json
{
  "manifest_version": 1,
  "id": "jdoe.lang-pt-br",
  "name": "Português (Brasil)",
  "version": "1.0.0",
  "kind": "interface",
  "publisher": "J. Doe",
  "license": "GPL-3.0-or-later",
  "api": 1,
  "needs": ["kind.interface", "languages.1"],
  "language": { "code": "pt-BR", "name": "Português (Brasil)" }
}
```

`code` is a language code (`es`, `pt-BR`, `zh-TW`) and `name` the language's own name, which the
language list shows. `en` is refused. The index entry carries both, so EmuDEN can offer the pack
at the first start when the system speaks that language (the exact code first, else the same
language: a `pt-PT` system is offered `pt-BR` when that is all there is).

## strings.json

One object of texts by key:

- **Dotted keys** (`common.ok`, `setup.welcome`) are the app's named texts; the English ones are
  in `assets/strings/en.json` of the EmuDEN repository.
- **English texts** (`"Check for updates"`, `"Saved to slot {}"`) are texts the app has in its code;
  the English text is the key.

A text the pack lacks stays English. The `{}` fields of the English text must be in the
translation, as many and in any order the sentence needs (`"{} de {}"`); a text that does not
match is ignored by the app and refused by `validate`. `python -I tools/plugin_tool.py validate`
checks that, and `python tools/extract_strings.py --missing strings.json` in the EmuDEN repository
lists the English texts a pack has not translated yet.

## plugin_strings.json

Optional: texts for other plugins, by plugin id, so a pack can translate a plugin that has no
translation of its own in that language (or reword one it has):

```json
{
  "emuden.sync.gdrive": { "Sign in with Google": "Entrar con Google" },
  "jdoe.hello-feature": { "Say hello": "Saludar", "{} saves": "{} partidas" }
}
```

Keys are the plugin's English texts (its manifest's names, labels and descriptions, and what its
script passes to `den.tr`). A pack's text wins over the plugin's own; the same `{}` rule applies.

## Plugins' own translations

Every plugin can carry its texts in other languages itself, without a pack: see
[translations](manifest.md#translations). Those apply whenever the app is in that language,
whichever pack is installed.

## Games

The app's language also reaches the games:

- A core that asks the frontend for its language (libretro `GET_LANGUAGE`) is told it.
- A console plugin can name a core's language option and its values: see `language` in
  [manifest.md](manifest.md). The player's own choice for that option always wins.
