#!/usr/bin/env python3
"""Find catalog objects with generic type-only common names but known proper names."""

from __future__ import annotations

import csv
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
GENERIC = {
    "발광성운",
    "반사성운",
    "산개성단",
    "구상성단",
    "은하",
    "나선은하",
    "타원은하",
    "행성상성운",
    "초신성잔해",
    "성운",
    "성단",
    "기타",
}

# Known proper names from generator / astronomy references.
KNOWN_PROPER: dict[str, str] = {
    "Sh2-298": "토르의 헬멧",
    "Sh2-101": "튤립 성운",
    "Sh2-155": "동굴 성운",
    "Sh2-308": "돌고래 성운",
    "Sh2-54": "쌍둥이 성운",
    "Sh2-140": "철사 고리 성운",
    "Sh2-171": "초신성 잔해",
    "Sh2-235": "눈사람 성운",
    "Sh2-273": "플라이트 성운",
    "Sh2-311": "애기 성운",
    "Sh2-1": "Sharpless 1",
    "Sh2-3": "Sharpless 3",
    "Sh2-103": "Cygnus Loop fragment",
    "Sh2-108": "LBN 240",
    "Sh2-142": "우주의 뇌",
    "Sh2-157": "뿔 성운",
    "Sh2-158": "NGC 7635 region",
    "Sh2-296": "오리온 B",
}


def is_generic(name: str | None) -> bool:
    if not name:
        return True
    return name.strip() in GENERIC


def load_openngc_names() -> dict[str, str]:
    path = ROOT / "tools/openngc/NGC.csv"
    names: dict[str, str] = {}
    if not path.exists():
        return names
    with path.open(encoding="utf-8") as handle:
        reader = csv.reader(handle, delimiter=";")
        for row in reader:
            if not row or row[0].startswith("#"):
                continue
            obj_id = row[0].strip()
            if len(row) < 20:
                continue
            # Common name is typically near the end before notes
            for field in reversed(row):
                field = field.strip()
                if not field or field in {"Type:1", "Dup"}:
                    continue
                if re.match(r"^Type:\d", field):
                    continue
                if re.search(r"[A-Za-z]{4,}", field) and ";" not in field:
                    if not re.fullmatch(r"[0-9.+\-'; ]+", field):
                        if field not in {"G", "OCl", "GCl", "Neb", "HII", "SNR", "PN"}:
                            names.setdefault(obj_id.replace(" ", ""), field)
                            break
    return names


def main() -> None:
    catalog_files = [
        ROOT / "assets/catalog/seestar_catalog.json",
        ROOT / "assets/catalog/messier.json",
    ]
    openngc = load_openngc_names()
    generic_items: list[dict] = []

    for path in catalog_files:
        for obj in json.load(path.open(encoding="utf-8-sig")):
            cn = (obj.get("commonName") or obj.get("name") or "").strip()
            if not is_generic(cn):
                continue
            obj_id = obj["id"]
            aliases = obj.get("aliases") or []
            eng_aliases = [
                a
                for a in aliases
                if isinstance(a, str)
                and re.search(r"[A-Za-z]{3,}", a)
                and not re.match(
                    r"^(NGC|IC|Sh2|RCW|vdB|Caldwell|C|M|SH2|2MASX|IRAS|PGC)\b",
                    a,
                    re.I,
                )
            ]
            known = KNOWN_PROPER.get(obj_id)
            ngc_key = obj_id.replace("-", " ")
            open_name = openngc.get(obj_id) or openngc.get(ngc_key)
            generic_items.append(
                {
                    "id": obj_id,
                    "catalog": obj.get("catalog", "messier"),
                    "commonName": cn,
                    "constellation": obj.get("constellation", "-"),
                    "known_proper": known,
                    "openngc_name": open_name,
                    "eng_aliases": eng_aliases[:5],
                }
            )

    with_known = [
        x
        for x in generic_items
        if x["known_proper"] or x["openngc_name"] or x["eng_aliases"]
    ]
    with_known.sort(key=lambda x: x["id"])

    print(f"Generic commonName total: {len(generic_items)}")
    print(f"Likely missing proper name: {len(with_known)}")
    print()
    for item in with_known:
        proper = item["known_proper"] or item["openngc_name"] or ", ".join(
            item["eng_aliases"]
        )
        print(
            f"{item['id']}\t{item['catalog']}\t{item['commonName']}\t->\t{proper}"
        )


if __name__ == "__main__":
    main()
