#!/usr/bin/env python3
# SPDX-FileCopyrightText: Copyright 2026 Lichii Emulator Project
# SPDX-License-Identifier: GPL-3.0-or-later
"""Builds and checks an EmuDEN plugin repository. Standard library only; signing calls the
`openssl` program (3.0 or newer).

    python -I tools/plugin_tool.py validate plugins/emuden.nes        one plugin
    python -I tools/plugin_tool.py validate --all                     everything in the repository
    python -I tools/plugin_tool.py pack plugins/jdoe.wiiu-cemu        -> packages/<id>-<version>.emuplugin
    python -I tools/plugin_tool.py index --sequence 2                 packs all, writes index.json
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
import subprocess
import sys
import tempfile
import urllib.request
import zipfile

HOST_CAPABILITIES = ["engine.libretro", "engine.external", "engine.switch2", "engine.pcstore",
                     "settings.v1", "content.multi_file", "content.magic"]
PLATFORMS = ["windows-x86_64", "linux-x86_64", "linux-aarch64", "macos-arm64", "android-arm64"]
LAUNCH_VARIABLES = ["rom", "rom_dir", "rom_name", "emulator_dir", "data_dir", "save_dir",
                    "bios_dir", "platform"]
DENIED_ENV = ["PATH", "HOME", "USERPROFILE", "APPDATA", "LOCALAPPDATA", "TEMP", "TMP", "SHELL",
              "COMSPEC", "IFS"]
DENIED_ENV_PREFIXES = ["LD_", "DYLD_", "XDG_", "QT_", "STEAM_", "WINE", "PROTON", "PYTHON", "SDL_",
                       "VK_", "__", "EMUDEN_"]
GLOBAL_KEYS = ["video.fullscreen", "audio.volume", "audio.mute", "general.pause_in_background"]
PLAYER_KEYS = ["picture", "fast_forward", "run_ahead", "screen_size", "border", "volume",
               "mute_fast_forward", "low_latency"]
RESERVED_SYSTEM_IDS = ["global", "defaults", "local", "dev"]
UNPINNED_HOST = "buildbot.libretro.com"
MAX_UNPINNED_SIZE = 256 * 1024 * 1024
PACKAGE_FILES = re.compile(r"^(plugin\.json|icon\.png|assets/.+|LICENSE[^/]*|README[^/]*)$")
EXECUTABLE_EXTENSIONS = (".exe", ".dll", ".so", ".dylib", ".bat", ".cmd", ".com", ".ps1", ".sh",
                         ".py", ".js", ".vbs", ".msi", ".scr", ".jar", ".appimage", ".lnk")
EXECUTABLE_MAGICS = (b"MZ", b"\x7fELF", b"#!", b"\xcf\xfa\xed\xfe", b"\xce\xfa\xed\xfe",
                     b"\xfe\xed\xfa\xcf", b"\xfe\xed\xfa\xce", b"\xca\xfe\xba\xbe")
MAX_PACKAGE_FILES = 256
MAX_PACKAGE_BYTES = 16 * 1024 * 1024
MAX_EXPIRY_DAYS = 120

# A field that changes what runs, what is written or what is synced needs a capability, so an
# older EmuDEN refuses the manifest instead of reading half of it.
FIELD_CAPABILITIES = [
    (lambda m: bool(m.get("settings")), "settings.v1"),
    (lambda m: any(s.get("content", {}).get("multi_file") for s in m.get("systems", [])),
     "content.multi_file"),
    (lambda m: any(s.get("content", {}).get("magic") for s in m.get("systems", [])),
     "content.magic"),
]


# --- a small JSON Schema checker (the subset the schemas in schema/ use) ---------------------

def _type_ok(value, name):
    return {
        "object": isinstance(value, dict),
        "array": isinstance(value, list),
        "string": isinstance(value, str),
        "boolean": isinstance(value, bool),
        "null": value is None,
        "integer": isinstance(value, int) and not isinstance(value, bool),
        "number": isinstance(value, (int, float)) and not isinstance(value, bool),
    }[name]


def check_schema(value, schema, root, path, errors):
    if "$ref" in schema:
        target = root
        for part in schema["$ref"].lstrip("#/").split("/"):
            target = target[part]
        check_schema(value, target, root, path, errors)
        return
    if "anyOf" in schema:
        if not any(not _collect(value, option, root) for option in schema["anyOf"]):
            errors.append((path, "fits none of the allowed forms"))
        return
    if "type" in schema:
        names = schema["type"] if isinstance(schema["type"], list) else [schema["type"]]
        if not any(_type_ok(value, name) for name in names):
            errors.append((path, "must be " + " or ".join(names)))
            return
    if "enum" in schema and value not in schema["enum"]:
        errors.append((path, "must be one of " + ", ".join(json.dumps(e) for e in schema["enum"])))
    if isinstance(value, str):
        if "pattern" in schema and not re.search(schema["pattern"], value):
            errors.append((path, "has the wrong form"))
        if len(value) < schema.get("minLength", 0):
            errors.append((path, "must not be empty"))
        if len(value) > schema.get("maxLength", 1 << 30):
            errors.append((path, "too long"))
    if isinstance(value, (int, float)) and not isinstance(value, bool):
        if "minimum" in schema and value < schema["minimum"]:
            errors.append((path, f"must be at least {schema['minimum']}"))
        if "maximum" in schema and value > schema["maximum"]:
            errors.append((path, f"must be at most {schema['maximum']}"))
    if isinstance(value, list):
        if len(value) < schema.get("minItems", 0) or len(value) > schema.get("maxItems", 1 << 30):
            errors.append((path, "has the wrong number of items"))
        if "items" in schema:
            for i, item in enumerate(value):
                check_schema(item, schema["items"], root, f"{path}[{i}]", errors)
    if isinstance(value, dict):
        properties = schema.get("properties", {})
        for key in schema.get("required", []):
            if key not in value:
                errors.append((f"{path}.{key}".lstrip("."), "missing"))
        if len(value) < schema.get("minProperties", 0):
            errors.append((path, "must not be empty"))
        extra = schema.get("additionalProperties", True)
        for key, item in value.items():
            child = f"{path}.{key}".lstrip(".")
            if key in properties:
                check_schema(item, properties[key], root, child, errors)
            elif extra is False:
                errors.append((child, "unknown key"))
            elif isinstance(extra, dict):
                check_schema(item, extra, root, child, errors)


def _collect(value, schema, root):
    errors = []
    check_schema(value, schema, root, "", errors)
    return errors


def load_schema(repo, name):
    return json.loads((repo / "schema" / name).read_text(encoding="utf-8"))


def load_json(path):
    def no_duplicates(pairs):
        keys = [key for key, _ in pairs]
        for key in keys:
            if keys.count(key) > 1:
                raise ValueError(f"key given twice: {key}")
        return dict(pairs)
    return json.loads(pathlib.Path(path).read_text(encoding="utf-8"),
                      object_pairs_hook=no_duplicates)


# --- manifest rules that a schema cannot say ---------------------------------------------------

def template_error(text, setting_keys, allow_value=False):
    for name in re.findall(r"\{([^}]*)\}", text):
        if name.startswith("setting:"):
            if name[len("setting:"):] not in setting_keys:
                return f"unknown setting in {{{name}}}"
        elif name not in LAUNCH_VARIABLES and not (allow_value and name == "value"):
            return f"unknown variable {{{name}}}"
    if text.count("{") != len(re.findall(r"\{[^}]*\}", text)):
        return "unclosed '{'"
    return None


def env_name_allowed(name):
    return (re.fullmatch(r"[A-Z][A-Z0-9_]{0,63}", name) is not None and name not in DENIED_ENV
            and not any(name.startswith(prefix) for prefix in DENIED_ENV_PREFIXES))


def safe_relative(path):
    return (bool(path) and not path.startswith("/") and "\\" not in path and ":" not in path
            and "{" not in path and ".." not in path.split("/"))


def url_host(url):
    return url.split("://", 1)[-1].split("/", 1)[0].lower()


def validate_manifest(manifest, repo, trust="third-party", namespace=None):
    """Returns a list of (json path, reason)."""
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
    if kind == "console" and not engine:
        err("engine", "missing")
    if kind != "console" and engine:
        err("engine", "only a console has an engine")
    if kind == "tweak-tool" and not reserved:
        err("kind", "only EmuDEN's own plugins change PC game folders")
    if (engine == "switch2" and not reserved) or (engine == "pcstore" and trust != "bundled"):
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

    fitting = {"libretro-core": "libretro", "external-emulator": "external", "engine": "switch2"}
    for i, component in enumerate(manifest.get("components", [])):
        path = f"components[{i}]"
        kind_of = component["type"]
        if kind_of in ("engine", "tool") and not reserved:
            err(f"{path}.type", "only EmuDEN's own plugins have this type")
        if kind_of in fitting and fitting[kind_of] != engine:
            err(f"{path}.type", "does not fit the plugin's engine")
        if "delivery" in component and kind_of != "engine":
            err(f"{path}.delivery", "only for an engine")
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
        launch = component.get("launch")
        if kind_of == "external-emulator" and launch is None:
            err(f"{path}.launch", "missing")
        if kind_of != "external-emulator" and launch is not None:
            err(f"{path}.launch", "only an external emulator is launched")
        if launch:
            for platform in launch["executable"]:
                if platform not in PLATFORMS:
                    err(f"{path}.launch.executable.{platform}", "unknown platform")
            for j, arg in enumerate(launch["args"]):
                if problem := template_error(arg, setting_keys):
                    err(f"{path}.launch.args[{j}]", problem)
            for name, text in launch.get("env", {}).items():
                if not env_name_allowed(name):
                    err(f"{path}.launch.env.{name}", "this environment variable may not be set")
                elif problem := template_error(text, setting_keys):
                    err(f"{path}.launch.env.{name}", problem)
            for j, created in enumerate(launch.get("create_files", [])):
                relative = re.sub(r"^\{(data_dir|emulator_dir)\}/", "", created["path"])
                if not safe_relative(relative):
                    err(f"{path}.launch.create_files[{j}].path",
                        "must be a relative path in the emulator's or the data folder")
            own = launch.get("user_provided_setting")
            if own:
                setting = next((s for s in settings if s["key"] == own), None)
                if (not setting or setting["type"] != "path" or setting.get("path_kind") != "file"
                        or "launch_var" not in setting["apply"]):
                    err(f"{path}.launch.user_provided_setting",
                        "must name a file setting applied as launch_var")

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
            if components.get(core, {}).get("type") != "libretro-core":
                err(f"{path}.cores", f"{core} is not a core of the plugin")
        emulator = system.get("emulator")
        if engine == "external" and not emulator:
            err(f"{path}.emulator", "missing")
        if emulator and components.get(emulator, {}).get("type") != "external-emulator":
            err(f"{path}.emulator", "not an emulator of the plugin")
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
             "args": "external", "args_if_true": "external", "args_if_false": "external",
             "env": "external", "launch_var": "external", "native_setting": "switch2"}
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
        if form.startswith("args"):
            if form != "args" and setting["type"] != "toggle":
                err(f"{path}.apply.{form}", "only for a toggle")
            for arg in apply[form]:
                if problem := template_error(arg, setting_keys, allow_value=form == "args"):
                    err(f"{path}.apply.{form}", problem)
        if form == "env" and not env_name_allowed(apply["env"]):
            err(f"{path}.apply.env", "this environment variable may not be set")
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
        if kind != "console" or engine not in ("libretro", "external", "switch2"):
            err("sync", "this kind of plugin never syncs")
        if sync.get("paths") and engine != "external":
            err("sync.paths", "only for the external engine")
        ids = [p["id"] for p in sync.get("paths", [])]
        if len(set(ids)) != len(ids):
            err("sync.paths", "an id is used twice")
    return errors


def code_class(manifest, trusted=()):
    """none, cores or external: what the plugin makes run on any platform."""
    result = "none"
    for component in manifest.get("components", []):
        if component["type"] == "external-emulator":
            return "external"
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
            downloads = [c.get("downloads", {}) for c in components]
            if any(downloads) and not any(platform in d or "any" in d for d in downloads):
                continue
        elif engine == "external":
            if not any(platform in c.get("launch", {}).get("executable", {})
                       or c.get("launch", {}).get("user_provided_setting") for c in components):
                continue
        elif engine == "switch2":
            if not any(platform in c.get("delivery", {}) for c in components):
                continue
        out.append(platform)
    return out


def sample_argv(manifest):
    """The command line a sample game would be started with, for `validate` to print."""
    for component in manifest.get("components", []):
        launch = component.get("launch")
        if not launch:
            continue
        values = {"rom": "/games/Sample Game.rom", "rom_dir": "/games", "rom_name": "Sample Game",
                  "emulator_dir": f"<emuden>/emulators/{component['id']}/{component.get('version', '0')}",
                  "data_dir": f"<emuden>/plugin-data/{manifest['id']}", "save_dir": "<emuden>/saves",
                  "bios_dir": "<emuden>/bios", "platform": "<platform>"}
        defaults = {s["key"]: s.get("default", "") for s in manifest.get("settings", [])}

        def expand(text, value=None):
            def one(match):
                name = match.group(1)
                if name == "value":
                    return str(value).lower() if isinstance(value, bool) else str(value)
                if name.startswith("setting:"):
                    return str(defaults.get(name[8:], ""))
                return values[name]
            return re.sub(r"\{([^}]*)\}", one, text)

        argv = [next(iter(launch["executable"].values()))] + [expand(a) for a in launch["args"]]
        for setting in manifest.get("settings", []):
            apply, value = setting["apply"], setting.get("default")
            if "args" in apply:
                argv += [expand(a, value) for a in apply["args"]]
            if "args_if_true" in apply and value is True:
                argv += [expand(a) for a in apply["args_if_true"]]
            if "args_if_false" in apply and value is False:
                argv += [expand(a) for a in apply["args_if_false"]]
        return argv
    return None


# --- packages, index, signatures ---------------------------------------------------------------

def package_files(folder):
    files = []
    for path in sorted(folder.rglob("*")):
        if path.is_dir():
            continue
        name = path.relative_to(folder).as_posix()
        if path.is_symlink() or not PACKAGE_FILES.match(name):
            raise SystemExit(f"{folder.name}: {name} does not belong in a plugin package "
                             "(plugin.json, icon.png, assets/, LICENSE*, README*)")
        data = path.read_bytes()
        if name.lower().endswith(EXECUTABLE_EXTENSIONS) or data.startswith(EXECUTABLE_MAGICS):
            raise SystemExit(f"{folder.name}: {name} is a program; a plugin package holds none")
        files.append((name, data))
    if len(files) > MAX_PACKAGE_FILES or sum(len(d) for _, d in files) > MAX_PACKAGE_BYTES:
        raise SystemExit(f"{folder.name}: more than 256 files or 16 MiB")
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


def sha256_file(path):
    return hashlib.sha256(pathlib.Path(path).read_bytes()).hexdigest()


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
        errors = validate_manifest(manifest, repo, trust, namespace)
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
    print("Not signed yet: run `plugin_tool.py sign --key <private key>`.")


def openssl(*args, data=None):
    try:
        done = subprocess.run(["openssl", *args], input=data, capture_output=True, check=False)
    except FileNotFoundError:
        raise SystemExit("the openssl program was not found; install OpenSSL 3")
    if done.returncode != 0:
        raise SystemExit("openssl failed: " + done.stderr.decode(errors="replace").strip())
    return done.stdout


def public_key_of(private_key):
    """The raw 32-byte Ed25519 public key of a PEM private key, as base64."""
    der = openssl("pkey", "-in", str(private_key), "-pubout", "-outform", "DER")
    if len(der) != 44:
        raise SystemExit("that is not an Ed25519 key")
    return base64.b64encode(der[-32:]).decode()


def fingerprint(public_b64):
    digest = hashlib.sha256(base64.b64decode(public_b64)).hexdigest()[:16]
    return " ".join(digest[i:i + 4] for i in range(0, 16, 4))


def keygen(repo, args):
    key = pathlib.Path(args.key).expanduser()
    if key.exists():
        raise SystemExit(f"{key} exists already; a source keeps one key for good")
    if repo.resolve() in key.resolve().parents:
        raise SystemExit("keep the private key outside the repository")
    key.parent.mkdir(parents=True, exist_ok=True)
    openssl("genpkey", "-algorithm", "ed25519", "-out", str(key))
    public = public_key_of(key)
    (repo / "keys").mkdir(exist_ok=True)
    (repo / "keys" / "source.pub").write_text(public + "\n", encoding="ascii", newline="\n")
    print(f"private key: {key}  (never commit or share it)")
    print(f"public key:  keys/source.pub, fingerprint {fingerprint(public)}")


def sign(repo, args):
    key = pathlib.Path(args.key).expanduser()
    index = repo / "index.json"
    public = public_key_of(key)
    published = (repo / "keys" / "source.pub").read_text(encoding="ascii").strip()
    if public != published:
        raise SystemExit("this key is not the one in keys/source.pub")
    with tempfile.TemporaryDirectory() as temp:
        out = pathlib.Path(temp) / "sig"
        openssl("pkeyutl", "-sign", "-inkey", str(key), "-rawin", "-in", str(index),
                "-out", str(out))
        signature = out.read_bytes()
    if len(signature) != 64:
        raise SystemExit("unexpected signature size")
    (repo / "index.json.sig").write_text(base64.b64encode(signature).decode() + "\n",
                                         encoding="ascii", newline="\n")
    verify(repo, args)


def verify(repo, args):
    public = base64.b64decode((repo / "keys" / "source.pub").read_text(encoding="ascii").strip())
    signature = base64.b64decode((repo / "index.json.sig").read_text(encoding="ascii").strip())
    # SubjectPublicKeyInfo of an Ed25519 key: a fixed 12-byte header, then the key.
    der = bytes.fromhex("302a300506032b6570032100") + public
    with tempfile.TemporaryDirectory() as temp:
        temp = pathlib.Path(temp)
        (temp / "pub.der").write_bytes(der)
        (temp / "sig").write_bytes(signature)
        openssl("pkeyutl", "-verify", "-pubin", "-inkey", str(temp / "pub.der"), "-keyform", "DER",
                "-rawin", "-in", str(repo / "index.json"), "-sigfile", str(temp / "sig"))
    index = load_json(repo / "index.json")
    for entry in index["plugins"]:
        url = entry["package"]["url"]
        if "://" not in url:
            package = repo / url
            if not package.exists() or sha256_file(package) != entry["package"]["sha256"]:
                raise SystemExit(f"{url} is not the package the index lists; run `index` again")
    print(f"index.json.sig is good (key {fingerprint(base64.b64encode(public).decode())}, "
          f"sequence {index['sequence']}, expires {index['expires']})")


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
    targets = plugin_folders(repo) if args.all else [pathlib.Path(p) for p in args.paths]
    if not targets:
        raise SystemExit("nothing to validate: name a plugin folder or pass --all")
    failed = False
    for target in targets:
        file = target / "plugin.json" if target.is_dir() else target
        try:
            manifest = load_json(file)
            errors = validate_manifest(manifest, repo, args.trust, args.namespace)
        except (ValueError, OSError) as error:
            errors, manifest = [("", str(error))], None
        for path, reason in errors:
            print(f"{file}: {path or 'plugin.json'}: {reason}")
        failed = failed or bool(errors)
        if not errors:
            line = f"{file}: ok ({manifest['id']} {manifest['version']}, code: {code_class(manifest)})"
            argv = sample_argv(manifest)
            print(line + (f"\n  would run: {argv}" if argv else ""))
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
        addon_schema = load_schema(repo, "addon.schema.json")
        for file in sorted((repo / "addons").glob("*/*/addon.json")):
            problems = []
            check_schema(load_json(file), addon_schema, addon_schema, "", problems)
            for path, reason in problems:
                print(f"{file}: {path}: {reason}")
            failed = failed or bool(problems)
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
    packer = commands.add_parser("pack", help="write a .emuplugin package")
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
    commands.add_parser("pin-cores", help="download every core and record its checksum")

    args = parser.parse_args()
    repo = pathlib.Path(args.repo).resolve()
    if args.command == "validate":
        return cmd_validate(repo, args)
    if args.command == "pack":
        folder = pathlib.Path(args.path)
        errors = validate_manifest(load_json(folder / "plugin.json"), repo, "developer")
        for path, reason in errors:
            print(f"{folder.name}: {path}: {reason}", file=sys.stderr)
        if errors:
            return 1
        print(pack(folder, pathlib.Path(args.out) if args.out else repo / "packages"))
        return 0
    {"index": build_index, "sign": sign, "verify": verify, "keygen": keygen,
     "pin-cores": pin_cores}[args.command](repo, args)
    return 0


if __name__ == "__main__":
    sys.exit(main())
