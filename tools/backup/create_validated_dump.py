#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

IDENTIFIER_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_$]*$")
TOC_TABLE_DATA_RE = re.compile(
    r"^(?P<dump_id>\d+);\s+\d+\s+\d+\s+TABLE DATA\s+"
    r"(?P<schema>\S+)\s+(?P<table>\S+)\s+.*$"
)
COPY_START_RE = re.compile(rb"^COPY\s+.+\s+FROM stdin;\r?\n$")
COPY_END_RE = re.compile(rb"^\\\.\r?\n$")


@dataclass(frozen=True)
class RequiredTable:
    schema: str
    table: str

    @property
    def qualified(self) -> str:
        return f"{self.schema}.{self.table}"


def fail(message: str) -> "NoReturn":
    raise SystemExit(f"ERROR: {message}")


def parse_required_table(value: str) -> RequiredTable:
    parts = value.split(".", 1)
    if len(parts) != 2 or not all(IDENTIFIER_RE.fullmatch(part) for part in parts):
        fail(f"tabla requerida inválida: {value!r}")
    return RequiredTable(parts[0], parts[1])


def parse_toc(text: str) -> dict[str, str]:
    entries: dict[str, str] = {}
    for raw_line in text.splitlines():
        match = TOC_TABLE_DATA_RE.match(raw_line)
        if not match:
            continue
        key = f"{match.group('schema')}.{match.group('table')}"
        if key in entries:
            fail(f"el TOC contiene TABLE DATA duplicado para {key}")
        entries[key] = raw_line
    return entries


def count_copy_rows(lines: Iterable[bytes]) -> int:
    in_copy = False
    copy_blocks = 0
    row_count = 0

    for line in lines:
        if not in_copy:
            if COPY_START_RE.match(line):
                in_copy = True
                copy_blocks += 1
            continue

        if COPY_END_RE.match(line):
            in_copy = False
            continue

        row_count += 1

    if in_copy:
        fail("salida de pg_restore truncada dentro de COPY")
    if copy_blocks != 1:
        fail(f"se esperaba un bloque COPY y se encontraron {copy_blocks}")
    return row_count


