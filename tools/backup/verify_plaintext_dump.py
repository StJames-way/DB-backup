#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("manifest", type=Path)
    parser.add_argument("dump", type=Path)
    args = parser.parse_args()

    document = json.loads(args.manifest.read_text(encoding="utf-8"))
    encryption = document.get("encryption")
    if not isinstance(encryption, dict):
        raise SystemExit("El manifiesto no contiene encryption")
    expected = encryption.get("plaintext_sha256")
    if not isinstance(expected, str):
        raise SystemExit("El manifiesto no contiene encryption.plaintext_sha256")
    actual = sha256_file(args.dump)
    if actual != expected:
        raise SystemExit(f"SHA-256 del dump incorrecto: esperado {expected}, obtenido {actual}")
    print(f"SHA-256 del dump correcto: {actual}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
