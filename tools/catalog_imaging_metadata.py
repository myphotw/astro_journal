#!/usr/bin/env python3
"""Audit and repair catalog imaging metadata from local trusted sources.

Canonical numeric size unit in this pipeline is arcminutes. Runtime/public
models keep their existing string representation; no SQLite schema is added.

Field source priority:
  1. OpenNGC structured row matched by an authoritative typed identifier
  2. Project canonical JSON for the same identifier
  3. Existing seed value
  4. Derived display value from trusted major/minor axes

No value is repaired from numeric appearance alone. Conflicts without a
trusted identity-matched source remain MANUAL_REVIEW entries.
"""

from __future__ import annotations

import argparse
import csv
import json
import math
import re
import sqlite3
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
TOOLS = ROOT / "tools"
SEED_DB = ROOT / "assets" / "database" / "catalog_seed.db"
OPENNGC_PATH = TOOLS / "openngc" / "NGC.csv"
DEFAULT_REPORT = ROOT / "build" / "catalog_imaging_metadata_audit.json"

sys.path.insert(0, str(TOOLS))
from catalog_identity import (  # noqa: E402
    IAU_TO_KO,
    angular_separation_degrees,
    type_family,
)

LOCAL_SOURCES = (
    ("project_messier", ROOT / "assets" / "catalog" / "messier.json"),
    ("project_ngc", ROOT / "assets" / "catalog" / "ngc.json"),
    ("project_ic", ROOT / "assets" / "catalog" / "ic.json"),
    ("project_caldwell", ROOT / "assets" / "catalog" / "caldwell.json"),
    ("project_sh2", ROOT / "assets" / "catalog" / "sh2.json"),
    ("seestar_generated", ROOT / "assets" / "catalog" / "seestar_catalog.json"),
    ("project_extended", ROOT / "assets" / "catalog" / "extended_catalogs.json"),
)

OBJECT_TYPES = {
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
}


def missing(value: Any) -> bool:
    return value is None or (isinstance(value, str) and value.strip() in {"", "-"})


def number(value: Any) -> float | None:
    if value is None or value == "":
        return None
    try:
        result = float(value)
    except (TypeError, ValueError):
        return None
    return result if math.isfinite(result) else None


def typed_id(prefix: str, raw: str) -> str | None:
    raw = raw.strip()
    if not raw or not raw.isdigit():
        return None
    return f"{prefix}{int(raw)}"


def parse_ra_degrees(value: str | None) -> float | None:
    if missing(value):
        return None
    text = str(value).strip()
    colon = re.fullmatch(r"(\d{1,2}):(\d{1,2})(?::(\d+(?:\.\d+)?))?", text)
    units = re.fullmatch(
        r"(\d{1,2})\s*h(?:\s*(\d+(?:\.\d+)?)\s*m)?"
        r"(?:\s*(\d+(?:\.\d+)?)\s*s)?",
        text,
        re.I,
    )
    match = colon or units
    if not match:
        return None
    hours = float(match.group(1))
    minutes = float(match.group(2) or 0)
    seconds = float(match.group(3) or 0)
    if hours >= 24 or minutes >= 60 or seconds >= 60:
        return None
    return (hours + minutes / 60 + seconds / 3600) * 15


def parse_dec_degrees(value: str | None) -> float | None:
    if missing(value):
        return None
    text = str(value).strip()
    colon = re.fullmatch(
        r"([+-]?)(\d{1,2}):(\d{1,2})(?::(\d+(?:\.\d+)?))?", text
    )
    units = re.fullmatch(
        r"([+-]?)(\d{1,2})\s*[°d](?:\s*(\d+(?:\.\d+)?)\s*['′m])?"
        r"(?:\s*(\d+(?:\.\d+)?)\s*[\"″s])?",
        text,
        re.I,
    )
    match = colon or units
    if not match:
        return None
    sign = -1 if match.group(1) == "-" else 1
    degrees = float(match.group(2))
    minutes = float(match.group(3) or 0)
    seconds = float(match.group(4) or 0)
    if degrees > 90 or minutes >= 60 or seconds >= 60:
        return None
    result = sign * (degrees + minutes / 60 + seconds / 3600)
    return result if -90 <= result <= 90 else None


def format_ra(ra_degrees: float) -> str:
    hours_total = ra_degrees / 15
    hours = int(hours_total)
    minutes_total = (hours_total - hours) * 60
    minutes = int(minutes_total)
    seconds = (minutes_total - minutes) * 60
    return f"{hours:02d}h {minutes:02d}m {seconds:04.1f}s"


