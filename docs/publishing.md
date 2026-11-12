# Publishing a source

A source is a GitHub repository with this folder's layout. EmuDEN reads plain files from it and
never calls the GitHub API.

```
index.json            the list of plugins (generated)
index.json.sig        its signature (generated)
keys/source.pub       your public key
plugins/<id>/plugin.json, icon.png, assets/...
packages/<id>-<version>.emuplugin
tools/plugin_tool.py
```

## Once: make a key

```
python -I tools/plugin_tool.py keygen --key /somewhere/safe/source.key
```

This writes the private key to the file you name and the public key to `keys/source.pub`. Commit
the public key. Keep the private key out of the repository and out of CI secrets: whoever holds it
can publish programs to everyone who added your source. `keygen` and `sign` need the `openssl`
command.

## Every release

```
python -I tools/plugin_tool.py validate --all
python -I tools/plugin_tool.py index --name "My consoles" --sequence 2 --days 90
python -I tools/plugin_tool.py sign --key /somewhere/safe/source.key
python -I tools/plugin_tool.py verify
```

- `validate` runs the checks the app runs.
- `index` packs each plugin into `packages/` and writes `index.json` with every package's size and
  checksum. `--sequence` must be higher than last time: EmuDEN refuses a list older than the one it
  has seen. `--days` is how long the list stays valid, 120 at most; publish a fresh one before it
  runs out, or installs stop until you do.
- `sign` writes `index.json.sig` over the exact bytes of `index.json`. Do not edit the list
  afterwards, and keep `.gitattributes` so git does not change its line endings.
- Commit `index.json`, `index.json.sig` and `packages/`. Packages may also be release assets: put
  the full `https://github.com/<owner>/<repo>/releases/download/...` address in the index.

A package holds `plugin.json`, `icon.png`, `assets/`, `LICENSE*` and `README*` and nothing else. A
program or a script in it is refused.

## How players add it

They type `owner/repo` (or `owner/repo@branch`) under Plugin sources. EmuDEN shows the key's
fingerprint, the first 16 hex digits of the SHA-256 of the public key, for example
`3fa9 12c4 77e0 b5d1`. Publish yours where players can compare it, or hand out
`owner/repo#3fa912c477e0b5d1`, which only adds the source when the key matches. In EmuDEN your
source is called by its address (`owner/repo`), not by the name your list gives itself.

## The namespace rule

A source publishes plugins whose id starts with its owner's GitHub name in lower case:
`jdoe/consoles` publishes `jdoe.*`. `emuden.*` belongs to EmuDEN.

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
