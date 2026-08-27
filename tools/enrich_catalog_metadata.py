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

from catalog_identity import CALDWELL_PRIMARY as CALDWELL_NGC, IAU_TO_KO
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
    object_type = {
        "G": "은하",
        "GPair": "은하",
        "GTrpl": "은하",
        "GGroup": "은하군",
        "PN": "행성상성운",
        "OCl": "산개성단",
        "GCl": "구상성단",
        "HII": "발광성운",
        "EmN": "발광성운",
        "RfN": "반사성운",
        "SNR": "초신성잔해",
        "Cl+N": "성단과 성운",
    }.get(row.get("Type", "").strip())
    return {
        "sourceId": row.get("Name", "").strip(),
        "objectType": object_type,
        "constellation": IAU_TO_KO.get(const, const) if const else None,
        "ra": row.get("RA", "").strip() or None,
        "dec": row.get("Dec", "").strip() or None,
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
        candidates.append(CALDWELL_NGC[number])
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
    # A missing catalog must never imply Messier. The old fallback correlated
    # solar_1..solar_10 with M1..M10 by number and polluted every moving target
    # with unrelated DSO metadata (for example Uranus with M8/Lagoon Nebula).
    catalog = obj.get("catalog")
    if catalog not in {"messier", "ngc", "ic", "caldwell"}:
        return None
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
        target = CALDWELL_NGC[number]
        match = re.fullmatch(r"NGC(\d+)", target)
        if match:
            return ngc_db.get(int(match.group(1)))
        match = re.fullmatch(r"IC(\d+)", target)
        if match:
            return ic_db.get(int(match.group(1)))
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


def apply_source(
    obj: dict,
    source: dict,
    *,
    include_common: bool = True,
    replace_catalog_owned: bool = False,
) -> bool:
    changed = False
    if (replace_catalog_owned or is_missing(obj.get("constellation"))) and source.get("constellation"):
        obj["constellation"] = source["constellation"]
        changed = True
    if (replace_catalog_owned or is_missing(obj.get("magnitude"))) and source.get("magnitude"):
        obj["magnitude"] = source["magnitude"]
        changed = True
    if (replace_catalog_owned or is_missing(obj.get("angularSize"))) and source.get("angularSize"):
        obj["angularSize"] = source["angularSize"]
        changed = True
    if replace_catalog_owned and source.get("objectType"):
        obj["objectType"] = source["objectType"]
        obj["type"] = source["objectType"]
        changed = True
    if include_common and source.get("commonName"):
        cn = source["commonName"]
        if obj.get("commonName") in (None, "", obj.get("id"), obj.get("displayName")):
            obj["commonName"] = cn
            if is_missing(obj.get("name")) or obj.get("name") == obj.get("id"):
                obj["name"] = cn
            changed = True
    if source.get("aliases"):
        existing = [] if replace_catalog_owned else list(obj.get("aliases") or [])
        merged = unique_aliases([*existing, *source["aliases"]])
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

    openngc_source = lookup_openngc(obj, ngc_db, ic_db, messier_db)
    for source, replace_catalog_owned in (
        (openngc_source, True),
        (lookup_reference(obj, reference_lookup), False),
        (MANUAL_METADATA.get(obj_id), False),
    ):
        if source and apply_source(
            obj,
            source,
            replace_catalog_owned=replace_catalog_owned,
        ):
            changed = True

    if obj_id in common_names:
        cn = common_names[obj_id].strip()
        if cn and obj.get("commonName") != cn:
            obj["commonName"] = cn
            obj["name"] = cn
            changed = True

    # Catalog-owned aliases are rebuilt from validated identity sources. This
    # prevents a stale bad alias from surviving every enrichment run.
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
