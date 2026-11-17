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

    def test_quick_settings_layouts(self):
        folder = REPO / "plugins" / "emuden.quick-layouts"
        manifest = plugin_tool.load_json(folder / "plugin.json")
        self.assertEqual(plugin_tool.validate_manifest(manifest, REPO, "official", None, folder), [])
        missing = copy.deepcopy(manifest)
        missing["needs"].remove("quick_settings.1")
        self.assertTrue(any("quick_settings.1" in p for p in problems(missing, "official")))
        twice = copy.deepcopy(manifest)
        twice["quick_settings"]["layouts"][1]["id"] = "grid"
        self.assertTrue(any("already a choice" in p for p in problems(twice, "official")))
        unknown = copy.deepcopy(manifest)
        unknown["quick_settings"]["layouts"][0]["layout"] = "carousel"
        self.assertTrue(problems(unknown, "official"))
        both = copy.deepcopy(manifest)
        both["interface"] = {"layout": "carousel"}
        self.assertTrue(any("interface.1" in p for p in problems(both, "official")))
        both["needs"].append("interface.1")
        self.assertEqual(problems(both, "official"), [])
        neither = copy.deepcopy(manifest)
        del neither["quick_settings"]
        self.assertTrue(problems(neither, "official"))
        feature_kind = feature([])
        feature_kind["quick_settings"] = {"layout": "grid"}
        self.assertTrue(any("only for a plugin of kind interface" in p for p in problems(feature_kind)))

    def test_several_home_looks_and_themes(self):
        def interface(**fields):
            base = {"manifest_version": 1, "id": "jdoe.looks", "name": "Looks", "version": "1.0.0",
                    "kind": "interface", "publisher": "J. Doe", "license": "MIT", "api": 1,
                    "needs": ["kind.interface", "interface.1", "interfaces.1", "themes.1"]}
            base.update(fields)
            return base

        looks = interface(interfaces=[{"id": "grid", "name": "Grid", "layout": "grid"},
                                      {"id": "list", "name": "List", "layout": "list"}])
        self.assertEqual(problems(looks), [])
        looks["interfaces"][1]["id"] = "grid"
        self.assertTrue(any("already a look" in p for p in problems(looks)))
        looks["needs"].remove("interfaces.1")
        self.assertTrue(any("interfaces.1" in p for p in problems(looks)))

        themes = interface(themes=[{"id": "night", "name": "Night", "colors": {"page": "#000000", "fg": "#ffffff"}}])
        self.assertEqual(problems(themes), [])
        themes["themes"][0]["colors"]["text_dim"] = "#444444"
        self.assertTrue(any("contrast" in p for p in problems(themes)))
        themes["themes"][0]["colors"] = {"page": "#ffffff", "fg": "#999999"}
        self.assertTrue(any("colors.fg" in p for p in problems(themes)))

    def test_official_themes_are_readable(self):
        from plugin_kinds import contrast
        manifest = plugin_tool.load_json(REPO / "plugins" / "emuden.themes" / "plugin.json")
        self.assertGreaterEqual(len(manifest["themes"]), 8)
        for theme in manifest["themes"]:
            colors = theme["colors"]
            with self.subTest(theme["id"]):
                self.assertGreaterEqual(contrast(colors["fg"], colors["page"]), 4.5)
                self.assertGreaterEqual(contrast(colors["text_dim"], colors["page"]), 4.5)
                self.assertGreaterEqual(contrast(colors["fg"], colors["dialog"]), 4.5)

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
