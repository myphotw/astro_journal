#!/usr/bin/env python3
"""Deep audit: mapping issues, id/catalog mismatches, enrichable gaps."""
import json
import re
import sqlite3
import sys
from collections import Counter, defaultdict
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8")

ROOT = Path(__file__).resolve().parents[1]
DB = ROOT / "assets" / "database" / "catalog_seed.db"
SUPPORTED = {
    "messier", "ngc", "ic", "caldwell", "sh2", "rcw", "vdb", "solar", "milky",
}


def missing(v):
    return v is None or str(v).strip() in {"", "-"}


def expected_id(catalog, num, suffix):
    suffix = suffix or ""
    if catalog == "messier":
        return f"M{num}"
    if catalog == "ngc":
        return f"NGC{num}"
    if catalog == "ic":
        return f"IC{num}{suffix}"
    if catalog == "caldwell":
        return f"C{num}"
    if catalog == "sh2":
        return f"Sh2-{num}"
    if catalog == "rcw":
        return f"RCW{num}"
    if catalog == "vdb":
        return f"vdB{num}"
    if catalog == "solar":
        return f"solar_{num}"
    if catalog == "milky":
        return "mw"
    return None


def main():
    conn = sqlite3.connect(DB)
    conn.row_factory = sqlite3.Row
    rows = conn.execute("SELECT * FROM celestial_objects").fetchall()

    id_mismatch = []
    unknown_catalog = []
    for r in rows:
        cat = r["catalog"]
        if cat not in SUPPORTED:
            unknown_catalog.append(dict(r))
        exp = expected_id(cat, r["num"], r["suffix"])
        if exp and r["id"] != exp:
            id_mismatch.append((r["id"], exp, cat))

    print(f"id/catalog mismatch: {len(id_mismatch)}")
    for item in id_mismatch[:15]:
        print(f"  id={item[0]} expected={item[1]} catalog={item[2]}")

    print(f"\nunknown catalog rows: {len(unknown_catalog)}")

    # cross refs pointing nowhere
    all_ids = {r["id"] for r in rows}
    missing_refs = Counter()
    samples = []
    ref_re = re.compile(
        r"^(M|NGC|IC|C|Sh2-?|RCW|vdB|Barnard|B|LDN|LBN)\s*[\dA-Za-z]+",
        re.I,
    )
    for r in rows:
        for field in ("aliases_json", "cross_catalog_refs_json"):
            raw = r[field]
            if not raw:
                continue
            try:
                items = json.loads(raw)
            except Exception:
                continue
            for item in items:
                m = ref_re.match(str(item).strip())
                if not m:
                    continue
                key = str(item).strip()
                # normalize common refs to id-ish
                norm = re.sub(r"\s+", "", key)
                if norm not in all_ids and key not in all_ids:
                    # try loose match
                    loose = norm.upper().replace("SH2", "Sh2-").replace("SH2-", "Sh2-")
                    if loose not in all_ids and norm.upper() not in all_ids:
                        missing_refs[key] += 1
                        if len(samples) < 25:
                            samples.append((r["id"], key))

    print(f"\nunresolved cross-ref designations (top 20):")
    for ref, n in missing_refs.most_common(20):
        print(f"  {ref}: {n}")

    print("\nsamples of refs without primary row:")
    for src, ref in samples[:20]:
        print(f"  {src} -> {ref}")

    # enrichable gaps by supported catalog
    print("\n== enrichable gaps (mag/size/constellation) ==")
    for cat in sorted(SUPPORTED):
        subset = [r for r in rows if r["catalog"] == cat]
        if not subset:
            continue
        mag_miss = sum(1 for r in subset if missing(r["mag"]))
        size_miss = sum(1 for r in subset if missing(r["angular_size"]))
        con_miss = sum(1 for r in subset if missing(r["constellation"]))
        if mag_miss or size_miss or con_miss:
            print(
                f"  {cat:8} total={len(subset):5} "
                f"mag={mag_miss:4} size={size_miss:4} constellation={con_miss:4}"
            )

    conn.close()


if __name__ == "__main__":
    main()