def format_dec(dec_degrees: float) -> str:
    sign = "+" if dec_degrees >= 0 else "-"
    absolute = abs(dec_degrees)
    degrees = int(absolute)
    minutes_total = (absolute - degrees) * 60
    minutes = int(minutes_total)
    seconds = (minutes_total - minutes) * 60
    return f"{sign}{degrees:02d}° {minutes:02d}' {seconds:04.1f}\""


@dataclass(frozen=True)
class AngularValue:
    major_arcmin: float
    minor_arcmin: float | None
    explicit_unit: bool


def _axis_to_arcmin(raw: str, default_unit: str | None = None) -> tuple[float, bool]:
    match = re.fullmatch(r"\s*(\d+(?:\.\d+)?)\s*([°'′\"″]?)\s*", raw)
    if not match:
        raise ValueError(raw)
    value = float(match.group(1))
    unit = match.group(2) or default_unit
    if unit == "°":
        return value * 60, True
    if unit in {"\"", "″"}:
        return value / 60, True
    if unit in {"'", "′"}:
        return value, True
    return value, False


def parse_angular_size(value: str | None) -> AngularValue | None:
    if missing(value):
        return None
    text = str(value).strip().replace("arcmin", "'").replace("arcsec", '"')
    parts = re.split(r"\s*[×xX]\s*", text)
    if len(parts) not in {1, 2}:
        return None
    trailing_unit = None
    match = re.search(r"([°'′\"″])\s*$", parts[-1])
    if match:
        trailing_unit = match.group(1)
    try:
        major, major_explicit = _axis_to_arcmin(parts[0], trailing_unit)
        minor = None
        minor_explicit = True
        if len(parts) == 2:
            minor, minor_explicit = _axis_to_arcmin(parts[1], trailing_unit)
    except ValueError:
        return None
    return AngularValue(major, minor, major_explicit and minor_explicit)


def angular_text(major: float, minor: float | None) -> str:
    if minor is not None and not math.isclose(major, minor, abs_tol=0.01):
        return f"{major:.2f}' × {minor:.2f}'"
    return f"{major:.2f}'"


def materially_different(left: float | None, right: float | None) -> bool:
    if left is None or right is None:
        return left != right
    tolerance = max(0.05, min(abs(left), abs(right)) * 0.05)
    return abs(left - right) > tolerance


@dataclass(frozen=True)
class MetadataSource:
    name: str
    object_id: str
    magnitude: str | None = None
    angular_size: str | None = None
    major_axis: float | None = None
    minor_axis: float | None = None
    position_angle: float | None = None
    object_type: str | None = None
    constellation: str | None = None
    ra_degrees: float | None = None
    dec_degrees: float | None = None


def load_openngc() -> dict[str, MetadataSource]:
    result: dict[str, MetadataSource] = {}
    with OPENNGC_PATH.open(encoding="utf-8") as handle:
        for row in csv.DictReader(handle, delimiter=";"):
            source_id = row.get("Name", "").strip()
            match = re.fullmatch(r"(NGC|IC)0*(\d+)([A-Z]?)", source_id, re.I)
            identifiers: set[str] = set()
            if match:
                identifiers.add(
                    f"{match.group(1).upper()}{int(match.group(2))}{match.group(3).upper()}"
                )
            for prefix, column in (("M", "M"), ("NGC", "NGC"), ("IC", "IC")):
                identifier = typed_id(prefix, row.get(column, ""))
                if identifier:
                    identifiers.add(identifier)
            if not identifiers:
                continue
            major = number(row.get("MajAx"))
            minor = number(row.get("MinAx"))
            magnitude = row.get("V-Mag", "").strip() or row.get("B-Mag", "").strip()
            angular = angular_text(major, minor) if major is not None else None
            source = MetadataSource(
                name="OpenNGC",
                object_id=source_id,
                magnitude=magnitude or None,
                angular_size=angular,
                major_axis=major,
                minor_axis=minor,
                position_angle=number(row.get("PosAng")),
                object_type=OBJECT_TYPES.get(row.get("Type", "").strip()),
                constellation=IAU_TO_KO.get(row.get("Const", "").strip()),
                ra_degrees=parse_ra_degrees(row.get("RA")),
                dec_degrees=parse_dec_degrees(row.get("Dec")),
            )
            for identifier in identifiers:
                result[identifier] = source
    return result


