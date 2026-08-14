#!/usr/bin/env python3
"""Remove cross-catalog duplicate objects; keep highest-priority catalog entry."""

from __future__ import annotations

import json
import re
from pathlib import Path

from catalog_identity import CALDWELL_PRIMARY

ROOT = Path(__file__).resolve().parents[1]
CATALOG_DIR = ROOT / "assets/catalog"
SEESTAR_PATH = CATALOG_DIR / "seestar_catalog.json"
REMAP_PATH = CATALOG_DIR / "id_remap.json"
EQUIV_PATH = CATALOG_DIR / "catalog_equivalence.json"
COMMON_NAMES_PATH = CATALOG_DIR / "common_names.json"
OPENNGC_PATH = ROOT / "tools/openngc/NGC.csv"

# lib/core/constants/catalog_type.dart mergePriority
PRIORITY = {
    "messier": 0,
    "ngc": 1,
    "ic": 2,
    "caldwell": 3,
    "sh2": 4,
    "rcw": 5,
    "vdb": 6,
}

SEPARATE_IDS = {"IC1318A", "IC1318B", "IC1396A", "IC1396B"}
def load_caldwell_primary() -> dict[int, str]:
    return dict(CALDWELL_PRIMARY)


def load_ic_dup_to_ngc() -> dict[str, str]:
    mapping: dict[str, str] = {}
    if not OPENNGC_PATH.exists():
        return mapping
    with OPENNGC_PATH.open(encoding="utf-8") as handle:
        for line in handle:
            if not line.startswith("IC"):
                continue
            parts = line.strip().split(";")
            if len(parts) < 2 or parts[1] != "Dup":
                continue
            ic_num = parts[0].replace("IC", "").lstrip("0") or "0"
            ic_id = f"IC{ic_num}"
            ngc_ref = None
            for field in reversed(parts):
                field = field.strip()
                m = re.fullmatch(r"0*(\d+)([A-Z]?)", field)
                if m and int(m.group(1)) < 10000:
                    ngc_ref = m.group(1)
                    break
            if ngc_ref:
                mapping[ic_id] = f"NGC{ngc_ref}"
    return mapping


class UnionFind:
    def __init__(self) -> None:
        self.parent: dict[str, str] = {}

    def add(self, node: str) -> None:
        self.parent.setdefault(node, node)

    def find(self, node: str) -> str:
        self.parent.setdefault(node, node)
        if self.parent[node] != node:
            self.parent[node] = self.find(self.parent[node])
        return self.parent[node]

    def unite(self, a: str, b: str) -> None:
        self.add(a)
        self.add(b)
        ra, rb = self.find(a), self.find(b)
        if ra != rb:
            self.parent[rb] = ra


def pick_canonical(members: list[dict]) -> dict:
    def sort_key(obj: dict) -> tuple[int, str]:
        catalog = obj.get("catalog", "")
        return (PRIORITY.get(catalog, 99), obj["id"])

    return sorted(members, key=sort_key)[0]


def merge_aliases(canonical: dict, members: list[dict]) -> None:
    aliases: set[str] = set(canonical.get("aliases") or [])
    aliases.add(canonical["id"])
    aliases.add(canonical.get("displayName", ""))
    for member in members:
        aliases.add(member["id"])
        aliases.add(member.get("displayName", ""))
        aliases.update(member.get("aliases") or [])
    aliases.discard("")
    aliases.discard(canonical["id"])
    aliases.discard(canonical.get("displayName"))
    canonical["aliases"] = sorted(aliases)


