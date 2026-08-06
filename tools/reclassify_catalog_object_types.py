#!/usr/bin/env python3
"""Reclassify object_type in catalog_seed.db and remove dark nebulae.

Mirrors lib/services/object_type_classifier.dart rules.
Only reclassifies 기타/empty (plus explicit overrides). Keeps fine types.

실행:
    python tools/reclassify_catalog_object_types.py
    python tools/reclassify_catalog_object_types.py --dry-run
"""

from __future__ import annotations

import argparse
import json
import sqlite3
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SEED_DB = ROOT / "assets" / "database" / "catalog_seed.db"
EXTENDED = ROOT / "assets" / "catalog" / "extended_catalogs.json"

sys.stdout.reconfigure(encoding="utf-8")

LABELS = {
    "galaxy": "은하",
    "galaxyGroup": "은하군",
    "emissionNebula": "발광성운",
    "reflectionNebula": "반사성운",
    "darkNebula": "암흑성운",
    "planetaryNebula": "행성상성운",
    "openCluster": "산개성단",
    "globularCluster": "구상성단",
    "supernovaRemnant": "초신성잔해",
    "complexNebula": "복합성운",
    "nebulaWithCluster": "성운+성단",
    "starCloud": "별구름",
    "milkyWay": "은하수",
    "doubleStar": "쌍성",
    "star": "항성",
    "planet": "행성",
    "moon": "위성",
    "dwarfPlanet": "왜소행성",
    "other": "기타",
}

KNOWN_FINE = set(LABELS.values()) - {"기타", "암흑성운"}


def blob(parts) -> str:
    return " | ".join(
        str(p).strip().lower() for p in parts if p is not None and str(p).strip()
    )


def parse_aliases(raw) -> list[str]:
    if not raw:
        return []
    try:
        data = json.loads(raw)
        if isinstance(data, list):
            return [str(x) for x in data]
    except Exception:
        pass
    return []


def override(id_: str, title_blob: str) -> str | None:
    nid = id_.strip().upper().replace(" ", "")
    if (
        nid in {"NGC2359", "SH2-298"}
        or "토르의 헬멧" in title_blob
        or "thor's helmet" in title_blob
        or "thors helmet" in title_blob
    ):
        return LABELS["emissionNebula"]
    # ID-first: Sh2-273(성운) vs NGC2264(성단) share similar aliases.
    if nid == "SH2-273":
        return LABELS["emissionNebula"]
    if nid == "NGC2264":
        return LABELS["openCluster"]
    if "크리스마스 트리 성운" in title_blob or "christmas tree nebula" in title_blob:
        return LABELS["emissionNebula"]
    if (
        "크리스마스 트리 성단" in title_blob
        or "christmas tree cluster" in title_blob
        or "cone nebula cluster" in title_blob
    ):
        return LABELS["openCluster"]
    if nid == "SH2-171" or "북쪽 삼각형" in title_blob or "northern triangle" in title_blob:
        return LABELS["emissionNebula"]
    if nid in {"NGC7380", "NGC7538", "NGC7822", "NGC2467"}:
        return LABELS["emissionNebula"]
    if nid in {"MW", "MILKY"}:
        return LABELS["milkyWay"]
    return None


def from_catalog(catalog: str, title_blob: str) -> str | None:
    if catalog in {"rcw", "sh2"}:
        return LABELS["emissionNebula"]
    if catalog == "vdb":
        return LABELS["reflectionNebula"]
    if catalog == "milky":
        return LABELS["milkyWay"]
    if catalog == "solar":
        if any(
            k in title_blob
            for k in (
                "왜소",
                "dwarf",
                "명왕",
                "pluto",
                "세레스",
                "ceres",
                "소행성",
                "asteroid",
            )
        ):
            return LABELS["dwarfPlanet"]
        if any(
            k in title_blob
            for k in (
                "위성",
                "moon",
                "달",
                "타이탄",
                "이오",
                "유로파",
                "가니메데",
                "칼리스토",
            )
        ):
            return LABELS["moon"]
        if "태양" in title_blob or "sun" in title_blob:
            return LABELS["star"]
        return LABELS["planet"]
    if catalog in {"star", "stars"}:
        if "쌍성" in title_blob or "double star" in title_blob:
            return LABELS["doubleStar"]
        return LABELS["star"]
    if catalog in {"barnard", "ldn", "lbn"}:
        return LABELS["darkNebula"]
    return None


