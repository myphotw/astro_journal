#!/usr/bin/env python3
"""Audit missing catalog metadata fields across import sources."""

from __future__ import annotations

import json
from collections import Counter, defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def is_missing(value: str | None) -> bool:
    if value is None:
        return True
    trimmed = value.strip()
    return trimmed in {"", "-"}


def load_json(path: Path):
    with path.open(encoding="utf-8-sig") as handle:
        return json.load(handle)


def audit_objects(objects: list[dict]) -> dict[str, list[str]]:
    gaps: dict[str, list[str]] = defaultdict(list)
    for obj in objects:
        obj_id = obj.get("id", "?")
        if is_missing(obj.get("constellation")):
            gaps["constellation"].append(obj_id)
        if is_missing(obj.get("magnitude")):
            gaps["magnitude"].append(obj_id)
        aliases = obj.get("aliases") or []
        if not aliases:
            gaps["aliases"].append(obj_id)
        common = (obj.get("commonName") or obj.get("name") or "").strip()
        display = (obj.get("displayName") or obj.get("name") or obj_id).strip()
        if common == display or common == obj_id:
            gaps["commonName"].append(obj_id)
        if is_missing(obj.get("angularSize")):
            gaps["angularSize"].append(obj_id)
        if is_missing(obj.get("description")):
            gaps["description"].append(obj_id)
        if is_missing(obj.get("bestSeason")):
            gaps["bestSeason"].append(obj_id)
    return gaps


def main() -> None:
    messier = load_json(ROOT / "assets/catalog/messier.json")
    seestar = load_json(ROOT / "assets/catalog/seestar_catalog.json")
    solar = load_json(ROOT / "assets/catalog/solar.json")
    milky = load_json(ROOT / "assets/catalog/milkyway.json")
    all_objects = [*messier, *seestar, *solar, *milky]

    gaps = audit_objects(all_objects)
    print(f"total objects: {len(all_objects)}")
    for field, ids in sorted(gaps.items()):
        print(f"{field}: {len(ids)} missing")

    by_catalog = Counter(obj.get("catalog", "messier") for obj in seestar)
  # messier has no catalog field
    print("\nseestar by catalog:", dict(by_catalog))


if __name__ == "__main__":
    main()
