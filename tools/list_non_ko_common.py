#!/usr/bin/env python3
"""List objects needing Korean commonName."""

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
HANGUL = re.compile(r"[\uac00-\ud7a3]")

for fname in ["messier.json", "seestar_catalog.json"]:
    for o in json.load(open(ROOT / "assets/catalog" / fname, encoding="utf-8-sig")):
        cn = (o.get("commonName") or "").strip()
        if not HANGUL.search(cn):
            print(f"{o.get('id')}\t{cn}\t{o.get('displayName','')}\t{o.get('type','')}\t{o.get('constellation','')}")
