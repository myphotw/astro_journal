#!/usr/bin/env python3
"""Shorten '{별자리} {유형}' common names to just '{유형}'."""

from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TARGET_FILES = [
    ROOT / "assets/catalog/messier.json",
    ROOT / "assets/catalog/seestar_catalog.json",
]
COMMON_NAMES_PATH = ROOT / "assets/catalog/common_names.json"
CONSTELLATION_SUFFIX = re.compile(r"^.+자리\s+")


def strip_constellation_prefix(common: str, const: str) -> str | None:
    if not const or const == "-":
        return None

    prefixes: list[str] = [const]
    if not const.endswith("자리"):
        prefixes.append(f"{const}자리")
    base = const.removesuffix("자리")
    if base != const:
        prefixes.append(f"{base}자리")

    seen: set[str] = set()
    for prefix in prefixes:
        if prefix in seen:
            continue
        seen.add(prefix)
        token = f"{prefix} "
        if not common.startswith(token):
            continue
        rest = common[len(token) :].strip()
        if len(rest) == 1 and rest.isascii():
            return None
        if rest:
            return rest
    return None


NON_CONSTELLATION_PREFIXES = {"가장자리"}


def shorten_for_object(obj: dict) -> str | None:
    common = (obj.get("commonName") or "").strip()
    const = (obj.get("constellation") or "").strip()
    obj_type = (obj.get("objectType") or obj.get("type") or "").strip()
    if not common:
        return None

    if obj_type:
        if const and const != "-" and common == f"{const} {obj_type}":
            if len(obj_type) == 1 and obj_type.isascii():
                return None
            return obj_type

        # 별자리 접두 + 유형 접미 (별자리 필드와 표기 불일치 포함)
        if common.endswith(obj_type) and len(common) > len(obj_type):
            prefix = common[: -len(obj_type)].strip()
            if prefix.endswith("자리"):
                return obj_type

    rest = strip_constellation_prefix(common, const)
    if rest:
        return rest

    if const in ("", "-"):
        match = re.match(r"^(\S+자리) (.+)$", common)
        if match and match.group(1) not in NON_CONSTELLATION_PREFIXES:
            tail = match.group(2).strip()
            if len(tail) == 1 and tail.isascii():
                return None
            if tail:
                return tail

    return None


def shorten_value(value: str, obj: dict) -> str | None:
    fake = {"commonName": value, **obj}
    return shorten_for_object(fake)


def main() -> None:
    total = 0

    for path in TARGET_FILES:
        data = json.load(path.open(encoding="utf-8-sig"))
        changed = 0
        for obj in data:
            new_common = shorten_for_object(obj)
            if not new_common:
                continue
            old_common = obj.get("commonName", "")
            if old_common == new_common:
                continue
            obj["commonName"] = new_common
            if obj.get("name") == old_common:
                obj["name"] = new_common
            desc = obj.get("description")
            if isinstance(desc, str) and old_common in desc:
                obj["description"] = desc.replace(old_common, new_common)
            changed += 1
            total += 1
        if changed:
            json.dump(data, path.open("w", encoding="utf-8"), ensure_ascii=False, indent=2)
            path.open("a", encoding="utf-8").write("\n")
        print(f"{path.name}: {changed}")

    common_names = json.load(COMMON_NAMES_PATH.open(encoding="utf-8-sig"))
    cn_changed = 0
    # Re-load objects for id -> type/const lookup
    lookup: dict[str, dict] = {}
    for path in TARGET_FILES:
        for obj in json.load(path.open(encoding="utf-8-sig")):
            lookup[obj["id"]] = obj

    for obj_id, value in list(common_names.items()):
        obj = lookup.get(obj_id)
        if not obj:
            continue
        new_value = shorten_value(value, obj)
        if new_value and new_value != value:
            common_names[obj_id] = new_value
            cn_changed += 1

    if cn_changed:
        json.dump(
            dict(sorted(common_names.items(), key=lambda x: x[0])),
            COMMON_NAMES_PATH.open("w", encoding="utf-8"),
            ensure_ascii=False,
            indent=2,
        )
        COMMON_NAMES_PATH.open("a", encoding="utf-8").write("\n")
    print(f"common_names.json: {cn_changed}")
    print(f"total: {total}")


if __name__ == "__main__":
    main()
