#!/usr/bin/env python3
"""Repair catalog_seed.db: remap catalogs, add extended entries, enrich metadata.

실행:
    python tools/repair_catalog_seed.py
    python tools/repair_catalog_seed.py --report
"""

from __future__ import annotations

import argparse
import csv
import json
import math
import re
import sqlite3
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SEED_DB = ROOT / "assets" / "database" / "catalog_seed.db"
EXTENDED = ROOT / "assets" / "catalog" / "extended_catalogs.json"
OPENNGC = ROOT / "tools" / "openngc" / "NGC.csv"

sys.path.insert(0, str(ROOT / "tools"))
from enrich_catalog_metadata import (  # noqa: E402
    CALDWELL_NGC,
    IAU_TO_KO,
    MANUAL_METADATA,
    is_missing,
    load_openngc,
    lookup_openngc,
    parse_openngc_row,
)

SUPPORTED = {
    "messier", "ngc", "ic", "caldwell", "sh2", "rcw", "vdb",
    "barnard", "ldn", "lbn", "solar", "milky",
}

CATALOG_ALIASES = {
    "sh2-": "sh2",
    "sh2_": "sh2",
    "barnard": "barnard",
    "ldn": "ldn",
    "lbn": "lbn",
    "nn": None,  # junk catalog — remove
}

MESSIER_ANGULAR = {
    "M1": "6' × 4'", "M2": "16'", "M3": "18'", "M4": "36'", "M5": "23'",
    "M6": "25'", "M7": "80'", "M8": "90' × 40'", "M9": "9'", "M10": "20'",
    "M11": "14'", "M12": "16'", "M13": "20'", "M14": "11'", "M15": "18'",
    "M16": "7'", "M17": "11'", "M18": "9'", "M19": "17'", "M20": "28'",
    "M21": "13'", "M22": "32'", "M23": "27'", "M24": "90'", "M25": "32'",
    "M26": "15'", "M27": "8' × 6'", "M28": "11'", "M29": "7'", "M30": "12'",
    "M31": "190' × 60'", "M32": "8' × 6'", "M33": "73' × 45'", "M34": "35'",
    "M35": "28'", "M36": "12'", "M37": "24'", "M38": "21'", "M39": "32'",
    "M40": "0.8'", "M41": "38'", "M42": "85' × 60'", "M43": "20' × 15'",
    "M44": "95'", "M45": "110'", "M46": "27'", "M47": "30'", "M48": "54'",
    "M49": "8'", "M50": "16'", "M51": "11' × 7'", "M52": "13'", "M53": "13'",
    "M54": "12'", "M55": "19'", "M56": "7'", "M57": "1.4' × 1.0'",
    "M58": "6'", "M59": "5'", "M60": "7'", "M61": "6'", "M62": "14'",
    "M63": "10' × 6'", "M64": "10' × 5'", "M65": "9'", "M66": "9'",
    "M67": "30'", "M68": "11'", "M69": "9'", "M70": "8'", "M71": "7'",
    "M72": "6'", "M73": "1.4'", "M74": "10'", "M75": "6'", "M76": "2.7' × 1.8'",
    "M77": "7'", "M78": "8' × 6'", "M79": "9'", "M80": "9'", "M81": "27'",
    "M82": "11' × 5'", "M83": "13'", "M84": "5'", "M85": "7'", "M86": "8'",
    "M87": "7'", "M88": "7'", "M89": "5'", "M90": "10'", "M91": "5'",
    "M92": "14'", "M93": "22'", "M94": "11'", "M95": "7'", "M96": "7'",
    "M97": "3.4' × 3.3'", "M98": "10'", "M99": "5.4'", "M100": "7'",
    "M101": "29'", "M102": "5' × 2'", "M103": "6'", "M104": "9' × 4'",
    "M105": "5'", "M106": "19'", "M107": "13'", "M108": "9'", "M109": "7'",
    "M110": "17' × 10'",
}

