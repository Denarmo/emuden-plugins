# SPDX-FileCopyrightText: Copyright 2026 EmuDEN contributors
# SPDX-License-Identifier: GPL-3.0-or-later
"""Console plugins that are installed by hand: manual/<id>/plugin.json. They are in no list.
`index` packs each into manual/<id>.emuplugin, `sign` puts plugin.json.sig (the source key's
signature of plugin.json) into it, and `verify` checks both. EmuDEN installs such a file under
Settings > Plugins > Install a console from a file as one of its own plugins when the signature
is good."""

import base64
import pathlib
import zipfile

SIGNATURE = "plugin.json.sig"


def manual_folders(repo):
    return sorted(p.parent for p in (repo / "manual").glob("*/plugin.json"))


def package_path(repo, folder):
    return repo / "manual" / f"{folder.name}.emuplugin"


def write_package(target, files):
    """The same input always gives the same bytes."""
    with zipfile.ZipFile(target, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for name, data in files:
            info = zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o644 << 16
            archive.writestr(info, data)


def pack_all(repo, package_files):
    """Unsigned packages; `sign` adds the signatures."""
    out = []
    for folder in manual_folders(repo):
        write_package(package_path(repo, folder), package_files(folder))
        out.append(folder.name)
    return out


def sign_all(repo, package_files, sign_bytes, key):
    for folder in manual_folders(repo):
        signature = sign_bytes(key, folder / "plugin.json")
        if len(signature) != 64:
            raise SystemExit("unexpected signature size")
        files = [(n, d) for n, d in package_files(folder) if n != SIGNATURE]
        files.append((SIGNATURE, (base64.b64encode(signature).decode() + "\n").encode("ascii")))
        write_package(package_path(repo, folder), files)


def verify_all(repo, verify_bytes, public_raw):
    names = []
    for folder in manual_folders(repo):
        package = package_path(repo, folder)
        if not package.exists():
            raise SystemExit(f"{package.name} is missing; run `index` and `sign` again")
        with zipfile.ZipFile(package) as archive:
            manifest = archive.read("plugin.json")
            try:
                signature = base64.b64decode(archive.read(SIGNATURE))
            except KeyError:
                raise SystemExit(f"{package.name} is not signed; run `sign`")
        if manifest != (folder / "plugin.json").read_bytes():
            raise SystemExit(f"{package.name} is not {folder.name}/plugin.json; run `index` and `sign` again")
        with_bytes = pathlib.Path(package.with_suffix(".check"))
        with_bytes.write_bytes(manifest)
        try:
            verify_bytes(public_raw, signature, with_bytes, f"{package.name}: {SIGNATURE}")
        finally:
            with_bytes.unlink()
        names.append(folder.name)
    return names
