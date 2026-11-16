# Hello (example feature plugin)

A small feature plugin to start from. It is not published and EmuDEN does not install it by
itself.

- One page with a heading, a text and a button. Each press is counted in `den.storage`, so the
  count stays between visits.
- One request: `den.http.get` reads the latest tags of `lua/lua` from `api.github.com` (the only
  host the manifest declares) and shows them as rows. A failure is shown as a warning text;
  "Refresh" asks again without the cache.

The calls it uses are in [docs/lua-api.md](../../docs/lua-api.md). The offline test is
`tests/jdoe.hello-feature/test.lua`; it runs on any Lua 5.4 with `tests/den_mock.lua`:

```sh
LUA_PATH="tests/?.lua;tests/jdoe.hello-feature/?.lua;examples/jdoe.hello-feature/?.lua;;" \
DEN_PLUGIN_DIR=examples/jdoe.hello-feature lua tests/jdoe.hello-feature/test.lua
```

To try it in the app, copy the folder to `<data>/plugins-dev/jdoe.hello-feature/` and turn on
Settings > Plugins > Developer mode; it is listed under Plugins as "Developer".
Before publishing a plugin made from it, change the id and `publisher` to your own name.
