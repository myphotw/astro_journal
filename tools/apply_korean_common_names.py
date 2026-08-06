#!/usr/bin/env python3
"""Apply Korean common names across catalog JSON files."""

from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
COMMON_NAMES_PATH = ROOT / "assets/catalog/common_names.json"
TARGET_FILES = [
    ROOT / "assets/catalog/messier.json",
    ROOT / "assets/catalog/seestar_catalog.json",
]

HANGUL = re.compile(r"[\uac00-\ud7a3]")

# Famous / fixed Korean common names by object id.
ID_TO_KO: dict[str, str] = {
    # Messier (well-known)
    "M2": "구상성단",
    "M3": "구상성단",
    "M4": "구상성단",
    "M5": "구상성단",
    "M9": "구상성단",
    "M10": "구상성단",
    "M12": "구상성단",
    "M14": "구상성단",
    "M15": "구상성단",
    "M18": "산개성단",
    "M19": "구상성단",
    "M21": "산개성단",
    "M22": "구상성단",
    "M23": "산개성단",
    "M25": "산개성단",
    "M26": "산개성단",
    "M28": "구상성단",
    "M29": "산개성단",
    "M30": "구상성단",
    "M32": "안드로메다 위성은하",
    "M34": "산개성단",
    "M35": "산개성단",
    "M36": "산개성단",
    "M37": "산개성단",
    "M38": "산개성단",
    "M39": "산개성단",
    "M41": "산개성단",
    "M46": "산개성단",
    "M47": "산개성단",
    "M48": "산개성단",
    "M49": "타원은하",
    "M50": "산개성단",
    "M52": "산개성단",
    "M53": "구상성단",
    "M54": "구상성단",
    "M55": "구상성단",
    "M56": "구상성단",
    "M58": "나선은하",
    "M59": "타원은하",
    "M60": "타원은하",
    "M61": "나선은하",
    "M62": "구상성단",
    "M65": "나선은하",
    "M66": "나선은하",
    "M67": "산개성단",
    "M68": "구상성단",
    "M69": "구상성단",
    "M70": "구상성단",
    "M71": "구상성단",
    "M72": "구상성단",
    "M73": "산개성단",
    "M74": "나선은하",
    "M75": "구상성단",
    "M77": "나선은하",
    "M78": "반사성운",
    "M79": "구상성단",
    "M80": "구상성단",
    "M84": "타원은하",
    "M85": "타원은하",
    "M86": "타원은하",
    "M87": "처녀자리 A",
    "M88": "나선은하",
    "M89": "타원은하",
    "M90": "나선은하",
    "M91": "나선은하",
    "M92": "구상성단",
    "M93": "산개성단",
    "M94": "나선은하",
    "M95": "나선은하",
    "M96": "나선은하",
    "M98": "나선은하",
    "M99": "바람개비 은하",
    "M100": "나선은하",
    "M103": "산개성단",
    "M105": "타원은하",
    "M106": "나선은하",
    "M107": "구상성단",
    "M108": "나선은하",
    "M109": "나선은하",
    "M110": "안드로메다 위성은하",
    # Caldwell
    "C1": "세페우스자리 산개성단",
    "C2": "거품 성운",
    "C3": "용자리 은하",
    "C4": "붓꽃 성운",
    "C5": "숨겨진 은하",
    "C6": "고양이 눈 성운",
    "C7": "기린자리 은하",
    "C8": "카시오페아자리 산개성단",
    "C10": "카시오페아자리 산개성단",
    "C16": "도마뱀자리 산개성단",
    "C17": "카시오페아자리 은하",
    "C18": "카시오페아자리 은하",
    "C19": "카시오페아자리 은하",
    "C21": "사냥개자리 은하",
    "C22": "푸른 눈덩이 성운",
    "C23": "바늘 은하",
    "C24": "페르세우스 A",
    "C25": "북미 성운",
    "C28": "안드로메다자리 은하",
    "C29": "사냥개자리 은하",
    "C35": "머리털자리 은하",
    "C36": "머리털자리 은하",
    "C40": "사자자리 은하",
    "C42": "돌고래자리 은하",
    "C43": "페가수스자리 은하",
    "C44": "페가수스자리 은하",
    "C45": "목동자리 은하",
    "C46": "허블 성운",
    "C47": "백조자리 은하",
    "C52": "처녀자리 은하",
    "C54": "처녀자리 은하",
    "C55": "토성 성운",
    "C56": "고래자리 은하",
    "C58": "고리 성운",
    "C59": "목성 유령 성운",
    "C61": "안테나 은하",
    "C62": "고래자리 은하",
    "C64": "큰개자리 은하",
    "C66": "물뱀자리 은하",
    "C67": "화로자리 은하",
    "C69": "벌 성운",
    "C70": "조각가자리 행성상성운",
    "C73": "비둘기자리 은하",
    "C74": "여덟 폭발 성운",
    "C75": "전갈자리 행성상성운",
    "C76": "전갈자리 은하",
    "C78": "고양이 눈 성운",
    "C79": "전갈자리 행성상성운",
    "C83": "센타우루스자리 은하",
    "C84": "센타우루스자리 은하",
    "C86": "제단자리 구상성단",
    "C87": "거문고자리 은하",
    "C89": "정사각형자리 은하",
    "C90": "물뱀자리 행성상성운",
    "C91": "소원 우물 성단",
    "C93": "공작자리 구상성단",
    "C94": "보석 상자 성단",
    "C95": "남쪽삼각형자리 은하",
    "C96": "물뱀자리 산개성단",
    "C97": "고래자리 산개성단",
    "C98": "안드로메다자리 은하",
    "C99": "캘리포니아 성운",
    "C100": "쥐자리 은하",
    "C101": "공작자리 은하",
    "C102": "물뱀자리 은하",
    "C103": "타란툴라 성단",
    "C104": "물뱀자리 은하",
    "C105": "쥐자리 은하",
    "C106": "47 투카나 성단",
    "C107": "파리자리 은하",
    "C108": "쥐자리 은하",
    "C109": "큰곰자리 은하",
    # NGC / IC
    "NGC55": "조각가 은하",
    "NGC147": "은하",
    "NGC2403": "은하",
    "NGC247": "은하",
    "NGC281": "북미 성운",
    "NGC2903": "은하",
    "NGC300": "조각가 은하",
    "NGC4236": "은하",
    "NGC4244": "은하",
    "NGC7331": "은하",
    "NGC891": "바늘 은하",
    "NGC1269": "발광성운",
    "NGC1316": "화로자리 A",
    "NGC1365": "은하",
    "NGC1432": "마이아 성운",
    "NGC1435": "메로페 성운",
    "NGC1491": "발광성운",
    "NGC1532": "은하",
    "NGC1750": "발광성운",
    "NGC1966": "발광성운",
    "NGC1975": "러닝맨 성운",
    "NGC1990": "알닐람 성운",
    "NGC2052": "발광성운",
    "NGC2070": "타란툴라 성운",
    "NGC2077": "발광성운",
    "NGC2175": "원숭이 머리 성운",
    "NGC2678": "발광성운",
    "NGC2736": "연필 성운",
    "NGC292": "작은 마젤란 은하",
    "NGC3109": "은하",
    "NGC3199": "와플 성운",
    "NGC3324": "발광성운",
    "NGC346": "발광성운",
    "NGC3521": "은하",
    "NGC3576": "자유의 여신상 성운",
    "NGC3621": "은하",
    "NGC4395": "은하",
    "NGC4437": "은하",
    "NGC4559": "은하",
    "NGC456": "발광성운",
    "NGC4656": "은하",
    "NGC4725": "은하",
    "NGC4945": "은하",
    "NGC5033": "은하",
    "NGC5284": "은하",
    "NGC5907": "은하",
    "NGC6729": "발광성운",
    "NGC6744": "은하",
    "NGC7640": "은하",
    "NGC925": "은하",
    "IC1284": "발광성운",
    "IC1287": "발광성운",
    "IC1613": "은하",
    "IC1795": "발광성운",
    "IC1995": "발광성운",
    "IC2574": "코딩턴 은하",
    "IC2872": "발광성운",
    "IC2944": "람다 센타우리 성운",
    "IC353": "발광성운",
    "IC360": "발광성운",
    "IC417": "발광성운",
    "IC430": "발광성운",
    "IC444": "발광성운",
    "IC447": "발광성운",
    "IC448": "발광성운",
    "IC4591": "발광성운",
    "IC4601": "발광성운",
    "IC4603": "발광성운",
    "IC4604": "로 오피우히 성운",
    "IC4605": "발광성운",
    "IC4685": "발광성운",
    "IC4701": "발광성운",
    "IC4895": "바너드 은하",
    "IC5068": "발광성운",
    "IC5070": "펠리컨 성운",
    "IC63": "발광성운",
    # Sharpless / RCW / vdB
    "Sh2-1": "발광성운",
    "Sh2-3": "Green Ring 성운",
    "Sh2-54": "Nest 성운",
    "Sh2-103": "베일 성운",
    "Sh2-108": "발광성운",
    "Sh2-140": "발광성운",
    "Sh2-142": "발광성운",
    "Sh2-158": "발광성운",
    "Sh2-235": "발광성운",
    "Sh2-273": "크리스마스 트리 성운",
    "Sh2-296": "Seagull's Wings",
    "Sh2-298": "발광성운",
    "Sh2-311": "Skull and Crossbone 성운",
    "RCW57": "발광성운",
    "RCW77": "발광성운",
    "RCW98": "발광성운",
    "RCW100": "발광성운",
    "RCW101": "발광성운",
    "RCW114": "발광성운",
    "vdB31": "반사성운",
    "vdB38": "반사성운",
    "vdB106": "반사성운",
    "vdB107": "반사성운",
    "vdB123": "반사성운",
    "vdB126": "반사성운",
    "vdB136": "반사성운",
    "vdB140": "반사성운",
    "vdB150": "반사성운",
    "vdB152": "반사성운",
}