NGC_REF = re.compile(r"NGC\s*(\d+)", re.I)
IC_REF = re.compile(r"IC\s*(\d+)([AB])?", re.I)
MESSIER_REF = re.compile(r"\bM(\d+)\b", re.I)
DISPLAY_DICT_PATH = ROOT / "assets" / "catalog" / "display_name_dictionary.json"
EQUIV_PATH = ROOT / "assets" / "catalog" / "catalog_equivalence.json"
SEARCH_ALIASES_PATH = ROOT / "assets" / "catalog" / "search_aliases.json"

CATALOG_PRIORITY = {
    "messier": 0,
    "ngc": 1,
    "ic": 2,
    "caldwell": 3,
    "sh2": 4,
    "rcw": 5,
    "vdb": 6,
    "barnard": 7,
    "ldn": 8,
    "lbn": 9,
}

GENERIC_COMMON = {
    "발광성운", "반사성운", "암흑성운", "산개성단", "구상성단", "은하",
    "행성상성운", "초신성잔해", "기타", "성운", "성단",
}


def load_display_dictionary() -> dict[str, str]:
    if not DISPLAY_DICT_PATH.is_file():
        return {}
    data = json.loads(DISPLAY_DICT_PATH.read_text(encoding="utf-8"))
    entries = data.get("entries", {})
    return {k.strip().lower(): v for k, v in entries.items()}


def load_search_aliases() -> dict[str, list[str]]:
    if not SEARCH_ALIASES_PATH.is_file():
        return {}
    return json.loads(SEARCH_ALIASES_PATH.read_text(encoding="utf-8"))


def normalize_alias_key(value: str) -> str:
    return " ".join(value.strip().lower().split())


def translate_alias(alias: str, dictionary: dict[str, str]) -> str | None:
    key = normalize_alias_key(alias)
    if key in dictionary:
        return dictionary[key]
    no_apostrophe = key.replace("'", "")
    return dictionary.get(no_apostrophe)


def resolve_display_name(
    row: dict,
    dictionary: dict[str, str],
    aliases_map: dict[str, list[str]],
) -> str | None:
    object_id = row["id"]
    aliases = parse_json_list(row.get("aliases_json"))
    aliases.extend(aliases_map.get(object_id, []))

    for alias in aliases:
        if re.search(r"[\uAC00-\uD7A3]", alias):
            return alias.strip()

    for alias in aliases:
        translated = translate_alias(alias, dictionary)
        if translated:
            return translated

    common = (row.get("common_name") or "").strip()
    if common and common not in GENERIC_COMMON and common != object_id:
        return common

    name = (row.get("name") or "").strip()
    if name and name not in GENERIC_COMMON and name != object_id:
        return name

    object_type = (row.get("object_type") or row.get("type") or "").strip()
    return object_type or None


def enrich_display_names(rows: dict[str, dict]) -> int:
    dictionary = load_display_dictionary()
    aliases_map = load_search_aliases()
    updated = 0
    for row in rows.values():
        resolved = resolve_display_name(row, dictionary, aliases_map)
        if not resolved:
            continue
        current = (row.get("common_name") or "").strip()
        if current in GENERIC_COMMON or current == row["id"] or not current:
            row["common_name"] = resolved
            updated += 1
    return updated


def pick_primary_id(members: list[str], canonical_id: str, rows: dict[str, dict]) -> str:
    if canonical_id and canonical_id in members:
        return canonical_id

    def score(object_id: str) -> tuple[int, int, int, str]:
        row = rows[object_id]
        pri = CATALOG_PRIORITY.get(row["catalog"], 50)
        featured = -(row.get("is_featured") or 0)
        display_priority = row.get("display_priority") or 9999
        return (pri, featured, display_priority, object_id)

    return sorted(members, key=score)[0]


def norm_ref(value: str) -> str:
    return re.sub(r"[\s\-_]+", "", value).upper()


