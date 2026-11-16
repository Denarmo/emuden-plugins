# SPDX-FileCopyrightText: Copyright 2026 EmuDEN contributors
# SPDX-License-Identifier: GPL-3.0-or-later
"""The small JSON Schema checker plugin_tool.py uses (the subset the schemas in schema/ use)."""

import json
import pathlib
import re


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
