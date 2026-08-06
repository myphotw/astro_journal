#!/usr/bin/env python3
"""Find mutual cross-catalog reference groups in seed DB."""
import json
import re
import sqlite3
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SEED = ROOT / "assets/database/catalog_seed.db"

PRIORITY = {
    "messier": 0, "ngc": 1, "ic": 2, "caldwell": 3, "sh2": 4,
    "rcw": 5, "vdb": 6, "barnard": 7, "ldn": 8, "lbn": 9,
}


def norm(value: str) -> str:
    return re.sub(r"[\s\-_]+", "", value).upper()


def parse_list(raw):
    if not raw:
        return []
    try:
        return [str(x) for x in json.loads(raw)]
    except json.JSONDecodeError:
        return []


def main():
    conn = sqlite3.connect(SEED)
    rows = conn.execute(
        "select id, catalog, common_name, constellation, ra, dec, "
        "cross_catalog_refs_json, aliases_json from celestial_objects"
    ).fetchall()
    by_id = {r[0]: r for r in rows}
    lookup = {norm(r[0]): r[0] for r in rows}

    def resolve(ref: str) -> str | None:
        key = norm(ref)
        if key in lookup:
            return lookup[key]
        m = re.match(r"^M(\d+)$", key)
        if m and f"M{m.group(1)}" in by_id:
            return f"M{m.group(1)}"
        m = re.match(r"^NGC(\d+)([AB])?$", key)
        if m:
            oid = f"NGC{m.group(1)}{m.group(2) or ''}"
            if oid in by_id:
                return oid
        m = re.match(r"^IC(\d+)([AB])?$", key)
        if m:
            oid = f"IC{m.group(1)}{m.group(2) or ''}"
            if oid in by_id:
                return oid
        m = re.match(r"^SH2(\d+)$", key)
        if m and f"Sh2-{m.group(1)}" in by_id:
            return f"Sh2-{m.group(1)}"
        m = re.match(r"^RCW(\d+)$", key)
        if m and f"RCW{m.group(1)}" in by_id:
            return f"RCW{m.group(1)}"
        m = re.match(r"^C(\d+)$", key)
        if m and f"C{m.group(1)}" in by_id:
            return f"C{m.group(1)}"
        return None

    edges = defaultdict(set)
    for row in rows:
        oid = row[0]
        refs = set(parse_list(row[6]) + parse_list(row[7]))
        for ref in refs:
            target = resolve(ref)
            if target and target != oid:
                edges[oid].add(target)

    mutual = []
    seen = set()
    for a, bs in edges.items():
        for b in bs:
            if a in edges.get(b, set()) and by_id[a][1] != by_id[b][1]:
                pair = tuple(sorted((a, b)))
                if pair not in seen:
                    seen.add(pair)
                    mutual.append(pair)

    parent = {r[0]: r[0] for r in rows}

    def find(x):
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x

    def union(a, b):
        ra, rb = find(a), find(b)
        if ra != rb:
            parent[rb] = ra

    for a, b in mutual:
        union(a, b)

    groups = defaultdict(set)
    for oid in by_id:
        groups[find(oid)].add(oid)

    interesting = [sorted(g) for g in groups.values() if len(g) > 1]
    interesting.sort(key=lambda g: (-len(g), g[0]))
    print(f"mutual pairs: {len(mutual)}")
    print(f"groups: {len(interesting)}")
    for g in interesting[:50]:
        info = [
            (x, by_id[x][1], by_id[x][2], by_id[x][3])
            for x in g
        ]
        print(g, info)


if __name__ == "__main__":
    main()
