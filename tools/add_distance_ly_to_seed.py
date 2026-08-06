#!/usr/bin/env python3
"""Add distance_ly column to catalog_seed.db and populate known star distances."""

from __future__ import annotations

import json
import sqlite3
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SEED_DB = ROOT / "assets" / "database" / "catalog_seed.db"
STARS = ROOT / "assets" / "catalog" / "stars.json"

sys.stdout.reconfigure(encoding="utf-8")

# Known bright-star distances (ly) used when stars.json has distanceLy.
STAR_DISTANCES = {
    "star_sirius": 8.6,
    "star_betelgeuse": 640,
    "star_rigel": 860,
    "star_vega": 25,
    "star_altair": 17,
    "star_deneb": 2600,
    "star_antares": 550,
    "star_arcturus": 37,
    "star_capella": 43,
    "star_aldebaran": 65,
    "star_polaris": 430,
    "star_procyon": 11.5,
    "star_spica": 250,
    "star_regulus": 79,
    "star_fomalhaut": 25,
    "star_castor": 51,
    "star_pollux": 34,
    "star_mizar": 83,
    "star_orion_belt": 1200,
}


def main() -> int:
    conn = sqlite3.connect(SEED_DB)
    cur = conn.cursor()
    cols = [r[1] for r in cur.execute("pragma table_info(celestial_objects)")]
    if "distance_ly" not in cols:
        cur.execute("alter table celestial_objects add column distance_ly real")
        print("added column distance_ly")
    else:
        print("column distance_ly already exists")

    stars = json.loads(STARS.read_text(encoding="utf-8"))
    updated_json = False
    for star in stars:
        sid = star["id"]
        distance = star.get("distanceLy")
        if distance is None and sid in STAR_DISTANCES:
            distance = STAR_DISTANCES[sid]
            star["distanceLy"] = distance
            updated_json = True
        if distance is None:
            continue
        cur.execute(
            "update celestial_objects set distance_ly=? where id=?",
            (float(distance), sid),
        )

    if updated_json:
        STARS.write_text(
            json.dumps(stars, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )
        print("updated stars.json with distanceLy")

    n = cur.execute(
        "select count(*) from celestial_objects where distance_ly is not null and distance_ly > 0"
    ).fetchone()[0]
    conn.commit()
    conn.close()
    print(f"objects_with_distance: {n}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