def load_local_sources() -> dict[str, MetadataSource]:
    result: dict[str, MetadataSource] = {}
    for name, path in LOCAL_SOURCES:
        if not path.is_file():
            continue
        objects = json.loads(path.read_text(encoding="utf-8-sig"))
        for obj in objects:
            object_id = str(obj.get("id", "")).strip()
            if not object_id or object_id in result:
                continue
            parsed = parse_angular_size(obj.get("angularSize"))
            result[object_id] = MetadataSource(
                name=name,
                object_id=object_id,
                magnitude=None if missing(obj.get("magnitude")) else str(obj["magnitude"]),
                angular_size=obj.get("angularSize"),
                major_axis=number(obj.get("majorAxis")) or (parsed.major_arcmin if parsed else None),
                minor_axis=number(obj.get("minorAxis")) or (parsed.minor_arcmin if parsed else None),
                position_angle=number(obj.get("positionAngle")),
                object_type=obj.get("objectType") or obj.get("type"),
                constellation=obj.get("constellation"),
                ra_degrees=parse_ra_degrees(obj.get("ra")),
                dec_degrees=parse_dec_degrees(obj.get("dec")),
            )
    return result


@dataclass
class AuditState:
    issues: list[dict[str, Any]] = field(default_factory=list)
    changes: list[dict[str, Any]] = field(default_factory=list)
    auto_fixed: set[str] = field(default_factory=set)
    manual_review: set[str] = field(default_factory=set)
    source_conflicts: int = 0
    axis_conflicts: int = 0
    unit_conflicts: int = 0
    object_type_conflicts: int = 0
    coordinate_conflicts: int = 0

    def issue(
        self,
        object_id: str,
        code: str,
        field_name: str,
        current: Any,
        source: MetadataSource | None,
        source_value: Any,
        *,
        severity: str,
        decision: str,
        fixed: bool = False,
    ) -> None:
        effective = "INFO" if fixed else severity
        self.issues.append(
            {
                "canonicalId": object_id,
                "code": code,
                "field": field_name,
                "currentValue": current,
                "source": source.name if source else None,
                "sourceObjectId": source.object_id if source else None,
                "comparisonValue": source_value,
                "severity": effective,
                "detectedSeverity": severity,
                "decision": decision,
                "autoFixed": fixed,
            }
        )
        if fixed:
            self.auto_fixed.add(object_id)
        elif severity in {"HARD_ERROR", "WARNING"}:
            self.manual_review.add(object_id)


def source_for_row(
    row: dict[str, Any],
    openngc: dict[str, MetadataSource],
    local: dict[str, MetadataSource],
) -> MetadataSource | None:
    # Hidden cross-catalog rows must inherit the canonical object's metadata.
    # Looking up a standalone Caldwell/IC alias here can re-introduce the exact
    # identity mixing that the canonical grouping stage removed.
    lookup_id = (
        row.get("primary_catalog_id")
        if row.get("is_primary_catalog") == 0 and row.get("primary_catalog_id")
        else row["id"]
    )
    return openngc.get(lookup_id) or local.get(lookup_id)


def coordinates_compatible(row: dict[str, Any], source: MetadataSource) -> bool:
    current_ra = parse_ra_degrees(row.get("ra"))
    current_dec = parse_dec_degrees(row.get("dec"))
    if None in {current_ra, current_dec, source.ra_degrees, source.dec_degrees}:
        return True
    separation = angular_separation_degrees(
        current_ra, current_dec, source.ra_degrees, source.dec_degrees
    )
    # Seed coordinates are generally rounded to whole arcminutes and extended
    # nebulae legitimately use different catalog centers. OpenNGC typed-ID
    # matches therefore allow 0.75 deg; local fallback sources stay stricter.
    limit = 0.75 if source.name == "OpenNGC" else 0.25
    return separation <= limit


def set_field(
    row: dict[str, Any], field_name: str, value: Any, changed: dict[str, Any]
) -> None:
    if row.get(field_name) != value:
        changed[field_name] = {"before": row.get(field_name), "after": value}
        row[field_name] = value


