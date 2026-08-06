#!/usr/bin/env python3
"""Fast catalog metadata enrichment using local references and OpenNGC."""

from __future__ import annotations

import csv
import json
import math
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OPENNGC_PATH = ROOT / "tools/openngc/NGC.csv"
REFERENCE_FILES = [
    ROOT / "assets/catalog/messier.json",
    ROOT / "assets/catalog/ngc.json",
    ROOT / "assets/catalog/ic.json",
    ROOT / "assets/catalog/caldwell.json",
    ROOT / "assets/catalog/sh2.json",
]
TARGET_FILES = [
    ROOT / "assets/catalog/messier.json",
    ROOT / "assets/catalog/seestar_catalog.json",
    ROOT / "assets/catalog/solar.json",
    ROOT / "assets/catalog/milkyway.json",
]
COMMON_NAMES_PATH = ROOT / "assets/catalog/common_names.json"
SEARCH_ALIASES_PATH = ROOT / "assets/catalog/search_aliases.json"
ID_REMAP_PATH = ROOT / "assets/catalog/id_remap.json"

OPTIMAL_RA_BY_MONTH = [7, 9, 11, 13, 15, 17, 19, 21, 23, 1, 3, 5]
MONTH_LABELS = [
    "1월", "2월", "3월", "4월", "5월", "6월",
    "7월", "8월", "9월", "10월", "11월", "12월",
]
SEASON_BY_MONTH = {
    3: ("봄", "3~5월"), 4: ("봄", "3~5월"), 5: ("봄", "3~5월"),
    6: ("여름", "6~8월"), 7: ("여름", "6~8월"), 8: ("여름", "6~8월"),
    9: ("가을", "9~11월"), 10: ("가을", "9~11월"), 11: ("가을", "9~11월"),
    12: ("겨울", "12~2월"), 1: ("겨울", "12~2월"), 2: ("겨울", "12~2월"),
}

IAU_TO_KO = {
    "And": "안드로메다자리", "Ant": "개미자리", "Aps": "파리자리", "Aql": "독수리자리",
    "Aqr": "물병자리", "Ara": "제단자리", "Ari": "양자리", "Aur": "마차부자리",
    "Boo": "목동자리", "CMa": "큰개자리", "CMi": "작은개자리", "Cnc": "게자리",
    "CVn": "사냥개자리", "Cap": "염소자리", "Car": "용골자리", "Cas": "카시오페아자리",
    "Cen": "센타우루스자리", "Cep": "세페우스자리", "Cet": "고래자리", "Cha": "카멜레온자리",
    "Cir": "컴퍼스자리", "Col": "비둘기자리", "Com": "머리털자리", "CrA": "남쪽왕관자리",
    "CrB": "북쪽왕관자리", "Crt": "컵자리", "Cru": "남십자자리", "Crv": "까마귀자리",
    "Cyg": "백조자리", "Del": "돌고래자리", "Dor": "도라도자리", "Dra": "용자리",
    "Equ": "승마자리", "Eri": "에리다누스자리", "For": "화로자리", "Gem": "쌍둥이자리",
    "Gru": "두루미자리", "Her": "헤라클레스자리", "Hor": "시계자리", "Hya": "물뱀자리",
    "Hyi": "작은바다뱀자리", "Ind": "인디언자리", "Lac": "도마뱀자리", "Leo": "사자자리",
    "LMi": "작은사자자리", "Lep": "토끼자리", "Lib": "처녀자리", "Lup": "늑대자리",
    "Lyn": "여우자리", "Lyr": "리라자리", "Men": "탁자자리", "Mic": "현미경자리",
    "Mon": "외뿔소자리", "Mus": "쥐자리", "Nor": "정사각형자리", "Oct": "남극자리",
    "Oph": "뱀주인자리", "Ori": "오리온자리", "Pav": "공작자리", "Peg": "페가수스자리",
    "Per": "페르세우스자리", "Phe": "봉황자리", "Pic": "화가자리", "PsA": "남쪽물고기자리",
    "Psc": "물고기자리", "Pup": "고물자리", "Pyx": "나침반자리", "Ret": "망원경자리",
    "Sge": "화살자리", "Sgr": "궁수자리", "Sco": "전갈자리", "Scl": "조각가자리",
    "Sct": "방패자리", "Ser": "뱀자리", "Sex": "육분의자리", "Tau": "황소자리",
    "Tel": "망원경자리", "Tri": "삼각자리", "TrA": "남쪽삼각형자리", "Tuc": "큰부리자리",
    "UMa": "큰곰자리", "UMi": "작은곰자리", "Vel": "돛자리", "Vir": "처녀자리",
    "Vol": "비행고자리", "Vul": "거문고자리",
}

