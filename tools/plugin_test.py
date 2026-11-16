# SPDX-FileCopyrightText: Copyright 2026 EmuDEN contributors
# SPDX-License-Identifier: GPL-3.0-or-later
"""`plugin_tool.py test`: runs a plugin's offline Lua tests with a Lua 5.4 interpreter.

The tests of the plugin <id> are tests/<id>/*test.lua. Each runs from the repository root with
LUA_PATH "tests/?.lua;tests/<id>/?.lua;<plugin folder>/?.lua;;", so `require("den_mock")` finds the
shared mock of `den` (tests/den_mock.lua), and DEN_PLUGIN_DIR names the plugin folder. A test
fails by exiting with a status other than 0."""

import json
import os
import pathlib
import shutil
import subprocess


def find_lua(wanted):
    for name in ([wanted] if wanted else []) + [os.environ.get("LUA", "")] + ["lua5.4", "lua54", "lua"]:
        if not name:
            continue
        path = shutil.which(name) or (name if pathlib.Path(name).is_file() else None)
        if path:
            version = subprocess.run([path, "-v"], capture_output=True, text=True, check=False)
            if "Lua 5.4" in version.stdout + version.stderr:
                return path
    raise SystemExit("no Lua 5.4 interpreter found: pass --lua <program> or set LUA")


def plugin_id(folder):
    return json.loads((folder / "plugin.json").read_text(encoding="utf-8"))["id"]


def run(repo, folders, lua=None):
    if not folders:
        folders = sorted(p.parent for kind in ("plugins", "examples") for p in (repo / kind).glob("*/plugin.json"))
        folders = [f for f in folders if (repo / "tests" / plugin_id(f)).is_dir()]
    if not folders:
        raise SystemExit("no plugin with tests in tests/<id>/")
    lua = find_lua(lua)
    failed = 0
    for folder in folders:
        folder = folder.resolve()
        identifier = plugin_id(folder)
        tests = sorted((repo / "tests" / identifier).glob("*test.lua"))
        if not tests:
            print(f"{identifier}: no tests in tests/{identifier}/")
            failed += 1
            continue
        relative = folder.relative_to(repo).as_posix() if folder.is_relative_to(repo) else folder.as_posix()
        env = dict(os.environ, LUA_PATH=f"tests/?.lua;tests/{identifier}/?.lua;{relative}/?.lua;;",
                   DEN_PLUGIN_DIR=relative)
        for test in tests:
            done = subprocess.run([lua, test.relative_to(repo).as_posix()], cwd=repo, env=env,
                                  capture_output=True, text=True, check=False)
            ok = done.returncode == 0
            failed += not ok
            last = (done.stdout.strip().splitlines() or [""])[-1]
            print(f"{identifier}: {test.name}: {'ok' if ok else 'FAILED'} {last}")
            if not ok:
                print((done.stdout + done.stderr).strip())
    return 1 if failed else 0