def repair_from_source(
    row: dict[str, Any], source: MetadataSource, state: AuditState
) -> dict[str, Any]:
    changed: dict[str, Any] = {}
    object_id = row["id"]
    authoritative = source.name == "OpenNGC"
    if not coordinates_compatible(row, source):
        state.coordinate_conflicts += 1
        state.issue(
            object_id,
            "identity_coordinate_conflict",
            "ra/dec",
            {"ra": row.get("ra"), "dec": row.get("dec")},
            source,
            {"raDegrees": source.ra_degrees, "decDegrees": source.dec_degrees},
            severity="WARNING",
            decision="MANUAL_REVIEW; source not applied",
        )
        return changed

    current_mag = None if missing(row.get("mag")) else str(row.get("mag"))
    current_mag_number = number(current_mag)
    source_mag_number = number(source.magnitude)
    magnitude_differs = (
        current_mag is None
        or source_mag_number is None
        or current_mag_number is None
        or not math.isclose(current_mag_number, source_mag_number, abs_tol=0.01)
    )
    if source.magnitude is not None and magnitude_differs:
        state.source_conflicts += 1
        set_field(row, "mag", source.magnitude, changed)
        state.issue(
            object_id,
            "source_conflict",
            "magnitude",
            current_mag,
            source,
            source.magnitude,
            severity="WARNING",
            decision="replaced by higher-priority identity-matched source",
            fixed=True,
        )

    current_angular = parse_angular_size(row.get("angular_size"))
    if source.angular_size is not None:
        different = (
            current_angular is None
            or materially_different(current_angular.major_arcmin, source.major_axis)
            or materially_different(current_angular.minor_arcmin, source.minor_axis)
        )
        if different:
            state.source_conflicts += 1
            ratio = None
            if current_angular and source.major_axis and source.major_axis > 0:
                ratio = current_angular.major_arcmin / source.major_axis
                if math.isclose(ratio, 60, rel_tol=0.08) or math.isclose(
                    ratio, 1 / 60, rel_tol=0.08
                ):
                    state.unit_conflicts += 1
            set_field(row, "angular_size", source.angular_size, changed)
            state.issue(
                object_id,
                "unit_conflict" if ratio and (ratio > 50 or ratio < 0.02) else "source_conflict",
                "angular_size",
                row.get("angular_size") if "angular_size" not in changed else changed["angular_size"]["before"],
                source,
                source.angular_size,
                severity="HARD_ERROR" if ratio and (ratio > 50 or ratio < 0.02) else "WARNING",
                decision="normalized to authoritative arcminutes",
                fixed=True,
            )

    if authoritative and source.major_axis is not None:
        if materially_different(number(row.get("major_axis")), source.major_axis) or materially_different(
            number(row.get("minor_axis")), source.minor_axis
        ):
            state.axis_conflicts += 1
            before = {"major": row.get("major_axis"), "minor": row.get("minor_axis")}
            set_field(row, "major_axis", source.major_axis, changed)
            set_field(row, "minor_axis", source.minor_axis, changed)
            if source.position_angle is not None:
                set_field(row, "position_angle", source.position_angle, changed)
            state.issue(
                object_id,
                "major_minor_conflict",
                "major_axis/minor_axis",
                before,
                source,
                {"major": source.major_axis, "minor": source.minor_axis},
                severity="WARNING",
                decision="replaced by OpenNGC axes in arcminutes",
                fixed=True,
            )

    source_family = type_family(source.object_type)
    current_type = row.get("object_type") or row.get("type")
    current_family = type_family(current_type)
    if authoritative and source_family and current_family and source_family != current_family:
        state.object_type_conflicts += 1
        set_field(row, "object_type", source.object_type, changed)
        set_field(row, "type", source.object_type, changed)
        state.issue(
            object_id,
            "object_type_conflict",
            "object_type",
            current_type,
            source,
            source.object_type,
            severity="WARNING",
            decision="replaced by authoritative structured type",
            fixed=True,
        )

    if authoritative and source.constellation and row.get("constellation") != source.constellation:
        set_field(row, "constellation", source.constellation, changed)

    if missing(row.get("ra")) and source.ra_degrees is not None:
        set_field(row, "ra", format_ra(source.ra_degrees), changed)
    if missing(row.get("dec")) and source.dec_degrees is not None:
        set_field(row, "dec", format_dec(source.dec_degrees), changed)

    if changed:
        state.changes.append(
            {
                "canonicalId": object_id,
                "source": source.name,
                "sourceObjectId": source.object_id,
                "fields": changed,
            }
        )
        state.auto_fixed.add(object_id)
    return changed


