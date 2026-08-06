# -*- coding: utf-8 -*-
"""Tier1(메시에/Caldwell/별/태양계/은하수, 총 214개) 상세설명+거리 데이터를
catalog_seed.db에 적용한다.

- description: 항상 새 값으로 교체 (기존 1줄 요약 -> 상세 설명)
- distance_ly: 값이 있는 경우만 갱신 (태양계 등 None인 경우는 건드리지 않음)
- 일부 Caldwell 항목은 과거 데이터 오염으로 name/common_name/object_type이
  잘못돼 있어 fix 튜플이 있는 경우 함께 보정한다.
- C99(석탄 자루, 암흑성운)는 정책상 촬영 대상에서 제외하므로 DB에서 삭제한다.
"""

import importlib.util as _u
import sqlite3
import sys

sys.stdout.reconfigure(encoding="utf-8")


def _load(name, path):
    spec = _u.spec_from_file_location(name, path)
    mod = _u.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def _unpack(value):
    """(distance, desc) 또는 (distance, desc, fix) 튜플을 정규화."""
    if len(value) == 2:
        distance, desc = value
        fix = None
    else:
        distance, desc, fix = value
    return distance, desc, fix


def main():
    messier = _load("tier1_messier", "tools/tier1_messier.py").MESSIER
    caldwell = _load("tier1_caldwell", "tools/tier1_caldwell.py").CALDWELL
    sms = _load("tier1_sms", "tools/tier1_solar_milky_stars.py")

    conn = sqlite3.connect(r"assets/database/catalog_seed.db")
    cur = conn.cursor()

    updated = 0
    distance_set = 0
    identity_fixed = 0
    deleted = 0

    def apply_group(data, is_star=False):
        nonlocal updated, distance_set, identity_fixed
        for obj_id, value in data.items():
            if is_star:
                desc = value
                distance, fix = None, None
            else:
                distance, desc, fix = _unpack(value)

            row = cur.execute(
                "select id from celestial_objects where id=?", (obj_id,)
            ).fetchone()
            if row is None:
                print(f"WARN: id not found, skipped: {obj_id}")
                continue

            cur.execute(
                "update celestial_objects set description=? where id=?",
                (desc, obj_id),
            )
            updated += 1

            if distance:
                cur.execute(
                    "update celestial_objects set distance_ly=? where id=?",
                    (distance, obj_id),
                )
                distance_set += 1

            if fix:
                name, common_name, object_type = fix
                cur.execute(
                    "update celestial_objects set name=?, common_name=?, "
                    "object_type=?, type=? where id=?",
                    (name, common_name, object_type, object_type, obj_id),
                )
                identity_fixed += 1

    apply_group(messier)
    apply_group(caldwell)
    apply_group(sms.SOLAR)
    apply_group(sms.MILKY)

    for obj_id, desc in sms.STARS.items():
        row = cur.execute(
            "select id from celestial_objects where id=?", (obj_id,)
        ).fetchone()
        if row is None:
            print(f"WARN: star id not found, skipped: {obj_id}")
            continue
        cur.execute(
            "update celestial_objects set description=? where id=?",
            (desc, obj_id),
        )
        updated += 1

    # C99: 정책상 촬영 대상에서 제외하는 암흑성운(석탄 자루) -> 삭제
    c99 = cur.execute("select id from celestial_objects where id='C99'").fetchone()
    if c99:
        cur.execute("delete from celestial_objects where id='C99'")
        deleted += 1

    conn.commit()
    conn.close()

    print(f"description_updated: {updated}")
    print(f"distance_set: {distance_set}")
    print(f"identity_fixed: {identity_fixed}")
    print(f"dark_nebula_deleted: {deleted}")


if __name__ == "__main__":
    main()
