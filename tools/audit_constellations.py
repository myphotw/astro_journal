#!/usr/bin/env python3
"""Find inconsistent Korean constellation names across catalog JSON."""

from __future__ import annotations

import json
import re
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FILES = [
    ROOT / "assets/catalog/messier.json",
    ROOT / "assets/catalog/seestar_catalog.json",
    ROOT / "assets/catalog/ngc.json",
    ROOT / "assets/catalog/ic.json",
    ROOT / "assets/catalog/caldwell.json",
    ROOT / "assets/catalog/sh2.json",
]

# Canonical Korean IAU names (standard short form used in Korean astronomy apps).
CANONICAL = {
    "And": "안드로메다자리",
    "Ant": "개미자리",
    "Aps": "파리자리",
    "Aql": "독수리자리",
    "Aqr": "물병자리",
    "Ara": "제단자리",
    "Ari": "양자리",
    "Aur": "마차부자리",
    "Boo": "목동자리",
    "CMa": "큰개자리",
    "CMi": "작은개자리",
    "Cnc": "게자리",
    "CVn": "사냥개자리",
    "Cap": "염소자리",
    "Car": "용골자리",
    "Cas": "카시오페아자리",
    "Cen": "센타우루스자리",
    "Cep": "세페우스자리",
    "Cet": "고래자리",
    "Cha": "카멜레온자리",
    "Cir": "컴퍼스자리",
    "Col": "비둘기자리",
    "Com": "머리털자리",
    "CrA": "남쪽왕관자리",
    "CrB": "북쪽왕관자리",
    "Crt": "컵자리",
    "Cru": "남십자자리",
    "Crv": "까마귀자리",
    "Cyg": "백조자리",
    "Del": "돌고래자리",
    "Dor": "도라도자리",
    "Dra": "용자리",
    "Equ": "승마자리",
    "Eri": "에리다누스자리",
    "For": "화로자리",
    "Gem": "쌍둥이자리",
    "Gru": "두루미자리",
    "Her": "헤라클레스자리",
    "Hor": "시계자리",
    "Hya": "물뱀자리",
    "Hyi": "작은바다뱀자리",
    "Ind": "인디언자리",
    "Lac": "도마뱀자리",
    "Leo": "사자자리",
    "LMi": "작은사자자리",
    "Lep": "토끼자리",
    "Lib": "처녀자리",
    "Lup": "늑대자리",
    "Lyn": "여우자리",
    "Lyr": "리라자리",
    "Men": "탁자자리",
    "Mic": "현미경자리",
    "Mon": "외뿔소자리",
    "Mus": "쥐자리",
    "Nor": "정사각형자리",
    "Oct": "남극자리",
    "Oph": "뱀주인자리",
    "Ori": "오리온자리",
    "Pav": "공작자리",
    "Peg": "페가수스자리",
    "Per": "페르세우스자리",
    "Phe": "봉황자리",
    "Pic": "화가자리",
    "PsA": "남쪽물고기자리",
    "Psc": "물고기자리",
    "Pup": "고물자리",
    "Pyx": "나침반자리",
    "Ret": "망원경자리",
    "Sge": "화살자리",
    "Sgr": "궁수자리",
    "Sco": "전갈자리",
    "Scl": "조각가자리",
    "Sct": "방패자리",
    "Ser": "뱀자리",
    "Sex": "육분의자리",
    "Tau": "황소자리",
    "Tel": "망원경자리",
    "Tri": "삼각자리",
    "TrA": "남쪽삼각형자리",
    "Tuc": "큰부리자리",
    "UMa": "큰곰자리",
    "UMi": "작은곰자리",
    "Vel": "돛자리",
    "Vir": "처녀자리",
    "Vol": "비행고자리",
    "Vul": "거문고자리",
}