def resolve_ref(ref: str, lookup: dict[str, str]) -> str | None:
    key = norm_ref(ref)
    if key in lookup:
        return lookup[key]
    patterns = [
        (r"^M(\d+)$", lambda m: f"M{m.group(1)}"),
        (r"^NGC(\d+)([AB])?$", lambda m: f"NGC{m.group(1)}{m.group(2) or ''}"),
        (r"^IC(\d+)([AB])?$", lambda m: f"IC{m.group(1)}{m.group(2) or ''}"),
        (r"^SH2(\d+)$", lambda m: f"Sh2-{m.group(1)}"),
        (r"^RCW(\d+)$", lambda m: f"RCW{m.group(1)}"),
        (r"^C(\d+)$", lambda m: f"C{m.group(1)}"),
        (r"^B(\d+)$", lambda m: f"B{m.group(1)}"),
        (r"^LDN(\d+)$", lambda m: f"LDN{m.group(1)}"),
        (r"^LBN(\d+)$", lambda m: f"LBN{m.group(1)}"),
        (r"^VDB(\d+)$", lambda m: f"vdB{m.group(1)}"),
    ]
    for pattern, fmt in patterns:
        match = re.match(pattern, key)
        if not match:
            continue
        object_id = fmt(match)
        if object_id in lookup.values():
            return object_id
    return None


def best_common_name(members: list[str], rows: dict[str, dict]) -> str | None:
    best = None
    best_score = -1
    for member_id in members:
        common = (rows[member_id].get("common_name") or "").strip()
        if not common or common in GENERIC_COMMON or common == member_id:
            continue
        score = (100 - CATALOG_PRIORITY.get(rows[member_id]["catalog"], 50)) * 10
        score += rows[member_id].get("is_featured") or 0
        if re.search(r"[\uAC00-\uD7A3]", common):
            score += 5
        if score > best_score:
            best_score = score
            best = common
    return best


def apply_group(
    members: list[str],
    rows: dict[str, dict],
    canonical_id: str | None = None,
    common_name: str | None = None,
) -> int:
    if len(members) <= 1:
        return 0
    primary_id = pick_primary_id(members, canonical_id or members[0], rows)
    primary = rows[primary_id]
    cross = set(parse_json_list(primary.get("cross_catalog_refs_json")))
    hidden = 0
    for member_id in members:
        if member_id == primary_id:
            continue
        cross.add(member_id)
        member = rows[member_id]
        member["is_primary_catalog"] = 0
        member["primary_catalog_id"] = primary_id
        hidden += 1
    primary["cross_catalog_refs_json"] = encode_json_list(sorted(cross))
    chosen_name = (common_name or "").strip() or best_common_name(members, rows)
    current = (primary.get("common_name") or "").strip()
    if chosen_name and (not current or current in GENERIC_COMMON):
        primary["common_name"] = chosen_name
    primary["is_primary_catalog"] = 1
    primary["primary_catalog_id"] = None
    return hidden


def discover_cross_catalog_groups(rows: dict[str, dict]) -> list[dict]:
    lookup = {norm_ref(object_id): object_id for object_id in rows}
    edges: dict[str, set[str]] = {}
    for object_id, row in rows.items():
        refs = set(parse_json_list(row.get("aliases_json")))
        refs.update(parse_json_list(row.get("cross_catalog_refs_json")))
        for ref in refs:
            target = resolve_ref(ref, lookup)
            if target and target != object_id:
                edges.setdefault(object_id, set()).add(target)

    pairs: set[tuple[str, str]] = set()
    for object_id, targets in edges.items():
        catalog = rows[object_id]["catalog"]
        for target in targets:
            if rows[target]["catalog"] == catalog:
                continue
            if object_id not in edges.get(target, set()):
                continue
            pairs.add(tuple(sorted((object_id, target))))

    parent = {object_id: object_id for object_id in rows}
    def find(node: str) -> str:
        while parent[node] != node:
            parent[node] = parent[parent[node]]
            node = parent[node]
        return node

    def union(a: str, b: str) -> None:
        ra, rb = find(a), find(b)
        if ra != rb:
            parent[rb] = ra

    for a, b in pairs:
        union(a, b)

    components: dict[str, set[str]] = {}
    for object_id in rows:
        components.setdefault(find(object_id), set()).add(object_id)

    groups = []
    for members in components.values():
        if len(members) <= 1:
            continue
        member_list = sorted(members)
        groups.append(
            {
                "canonicalId": pick_primary_id(member_list, "", rows),
                "members": member_list,
                "commonName": best_common_name(member_list, rows),
            }
        )
    return groups


