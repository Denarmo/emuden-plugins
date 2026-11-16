# SPDX-FileCopyrightText: Copyright 2026 EmuDEN contributors
# SPDX-License-Identifier: GPL-3.0-or-later
"""The rules of feature and interface plugins, the capability list the app shares
(schema/capabilities.json), and the manifest fields the app does not read yet."""

import json
import pathlib
import re

CAPABILITIES = json.loads((pathlib.Path(__file__).resolve().parent.parent / "schema" / "capabilities.json")
                          .read_text(encoding="utf-8"))
HOST_CAPABILITIES = [c["name"] for c in CAPABILITIES["capabilities"]]
FEATURE_PERMISSIONS = [p["name"] for p in CAPABILITIES["permissions"]]
# The capability `needs` must list for a permission, beyond kind.feature and feature.lua.1.
PERMISSION_NEEDS = {p["name"]: p["needs"] for p in CAPABILITIES["permissions"] if p["needs"]}
# Only EmuDEN's own plugins hold these; the developer folder neither.
OFFICIAL_PERMISSIONS = [p["name"] for p in CAPABILITIES["permissions"] if p["official_only"]]
# What a sync provider (permission "sync") may carry between devices (EmuDEN docs/sync.md).
SYNC_CATEGORIES = ["saves", "states", "config", "games", "bios"]
# Lua kept once in shared/<name>/ and copied into the package of every plugin whose folder
# names it in the file ".shared" (one name a line). A file of the plugin's own folder wins.
SHARED_MARK = ".shared"
HOST_NAME = re.compile(r"^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$")

# Fields the schema allows that this EmuDEN does not read yet: `validate` warns, so nobody
# relies on them. "*" stands for any list index or object key; "=value" warns only for that value.
IGNORED_FIELDS = {
    "sync.cheats": "EmuDEN has no cheats",
    "capabilities.run_ahead": "EmuDEN has no run-ahead",
    "capabilities.cheats": "EmuDEN has no cheats",
    "systems.*.capabilities.run_ahead": "EmuDEN has no run-ahead",
    "systems.*.capabilities.cheats": "EmuDEN has no cheats",
    "systems.*.content.hash_variants": "games are looked up by their whole file",
    "systems.*.presentation.native_size": "the core reports its picture size",
    "systems.*.romm_slugs": "",
    "settings.*.scope=game": "every setting is the console's; games have no value of their own",
    "settings.*.live": "the pause menu does not show plugin settings",
    "settings.*.inherit": "",
    "settings.*.apply.core_option_contains": "only apply.core_option is applied",
    "settings.*.apply.player": "only apply.core_option is applied",
    "settings.*.apply.native_setting": "only apply.core_option is applied",
    "components.*.downloads.*.strip_components": "",
    "components.*.downloads.*.rename": "",
    "components.*.downloads.*.executable_bit": "",
}


def ignored_fields(manifest):
    """(path, why) of every field of a console manifest that the app does not read yet."""
    if manifest.get("kind") != "console":
        return []
    found = []

    def walk(value, parts, path):
        if not parts:
            if only is None or value == only:
                found.append(path)
            return
        head, rest = parts[0], parts[1:]
        if head == "*":
            items = enumerate(value) if isinstance(value, list) else \
                value.items() if isinstance(value, dict) else []
            for key, item in items:
                walk(item, rest, f"{path}[{key}]" if isinstance(value, list) else f"{path}.{key}")
        elif isinstance(value, dict) and head in value:
            walk(value[head], rest, f"{path}.{head}".lstrip("."))

    out = []
    for field, why in IGNORED_FIELDS.items():
        found.clear()
        field, _, only = field.partition("=")
        only = only or None
        walk(manifest, field.split("."), "")
        out += [(path, why) for path in found]
    return out


def safe_relative(path):
    return (bool(path) and not path.startswith("/") and "\\" not in path and ":" not in path
            and "{" not in path and ".." not in path.split("/"))


def shared_files(folder):
    """{package path: file} of the shared libraries a plugin folder names."""
    mark = folder / SHARED_MARK
    found = {}
    if not mark.is_file():
        return found
    for name in mark.read_text(encoding="utf-8").split():
        library = folder.resolve().parent.parent / "shared" / name
        if not re.match(r"^[a-z0-9][a-z0-9_-]*$", name) or not library.is_dir():
            raise SystemExit(f"{folder.name}: {SHARED_MARK} names {name}, which is not a folder "
                             "of shared/")
        for path in sorted(library.rglob("*")):
            if path.is_file():
                found.setdefault(path.relative_to(library).as_posix(), path)
    return found


def in_package(folder, name):
    return (folder / name).is_file() or name in shared_files(folder)


