#!/usr/bin/env python3
"""Verify manifest structure, part sizes and SHA-256 hashes."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
from pathlib import Path
from typing import Any

HEX_64 = re.compile(r"^[0-9a-f]{64}$")
EXPECTED_TYPE = "full_logical_pg_dump_custom_age_encrypted_split_signed"


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def validate_manifest(manifest: dict[str, Any]) -> None:
    require(manifest.get("schema_version") == 5, "schema_version no válida")
    require(manifest.get("backup_type") == EXPECTED_TYPE, "backup_type no válido")
    require(manifest.get("format") == "pg_dump_custom", "format no válido")

    encryption = manifest.get("encryption")
    require(isinstance(encryption, dict), "Falta encryption")
    require(encryption.get("algorithm") == "age", "Algoritmo no válido")

    for key in ("age_recipient_sha256", "plaintext_sha256", "encrypted_sha256"):
        require(
            isinstance(encryption.get(key), str)
            and bool(HEX_64.fullmatch(encryption[key])),
            f"{key} no válido",
        )

    parts = manifest.get("parts")
    require(isinstance(parts, list) and parts, "No hay partes")
    require(manifest.get("part_count") == len(parts), "part_count no coincide")

    for part in parts:
        require(
            isinstance(part, dict)
            and set(part) == {"name", "size_bytes", "sha256"},
            "Estructura de parte no válida",
        )
        name = part["name"]
        require(
            isinstance(name, str)
            and name.startswith("encrypted_backups/")
            and ".." not in name
            and name.endswith(".part"),
            "Nombre de parte no válido",
        )
        require(
            isinstance(part["size_bytes"], int) and part["size_bytes"] > 0,
            "Tamaño de parte no válido",
        )
        require(
            isinstance(part["sha256"], str)
            and bool(HEX_64.fullmatch(part["sha256"])),
            "SHA-256 de parte no válido",
        )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", required=True)
    args = parser.parse_args()

    manifest_path = Path(args.manifest)
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    validate_manifest(manifest)

    for part in manifest["parts"]:
        path = Path(part["name"])
        require(path.is_file(), f"Falta la parte {path}")
        require(path.stat().st_size == part["size_bytes"], f"Tamaño incorrecto: {path}")
        require(sha256_file(path) == part["sha256"], f"SHA-256 incorrecta: {path}")

    print(f"Backup válido: {manifest_path} ({len(manifest['parts'])} partes)")


if __name__ == "__main__":
    main()
