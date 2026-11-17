#!/usr/bin/env python3
# SPDX-FileCopyrightText: Copyright 2026 EmuDEN contributors
# SPDX-License-Identifier: GPL-3.0-or-later
"""Builds and checks an EmuDEN plugin repository. Standard library only; signing uses the Python
package `cryptography` when it is installed, else the `openssl` program (3.0 or newer).

    python -I tools/plugin_tool.py validate plugins/emuden.nes        one plugin
    python -I tools/plugin_tool.py validate --all                     everything in the repository
    python -I tools/plugin_tool.py test examples/jdoe.hello-feature   its tests/<id>/*test.lua (Lua 5.4)
    python -I tools/plugin_tool.py assemble plugins/<id> -o <folder>  a feature plugin's files, to try it
    python -I tools/plugin_tool.py pack plugins/jdoe.consoles         -> packages/<id>-<version>.emuplugin
    python -I tools/plugin_tool.py pack addons/<program id>/<id>      -> packages/<id>-<version>.emuaddon
    python -I tools/plugin_tool.py index --sequence 2                 packs all, writes index.json and
                                                                      the add-on list in addons.json
    python -I tools/plugin_tool.py sign --key ~/keys/source.key       writes index.json.sig
    python -I tools/plugin_tool.py verify                             checks index.json.sig
    python -I tools/plugin_tool.py keygen --key ~/keys/source.key     a new key pair, once
    python -I tools/plugin_tool.py pin-cores                          hashes the cores, cores.lock.json

Run it from the repository root, or pass --repo.
"""

import argparse
import base64
import datetime
import hashlib
import json
import pathlib
import re
import sys
import urllib.request
import zipfile

# The tool's own modules beside it (python -I leaves its folder off the path).
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

from plugin_addons import (EXECUTABLE_EXTENSIONS, EXECUTABLE_MAGICS, addon_folders,  # noqa: E402
                           build_catalogue, pack_addon, sha256_file, validate_addon)
from plugin_kinds import (HOST_CAPABILITIES, SHARED_MARK, ignored_fields, safe_relative,  # noqa: E402
                          shared_files, validate_feature, validate_interface)
from plugin_schema import check_schema, load_json, load_schema  # noqa: E402
import plugin_manual  # noqa: E402
import plugin_sign  # noqa: E402
import plugin_test  # noqa: E402

PLATFORMS = ["windows-x86_64", "linux-x86_64", "linux-aarch64", "macos-arm64", "android-arm64"]
GLOBAL_KEYS = ["video.fullscreen", "audio.volume", "audio.mute", "general.pause_in_background"]
PLAYER_KEYS = ["picture", "fast_forward", "run_ahead", "screen_size", "border", "volume",
               "mute_fast_forward", "low_latency"]
RESERVED_SYSTEM_IDS = ["global", "defaults", "local", "dev"]
UNPINNED_HOST = "buildbot.libretro.com"
MAX_UNPINNED_SIZE = 256 * 1024 * 1024
PACKAGE_FILES = re.compile(r"^(plugin\.json|icon\.png|assets/.+|LICENSE[^/]*|README[^/]*)$")
MAX_PACKAGE_FILES = 256
MAX_PACKAGE_BYTES = 16 * 1024 * 1024
MAX_EXPIRY_DAYS = 120

FEATURE_PACKAGE_FILES = re.compile(r"^[A-Za-z0-9_][A-Za-z0-9_.-]*(/[A-Za-z0-9_][A-Za-z0-9_.-]*)*"
                                   r"\.(json|lua|png|jpg|txt|md)$")
# Interface plugins (kind "interface"): data only, looks for Home, quick settings layouts, themes.
INTERFACE_PACKAGE_FILES = re.compile(r"^[A-Za-z0-9_][A-Za-z0-9_.-]*(/[A-Za-z0-9_][A-Za-z0-9_.-]*)*"
                                     r"\.(json|png|jpg|txt|md)$")
MAX_FEATURE_FILES = 200
MAX_FEATURE_BYTES = 8 * 1024 * 1024

# A field that changes what runs, what is written or what is synced needs a capability, so an
# older EmuDEN refuses the manifest instead of reading half of it.
FIELD_CAPABILITIES = [
    (lambda m: bool(m.get("settings")), "settings.v1"),
    (lambda m: any(s.get("content", {}).get("multi_file") for s in m.get("systems", [])),
     "content.multi_file"),
    (lambda m: any(s.get("content", {}).get("magic") for s in m.get("systems", [])),
     "content.magic"),
]


