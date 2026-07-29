#!/usr/bin/env python3
"""Verify an OpenBao Transit Ed25519 signature over canonical manifest bytes."""

from __future__ import annotations

import argparse
import base64
import json
from pathlib import Path

from cryptography.hazmat.primitives.serialization import load_pem_public_key


def canonical_manifest(path: Path) -> bytes:
    value = json.loads(path.read_text(encoding="utf-8"))
    return json.dumps(
        value,
        sort_keys=True,
        separators=(",", ":"),
        ensure_ascii=False,
    ).encode("utf-8")


def decode_openbao_signature(value: str) -> bytes:
    # OpenBao returns: vault:v<key-version>:<base64-signature>
    parts = value.strip().split(":", 2)
    if len(parts) != 3 or parts[0] not in {"vault", "bao"}:
        raise ValueError("Formato de firma Transit no reconocido")
    return base64.b64decode(parts[2], validate=True)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--public-key", required=True)
    parser.add_argument("--manifest", required=True)
    parser.add_argument("--signature", required=True)
    args = parser.parse_args()

    public_key = load_pem_public_key(Path(args.public_key).read_bytes())
    signature = decode_openbao_signature(
        Path(args.signature).read_text(encoding="utf-8")
    )
    public_key.verify(signature, canonical_manifest(Path(args.manifest)))
    print("Firma Ed25519 válida")


if __name__ == "__main__":
    main()
