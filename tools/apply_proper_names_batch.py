#!/usr/bin/env python3
"""Apply user-specified proper common names and dedupe Sh2-103 -> NGC6995."""

from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SEESTAR = ROOT / "assets/catalog/seestar_catalog.json"
COMMON = ROOT / "assets/catalog/common_names.json"
REMAP = ROOT / "assets/catalog/id_remap.json"
EQUIV = ROOT / "assets/catalog/catalog_equivalence.json"
APPLY = ROOT / "tools/apply_korean_common_names.py"

NAMES: dict[str, str] = {
    "NGC2175": "원숭이 머리 성운",
    "Sh2-273": "크리스마스 트리 성운",
    "Sh2-3": "Green Ring 성운",
    "Sh2-54": "Nest 성운",
    "Sh2-296": "Seagull's Wings",
    "Sh2-311": "Skull and Crossbone 성운",
}

EXTRA_ALIASES: dict[str, list[str]] = {
    "NGC2175": ["Monkey Head Nebula", "Monkey Head"],
    "Sh2-273": ["Christmas Tree Nebula", "Christmas Tree"],
    "Sh2-3": ["Green Ring Nebula", "Green Ring"],
    "Sh2-54": ["Nest Nebula", "Nest"],
    "Sh2-296": ["Seagull's Wings Nebula", "Seagull Wings"],
    "Sh2-311": ["Skull and Crossbones Nebula", "Skull and Crossbones"],
    "NGC6995": ["Sh2-103", "Sh2 103", "SH2103", "Cygnus Loop"],
}

REMOVE_REMAP_TO = ("Sh2-103", "NGC6995")


def update_object(obj: dict, new_name: str, extra_aliases: list[str]) -> None:
    old = (obj.get("commonName") or obj.get("name") or "").strip()
    obj["commonName"] = new_name
    obj["name"] = new_name
    aliases = set(obj.get("aliases") or [])
    aliases.update(extra_aliases)
    aliases.discard(new_name)
    obj["aliases"] = sorted(aliases)
    desc = obj.get("description")
    if isinstance(desc, str) and old and old in desc:
        obj["description"] = desc.replace(old, new_name)
    elif isinstance(desc, str) and desc in {"발광성운.", "반사성운."}:
        const = obj.get("constellation", "-")
        if const and const != "-":
            obj["description"] = f"{const}에 위치한 {obj.get('objectType', '천체')}. {new_name}."
        else:
            obj["description"] = f"{new_name}."


def patch_apply_py() -> None:
    text = APPLY.read_text(encoding="utf-8")
    for obj_id, name in NAMES.items():
        pattern = rf'("{re.escape(obj_id)}": )"[^"]*"'
        text, n = re.subn(pattern, rf'\1"{name}"', text, count=1)
        if n == 0:
            print(f"warn: {obj_id} not found in apply_korean_common_names.py")
    text, n = re.subn(r'"Sh2-103": "[^"]*"', '"Sh2-103": "베일 성운"', text, count=1)
    APPLY.write_text(text, encoding="utf-8")


def main() -> None:
    data = json.loads(SEESTAR.read_text(encoding="utf-8-sig"))
    by_id = {o["id"]: o for o in data}
    removed_id, canonical_id = REMOVE_REMAP_TO

    new_data: list[dict] = []
    for obj in data:
        obj_id = obj["id"]
        if obj_id == removed_id:
            continue
        if obj_id in NAMES:
            update_object(obj, NAMES[obj_id], EXTRA_ALIASES.get(obj_id, []))
        new_data.append(obj)

    if removed_id in by_id:
        removed = by_id[removed_id]
        canonical = by_id.get(canonical_id)
        if canonical:
            canonical_aliases = set(canonical.get("aliases") or [])
            canonical_aliases.update(removed.get("aliases") or [])
            canonical_aliases.update(EXTRA_ALIASES.get(canonical_id, []))
            canonical_aliases.add(removed_id)
            canonical_aliases.add(removed.get("displayName", removed_id))
            canonical["aliases"] = sorted(canonical_aliases)

    SEESTAR.write_text(
        json.dumps(new_data, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )

    common = json.loads(COMMON.read_text(encoding="utf-8-sig"))
    for obj_id, name in NAMES.items():
        common[obj_id] = name
    common.pop(removed_id, None)
    COMMON.write_text(
        json.dumps(dict(sorted(common.items())), ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )

    remap = json.loads(REMAP.read_text(encoding="utf-8-sig"))
    remap[removed_id] = canonical_id
    REMAP.write_text(
        json.dumps(dict(sorted(remap.items())), ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )

    equiv = json.loads(EQUIV.read_text(encoding="utf-8-sig"))
    equiv["idRemap"] = remap
    groups = [g for g in equiv.get("groups", []) if g.get("canonicalId") != removed_id]
    for group in groups:
        if group.get("canonicalId") == canonical_id:
            members = set(group.get("members") or [])
            members.add(removed_id)
            group["members"] = sorted(members)
    equiv["groups"] = sorted(groups, key=lambda g: g["canonicalId"])
    EQUIV.write_text(
        json.dumps(equiv, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )

    patch_apply_py()
    print(f"updated names: {len(NAMES)}")
    print(f"removed: {removed_id} -> {canonical_id}")
    print(f"seestar count: {len(data)} -> {len(new_data)}")


if __name__ == "__main__":
    main()