# --- manifest rules that a schema cannot say ---------------------------------------------------

def url_host(url):
    return url.split("://", 1)[-1].split("/", 1)[0].lower()


def validate_manifest(manifest, repo, trust="third-party", namespace=None, folder=None):
    """Returns a list of (json path, reason). `folder`: the plugin's folder, to check its files."""
    errors = []
    schema = load_schema(repo, "plugin.schema.json")
    check_schema(manifest, schema, schema, "", errors)
    if errors:
        return errors
    reserved = trust in ("bundled", "official")
    err = lambda path, reason: errors.append((path, reason))

    plugin_id = manifest["id"]
    if plugin_id.split(".")[0] == "emuden" and not reserved:
        err("id", "the emuden namespace belongs to EmuDEN's own plugins")
    if namespace and trust == "third-party" and plugin_id.split(".")[0] != namespace:
        err("id", f"must start with {namespace}. (the owner of the repository)")
    kind, engine = manifest["kind"], manifest.get("engine")
    if kind == "feature":
        validate_feature(manifest, trust, folder, err)
    elif "feature" in manifest:
        err("feature", "only for a plugin of kind feature")
    if kind == "interface":
        validate_interface(manifest, folder, err)
    else:
        for field in ("icon", "interface", "interfaces", "quick_settings", "themes"):
            if field in manifest:
                err(field, "only for a plugin of kind interface")
    if kind == "console" and not engine:
        err("engine", "missing")
    if kind != "console" and engine:
        err("engine", "only a console has an engine")
    if kind == "tweak-tool" and not reserved:
        err("kind", "only EmuDEN's own plugins change PC game folders")
    if engine == "switch2" and not reserved:
        err("engine", "this engine is only for EmuDEN's own plugins")
    if engine and f"engine.{engine}" not in manifest["needs"]:
        err("needs", f"must list engine.{engine}")
    for uses, capability in FIELD_CAPABILITIES:
        if uses(manifest) and capability not in manifest["needs"]:
            err("needs", f"must list {capability}")
    for need in manifest["needs"]:
        if need not in HOST_CAPABILITIES:
            print(f"note: needs {need}, which no released EmuDEN has yet", file=sys.stderr)
    if manifest.get("api", 1) > 1:
        print("note: api is newer than this tool knows", file=sys.stderr)

    components = {c["id"]: c for c in manifest.get("components", [])}
    if len(components) != len(manifest.get("components", [])):
        err("components", "a component id is used twice")
    settings = manifest.get("settings", [])
    setting_keys = [s["key"] for s in settings]
    if len(set(setting_keys)) != len(setting_keys):
        err("settings", "a setting key is used twice")

    fitting = {"libretro-core": "libretro", "engine-app": "libretro", "engine": "switch2"}
    for i, component in enumerate(manifest.get("components", [])):
        path = f"components[{i}]"
        kind_of = component["type"]
        if kind_of in ("engine", "tool") and not reserved:
            err(f"{path}.type", "only EmuDEN's own plugins have this type")
        if kind_of in fitting and fitting[kind_of] != engine:
            err(f"{path}.type", "does not fit the plugin's engine")
        if "delivery" in component and kind_of != "engine":
            err(f"{path}.delivery", "only for an engine")
        if kind_of == "system-files" and not reserved:
            err(f"{path}.type", "only EmuDEN's own plugins have this type")
        if "cores" in component and kind_of != "system-files":
            err(f"{path}.cores", "only for system files")
        for core in component.get("cores", []):
            if components.get(core, {}).get("type") != "libretro-core":
                err(f"{path}.cores", f"{core} is not a core of the plugin")
        for platform, download in component.get("downloads", {}).items():
            where = f"{path}.downloads.{platform}"
            if platform not in PLATFORMS + ["any"]:
                err(where, "unknown platform")
            local = "file" in download
            if local and trust != "developer":
                err(f"{where}.file", "only allowed in the developer folder")
            if not local and "url" not in download:
                err(f"{where}.url", "missing")
            unpinned = download.get("integrity") == "unpinned"
            if unpinned and (trust != "bundled" or url_host(download.get("url", "")) != UNPINNED_HOST):
                err(f"{where}.integrity",
                    "downloads without a checksum are only allowed in the built-in list")
            if unpinned and download.get("sha256") is not None:
                err(f"{where}.sha256", "must be null for an unpinned download")
            if not unpinned and not local and not download.get("sha256"):
                err(f"{where}.sha256", "missing")
            if not local and download.get("size", 0) < 1:
                err(f"{where}.size", "missing: the exact size in bytes")
            if unpinned and download.get("size", 0) > MAX_UNPINNED_SIZE:
                err(f"{where}.size", "an unpinned download is capped at 256 MiB")
            if kind_of == "libretro-core" and download["archive"] == "zip" and "entry" not in download:
                err(f"{where}.entry", "missing: the core library inside the zip")
            if kind_of == "system-files" and not (
                    download["archive"] == "zip" and download.get("entry", "").endswith("/")):
                err(f"{where}.entry", "system files are a zip and a folder inside it, as \"Name/\"")
        if kind_of == "engine-app":
            if not isinstance(component.get("ecp"), dict):
                err(f"{path}.ecp", "missing: the engine's ECP descriptor")
            android = component.get("android")
            if android is None and not component.get("executable"):
                err(path, "an engine app needs android or executable")
            if android is not None:
                apk = android.get("apk")
                if apk is None and not android.get("store"):
                    err(f"{path}.android", "needs apk or store")
                if apk is not None and (not apk.get("sha256") or apk.get("size", 0) < 1
                                        or not str(apk.get("url", "")).startswith("https://")):
                    err(f"{path}.android.apk", "must be a pinned https download (url, sha256, size)")
        elif "ecp" in component or "android" in component or "executable" in component:
            err(path, "ecp, android and executable are only for an engine app")
    system_ids = []
    for i, system in enumerate(manifest.get("systems", [])):
        path = f"systems[{i}]"
        system_id = system["id"]
        if (system_id in RESERVED_SYSTEM_IDS
                or system_id.startswith(("game-", "plugin-", "options-"))):
            err(f"{path}.id", "reserved")
        if system_id in system_ids:
            err(f"{path}.id", "used twice")
        system_ids.append(system_id)
        content = system["content"]
        for extension in content.get("folder_only_extensions", []):
            if extension not in content.get("extensions", []):
                err(f"{path}.content.folder_only_extensions", f"{extension} is not an extension")
        if "scanner" in content and not (reserved and content["scanner"] == engine):
            err(f"{path}.content.scanner", "only built-in consoles scan by themselves")
        cores = system.get("cores", [])
        if engine == "libretro" and not cores:
            err(f"{path}.cores", "missing")
        if engine != "libretro" and cores:
            err(f"{path}.cores", "only for the libretro engine")
        for core in cores:
            if components.get(core, {}).get("type") not in ("libretro-core", "engine-app"):
                err(f"{path}.cores", f"{core} is not a core of the plugin")
        for j, bios in enumerate(system.get("bios", [])):
            for k, entry in enumerate(bios["files"]):
                name = entry["path"]
                if name in ("@firmware", "@keys"):
                    if engine != "switch2":
                        err(f"{path}.bios[{j}].files[{k}].path", "only the Switch 2 engine answers this")
                elif not safe_relative(name.rstrip("/")):
                    err(f"{path}.bios[{j}].files[{k}].path", "must be a relative path in the BIOS folder")
    if kind == "console" and not system_ids:
        err("systems", "a console plugin needs at least one system")

    def check_capabilities(caps, path):
        player = any(caps.get(k) for k in ("save_states", "rewind", "fast_forward", "run_ahead",
                                           "cheats", "netplay", "achievements"))
        if (player and engine != "libretro") or (caps.get("addons") and engine != "switch2"):
            err(path, f"claims a capability the {engine} engine does not have")
    check_capabilities(manifest.get("capabilities", {}), "capabilities")
    for i, system in enumerate(manifest.get("systems", [])):
        check_capabilities(system.get("capabilities", {}), f"systems[{i}].capabilities")

    forms = {"core_option": "libretro", "core_option_contains": "libretro", "player": "libretro",
             "native_setting": "switch2"}
    for i, setting in enumerate(settings):
        path = f"settings[{i}]"
        apply = setting["apply"]
        used = [form for form in forms if form in apply]
        if len(used) != 1:
            err(f"{path}.apply", "must hold exactly one way to apply the setting")
            continue
        form = used[0]
        if forms[form] != engine:
            err(f"{path}.apply.{form}", f"not available with the {engine} engine")
        native, from_core = form == "native_setting", form == "core_option_contains"
        if not native and not setting.get("label"):
            err(f"{path}.label", "missing")
        if "default" not in setting and not native and not from_core:
            err(f"{path}.default", "missing")
        if "default" in setting:
            wanted = {"toggle": bool, "range": (int, float)}.get(setting["type"], str)
            if not isinstance(setting["default"], wanted) or (
                    setting["type"] == "range" and isinstance(setting["default"], bool)):
                err(f"{path}.default", "does not fit the type")
        if setting["type"] == "choice" and not setting.get("choices") and not native and not from_core:
            err(f"{path}.choices", "missing")
        if setting["type"] == "range" and not native and ("min" not in setting or "max" not in setting):
            err(path, "a range needs min and max")
        if setting["type"] == "path" and "path_kind" not in setting:
            err(f"{path}.path_kind", "missing")
        if setting["type"] == "path" and setting.get("default"):
            err(f"{path}.default", "a path setting has no default: use \"\"")
        inherit = setting.get("inherit")
        if inherit and inherit not in GLOBAL_KEYS + [f"player.{key}" for key in PLAYER_KEYS]:
            err(f"{path}.inherit", "not a setting a plugin can inherit")
        for system_id in setting.get("systems", []):
            if system_id not in system_ids:
                err(f"{path}.systems", f"{system_id} is not a system of the plugin")
        if setting.get("when_core") and setting["when_core"] not in components:
            err(f"{path}.when_core", "not a component of the plugin")

    sync = manifest.get("sync")
    if sync is not None:
        if kind != "console" or engine not in ("libretro", "switch2"):
            err("sync", "this kind of plugin never syncs")
    return errors