CALDWELL_NGC = {
    1: 188, 2: 7635, 3: 4236, 4: 7023, 5: 342, 6: 6543, 7: 2403, 8: 559, 9: 6293,
    10: 663, 11: 7635, 12: 6946, 13: 457, 14: 869, 15: 6826, 16: 7243, 17: 147,
    18: 185, 19: 278, 20: 7000, 21: 4449, 22: 7662, 23: 891, 24: 1275, 25: 281,
    26: 4244, 27: 6888, 28: 752, 29: 5005, 30: 7331, 31: 1805, 32: 4631, 33: 6992,
    34: 1848, 35: 4889, 36: 4559, 37: 253, 38: 4565, 39: 2392, 40: 3626, 41: 3242,
    42: 7006, 43: 7814, 44: 7479, 45: 5248, 46: 2261, 47: 6811, 48: 2775, 49: 2237,
    50: 2244, 51: 2392, 52: 4697, 53: 253, 54: 5595, 55: 7009, 56: 246, 57: 7293,
    58: 6720, 59: 3242, 60: 4038, 61: 4038, 62: 247, 63: 7293, 64: 2362, 65: 253,
    66: 5694, 67: 1097, 68: 6729, 69: 6302, 70: 300, 71: 247, 72: 1435, 73: 1851,
    74: 3132, 75: 6124, 76: 6231, 77: 5128, 78: 6543, 79: 6231, 80: 5139, 81: 3621,
    82: 4631, 83: 4945, 84: 5286, 85: 3521, 86: 6397, 87: 6885, 88: 5823, 89: 6087,
    90: 2865, 91: 3532, 92: 3372, 93: 6752, 94: 4755, 95: 6025, 96: 3621, 97: 246,
    98: 205, 99: 1499, 100: 4372, 101: 6744, 102: 3621, 103: 2070, 104: 3621,
    105: 4833, 106: 104, 107: 6101, 108: 4372, 109: 3198,
}

