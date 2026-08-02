#!/usr/bin/env python3
"""Validate the public recovery trust contract without private keys."""

from __future__ import annotations

import argparse
import base64
import hashlib
import json
import re
import sys
from pathlib import Path
from typing import NoReturn


def fail(message: str) -> NoReturn:
    print(f"ROJO: {message}", file=sys.stderr)
    raise SystemExit(1)


def read_json(path: Path) -> dict:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        fail(f"No se pudo leer {path}: {exc}")
    if not isinstance(value, dict):
        fail("El contrato de confianza debe ser un objeto JSON")
    return value


def public_key_der(path: Path) -> bytes:
    try:
        text = path.read_text(encoding="ascii").strip()
    except OSError as exc:
        fail(f"No se pudo leer la clave pública: {exc}")

    match = re.fullmatch(
        r"-----BEGIN PUBLIC KEY-----\s+([A-Za-z0-9+/=\s]+)"
        r"-----END PUBLIC KEY-----",
        text,
    )
    if not match:
        fail("La clave pública no es un PEM PUBLIC KEY válido")

    try:
        return base64.b64decode(
            re.sub(r"\s+", "", match.group(1)),
            validate=True,
        )
    except ValueError as exc:
        fail(f"Base64 PEM inválido: {exc}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--trust",
        type=Path,
        default=Path("config/backup-recovery-trust.json"),
    )
    parser.add_argument(
        "--public-key",
        type=Path,
        default=Path("config/backup-signing-public-key.pem"),
    )
    args = parser.parse_args()

    trust = read_json(args.trust)
    encryption = trust.get("encryption")
    signature = trust.get("signature")
    if not isinstance(encryption, dict) or not isinstance(signature, dict):
        fail("Faltan los bloques encryption o signature")

    recipient = encryption.get("approved_recipient")
    expected_recipient_sha = encryption.get("approved_recipient_sha256")
    if not isinstance(recipient, str) or not recipient.startswith("age1"):
        fail("approved_recipient no parece un recipient age")
    if not isinstance(expected_recipient_sha, str):
        fail("Falta approved_recipient_sha256")

    actual_recipient_sha = hashlib.sha256(
        recipient.encode("utf-8")
    ).hexdigest()
    if actual_recipient_sha != expected_recipient_sha:
        fail(
            "El SHA-256 del recipient no coincide: "
            f"{actual_recipient_sha} != {expected_recipient_sha}"
        )

    expected_key_sha = signature.get("public_key_sha256_der")
    if not isinstance(expected_key_sha, str):
        fail("Falta public_key_sha256_der")

    actual_key_sha = hashlib.sha256(
        public_key_der(args.public_key)
    ).hexdigest()
    if actual_key_sha != expected_key_sha:
        fail(
            "La huella DER de la clave pública no coincide: "
            f"{actual_key_sha} != {expected_key_sha}"
        )

    print("VERDE: contrato público de recuperación correcto")
    print(f"Recipient: {recipient}")
    print(f"Recipient SHA-256: {actual_recipient_sha}")
    print(f"Signing key SHA-256 DER: {actual_key_sha}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
