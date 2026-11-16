# SPDX-FileCopyrightText: Copyright 2026 EmuDEN contributors
# SPDX-License-Identifier: GPL-3.0-or-later
"""The source key and the signatures of index.json and of the manual packages (Ed25519). Uses the Python package
`cryptography` when it is installed, else the `openssl` program (3.0 or newer)."""

import base64
import hashlib
import pathlib
import subprocess
import tempfile

from plugin_addons import sha256_file
import plugin_manual
from plugin_schema import load_json

try:
    from cryptography.hazmat.primitives import serialization
    from cryptography.hazmat.primitives.asymmetric import ed25519
    from cryptography.exceptions import InvalidSignature
except ImportError:  # the openssl program instead
    ed25519 = None

# SubjectPublicKeyInfo of an Ed25519 key: a fixed 12-byte header, then the key.
SPKI_HEADER = bytes.fromhex("302a300506032b6570032100")


def openssl(*args):
    try:
        done = subprocess.run(["openssl", *args], capture_output=True, check=False)
    except FileNotFoundError:
        raise SystemExit("neither the Python package cryptography nor the openssl program was found; "
                         "install one of them (pip install cryptography, or OpenSSL 3)")
    if done.returncode != 0:
        raise SystemExit("openssl failed: " + done.stderr.decode(errors="replace").strip())
    return done.stdout


def load_private(path):
    key = serialization.load_pem_private_key(pathlib.Path(path).read_bytes(), password=None)
    if not isinstance(key, ed25519.Ed25519PrivateKey):
        raise SystemExit("that is not an Ed25519 key")
    return key


def public_key_of(private_key):
    """The raw 32-byte Ed25519 public key of a PEM private key, as base64."""
    if ed25519 is not None:
        raw = load_private(private_key).public_key().public_bytes(serialization.Encoding.Raw,
                                                                  serialization.PublicFormat.Raw)
        return base64.b64encode(raw).decode()
    der = openssl("pkey", "-in", str(private_key), "-pubout", "-outform", "DER")
    if len(der) != 44:
        raise SystemExit("that is not an Ed25519 key")
    return base64.b64encode(der[-32:]).decode()


def fingerprint(public_b64):
    digest = hashlib.sha256(base64.b64decode(public_b64)).hexdigest()[:16]
    return " ".join(digest[i:i + 4] for i in range(0, 16, 4))


def generate(path):
    """Writes a new private key (PEM) to `path`."""
    if ed25519 is not None:
        pem = ed25519.Ed25519PrivateKey.generate().private_bytes(
            serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8, serialization.NoEncryption())
        pathlib.Path(path).write_bytes(pem)
        return
    openssl("genpkey", "-algorithm", "ed25519", "-out", str(path))


def sign_bytes(private_key, path):
    """The 64-byte signature of the file at `path`."""
    if ed25519 is not None:
        return load_private(private_key).sign(pathlib.Path(path).read_bytes())
    with tempfile.TemporaryDirectory() as temp:
        out = pathlib.Path(temp) / "sig"
        openssl("pkeyutl", "-sign", "-inkey", str(private_key), "-rawin", "-in", str(path), "-out", str(out))
        return out.read_bytes()


def verify_bytes(public_raw, signature, path, what="index.json.sig"):
    """Stops when the signature of the file at `path` is not good."""
    if ed25519 is not None:
        try:
            ed25519.Ed25519PublicKey.from_public_bytes(public_raw).verify(signature, pathlib.Path(path).read_bytes())
        except InvalidSignature:
            raise SystemExit(f"{what} is not a good signature")
        return
    with tempfile.TemporaryDirectory() as temp:
        temp = pathlib.Path(temp)
        (temp / "pub.der").write_bytes(SPKI_HEADER + public_raw)
        (temp / "sig").write_bytes(signature)
        openssl("pkeyutl", "-verify", "-pubin", "-inkey", str(temp / "pub.der"), "-keyform", "DER",
                "-rawin", "-in", str(path), "-sigfile", str(temp / "sig"))


# --- the commands keygen, sign and verify ------------------------------------------------------

def keygen(repo, args):
    key = pathlib.Path(args.key).expanduser()
    if key.exists():
        raise SystemExit(f"{key} exists already; a source keeps one key for good")
    if repo.resolve() in key.resolve().parents:
        raise SystemExit("keep the private key outside the repository")
    key.parent.mkdir(parents=True, exist_ok=True)
    generate(key)
    public = public_key_of(key)
    (repo / "keys").mkdir(exist_ok=True)
    (repo / "keys" / "source.pub").write_text(public + "\n", encoding="ascii", newline="\n")
    print(f"private key: {key}  (never commit or share it)")
    print(f"public key:  keys/source.pub, fingerprint {fingerprint(public)}")


def sign(repo, args):
    key = pathlib.Path(args.key).expanduser()
    published = (repo / "keys" / "source.pub").read_text(encoding="ascii").strip()
    if public_key_of(key) != published:
        raise SystemExit("this key is not the one in keys/source.pub")
    signature = sign_bytes(key, repo / "index.json")
    if len(signature) != 64:
        raise SystemExit("unexpected signature size")
    (repo / "index.json.sig").write_text(base64.b64encode(signature).decode() + "\n",
                                         encoding="ascii", newline="\n")
    from plugin_tool import package_files
    plugin_manual.sign_all(repo, package_files, sign_bytes, key)
    verify(repo, args)


def verify(repo, args):
    public = base64.b64decode((repo / "keys" / "source.pub").read_text(encoding="ascii").strip())
    signature = base64.b64decode((repo / "index.json.sig").read_text(encoding="ascii").strip())
    verify_bytes(public, signature, repo / "index.json")
    index = load_json(repo / "index.json")
    for entry in index["plugins"]:
        url = entry["package"]["url"]
        if "://" not in url:
            package = repo / url
            if not package.exists() or sha256_file(package) != entry["package"]["sha256"]:
                raise SystemExit(f"{url} is not the package the index lists; run `index` again")
    print(f"index.json.sig is good (key {fingerprint(base64.b64encode(public).decode())}, "
          f"sequence {index['sequence']}, expires {index['expires']})")
    for name in plugin_manual.verify_all(repo, verify_bytes, public):
        print(f"manual/{name}.emuplugin is signed (installed by hand, in no list)")