# OpenNGC·로컬 카탈로그에 없는 RCW/vdB/Sh2 별자리·별칭 (SIMBAD·좌표 기준).
MANUAL_METADATA: dict[str, dict] = {
    "RCW57": {"constellation": "용골자리", "aliases": ["RCW 57"]},
    "RCW77": {"constellation": "용골자리", "aliases": ["RCW 77"]},
    "RCW98": {"constellation": "센타우루스자리", "aliases": ["RCW 98"]},
    "RCW100": {"constellation": "센타우루스자리", "aliases": ["RCW 100"]},
    "RCW101": {"constellation": "센타우루스자리", "aliases": ["RCW 101"]},
    "RCW114": {"constellation": "전갈자리", "aliases": ["RCW 114"]},
    "Sh2-1": {"constellation": "전갈자리"},
    "Sh2-3": {"constellation": "전갈자리"},
    "Sh2-103": {"constellation": "백조자리"},
    "Sh2-108": {"constellation": "백조자리"},
    "Sh2-140": {"constellation": "세페우스자리"},
    "Sh2-142": {"constellation": "세페우스자리"},
    "Sh2-158": {"constellation": "카시오페아자리"},
    "Sh2-235": {"constellation": "황소자리"},
    "Sh2-273": {"constellation": "외뿔소자리"},
    "Sh2-296": {"constellation": "큰개자리"},
    "Sh2-298": {"constellation": "고물자리"},
    "Sh2-311": {"constellation": "큰개자리"},
    "vdB31": {"constellation": "황소자리", "aliases": ["vdB 31"]},
    "vdB38": {"constellation": "오리온자리", "aliases": ["vdB 38"]},
    "vdB106": {"constellation": "전갈자리", "aliases": ["vdB 106"]},
    "vdB107": {"constellation": "전갈자리", "aliases": ["vdB 107"]},
    "vdB123": {"constellation": "뱀자리", "aliases": ["vdB 123"]},
    "vdB126": {"constellation": "거문고자리", "aliases": ["vdB 126"]},
    "vdB136": {"constellation": "백조자리", "aliases": ["vdB 136"]},
    "vdB140": {"constellation": "세페우스자리", "aliases": ["vdB 140"]},
    "vdB150": {"constellation": "세페우스자리", "aliases": ["vdB 150"]},
    "vdB152": {"constellation": "세페우스자리", "aliases": ["vdB 152"]},
    "NGC1975": {"commonName": "러닝맨 성운", "aliases": ["Running Man Nebula", "Running Man", "NGC 1975"]},
    "NGC3199": {"commonName": "와플 성운", "aliases": ["Waffle Nebula", "NGC 3199"]},
    "NGC3576": {"commonName": "자유의 여신상 성운", "aliases": ["NGC 3576", "Statue of Liberty Nebula", "Statue of Liberty"]},
    "IC1284": {"aliases": ["IC 1284"]},
    "IC1995": {"aliases": ["IC 1995"]},
    "IC2872": {"aliases": ["IC 2872"]},
    "IC353": {"aliases": ["IC 353"]},
    "IC430": {"aliases": ["IC 430"]},
    "IC447": {"aliases": ["IC 447"]},
    "IC4601": {"aliases": ["IC 4601"]},
    "IC4685": {"aliases": ["IC 4685"]},
    "NGC1269": {"aliases": ["NGC 1269"]},
    "NGC1750": {"aliases": ["NGC 1750"]},
    "NGC2678": {"aliases": ["NGC 2678"]},
    "M73": {"aliases": ["NGC 6994", "NGC6994"]},
}


def is_missing(value: str | None) -> bool:
    if value is None:
        return True
    return value.strip() in {"", "-"}


def normalize_key(value: str) -> str:
    return re.sub(r"[^a-z0-9]", "", value.lower())


def load_json(path: Path):
    with path.open(encoding="utf-8-sig") as handle:
        return json.load(handle)


def save_json(path: Path, data) -> None:
    with path.open("w", encoding="utf-8") as handle:
        json.dump(data, handle, ensure_ascii=False, indent=2)
        handle.write("\n")


def split_csv_list(value: str) -> list[str]:
    if not value or not value.strip():
        return []
    return [part.strip() for part in value.split(",") if part.strip()]


def parse_openngc_row(row: dict) -> dict:
    const = row.get("Const", "").strip()
    vmag = row.get("V-Mag", "").strip()
    bmag = row.get("B-Mag", "").strip()
    magnitude = vmag or bmag
    maj = row.get("MajAx", "").strip()
    min_ax = row.get("MinAx", "").strip()
    angular_size = None
    if maj and min_ax:
        angular_size = f"{maj}' × {min_ax}'"
    elif maj:
        angular_size = f"{maj}'"

    common_names = split_csv_list(row.get("Common names", ""))
    identifiers = split_csv_list(row.get("Identifiers", ""))
    return {
        "constellation": IAU_TO_KO.get(const, const) if const else None,
        "magnitude": magnitude if magnitude else None,
        "angularSize": angular_size,
        "aliases": common_names + identifiers,
        "commonName": common_names[0] if common_names else None,
    }


