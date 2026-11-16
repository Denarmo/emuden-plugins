# SPDX-FileCopyrightText: Copyright 2026 EmuDEN contributors
# SPDX-License-Identifier: GPL-3.0-or-later
"""Switch 2 add-ons (addons/<program id>/<id>/addon.json): checks, packages, addons.json."""

import hashlib
import json
import pathlib
import sys
import zipfile

from plugin_schema import check_schema, load_json, load_schema

EXECUTABLE_EXTENSIONS = (".exe", ".dll", ".so", ".dylib", ".bat", ".cmd", ".com", ".ps1", ".sh",
                         ".py", ".js", ".vbs", ".msi", ".scr", ".jar", ".appimage", ".lnk")
EXECUTABLE_MAGICS = (b"MZ", b"\x7fELF", b"#!", b"\xcf\xfa\xed\xfe", b"\xce\xfa\xed\xfe",
                     b"\xfe\xed\xfa\xcf", b"\xfe\xed\xfa\xce", b"\xca\xfe\xba\xbe")


def sha256_file(path):
    return hashlib.sha256(pathlib.Path(path).read_bytes()).hexdigest()


ADDON_FOLDERS = ("blobs", "exefs", "romfs", "romfslite", "romfs_ext", "cheats", "font", "data",
                 "screenshots")
ADDON_FILE_LAYERS = ("exefs", "romfs", "romfslite", "romfs_ext", "cheats")
ADDON_CAPABILITIES = ("addon.code_patch", "addon.transform.bfotf_add_glyphs",
                      "addon.literal.scene_aspect")
MAX_ADDON_BYTES = 2 << 30


def addon_folders(repo):
    return sorted(p.parent for p in (repo / "addons").glob("*/*/addon.json"))


def addon_files(folder):
    files = []
    for path in sorted(folder.rglob("*")):
        if path.is_dir():
            continue
        name = path.relative_to(folder).as_posix()
        if path.is_symlink() or not (name in ("addon.json", "icon.png") or
                                     name.split("/")[0] in ADDON_FOLDERS and "/" in name):
            raise SystemExit(f"{folder.name}: {name} does not belong in an add-on package "
                             "(addon.json, icon.png, " + "/, ".join(ADDON_FOLDERS) + "/)")
        data = path.read_bytes()
        if name.lower().endswith(EXECUTABLE_EXTENSIONS) or data.startswith(EXECUTABLE_MAGICS):
            raise SystemExit(f"{folder.name}: {name} is a program; an add-on holds none")
        files.append((name, data))
    if sum(len(d) for _, d in files) > MAX_ADDON_BYTES:
        raise SystemExit(f"{folder.name}: more than 2 GiB")
    return files


