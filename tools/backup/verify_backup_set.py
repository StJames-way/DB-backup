#!/usr/bin/env python3
from __future__ import annotations

import argparse
import base64
import hashlib
import json
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from cryptography.exceptions import InvalidSignature
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey

SIGNATURE_RE = re.compile(
    r"^(?:vault|bao):v(?P<version>[1-9][0-9]*):(?P<body>[A-Za-z0-9+/=_-]+)$"
)
MAX_PART_SIZE = 90 * 1024 * 1024


@dataclass(frozen=True)
class ValidatedBackup:
    manifest: Path
    signature: Path
    sha_file: Path
    parts: tuple[Path, ...]
    encrypted_sha256: str


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def load_public_key(path: Path) -> tuple[Ed25519PublicKey, str]:
    loaded = serialization.load_pem_public_key(path.read_bytes())
    if not isinstance(loaded, Ed25519PublicKey):
        raise ValueError("La clave pública fijada no es Ed25519")
    der = loaded.public_bytes(
        serialization.Encoding.DER,
        serialization.PublicFormat.SubjectPublicKeyInfo,
    )
    return loaded, hashlib.sha256(der).hexdigest()


def confined(repo: Path, relative_name: str, root: Path) -> Path:
    relative = Path(relative_name)
    if relative.is_absolute() or ".." in relative.parts:
        raise ValueError(f"Ruta insegura: {relative_name}")
    absolute = (repo / relative).resolve()
    if absolute != root and root not in absolute.parents:
        raise ValueError(f"Ruta fuera del directorio permitido: {relative_name}")
    if absolute.is_symlink():
        raise ValueError(f"No se permiten enlaces simbólicos: {relative_name}")
    return absolute


def verify_signature(
    manifest_path: Path,
    document: dict[str, Any],
    signature_path: Path,
    public_key: Ed25519PublicKey,
    public_key_sha256: str,
) -> None:
    raw = manifest_path.read_bytes()
    manifest_sha256 = hashlib.sha256(raw).hexdigest()
    bundle = json.loads(signature_path.read_text(encoding="utf-8"))

    expected = {
        "schema_version": 1,
        "provider": "openbao-transit",
        "algorithm": "ed25519",
        "mount": "transit-backup",
        "key_name": "supabase-backup-manifest",
    }
    for field, value in expected.items():
        if bundle.get(field) != value:
            raise ValueError(f"Campo de firma inesperado: {field}")

    if bundle.get("manifest_sha256") != manifest_sha256:
        raise ValueError("La firma no corresponde al SHA-256 del manifest")
    if bundle.get("public_key_sha256") != public_key_sha256:
        raise ValueError("La firma no corresponde a la clave pública fijada")

    signing = document.get("signing")
    provenance = document.get("provenance")
    if not isinstance(signing, dict) or not isinstance(provenance, dict):
        raise ValueError("Faltan signing/provenance en el manifest")

    for field in ("provider", "algorithm", "mount", "key_name", "public_key_sha256"):
        if signing.get(field) != bundle.get(field):
            raise ValueError(f"Manifest y firma no coinciden en {field}")

    oidc = bundle.get("oidc")
    if not isinstance(oidc, dict):
        raise ValueError("Falta evidencia OIDC en la firma")

    direct_fields = (
        "repository",
        "repository_id",
        "repository_owner_id",
        "workflow_ref",
        "workflow_sha",
        "job_workflow_ref",
        "job_workflow_sha",
        "ref",
        "run_id",
        "run_attempt",
        "event_name",
        "runner_environment",
    )
    for field in direct_fields:
        if str(oidc.get(field, "")) != str(provenance.get(field, "")):
            raise ValueError(f"OIDC/provenance no coincide: {field}")
    if str(oidc.get("sha", "")) != str(provenance.get("source_commit", "")):
        raise ValueError("OIDC/provenance no coincide: source_commit")

    signature_text = bundle.get("signature")
    if not isinstance(signature_text, str):
        raise ValueError("Falta la firma")
    match = SIGNATURE_RE.match(signature_text)
    if not match:
        raise ValueError("Formato de firma OpenBao no reconocido")
    if int(match.group("version")) != int(bundle.get("key_version", 0)):
        raise ValueError("La versión de clave de la firma no coincide")

    try:
        signature = base64.b64decode(match.group("body"), validate=True)
        public_key.verify(signature, raw)
    except (ValueError, InvalidSignature) as exc:
        raise ValueError("Firma Ed25519 inválida") from exc


