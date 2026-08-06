#!/usr/bin/env python3
"""Audit commonName fields for non-Korean entries."""

from __future__ import annotations

import json
import re
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FILES = [
    ROOT / "assets/catalog/messier.json",
    ROOT / "assets/catalog/seestar_catalog.json",
]

# Hangul detection
HANGUL = re.compile(r"[\uac00-\ud7a3]")


def is_korean(text: str) -> bool:
    return bool(HANGUL.search(text))


def is_catalog_id_only(text: str) -> bool:
    t = text.strip()
    return bool(
        re.fullmatch(r"(M|NGC|IC|C|Caldwell|Sh2|RCW|vdB)\s*[\dA-Z\-]+", t, re.I)
        or re.fullmatch(r"NGC\d+", t, re.I)
        or re.fullmatch(r"IC\d+[A-Z]?", t, re.I)
        or re.fullmatch(r"C\d+", t, re.I)
        or re.fullmatch(r"Sh2-\d+", t, re.I)
        or re.fullmatch(r"RCW\s*\d+", t, re.I)
        or re.fullmatch(r"vdB\s*\d+", t, re.I)
    )


def main() -> None:
    non_ko: list[tuple[str, str, str]] = []
    for path in FILES:
        for obj in json.load(path.open(encoding="utf-8-sig")):
            oid = obj.get("id", "?")
            cn = (obj.get("commonName") or obj.get("name") or "").strip()
            display = (obj.get("displayName") or oid).strip()
            if not cn or cn == display or cn == oid:
                non_ko.append((path.name, oid, cn or display))
            elif not is_korean(cn):
                non_ko.append((path.name, oid, cn))

    print(f"needs korean commonName: {len(non_ko)}")
    samples = Counter(cn for _, _, cn in non_ko)
    for name, count in samples.most_common(40):
        print(f"  {count:3} {name}")
    print("\n--- sample ids ---")
    for row in non_ko[:30]:
        print(f"  {row[1]}: {row[2]}")


if __name__ == "__main__":
    main()
