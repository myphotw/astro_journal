#!/usr/bin/env python3
"""Normalize constellation names to canonical Korean IAU forms (XXX자리)."""

from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

TARGET_FILES = [
    ROOT / "assets/catalog/messier.json",
    ROOT / "assets/catalog/seestar_catalog.json",
    ROOT / "assets/catalog/ngc.json",
    ROOT / "assets/catalog/ic.json",
    ROOT / "assets/catalog/caldwell.json",
    ROOT / "assets/catalog/sh2.json",
]

# Short / legacy → canonical (official Korean IAU style with 자리 suffix).
ALIASES: dict[str, str] = {
    "안드로메다": "안드로메다자리",
    "개미": "개미자리",
    "파리": "파리자리",
    "독수리": "독수리자리",
    "물병": "물병자리",
    "제단": "제단자리",
    "양": "양자리",
    "마차부": "마차부자리",
    "목동": "목동자리",
    "큰개": "큰개자리",
    "작은개": "작은개자리",
    "게": "게자리",
    "사냥개": "사냥개자리",
    "염소": "염소자리",
    "용골": "용골자리",
    "카시오페아": "카시오페아자리",
    "센타우루스": "센타우루스자리",
    "세페우스": "세페우스자리",
    "고래": "고래자리",
    "카멜레온": "카멜레온자리",
    "컴퍼스": "컴퍼스자리",
    "비둘기": "비둘기자리",
    "머리털": "머리털자리",
    "남쪽왕관": "남쪽왕관자리",
    "북쪽왕관": "북쪽왕관자리",
    "컵": "컵자리",
    "남십자": "남십자자리",
    "까마귀": "까마귀자리",
    "백조": "백조자리",
    "돌고래": "돌고래자리",
    "도라도": "도라도자리",
    "용": "용자리",
    "승마": "승마자리",
    "에리다누스": "에리다누스자리",
    "화로": "화로자리",
    "쌍둥이": "쌍둥이자리",
    "두루미": "두루미자리",
    "헤라클레스": "헤라클레스자리",
    "시계": "시계자리",
    "물뱀": "물뱀자리",
    "작은바다뱀": "작은바다뱀자리",
    "인디언": "인디언자리",
    "도마뱀": "도마뱀자리",
    "사자": "사자자리",
    "작은사자": "작은사자자리",
    "토끼": "토끼자리",
    "처녀": "처녀자리",
    "늑대": "늑대자리",
    "여우": "여우자리",
    "리라": "리라자리",
    "탁자": "탁자자리",
    "현미경": "현미경자리",
    "외뿔소": "외뿔소자리",
    "쥐": "쥐자리",
    "정사각형": "정사각형자리",
    "남극": "남극자리",
    "뱀주인": "뱀주인자리",
    "오리온": "오리온자리",
    "공작": "공작자리",
    "페가수스": "페가수스자리",
    "페르세우스": "페르세우스자리",
    "봉황": "봉황자리",
    "화가": "화가자리",
    "남쪽물고기": "남쪽물고기자리",
    "물고기": "물고기자리",
    "고물": "고물자리",
    "나침반": "나침반자리",
    "망원경": "망원경자리",
    "화살": "화살자리",
    "궁수": "궁수자리",
    "전갈": "전갈자리",
    "조각가": "조각가자리",
    "방패": "방패자리",
    "뱀": "뱀자리",
    "육분의": "육분의자리",
    "황소": "황소자리",
    "삼각": "삼각자리",
    "남쪽삼각형": "남쪽삼각형자리",
    "큰부리": "큰부리자리",
    "큰곰": "큰곰자리",
    "작은곰": "작은곰자리",
    "돛": "돛자리",
    "거문고": "거문고자리",
    "비행고": "비행고자리",
    "기린": "기린자리",
}

CANONICAL = set(ALIASES.values())


def normalize(name: str) -> str:
    name = name.strip()
    if not name or name == "-":
        return name
    if name in ALIASES:
        return ALIASES[name]
    if name in CANONICAL:
        return name
    if name.endswith("자리"):
        return name
    return ALIASES.get(name, name)


def fix_description(text: str) -> str:
    if not text:
        return text
    # Longer names first to avoid partial replacement.
    for old in sorted(ALIASES.keys(), key=len, reverse=True):
        new = ALIASES[old]
        text = text.replace(f"{old}에 위치한", f"{new}에 위치한")
    return text


def main() -> None:
    total = 0
    for path in TARGET_FILES:
        if not path.exists():
            continue
        data = json.load(path.open(encoding="utf-8-sig"))
        changed = 0
        for obj in data:
            raw = (obj.get("constellation") or "").strip()
            if not raw or raw == "-":
                continue
            canon = normalize(raw)
            if canon != raw:
                obj["constellation"] = canon
                changed += 1
            desc = obj.get("description")
            if isinstance(desc, str):
                fixed = fix_description(desc)
                if fixed != desc:
                    obj["description"] = fixed
                    changed += 1
            best = obj.get("bestSeason")
            if isinstance(best, str):
                fixed = fix_description(best)
                if fixed != best:
                    obj["bestSeason"] = fixed
                    changed += 1
        if changed:
            json.dump(data, path.open("w", encoding="utf-8"), ensure_ascii=False, indent=2)
            path.open("a", encoding="utf-8").write("\n")
        print(f"{path.name}: {changed} field updates")
        total += changed
    print(f"total: {total}")


if __name__ == "__main__":
    main()
