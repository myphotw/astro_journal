import json
import math
import re
import sqlite3
import sys

sys.stdout.reconfigure(encoding="utf-8")

DB = r"D:\999. etc\astro_journal\assets\database\catalog_seed.db"

# 일반 명칭(천체 유형 라벨) — 고유명이 아님
GENERIC = {
    "산개성단", "초신성잔해", "발광성운", "구상성단", "은하", "행성상성운",
    "기타", "반사성운", "행성", "성운+성단", "항성", "위성", "왜소행성",
    "쌍성", "복합성운", "성운", "성단", "은하단", "암흑성운",
}


def parse_mag(v):
    try:
        return float(str(v))
    except Exception:
        return None


def parse_size(v):
    if not v:
        return None
    m = re.findall(r"[\d.]+", str(v))
    if not m:
        return None
    try:
        vals = [float(x) for x in m[:2]]
        return max(vals)
    except Exception:
        return None


def is_proper(common_name, name, obj_type):
    if not common_name:
        return False
    cn = common_name.strip()
    if not cn or cn in GENERIC:
        return False
    if cn == (name or "").strip():
        return False
    if cn == (obj_type or "").strip():
        return False
    return True


def alias_count(aliases_json, cross_json):
    n = 0
    for raw in (aliases_json, cross_json):
        if raw:
            try:
                n += len(json.loads(raw))
            except Exception:
                pass
    return n


def score(row):
    s = 0.0
    proper = is_proper(row["common_name"], row["name"], row["object_type"])
    if proper:
        s += 45
    ac = alias_count(row["aliases_json"], row["cross_catalog_refs_json"])
    s += min(ac, 6) * 4  # up to 24
    mag = parse_mag(row["mag"])
    if mag is not None:
        # 밝을수록 높게: mag 0 -> 25, mag 15 -> 0
        s += max(0.0, min(25.0, (15.0 - mag) / 15.0 * 25.0))
    sz = parse_size(row["angular_size"])
    if sz is not None:
        s += min(15.0, math.log10(sz + 1) * 12.0)
    if row["description"] and str(row["description"]).strip() not in ("", "-"):
        s += 6
    if row["seestar_supported"] == 1:
        s += 20
    return s, proper, ac, mag, sz


conn = sqlite3.connect(DB)
conn.row_factory = sqlite3.Row
rows = conn.execute(
    "SELECT id, catalog, num, name, common_name, object_type, mag, angular_size, "
    "description, aliases_json, cross_catalog_refs_json, seestar_supported "
    "FROM celestial_objects WHERE catalog != 'messier'"
).fetchall()

scored = []
for r in rows:
    sc, proper, ac, mag, sz = score(r)
    scored.append((sc, r, proper))

# per catalog proper-name & seestar counts
print("-- per catalog: proper names / seestar_supported --")
from collections import Counter, defaultdict

cat_proper = Counter()
cat_seestar = Counter()
cat_total = Counter()
for sc, r, proper in scored:
    cat_total[r["catalog"]] += 1
    if proper:
        cat_proper[r["catalog"]] += 1
    if r["seestar_supported"] == 1:
        cat_seestar[r["catalog"]] += 1
for cat in cat_total:
    print(f"  {cat:10} total={cat_total[cat]:5} proper={cat_proper[cat]:4} seestar={cat_seestar[cat]:4}")

def top_by(pred, label, n=10):
    sub = [(sc, r) for sc, r, proper in scored if pred(r)]
    sub.sort(key=lambda x: (-x[0], x[1]["name"] or ""))
    print(f"\n== {label} Top {n} ==")
    for sc, r in sub[:n]:
        print(f"  {sc:6.1f}  {r['id']:10} {r['common_name']!r:28} mag={r['mag']} type={r['object_type']}")

for cat in ["ngc", "ic", "sh2", "rcw", "vdb", "caldwell"]:
    top_by(lambda r, c=cat: r["catalog"] == c, cat.upper())

for otype in ["행성상성운", "은하", "산개성단", "발광성운", "구상성단"]:
    top_by(lambda r, t=otype: r["object_type"] == t, f"objtype:{otype}")

conn.close()
