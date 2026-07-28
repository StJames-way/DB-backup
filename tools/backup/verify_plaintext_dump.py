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


parser = argparse.ArgumentParser()
parser.add_argument("manifest", type=Path)
parser.add_argument("dump", type=Path)
args = parser.parse_args()
manifest = json.loads(args.manifest.read_text(encoding="utf-8"))
expected = manifest["plaintext_dump_sha256"]
actual = sha256_file(args.dump)
if actual != expected:
    raise SystemExit(f"SHA-256 del dump descifrado incorrecto: {actual} != {expected}")
print("SHA-256 del dump descifrado verificado")
