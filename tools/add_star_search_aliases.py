#!/usr/bin/env python3
"""Merge star aliases into search_aliases.json and display_name_dictionary.json."""

from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
STARS = ROOT / "assets" / "catalog" / "stars.json"
ALIASES = ROOT / "assets" / "catalog" / "search_aliases.json"
DISPLAY = ROOT / "assets" / "catalog" / "display_name_dictionary.json"

sys.stdout.reconfigure(encoding="utf-8")


def main() -> int:
    stars = json.loads(STARS.read_text(encoding="utf-8"))
    aliases = json.loads(ALIASES.read_text(encoding="utf-8"))
    display = json.loads(DISPLAY.read_text(encoding="utf-8"))
    if not isinstance(display, dict):
        display = {}

    added = 0
    for star in stars:
        sid = star["id"]
        name = star.get("commonName") or star.get("name")
        star_aliases = list(star.get("aliases") or [])
        # Keep Korean name searchable too.
        values = []
        for item in [name, *star_aliases]:
            if not item:
                continue
            text = str(item).strip()
            if text and text not in values:
                values.append(text)
        if not values:
            continue
        existing = aliases.get(sid, [])
        merged = []
        for item in [*existing, *values]:
            if item not in merged:
                merged.append(item)
        if aliases.get(sid) != merged:
            aliases[sid] = merged
            added += 1
        # English alias → Korean display name
        for alias in star_aliases:
            if alias and alias not in display:
                display[alias] = name

    ALIASES.write_text(
        json.dumps(aliases, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    DISPLAY.write_text(
        json.dumps(display, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(f"updated_star_alias_entries: {added}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
