#!/usr/bin/env python3
"""
Standardize Docker Compose labels for dynamic monitoring discovery.

Mandatory labels per service (namespace configurable):
  - <label_prefix>.project
  - <label_prefix>.env
  - <label_prefix>.service
"""

from __future__ import annotations

import argparse
import shutil
import sys
from pathlib import Path
from typing import Any, Iterable

import yaml

DEFAULT_PROJECT_LABEL = "${PROJECT_NAME}"
DEFAULT_ENV_LABEL = "${ENV}"
DEFAULT_LABEL_PREFIX = "cic"


def namespaced_key(label_prefix: str, suffix: str) -> str:
    return f"{label_prefix}.{suffix}"


def unique(values: Iterable[str]) -> list[str]:
    seen: set[str] = set()
    output: list[str] = []
    for value in values:
        if value in seen:
            continue
        seen.add(value)
        output.append(value)
    return output


def equivalent_keys(label_prefix: str, suffix: str, include_legacy_cic: bool = False) -> list[str]:
    keys = [
        namespaced_key(label_prefix, suffix),
        f"${{LABEL_NAMESPACE}}.{suffix}",
        f"${{LABEL_NAMESPACE:-{DEFAULT_LABEL_PREFIX}}}.{suffix}",
    ]
    if include_legacy_cic and label_prefix != DEFAULT_LABEL_PREFIX:
        keys.append(namespaced_key(DEFAULT_LABEL_PREFIX, suffix))
    return unique(keys)


def infer_env_from_filename(compose_file: Path) -> str:
    name = compose_file.name
    if "docker-compose.dev" in name:
        return "dev"
    if "docker-compose.staging" in name:
        return "staging"
    if "docker-compose.prod" in name:
        return "prod"
    return DEFAULT_ENV_LABEL


def to_key_set(keys: str | Iterable[str]) -> set[str]:
    if isinstance(keys, str):
        return {keys}
    return set(keys)


def get_label_value(labels: Any, keys: str | Iterable[str]) -> str | None:
    key_set = to_key_set(keys)

    if isinstance(labels, dict):
        for key in key_set:
            value = labels.get(key)
            if value is not None:
                return str(value)
        return None

    if isinstance(labels, list):
        for item in labels:
            if isinstance(item, str) and "=" in item:
                current_key, current_value = item.split("=", 1)
                if current_key.strip() in key_set:
                    return current_value.strip()
            elif isinstance(item, dict):
                for key in key_set:
                    if key in item:
                        value = item.get(key)
                        return None if value is None else str(value)
    return None


def set_label_value(labels: Any, key: str, value: str, aliases: Iterable[str] | None = None) -> tuple[Any, bool]:
    aliases = list(aliases or [])
    candidate_keys = unique([key, *aliases])
    changed = False

    if labels is None:
        return [f"{key}={value}"], True

    if isinstance(labels, dict):
        candidate_found = False
        for candidate in candidate_keys:
            if candidate in labels:
                candidate_found = True
                if candidate != key:
                    labels.pop(candidate, None)
                    labels[key] = value
                    changed = True
                elif labels.get(key) != value:
                    labels[key] = value
                    changed = True

        if not candidate_found:
            labels[key] = value
            changed = True

        for alias in aliases:
            if alias in labels:
                labels.pop(alias, None)
                changed = True

        return labels, changed

    if isinstance(labels, list):
        found_index: int | None = None
        found_as_dict = False
        duplicate_indexes: list[int] = []

        for idx, item in enumerate(labels):
            item_key: str | None = None
            if isinstance(item, str) and "=" in item:
                item_key = item.split("=", 1)[0].strip()
            elif isinstance(item, dict):
                for candidate in candidate_keys:
                    if candidate in item:
                        item_key = candidate
                        break

            if item_key in candidate_keys:
                if found_index is None:
                    found_index = idx
                    found_as_dict = isinstance(item, dict)
                else:
                    duplicate_indexes.append(idx)

        for idx in reversed(duplicate_indexes):
            del labels[idx]
            changed = True

        expected = f"{key}={value}"

        if found_index is None:
            labels.append(expected)
            return labels, True

        existing = labels[found_index]
        if found_as_dict and isinstance(existing, dict):
            for alias in aliases:
                if alias in existing:
                    existing.pop(alias, None)
                    changed = True
            if existing.get(key) != value:
                existing[key] = value
                changed = True
        else:
            if existing != expected:
                labels[found_index] = expected
                changed = True

        return labels, changed

    raise TypeError("Unsupported labels type")


