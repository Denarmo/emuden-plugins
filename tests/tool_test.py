# SPDX-FileCopyrightText: Copyright 2026 EmuDEN contributors
# SPDX-License-Identifier: GPL-3.0-or-later
"""Checks of tools/plugin_tool.py. Run from the repository root: python -I tests/tool_test.py"""

import copy
import pathlib
import sys
import unittest

REPO = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO / "tools"))

import plugin_tool  # noqa: E402
from plugin_kinds import ignored_fields  # noqa: E402


def feature(permissions, needs=("kind.feature", "feature.lua.1"), plugin_id="jdoe.thing", **extra):
    body = {"entry": "main.lua", "permissions": list(permissions)}
    body.update(extra)
    return {"manifest_version": 1, "id": plugin_id, "name": "Thing", "version": "1.0.0", "kind": "feature",
            "publisher": "J. Doe", "license": "MIT", "api": 1, "needs": list(needs), "feature": body}


def problems(manifest, trust="third-party"):
    return [f"{path}: {reason}" for path, reason in plugin_tool.validate_manifest(manifest, REPO, trust)]


class Tool(unittest.TestCase):
    def test_permission_needs_its_capability(self):
        browse = feature(["browse"], browse_hosts=["example.org"])
        self.assertTrue(any("feature.web.1" in p for p in problems(browse)))
        browse["needs"].append("feature.web.1")
        self.assertEqual(problems(browse), [])

    def test_achievements_are_official_only(self):
        cheevos = feature(["achievements"], needs=("kind.feature", "feature.lua.1", "feature.achievements.1"))
        self.assertTrue(any("only EmuDEN's own" in p for p in problems(cheevos)))
        self.assertTrue(any("only EmuDEN's own" in p for p in problems(cheevos, "developer")))
        cheevos["id"] = "emuden.thing"
        self.assertEqual(problems(cheevos, "official"), [])

    def test_no_external_engine(self):
        manifest = plugin_tool.load_json(REPO / "examples" / "jdoe.wiiu-cemu" / "plugin.json")
        self.assertEqual(problems(manifest), [])
        manifest["engine"] = "external"
        self.assertTrue(problems(manifest))

    def test_fields_the_app_ignores_are_named(self):
        manifest = plugin_tool.load_json(REPO / "examples" / "jdoe.wiiu-cemu" / "plugin.json")
        self.assertEqual(ignored_fields(manifest), [])
        changed = copy.deepcopy(manifest)
        changed["sync"] = {"saves": True, "cheats": True}
        changed["systems"][0]["capabilities"]["rewind"] = True
        changed["systems"][0]["capabilities"]["run_ahead"] = True
        changed["systems"][0]["capabilities"]["cheats"] = False  # read: cheats off for the console
        changed["settings"][0]["scope"] = "game"
        changed["settings"][0]["live"] = True
        paths = [path for path, _ in ignored_fields(changed)]
        self.assertEqual(sorted(paths), ["settings[0].live", "settings[0].scope", "sync.cheats",
                                         "systems[0].capabilities.run_ahead"])

    def test_manual_plugins_are_in_no_list(self):
        import plugin_manual
        manual = [f.name for f in plugin_manual.manual_folders(REPO)]
        self.assertIn("emuden.switch2", manual)
        self.assertFalse(set(manual) & {f.name for f in plugin_tool.plugin_folders(REPO)})
        index = plugin_tool.load_json(REPO / "index.json")
        self.assertFalse(set(manual) & {p["id"] for p in index["plugins"]})

    def test_examples_validate(self):
        for folder in sorted((REPO / "examples").glob("*/plugin.json")):
            with self.subTest(folder.parent.name):
                errors = plugin_tool.validate_manifest(plugin_tool.load_json(folder), REPO, "third-party",
                                                       "jdoe", folder.parent)
                self.assertEqual(errors, [])


if __name__ == "__main__":
    unittest.main()
