#!/usr/bin/env python3
"""Fetch constellation from SIMBAD for objects missing local data."""

from __future__ import annotations

import json
import re
import time
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SIMBAD_TAP = "https://simbad.cds.unistra.fr/simbad/sim-tap/sync"

IAU_TO_KO = {
    "And": "안드로메다", "Ant": "개미자리", "Aps": "파리자리", "Aql": "독수리자리",
    "Aqr": "물병자리", "Ara": "제단", "Ari": "양자리", "Aur": "마차부",
    "Boo": "목동자리", "CMa": "큰개", "CMi": "작은개", "Cnc": "게",
    "CVn": "사냥개", "Cap": "염소자리", "Car": "용골", "Cas": "카시오페아",
    "Cen": "센타우루스", "Cep": "세페우스", "Cet": "고래자리", "Cha": "카멜레온자리",
    "Cir": "컴퍼스자리", "Col": "비둘기자리", "Com": "머리털자리", "CrA": "남쪽왕관",
    "CrB": "북쪽왕관", "Crt": "컵자리", "Cru": "남십자자리", "Crv": "까마귀",
    "Cyg": "백조", "Del": "돌고래자리", "Dor": "도라도", "Dra": "용",
    "Equ": "승마자리", "Eri": "에리다누스", "For": "화로자리", "Gem": "쌍둥이자리",
    "Gru": "두루미자리", "Her": "헤라클레스", "Hor": "시계자리", "Hya": "물뱀",
    "Hyi": "작은바다뱀", "Ind": "인디언자리", "Lac": "도마뱀", "Leo": "사자",
    "LMi": "작은사자", "Lep": "토끼자리", "Lib": "처녀자리", "Lup": "늑대자리",
    "Lyn": "여우자리", "Lyr": "리라", "Men": "탁자자리", "Mic": "현미경자리",
    "Mon": "외뿔소", "Mus": "쥐자리", "Nor": "정사각형자리", "Oct": "남극자리",
    "Oph": "뱀주인", "Ori": "오리온", "Pav": "공작자리", "Peg": "페가수스",
    "Per": "페르세우스", "Phe": "봉황자리", "Pic": "화가자리", "PsA": "남쪽물고기자리",
    "Psc": "물고기자리", "Pup": "고물", "Pyx": "나침반자리", "Ret": "망원경자리",
    "Sge": "화살자리", "Sgr": "궁수", "Sco": "전갈", "Scl": "조각가",
    "Sct": "방패", "Ser": "뱀", "Sex": "육분의자리", "Tau": "황소",
    "Tel": "망원경자리", "Tri": "삼각자리", "TrA": "남쪽삼각형자리", "Tuc": "큰부리자리",
    "UMa": "큰곰", "UMi": "작은곰", "Vel": "돛자리", "Vir": "처녀자리",
    "Vol": "비행고자리", "Vul": "거문고",
}


def format_simbad_id(name: str) -> str:
    match = re.fullmatch(r"NGC\s*(\d+)", name, re.IGNORECASE)
    if match:
        return f"NGC {int(match.group(1)):>7}"
    match = re.fullmatch(r"IC\s*(\d+)", name, re.IGNORECASE)
    if match:
        return f"IC {int(match.group(1)):>6}"
    match = re.fullmatch(r"SH\s*2[-\s]?(\d+)", name, re.IGNORECASE)
    if match:
        return f"SH  2-{int(match.group(1))}"
    match = re.fullmatch(r"RCW\s*(\d+)", name, re.IGNORECASE)
    if match:
        return f"RCW {int(match.group(1))}"
    match = re.fullmatch(r"vdB\s*(\d+)", name, re.IGNORECASE)
    if match:
        return f"vdB {int(match.group(1))}"
    return name


def simbad_names_for(obj: dict) -> list[str]:
    catalog = obj.get("catalog", "")
    number = obj.get("number")
    names: list[str] = []
    if catalog == "sh2" and number is not None:
        names.append(f"Sh2-{number}")
    elif catalog == "rcw" and number is not None:
        names.append(f"RCW {number}")
    elif catalog == "vdb" and number is not None:
        names.append(f"vdB {number}")
    display = obj.get("displayName") or obj.get("id", "")
    if display not in names:
        names.append(display)
    return names


def query_constellation(names: list[str]) -> str | None:
    for name in names:
        simbad_name = format_simbad_id(name)
        query = (
            "SELECT TOP 1 mesconstellation.constell "
            "FROM ident JOIN mesconstellation ON ident.oidref = mesconstellation.oidref "
            f"WHERE ident.id = '{simbad_name.replace(chr(39), chr(39)+chr(39))}'"
        )
        params = urllib.parse.urlencode(
            {"request": "doQuery", "lang": "adql", "format": "json", "query": query}
        )
        url = f"{SIMBAD_TAP}?{params}"
        request = urllib.request.Request(url, headers={"User-Agent": "astro-journal-enrich/1.0"})
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                payload = json.load(response)
        except Exception as error:  # noqa: BLE001
            print(f"SIMBAD error for {simbad_name}: {error}")
            continue
        rows = payload.get("data", [])
        if not rows or not rows[0][0]:
            continue
        iau = rows[0][0].strip()
        return IAU_TO_KO.get(iau, iau)
    return None


def main() -> None:
    path = ROOT / "assets/catalog/seestar_catalog.json"
    objects = json.load(path.open(encoding="utf-8-sig"))
    updated = 0
    for obj in objects:
        const = obj.get("constellation", "-")
        if const and const.strip() not in {"", "-"}:
            continue
        catalog = obj.get("catalog", "")
        if catalog not in ("rcw", "vdb", "sh2"):
            continue
        names = simbad_names_for(obj)
        result = query_constellation(names)
        print(f"{obj['id']}: {result} (from {names[0]})")
        if result:
            obj["constellation"] = result
            obj_type = obj.get("objectType") or obj.get("type") or "천체"
            name = obj.get("commonName") or obj.get("name") or ""
            if name and name not in {obj.get("displayName"), obj.get("id")}:
                obj["description"] = f"{result}에 위치한 {obj_type}. {name}."
            else:
                obj["description"] = f"{result}에 위치한 {obj_type}."
            updated += 1
        time.sleep(0.15)
    json.dump(objects, path.open("w", encoding="utf-8"), ensure_ascii=False, indent=2)
    path.open("a", encoding="utf-8").write("\n")
    print(f"updated {updated} objects")


if __name__ == "__main__":
    main()
