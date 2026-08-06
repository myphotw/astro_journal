#!/usr/bin/env python3
import json
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

def missing(v):
    return v is None or str(v).strip() in {"", "-"}

for fname in ["messier.json", "seestar_catalog.json", "solar.json", "milkyway.json"]:
    objs = json.load(open(ROOT / "assets/catalog" / fname, encoding="utf-8-sig"))
    by_field = defaultdict(list)
    for o in objs:
        oid = o.get("id", "?")
        if missing(o.get("constellation")):
            by_field["constellation"].append(oid)
        if missing(o.get("magnitude")):
            by_field["magnitude"].append(oid)
        if not o.get("aliases"):
            by_field["aliases"].append(oid)
        if missing(o.get("angularSize")):
            by_field["angularSize"].append(oid)
        if missing(o.get("bestSeason")):
            by_field["bestSeason"].append(oid)
        if missing(o.get("description")):
            by_field["description"].append(oid)
    print(f"\n=== {fname} ===")
    for k, ids in sorted(by_field.items()):
        print(f"{k}: {len(ids)}")
        for i in ids[:20]:
            print(f"  {i}")
        if len(ids) > 20:
            print(f"  ... +{len(ids)-20} more")
