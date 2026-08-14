#!/usr/bin/env python3
"""Shared authoritative catalog identity rules for build and audit tools."""

from __future__ import annotations

import json
import math
import re
from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DATA_DIR = ROOT / "tools" / "catalog_data"
CALDWELL_PATH = DATA_DIR / "caldwell_identity.json"
CONSTELLATIONS_PATH = DATA_DIR / "constellations_ko.json"

TYPED_ID = re.compile(r"^(M|NGC|IC|C|Sh2-|RCW|vdB)(\d+)([AB])?$", re.I)


def load_caldwell_mapping() -> dict[int, str]:
    data = json.loads(CALDWELL_PATH.read_text(encoding="utf-8"))
    raw = data.get("mapping", {})
    expected = {str(number) for number in range(1, 110)}
    if set(raw) != expected:
        missing = sorted(expected - set(raw), key=int)
        extra = sorted(set(raw) - expected)
        raise ValueError(f"Caldwell mapping mismatch: missing={missing}, extra={extra}")
    result = {int(number): str(target).strip() for number, target in raw.items()}
    if any(not target for target in result.values()):
        raise ValueError("Caldwell mapping contains an empty canonical identifier")
    return result


def load_constellations() -> dict[str, str]:
    result = json.loads(CONSTELLATIONS_PATH.read_text(encoding="utf-8"))
    if len(result) != 88 or len(set(result)) != 88:
        raise ValueError("Constellation mapping must contain 88 unique abbreviations")
    if len(set(result.values())) != 88:
        raise ValueError("Constellation mapping contains duplicate Korean names")
    return result


CALDWELL_PRIMARY = load_caldwell_mapping()
IAU_TO_KO = load_constellations()


def normalize_typed_id(value: str) -> str | None:
    compact = re.sub(r"[\s_-]+", "", value.strip())
    match = re.fullmatch(r"(M|NGC|IC|C|SH2|RCW|VDB)(\d+)([AB])?", compact, re.I)
    if not match:
        return None
    prefix = match.group(1).upper()
    number = int(match.group(2))
    suffix = (match.group(3) or "").upper()
    if prefix == "SH2":
        return f"Sh2-{number}"
    if prefix == "VDB":
        return f"vdB{number}{suffix}"
    return f"{prefix}{number}{suffix}"


def type_family(value: str | None) -> str | None:
    if not value:
        return None
    lowered = value.casefold()
    rules = (
        (("galaxy", "은하"), "galaxy"),
        (("planetary", "행성상"), "planetary_nebula"),
        (("open cluster", "산개"), "open_cluster"),
        (("globular", "구상"), "globular_cluster"),
        (("nebula", "성운", "snr"), "nebula"),
    )
    for needles, family in rules:
        if any(needle in lowered for needle in needles):
            return family
    return None


def angular_separation_degrees(
    ra1_degrees: float,
    dec1_degrees: float,
    ra2_degrees: float,
    dec2_degrees: float,
) -> float:
    ra1, dec1, ra2, dec2 = map(
        math.radians, (ra1_degrees, dec1_degrees, ra2_degrees, dec2_degrees)
    )
    cosine = (
        math.sin(dec1) * math.sin(dec2)
        + math.cos(dec1) * math.cos(dec2) * math.cos(ra1 - ra2)
    )
    return math.degrees(math.acos(max(-1.0, min(1.0, cosine))))


@dataclass(frozen=True)
class IdentityEvidence:
    object_id: str
    ra_degrees: float | None = None
    dec_degrees: float | None = None
    constellation: str | None = None
    object_type: str | None = None


def validate_merge(
    left: IdentityEvidence,
    right: IdentityEvidence,
    *,
    authoritative: bool,
    max_separation_degrees: float = 0.25,
) -> list[str]:
    """Return hard-error reasons; aliases are intentionally not accepted here."""
    errors: list[str] = []
    if not authoritative:
        errors.append("missing authoritative cross-catalog mapping")
    if (
        left.ra_degrees is not None
        and left.dec_degrees is not None
        and right.ra_degrees is not None
        and right.dec_degrees is not None
    ):
        separation = angular_separation_degrees(
            left.ra_degrees,
            left.dec_degrees,
            right.ra_degrees,
            right.dec_degrees,
        )
        if separation > max_separation_degrees:
            errors.append(f"coordinate separation {separation:.3f} deg")
    if (
        left.constellation
        and right.constellation
        and left.constellation != right.constellation
    ):
        errors.append(
            f"constellation mismatch {left.constellation}/{right.constellation}"
        )
    left_family = type_family(left.object_type)
    right_family = type_family(right.object_type)
    if left_family and right_family and left_family != right_family:
        errors.append(f"object type mismatch {left_family}/{right_family}")
    return errors
