#!/usr/bin/env python3
"""Insert assets/catalog/stars.json into catalog_seed.db."""

from __future__ import annotations

import json
import sqlite3
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SEED_DB = ROOT / "assets" / "database" / "catalog_seed.db"
STARS = ROOT / "assets" / "catalog" / "stars.json"

sys.stdout.reconfigure(encoding="utf-8")


def main() -> int:
    stars = json.loads(STARS.read_text(encoding="utf-8"))
    conn = sqlite3.connect(SEED_DB)
    cur = conn.cursor()
    cols = [r[1] for r in cur.execute("pragma table_info(celestial_objects)")]

    inserted = 0
    for star in stars:
        row = {
            "id": star["id"],
            "num": star["number"],
            "catalog": "star",
            "name": star["name"],
            "type": star.get("objectType") or star.get("type") or "항성",
            "constellation": star.get("constellation") or "",
            "ra": star.get("ra") or "-",
            "dec": star.get("dec") or "-",
            "mag": star.get("magnitude") or "-",
            "captured": 0,
            "captured_date": None,
            "photo_uri": None,
            "memo": "",
            "exif_json": None,
            "aliases_json": json.dumps(star.get("aliases") or [], ensure_ascii=False),
            "cross_catalog_refs_json": None,
            "common_name": star.get("commonName") or star["name"],
            "object_type": star.get("objectType") or "항성",
            "seestar_supported": 0,
            "suffix": None,
            "tags_json": None,
            "peak_month": star.get("peakMonth"),
            "best_season": star.get("bestSeason"),
            "angular_size": star.get("angularSize"),
            "distance_ly": star.get("distanceLy"),
            "description": star.get("description"),
            "search_keywords": None,
            "major_axis": None,
            "minor_axis": None,
            "position_angle": None,
            "data_source": "Manual",
            "is_featured": 1,
            "display_priority": star["number"],
            "is_primary_catalog": 1,
            "primary_catalog_id": None,
        }
        filtered = {k: v for k, v in row.items() if k in cols}
        placeholders = ", ".join("?" for _ in filtered)
        col_names = ", ".join(filtered.keys())
        cur.execute(
            f"insert or replace into celestial_objects ({col_names}) values ({placeholders})",
            list(filtered.values()),
        )
        inserted += 1

    conn.commit()
    n = cur.execute(
        "select count(*) from celestial_objects where catalog='star'"
    ).fetchone()[0]
    conn.close()
    print(f"inserted/replaced: {inserted}, star catalog count: {n}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
