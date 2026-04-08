#!/usr/bin/env python3
"""
Rotate selected .env variables for a given deployment environment.

Config sources (project root):
  1) .env.rotation.yml (preferred)
  2) .devops.yml

Supported config shapes:
  # .env.rotation.yml
  length: 20
  variables:
    - POSTGRES_PASSWORD
    - AIRFLOW_DB_PASSWORD

  # .devops.yml
  secret_rotation:
    length: 20
    variables:
      - POSTGRES_PASSWORD
      - AIRFLOW_DB_PASSWORD

  # optional per-env extension in both files:
  secret_rotation:
    variables_by_env:
      dev: [POSTGRES_PASSWORD]
      staging: [POSTGRES_PASSWORD, AIRFLOW_DB_PASSWORD]
      prod: [POSTGRES_PASSWORD, AIRFLOW_DB_PASSWORD]
"""

from __future__ import annotations

import argparse
import os
import re
import secrets
import string
import sys
from pathlib import Path
from typing import Any

try:
    import yaml
except Exception as exc:  # pragma: no cover
    print(f"[ERROR] Missing dependency PyYAML: {exc}", file=sys.stderr)
    sys.exit(2)


ENV_NAME_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")
ENV_LINE_RE = re.compile(r"^(\s*)(export\s+)?([A-Za-z_][A-Za-z0-9_]*?)=(.*)$")


def _load_yaml(path: Path) -> dict[str, Any]:
    if not path.exists():
        return {}
    with path.open("r", encoding="utf-8") as f:
        data = yaml.safe_load(f) or {}
    if not isinstance(data, dict):
        return {}
    return data


def _read_rotation_config(project_dir: Path, env_name: str) -> tuple[list[str], int]:
    defaults_length = 16
    merged_vars: list[str] = []
    length: int | None = None

    def merge_from(data: dict[str, Any]) -> None:
        nonlocal length
        if not data:
            return

        section = data.get("secret_rotation")
        if isinstance(section, dict):
            if length is None and isinstance(section.get("length"), int):
                length = section["length"]
            if isinstance(section.get("variables"), list):
                for item in section["variables"]:
                    if isinstance(item, str):
                        merged_vars.append(item.strip())
            by_env = section.get("variables_by_env")
            if isinstance(by_env, dict):
                env_values = by_env.get(env_name)
                if isinstance(env_values, list):
                    for item in env_values:
                        if isinstance(item, str):
                            merged_vars.append(item.strip())

        # Also support top-level keys for simple config files.
        if length is None and isinstance(data.get("length"), int):
            length = data["length"]
        if isinstance(data.get("variables"), list):
            for item in data["variables"]:
                if isinstance(item, str):
                    merged_vars.append(item.strip())
        if length is None and isinstance(data.get("secret_rotation_length"), int):
            length = data["secret_rotation_length"]
        if isinstance(data.get("secret_rotation_variables"), list):
            for item in data["secret_rotation_variables"]:
                if isinstance(item, str):
                    merged_vars.append(item.strip())

    # Priority: dedicated file first, then .devops.yml.
    merge_from(_load_yaml(project_dir / ".env.rotation.yml"))
    merge_from(_load_yaml(project_dir / ".devops.yml"))

    seen: set[str] = set()
    result_vars: list[str] = []
    for raw in merged_vars:
        name = raw.strip()
        if not name or name in seen:
            continue
        if not ENV_NAME_RE.match(name):
            continue
        seen.add(name)
        result_vars.append(name)

    effective_length = length if isinstance(length, int) and length > 0 else defaults_length
    return result_vars, effective_length


def _generate_secret(length: int) -> str:
    if length < 8:
        raise ValueError("length must be >= 8")

    lowers = string.ascii_lowercase
    uppers = string.ascii_uppercase
    digits = string.digits
    symbols = "@%+=_-"
    alphabet = lowers + uppers + digits + symbols

    chars = [
        secrets.choice(lowers),
        secrets.choice(uppers),
        secrets.choice(digits),
        secrets.choice(symbols),
    ]
    chars.extend(secrets.choice(alphabet) for _ in range(length - 4))
    secrets.SystemRandom().shuffle(chars)
    return "".join(chars)


def _rotate_env_file(env_file: Path, var_names: list[str], length: int) -> tuple[int, int]:
    if not env_file.exists():
        raise FileNotFoundError(f"Missing env file: {env_file}")

    raw_lines = env_file.read_text(encoding="utf-8").splitlines(keepends=True)
    values = {name: _generate_secret(length) for name in var_names}

    found: set[str] = set()
    out_lines: list[str] = []
    replaced = 0

    for line in raw_lines:
        m = ENV_LINE_RE.match(line)
        if not m:
            out_lines.append(line)
            continue

        indent, export_kw, key, _rest = m.groups()
        if key not in values:
            out_lines.append(line)
            continue

        found.add(key)
        export_part = export_kw or ""
        newline = "\n" if line.endswith("\n") else ""
        out_lines.append(f"{indent}{export_part}{key}={values[key]}{newline}")
        replaced += 1

    added = 0
    missing = [name for name in var_names if name not in found]
    if missing and out_lines and not out_lines[-1].endswith("\n"):
        out_lines[-1] = out_lines[-1] + "\n"
    for name in missing:
        out_lines.append(f"{name}={values[name]}\n")
        added += 1

    st = env_file.stat()
    tmp_file = env_file.with_suffix(env_file.suffix + ".tmp")
    tmp_file.write_text("".join(out_lines), encoding="utf-8")
    os.chmod(tmp_file, st.st_mode)
    os.replace(tmp_file, env_file)
    return replaced, added


def main() -> int:
    parser = argparse.ArgumentParser(description="Rotate selected secrets in .env.<env> files")
    parser.add_argument("--project-dir", required=True, help="Project root directory")
    parser.add_argument("--env", required=True, choices=["dev", "staging", "prod"], help="Target environment")
    parser.add_argument("--length", type=int, default=None, help="Override generated secret length")
    args = parser.parse_args()

    project_dir = Path(args.project_dir).resolve()
    env_name = args.env

    var_names, config_length = _read_rotation_config(project_dir, env_name)
    if not var_names:
        print(
            "[WARN] No rotation variables configured. "
            "Add .env.rotation.yml or secret_rotation.variables in .devops.yml.",
            file=sys.stderr,
        )
        return 3

    length = args.length if args.length is not None else config_length
    if length < 8:
        print("[ERROR] Invalid length: must be >= 8", file=sys.stderr)
        return 2

    env_file = project_dir / f".env.{env_name}"
    try:
        replaced, added = _rotate_env_file(env_file, var_names, length)
    except FileNotFoundError as exc:
        print(f"[ERROR] {exc}", file=sys.stderr)
        return 4
    except Exception as exc:  # pragma: no cover
        print(f"[ERROR] Failed to rotate secrets: {exc}", file=sys.stderr)
        return 1

    print(
        f"[OK] Rotation complete for {env_file} | "
        f"vars={len(var_names)} replaced={replaced} added={added} length={length}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