def load_openngc() -> tuple[dict[int, dict], dict[int, dict], dict[int, dict]]:
    ngc: dict[int, dict] = {}
    ic: dict[int, dict] = {}
    messier: dict[int, dict] = {}

    with OPENNGC_PATH.open(encoding="utf-8") as handle:
        reader = csv.DictReader(handle, delimiter=";")
        for row in reader:
            parsed = parse_openngc_row(row)
            name = row.get("Name", "").strip()
            ngc_match = re.fullmatch(r"NGC(\d+)", name, re.IGNORECASE)
            ic_match = re.fullmatch(r"IC(\d+)", name, re.IGNORECASE)
            if ngc_match:
                ngc[int(ngc_match.group(1))] = parsed
            if ic_match:
                ic[int(ic_match.group(1))] = parsed
            if row.get("NGC", "").strip().isdigit():
                ngc[int(row["NGC"])] = parsed
            if row.get("IC", "").strip().isdigit():
                ic[int(row["IC"])] = parsed
            if row.get("M", "").strip().isdigit():
                messier[int(row["M"])] = parsed

    return ngc, ic, messier


def parse_ra_hours(ra: str) -> float:
    match = re.search(r"(\d+)h(?:\s*(\d+(?:\.\d+)?)m)?", ra, re.IGNORECASE)
    if not match:
        return float("nan")
    return float(match.group(1)) + float(match.group(2) or 0) / 60.0


def ra_distance(ra1: float, ra2: float) -> float:
    diff = abs(ra1 - ra2)
    return 24 - diff if diff > 12 else diff


def compute_season_fields(obj: dict) -> tuple[int, str] | None:
    if obj.get("catalog") in ("solar", "milky"):
        return None
    ra = obj.get("ra", "")
    if is_missing(ra):
        return None
    ra_hours = parse_ra_hours(ra)
    if math.isnan(ra_hours):
        return None
    best_month = 1
    best_score = -1.0
    for month in range(1, 13):
        optimal = OPTIMAL_RA_BY_MONTH[month - 1]
        score = max(0.0, 1 - ra_distance(optimal, ra_hours) / 12.0)
        if score > best_score:
            best_score = score
            best_month = month
    season_label, season_subtitle = SEASON_BY_MONTH[best_month]
    return best_month, f"최적 {MONTH_LABELS[best_month - 1]} · {season_label} ({season_subtitle})"


def build_reference_lookup() -> dict[str, dict]:
    lookup: dict[str, dict] = {}
    for path in REFERENCE_FILES:
        if not path.exists():
            continue
        for entry in load_json(path):
            keys = {
                normalize_key(entry.get("id", "")),
                normalize_key(entry.get("name", "")),
                normalize_key(f"{entry.get('catalog', '')}{entry.get('number', '')}"),
            }
            catalog = entry.get("catalog")
            number = entry.get("number")
            if catalog == "sh2" and number is not None:
                keys.add(normalize_key(f"sh2-{number}"))
                keys.add(normalize_key(f"sh2{number}"))
            for key in keys:
                if key:
                    lookup[key] = entry
    return lookup


def lookup_reference(obj: dict, lookup: dict[str, dict]) -> dict | None:
    candidates = [obj.get("id", ""), f"{obj.get('catalog', '')}{obj.get('number', '')}"]
    catalog = obj.get("catalog")
    number = obj.get("number")
    if catalog == "caldwell" and number in CALDWELL_NGC:
        candidates.append(f"NGC{CALDWELL_NGC[number]}")
    if catalog == "ic":
        match = re.match(r"(IC\d+)", str(obj.get("id", "")), re.IGNORECASE)
        if match:
            candidates.append(match.group(1))
    for candidate in candidates:
        hit = lookup.get(normalize_key(str(candidate)))
        if hit:
            return hit
    return None


