#!/usr/bin/env python3
"""Fill missing RA/Dec in seestar_catalog.json from local catalogs and SIMBAD."""

from __future__ import annotations

import json
import math
import re
import time
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SEESTAR_PATH = ROOT / "assets/catalog/seestar_catalog.json"
REFERENCE_FILES = [
    ROOT / "assets/catalog/messier.json",
    ROOT / "assets/catalog/ngc.json",
    ROOT / "assets/catalog/ic.json",
    ROOT / "assets/catalog/caldwell.json",
    ROOT / "assets/catalog/sh2.json",
]
ID_REMAP_PATH = ROOT / "assets/catalog/id_remap.json"
SIMBAD_TAP = "https://simbad.cds.unistra.fr/simbad/sim-tap/sync"

from catalog_identity import CALDWELL_PRIMARY as CALDWELL_NGC





def has_valid_ra(ra: str | None) -> bool:
    ra = (ra or "").strip()
    return ra not in ("", "-") and "h" in ra.lower()


def normalize_key(value: str) -> str:
    return re.sub(r"[^a-z0-9]", "", value.lower())


def load_json(path: Path) -> list[dict]:
    with path.open(encoding="utf-8-sig") as handle:
        return json.load(handle)


def build_reference_lookup() -> dict[str, tuple[str, str]]:
    lookup: dict[str, tuple[str, str]] = {}

    def add_entry(entry: dict) -> None:
        ra = entry.get("ra", "")
        dec = entry.get("dec", "")
        if not has_valid_ra(ra):
            return
        keys = {
            normalize_key(entry.get("id", "")),
            normalize_key(entry.get("name", "")),
            normalize_key(entry.get("displayName", "")),
        }
        number = entry.get("number")
        catalog = entry.get("catalog")
        if catalog and number is not None:
            keys.add(normalize_key(f"{catalog}{number}"))
            keys.add(normalize_key(f"{catalog} {number}"))
        for key in keys:
            if key:
                lookup[key] = (ra, dec)

    for path in REFERENCE_FILES:
        if not path.exists():
            continue
        for entry in load_json(path):
            add_entry(entry)

    for entry in load_json(SEESTAR_PATH):
        add_entry(entry)

    return lookup


def lookup_coords(obj: dict, lookup: dict[str, tuple[str, str]]) -> tuple[str, str] | None:
    candidates = [
        obj.get("id", ""),
        obj.get("displayName", ""),
        obj.get("name", ""),
        f"{obj.get('catalog', '')}{obj.get('number', '')}",
        f"{obj.get('catalog', '')} {obj.get('number', '')}",
    ]
    catalog = obj.get("catalog", "")
    number = obj.get("number")
    if catalog == "caldwell" and number in CALDWELL_NGC:
        target = CALDWELL_NGC[number]
        candidates.append(target)
        candidates.append(re.sub(r"^(NGC|IC)", r"\1 ", target))
    if catalog == "ic":
        base = str(obj.get("id", ""))
        match = re.match(r"(IC\d+)", base, re.IGNORECASE)
        if match:
            parent_id = match.group(1)
            candidates.append(parent_id)
            parent_key = normalize_key(parent_id)
            if parent_key in lookup:
                return lookup[parent_key]

    for alias in obj.get("aliases", []):
        candidates.append(alias)

    for candidate in candidates:
        key = normalize_key(str(candidate))
        if key in lookup:
            return lookup[key]
    return None


def simbad_id_for_object(obj: dict, id_remap: dict[str, str]) -> list[str]:
    obj_id = obj.get("id", "")
    if obj_id in id_remap:
        remapped = id_remap[obj_id]
        return simbad_id_for_text(remapped)

    catalog = obj.get("catalog", "")
    number = obj.get("number")
    names: list[str] = []

    if catalog == "ngc" and number is not None:
        names.append(f"NGC {number}")
    elif catalog == "ic" and number is not None:
        names.append(f"IC {number}")
    elif catalog == "caldwell" and number in CALDWELL_NGC:
        names.extend(simbad_id_for_text(CALDWELL_NGC[number]))
    elif catalog == "sh2" and number is not None:
        names.append(f"SH 2-{number}")
        names.append(f"Sh2-{number}")
    elif catalog == "rcw" and number is not None:
        names.append(f"RCW {number}")
    elif catalog == "vdb" and number is not None:
        names.append(f"vdB {number}")

    display = obj.get("displayName") or obj.get("name") or obj_id
    names.append(display)
    return names


