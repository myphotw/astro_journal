#!/usr/bin/env python3
"""Find objects in seestar_catalog.json with unsupported/unmapped catalog prefixes."""
import json
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8")

ROOT = Path(__file__).resolve().parents[1]
JSON = ROOT / "assets" / "catalog" / "seestar_catalog.json"
SUPPORTED = {
    "messier", "ngc", "ic", "caldwell", "sh2", "rcw", "vdb", "solar", "milky",
}

ID_PREFIX = re.compile(
    r"^(M|NGC|IC|C|Sh2-?|RCW|vdB|Barnard|B|LDN|LBN|NN|PK|Abell|Mel|Cr|Tr|"
    r"Do|HCG|UGC|PGC|solar_|mw)\b",
    re.I,
)


def infer_catalog(obj):
    catalog = (obj.get("catalog") or "").strip().lower()
    if catalog:
        return catalog
    oid = obj.get("id", "")
    if oid.startswith("solar_"):
        return "solar"
    if oid == "mw":
        return "milky"
    m = re.match(r"^M(\d+)$", oid, re.I)
    if m:
        return "messier"
    if re.match(r"^NGC\d", oid, re.I):
        return "ngc"
    if re.match(r"^IC\d", oid, re.I):
        return "ic"
    if re.match(r"^C\d+$", oid):
        return "caldwell"
    if re.match(r"^Sh2-?\d", oid, re.I):
        return "sh2"
    if re.match(r"^RCW\d", oid, re.I):
        return "rcw"
    if re.match(r"^vdB\d", oid, re.I):
        return "vdb"
    if re.match(r"^Barnard\d", oid, re.I) or re.match(r"^B\d+$", oid):
        return "barnard"
    if re.match(r"^LDN\d", oid, re.I):
        return "ldn"
    if re.match(r"^LBN\d", oid, re.I):
        return "lbn"
    if re.match(r"^NN\d", oid, re.I):
        return "nn"
    return "unknown"


def main():
    objs = json.load(open(JSON, encoding="utf-8-sig"))
    print(f"total in seestar_catalog.json: {len(objs)}")

    by_catalog = Counter()
    unsupported = defaultdict(list)
    unknown_ids = []

    for o in objs:
        cat = infer_catalog(o)
        by_catalog[cat] += 1
        if cat not in SUPPORTED and cat != "unknown":
            unsupported[cat].append(o)
        if cat == "unknown":
            unknown_ids.append(o)

    print("\n== inferred catalog distribution ==")
    for cat, n in by_catalog.most_common():
        flag = "" if cat in SUPPORTED else " [UNSUPPORTED]"
        print(f"  {cat}: {n}{flag}")

    print("\n== unsupported catalog samples ==")
    for cat, items in sorted(unsupported.items()):
        print(f"\n  {cat}: {len(items)}")
        for o in items[:8]:
            print(
                f"    {o.get('id')} | catalog={o.get('catalog')} | "
                f"name={o.get('name')} | common={o.get('commonName')}"
            )

    print("\n== unknown id samples ==")
    for o in unknown_ids[:20]:
        print(f"  {o.get('id')} | catalog={o.get('catalog')} | name={o.get('name')}")

    # explicit catalog field values not in supported
    explicit_bad = Counter()
    for o in objs:
        c = (o.get("catalog") or "").strip().lower()
        if c and c not in SUPPORTED:
            explicit_bad[c] += 1
    print("\n== explicit unsupported catalog field values ==")
    for c, n in explicit_bad.most_common():
        print(f"  {c}: {n}")


if __name__ == "__main__":
    main()