def command_version(program: str) -> str:
    result = subprocess.run(
        [program, "--version"],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    return result.stdout.strip()


def quote_identifier(identifier: str) -> str:
    return '"' + identifier.replace('"', '""') + '"'


def source_table_stats(cursor: object, table: RequiredTable) -> tuple[int, int]:
    qualified = f"{quote_identifier(table.schema)}.{quote_identifier(table.table)}"
    cursor.execute(
        f"SELECT count(*)::bigint, pg_total_relation_size(%s::regclass)::bigint "
        f"FROM {qualified}",
        (table.qualified,),
    )
    row = cursor.fetchone()
    if not row or len(row) != 2:
        fail(f"no se pudieron obtener estadísticas de {table.qualified}")
    return int(row[0]), int(row[1])


def archive_table_row_count(
    pg_restore: str,
    archive: Path,
    toc_line: str,
) -> int:
    with tempfile.TemporaryDirectory(prefix="pgdump-table-") as temp_dir:
        list_path = Path(temp_dir) / "restore.list"
        list_path.write_text(toc_line + "\n", encoding="utf-8")

        with tempfile.TemporaryFile() as stderr_file:
            process = subprocess.Popen(
                [
                    pg_restore,
                    "--data-only",
                    f"--use-list={list_path}",
                    "--file=-",
                    str(archive),
                ],
                stdout=subprocess.PIPE,
                stderr=stderr_file,
            )
            assert process.stdout is not None
            try:
                count = count_copy_rows(process.stdout)
            finally:
                process.stdout.close()
            return_code = process.wait()
            if return_code != 0:
                stderr_file.seek(0)
                error = stderr_file.read().decode("utf-8", errors="replace")
                fail(f"pg_restore falló al inspeccionar datos: {error.strip()}")
            return count


def self_test() -> int:
    toc = """;
; Archive created at 2026-08-04
123; 0 456 TABLE DATA public pois postgres
124; 0 457 TABLE DATA auth users supabase_auth_admin
"""
    parsed = parse_toc(toc)
    assert parsed["public.pois"].startswith("123;")
    assert parsed["auth.users"].startswith("124;")
    assert count_copy_rows(
        [
            b"-- prelude\n",
            b"COPY public.pois (id, name) FROM stdin;\n",
            b"1\tuno\n",
            b"2\tdos\\nlineas\n",
            b"\\.\n",
        ]
    ) == 2
    assert parse_required_table("public.pois").qualified == "public.pois"
    print("OK: self-test create_validated_dump.py")
    return 0


def main() -> int:
    if sys.argv[1:] == ["--self-test"]:
        return self_test()

    parser = argparse.ArgumentParser(
        description=(
            "Crea un pg_dump consistente y compara exactamente las filas de "
            "tablas críticas entre la instantánea PostgreSQL y el archivo."
        )
    )
    parser.add_argument("--db-url", required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--report", type=Path, required=True)
    parser.add_argument(
        "--required-table",
        action="append",
        default=[],
        help="Tabla schema.nombre; se puede repetir.",
    )
    args = parser.parse_args()

    required_tables = [parse_required_table(value) for value in args.required_table]
    if not required_tables:
        fail("debe indicarse al menos una --required-table")
    if len({table.qualified for table in required_tables}) != len(required_tables):
        fail("hay tablas requeridas duplicadas")
    if args.output.exists():
        fail(f"el archivo de salida ya existe: {args.output}")

    pg_dump = shutil.which("pg_dump")
    pg_restore = shutil.which("pg_restore")
    if not pg_dump or not pg_restore:
        fail("pg_dump y pg_restore deben estar en PATH")

    try:
        import psycopg2  # type: ignore
    except ImportError as exc:
        fail(f"falta psycopg2: {exc}")

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.report.parent.mkdir(parents=True, exist_ok=True)

    source_stats: dict[str, dict[str, int]] = {}
    archive_stats: dict[str, dict[str, int]] = {}

    try:
        with psycopg2.connect(args.db_url) as connection:
            connection.set_session(
                isolation_level="REPEATABLE READ",
                readonly=True,
                autocommit=False,
            )
            with connection.cursor() as cursor:
                cursor.execute(
                    "SELECT current_database(), current_user, "
                    "current_setting('server_version_num')::integer, "
                    "pg_export_snapshot()"
                )
                database_name, database_user, server_version_num, snapshot = cursor.fetchone()

                for table in required_tables:
                    rows, total_size_bytes = source_table_stats(cursor, table)
                    source_stats[table.qualified] = {
                        "rows": rows,
                        "total_size_bytes": total_size_bytes,
                    }

                dump_command = [
                    pg_dump,
                    args.db_url,
                    "--format=custom",
                    "--blobs",
                    "--no-owner",
                    "--no-privileges",
                    f"--snapshot={snapshot}",
                    "--file",
                    str(args.output),
                ]
                subprocess.run(dump_command, check=True)

                toc_result = subprocess.run(
                    [pg_restore, "--list", str(args.output)],
                    check=True,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    text=True,
                )
                toc_entries = parse_toc(toc_result.stdout)

                missing = [
                    table.qualified
                    for table in required_tables
                    if table.qualified not in toc_entries
                ]
                if missing:
                    fail("faltan entradas TABLE DATA: " + ", ".join(missing))

                for table in required_tables:
                    dump_rows = archive_table_row_count(
                        pg_restore,
                        args.output,
                        toc_entries[table.qualified],
                    )
                    source_rows = source_stats[table.qualified]["rows"]
                    archive_stats[table.qualified] = {"rows": dump_rows}
                    if dump_rows != source_rows:
                        fail(
                            f"recuento distinto para {table.qualified}: "
                            f"origen={source_rows}, dump={dump_rows}"
                        )

                report = {
                    "schema_version": 1,
                    "status": "validated",
                    "database": {
                        "name": str(database_name),
                        "user": str(database_user),
                        "server_version_num": int(server_version_num),
                        "snapshot": str(snapshot),
                    },
                    "tools": {
                        "pg_dump": command_version(pg_dump),
                        "pg_restore": command_version(pg_restore),
                    },
                    "archive": {
                        "path": args.output.name,
                        "size_bytes": args.output.stat().st_size,
                        "table_data_entries": len(toc_entries),
                    },
                    "required_tables": {
                        table.qualified: {
                            **source_stats[table.qualified],
                            "dump_rows": archive_stats[table.qualified]["rows"],
                            "match": True,
                        }
                        for table in required_tables
                    },
                }
                args.report.write_text(
                    json.dumps(report, sort_keys=True, indent=2) + "\n",
                    encoding="utf-8",
                )
                connection.rollback()
    except BaseException:
        args.output.unlink(missing_ok=True)
        args.report.unlink(missing_ok=True)
        raise

    print(args.report.read_text(encoding="utf-8"), end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
