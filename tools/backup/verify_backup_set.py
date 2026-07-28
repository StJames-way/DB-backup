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

SIGNATURE_RE = re.compile(r"^[^:]+:v(?P<version>[0-9]+):(?P<body>[A-Za-z0-9+/=]+)$")


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
        raise ValueError("La clave pública no es Ed25519")
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

    if bundle.get("schema_version") != 1:
        raise ValueError("Schema de firma no admitido")
    if bundle.get("provider") != "openbao-transit":
        raise ValueError("Proveedor de firma no admitido")
    if bundle.get("algorithm") != "ed25519":
        raise ValueError("Algoritmo de firma no admitido")
    if bundle.get("manifest_sha256") != manifest_sha256:
        raise ValueError("La firma no corresponde al SHA-256 del manifest")
    if bundle.get("public_key_sha256") != public_key_sha256:
        raise ValueError("La firma no corresponde a la clave pública fijada")

    signing = document.get("signing")
    provenance = document.get("provenance")
    if not isinstance(signing, dict) or not isinstance(provenance, dict):
        raise ValueError("Faltan signing/provenance en el manifest")

    for field in (
        "provider",
        "algorithm",
        "mount",
        "key_name",
        "public_key_sha256",
    ):
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
    if document.get("backup_type") != "full_logical_pg_dump_custom_age_encrypted_split_signed":
        raise ValueError("Tipo de backup no admitido")

    part_size_bytes = document.get("part_size_bytes")
    if not isinstance(part_size_bytes, int) or part_size_bytes <= 0:
        raise ValueError("part_size_bytes inválido")

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
    previous_name = ""

    for index, entry in enumerate(parts):
        if not isinstance(entry, dict):
            raise ValueError("Entrada de parte inválida")
        name = entry.get("name")
        expected_size = entry.get("size_bytes")
        expected_hash = entry.get("sha256")
        if not isinstance(name, str) or name in seen:
            raise ValueError(f"Parte inválida o duplicada: {name}")
        if previous_name and name <= previous_name:
            raise ValueError("Las partes no están ordenadas")
        if not isinstance(expected_size, int) or not isinstance(expected_hash, str):
            raise ValueError(f"Metadatos inválidos para {name}")
        if not re.fullmatch(r"[0-9a-f]{64}", expected_hash):
            raise ValueError(f"SHA-256 inválido para {name}")
        seen.add(name)
        previous_name = name

        path = confined(repo, name, encrypted_root)
        if not path.is_file():
            raise ValueError(f"Falta la parte: {name}")
        size = path.stat().st_size
        if size <= 0 or size > part_size_bytes or size != expected_size:
            raise ValueError(f"Tamaño inválido: {name}")
        if index < len(parts) - 1 and size != part_size_bytes:
            raise ValueError(f"Parte intermedia truncada: {name}")

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
    if len(words) < 2 or words[0] != overall_hash:
        raise ValueError("El fichero SHA-256 separado no coincide")
    if words[1] != Path(document.get("encrypted_original_filename", "")).name:
        raise ValueError("El nombre registrado en el fichero SHA-256 no coincide")

    plaintext_hash = document.get("plaintext_dump_sha256")
    if not isinstance(plaintext_hash, str) or not re.fullmatch(r"[0-9a-f]{64}", plaintext_hash):
        raise ValueError("plaintext_dump_sha256 inválido")

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
    expected_key_sha = args.expected_public_key_sha256.lower()
    if not re.fullmatch(r"[0-9a-f]{64}", expected_key_sha):
        raise ValueError("Huella pública esperada inválida")

    public_key, actual_key_sha = load_public_key(args.public_key.resolve())
    if actual_key_sha != expected_key_sha:
        raise ValueError(
            f"Huella pública incorrecta: esperada {expected_key_sha}, obtenida {actual_key_sha}"
        )

    manifests_root = (repo / "manifests").resolve()
    manifests_root.mkdir(parents=True, exist_ok=True)

    selected = args.manifest or args.new_manifest
    if selected:
        selected_path = selected if selected.is_absolute() else repo / selected
        item = validate_manifest(repo, selected_path.resolve(), public_key, actual_key_sha)
        if args.reassemble_to:
            reassemble(item, args.reassemble_to.resolve())
        print(f"Backup verificado: {item.manifest.name}")
        return 0

    manifest_paths = sorted(manifests_root.glob("database_backup_*.json"))
    if not manifest_paths:
        raise ValueError("No existen manifests")

    validated: list[ValidatedBackup] = []
    errors: list[str] = []
    for path in manifest_paths:
        try:
            validated.append(validate_manifest(repo, path, public_key, actual_key_sha))
        except Exception as exc:  # noqa: BLE001
            errors.append(f"{path.name}: {exc}")

    if errors:
        raise ValueError("Backups inconsistentes:\n - " + "\n - ".join(errors))

    if args.retain < 0:
        raise ValueError("retain no puede ser negativo")
    if args.delete_old and args.retain <= 0:
        raise ValueError("--delete-old exige --retain mayor que cero")

    if args.delete_old and len(validated) > args.retain:
        for item in validated[:-args.retain]:
            for part in item.parts:
                part.unlink()
            item.sha_file.unlink()
            item.signature.unlink()
            item.manifest.unlink()

    print(f"Backups verificados: {len(validated)}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:  # noqa: BLE001
        print(f"ERROR: {exc}", file=sys.stderr)
        raise SystemExit(1)