def code_class(manifest, trusted=()):
    """none or cores: what the plugin makes run on any platform."""
    result = "none"
    for component in manifest.get("components", []):
        if component["type"] == "engine-app":
            result = "cores"
        if component["type"] == "libretro-core":
            for download in component.get("downloads", {}).values():
                if download.get("sha256") not in trusted:
                    result = "cores"
    return result


def usable_platforms(manifest):
    listed = manifest.get("platforms") or ["any"]
    out = []
    for platform in PLATFORMS:
        if "any" not in listed and platform not in listed:
            continue
        engine = manifest.get("engine")
        components = manifest.get("components", [])
        if engine == "libretro":
            downloads = [c.get("downloads", {}) for c in components
                         if c["type"] == "libretro-core"]
            if any(downloads) and not any(platform in d or "any" in d for d in downloads):
                continue
        elif engine == "switch2":
            if not any(platform in c.get("delivery", {}) for c in components):
                continue
        out.append(platform)
    return out


# --- packages, index, signatures ---------------------------------------------------------------

def package_files(folder):
    kind = load_json(folder / "plugin.json").get("kind")
    feature = kind == "feature"
    allowed = (FEATURE_PACKAGE_FILES if feature else
               INTERFACE_PACKAGE_FILES if kind == "interface" else PACKAGE_FILES)
    files = []
    sources = dict(shared_files(folder)) if feature else {}
    for path in sorted(folder.rglob("*")):
        if path.is_file() and path.relative_to(folder).as_posix() != SHARED_MARK:
            sources[path.relative_to(folder).as_posix()] = path
    for name, path in sorted(sources.items()):
        if path.is_symlink() or not allowed.match(name):
            raise SystemExit(f"{folder.name}: {name} does not belong in a plugin package (" +
                             ("only .json, .lua, .png, .jpg, .txt and .md files" if feature else
                              "only .json, .png, .jpg, .txt and .md files" if kind == "interface" else
                              "plugin.json, icon.png, assets/, LICENSE*, README*") + ")")
        data = path.read_bytes()
        if name.lower().endswith(EXECUTABLE_EXTENSIONS) or data.startswith(EXECUTABLE_MAGICS):
            raise SystemExit(f"{folder.name}: {name} is a program; a plugin package holds none")
        if feature and name.endswith(".lua") and data.startswith(b"\x1bLua"):
            raise SystemExit(f"{folder.name}: {name} is compiled Lua; scripts are text")
        files.append((name, data))
    most, room = (MAX_FEATURE_FILES, MAX_FEATURE_BYTES) if kind in ("feature", "interface") else \
        (MAX_PACKAGE_FILES, MAX_PACKAGE_BYTES)
    if len(files) > most or sum(len(d) for _, d in files) > room:
        raise SystemExit(f"{folder.name}: more than {most} files or {room >> 20} MiB")
    return files


