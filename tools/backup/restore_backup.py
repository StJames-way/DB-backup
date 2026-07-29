#!/usr/bin/env python3
"""Fail-closed verification, reconstruction and decryption of one backup set."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any


def fail(message: str) -> None:
    raise SystemExit(f"ERROR: {message}")


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def run(command: list[str], *, env: dict[str, str] | None = None) -> None:
    subprocess.run(command, check=True, env=env)


def require_program(name: str) -> None:
    if shutil.which(name) is None:
        fail(f"No se encuentra el programa requerido: {name}")


def load_manifest(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        fail(f"No se puede leer el manifiesto: {error}")

    if not isinstance(value, dict):
        fail("El manifiesto no es un objeto JSON")
    return value


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", required=True, type=Path)
    parser.add_argument("--signature", required=True, type=Path)
    parser.add_argument("--public-key", required=True, type=Path)
    parser.add_argument("--age-identity", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument(
        "--allow-existing-output",
        action="store_true",
        help="Permite sobrescribir --output; no usar en restauraciones ordinarias",
    )
    args = parser.parse_args()

    for program in ("age", "pg_restore", "python3"):
        require_program(program)

    for path in (
        args.manifest,
        args.signature,
        args.public_key,
        args.age_identity,
    ):
        if not path.is_file():
            fail(f"Falta el fichero: {path}")

    if args.output.exists() and not args.allow_existing_output:
        fail(f"El destino ya existe: {args.output}")

    script_dir = Path(__file__).resolve().parent
    verify_set = script_dir / "verify_backup_set.py"
    verify_signature = script_dir / "verify_signature.py"

    # Primero integridad de todas las partes y después autenticidad del manifiesto.
    run(["python3", str(verify_set), "--manifest", str(args.manifest)])
    run(
        [
            "python3",
            str(verify_signature),
            "--public-key",
            str(args.public_key),
            "--manifest",
            str(args.manifest),
            "--signature",
            str(args.signature),
        ]
    )

    manifest = load_manifest(args.manifest)
    parts = manifest.get("parts")
    encryption = manifest.get("encryption")
    if not isinstance(parts, list) or not isinstance(encryption, dict):
        fail("Manifiesto incompleto")

    expected_encrypted = encryption.get("encrypted_sha256")
    expected_plaintext = encryption.get("plaintext_sha256")
    if not isinstance(expected_encrypted, str) or not isinstance(
        expected_plaintext, str
    ):
        fail("Faltan hashes del cifrado o del dump")

    output_parent = args.output.resolve().parent
    output_parent.mkdir(parents=True, exist_ok=True)

    old_umask = os.umask(0o077)
    try:
        with tempfile.TemporaryDirectory(
            prefix=".restore-",
            dir=output_parent,
        ) as temporary:
            temp_dir = Path(temporary)
            encrypted = temp_dir / "backup.dump.age"
            plaintext = temp_dir / "backup.dump"

            with encrypted.open("xb") as destination:
                for part in parts:
                    part_path = Path(part["name"])
                    with part_path.open("rb") as source:
                        shutil.copyfileobj(source, destination, 1024 * 1024)

            if sha256_file(encrypted) != expected_encrypted:
                fail("SHA-256 del cifrado reconstruido no coincide")

            run(
                [
                    "age",
                    "--decrypt",
                    "--identity",
                    str(args.age_identity),
                    "--output",
                    str(plaintext),
                    str(encrypted),
                ]
            )

            if sha256_file(plaintext) != expected_plaintext:
                fail("SHA-256 del dump descifrado no coincide")

            # Validación estructural antes de mover el dump al destino final.
            run(["pg_restore", "--list", str(plaintext)])

            if args.output.exists():
                args.output.unlink()
            os.replace(plaintext, args.output)
            os.chmod(args.output, 0o600)
    finally:
        os.umask(old_umask)

    print(f"Dump verificado y descifrado: {args.output}")
    print("El script no lo ha restaurado en ninguna base de datos.")
    print("Ejecuta pg_restore contra una base vacía y aislada.")


if __name__ == "__main__":
    main()
