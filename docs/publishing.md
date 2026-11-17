# Publishing a source

A source is a GitHub repository with this folder's layout, or an https address serving the same
files. EmuDEN reads plain files from it and never calls the GitHub API.

```
index.json            the list of plugins (generated)
index.json.sig        its signature (generated)
keys/source.pub       your public key
plugins/<id>/plugin.json, and the plugin's other files
packages/<id>-<version>.emuplugin
tools/plugin_tool.py, tools/plugin_*.py, schema/
```

## Once: make a key

```
python -I tools/plugin_tool.py keygen --key /somewhere/safe/source.key
```

This writes the private key to the file you name and the public key to `keys/source.pub`. Commit
the public key. Keep the private key out of the repository and out of CI secrets: whoever holds it
can publish to everyone who added your source. `keygen` and `sign` use the Python package
`cryptography` when it is installed (`pip install cryptography`), else the `openssl` command
(OpenSSL 3).

## Every release

```
python -I tools/plugin_tool.py validate --all
python -I tools/plugin_tool.py test
python -I tools/plugin_tool.py index --name "My plugins" --sequence 2 --days 90
python -I tools/plugin_tool.py sign --key /somewhere/safe/source.key
python -I tools/plugin_tool.py verify
```

- `validate` runs the checks the app runs, and warns about fields the app does not read yet.
- `test` runs the offline Lua tests of your feature plugins (`tests/<id>/*test.lua`).
- `index` packs each plugin into `packages/` and writes `index.json` with every package's size and
  checksum. `--sequence` must be higher than last time: EmuDEN refuses a list older than the one it
  has seen. `--days` is how long the list stays valid, 120 at most; publish a fresh one before it
  runs out, or installs stop until you do.
- `sign` writes `index.json.sig` over the exact bytes of `index.json`. Do not edit the list
  afterwards, and keep `.gitattributes` so git does not change its line endings.
- Commit `index.json`, `index.json.sig` and `packages/`. Packages may also be release assets: put
  the full `https://github.com/<owner>/<repo>/releases/download/...` address in the index.

## What a package may hold

| Kind | Files | Limits |
|---|---|---|
| `console` | `plugin.json`, `icon.png`, `assets/`, `LICENSE*`, `README*` | 256 files, 16 MiB |
| `feature` | `.json`, `.lua`, `.png`, `.jpg`, `.txt`, `.md` (shared libraries named in `.shared` are copied in) | 200 files, 8 MiB |
| `interface` | `.json`, `.png`, `.jpg`, `.txt`, `.md` | 200 files, 8 MiB |

Programs are refused in every kind, by name and by content, and so is compiled Lua. A console's
cores and engine apps are not in the package: they are pinned downloads the manifest names.

The index entry of a feature plugin carries its permissions, hosts and systems, so EmuDEN shows
what it asks for before anything is downloaded.

## How players add it

They type `owner/repo` (or `owner/repo@branch`, or an https address) under Settings > Plugins >
Add a source. EmuDEN shows the key's fingerprint, the first 16 hex digits of the SHA-256 of the
public key, for example `3fa9 12c4 77e0 b5d1`. Publish yours where players can compare it, or hand
out `owner/repo#3fa912c477e0b5d1`, which only adds the source when the key matches. In EmuDEN your
source is called by its address (`owner/repo`), not by the name your list gives itself.

## What an added source may publish

| | Rule |
|---|---|
| Ids | Start with the source's namespace: the owner's GitHub name in lower case (`jdoe/consoles` publishes `jdoe.*`), or the host name of an https source. `emuden.*` belongs to EmuDEN |
| Consoles | The `libretro` engine only, no `scanner`, no `@firmware` BIOS entries; engine apps in the source's namespace ([engines.md](engines.md#the-namespace-rule)). A console that an official plugin already offers stays the official one |
| Feature plugins | Any permission except `downloads.watch`, `browse.any`, `downloads.setup` and `achievements`, and named `systems` only (not `["*"]`): those are EmuDEN's own. The player agrees to the permissions before install and again when an update asks for more |
| Interface plugins | Anything the format has: they hold no code and ask for nothing |

When two sources publish the same id, the source the player added first is used. Only a plugin's
own source updates it.

## Taking a plugin back

Add it to `revoked` in `index.json` before signing:

```json
"revoked": [{ "id": "jdoe.wiiu-cemu", "versions": "<1.0.2", "reason": "Deletes saves" }]
```

Installed copies in that range are switched off and say why. `blocked_sha256` does the same for a
download by its checksum.

## Changing the key

Players pinned your key when they added the source. A list signed with another key is refused, so
a new key means asking them to remove and add the source again.

If a source's key leaks, EmuDEN can withdraw it through `revoked_keys` (fingerprints) in its own
index: nothing signed with that key loads any more, and it cannot be added again.
