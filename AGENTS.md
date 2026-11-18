# Project rules (Denarmo/emuden-plugins)

These rules cover the official plugin repository. Other repositories open in the
same workspace (`emuden`, `emuden-switch2`, engine forks) follow their own AGENTS.md.

## Committing and pushing

- When a task is finished and the repository's checks pass, commit it to `main`
  and push. Don't wait to be asked. The checks are the same as CI:
  - `python -I tools/plugin_tool.py validate --all --trust bundled`
  - `python -I tests/tool_test.py`
  - `python -I tools/plugin_tool.py test` (needs Lua 5.4; WSL Debian has `lua5.4`)
  - `python -I tools/plugin_tool.py verify`
- Other agents may be working in this same checkout. Stage only the files your task
  changed (`git add <paths>`, never `git add -A` or `git commit -a`), and leave
  everyone else's uncommitted changes, including new plugin folders, as they are.
- If another task's uncommitted changes break the checks, run them on your files
  in a clean worktree from `origin/main` and push from there.
- A plugin release (new version for players) follows docs/publishing.md: bump the
  version, run `index` with the next `--sequence`, `sign`, then `verify`, and commit
  `index.json`, `index.json.sig` and the new package together. Without a release,
  manifest changes may be pushed as source only; say so in the commit message.
- When a bundled plugin changes, update its copy in `emuden/assets/plugins/` too
  (that repository's rules apply to that commit).
- Never print, read, copy or commit private signing keys; pass the key path to
  `sign` only. Never commit game data, BIOS, firmware or console keys.
- Pull with `--ff-only` before pushing. Never force-push or rewrite pushed history.
- A push to `main` runs the CI workflow; don't trigger, re-run or add workflows
  beyond that.