def apply_primary_catalog(rows: dict[str, dict]) -> int:
    hidden = 0
    for row in rows.values():
        row["is_primary_catalog"] = 1
        row["primary_catalog_id"] = None

    json_groups = []
    if EQUIV_PATH.is_file():
        data = json.loads(EQUIV_PATH.read_text(encoding="utf-8"))
        json_groups = data.get("groups", [])

    for group in json_groups:
        members = [member for member in group.get("members", []) if member in rows]
        hidden += apply_group(
            members,
            rows,
            canonical_id=group.get("canonicalId"),
            common_name=group.get("commonName"),
        )

    for group in discover_cross_catalog_groups(rows):
        members = [member for member in group["members"] if member in rows]
        hidden += apply_group(
            members,
            rows,
            canonical_id=group.get("canonicalId"),
            common_name=group.get("commonName"),
        )

    return hidden


def parse_json_list(raw: str | None) -> list[str]:
    if not raw:
        return []
    try:
        data = json.loads(raw)
        if isinstance(data, list):
            return [str(x) for x in data]
    except json.JSONDecodeError:
        pass
    return []


def encode_json_list(items: list[str]) -> str | None:
    cleaned = [x.strip() for x in items if x and x.strip()]
    if not cleaned:
        return None
    return json.dumps(cleaned, ensure_ascii=False)


def angular_from_axes(maj: float | None, min_ax: float | None) -> str | None:
    if maj is None:
        return None
    if min_ax is not None and abs(min_ax - maj) > 0.01:
        return f"{maj:g}' × {min_ax:g}'"
    return f"{maj:g}'"


def normalize_catalog(raw: str | None) -> str | None:
    if not raw:
        return None
    cat = raw.strip().lower()
    if cat in CATALOG_ALIASES:
        return CATALOG_ALIASES[cat]
    return cat if cat in SUPPORTED else None


def row_to_object(row: dict) -> dict:
    return {
        "id": row["id"],
        "catalog": row["catalog"],
        "number": row["num"],
        "suffix": row.get("suffix"),
        "name": row.get("name"),
        "commonName": row.get("common_name"),
        "objectType": row.get("object_type"),
        "constellation": row.get("constellation"),
        "magnitude": row.get("mag"),
        "angularSize": row.get("angular_size"),
        "ra": row.get("ra"),
        "dec": row.get("dec"),
    }


def apply_openngc(row: dict, ngc_db, ic_db, messier_db) -> bool:
    obj = row_to_object(row)
    source = lookup_openngc(obj, ngc_db, ic_db, messier_db)
    if not source:
        return False
    changed = False
    if is_missing(row.get("constellation")) and source.get("constellation"):
        row["constellation"] = source["constellation"]
        changed = True
    if is_missing(row.get("mag")) and source.get("magnitude"):
        row["mag"] = source["magnitude"]
        changed = True
    if is_missing(row.get("angular_size")) and source.get("angularSize"):
        row["angular_size"] = source["angularSize"]
        changed = True
    if source.get("major_axis") and row.get("major_axis") is None:
        pass
    return changed


def apply_manual(row: dict) -> bool:
    manual = MANUAL_METADATA.get(row["id"])
    if not manual:
        return False
    changed = False
    if is_missing(row.get("constellation")) and manual.get("constellation"):
        row["constellation"] = manual["constellation"]
        changed = True
    if is_missing(row.get("mag")) and manual.get("magnitude"):
        row["mag"] = manual["magnitude"]
        changed = True
    if is_missing(row.get("angular_size")) and manual.get("angularSize"):
        row["angular_size"] = manual["angularSize"]
        changed = True
    if manual.get("commonName") and row.get("common_name") in GENERIC_COMMON:
        row["common_name"] = manual["commonName"]
        if row.get("name") in GENERIC_COMMON:
            row["name"] = manual["commonName"]
        changed = True
    if manual.get("aliases"):
        aliases = parse_json_list(row.get("aliases_json"))
        merged = list(dict.fromkeys([*aliases, *manual["aliases"]]))
        encoded = encode_json_list(merged)
        if encoded != row.get("aliases_json"):
            row["aliases_json"] = encoded
            changed = True
    return changed