def normalize_service_name(raw_service_name: str, project_name: str, env_value: str) -> str:
    name = raw_service_name

    prefixes = [
        "__PROJECT_NAME__-",
        "${PROJECT_NAME}-",
    ]
    if project_name:
        prefixes.append(f"{project_name}-")

    for prefix in prefixes:
        if name.startswith(prefix):
            name = name[len(prefix) :]
            break

    suffixes = [
        "-__ENV__",
        "-${ENV}",
        "-${ENV:-dev}",
        "-dev",
        "-staging",
        "-prod",
    ]
    if env_value and env_value != DEFAULT_ENV_LABEL:
        suffixes.insert(0, f"-{env_value}")

    for suffix in suffixes:
        if name.endswith(suffix):
            name = name[: -len(suffix)]
            break

    return name or raw_service_name


def infer_service_label(
    service_name: str,
    service_data: dict[str, Any],
    project_name: str,
    env_value: str,
    label_prefix: str,
) -> str:
    labels = service_data.get("labels")
    label_keys = unique([
        *equivalent_keys(label_prefix, "service", include_legacy_cic=True),
        "service",
    ])
    value = get_label_value(labels, label_keys)
    if value:
        return value
    return normalize_service_name(service_name, project_name, env_value)


def process_compose_file(
    compose_file: Path,
    project_name: str,
    label_prefix: str,
    mode: str,
    dry_run: bool,
    with_backup: bool,
) -> tuple[bool, list[str], str]:
    raw_content = compose_file.read_text(encoding="utf-8")
    try:
        data = yaml.safe_load(raw_content) or {}
    except Exception as exc:
        return False, [f"{compose_file}: YAML invalide ({exc})"], "error"

    if not isinstance(data, dict):
        return False, [f"{compose_file}: structure YAML non supportee"], "error"

    services = data.get("services")
    if not isinstance(services, dict):
        return False, [], "skipped"

    env_value = infer_env_from_filename(compose_file)
    issues: list[str] = []
    changed = False

    for service_name, service_data in services.items():
        if not isinstance(service_data, dict):
            continue

        service_label = infer_service_label(
            str(service_name),
            service_data,
            project_name,
            env_value,
            label_prefix,
        )
        desired_by_suffix = {
            "project": project_name,
            "env": env_value,
            "service": service_label,
        }

        labels = service_data.get("labels")

        for suffix, expected_value in desired_by_suffix.items():
            check_keys = equivalent_keys(label_prefix, suffix, include_legacy_cic=False)
            current_value = get_label_value(labels, check_keys)
            if current_value != expected_value:
                issues.append(
                    f"{compose_file.name}:{service_name}: {namespaced_key(label_prefix, suffix)} "
                    f"attendu='{expected_value}' actuel='{current_value or 'absent'}'"
                )

        if mode == "sync":
            local_labels = service_data.get("labels")
            for suffix, expected_value in desired_by_suffix.items():
                key = namespaced_key(label_prefix, suffix)
                aliases = equivalent_keys(label_prefix, suffix, include_legacy_cic=True)
                aliases = [candidate for candidate in aliases if candidate != key]
                try:
                    local_labels, local_changed = set_label_value(
                        local_labels,
                        key,
                        expected_value,
                        aliases=aliases,
                    )
                except TypeError:
                    issues.append(f"{compose_file.name}:{service_name}: type de labels non supporte")
                    continue
                if local_changed:
                    changed = True
            service_data["labels"] = local_labels

    if mode == "check":
        return False, issues, "checked"

    if not changed:
        return False, issues, "unchanged"

    rendered = yaml.safe_dump(
        data,
        sort_keys=False,
        default_flow_style=False,
        allow_unicode=False,
        width=120,
    )

    if dry_run:
        return True, issues, "dry-run"

    if with_backup:
        backup_file = compose_file.with_suffix(compose_file.suffix + ".bak")
        shutil.copy2(compose_file, backup_file)

    compose_file.write_text(rendered, encoding="utf-8")
    return True, issues, "updated"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Standardise les labels <namespace>.* dans les fichiers docker-compose."
    )
    parser.add_argument(
        "--deployment-dir",
        default="deployment",
        help="Dossier contenant les docker-compose*.yml (defaut: deployment).",
    )
    parser.add_argument(
        "--project-name",
        default=DEFAULT_PROJECT_LABEL,
        help=f"Valeur du label <namespace>.project (defaut: {DEFAULT_PROJECT_LABEL}).",
    )
    parser.add_argument(
        "--label-prefix",
        default=DEFAULT_LABEL_PREFIX,
        help=f"Namespace de labels (defaut: {DEFAULT_LABEL_PREFIX}).",
    )
    parser.add_argument(
        "--mode",
        choices=("sync", "check"),
        default="sync",
        help="sync: corrige les fichiers, check: verifie seulement.",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Affiche les fichiers a mettre a jour sans les modifier.",
    )
    parser.add_argument(
        "--no-backup",
        action="store_true",
        help="N'ecrit pas de .bak avant modification.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    label_prefix = (args.label_prefix or "").strip()
    if not label_prefix:
        print("[ERROR] --label-prefix ne peut pas etre vide", file=sys.stderr)
        return 1

    deployment_dir = Path(args.deployment_dir)

    if not deployment_dir.exists():
        print(f"[ERROR] Dossier introuvable: {deployment_dir}", file=sys.stderr)
        return 1

    compose_files = sorted(
        file for file in deployment_dir.glob("docker-compose*.yml") if file.is_file()
    )
    if not compose_files:
        print(f"[WARN] Aucun fichier docker-compose*.yml trouve dans {deployment_dir}")
        return 0

    total_issues: list[str] = []
    updated_files: list[Path] = []
    checked_files = 0

    for compose_file in compose_files:
        changed, issues, status = process_compose_file(
            compose_file=compose_file,
            project_name=args.project_name,
            label_prefix=label_prefix,
            mode=args.mode,
            dry_run=args.dry_run,
            with_backup=not args.no_backup,
        )
        checked_files += 1
        total_issues.extend(issues)
        if changed:
            updated_files.append(compose_file)
        if status == "error":
            print(f"[ERROR] {issues[0] if issues else compose_file}")

    if args.mode == "check":
        if total_issues:
            print(f"[ERROR] Labels {label_prefix}.* non conformes:")
            for issue in total_issues:
                print(f"  - {issue}")
            return 1
        print(f"[OK] Tous les services sont conformes ({checked_files} fichier(s) verifie(s)).")
        return 0

    if args.dry_run:
        if updated_files:
            print("[INFO] Fichiers a mettre a jour:")
            for file in updated_files:
                print(f"  - {file}")
        else:
            print("[OK] Aucun changement necessaire.")
    else:
        if updated_files:
            print(f"[OK] Labels {label_prefix}.* standardises dans:")
            for file in updated_files:
                print(f"  - {file}")
        else:
            print("[OK] Aucun changement necessaire.")

    if total_issues:
        print("[WARN] Points detectes pendant la standardisation:")
        for issue in total_issues:
            print(f"  - {issue}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