def audit_row(
    row: dict[str, Any], source: MetadataSource | None, state: AuditState
) -> str:
    object_id = row["id"]
    has_ra = not missing(row.get("ra"))
    has_dec = not missing(row.get("dec"))
    ra = parse_ra_degrees(row.get("ra"))
    dec = parse_dec_degrees(row.get("dec"))
    if has_ra != has_dec:
        state.issue(
            object_id,
            "coordinate_pair_incomplete",
            "ra/dec",
            {"ra": row.get("ra"), "dec": row.get("dec")},
            source,
            None,
            severity="HARD_ERROR",
            decision="MANUAL_REVIEW",
        )
    elif has_ra and (ra is None or dec is None):
        state.issue(
            object_id,
            "invalid_coordinate",
            "ra/dec",
            {"ra": row.get("ra"), "dec": row.get("dec")},
            source,
            None,
            severity="HARD_ERROR",
            decision="MANUAL_REVIEW",
        )

    mag = None if missing(row.get("mag")) else number(row.get("mag"))
    if missing(row.get("mag")):
        state.issue(
            object_id,
            "magnitude_missing",
            "magnitude",
            row.get("mag"),
            source,
            source.magnitude if source else None,
            severity="INFO",
            decision="UNKNOWN; surface brightness unavailable",
        )
    elif mag is None or not -30 <= mag <= 40:
        state.issue(
            object_id,
            "invalid_magnitude",
            "magnitude",
            row.get("mag"),
            source,
            source.magnitude if source else None,
            severity="HARD_ERROR",
            decision="MANUAL_REVIEW",
        )

    angular = parse_angular_size(row.get("angular_size"))
    major = number(row.get("major_axis"))
    minor = number(row.get("minor_axis"))
    if angular is None:
        state.issue(
            object_id,
            "angular_size_missing" if missing(row.get("angular_size")) else "invalid_angular_size",
            "angular_size",
            row.get("angular_size"),
            source,
            source.angular_size if source else None,
            severity="INFO" if missing(row.get("angular_size")) else "HARD_ERROR",
            decision="UNKNOWN" if missing(row.get("angular_size")) else "MANUAL_REVIEW",
        )
    elif angular.major_arcmin <= 0 or (
        angular.minor_arcmin is not None and angular.minor_arcmin <= 0
    ):
        state.issue(
            object_id,
            "non_positive_angular_size",
            "angular_size",
            row.get("angular_size"),
            source,
            source.angular_size if source else None,
            severity="HARD_ERROR",
            decision="MANUAL_REVIEW",
        )
    elif angular.major_arcmin > 21600:
        state.issue(
            object_id,
            "impossible_angular_size",
            "angular_size",
            row.get("angular_size"),
            source,
            source.angular_size if source else None,
            severity="HARD_ERROR",
            decision="MANUAL_REVIEW",
        )

    if major is not None and major <= 0 or minor is not None and minor <= 0:
        state.issue(
            object_id,
            "non_positive_axis",
            "major_axis/minor_axis",
            {"major": major, "minor": minor},
            source,
            None,
            severity="HARD_ERROR",
            decision="MANUAL_REVIEW",
        )
    if major is not None and minor is not None and major < minor:
        state.axis_conflicts += 1
        state.issue(
            object_id,
            "major_minor_reversed",
            "major_axis/minor_axis",
            {"major": major, "minor": minor},
            source,
            None,
            severity="WARNING",
            decision="MANUAL_REVIEW; not swapped without matching trusted source",
        )
    if angular and major is not None and (
        materially_different(angular.major_arcmin, major)
        or materially_different(angular.minor_arcmin, minor)
    ):
        state.axis_conflicts += 1
        state.issue(
            object_id,
            "angular_axis_conflict",
            "angular_size/axes",
            {
                "angularSize": row.get("angular_size"),
                "major": major,
                "minor": minor,
            },
            source,
            None,
            severity="WARNING",
            decision="MANUAL_REVIEW; definitions or source generations differ",
        )

    unresolved = object_id in state.manual_review
    if unresolved:
        return "conflicted"
    if mag is None or (angular is None and major is None):
        return "missing"
    if major is not None and minor is not None:
        return "reliable"
    return "partial"


def write_rows(conn: sqlite3.Connection, rows: list[dict[str, Any]]) -> None:
    columns = [entry[1] for entry in conn.execute("PRAGMA table_info(celestial_objects)")]
    writable = set(columns)
    conn.execute("BEGIN")
    for row in rows:
        values = {key: value for key, value in row.items() if key in writable and key != "id"}
        assignments = ", ".join(f"{key} = ?" for key in values)
        conn.execute(
            f"UPDATE celestial_objects SET {assignments} WHERE id = ?",
            [*values.values(), row["id"]],
        )
    conn.commit()


