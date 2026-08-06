"""카테고리별 대표 천체(is_featured)와 표시 우선순위(display_priority)를
Seestar 파생 메타데이터로 자동 생성한다.

- 대표 천체 목록을 하드코딩하지 않는다.
- catalog_seed.db(= Seestar 파생 데이터)를 분석하여 유명도를 자동 계산한다.
- lib/services/catalog_featured_ranking_service.dart 와 동일한 알고리즘을 사용한다.
- Seestar StarDB가 갱신되어 seed가 바뀌면 재실행만으로 우선순위가 자동 갱신된다.

실행:
    python tools/generate_featured_ranking.py           # seed DB에 반영 + 리포트
    python tools/generate_featured_ranking.py --report  # 리포트만 (쓰기 없음)
"""

import argparse
import json
import math
import re
import sqlite3
import sys
from collections import defaultdict

sys.stdout.reconfigure(encoding="utf-8")

DB = r"assets/database/catalog_seed.db"
MESSIER = "messier"
DEFAULT_PRIORITY = 9999

MIN_FEATURED = 10
MAX_FEATURED = 50
FEATURED_RATIO = 0.1

GENERIC_NAMES = {
    "산개성단", "초신성잔해", "발광성운", "구상성단", "은하", "행성상성운",
    "기타", "반사성운", "행성", "성운+성단", "항성", "위성", "왜소행성",
    "쌍성", "복합성운", "성운", "성단", "은하단", "암흑성운", "성협",
}

CATALOG_ID_RE = re.compile(
    r"^(M|NGC|IC|C|Caldwell|Sh2-?|RCW|vdB)\s*\d+[A-Za-z]?$", re.IGNORECASE
)


def is_proper_name(common_name, object_type):
    if not common_name:
        return False
    cn = common_name.strip()
    if not cn or cn in GENERIC_NAMES:
        return False
    if cn == (object_type or "").strip():
        return False
    if CATALOG_ID_RE.match(cn):
        return False
    return True


def list_length(raw):
    if not raw:
        return 0
    try:
        data = json.loads(raw)
        return len(data) if isinstance(data, list) else 0
    except Exception:
        return 0


def parse_mag(v):
    try:
        return float(str(v))
    except Exception:
        return None


def parse_max_size(v):
    if not v:
        return None
    nums = re.findall(r"[\d.]+", str(v))
    if not nums:
        return None
    best = None
    for n in nums[:2]:
        try:
            val = float(n)
        except Exception:
            continue
        if best is None or val > best:
            best = val
    return best


def score(row):
    s = 0.0
    if is_proper_name(row["common_name"], row["object_type"]):
        s += 45
    alias = list_length(row["aliases_json"]) + list_length(
        row["cross_catalog_refs_json"]
    )
    s += min(alias, 6) * 4
    mag = parse_mag(row["mag"])
    if mag is not None:
        s += max(0.0, min(25.0, (15.0 - mag) / 15.0 * 25.0))
    size = parse_max_size(row["angular_size"])
    if size is not None:
        s += min(15.0, math.log10(size + 1) * 12.0)
    desc = row["description"]
    if desc and str(desc).strip() not in ("", "-"):
        s += 6
    if row["seestar_supported"] == 1:
        s += 20
    return s


def featured_count(n):
    if n <= MIN_FEATURED:
        return n
    return min(MAX_FEATURED, max(MIN_FEATURED, round(n * FEATURED_RATIO)))


def compute(conn):
    rows = conn.execute(
        "SELECT id, catalog, num, name, common_name, object_type, mag, "
        "angular_size, description, aliases_json, cross_catalog_refs_json, "
        "seestar_supported FROM celestial_objects"
    ).fetchall()

    by_catalog = defaultdict(list)
    for r in rows:
        if r["catalog"] == MESSIER:
            continue
        by_catalog[r["catalog"]].append((score(r), r))

    result = {}  # id -> (is_featured, display_priority)
    for catalog, scored in by_catalog.items():
        scored.sort(key=lambda x: (-x[0], (x[1]["name"] or "")))
        fcount = featured_count(len(scored))
        for i, (_, r) in enumerate(scored):
            result[r["id"]] = (1 if i < fcount else 0, i + 1)
    return rows, by_catalog, result


def write_back(conn, result):
    cur = conn.cursor()
    for oid, (feat, prio) in result.items():
        cur.execute(
            "UPDATE celestial_objects SET is_featured=?, display_priority=? "
            "WHERE id=?",
            (feat, prio, oid),
        )
    # Messier: 기본값 유지
    cur.execute(
        "UPDATE celestial_objects SET is_featured=0, display_priority=? "
        "WHERE catalog=?",
        (DEFAULT_PRIORITY, MESSIER),
    )
    conn.commit()


def ensure_columns(conn):
    cols = [r[1] for r in conn.execute("PRAGMA table_info(celestial_objects)")]
    if "is_featured" not in cols:
        conn.execute(
            "ALTER TABLE celestial_objects ADD COLUMN is_featured "
            "INTEGER NOT NULL DEFAULT 0"
        )
    if "display_priority" not in cols:
        conn.execute(
            "ALTER TABLE celestial_objects ADD COLUMN display_priority "
            f"INTEGER NOT NULL DEFAULT {DEFAULT_PRIORITY}"
        )
    conn.commit()


def report(conn, by_catalog, result):
    def top(rows_with_score, label, n=10):
        rows_with_score = sorted(
            rows_with_score, key=lambda x: (-x[0], (x[1]["name"] or ""))
        )
        print(f"\n== {label} Top {n} ==")
        for sc, r in rows_with_score[:n]:
            feat = "★" if result.get(r["id"], (0, 0))[0] else " "
            prio = result.get(r["id"], (0, DEFAULT_PRIORITY))[1]
            print(
                f"  {feat} #{prio:<4} {sc:6.1f}  {r['id']:10} "
                f"{(r['common_name'] or ''):26} mag={r['mag']}"
            )

    for cat in ["ngc", "ic", "sh2", "rcw", "vdb", "caldwell"]:
        if cat in by_catalog:
            top(by_catalog[cat], cat.upper())

    # object_type 기준 검증
    all_rows = conn.execute(
        "SELECT id, catalog, name, common_name, object_type, mag, "
        "angular_size, description, aliases_json, cross_catalog_refs_json, "
        "seestar_supported FROM celestial_objects WHERE catalog != ?",
        (MESSIER,),
    ).fetchall()
    by_type = defaultdict(list)
    for r in all_rows:
        by_type[r["object_type"]].append((score(r), r))
    for otype in ["행성상성운", "은하", "산개성단", "발광성운", "구상성단"]:
        if otype in by_type:
            top(by_type[otype], f"유형:{otype}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--report", action="store_true", help="쓰기 없이 리포트만")
    parser.add_argument("--db", default=DB)
    args = parser.parse_args()

    conn = sqlite3.connect(args.db)
    conn.row_factory = sqlite3.Row

    if not args.report:
        ensure_columns(conn)

    rows, by_catalog, result = compute(conn)

    if not args.report:
        write_back(conn, result)
        print(f"반영 완료: {len(result)}개 천체 (Messier 제외)")

    featured_total = sum(1 for v in result.values() if v[0])
    print(f"대표 천체(featured) 총 {featured_total}개 / 전체 {len(result)}개")
    print("\n-- 카탈로그별 featured 수 --")
    for cat, scored in by_catalog.items():
        fc = featured_count(len(scored))
        print(f"  {cat:10} featured={fc:4} / total={len(scored)}")

    report(conn, by_catalog, result)
    conn.close()


if __name__ == "__main__":
    main()