def from_keywords(b: str) -> str | None:
    if "은하수" in b or "milky way" in b:
        return LABELS["milkyWay"]
    if "은하군" in b or "galaxy group" in b:
        return LABELS["galaxyGroup"]
    if ("galaxy" in b or "은하" in b) and "은하수" not in b:
        return LABELS["galaxy"]
    if "초신성" in b or "supernova remnant" in b:
        return LABELS["supernovaRemnant"]
    if "행성상" in b or "planetary nebula" in b:
        return LABELS["planetaryNebula"]
    if "반사성운" in b or "reflection nebula" in b:
        return LABELS["reflectionNebula"]
    if "암흑성운" in b or "dark nebula" in b:
        return LABELS["darkNebula"]
    if "복합성운" in b:
        return LABELS["complexNebula"]
    if "성운+성단" in b:
        return LABELS["nebulaWithCluster"]
    if "발광성운" in b or "emission nebula" in b or "hii region" in b:
        return LABELS["emissionNebula"]
    if "성운" in b or "nebula" in b:
        return LABELS["emissionNebula"]
    if "구상성단" in b or "globular" in b:
        return LABELS["globularCluster"]
    if "산개성단" in b or "open cluster" in b or "성단" in b or "cluster" in b:
        return LABELS["openCluster"]
    if "별구름" in b or "star cloud" in b:
        return LABELS["starCloud"]
    if "쌍성" in b or "double star" in b:
        return LABELS["doubleStar"]
    if "항성" in b or "bright star" in b:
        return LABELS["star"]
    if "왜소행성" in b or "dwarf planet" in b:
        return LABELS["dwarfPlanet"]
    if "위성" in b:
        return LABELS["moon"]
    if any(k in b for k in ("행성", "planet", "소행성", "asteroid", "혜성", "comet")):
        return LABELS["planet"]
    return None


def classify(row) -> str:
    id_ = row["id"] or ""
    catalog = (row["catalog"] or "").strip().lower()
    aliases = parse_aliases(row["aliases_json"])
    title_blob = blob([id_, row["name"], row["common_name"], *aliases])
    existing = (row["object_type"] or row["type"] or "").strip()

    ov = override(id_, title_blob)
    if ov:
        return ov

    if existing in KNOWN_FINE:
        return existing

    cat = from_catalog(catalog, title_blob)
    if cat:
        return cat

    title_kw = from_keywords(
        blob([id_, row["name"], row["common_name"], *aliases, row["type"], row["object_type"]])
    )
    if title_kw:
        return title_kw

    full = from_keywords(
        blob(
            [
                id_,
                row["name"],
                row["common_name"],
                row["object_type"],
                row["type"],
                row["description"],
                *aliases,
            ]
        )
    )
    if full:
        return full
    return LABELS["other"]


def is_dark(row) -> bool:
    catalog = (row["catalog"] or "").strip().lower()
    if catalog in {"barnard", "ldn", "lbn"}:
        return True
    type_blob = blob([row["object_type"], row["type"]])
    return any(
        k in type_blob
        for k in ("암흑성운", "dark nebula", "molecular cloud", "dust cloud")
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    conn = sqlite3.connect(SEED_DB)
    conn.row_factory = sqlite3.Row
    cur = conn.cursor()
    rows = list(
        cur.execute(
            "select id, catalog, name, common_name, object_type, type, "
            "description, aliases_json from celestial_objects"
        )
    )

    changed = 0
    dark_ids = []
    samples = []
    for row in rows:
        if is_dark(row):
            dark_ids.append(row["id"])
            continue
        new_type = classify(row)
        old = (row["object_type"] or "").strip()
        if new_type != old:
            changed += 1
            if len(samples) < 30:
                samples.append((row["id"], old, new_type, row["name"]))
            if not args.dry_run:
                cur.execute(
                    "update celestial_objects set object_type=?, type=? where id=?",
                    (new_type, new_type, row["id"]),
                )

    print(f"reclassified: {changed}")
    for s in samples:
        print(" ", s)
    print(f"dark_to_delete: {len(dark_ids)}")
    if dark_ids:
        print("dark ids:", ", ".join(dark_ids))

    if not args.dry_run and dark_ids:
        placeholders = ",".join("?" * len(dark_ids))
        cur.execute(
            f"delete from celestial_objects where id in ({placeholders})",
            dark_ids,
        )

    if EXTENDED.exists() and not args.dry_run:
        data = json.loads(EXTENDED.read_text(encoding="utf-8"))
        before = len(data)
        data = [
            item
            for item in data
            if str(item.get("catalog", "")).lower()
            not in {"barnard", "ldn", "lbn"}
            and "암흑" not in str(item.get("objectType", ""))
        ]
        EXTENDED.write_text(
            json.dumps(data, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )
        print(f"extended_catalogs.json: {before} -> {len(data)}")

    if not args.dry_run:
        conn.commit()
    conn.close()

    conn = sqlite3.connect(SEED_DB)
    cur = conn.cursor()
    other_n = cur.execute(
        "select count(*) from celestial_objects where object_type='기타'"
    ).fetchone()[0]
    dark_n = cur.execute(
        "select count(*) from celestial_objects where catalog in ('barnard','ldn','lbn') "
        "or object_type='암흑성운'"
    ).fetchone()[0]
    total = cur.execute("select count(*) from celestial_objects").fetchone()[0]
    print(f"remaining_other: {other_n}")
    print(f"remaining_dark: {dark_n}")
    print(f"total: {total}")
    conn.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