def build_unions(ids: set[str], caldwell: dict[int, str], ic_dup: dict[str, str]) -> UnionFind:
    uf = UnionFind()
    for obj_id in ids:
        uf.add(obj_id)

    for ic_id, ngc_id in ic_dup.items():
        if ic_id in ids and ngc_id in ids:
            uf.unite(ic_id, ngc_id)

    ngc_to_ics: dict[str, list[str]] = {}
    for ic_id, ngc_id in ic_dup.items():
        if ic_id in ids:
            ngc_to_ics.setdefault(ngc_id, []).append(ic_id)

    for number, primary in caldwell.items():
        c_id = f"C{number}"
        if c_id not in ids:
            continue
        if primary in ids:
            uf.unite(c_id, primary)
            continue
        for ic_id in ngc_to_ics.get(primary, []):
            uf.unite(c_id, ic_id)

    return uf


def main() -> None:
    objects = json.loads(SEESTAR_PATH.read_text(encoding="utf-8-sig"))
    by_id = {obj["id"]: obj for obj in objects}
    ids = set(by_id)

    caldwell = load_caldwell_primary()
    ic_dup = load_ic_dup_to_ngc()
    uf = build_unions(ids, caldwell, ic_dup)

    clusters: dict[str, list[dict]] = {}
    for obj_id in ids:
        if obj_id in SEPARATE_IDS:
            clusters[obj_id] = [by_id[obj_id]]
            continue
        root = uf.find(obj_id)
        clusters.setdefault(root, []).append(by_id[obj_id])

    kept: list[dict] = []
    id_remap: dict[str, str] = {}
    groups: list[dict] = []
    removed = 0

    for members in clusters.values():
        members = sorted(members, key=lambda o: o["id"])
        canonical = pick_canonical(members)
        merge_aliases(canonical, members)
        kept.append(canonical)
        member_ids = [m["id"] for m in members]
        groups.append(
            {
                "canonicalId": canonical["id"],
                "members": member_ids,
                **(
                    {"commonName": canonical.get("commonName")}
                    if canonical.get("commonName")
                    else {}
                ),
            }
        )
        for member in members:
            if member["id"] != canonical["id"]:
                id_remap[member["id"]] = canonical["id"]
                removed += 1

    kept.sort(key=lambda o: o["id"])
    groups.sort(key=lambda g: g["canonicalId"])

    existing_equiv = json.loads(EQUIV_PATH.read_text(encoding="utf-8-sig"))
    existing_remap = existing_equiv.get("idRemap", {})
    # The generator owns cross-catalog identity. This pass may add OpenNGC
    # duplicate collapses, but it never resurrects stale append-only remaps.
    id_remap = {**existing_remap, **id_remap}
    id_remap = dict(sorted(id_remap.items()))

    SEESTAR_PATH.write_text(
        json.dumps(kept, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    REMAP_PATH.write_text(
        json.dumps(dict(sorted(id_remap.items())), ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )

    existing_groups = existing_equiv.get("groups", [])
    group_by_canonical = {g["canonicalId"]: g for g in existing_groups}
    for group in groups:
        if len(group.get("members", [])) > 1:
            group_by_canonical[group["canonicalId"]] = group
    equiv = {
        "version": 1,
        "groups": sorted(group_by_canonical.values(), key=lambda g: g["canonicalId"]),
        "messierNgc": existing_equiv.get("messierNgc", {}),
        "idRemap": id_remap,
    }
    EQUIV_PATH.write_text(
        json.dumps(equiv, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )

    if COMMON_NAMES_PATH.exists():
        common_names = json.loads(COMMON_NAMES_PATH.read_text(encoding="utf-8-sig"))
        for member_id in id_remap:
            common_names.pop(member_id, None)
        for obj in kept:
            cn = obj.get("commonName")
            if cn:
                common_names[obj["id"]] = cn
        COMMON_NAMES_PATH.write_text(
            json.dumps(dict(sorted(common_names.items())), ensure_ascii=False, indent=2)
            + "\n",
            encoding="utf-8",
        )

    print(f"seestar_catalog.json: {len(objects)} -> {len(kept)} (-{removed})")
    print(f"id_remap entries: {len(id_remap)}")
    for member, canonical in sorted(id_remap.items()):
        print(f"  {member} -> {canonical}")


if __name__ == "__main__":
    main()
