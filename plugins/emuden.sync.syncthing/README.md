# Sync: Syncthing (`emuden.sync.syncthing`)

A sync provider for EmuDEN (`docs/sync.md`, section 7.3, in the EmuDEN repository). EmuDEN
keeps the synced files as plain files in a folder (the host's folder store,
`den.sync.use_folder`); Syncthing replicates that folder between the user's devices. All
categories: saves, states, config, games, bios.

The page has three parts:

1. **Sync folder.** "Use Sync/EmuDEN" (in the home folder on desktop, in shared storage on
   Android) or "Choose a folder" (`den.sync.use_folder`; the host keeps the folder and the
   page reads it back with `den.sync.folder`). Below it, EmuDEN's last sync of the folder,
   its conflicts and first error (`den.sync.status`) and "Sync now".
2. **Connect to Syncthing on this device** (optional). The user pastes Syncthing's API key
   (kept in `den.secrets`). The page then shows this device's id, the devices Syncthing knows
   with "Shared"/"Not shared", and adds or updates the Syncthing folder `emuden` (label
   "EmuDEN", the chosen path, type `sendreceive`). It shows the folder's completion on this
   device and on each device it is shared with, and the last file synced.
3. **Getting Syncthing**, shown while it is not connected: Syncthing from syncthing.net on
   Windows, Linux and macOS; Syncthing-Fork from F-Droid
   (`com.github.catfriend1.syncthingfork`) or `github.com/researchxxl/syncthing-android` on
   Android. The plugin downloads nothing.

Without Syncthing the folder still works: anything that copies it between devices will do.

## Syncthing REST API used (checked against v2.1.7)

All requests go to `127.0.0.1:8384` (or the address the user enters; loopback only, the
`http.local` permission) with the `X-API-Key` header.

| Request | For |
|---|---|
| `GET /rest/system/status` | `myID`, this device's id; a refused key (401/403) |
| `GET /rest/config/devices` | the devices to share with |
| `GET /rest/config/folders` | that no other folder already uses the chosen path |
| `GET /rest/config/folders/emuden` | the folder, 404 when missing |
| `POST /rest/config/folders` | adds `emuden`; Syncthing fills the rest from its folder defaults |
| `PATCH /rest/config/folders/emuden` | updates `label`, `path`, `type`, `devices` only |
| `GET /rest/db/completion?folder=emuden[&device=<id>]` | completion here and on each shared device |
| `GET /rest/stats/folder` | `lastFile` and `lastScan` of `emuden` (the docs call `db/status` expensive, so it is not used) |

Other folders are never written. Unticking a device removes it from the folder's devices;
entries for devices Syncthing does not list are kept, as are `introducedBy` and
`encryptionPassword` of the entries that stay.

Syncthing-Fork serves its GUI over TLS on Android (7.0 excepted); plain http then answers
with a 307 to https. The plugin tries http first and https after such a redirect or a
refused connection, and remembers what worked.

## Test

`lua tests/sync-syncthing.lua` from the repository root (plain Lua 5.4), with a fake `den`
and a fake Syncthing.
