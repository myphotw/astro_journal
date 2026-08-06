#!/usr/bin/env python3
"""Shorten ID_TO_KO values in apply_korean_common_names.py."""

from __future__ import annotations

import importlib.util
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
APPLY_PATH = ROOT / "tools/apply_korean_common_names.py"

spec = importlib.util.spec_from_file_location(
    "shorten", ROOT / "tools/shorten_common_names.py"
)
mod = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(mod)

text = APPLY_PATH.read_text(encoding="utf-8")
pattern = re.compile(
    r'("(?:M\d+|NGC\d+|IC\d+|Sh2-\d+|vdB\d+|RCW\d+)[^"]*")\s*:\s*"([^"]+)"'
)


def repl(match: re.Match[str]) -> str:
    key, value = match.group(1), match.group(2)
    fake: dict[str, str] = {
        "commonName": value,
        "constellation": "",
        "type": "",
        "objectType": "",
    }
    prefix_match = re.match(r"^(\S+자리) (.+)$", value)
    if prefix_match:
        fake["constellation"] = prefix_match.group(1)
        fake["type"] = prefix_match.group(2)
    new_value = mod.shorten_for_object(fake)
    if new_value and new_value != value:
        return f'{key}: "{new_value}"'
    return match.group(0)


new_text, count = pattern.subn(repl, text)
if count:
    APPLY_PATH.write_text(new_text, encoding="utf-8")
print(f"updated: {count}")
