#!/usr/bin/env python3
"""Build a deterministic JSON manifest for an encrypted split backup."""

from __future__ import annotations

import argparse
import glob
import hashlib
import json
import re
from pathlib import Path

HEX_64 = re.compile(r"^[0-9a-f]{64}$")


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def require_sha256(value: str, label: str) -> str:
    if not HEX_64.fullmatch(value):
        raise ValueError(f"{label} debe ser SHA-256 hexadecimal en minúsculas")
    return value


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--parts-glob", required=True)
    parser.add_argument("--plaintext-sha256", required=True)
    parser.add_argument("--encrypted-sha256", required=True)
    parser.add_argument("--age-recipient-sha256", required=True)
    parser.add_argument("--created-at-utc", required=True)
    parser.add_argument("--timestamp-madrid", required=True)
    parser.add_argument("--repository", required=True)
    parser.add_argument("--workflow-ref", required=True)
    parser.add_argument("--workflow-sha", required=True)
    parser.add_argument("--run-id", required=True)
    parser.add_argument("--run-attempt", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()

    part_paths = [Path(name) for name in sorted(glob.glob(args.parts_glob))]
    if not part_paths:
        raise SystemExit("No se generaron partes del backup")

    parts = [
        {
            "name": path.as_posix(),
            "size_bytes": path.stat().st_size,
            "sha256": sha256_file(path),
        }
        for path in part_paths
    ]

    manifest = {
        "schema_version": 5,
        "backup_type": "full_logical_pg_dump_custom_age_encrypted_split_signed",
        "created_at_utc": args.created_at_utc,
        "timestamp_madrid": args.timestamp_madrid,
        "format": "pg_dump_custom",
        "encryption": {
            "algorithm": "age",
            "age_recipient_sha256": require_sha256(
                args.age_recipient_sha256, "age_recipient_sha256"
            ),
            "plaintext_sha256": require_sha256(
                args.plaintext_sha256, "plaintext_sha256"
            ),
            "encrypted_sha256": require_sha256(
                args.encrypted_sha256, "encrypted_sha256"
            ),
        },
        "parts_prefix": str(part_paths[0]).rsplit(".", 2)[0],
        "part_size": "90MiB",
        "part_count": len(parts),
        "parts": parts,
        "provenance": {
            "repository": args.repository,
            "workflow_ref": args.workflow_ref,
            "workflow_sha": args.workflow_sha,
            "run_id": args.run_id,
            "run_attempt": args.run_attempt,
        },
    }

    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(
        json.dumps(
            manifest,
            sort_keys=True,
            separators=(",", ":"),
            ensure_ascii=False,
        )
        + "\n",
        encoding="utf-8",
    )


if __name__ == "__main__":
    main()