def lookup_openngc(obj: dict, ngc_db, ic_db, messier_db) -> dict | None:
    catalog = obj.get("catalog", "messier")
    number = obj.get("number")
    if number is None:
        return None
    if catalog == "messier":
        return messier_db.get(number)
    if catalog == "ngc":
        return ngc_db.get(number)
    if catalog == "ic":
        parent = ic_db.get(number)
        if parent:
            return parent
        match = re.match(r"(IC\d+)", str(obj.get("id", "")), re.IGNORECASE)
        if match:
            return ic_db.get(int(match.group(1)[2:]))
        return None
    if catalog == "caldwell" and number in CALDWELL_NGC:
        return ngc_db.get(CALDWELL_NGC[number])
    return None


def derive_description(obj: dict) -> str | None:
    obj_type = obj.get("objectType") or obj.get("type") or ""
    name = obj.get("commonName") or obj.get("name") or ""
    constellation = obj.get("constellation", "-")
    display_id = obj.get("displayName") or obj.get("id", "")

    if not is_missing(constellation):
        if name and name not in {display_id, "-"}:
            return f"{constellation}에 위치한 {obj_type}. {name}."
        return f"{constellation}에 위치한 {obj_type}."
    if name and name not in {display_id, "-"}:
        return f"{obj_type} · {name}."
    if obj_type and not is_missing(obj_type):
        return f"{obj_type}."
    return None


def unique_aliases(values: list[str]) -> list[str]:
    seen: set[str] = set()
    result: list[str] = []
    for value in values:
        trimmed = value.strip()
        if not trimmed or trimmed in seen:
            continue
        seen.add(trimmed)
        result.append(trimmed)
    return result


def catalog_id_aliases(obj: dict) -> list[str]:
    """카탈로그 ID의 흔한 표기 변형(공백·하이픈)을 별칭으로 생성."""
    aliases: list[str] = []
    obj_id = obj.get("id", "")
    display = (obj.get("displayName") or "").strip()
    if display and display != obj_id:
        aliases.append(display)

    match = re.fullmatch(r"(NGC|IC)(\d+)([A-Z]?)", obj_id, re.IGNORECASE)
    if match:
        prefix, number, suffix = match.group(1).upper(), int(match.group(2)), match.group(3)
        spaced = f"{prefix} {number}{suffix}"
        aliases.extend([spaced, f"{prefix}{number}{suffix}"])

    catalog = obj.get("catalog", "")
    number = obj.get("number")
    if catalog == "caldwell" and number is not None:
        aliases.extend([f"C{number}", f"Caldwell {number}", f"Cal {number}"])
    elif catalog == "sh2" and number is not None:
        aliases.extend([f"Sh2-{number}", f"Sh2 {number}", f"SH2-{number}", f"SH2{number}"])
    elif catalog == "rcw" and number is not None:
        aliases.append(f"RCW {number}")
    elif catalog == "vdb" and number is not None:
        aliases.extend([f"vdB {number}", f"VDB{number}"])

    return aliases


def apply_source(obj: dict, source: dict, *, include_common: bool = True) -> bool:
    changed = False
    if is_missing(obj.get("constellation")) and source.get("constellation"):
        obj["constellation"] = source["constellation"]
        changed = True
    if is_missing(obj.get("magnitude")) and source.get("magnitude"):
        obj["magnitude"] = source["magnitude"]
        changed = True
    if is_missing(obj.get("angularSize")) and source.get("angularSize"):
        obj["angularSize"] = source["angularSize"]
        changed = True
    if include_common and source.get("commonName"):
        cn = source["commonName"]
        if obj.get("commonName") in (None, "", obj.get("id"), obj.get("displayName")):
            obj["commonName"] = cn
            if is_missing(obj.get("name")) or obj.get("name") == obj.get("id"):
                obj["name"] = cn
            changed = True
    if source.get("aliases"):
        merged = unique_aliases([*(obj.get("aliases") or []), *source["aliases"]])
        if merged != (obj.get("aliases") or []):
            obj["aliases"] = merged
            changed = True
    return changed