def simbad_id_for_text(text: str) -> list[str]:
    text = text.strip()
    if re.fullmatch(r"NGC\d+", text, re.IGNORECASE):
        return [f"NGC {int(text[3:])}"]
    if re.fullmatch(r"IC\d+[A-Z]?", text, re.IGNORECASE):
        match = re.fullmatch(r"IC(\d+)([A-Z]?)", text, re.IGNORECASE)
        assert match
        return [f"IC {int(match.group(1))}"]
    if re.fullmatch(r"C\d+", text, re.IGNORECASE):
        number = int(text[1:])
        if number in CALDWELL_NGC:
            target = CALDWELL_NGC[number]
            if target.upper() == text.upper():
                return [text.upper()]
            return simbad_id_for_text(target)
    if re.fullmatch(r"M\d+", text, re.IGNORECASE):
        return [text.upper()]
    return [text]


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


def deg_to_ra(deg: float) -> str:
    deg = deg % 360.0
    hours = deg / 15.0
    h = int(hours)
    m = int(round((hours - h) * 60))
    if m == 60:
        h = (h + 1) % 24
        m = 0
    return f"{h:02d}h {m:02d}m"


def deg_to_dec(deg: float) -> str:
    sign = "+" if deg >= 0 else "-"
    deg = abs(deg)
    d = int(deg)
    m = int(round((deg - d) * 60))
    if m == 60:
        d += 1
        m = 0
    return f"{sign}{d}°{m:02d}'"


def query_simbad(names: list[str]) -> tuple[str, str] | None:
    for name in names:
        simbad_name = format_simbad_id(name)
        query = (
            "SELECT TOP 1 basic.ra, basic.dec "
            "FROM ident JOIN basic ON ident.oidref = basic.oid "
            f"WHERE ident.id = '{simbad_name.replace(chr(39), chr(39)+chr(39))}'"
        )
        params = urllib.parse.urlencode(
            {
                "request": "doQuery",
                "lang": "adql",
                "format": "json",
                "query": query,
            }
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
        if not rows:
            continue
        ra_deg, dec_deg = rows[0]
        if ra_deg is None or dec_deg is None:
            continue
        return deg_to_ra(float(ra_deg)), deg_to_dec(float(dec_deg))
    return None


def main() -> None:
    lookup = build_reference_lookup()
    id_remap = load_json(ID_REMAP_PATH)
    data = load_json(SEESTAR_PATH)

    updated_local = 0
    updated_simbad = 0
    unresolved: list[str] = []

    for obj in data:
        if has_valid_ra(obj.get("ra")):
            continue

        coords = lookup_coords(obj, lookup)
        source = "local"
        if coords is None:
            simbad_names = simbad_id_for_object(obj, id_remap)
            coords = query_simbad(simbad_names)
            source = "simbad"
            time.sleep(0.15)

        if coords is None:
            unresolved.append(obj.get("id", "?"))
            continue

        ra, dec = coords
        obj["ra"] = ra
        obj["dec"] = dec
        lookup[normalize_key(obj.get("id", ""))] = (ra, dec)
        if source == "local":
            updated_local += 1
        else:
            updated_simbad += 1
        print(f"[{source}] {obj.get('id')}: {ra}, {dec}")

    with SEESTAR_PATH.open("w", encoding="utf-8") as handle:
        json.dump(data, handle, ensure_ascii=False, indent=2)
        handle.write("\n")

    print(f"local={updated_local}, simbad={updated_simbad}, unresolved={len(unresolved)}")
    if unresolved:
        print("unresolved:", ", ".join(unresolved))


if __name__ == "__main__":
    main()