def validate_interface(manifest, folder, err):
    """The rules of an interface plugin: data the app's layouts draw, and its pictures."""
    for field in ("engine", "systems", "components", "settings", "sync", "capabilities"):
        if manifest.get(field):
            err(field, "an interface plugin has none")
    for need in ("kind.interface", "interface.1"):
        if need not in manifest["needs"]:
            err("needs", f"must list {need}")
    look = manifest.get("interface")
    if not isinstance(look, dict):
        err("interface", "missing")
        return
    pictures = [("interface.icon", look.get("icon")),
                ("interface.backdrop.wallpaper", look.get("backdrop", {}).get("wallpaper"))]
    for key, console in look.get("consoles", {}).items():
        pictures.append((f"interface.consoles.{key}.wallpaper", console.get("wallpaper")))
    for path, name in pictures:
        if not name:
            continue
        if not safe_relative(name) or not name.lower().endswith((".png", ".jpg", ".jpeg")):
            err(path, "must be a PNG or JPEG of the package")
        elif folder is not None and not (folder / name).is_file():
            err(path, "there is no such file in the plugin folder")


def validate_feature(manifest, trust, folder, err):
    """The rules of a feature plugin: a sandboxed Lua script with declared permissions."""
    reserved = trust in ("bundled", "official")
    for field in ("engine", "systems", "components", "settings", "sync", "capabilities"):
        if manifest.get(field):
            err(field, "a feature plugin has none")
    for need in ("kind.feature", "feature.lua.1"):
        if need not in manifest["needs"]:
            err("needs", f"must list {need}")
    feature = manifest.get("feature")
    if not isinstance(feature, dict):
        err("feature", "missing")
        return
    entry = feature["entry"]
    if not safe_relative(entry) or not entry.endswith(".lua"):
        err("feature.entry", "must be a script of the package (a relative path ending in .lua)")
    elif folder is not None and not in_package(folder, entry):
        err("feature.entry", "there is no such file in the plugin folder")
    icon = feature.get("icon")
    if icon and (not safe_relative(icon) or not icon.endswith(".png")):
        err("feature.icon", "must be a PNG of the package")
    elif icon and folder is not None and not in_package(folder, icon):
        err("feature.icon", "there is no such file in the plugin folder")
    permissions = feature["permissions"]
    for permission in permissions:
        if permission not in FEATURE_PERMISSIONS:
            err("feature.permissions", f"{permission} is not a permission")
    if len(set(permissions)) != len(permissions):
        err("feature.permissions", "a permission is listed twice")
    http_hosts = feature.get("http", {}).get("hosts", [])
    open_hosts = feature.get("open_hosts", [])
    browse_hosts = feature.get("browse_hosts", [])
    for path, hosts in (("feature.http.hosts", http_hosts), ("feature.open_hosts", open_hosts),
                        ("feature.browse_hosts", browse_hosts)):
        if len(hosts) > 8:
            err(path, "at most 8 hosts")
        for host in hosts:
            if not HOST_NAME.match(host):
                err(path, f"{host} is not an exact host name (no scheme, path or wildcard)")
    if ("http" in permissions or "download" in permissions) != bool(http_hosts):
        err("feature.http.hosts", "needed with http or download, and only with them")
    if ("open-url" in permissions) != bool(open_hosts):
        err("feature.open_hosts", "needed with open-url, and only with it")
    if ("browse" in permissions) != bool(browse_hosts):
        err("feature.browse_hosts", "needed with browse, and only with it")
    for permission in permissions:
        need = PERMISSION_NEEDS.get(permission)
        if need and need not in manifest["needs"]:
            err("needs", f"must list {need} with {permission}")
        if permission in OFFICIAL_PERMISSIONS and not reserved:
            err("feature.permissions", f"{permission}: only EmuDEN's own plugins have this permission")
    sync = feature.get("sync")
    if ("sync" in permissions) != (sync is not None):
        err("feature.sync", "needed with sync, and only with it")
    if sync is not None:
        categories = sync.get("categories", [])
        if not categories:
            err("feature.sync.categories", "a provider carries at least one category")
        for category in categories:
            if category not in SYNC_CATEGORIES:
                err("feature.sync.categories", f"{category} is not a sync category")
        if len(set(categories)) != len(categories):
            err("feature.sync.categories", "a category is listed twice")
    systems = feature.get("systems", [])
    for system in systems:
        if system != "*" and not re.match(r"^[a-z0-9][a-z0-9_-]*$", system):
            err("feature.systems", f"{system} is not a system id")
    if "*" in systems and (not reserved or len(systems) != 1):
        err("feature.systems", "only EmuDEN's own plugins see every console, as [\"*\"] alone")
    if any(p in permissions for p in ("library.read", "patch", "library.write", "game.settings")) and not systems:
        err("feature.systems", "needed with the library and patch permissions")
    file_types = feature.get("file_types", [])
    for extension in file_types:
        if not re.match(r"^[a-z0-9]{1,10}$", extension):
            err("feature.file_types", f"{extension} is not a file extension")
    if "downloads.watch" in permissions and not file_types:
        err("feature.file_types", "needed with downloads.watch")


