# Sync: WebDAV (template)

A template for a sync provider plugin. It keeps saves, save states and settings in a folder of
a WebDAV server the user enters (Nextcloud, ownCloud, a NAS, Apache `mod_dav`, nginx with
`dav`). **It is a template: it has only been run against the fake server of its offline test,
never against a real server.** It is not published and EmuDEN does not install it by itself.

## How it stores files

`den.http.request` offers GET, POST, PUT, PATCH, DELETE and HEAD, not WebDAV's `PROPFIND` or
`MKCOL`. So the plugin never lists or makes folders on the server:

- The user makes one folder on the server and enters its address. It must exist.
- Every file lies flat in that folder, its portable path percent-encoded into one name:
  `saves/gba/x.srm` is stored as `saves%2Fgba%2Fx.srm`. In the URL the name is encoded once more
  (`saves%252Fgba%252Fx.srm`), so the server keeps the `%` signs and never sees a `/`.
- `emuden-index.json` in the same folder lists the files:
  `{"version": 1, "files": {"saves/gba/x.srm": {"size": 8192, "modified": 1794000000, "rev": "..."}}}`.
  `list()` reads it with one GET; `put()` and `delete()` read it, change one entry and write it
  back with PUT.
- `rev` is the ETag the server returns for the PUT, else `<size>@<modified>`. `modified` is
  the time the sync engine gave `put()`, kept in the index, so it is the file's own time on
  every server.
- A `put()` whose `rev` differs from the one in the index answers `nil, "conflict"`.

**The index is last-writer-wins.** Two devices that sync at the same moment both read the
index, change it and write it back; the second write loses the first one's entry. The file
itself is on the server, but listings do not show it until it is put again, and its device's
journal believes it is there. A real plugin should make the index update conditional (an
`If-Match` with the index's ETag, retried on `412`) on servers that support it, or keep one
index per device and merge them in `list()`.

Other limits: the index is read whole (at most 8 MiB, the answer limit, which is tens of
thousands of files); every `put` and `delete` costs three requests; `games` and `bios` are not
in `feature.sync.categories`; locks (`423`) and quotas (`507`) only show as the status number.

## The page

The folder's address, the user name and the password. The address goes through
`den.sync.set_server`, so the user confirms the server once; the password is kept with
`den.secrets` (the device's credential store, never synced), the rest in `den.storage`.
"Check the connection" reads the index and writes an empty one when there is none (which also
shows that the folder exists). Basic authentication over plain `http` sends the password
unencrypted; the page says so.

`feature.sync.listing` is left at its default (`category`); `list()` takes any prefix, so
`all` or `per_folder` would work as well.

## Test

```sh
LUA_PATH="tests/?.lua;tests/jdoe.sync.webdav/?.lua;examples/jdoe.sync.webdav/?.lua;;" \
DEN_PLUGIN_DIR=examples/jdoe.sync.webdav lua tests/jdoe.sync.webdav/test.lua
```

Before publishing a plugin made from it, change the id and `publisher` to your own name, and
try it against the servers you name in its summary.