def apply_messier_override(row: dict) -> bool:
    if row.get("catalog") != "messier":
        return False
    size = MESSIER_ANGULAR.get(row["id"])
    if not size:
        return False
    if is_missing(row.get("angular_size")):
        row["angular_size"] = size
        return True
    return False


def infer_constellation_from_refs(row: dict, by_id: dict[str, dict]) -> bool:
    if not is_missing(row.get("constellation")):
        return False
    refs = parse_json_list(row.get("aliases_json")) + parse_json_list(
        row.get("cross_catalog_refs_json")
    )
    for ref in refs:
        m = NGC_REF.search(ref)
        if m:
            target = by_id.get(f"NGC{int(m.group(1))}")
            if target and not is_missing(target.get("constellation")):
                row["constellation"] = target["constellation"]
                return True
        m = IC_REF.search(ref)
        if m:
            suffix = (m.group(2) or "").upper()
            target = by_id.get(f"IC{int(m.group(1))}{suffix}")
            if target and not is_missing(target.get("constellation")):
                row["constellation"] = target["constellation"]
                return True
        m = MESSIER_REF.search(ref)
        if m:
            target = by_id.get(f"M{int(m.group(1))}")
            if target and not is_missing(target.get("constellation")):
                row["constellation"] = target["constellation"]
                return True
    return False


def cleanup_dark_catalog_metadata(rows: dict[str, dict]) -> int:
    """암흑 성운 카탈로그는 밝기 등급을 비워 둔다."""
    fixed = 0
    for row in rows.values():
        if row.get("catalog") not in {"barnard", "ldn", "lbn"}:
            continue
        if row.get("mag") not in (None, "", "-"):
            row["mag"] = "-"
            fixed += 1
    return fixed


def parse_ra_dec(ra: str | None, dec: str | None) -> tuple[float, float] | None:
    if not ra or not dec or is_missing(ra) or is_missing(dec):
        return None
    ra_match = re.search(
        r"(\d+)\s*h\s*(\d+(?:\.\d+)?)\s*m(?:\s*(\d+(?:\.\d+)?)\s*s)?",
        ra,
        re.I,
    )
    dec_match = re.search(
        r"([+-]?)\s*(\d+)\s*°\s*(\d+(?:\.\d+)?)\s*'(?:\s*(\d+(?:\.\d+)?)\s*\")?",
        dec,
    )
    if not ra_match or not dec_match:
        return None
    ra_hours = (
        float(ra_match.group(1))
        + float(ra_match.group(2)) / 60.0
        + float(ra_match.group(3) or 0) / 3600.0
    )
    sign = -1.0 if dec_match.group(1) == "-" else 1.0
    dec_deg = sign * (
        float(dec_match.group(2))
        + float(dec_match.group(3)) / 60.0
        + float(dec_match.group(4) or 0) / 3600.0
    )
    return ra_hours, dec_deg


def angular_distance_deg(ra1: float, dec1: float, ra2: float, dec2: float) -> float:
    ra1r, dec1r = math.radians(ra1 * 15), math.radians(dec1)
    ra2r, dec2r = math.radians(ra2 * 15), math.radians(dec2)
    cos_sep = math.sin(dec1r) * math.sin(dec2r) + math.cos(dec1r) * math.cos(
        dec2r
    ) * math.cos(ra1r - ra2r)
    cos_sep = max(-1.0, min(1.0, cos_sep))
    return math.degrees(math.acos(cos_sep))


def nearest_constellation_from_coords(
    row: dict, anchors: list[tuple[float, float, str]]
) -> str | None:
    coords = parse_ra_dec(row.get("ra"), row.get("dec"))
    if coords is None:
        return None
    ra, dec = coords
    best_dist = 999.0
    best_const: str | None = None
    for ara, adec, acon in anchors:
        dist = angular_distance_deg(ra, dec, ara, adec)
        if dist < best_dist:
            best_dist = dist
            best_const = acon
    if best_dist <= 8.0 and best_const:
        return best_const
    return None