ENGLISH_TO_KO: dict[str, str] = {
    "30 Dor Cluster": "타란툴라 성단",
    "47 Tuc Cluster": "47 투카나 성단",
    "Virgo Galaxy": "처녀자리 A",
    "Coma Pinwheel": "머리털자리 바람개비 은하",
    "Copeland's Blue Snowball": "푸른 눈덩이 성운",
    "Perseus A": "페르세우스 A",
    "Hubble's Nebula": "허블 성운",
    "Saturn Nebula": "토성 성운",
    "Ring Nebula": "고리 성운",
    "Jupiter's Ghost Nebula": "목성 유령 성운",
    "Antennae Galaxies": "안테나 은하",
    "Bug Nebula": "벌 성운",
    "Eight-Burst Nebula": "여덟 폭발 성운",
    "Cat's Eye Nebula": "고양이 눈 성운",
    "S Nor Cluster": "S 노르마 성단",
    "Wishing Well Cluster": "소원 우물 성단",
    "Herschel's Jewel Box": "보석 상자 성단",
    "California Nebula": "캘리포니아 성운",
    "Coddington's Nebula": "코딩턴 은하",
    "lam Cen Nebula": "람다 센타우리 성운",
    "rho Oph Nebula": "로 오피우히 성운",
    "Barnard's Galaxy": "바너드 은하",
    "Pelican Nebula": "펠리컨 성운",
    "Fornax A": "화로자리 A",
    "Maia Nebula": "마이아 성운",
    "Merope Nebula": "메로페 성운",
    "Alnilam": "알닐람 성운",
    "Pencil Nebula": "연필 성운",
    "Small Magellanic Cloud": "작은 마젤란 은하",
}


