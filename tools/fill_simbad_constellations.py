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

from catalog_identity import IAU_TO_KO


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