def enrich_object(
    obj: dict,
    *,
    reference_lookup: dict[str, dict],
    ngc_db, ic_db, messier_db,
    common_names: dict[str, str],
    search_aliases: dict[str, list[str]],
    reverse_remap: dict[str, list[str]],
) -> bool:
    changed = False
    obj_id = obj.get("id", "")

    for source in (
        MANUAL_METADATA.get(obj_id),
        lookup_reference(obj, reference_lookup),
        lookup_openngc(obj, ngc_db, ic_db, messier_db),
    ):
        if source and apply_source(obj, source):
            changed = True

    if obj_id in common_names:
        cn = common_names[obj_id].strip()
        if cn and obj.get("commonName") != cn:
            obj["commonName"] = cn
            obj["name"] = cn
            changed = True

    aliases = list(obj.get("aliases") or [])
    aliases.extend(catalog_id_aliases(obj))
    aliases.extend(search_aliases.get(obj_id, []))
    aliases.extend(reverse_remap.get(obj_id, []))
    display = obj.get("displayName")
    if display and display not in {obj_id, obj.get("commonName")}:
        aliases.append(display)
    new_aliases = unique_aliases(aliases)
    if new_aliases != (obj.get("aliases") or []):
        obj["aliases"] = new_aliases
        changed = True

    season = compute_season_fields(obj)
    if season:
        peak_month, label = season
        if obj.get("peakMonth") != peak_month:
            obj["peakMonth"] = peak_month
            changed = True
        if obj.get("bestSeason") != label:
            obj["bestSeason"] = label
            changed = True

    description = derive_description(obj)
    if description and obj.get("description") != description:
        obj["description"] = description
        changed = True

    return changed


def build_reverse_remap(id_remap: dict[str, str]) -> dict[str, list[str]]:
    reverse: dict[str, list[str]] = {}
    for source, target in id_remap.items():
        reverse.setdefault(target, []).append(source)
        if source.startswith("C") and source[1:].isdigit():
            reverse[target].append(f"Caldwell {source[1:]}")
    return reverse


def audit(objects: list[dict]) -> dict[str, int]:
    counts = {k: 0 for k in ("constellation", "magnitude", "aliases", "commonName", "bestSeason", "description", "angularSize")}
    for obj in objects:
        if is_missing(obj.get("constellation")):
            counts["constellation"] += 1
        if is_missing(obj.get("magnitude")):
            counts["magnitude"] += 1
        if not obj.get("aliases"):
            counts["aliases"] += 1
        common = (obj.get("commonName") or obj.get("name") or "").strip()
        if common in {"", obj.get("id", ""), obj.get("displayName", "")}:
            counts["commonName"] += 1
        if is_missing(obj.get("bestSeason")):
            counts["bestSeason"] += 1
        if is_missing(obj.get("description")):
            counts["description"] += 1
        if is_missing(obj.get("angularSize")):
            counts["angularSize"] += 1
    return counts


def main() -> None:
    ngc_db, ic_db, messier_db = load_openngc()
    reference_lookup = build_reference_lookup()
    common_names = load_json(COMMON_NAMES_PATH)
    search_aliases = load_json(SEARCH_ALIASES_PATH)
    reverse_remap = build_reverse_remap(load_json(ID_REMAP_PATH))

    all_before: list[dict] = []
    for path in TARGET_FILES:
        all_before.extend(load_json(path))
    print("before:", audit(all_before))

    total_changed = 0
    for path in TARGET_FILES:
        objects = load_json(path)
        changed_count = 0
        for obj in objects:
            if enrich_object(
                obj,
                reference_lookup=reference_lookup,
                ngc_db=ngc_db,
                ic_db=ic_db,
                messier_db=messier_db,
                common_names=common_names,
                search_aliases=search_aliases,
                reverse_remap=reverse_remap,
            ):
                changed_count += 1
                reference_lookup[normalize_key(obj.get("id", ""))] = obj
        save_json(path, objects)
        total_changed += changed_count
        print(f"updated {changed_count} in {path.name}")

    all_after: list[dict] = []
    for path in TARGET_FILES:
        all_after.extend(load_json(path))
    print("after:", audit(all_after))
    print("total changed:", total_changed)


if __name__ == "__main__":
    main()
