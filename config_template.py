#!/usr/bin/env python3
"""Config template helper for anf_interactive.sh

Reads a template from stdin, substitutes {{variable}} placeholders using
values from the YAML config (variables + secrets), and writes the result
to stdout. Designed to be more robust than large inline python -c
fragments, especially on Windows/Git Bash.
"""

import sys
import os
import json
from typing import Dict, Any

try:
    import yaml  # type: ignore
except Exception as exc:  # pragma: no cover - surfaced by shell script
    print(f"ERROR: PyYAML is required: {exc}", file=sys.stderr)
    sys.exit(1)


def _to_native_path(path: str) -> str:
    """Convert a Git-Bash style path (/d/...) to a native Windows path if needed.

    On non-Windows platforms, the path is returned unchanged.
    """

    if sys.platform == "win32" and path.startswith("/"):
        # Handle /d/dir/file style paths that Git Bash produces
        if len(path) > 2 and path[2] == "/":
            drive = path[1:2]
            rest = path[3:]
            return drive + ":\\" + rest.replace("/", "\\")
    return path


def _load_all_vars(config_path: str) -> Dict[str, Any]:
    config_path = _to_native_path(config_path)
    with open(config_path, encoding="utf-8") as f:
        config = yaml.safe_load(f) or {}
    variables = config.get("variables", {}) or {}
    secrets = config.get("secrets", {}) or {}
    merged: Dict[str, Any] = {}
    merged.update(variables)
    merged.update(secrets)
    return merged


def _substitute(template: str, all_vars: Dict[str, Any], mode: str) -> str:
    data = template

    for key, value in all_vars.items():
        # Special handling for source_peer_addresses so multiple IPs
        # can be represented as a JSON array in the template body.
        if key == "source_peer_addresses" and "{{source_peer_addresses}}" in data:
            try:
                parsed_addrs = json.loads(str(value))
                if isinstance(parsed_addrs, list):
                    json_array = json.dumps(parsed_addrs)
                    data = data.replace('["{{' + key + '}}"]', json_array)
                else:
                    data = data.replace("{{" + key + "}}", str(value))
            except (json.JSONDecodeError, TypeError):
                data = data.replace("{{" + key + "}}", str(value))
        else:
            data = data.replace("{{" + key + "}}", str(value))

    if mode == "body":
        # For request bodies, try to pretty-print JSON for readability.
        try:
            parsed = json.loads(data)
            return json.dumps(parsed, indent=2)
        except Exception:
            return data
    else:
        # URL mode: just return the substituted text.
        return data


def main(argv: list[str]) -> int:
    if len(argv) < 3 or argv[1] not in {"url", "body"}:
        print("Usage: config_template.py [url|body] <config_file>", file=sys.stderr)
        return 1

    mode = "body" if argv[1] == "body" else "url"
    config_file = argv[2]

    try:
        all_vars = _load_all_vars(config_file)
    except FileNotFoundError:
        print(f"ERROR: Config file not found: {config_file}", file=sys.stderr)
        return 1
    except Exception as exc:
        print(f"ERROR: Failed to load config '{config_file}': {exc}", file=sys.stderr)
        return 1

    template = sys.stdin.read()
    result = _substitute(template, all_vars, mode)
    sys.stdout.write(result)
    return 0


if __name__ == "__main__":  # pragma: no cover
    raise SystemExit(main(sys.argv))