def build_constellation_anchors(rows: dict[str, dict]) -> list[tuple[float, float, str]]:
    anchors: list[tuple[float, float, str]] = []
    for row in rows.values():
        if is_missing(row.get("constellation")):
            continue
        coords = parse_ra_dec(row.get("ra"), row.get("dec"))
        if coords is None:
            continue
        anchors.append((coords[0], coords[1], row["constellation"]))
    return anchors


def fill_constellation_by_coords(
    rows: dict[str, dict], anchors: list[tuple[float, float, str]]
) -> int:
    updated = 0
    for row in rows.values():
        if not is_missing(row.get("constellation")):
            continue
        result = nearest_constellation_from_coords(row, anchors)
        if result:
            row["constellation"] = result
            updated += 1
    return updated


def infer_mag_from_refs(row: dict, by_id: dict[str, dict]) -> bool:
    if not is_missing(row.get("mag")):
        return False
    if row.get("catalog") in {"barnard", "ldn", "lbn"}:
        return False
    if (row.get("object_type") or "") == "암흑성운":
        return False
    refs = parse_json_list(row.get("cross_catalog_refs_json"))
    for ref in refs:
        m = NGC_REF.search(ref)
        if m:
            target = by_id.get(f"NGC{int(m.group(1))}")
            if target and not is_missing(target.get("mag")):
                row["mag"] = target["mag"]
                return True
    return False


def fill_axes_to_angular(row: dict) -> bool:
    if not is_missing(row.get("angular_size")):
        return False
    maj = row.get("major_axis")
    min_ax = row.get("minor_axis")
    if maj is None:
        return False
    row["angular_size"] = angular_from_axes(float(maj), float(min_ax) if min_ax else None)
    return True


def extended_to_row(entry: dict) -> dict:
    aliases = entry.get("aliases") or []
    cross = entry.get("crossCatalogRefs") or []
    return {
        "id": entry["id"],
        "num": entry["number"],
        "catalog": entry["catalog"],
        "name": entry.get("name") or entry.get("commonName") or entry["id"],
        "type": entry.get("objectType") or entry.get("type") or "기타",
        "constellation": entry.get("constellation") or "-",
        "ra": entry.get("ra") or "-",
        "dec": entry.get("dec") or "-",
        "mag": entry.get("magnitude") or "-",
        "captured": 0,
        "captured_date": None,
        "photo_uri": None,
        "memo": "",
        "exif_json": None,
        "aliases_json": encode_json_list(aliases),
        "cross_catalog_refs_json": encode_json_list(cross),
        "common_name": entry.get("commonName") or entry.get("name"),
        "object_type": entry.get("objectType") or entry.get("type") or "기타",
        "seestar_supported": 1 if entry.get("seestarSupported") else 0,
        "suffix": entry.get("suffix"),
        "tags_json": None,
        "peak_month": None,
        "best_season": None,
        "angular_size": entry.get("angularSize"),
        "description": entry.get("description"),
        "search_keywords": None,
        "major_axis": None,
        "minor_axis": None,
        "position_angle": None,
        "data_source": "Manual" if not entry.get("seestarSupported") else "Seestar",
        "is_featured": 0,
        "display_priority": 9999,
    }


def remap_malformed_rows(rows: dict[str, dict]) -> tuple[int, int]:
    """Normalize catalog typos and drop junk nn rows."""
    remapped = 0
    removed = 0
    for oid in list(rows):
        row = rows[oid]
        raw_cat = (row.get("catalog") or "").strip().lower()
        fixed = normalize_catalog(raw_cat)
        if fixed is None and raw_cat == "nn":
            del rows[oid]
            removed += 1
            continue
        if fixed and fixed != raw_cat:
            row["catalog"] = fixed
            remapped += 1
    return remapped, removed


def add_extended_entries(rows: dict[str, dict]) -> int:
    if not EXTENDED.exists():
        return 0
    entries = json.load(EXTENDED.open(encoding="utf-8-sig"))
    added = 0
    for entry in entries:
        row = extended_to_row(entry)
        oid = row["id"]
        if oid in rows:
            existing = rows[oid]
            for field in (
                "constellation", "mag", "angular_size", "common_name", "name",
                "ra", "dec", "object_type", "type", "aliases_json",
                "cross_catalog_refs_json",
            ):
                if is_missing(existing.get(field)) and not is_missing(row.get(field)):
                    existing[field] = row[field]
            if existing.get("seestar_supported", 0) == 0 and row.get("seestar_supported") == 1:
                existing["seestar_supported"] = 1
            continue
        rows[oid] = row
        added += 1
    return added


