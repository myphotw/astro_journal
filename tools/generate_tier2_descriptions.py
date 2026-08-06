# -*- coding: utf-8 -*-
"""Tier2 템플릿 기반 상세설명 생성: NGC/IC/Sh2/RCW/vdB (약 13,000여 개).

Tier1(메시에/Caldwell/별/태양계/은하수)처럼 개별 역사·일화를 손으로 쓰는 것은
현실적으로 불가능하므로, 다음 3가지 '검증 가능한 사실'을 조합해 문장을
구성한다. 각 사실은 DB에 이미 저장된 실제 값이므로 허구·추측 정보가
섞이지 않는다.

  1) 카탈로그 배경 설명 (NGC/IC/Sh2/RCW/vdB 각각의 역사적 편찬 배경)
  2) 천체 종류(object_type) 일반 설명 (은하/성운/성단 등 물리적 정의)
  3) 개별 관측 사실 (별자리, 등급, 각크기, 최적 관측 시기 - 해당 row의 실값)

같은 카탈로그·타입 조합이라도 문장 변형을 여러 개 두고 id 해시로 골라
기계적 반복 느낌을 줄인다.
"""

import hashlib
import sqlite3
import sys

sys.stdout.reconfigure(encoding="utf-8")

CATALOG_INTRO = {
    "ngc": [
        "NGC(뉴 제너럴 카탈로그)는 윌리엄·캐롤라인·존 허셜 등의 관측 기록을 바탕으로 1888년 존 드레이어가 편찬한 목록으로, 오늘날까지 가장 널리 쓰이는 심우주 천체 성표 중 하나다.",
        "18~19세기 허셜 가문의 방대한 관측을 집대성해 1888년 존 드레이어가 정리한 NGC(뉴 제너럴 카탈로그)에 속한 천체다.",
    ],
    "ic": [
        "IC(인덱스 카탈로그)는 NGC 편찬 이후 사진 관측 등으로 새로 발견된 천체를 보완하기 위해 1895년과 1908년 두 차례에 걸쳐 존 드레이어가 추가로 정리한 목록이다.",
        "사진 관측 기술이 발전하며 NGC 이후 새롭게 확인된 천체를 보완하기 위해 1895·1908년 존 드레이어가 편찬한 IC(인덱스 카탈로그)에 속한다.",
    ],
    "sh2": [
        "Sh2(샤플리스 카탈로그)는 1959년 미국 천문학자 스튜어트 샤플리스가 팔로마산 천문대의 사진 관측을 바탕으로 발광성운(HII 영역)을 체계적으로 정리한 목록이다.",
        "1959년 스튜어트 샤플리스가 우리 은하의 발광성운(HII 영역)을 조사해 정리한 Sh2(샤플리스 카탈로그)에 속한 천체다.",
    ],
    "rcw": [
        "RCW 카탈로그는 1960년 오스트레일리아의 로저스, 캠벨, 화이트오크가 남반구 하늘의 은하 발광성운을 정리한 목록이다.",
        "1960년 로저스·캠벨·화이트오크가 남반구에서 관측되는 은하 발광성운을 체계적으로 정리한 RCW 카탈로그에 속한다.",
    ],
    "vdb": [
        "vdB(반 덴 베르흐 카탈로그)는 1966년 캐나다 천문학자 시드니 반 덴 베르흐가 밝은 별 주위에서 빛나는 반사성운을 체계적으로 정리한 목록이다.",
        "1966년 시드니 반 덴 베르흐가 밝은 별 인근의 반사성운을 정리해 발표한 vdB(반 덴 베르흐 카탈로그)에 속한 천체다.",
    ],
}