def validate_manifest(
    repo: Path,
    manifest_path: Path,
    public_key: Ed25519PublicKey,
    public_key_sha256: str,
) -> ValidatedBackup:
    manifests_root = (repo / "manifests").resolve()
    signatures_root = (repo / "signatures").resolve()
    encrypted_root = (repo / "encrypted_backups").resolve()

    if not manifest_path.is_file() or manifest_path.is_symlink():
        raise ValueError(f"Manifest inválido: {manifest_path}")

    document = json.loads(manifest_path.read_text(encoding="utf-8"))
    if document.get("schema_version") != 4:
        raise ValueError(f"Schema no admitido: {manifest_path.name}")

    signature_name = document.get("signing", {}).get("signature_file")
    if not isinstance(signature_name, str):
        raise ValueError("Falta signature_file")
    signature_path = confined(repo, signature_name, signatures_root)
    if not signature_path.is_file():
        raise ValueError(f"Falta la firma: {signature_name}")
    verify_signature(
        manifest_path,
        document,
        signature_path,
        public_key,
        public_key_sha256,
    )

    parts = document.get("parts")
    if not isinstance(parts, list) or not parts:
        raise ValueError("El manifest no contiene partes")
    if document.get("part_count") != len(parts):
        raise ValueError("part_count no coincide")

    seen: set[str] = set()
    part_paths: list[Path] = []
    overall = hashlib.sha256()
    for entry in parts:
        if not isinstance(entry, dict):
            raise ValueError("Entrada de parte inválida")
        name = entry.get("name")
        expected_size = entry.get("size_bytes")
        expected_hash = entry.get("sha256")
        if not isinstance(name, str) or name in seen:
            raise ValueError(f"Parte inválida o duplicada: {name}")
        if not isinstance(expected_size, int) or not isinstance(expected_hash, str):
            raise ValueError(f"Metadatos inválidos para {name}")
        seen.add(name)
        path = confined(repo, name, encrypted_root)
        if not path.is_file():
            raise ValueError(f"Falta la parte: {name}")
        size = path.stat().st_size
        if size <= 0 or size > MAX_PART_SIZE or size != expected_size:
            raise ValueError(f"Tamaño inválido: {name}")
        actual_hash = sha256_file(path)
        if actual_hash != expected_hash:
            raise ValueError(f"SHA-256 incorrecto: {name}")
        with path.open("rb") as handle:
            for chunk in iter(lambda: handle.read(1024 * 1024), b""):
                overall.update(chunk)
        part_paths.append(path)

    overall_hash = overall.hexdigest()
    if overall_hash != document.get("encrypted_sha256"):
        raise ValueError("SHA-256 global cifrado incorrecto")

    sha_name = document.get("sha256_file")
    if not isinstance(sha_name, str):
        raise ValueError("Falta sha256_file")
    sha_path = confined(repo, sha_name, encrypted_root)
    if not sha_path.is_file():
        raise ValueError(f"Falta el fichero SHA-256: {sha_name}")
    words = sha_path.read_text(encoding="utf-8").split()
    if not words or words[0] != overall_hash:
        raise ValueError("El fichero SHA-256 separado no coincide")

    return ValidatedBackup(
        manifest=manifest_path.resolve(),
        signature=signature_path,
        sha_file=sha_path,
        parts=tuple(part_paths),
        encrypted_sha256=overall_hash,
    )


def reassemble(item: ValidatedBackup, output: Path) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = output.with_suffix(output.suffix + ".tmp")
    digest = hashlib.sha256()
    try:
        with temporary.open("wb") as target:
            for part in item.parts:
                with part.open("rb") as source:
                    for chunk in iter(lambda: source.read(1024 * 1024), b""):
                        target.write(chunk)
                        digest.update(chunk)
        if digest.hexdigest() != item.encrypted_sha256:
            raise ValueError("El SHA-256 del fichero reensamblado no coincide")
        temporary.replace(output)
    finally:
        temporary.unlink(missing_ok=True)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-root", type=Path, default=Path.cwd())
    parser.add_argument("--public-key", type=Path, required=True)
    parser.add_argument("--expected-public-key-sha256", required=True)
    parser.add_argument("--manifest", type=Path)
    parser.add_argument("--new-manifest", type=Path)
    parser.add_argument("--retain", type=int, default=0)
    parser.add_argument("--delete-old", action="store_true")
    parser.add_argument("--reassemble-to", type=Path)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    repo = args.repo_root.resolve()
    public_key, fingerprint = load_public_key(args.public_key.resolve())
    if fingerprint != args.expected_public_key_sha256.lower():
        raise SystemExit(
            f"Huella de clave pública incorrecta: {fingerprint} != "
            f"{args.expected_public_key_sha256.lower()}"
        )

    if args.manifest:
        manifest_path = args.manifest
        if not manifest_path.is_absolute():
            manifest_path = repo / manifest_path
        manifest_paths = [manifest_path.resolve()]
    else:
        manifest_paths = sorted((repo / "manifests").glob("database_backup_*.json"))

    if not manifest_paths:
        raise SystemExit("No se encontraron manifests")

    validated: list[ValidatedBackup] = []
    errors: list[str] = []
    for manifest in manifest_paths:
        try:
            validated.append(validate_manifest(repo, manifest, public_key, fingerprint))
        except Exception as exc:  # noqa: BLE001 - aggregate all verification failures
            errors.append(f"{manifest.name}: {exc}")

    if errors:
        print("Backups inválidos o incompletos:", file=sys.stderr)
        for error in errors:
            print(f" - {error}", file=sys.stderr)
        return 1

    if args.new_manifest:
        expected_new = args.new_manifest
        if not expected_new.is_absolute():
            expected_new = repo / expected_new
        if expected_new.resolve() not in {item.manifest for item in validated}:
            raise SystemExit("El backup nuevo no está entre los backups verificados")

    if args.reassemble_to:
        if len(validated) != 1:
            raise SystemExit("--reassemble-to requiere exactamente un --manifest")
        reassemble(validated[0], args.reassemble_to.resolve())
        print(f"Backup reensamblado y verificado: {args.reassemble_to.resolve()}")

    print(f"Backups completamente firmados y verificados: {len(validated)}")

    if args.retain:
        if args.retain < 1:
            raise SystemExit("--retain debe ser al menos 1")
        if len(validated) > args.retain:
            delete = validated[:-args.retain]
            if not args.delete_old:
                print(f"Se eliminarían {len(delete)} backups; falta --delete-old")
            else:
                for item in delete:
                    print(f"Eliminando backup antiguo verificado: {item.manifest.name}")
                    for path in item.parts:
                        path.unlink()
                    item.sha_file.unlink()
                    item.signature.unlink()
                    item.manifest.unlink()
                remaining = list((repo / "manifests").glob("database_backup_*.json"))
                if len(remaining) != args.retain:
                    raise SystemExit(
                        f"Resultado de retención inesperado: quedan {len(remaining)} manifests"
                    )
        else:
            print(f"Retención: {len(validated)} <= {args.retain}; no se borra nada")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