def pack(folder, out_dir):
    """Writes <id>-<version>.emuplugin; the same input always gives the same bytes."""
    manifest = load_json(folder / "plugin.json")
    out_dir.mkdir(parents=True, exist_ok=True)
    target = out_dir / f"{manifest['id']}-{manifest['version']}.emuplugin"
    with zipfile.ZipFile(target, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for name, data in package_files(folder):
            info = zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o644 << 16
            archive.writestr(info, data)
    return target


def plugin_folders(repo):
    return sorted(p.parent for p in (repo / "plugins").glob("*/plugin.json"))


def build_index(repo, args):
    previous = load_json(repo / "index.json") if (repo / "index.json").exists() else {}
    sequence = args.sequence if args.sequence is not None else previous.get("sequence", 0) + 1
    if sequence < previous.get("sequence", 0):
        raise SystemExit("the sequence must not go down: EmuDEN refuses an older list")
    if not 1 <= args.days <= MAX_EXPIRY_DAYS:
        raise SystemExit(f"--days must be 1 to {MAX_EXPIRY_DAYS}")
    now = datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0)
    stamp = lambda t: t.strftime("%Y-%m-%dT%H:%M:%SZ")
    trust = args.trust
    namespace = args.namespace
    plugins = []
    for folder in plugin_folders(repo):
        manifest = load_json(folder / "plugin.json")
        errors = validate_manifest(manifest, repo, trust, namespace, folder)
        if errors:
            for path, reason in errors:
                print(f"{folder.name}: {path}: {reason}", file=sys.stderr)
            raise SystemExit(1)
        package = pack(folder, repo / "packages")
        sizes, hosts = {}, set()
        for platform in usable_platforms(manifest):
            total = 0
            for component in manifest.get("components", []):
                download = component.get("downloads", {}).get(platform) or \
                    component.get("downloads", {}).get("any")
                if download and "url" in download:
                    total += download.get("size", 0)
                    hosts.add(url_host(download["url"]))
            sizes[platform] = total
        base = args.base_url.rstrip("/") + "/" if args.base_url else "packages/"
        plugins.append({
            "id": manifest["id"], "name": manifest["name"], "version": manifest["version"],
            "kind": manifest["kind"], "engine": manifest.get("engine", "none"),
            "publisher": manifest["publisher"], "summary": manifest.get("summary", ""),
            "group": (manifest.get("systems") or [{}])[0].get("group", ""),
            "systems": [{"id": s["id"], "name": s["name"],
                         "folder_aliases": s["content"].get("folder_aliases", [])}
                        for s in manifest.get("systems", [])],
            "api": manifest["api"], "needs": manifest["needs"],
            "platforms": usable_platforms(manifest),
            "code": code_class(manifest),
            "package": {"url": base + package.name, "sha256": sha256_file(package),
                        "size": package.stat().st_size},
            "download_size": sizes, "download_hosts": sorted(hosts),
        })
        if manifest["kind"] == "feature":
            # What the package will ask for, shown before any download. "systems" stays the
            # list of console objects readers older than feature plugins expect (none here);
            # they refuse the entry by its needs and keep the rest of the list.
            feature = manifest["feature"]
            plugins[-1].update({
                "permissions": feature["permissions"],
                "http_hosts": feature.get("http", {}).get("hosts", []),
                "open_hosts": feature.get("open_hosts", []),
                "browse_hosts": feature.get("browse_hosts", []),
                "feature_systems": feature.get("systems", []),
            })
    index = {
        "index_version": 1,
        "source": {"name": args.name or previous.get("source", {}).get("name", ""),
                   "homepage": args.homepage or previous.get("source", {}).get("homepage", "")},
        "sequence": sequence,
        "generated": stamp(now),
        "expires": stamp(now + datetime.timedelta(days=args.days)),
        "plugins": plugins,
    }
    if not index["source"]["name"]:
        raise SystemExit("--name is needed the first time: what the source is called in EmuDEN")
    build_catalogue(repo, args.base_url.rstrip("/") + "/" if args.base_url else "packages/",
                    namespace, trust)
    addons = repo / "addons.json"
    if addons.exists():
        problems = []
        schema = load_schema(repo, "addons.schema.json")
        check_schema(load_json(addons), schema, schema, "", problems)
        if problems:
            raise SystemExit("addons.json: " + "; ".join(f"{p}: {r}" for p, r in problems))
        index["addons"] = {"url": "addons.json", "sha256": sha256_file(addons),
                           "size": addons.stat().st_size}
    index["trusted_component_sha256"] = sorted({
        download["sha256"]
        for folder in plugin_folders(repo)
        for component in load_json(folder / "plugin.json").get("components", [])
        for download in component.get("downloads", {}).values() if download.get("sha256")
    }) if trust in ("bundled", "official") else []
    index["revoked"] = previous.get("revoked", [])
    index["blocked_sha256"] = previous.get("blocked_sha256", [])
    index["revoked_keys"] = previous.get("revoked_keys", [])
    schema = load_schema(repo, "index.schema.json")
    problems = []
    check_schema(index, schema, schema, "", problems)
    if problems:
        raise SystemExit("index: " + "; ".join(f"{p}: {r}" for p, r in problems))
    text = json.dumps(index, indent=2, ensure_ascii=False) + "\n"
    (repo / "index.json").write_bytes(text.encode("utf-8"))
    signature = repo / "index.json.sig"
    if signature.exists():
        signature.unlink()
    print(f"index.json: sequence {sequence}, {len(plugins)} plugins, expires {index['expires']}")
    for name in plugin_manual.pack_all(repo, package_files):
        print(f"manual/{name}.emuplugin: packed, in no list")
    print("Not signed yet: run `plugin_tool.py sign --key <private key>`.")