def validate_addon(folder, repo, namespace=None, trust="third-party"):
    """The problems of an add-on folder, as (path, reason)."""
    problems = []
    try:
        manifest = load_json(folder / "addon.json")
    except (ValueError, OSError) as error:
        return [("", str(error))]
    schema = load_schema(repo, "addon.schema.json")
    check_schema(manifest, schema, schema, "", problems)
    if problems:
        return problems
    if folder.name != manifest["id"] or folder.parent.name != manifest["program_id"]:
        problems.append(("id", "the folder is addons/<program_id>/<id>"))
    if namespace and trust == "third-party" and manifest["id"].split(".")[0] != namespace:
        problems.append(("id", f"must start with {namespace}."))
    for need in manifest["needs"]:
        if need not in ADDON_CAPABILITIES:
            problems.append(("needs", f"{need} is not something EmuDEN has"))
    names = {name for name, _ in addon_files(folder)}
    wanted = set()

    def needs_file(path, name):
        if not name or name not in names or name.split("/")[0] not in ("blobs", "font", "data"):
            problems.append((path, f"{name or 'the file'} is not in blobs/, font/ or data/"))

    for i, layer in enumerate(manifest["layers"]):
        at = f"layers[{i}]"
        kind = layer["type"]
        if kind in ADDON_FILE_LAYERS:
            if layer.get("dir") != kind or set(layer) - {"type", "dir"}:
                problems.append((at, f"a {kind} layer is {{\"type\": \"{kind}\", \"dir\": \"{kind}\"}}"))
            elif not any(name.startswith(kind + "/") for name in names):
                problems.append((at, f"the folder {kind}/ is empty or missing"))
        elif kind == "nso-patch":
            wanted.add("addon.code_patch")
            if not layer.get("module") or not layer.get("build_id") or not layer.get("records"):
                problems.append((at, "module, build_id and records are needed"))
            for j, record in enumerate(layer.get("records", [])):
                if ("bytes" in record) == ("bytes_file" in record):
                    problems.append((f"{at}.records[{j}]", "one of bytes and bytes_file"))
                elif "bytes_file" in record:
                    needs_file(f"{at}.records[{j}].bytes_file", record["bytes_file"])
            for literal in layer.get("literals", []):
                wanted.add("addon.literal." + literal["from"])
        elif kind == "transform":
            wanted.add("addon.transform." + layer.get("transform", ""))
            if not layer.get("target", "").startswith("romfs:/"):
                problems.append((at, "target is a romfs:/ path"))
            for key in ("glyphs_file", "charstrings_file"):
                needs_file(f"{at}.{key}", layer.get(key))
    for need in sorted(wanted - set(manifest["needs"])):
        problems.append(("needs", f"{need} is missing"))
    return problems


def pack_addon(folder, out_dir):
    """Writes <id>-<version>.emuaddon; the same input always gives the same bytes."""
    manifest = load_json(folder / "addon.json")
    out_dir.mkdir(parents=True, exist_ok=True)
    target = out_dir / f"{manifest['id']}-{manifest['version']}.emuaddon"
    with zipfile.ZipFile(target, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for name, data in addon_files(folder):
            info = zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o644 << 16
            archive.writestr(info, data)
    return target


def build_catalogue(repo, base, namespace=None, trust="third-party"):
    """Packs every folder of addons/ and rewrites its entry in addons.json. Titles, tags and
    entries without a folder stay as they are."""
    file = repo / "addons.json"
    catalogue = load_json(file) if file.exists() else {"catalogue_version": 1, "titles": [],
                                                       "addons": []}
    entries = {entry["id"]: entry for entry in catalogue.get("addons", [])}
    titles = {title["program_id"] for title in catalogue.get("titles", [])}
    for folder in addon_folders(repo):
        problems = validate_addon(folder, repo, namespace, trust)
        if problems:
            for path, reason in problems:
                print(f"{folder}: {path or 'addon.json'}: {reason}", file=sys.stderr)
            raise SystemExit(1)
        manifest = load_json(folder / "addon.json")
        if manifest["program_id"] not in titles:
            raise SystemExit(f"addons.json: add {manifest['program_id']} and the game's name to "
                             "\"titles\" first")
        package = pack_addon(folder, repo / "packages")
        builds = manifest.get("builds", [])
        entries[manifest["id"]] = {
            "id": manifest["id"], "name": manifest["name"], "version": manifest["version"],
            "summary": manifest.get("summary", ""), "authors": manifest.get("authors", []),
            "tags": entries.get(manifest["id"], {}).get("tags", []),
            "program_id": manifest["program_id"],
            "game_versions": sorted({b["game_version"] for b in builds if b.get("game_version")}),
            "build_ids": sorted({b["build_id"].upper() for b in builds}),
            "needs": manifest["needs"],
            "layer_types": sorted({layer["type"] for layer in manifest["layers"]}),
            "package": {"url": base + package.name, "sha256": sha256_file(package),
                        "size": package.stat().st_size},
        }
    if not file.exists() and not entries:
        return
    catalogue["addons"] = sorted(entries.values(), key=lambda e: (e["program_id"], e["id"]))
    file.write_bytes((json.dumps(catalogue, indent=2, ensure_ascii=False) + "\n").encode("utf-8"))
    print(f"addons.json: {len(catalogue['addons'])} add-ons")
