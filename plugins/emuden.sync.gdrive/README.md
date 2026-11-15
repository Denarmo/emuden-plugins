# Sync: Google Drive (`emuden.sync.gdrive`)

A sync provider for EmuDEN (`docs/sync.md` section 7.1 in the EmuDEN repository). EmuDEN's sync
engine decides what moves; this plugin stores and fetches the files in a folder named
`EmuDEN` in the user's My Drive, one subfolder per category (`saves`, `states`, `config`,
`games`, `bios`).

- Sign-in: Google's OAuth 2.0 device flow. The page shows a code and `google.com/device`; the
  user enters it on a phone or computer. Scope `https://www.googleapis.com/auth/drive.file`
  only: EmuDEN sees just the files it created. The refresh token is kept in `den.secrets`.
- Files: Drive API v3. Uploads under 5 MiB are one `multipart/related` request the host
  builds from the metadata and the file; larger ones are resumable, sent in 16 MiB chunks
  (`body_offset`, `body_length`) with progress after each. The session is kept in
  `den.storage`, so an upload cut by the network, a game starting (`den.sync.status().stopping`)
  or the app closing goes on from the offset Google reports, also in a later run. `rev` is the
  file's Drive `version`, and an upload over a newer remote version answers `conflict`.
  Deleting moves the file to the Drive trash.
- Steam and PC data never goes to Google Drive: the plugin refuses it as well as the host.
- Hosts: `oauth2.googleapis.com`, `www.googleapis.com`.

## Setting up the OAuth client (owner, once)

Until `oauth_client.json` holds a client id the plugin's page says sync is not set up. A copy
of that file in the plugin's data folder (`<data>/plugin-data/emuden.sync.gdrive/`) wins over
the packaged one, to try a client before it ships.

1. Google Cloud console: create a project for EmuDEN and enable the **Google Drive API**.
2. Google Auth Platform (OAuth consent screen): audience **External**; app name, support
   email and developer contact; under Data access add only `.../auth/drive.file`
   (non-sensitive). Leave the logo out (a logo needs brand verification).
3. Publish the app (**In production**). In Testing, only listed test users can sign in and
   their sign-in ends after 7 days.
4. Credentials: Create OAuth client ID, application type **TVs and Limited Input devices**.
   Put its client id and secret into `oauth_client.json`. (Google treats this secret as not
   confidential for this client type.)

## Test

`lua tests/emuden.sync.gdrive/test.lua` (plain Lua 5.4, from the repository root) runs the
plugin against a fake host and a fake Google.