def pin_cores(repo, args):
    lock = {}
    for folder in plugin_folders(repo):
        for component in load_json(folder / "plugin.json").get("components", []):
            if component["type"] != "libretro-core":
                continue
            for platform, download in component.get("downloads", {}).items():
                if "url" not in download or f"{component['id']}:{platform}" in lock:
                    continue
                print(f"downloading {download['url']}")
                with urllib.request.urlopen(download["url"], timeout=60) as response:
                    data = response.read(MAX_UNPINNED_SIZE + 1)
                if len(data) > MAX_UNPINNED_SIZE:
                    raise SystemExit("larger than 256 MiB")
                lock[f"{component['id']}:{platform}"] = {
                    "core": component["id"], "platform": platform, "upstream": download["url"],
                    "license": component.get("license", ""),
                    "fetched": datetime.date.today().isoformat(),
                    "sha256": hashlib.sha256(data).hexdigest(), "size": len(data)}
    (repo / "cores.lock.json").write_text(json.dumps(lock, indent=2) + "\n", encoding="utf-8",
                                          newline="\n")
    print(f"cores.lock.json: {len(lock)} downloads. Mirror them in a release, then put the "
          "mirror's url, sha256 and size into the manifests and drop \"integrity\".")


def cmd_validate(repo, args):
    targets = plugin_folders(repo) + plugin_manual.manual_folders(repo) if args.all else \
        [pathlib.Path(p) for p in args.paths]
    if not targets:
        raise SystemExit("nothing to validate: name a plugin folder or pass --all")
    failed = False
    for target in [t for t in targets if (t / "addon.json").exists()]:
        targets.remove(target)
        problems = validate_addon(target.resolve(), repo, args.namespace, args.trust)
        for path, reason in problems:
            print(f"{target}: {path or 'addon.json'}: {reason}")
        failed = failed or bool(problems)
        if not problems:
            print(f"{target}: ok")
    for target in targets:
        file = target / "plugin.json" if target.is_dir() else target
        try:
            manifest = load_json(file)
            errors = validate_manifest(manifest, repo, args.trust, args.namespace,
                                       target if target.is_dir() else None)
        except (ValueError, OSError) as error:
            errors, manifest = [("", str(error))], None
        for path, reason in errors:
            print(f"{file}: {path or 'plugin.json'}: {reason}")
        failed = failed or bool(errors)
        if not errors:
            print(f"{file}: ok ({manifest['id']} {manifest['version']}, code: {code_class(manifest)})")
            if ignored := ignored_fields(manifest):
                print("  warning: not read by EmuDEN yet (docs/manifest.md): " +
                      ", ".join(path for path, _ in ignored))
            if target.is_dir():
                package_files(target)
    if args.all:
        for name, schema_name in (("addons.json", "addons.schema.json"),
                                  ("index.json", "index.schema.json")):
            if (repo / name).exists():
                schema, problems = load_schema(repo, schema_name), []
                check_schema(load_json(repo / name), schema, schema, "", problems)
                for path, reason in problems:
                    print(f"{name}: {path}: {reason}")
                failed = failed or bool(problems)
                if not problems:
                    print(f"{name}: ok")
        for folder in addon_folders(repo):
            problems = validate_addon(folder, repo, args.namespace, args.trust)
            for path, reason in problems:
                print(f"{folder}: {path or 'addon.json'}: {reason}")
            failed = failed or bool(problems)
            if not problems:
                print(f"{folder}: ok")
    return 1 if failed else 0


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--repo", default=".", help="the repository root (default: here)")
    commands = parser.add_subparsers(dest="command", required=True)

    def trust_options(command, default):
        command.add_argument("--trust", default=default,
                             choices=["bundled", "official", "third-party", "developer"],
                             help="where the plugins will come from, which decides what they may hold")
        command.add_argument("--namespace", help="the lower-case GitHub owner of the repository")

    validate = commands.add_parser("validate", help="check plugin folders")
    validate.add_argument("paths", nargs="*")
    validate.add_argument("--all", action="store_true")
    trust_options(validate, "third-party")
    assemble = commands.add_parser(
        "assemble", help="write a feature plugin's files, shared libraries included, to a "
        "folder (EmuDEN's developer folder plugins-dev/<id>, to try it unsigned)")
    assemble.add_argument("path")
    assemble.add_argument("-o", "--out", required=True)
    packer = commands.add_parser("pack", help="write a .emuplugin or .emuaddon package")
    packer.add_argument("path")
    packer.add_argument("-o", "--out", default=None)
    index = commands.add_parser("index", help="pack every plugin and write index.json")
    index.add_argument("--sequence", type=int)
    index.add_argument("--days", type=int, default=90, help="how long the list is valid (max 120)")
    index.add_argument("--base-url", help="where the packages will be downloaded from; "
                       "default: the packages/ folder next to index.json")
    index.add_argument("--name")
    index.add_argument("--homepage")
    trust_options(index, "third-party")
    for name in ("sign", "keygen"):
        command = commands.add_parser(name)
        command.add_argument("--key", required=True, help="the private key file (PEM)")
    commands.add_parser("verify", help="check index.json.sig against keys/source.pub")
    tester = commands.add_parser("test", help="run the offline Lua tests of plugin folders "
                                 "(tests/<id>/*test.lua; every plugin and example that has some)")
    tester.add_argument("paths", nargs="*")
    tester.add_argument("--lua", help="a Lua 5.4 interpreter (default: $LUA, then lua5.4, lua54, lua)")
    commands.add_parser("pin-cores", help="download every core and record its checksum")

    args = parser.parse_args()
    repo = pathlib.Path(args.repo).resolve()
    if args.command == "validate":
        return cmd_validate(repo, args)
    if args.command == "test":
        return plugin_test.run(repo, [pathlib.Path(p) for p in args.paths], args.lua)
    if args.command == "assemble":
        out = pathlib.Path(args.out)
        for name, data in package_files(pathlib.Path(args.path)):
            (out / name).parent.mkdir(parents=True, exist_ok=True)
            (out / name).write_bytes(data)
        print(out)
        return 0
    if args.command == "pack":
        folder = pathlib.Path(args.path)
        out = pathlib.Path(args.out) if args.out else repo / "packages"
        if (folder / "addon.json").exists():
            problems = validate_addon(folder.resolve(), repo)
            for path, reason in problems:
                print(f"{folder.name}: {path or 'addon.json'}: {reason}", file=sys.stderr)
            if problems:
                return 1
            print(pack_addon(folder, out))
            return 0
        errors = validate_manifest(load_json(folder / "plugin.json"), repo, "developer")
        for path, reason in errors:
            print(f"{folder.name}: {path}: {reason}", file=sys.stderr)
        if errors:
            return 1
        print(pack(folder, pathlib.Path(args.out) if args.out else repo / "packages"))
        return 0
    {"index": build_index, "sign": plugin_sign.sign, "verify": plugin_sign.verify, "keygen": plugin_sign.keygen,
     "pin-cores": pin_cores}[args.command](repo, args)
    return 0


if __name__ == "__main__":
    sys.exit(main())