TYPE_EXPLAIN = {
    "은하": [
        "별, 가스, 먼지, 암흑물질이 중력으로 묶여 이루는 거대한 천체 집합으로, 수십억에서 수조 개에 이르는 별을 포함한다.",
        "수많은 별과 성간물질이 중력으로 결속된 독립된 은하계로, 우리 은하 바깥의 우주 공간에 자리한다.",
    ],
    "발광성운": [
        "주변의 뜨겁고 젊은 별이 내는 강한 자외선이 수소 가스를 이온화시켜 스스로 붉게 빛나는 성간 가스 구름이다.",
        "새로 태어난 별들의 자외선 방사로 수소 가스가 들뜬 상태가 되어 붉은빛을 내는 별 탄생 지역이다.",
    ],
    "반사성운": [
        "스스로 빛을 내지 않고, 인근의 밝은 별빛이 성간 먼지 입자에 반사되어 푸른빛으로 보이는 가스·먼지 구름이다.",
        "주변 별빛을 먼지 알갱이가 산란시켜 푸르게 빛나 보이는 성간물질 구름이다.",
    ],
    "행성상성운": [
        "태양과 비슷한 질량의 별이 생을 마감하며 바깥층 가스를 우주 공간으로 서서히 방출해 만들어지는, 비교적 짧은 생애의 성운이다.",
        "적색거성 단계를 지난 별이 마지막으로 가스 껍질을 벗어던지며 형성되는 밝고 둥근 성운이다.",
    ],
    "초신성잔해": [
        "무거운 별이 생을 마치며 일으킨 초신성 폭발의 잔여 물질이 초음속으로 퍼져나가며 주변 성간물질과 충돌해 빛나는 구조다.",
        "별의 격렬한 최후인 초신성 폭발 이후 남은 가스와 충격파가 우주 공간으로 확산되는 잔해다.",
    ],
    "산개성단": [
        "같은 분자운에서 비슷한 시기에 태어난 별들이 비교적 느슨하게 모여 있는, 나이가 젊은 별 무리다.",
        "한 성간 구름에서 함께 탄생한 별들이 중력으로 느슨하게 묶여 있는 젊은 성단이다.",
    ],
    "구상성단": [
        "수만에서 수백만 개에 이르는 늙은 별들이 구형으로 빽빽하게 뭉쳐 있는, 우리 은하에서 가장 오래된 천체 중 하나다.",
        "은하 헤일로를 도는 나이 많은 별들이 강한 중력으로 촘촘하게 결속된 구형 성단이다.",
    ],
    "성운+성단": [
        "갓 태어난 별들로 이뤄진 젊은 성단과, 그 별들을 낳은 모체 성운의 가스가 함께 관측되는 활발한 별 탄생 지역이다.",
        "별 탄생이 진행 중인 성운과 그 안에서 형성된 어린 별들의 성단이 한데 어우러진 천체다.",
    ],
    "복합성운": [
        "발광·반사·암흑 성운의 성질이 한 지역에 함께 나타나는 복합적인 구조의 성운이다.",
        "여러 종류의 성간물질이 뒤섞여 발광과 반사 성질을 동시에 보이는 성운이다.",
    ],
}

DEFAULT_TYPE_EXPLAIN = [
    "카탈로그에 기록된 심우주 천체로, 세부 물리적 특징은 관측 데이터가 쌓이며 점차 밝혀지고 있다.",
]


def _pick(options, seed):
    if not options:
        return ""
    idx = int(hashlib.md5(seed.encode("utf-8")).hexdigest(), 16) % len(options)
    return options[idx]


def _fact_sentence(constellation, mag, angular_size, best_season):
    location = f"{constellation} 방향에 위치하며" if constellation else "밤하늘에 위치하며"

    has_mag = bool(mag) and mag not in ("-", "")
    if has_mag and angular_size:
        detail = f"겉보기 밝기 약 {mag}등급, 시야각 {angular_size} 크기로 관측된다."
    elif has_mag:
        detail = f"겉보기 밝기 약 {mag}등급으로 관측된다."
    elif angular_size:
        detail = f"시야각 {angular_size} 크기로 관측된다."
    else:
        detail = "관측된다."

    sentence = f"{location} {detail}"
    if best_season:
        sentence += f" {best_season}에 촬영하기 좋다."
    return sentence


def build_description(catalog, object_type, constellation, mag, angular_size,
                       best_season, obj_id):
    intro = _pick(CATALOG_INTRO.get(catalog, []), obj_id + "intro")
    type_explain = _pick(
        TYPE_EXPLAIN.get(object_type, DEFAULT_TYPE_EXPLAIN), obj_id + "type"
    )
    fact = _fact_sentence(constellation, mag, angular_size, best_season)
    return " ".join(s for s in [intro, type_explain, fact] if s)


def main():
    conn = sqlite3.connect(r"assets/database/catalog_seed.db")
    cur = conn.cursor()

    rows = cur.execute(
        "select id, catalog, object_type, constellation, mag, angular_size, best_season "
        "from celestial_objects where catalog in ('ngc','ic','sh2','rcw','vdb')"
    ).fetchall()

    updates = []
    for (obj_id, catalog, object_type, constellation, mag, angular_size,
         best_season) in rows:
        desc = build_description(
            catalog, object_type or "", constellation, mag, angular_size,
            best_season, obj_id,
        )
        updates.append((desc, obj_id))

    cur.executemany(
        "update celestial_objects set description=? where id=?", updates
    )
    conn.commit()
    conn.close()
    print(f"tier2_description_updated: {len(updates)}")


if __name__ == "__main__":
    main()
