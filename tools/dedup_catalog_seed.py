#!/usr/bin/env python3
"""Deduplicate catalog_seed.db: remove junk catalogs and cross-catalog duplicates."""

from __future__ import annotations

import json
import re
import sqlite3
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SEED_DB = ROOT / "assets" / "database" / "catalog_seed.db"

SUPPORTED_CATALOGS = {
    "messier",
    "ngc",
    "ic",
    "caldwell",
    "sh2",
    "rcw",
    "vdb",
    "barnard",
    "ldn",
    "lbn",
    "solar",
    "milky",
}

CATALOG_PRIORITY = {
    "messier": 0,
    "ngc": 1,
    "ic": 2,
    "caldwell": 3,
    "sh2": 4,
    "rcw": 5,
    "vdb": 6,
    "barnard": 7,
    "ldn": 8,
    "lbn": 9,
    "solar": 99,
    "milky": 99,
}

NGC_REF = re.compile(r"NGC\s*(\d+)", re.I)
IC_REF = re.compile(r"IC\s*(\d+)", re.I)
MESSIER_REF = re.compile(r"\bM(\d+)\b", re.I)


def canonical_id(catalog: str, num: int, suffix: str | None) -> str:
    suffix = suffix or ""
    if catalog == "messier":
        return f"M{num}"
    if catalog == "ngc":
        return f"NGC{num}"
    if catalog == "ic":
        return f"IC{num}{suffix}"
    if catalog == "caldwell":
        return f"C{num}"
    if catalog == "sh2":
        return f"Sh2-{num}"
    if catalog == "rcw":
        return f"RCW{num}"
    if catalog == "vdb":
        return f"vdB{num}"
    if catalog == "barnard":
        return f"B{num}"
    if catalog == "ldn":
        return f"LDN{num}"
    if catalog == "lbn":
        return f"LBN{num}"
    if catalog == "solar":
        return f"solar_{num}"
    if catalog == "milky":
        return "mw"
    return ""


def parse_json_list(raw: str | None) -> list[str]:
    if not raw:
        return []
    try:
        data = json.loads(raw)
        if isinstance(data, list):
            return [str(x) for x in data]
    except json.JSONDecodeError:
        pass
    return []


def merge_lists(a: list[str], b: list[str]) -> list[str]:
    seen: set[str] = set()
    out: list[str] = []
    for item in [*a, *b]:
        key = item.strip()
        if not key or key in seen:
            continue
        seen.add(key)
        out.append(key)
    return out


def merge_row(canonical: dict, other: dict) -> None:
    for field in (
        "aliases_json",
        "cross_catalog_refs_json",
        "search_keywords",
        "description",
        "angular_size",
        "major_axis",
        "minor_axis",
        "position_angle",
    ):
        if other.get(field) and not canonical.get(field):
            canonical[field] = other[field]

    aliases = merge_lists(
        parse_json_list(canonical.get("aliases_json")),
        parse_json_list(other.get("aliases_json")),
    )
    cross = merge_lists(
        parse_json_list(canonical.get("cross_catalog_refs_json")),
        parse_json_list(other.get("cross_catalog_refs_json")),
    )
    cross.append(other["id"])
    cross = merge_lists(cross, [other["id"]])

    if aliases:
        canonical["aliases_json"] = json.dumps(aliases, ensure_ascii=False)
    if cross:
        canonical["cross_catalog_refs_json"] = json.dumps(cross, ensure_ascii=False)

    if (not canonical.get("common_name") or canonical["common_name"] == "-") and other.get(
        "common_name"
    ):
        canonical["common_name"] = other["common_name"]


def load_rows(conn: sqlite3.Connection) -> dict[str, dict]:
    conn.row_factory = sqlite3.Row
    rows = conn.execute("SELECT * FROM celestial_objects").fetchall()
    return {row["id"]: dict(row) for row in rows}


