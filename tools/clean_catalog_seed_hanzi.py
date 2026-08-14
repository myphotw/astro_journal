#!/usr/bin/env python3
"""Remove Hanzi from catalog_seed.db and normalize constellations to Korean."""

from __future__ import annotations

import json
import re
import sqlite3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SEED_DB = ROOT / "assets" / "database" / "catalog_seed.db"
CN_INDEX = (
    ROOT
    / "tools"
    / "seestar_apk_extract"
    / "assets"
    / "main"
    / "SkyMap"
    / "data"
    / "skydata"
    / "skycultures"
    / "cn_western"
    / "index.json"
)

from catalog_identity import IAU_TO_KO

HANZI_RE = re.compile(r"[\u4e00-\u9fff\u3400-\u4dbf]")


def has_hanzi(text: str | None) -> bool:
    return bool(text and HANZI_RE.search(text))


def strip_hanzi(text: str | None) -> str:
    if not text:
        return ""
    cleaned = HANZI_RE.sub("", text)
    cleaned = re.sub(r"\s+", " ", cleaned).strip()
    cleaned = re.sub(r"^[|,\s]+|[|,\s]+$", "", cleaned)
    return cleaned


def load_cn_to_ko() -> dict[str, str]:
    mapping: dict[str, str] = {}
    if CN_INDEX.is_file():
        data = json.loads(CN_INDEX.read_text(encoding="utf-8"))
        for item in data.get("constellations", []):
            native = item.get("common_name", {}).get("native", "")
            iau = item.get("iau", "")
            ko = IAU_TO_KO.get(iau)
            if native and ko:
                mapping[native] = ko
                mapping[f"{native}자리"] = ko
    return mapping


CN_TO_KO = load_cn_to_ko()


def normalize_constellation(value: str | None) -> str:
    text = (value or "").strip()
    if not text or text == "-":
        return text or "-"
    if not has_hanzi(text):
        return text
    direct = CN_TO_KO.get(text)
    if direct:
        return direct
    if text.endswith("座자리"):
        direct = CN_TO_KO.get(text[:-1]) or CN_TO_KO.get(text[:-2] + "座")
        if direct:
            return direct
    if text.endswith("座"):
        direct = CN_TO_KO.get(text)
        if direct:
            return direct
    stripped = strip_hanzi(text)
    if stripped.endswith("자리") and stripped:
        return stripped
    return stripped or "-"


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


def clean_json_list(raw: str | None) -> str | None:
    items = [item for item in parse_json_list(raw) if item and not has_hanzi(item)]
    return json.dumps(items, ensure_ascii=False) if items else None


def clean_search_keywords(raw: str | None) -> str | None:
    if not raw:
        return None
    parts = [part.strip() for part in raw.split("|") if part.strip()]
    kept = [part for part in parts if not has_hanzi(part)]
    return "|".join(kept) if kept else None


def regenerate_description(row: sqlite3.Row) -> str | None:
    constellation = normalize_constellation(row["constellation"])
    obj_type = row["object_type"] or row["type"] or "기타"
    name = row["common_name"] or row["name"] or ""
    if has_hanzi(name):
        name = strip_hanzi(name)
    if constellation and constellation != "-":
        if name and name not in {obj_type, row["id"]}:
            return f"{constellation}에 위치한 {obj_type}. {name}."
        return f"{constellation}에 위치한 {obj_type}."
    if name and not has_hanzi(name):
        return f"{obj_type} · {name}."
    return None


def clean_row(row: sqlite3.Row) -> dict[str, object]:
    updates: dict[str, object] = {}

    constellation = normalize_constellation(row["constellation"])
    if constellation != row["constellation"]:
        updates["constellation"] = constellation

    for column in ("name", "common_name"):
        value = row[column]
        if value and has_hanzi(value):
            cleaned = strip_hanzi(value)
            updates[column] = cleaned or row["name"]

    aliases = clean_json_list(row["aliases_json"])
    if aliases != row["aliases_json"]:
        updates["aliases_json"] = aliases

    cross = clean_json_list(row["cross_catalog_refs_json"])
    if cross != row["cross_catalog_refs_json"]:
        updates["cross_catalog_refs_json"] = cross

    keywords = clean_search_keywords(row["search_keywords"])
    if keywords != row["search_keywords"]:
        updates["search_keywords"] = keywords

    description = row["description"]
    if description and has_hanzi(description):
        updates["description"] = regenerate_description(row)

    return updates


def count_hanzi(conn: sqlite3.Connection) -> dict[str, int]:
    counts: dict[str, int] = {}
    columns = [
        "name",
        "common_name",
        "constellation",
        "description",
        "search_keywords",
        "aliases_json",
    ]
    for column in columns:
        counts[column] = conn.execute(
            f"SELECT COUNT(*) FROM celestial_objects WHERE {column} GLOB '*[一-龥]*'"
        ).fetchone()[0]
    return counts


def main() -> int:
    if not SEED_DB.is_file():
        print(f"Seed DB not found: {SEED_DB}")
        return 1

    conn = sqlite3.connect(SEED_DB)
    conn.row_factory = sqlite3.Row
    before = count_hanzi(conn)
    print("Before:", before)

    rows = conn.execute("SELECT * FROM celestial_objects").fetchall()
    changed = 0
    for row in rows:
        updates = clean_row(row)
        if not updates:
            continue
        assignments = ", ".join(f"{key} = ?" for key in updates)
        conn.execute(
            f"UPDATE celestial_objects SET {assignments} WHERE id = ?",
            [*updates.values(), row["id"]],
        )
        changed += 1

    conn.commit()
    after = count_hanzi(conn)
    print(f"Updated rows: {changed}")
    print("After:", after)
    conn.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