# Short / legacy aliases in data → canonical.
ALIASES = {
    "안드로메다": "안드로메다자리",
    "제단": "제단자리",
    "마차부": "마차부자리",
    "큰개": "큰개자리",
    "작은개": "작은개자리",
    "게": "게자리",
    "사냥개": "사냥개자리",
    "용골": "용골자리",
    "카시오페아": "카시오페아자리",
    "센타우루스": "센타우루스자리",
    "세페우스": "세페우스자리",
    "백조": "백조자리",
    "돌고래": "돌고래자리",
    "도라도": "도라도자리",
    "용": "용자리",
    "에리다누스": "에리다누스자리",
    "헤라클레스": "헤라클레스자리",
    "물뱀": "물뱀자리",
    "외뿔소": "외뿔소자리",
    "뱀주인": "뱀주인자리",
    "오리온": "오리온자리",
    "리라": "리라자리",
    "궁수": "궁수자리",
    "전갈": "전갈자리",
    "방패": "방패자리",
    "뱀": "뱀자리",
    "황소": "황소자리",
    "큰곰": "큰곰자리",
    "작은곰": "작은곰자리",
    "돛": "돛자리",
    "처녀": "처녀자리",
    "거문고": "거문고자리",
    "고물": "고물자리",
    "삼각": "삼각자리",
    "남쪽삼각형": "남쪽삼각형자리",
    "북쪽왕관": "북쪽왕관자리",
    "남쪽왕관": "남쪽왕관자리",
    "남십자": "남십자자리",
    "까마귀": "까마귀자리",
    "컵": "컵자리",
    "조각가": "조각가자리",
    "화살": "화살자리",
    "페가수스": "페가수스자리",
    "페르세우스": "페르세우스자리",
    "쌍둥이": "쌍둥이자리",
    "사자": "사자자리",
    "토끼": "토끼자리",
    "늑대": "늑대자리",
    "여우": "여우자리",
    "목동": "목동자리",
    "양": "양자리",
    "물병": "물병자리",
    "독수리": "독수리자리",
    "고래": "고래자리",
    "공작": "공작자리",
    "두루미": "두루미자리",
    "비둘기": "비둘기자리",
    "머리털": "머리털자리",
    "물고기": "물고기자리",
    "남쪽물고기": "남쪽물고기자리",
    "큰부리": "큰부리자리",
    "비행고": "비행고자리",
    "나침반": "나침반자리",
    "망원경": "망원경자리",
    "현미경": "현미경자리",
    "시계": "시계자리",
    "화로": "화로자리",
    "화가": "화가자리",
    "봉황": "봉황자리",
    "탁자": "탁자자리",
    "정사각형": "정사각형자리",
    "남극": "남극자리",
    "쥐": "쥐자리",
    "개미": "개미자리",
    "파리": "파리자리",
    "카멜레온": "카멜레온자리",
    "컴퍼스": "컴퍼스자리",
    "승마": "승마자리",
    "도마뱀": "도마뱀자리",
    "작은사자": "작은사자자리",
    "작은바다뱀": "작은바다뱀자리",
    "인디언": "인디언자리",
    "육분의": "육분의자리",
    "염소": "염소자리",
}

CANONICAL_VALUES = set(CANONICAL.values())
ALL_CANONICAL = CANONICAL_VALUES | set(ALIASES.values())


def normalize(name: str) -> str:
    name = name.strip()
    if not name or name == "-":
        return name
    if name in ALIASES:
        return ALIASES[name]
    if name in CANONICAL_VALUES:
        return name
    # Already ends with 자리
    if name.endswith("자리"):
        return name
    return ALIASES.get(name, name)


def main() -> None:
    seen: dict[str, set[str]] = defaultdict(set)
    changes: list[tuple[str, str, str, str]] = []

    for path in FILES:
        if not path.exists():
            continue
        data = json.load(path.open(encoding="utf-8-sig"))
        for obj in data:
            raw = (obj.get("constellation") or "").strip()
            if not raw or raw == "-":
                continue
            canon = normalize(raw)
            seen[canon].add(raw)
            if raw != canon:
                changes.append((path.name, obj.get("id", "?"), raw, canon))

    print("=== Variants per canonical name ===")
    for canon in sorted(seen):
        variants = seen[canon]
        if len(variants) > 1:
            print(f"{canon}: {sorted(variants)}")

    print(f"\n=== Total renames needed: {len(changes)} ===")
    by_pair: dict[tuple[str, str], int] = defaultdict(int)
    for _, _, raw, canon in changes:
        by_pair[(raw, canon)] += 1
    for (raw, canon), count in sorted(by_pair.items(), key=lambda x: -x[1]):
        print(f"  {raw} -> {canon} ({count})")


if __name__ == "__main__":
    main()
