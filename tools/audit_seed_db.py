#!/usr/bin/env python3
"""Audit catalog_seed.db for unknown catalogs and missing metadata."""
import sqlite3
import sys
from collections import defaultdict
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8")

ROOT = Path(__file__).resolve().parents[1]
DB = ROOT / "assets" / "database" / "catalog_seed.db"
SUPPORTED = {
    "messier", "ngc", "ic", "caldwell", "sh2", "rcw", "vdb",
    "barnard", "ldn", "lbn", "solar", "milky",
}


def missing(v):
    return v is None or str(v).strip() in {"", "-"}


def main():
    conn = sqlite3.connect(DB)
    conn.row_factory = sqlite3.Row
    total = conn.execute("SELECT COUNT(*) FROM celestial_objects").fetchone()[0]
    print(f"total objects: {total}")

    print("\n== catalog distribution ==")
    for row in conn.execute(
        "SELECT catalog, COUNT(*) AS c FROM celestial_objects "
        "GROUP BY catalog ORDER BY c DESC"
    ):
        flag = "" if row["catalog"] in SUPPORTED else " [UNSUPPORTED]"
        print(f"  {row['catalog']}: {row['c']}{flag}")

    unknown = conn.execute(
        "SELECT catalog, COUNT(*) AS c FROM celestial_objects "
        "WHERE catalog NOT IN ({}) GROUP BY catalog".format(
            ",".join("?" * len(SUPPORTED))
        ),
        list(SUPPORTED),
    ).fetchall()
    print("\n== unsupported catalogs ==")
    if not unknown:
        print("  none")
    else:
        for row in unknown:
            print(f"  {row['catalog']}: {row['c']}")
            samples = conn.execute(
                "SELECT id, name, common_name FROM celestial_objects "
                "WHERE catalog=? LIMIT 10",
                (row["catalog"],),
            ).fetchall()
            for s in samples:
                print(f"    {s['id']} | {s['name']} | {s['common_name']}")

    fields = [
        "mag", "angular_size", "constellation", "description",
        "common_name", "object_type", "ra", "dec",
    ]
    print("\n== missing fields (all objects) ==")
    for field in fields:
        n = conn.execute(
            f"SELECT COUNT(*) FROM celestial_objects "
            f"WHERE {field} IS NULL OR TRIM({field}) IN ('', '-')"
        ).fetchone()[0]
        print(f"  {field}: {n}")

    print("\n== missing fields by catalog ==")
    for cat_row in conn.execute(
        "SELECT catalog, COUNT(*) AS c FROM celestial_objects GROUP BY catalog"
    ):
        cat = cat_row["catalog"]
        gaps = []
        for field in ("mag", "angular_size", "constellation"):
            n = conn.execute(
                f"SELECT COUNT(*) FROM celestial_objects "
                f"WHERE catalog=? AND ({field} IS NULL OR TRIM({field}) IN ('', '-'))",
                (cat,),
            ).fetchone()[0]
            if n:
                gaps.append(f"{field}={n}")
        if gaps:
            print(f"  {cat}: {', '.join(gaps)}")

    print("\n== sample unsupported rows ==")
    rows = conn.execute(
        "SELECT id, catalog, num, name, common_name, mag, angular_size "
        "FROM celestial_objects WHERE catalog NOT IN ({}) LIMIT 30".format(
            ",".join("?" * len(SUPPORTED))
        ),
        list(SUPPORTED),
    ).fetchall()
    for r in rows:
        print(
            f"  {r['id']} catalog={r['catalog']} mag={r['mag']} "
            f"size={r['angular_size']} name={r['name']}"
        )

    conn.close()


if __name__ == "__main__":
    main()
