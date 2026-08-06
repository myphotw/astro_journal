#!/usr/bin/env python3
"""Split mixed aliases into human aliases vs cross-catalog references."""

from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CATALOG_DIR = ROOT / "assets/catalog"

TARGET_FILES = [
    CATALOG_DIR / "messier.json",
    CATALOG_DIR / "seestar_catalog.json",
]

HANGUL = re.compile(r"[\uac00-\ud7a3]")

CROSS_PATTERNS = [
    re.compile(r"^NGC\s*\d", re.I),
    re.compile(r"^IC\s*\d", re.I),
    re.compile(r"^M\s*\d+$", re.I),
    re.compile(r"^C\s*\d+$", re.I),
    re.compile(r"^Caldwell\s*\d", re.I),
    re.compile(r"^Sh2[\s\-]?\d", re.I),
    re.compile(r"^RCW\s*\d", re.I),
    re.compile(r"^vdB\s*\d", re.I),
    re.compile(r"^MWSC\s*\d", re.I),
    re.compile(r"^LBN\s*\d", re.I),
    re.compile(r"^IRAS\s+", re.I),
    re.compile(r"^PGC\s*\d", re.I),
    re.compile(r"^UGC\s*\d", re.I),
    re.compile(r"^UGCA\s*\d", re.I),
    re.compile(r"^2MASX\s+", re.I),
    re.compile(r"^Cr\s*\d", re.I),
    re.compile(r"^Mel\s*\d", re.I),
    re.compile(r"^PN\s+G", re.I),
    re.compile(r"^HD\s+\d", re.I),
    re.compile(r"^HIP\s+\d", re.I),
    re.compile(r"^BD\s+[+\-]", re.I),
    re.compile(r"^ESO[\s\-]", re.I),
    re.compile(r"^SaO\s+\d", re.I),
    re.compile(r"^TYC\s+\d", re.I),
    re.compile(r"^GSC\s+\d", re.I),
    re.compile(r"^LDN\s+\d", re.I),
    re.compile(r"^B\s+\d{3,}", re.I),
    re.compile(r"^(NGC|IC|SH2|RCW|VDB|MWSC|LBN|PGC|UGC)\d+", re.I),
    re.compile(r"^Caldwell\d+$", re.I),
    re.compile(r"^Sh2\d+$", re.I),
]


def is_cross_catalog(value: str) -> bool:
    value = value.strip()
    if not value:
        return False
    if HANGUL.search(value):
        return False
    return any(p.match(value) for p in CROSS_PATTERNS)


def split_values(values: list[str]) -> tuple[list[str], list[str]]:
    aliases: list[str] = []
    cross: list[str] = []
    seen_a: set[str] = set()
    seen_c: set[str] = set()
    for raw in values:
        value = raw.strip()
        if not value:
            continue
        if is_cross_catalog(value):
            key = value.lower()
            if key not in seen_c:
                seen_c.add(key)
                cross.append(value)
        else:
            key = value.lower()
            if key not in seen_a:
                seen_a.add(key)
                aliases.append(value)
    return aliases, cross


def split_object(obj: dict) -> None:
    existing_aliases = list(obj.get("aliases") or [])
    existing_cross = list(obj.get("crossCatalogRefs") or [])
    merged = existing_aliases + existing_cross
    aliases, cross = split_values(merged)
    if aliases:
        obj["aliases"] = aliases
    else:
        obj.pop("aliases", None)
    if cross:
        obj["crossCatalogRefs"] = cross
    else:
        obj.pop("crossCatalogRefs", None)


def split_search_aliases() -> None:
    path = CATALOG_DIR / "search_aliases.json"
    data = json.loads(path.read_text(encoding="utf-8-sig"))
    alias_out: dict[str, list[str]] = {}
    cross_out: dict[str, list[str]] = {}
    for obj_id, values in data.items():
        aliases, cross = split_values(list(values))
        if aliases:
            alias_out[obj_id] = aliases
        if cross:
            cross_out[obj_id] = cross
    path.write_text(
        json.dumps(alias_out, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    cross_path = CATALOG_DIR / "search_cross_catalog.json"
    cross_path.write_text(
        json.dumps(cross_out, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(f"search_aliases.json: {len(alias_out)} keys")
    print(f"search_cross_catalog.json: {len(cross_out)} keys")


def main() -> None:
    total_alias = 0
    total_cross = 0
    for path in TARGET_FILES:
        data = json.load(path.open(encoding="utf-8-sig"))
        for obj in data:
            before_a = len(obj.get("aliases") or [])
            before_c = len(obj.get("crossCatalogRefs") or [])
            split_object(obj)
            total_alias += len(obj.get("aliases") or [])
            total_cross += len(obj.get("crossCatalogRefs") or [])
            _ = before_a, before_c
        path.write_text(
            json.dumps(data, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )
        print(f"{path.name}: processed {len(data)} objects")
    split_search_aliases()
    print(f"total aliases: {total_alias}, cross-catalog refs: {total_cross}")


if __name__ == "__main__":
    main()
