# Sync: RomM (`emuden.sync.romm`)

A sync provider for EmuDEN (`docs/sync.md` section 7.2 of the app). Saves and save states go to
the user's own [RomM](https://github.com/rommapp/romm) server, and the server's ROMs can be
downloaded into the library. EmuDEN's sync engine decides what moves and when; the plugin
only lists, fetches, stores and deletes files on the server.

Checked against RomM **5.4.1** (tag `5.4.1`, commit `9c74d01`). Older servers are refused with
a message; the version comes from `GET /api/heartbeat` (`SYSTEM.VERSION`).

## Setup

1. The user enters the server address (`http://host:port`); the app asks them to confirm it
   (`den.sync.set_server`, permission `http.user_host`).
2. They sign in with their RomM user. The password goes once to `POST /api/token`
   (`grant_type=password`, scopes `me.read roms.read platforms.read assets.read
   assets.write`) and is not kept. The refresh token is kept in `den.secrets`; RomM's refresh
   tokens are single use, so every refresh stores the new one. By default RomM lets a refresh
   token live 7 days (`OAUTH_REFRESH_TOKEN_EXPIRE_SECONDS`): a device that does not sync for
   longer has to sign in again.

## Names

| EmuDEN | RomM |
|---|---|
| `saves/<system>/<stem>.<ext>` | the save named `<stem>.<ext>` of the ROM of that console whose file name (without extension) is `<stem>` |
| `states/<system>/<stem>.slot<N>.state`, `<stem>.resume.state` | the state of that name of the same ROM |
| `states/<system>/<stem>.slot<N>.png` | the screenshot RomM keeps with the state `<stem>.slot<N>.state` |
| `games/<system>/<file name>` | a game file of a ROM (`GET /api/roms/{id}/content/{name}?file_ids=`), download only |

Consoles map to RomM platform slugs in `names.lua`. Saves with a RomM `slot` (versioned saves
of other clients) and saves named after another file are left alone. `rev` is the remote
`updated_at`; `put` reads the save again first and answers `nil, "conflict"` when it changed
since the rev the engine knows. RomM's `updated_at` is the upload time, so the file time `put`
is given is kept (`den.storage`, per file and rev) and `list` gives it back as `modified` while
the rev is unchanged. `config` and `bios` are not offered.

"Games on the server" hands a game's files to `den.sync.download_game`, which waits until the
host has fetched them (through `provider.get`) into the games folder and added it to the
library.

## Files

- `main.lua`: entry, the setup and status page, "Games on the server".
- `provider.lua`: `plugin.provider` (`list`, `get`, `put`, `delete`, `status`).
- `romm.lua`: the RomM API client and sign-in.
- `names.lua`: portable names and platform slugs.

The offline test is `tests/emuden.sync.romm/provider_test.lua` in this repository (not
packaged): `lua tests/emuden.sync.romm/provider_test.lua`.

Not affiliated with RomM.
