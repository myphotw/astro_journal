#!/usr/bin/env python3
"""Audit seestar_raw.json for unsupported catalog categories."""
import json
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8")

ROOT = Path(__file__).resolve().parents[1]
RAW = ROOT / "assets" / "catalog" / "seestar_raw.json"
SUPPORTED = {
    "messier", "ngc", "ic", "caldwell", "sh2", "rcw", "vdb", "solar", "milky",
}


def main():
    objs = json.load(open(RAW, encoding="utf-8-sig"))
    print(f"total in seestar_raw.json: {len(objs)}")

    by_catalog = Counter()
    unsupported = defaultdict(list)
    missing_catalog = []

    for o in objs:
        cat = (o.get("catalog") or "").strip().lower()
        if not cat:
            missing_catalog.append(o)
            cat = "(empty)"
        by_catalog[cat] += 1
        if cat not in SUPPORTED and cat != "(empty)":
            unsupported[cat].append(o)

    print("\n== catalog field distribution ==")
    for cat, n in by_catalog.most_common():
        flag = "" if cat in SUPPORTED or cat == "(empty)" else " [UNSUPPORTED]"
        print(f"  {cat}: {n}{flag}")

    print("\n== unsupported samples ==")
    for cat, items in sorted(unsupported.items()):
        print(f"\n  {cat}: {len(items)}")
        for o in items[:6]:
            print(
                f"    id={o.get('id')} name={o.get('name')} "
                f"common={o.get('commonName')} mag={o.get('magnitude')}"
            )

    print(f"\n== missing catalog field: {len(missing_catalog)} ==")
    for o in missing_catalog[:10]:
        print(f"  id={o.get('id')} name={o.get('name')}")


if __name__ == "__main__":
    main()