def build_report(
    rows: list[dict[str, Any]],
    state: AuditState,
    reliability: dict[str, str],
    source_names: dict[str, str | None],
) -> dict[str, Any]:
    unresolved_hard = [
        issue for issue in state.issues if issue["severity"] == "HARD_ERROR"
    ]
    unresolved_warning = [
        issue for issue in state.issues if issue["severity"] == "WARNING"
    ]
    infos = [issue for issue in state.issues if issue["severity"] == "INFO"]
    missing_mag = sum(1 for row in rows if missing(row.get("mag")))
    missing_size = sum(
        1
        for row in rows
        if missing(row.get("angular_size")) and row.get("major_axis") is None
    )
    representative_ids = {
        "NGC6822",
        "M33",
        "M31",
        "M42",
        "NGC7000",
        "NGC7293",
        "M45",
        "M13",
        "M1",
    }
    representative = []
    for row in rows:
        if row["id"] not in representative_ids:
            continue
        representative.append(
            {
                "id": row["id"],
                "type": row.get("object_type") or row.get("type"),
                "magnitude": row.get("mag"),
                "angularSize": row.get("angular_size"),
                "majorAxisArcmin": row.get("major_axis"),
                "minorAxisArcmin": row.get("minor_axis"),
                "metadataSource": source_names.get(row["id"]),
                "surfaceBrightnessCalculable": not missing(row.get("mag"))
                and (
                    not missing(row.get("angular_size"))
                    or row.get("major_axis") is not None
                ),
                "reliability": reliability[row["id"]],
            }
        )
    return {
        "schemaVersion": 1,
        "canonicalSizeUnit": "arcmin",
        "sourcePriority": [
            "OpenNGC identity-matched structured metadata",
            "project canonical JSON",
            "existing seed",
            "derived display value from trusted axes",
        ],
        "summary": {
            "totalObjects": len(rows),
            "hardErrorCount": len(unresolved_hard),
            "warningCount": len(unresolved_warning),
            "infoCount": len(infos),
            "magnitudeMissingCount": missing_mag,
            "angularSizeMissingCount": missing_size,
            "majorMinorConflictCount": state.axis_conflicts,
            "unitConflictCount": state.unit_conflicts,
            "sourceConflictCount": state.source_conflicts,
            "objectTypeConflictCount": state.object_type_conflicts,
            "coordinateConflictCount": state.coordinate_conflicts,
            "autoFixedObjectCount": len(state.auto_fixed),
            "manualReviewObjectCount": len(state.manual_review),
            "reliabilityCounts": {
                key: sum(1 for value in reliability.values() if value == key)
                for key in ("reliable", "partial", "missing", "conflicted")
            },
        },
        "representativeObjects": sorted(representative, key=lambda item: item["id"]),
        "changes": state.changes,
        "issues": state.issues,
    }


def run(seed_db: Path, *, repair: bool, report_path: Path) -> dict[str, Any]:
    openngc = load_openngc()
    local = load_local_sources()
    conn = sqlite3.connect(seed_db)
    conn.row_factory = sqlite3.Row
    rows = [dict(row) for row in conn.execute("SELECT * FROM celestial_objects")]
    state = AuditState()
    source_names: dict[str, str | None] = {}

    for row in rows:
        source = source_for_row(row, openngc, local)
        source_names[row["id"]] = source.name if source else None
        if repair and source:
            repair_from_source(row, source, state)

    reliability: dict[str, str] = {}
    for row in rows:
        source = source_for_row(row, openngc, local)
        reliability[row["id"]] = audit_row(row, source, state)

    if repair:
        write_rows(conn, rows)
    conn.close()
    report = build_report(rows, state, reliability, source_names)
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(
        json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(json.dumps(report["summary"], ensure_ascii=False, indent=2))
    return report


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--seed-db", type=Path, default=SEED_DB)
    parser.add_argument("--report-path", type=Path, default=DEFAULT_REPORT)
    parser.add_argument("--repair", action="store_true")
    args = parser.parse_args()
    report = run(args.seed_db, repair=args.repair, report_path=args.report_path)
    return 1 if report["summary"]["hardErrorCount"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