def has_korean(text: str) -> bool:
    return bool(HANGUL.search(text))


def resolve_korean_name(obj: dict, extra: dict[str, str]) -> str | None:
    obj_id = obj.get("id", "")
    if obj_id in ID_TO_KO:
        return ID_TO_KO[obj_id]
    if obj_id in extra and has_korean(extra[obj_id]):
        return extra[obj_id]

    common = (obj.get("commonName") or "").strip()
    if common in ENGLISH_TO_KO:
        return ENGLISH_TO_KO[common]

    name = (obj.get("name") or "").strip()
    if has_korean(name) and name not in {obj_id, obj.get("displayName")}:
        return name

    const = (obj.get("constellation") or "").strip()
    obj_type = (obj.get("objectType") or obj.get("type") or "").strip()
    if obj_type and has_korean(obj_type):
        return obj_type

    return None


def fix_description(desc: str, old_common: str, new_common: str) -> str:
    if not desc or old_common == new_common:
        return desc
    if old_common and old_common in desc:
        return desc.replace(old_common, new_common)
    return desc


def main() -> None:
    extra = json.load(COMMON_NAMES_PATH.open(encoding="utf-8-sig"))
    merged = {**extra, **ID_TO_KO}
    total = 0

    for path in TARGET_FILES:
        data = json.load(path.open(encoding="utf-8-sig"))
        changed = 0
        for obj in data:
            old_common = (obj.get("commonName") or obj.get("name") or "").strip()
            resolved = resolve_korean_name(obj, merged)
            if not resolved or not has_korean(resolved):
                continue
            if old_common == resolved:
                continue

            obj["commonName"] = resolved
            name = (obj.get("name") or "").strip()
            if not has_korean(name) or name == obj_id:
                obj["name"] = resolved

            desc = obj.get("description")
            if isinstance(desc, str):
                obj["description"] = fix_description(desc, old_common, resolved)

            merged[obj.get("id", "")] = resolved
            changed += 1
            total += 1

        if changed:
            json.dump(data, path.open("w", encoding="utf-8"), ensure_ascii=False, indent=2)
            path.open("a", encoding="utf-8").write("\n")
        print(f"{path.name}: {changed} updated")

    json.dump(
        dict(sorted(merged.items(), key=lambda x: x[0])),
        COMMON_NAMES_PATH.open("w", encoding="utf-8"),
        ensure_ascii=False,
        indent=2,
    )
    COMMON_NAMES_PATH.open("a", encoding="utf-8").write("\n")
    print(f"common_names.json: {len(merged)} entries, total updates: {total}")


def obj_id_if(obj: dict) -> str:
    return str(obj.get("id", ""))


if __name__ == "__main__":
    main()