def enrich_all(rows: dict[str, dict]) -> dict[str, int]:
    ngc_db, ic_db, messier_db = load_openngc()
    stats = {
        "openngc": 0,
        "manual": 0,
        "messier_size": 0,
        "cross_constellation": 0,
        "cross_mag": 0,
        "axes_size": 0,
    }

    # Pass 1: OpenNGC + manual + messier
    for row in rows.values():
        if apply_openngc(row, ngc_db, ic_db, messier_db):
            stats["openngc"] += 1
        if apply_manual(row):
            stats["manual"] += 1
        if apply_messier_override(row):
            stats["messier_size"] += 1
        if fill_axes_to_angular(row):
            stats["axes_size"] += 1

    by_id = rows

    # Pass 2: cross-ref inference (may need 2 rounds)
    for _ in range(2):
        for row in rows.values():
            if infer_constellation_from_refs(row, by_id):
                stats["cross_constellation"] += 1
            if infer_mag_from_refs(row, by_id):
                stats["cross_mag"] += 1

    anchors = build_constellation_anchors(rows)
    stats["coord_constellation"] = fill_constellation_by_coords(rows, anchors)

    return stats


def audit(rows: dict[str, dict]) -> None:
    total = len(rows)
    print(f"\n== audit ({total} objects) ==")
    for field in ("mag", "angular_size", "constellation"):
        miss = sum(1 for r in rows.values() if is_missing(r.get(field)))
        print(f"  missing {field}: {miss}")

    print("\n== by catalog ==")
    counts: dict[str, int] = {}
    for r in rows.values():
        counts[r["catalog"]] = counts.get(r["catalog"], 0) + 1
    for cat, n in sorted(counts.items(), key=lambda x: -x[1]):
        flag = "" if cat in SUPPORTED else " [UNSUPPORTED]"
        print(f"  {cat}: {n}{flag}")


def write_rows(conn: sqlite3.Connection, rows: dict[str, dict]) -> None:
    columns = conn.execute("PRAGMA table_info(celestial_objects)").fetchall()
    existing = {column[1] for column in columns}
    if "is_primary_catalog" not in existing:
        conn.execute(
            "ALTER TABLE celestial_objects "
            "ADD COLUMN is_primary_catalog INTEGER NOT NULL DEFAULT 1"
        )
    if "primary_catalog_id" not in existing:
        conn.execute(
            "ALTER TABLE celestial_objects ADD COLUMN primary_catalog_id TEXT"
        )

    conn.execute("DELETE FROM celestial_objects")
    for row in rows.values():
        columns = ", ".join(row.keys())
        placeholders = ", ".join("?" for _ in row)
        conn.execute(
            f"INSERT INTO celestial_objects ({columns}) VALUES ({placeholders})",
            list(row.values()),
        )
    conn.commit()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--report", action="store_true", help="변경 없이 감사만")
    args = parser.parse_args()

    if not SEED_DB.is_file():
        print(f"Missing seed DB: {SEED_DB}")
        return 1

    conn = sqlite3.connect(SEED_DB)
    conn.row_factory = sqlite3.Row
    rows = {r["id"]: dict(r) for r in conn.execute("SELECT * FROM celestial_objects")}

    print(f"loaded {len(rows)} rows")
    remapped, removed = remap_malformed_rows(rows)
    print(f"remapped catalogs: {remapped}, removed junk: {removed}")

    added = add_extended_entries(rows)
    print(f"added extended entries: {added}")

    stats = enrich_all(rows)
    stats["dark_mag_cleanup"] = cleanup_dark_catalog_metadata(rows)
    stats["display_names"] = enrich_display_names(rows)
    stats["primary_hidden"] = apply_primary_catalog(rows)
    print("enrichment:", stats)

    audit(rows)

    if args.report:
        conn.close()
        return 0

    write_rows(conn, rows)
    conn.close()
    print(f"\nwritten to {SEED_DB}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
