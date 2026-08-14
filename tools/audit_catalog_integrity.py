#!/usr/bin/env python3
"""Audit generated AstroJournal catalog identity and metadata integrity."""

from __future__ import annotations

import argparse
import json
import re
import sqlite3
from collections import defaultdict
from pathlib import Path

from catalog_identity import CALDWELL_PRIMARY, type_family

ROOT = Path(__file__).resolve().parents[1]
CATALOG_DIR = ROOT / "assets" / "catalog"
SEED_DB = ROOT / "assets" / "database" / "catalog_seed.db"
REPORT_PATH = ROOT / "build" / "catalog_audit_report.json"
TYPED_TOKEN = re.compile(r"\b(?:M|NGC|IC|C)\s*\d+[AB]?\b", re.I)


def normalize_id(value: str) -> str:
    return re.sub(r"\s+", "", value).upper()


def parse_json_list(raw: str | None) -> list[str]:
    if not raw:
        return []
    try:
        value = json.loads(raw)
        return [str(item) for item in value] if isinstance(value, list) else []
    except json.JSONDecodeError:
        return []


def resolve(object_id: str, remap: dict[str, str]) -> str:
    current = object_id
    visited: set[str] = set()
    while current in remap:
        if current in visited:
            raise ValueError(f"id remap cycle at {current}")
        visited.add(current)
        current = remap[current]
    return current


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--report-path", type=Path, default=REPORT_PATH)
    args = parser.parse_args()

    hard: list[str] = []
    warnings: list[str] = []
    equivalence = json.loads(
        (CATALOG_DIR / "catalog_equivalence.json").read_text(encoding="utf-8-sig")
    )
    remap = {str(k): str(v) for k, v in equivalence.get("idRemap", {}).items()}

    expected_caldwell = {f"C{number}" for number in range(1, 110)}
    mapped_caldwell = {f"C{number}" for number in CALDWELL_PRIMARY}
    if mapped_caldwell != expected_caldwell:
        hard.append("Caldwell mapping does not contain exactly C1-C109")
    for number, target in CALDWELL_PRIMARY.items():
        c_id = f"C{number}"
        actual = resolve(c_id, remap)
        expected = resolve(target, remap)
        if actual != expected:
            hard.append(f"{c_id} resolves to {actual}, expected {expected}")

    conn = sqlite3.connect(SEED_DB)
    conn.row_factory = sqlite3.Row
    rows = {row["id"]: dict(row) for row in conn.execute("SELECT * FROM celestial_objects")}
    conn.close()

    if len(rows) != len(set(rows)):
        hard.append("duplicate typed object identifiers in seed")

    groups = equivalence.get("groups", [])
    owner_by_member: dict[str, str] = {}
    for group in groups:
        canonical = str(group["canonicalId"])
        for member in group.get("members", []):
            member = str(member)
            prior = owner_by_member.get(member)
            if prior and prior != canonical:
                hard.append(f"identifier {member} belongs to {prior} and {canonical}")
            owner_by_member[member] = canonical

        present = [rows[member] for member in group.get("members", []) if member in rows]
        families = {
            family
            for row in present
            if (family := type_family(row.get("object_type") or row.get("type")))
        }
        constellations = {
            row["constellation"]
            for row in present
            if row.get("constellation") not in (None, "", "-")
        }
        coordinates = {
            (row.get("ra"), row.get("dec"))
            for row in present
            if row.get("ra") not in (None, "", "-")
            and row.get("dec") not in (None, "", "-")
        }
        if len(families) > 1:
            hard.append(f"{canonical} has incompatible object types: {sorted(families)}")
        if len(constellations) > 1:
            hard.append(
                f"{canonical} has incompatible constellations: {sorted(constellations)}"
            )
        if len(coordinates) > 1:
            hard.append(f"{canonical} has inconsistent RA/Dec among identity members")

    alias_owners: dict[str, set[str]] = defaultdict(set)
    missing = defaultdict(int)
    for object_id, row in rows.items():
        for field in ("ra", "dec", "mag", "angular_size"):
            if row.get(field) in (None, "", "-"):
                missing[field] += 1
        tokens = []
        for column in ("aliases_json", "cross_catalog_refs_json"):
            for value in parse_json_list(row.get(column)):
                alias_owners[value.casefold()].add(resolve(object_id, remap))
                tokens.extend(TYPED_TOKEN.findall(value))
        canonical = resolve(object_id, remap)
        for token in tokens:
            normalized = normalize_id(token)
            if normalized in remap and resolve(normalized, remap) != canonical:
                hard.append(
                    f"{object_id} contains contradictory identity token {normalized}"
                )

    for alias, owners in alias_owners.items():
        if len(owners) > 1:
            warnings.append(f"alias '{alias}' appears under {len(owners)} canonicals")

    def assert_group(ids: list[str], expected: str) -> None:
        actual = {resolve(object_id, remap) for object_id in ids}
        if actual != {expected}:
            hard.append(f"{ids} resolve to {sorted(actual)}, expected {expected}")

    assert_group(["NGC6822", "IC4895", "C57"], "NGC6822")
    assert_group(["NGC7293", "C63"], "NGC7293")
    if resolve("NGC6822", remap) == resolve("NGC7293", remap):
        hard.append("Barnard and Helix groups are merged")

    warnings.extend(f"missing {field}: {count}" for field, count in sorted(missing.items()))
    report = {
        "objects": len(rows),
        "hardErrorCount": len(hard),
        "warningCount": len(warnings),
        "hardErrors": hard,
        "warnings": warnings,
        "missingMetadata": dict(missing),
    }
    args.report_path.parent.mkdir(parents=True, exist_ok=True)
    args.report_path.write_text(
        json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 1 if hard else 0


if __name__ == "__main__":
    raise SystemExit(main())
