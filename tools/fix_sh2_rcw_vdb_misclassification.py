# -*- coding: utf-8 -*-
"""Sh2/RCW/vdB 카탈로그 오분류 수정.

Sh2(발광성운/HII영역), RCW(발광성운), vdB(반사성운) 카탈로그는 성격상
성단이 존재하지 않는데도, 원본 시드 데이터에 다수 항목이 '구상성단'으로
잘못 라벨링되어 있었다. ObjectTypeClassifier는 "이미 세분 타입이 있으면
유지"하는 정책이라 이 오류를 그대로 보존해왔으므로, 시드 데이터 자체를
카탈로그 성격에 맞게 수정한다.
"""

import sqlite3
import sys

sys.stdout.reconfigure(encoding="utf-8")

FIXES = {
    "sh2": "발광성운",
    "rcw": "발광성운",
    "vdb": "반사성운",
}


def main():
    conn = sqlite3.connect(r"assets/database/catalog_seed.db")
    cur = conn.cursor()

    total = 0
    for catalog, correct_type in FIXES.items():
        cur.execute(
            "update celestial_objects set object_type=?, type=? "
            "where catalog=? and object_type='구상성단'",
            (correct_type, correct_type, catalog),
        )
        count = cur.rowcount
        total += count
        print(f"{catalog}: {count}건 '구상성단' -> '{correct_type}' 수정")

    conn.commit()
    conn.close()
    print(f"total_fixed: {total}")


if __name__ == "__main__":
    main()