def main() -> int:
    if not SEED_DB.is_file():
        print(f"Missing seed DB: {SEED_DB}")
        return 1

    conn = sqlite3.connect(SEED_DB)
    rows = load_rows(conn)
    initial = len(rows)
    removed: list[str] = []

    # 1) Remove unsupported catalogs (barnard, lbn, ldn, nn, sh2-, ...)
    for oid in list(rows):
        if rows[oid]["catalog"] not in SUPPORTED_CATALOGS:
            removed.append(oid)
            del rows[oid]

    # 2) Same catalog+num(+suffix): keep canonical id / higher priority row
    groups: dict[tuple, list[str]] = defaultdict(list)
    for oid, row in rows.items():
        key = (row["catalog"], row["num"], row.get("suffix") or "")
        groups[key].append(oid)

    for key, ids in groups.items():
        if len(ids) <= 1:
            continue
        catalog, num, suffix = key
        expected = canonical_id(catalog, num, suffix or None)
        ids.sort(
            key=lambda i: (
                0 if i == expected else 1,
                CATALOG_PRIORITY.get(rows[i]["catalog"], 50),
                0 if rows[i].get("data_source") != "Seestar" else 1,
                i,
            )
        )
        keep = ids[0]
        for drop in ids[1:]:
            merge_row(rows[keep], rows[drop])
            removed.append(drop)
            del rows[drop]

    # 3) Cross-catalog duplicates referenced by higher-priority objects
    by_id = rows
    index_by_catalog_num: dict[tuple, str] = {}
    for oid, row in rows.items():
        index_by_catalog_num[(row["catalog"], row["num"], row.get("suffix") or "")] = oid

    def find_ngc(num: int) -> str | None:
        return index_by_catalog_num.get(("ngc", num, ""))

    def find_ic(num: int, suffix: str = "") -> str | None:
        return index_by_catalog_num.get(("ic", num, suffix))

    def find_messier(num: int) -> str | None:
        return index_by_catalog_num.get(("messier", num, ""))

    for oid in sorted(list(rows.keys())):
        if oid not in rows:
            continue
        row = rows[oid]
        pri = CATALOG_PRIORITY.get(row["catalog"], 50)
        refs = [
            *parse_json_list(row.get("aliases_json")),
            *parse_json_list(row.get("cross_catalog_refs_json")),
        ]
        if row.get("search_keywords"):
            refs.extend(row["search_keywords"].split("|"))

        drop_ids: set[str] = set()
        for ref in refs:
            m = NGC_REF.search(ref)
            if m and pri < CATALOG_PRIORITY["ngc"]:
                target = find_ngc(int(m.group(1)))
                if target and target != oid and target in rows:
                    drop_ids.add(target)
            m = IC_REF.search(ref)
            if m and pri < CATALOG_PRIORITY["ic"]:
                suffix = ref[m.end() :].strip().upper()
                suffix_clean = suffix[:1] if suffix[:1] in {"A", "B"} else ""
                target = find_ic(int(m.group(1)), suffix_clean)
                if target and target != oid and target in rows:
                    drop_ids.add(target)
            m = MESSIER_REF.search(ref)
            if m and pri < CATALOG_PRIORITY["messier"]:
                target = find_messier(int(m.group(1)))
                if target and target != oid and target in rows:
                    drop_ids.add(target)

        for drop in drop_ids:
            if drop not in rows:
                continue
            drop_row = rows[drop]
            merge_row(rows[oid], drop_row)
            removed.append(drop)
            index_by_catalog_num.pop(
                (drop_row["catalog"], drop_row["num"], drop_row.get("suffix") or ""),
                None,
            )
            del rows[drop]

    # Rewrite DB
    conn.execute("DELETE FROM celestial_objects")
    for row in rows.values():
        columns = ", ".join(row.keys())
        placeholders = ", ".join("?" for _ in row)
        conn.execute(
            f"INSERT INTO celestial_objects ({columns}) VALUES ({placeholders})",
            list(row.values()),
        )
    conn.commit()
    conn.close()

    print(f"Initial rows: {initial}")
    print(f"Removed rows: {len(removed)}")
    print(f"Final rows: {len(rows)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
