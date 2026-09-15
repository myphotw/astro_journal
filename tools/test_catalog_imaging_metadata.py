#!/usr/bin/env python3

from __future__ import annotations

import sqlite3
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from catalog_imaging_metadata import (
    AuditState,
    MetadataSource,
    load_openngc,
    openngc_object_type,
    parse_angular_size,
    repair_from_source,
    run,
)


class AngularSizeTest(unittest.TestCase):
    def test_normalizes_degree_arcmin_and_arcsec(self) -> None:
        self.assertAlmostEqual(parse_angular_size("0.5°").major_arcmin, 30)
        self.assertAlmostEqual(parse_angular_size("41.6'").major_arcmin, 41.6)
        self.assertAlmostEqual(parse_angular_size('30\"').major_arcmin, 0.5)

    def test_two_axes_inherit_trailing_unit(self) -> None:
        value = parse_angular_size("62.09 × 36.73'")
        self.assertAlmostEqual(value.major_arcmin, 62.09)
        self.assertAlmostEqual(value.minor_arcmin, 36.73)


class SourceRepairTest(unittest.TestCase):
    def _load_openngc_fixture(self, rows: list[str]):
        header = (
            "Name;Type;RA;Dec;Const;MajAx;MinAx;PosAng;B-Mag;V-Mag;"
            "M;NGC;IC\n"
        )
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "NGC.csv"
            path.write_text(header + "\n".join(rows) + "\n", encoding="utf-8")
            with patch("catalog_imaging_metadata.OPENNGC_PATH", path):
                return load_openngc()

    def test_openngc_stellar_and_nebula_raw_types_are_explicit(self) -> None:
        self.assertEqual(openngc_object_type("*"), "항성")
        self.assertEqual(openngc_object_type("**"), "쌍성")
        self.assertEqual(openngc_object_type("Neb"), "발광성운")
        self.assertEqual(openngc_object_type("Nova"), "항성")
        self.assertIsNone(openngc_object_type("*Ass"))

    def test_new_physical_mappings_repair_legacy_types(self) -> None:
        fixtures = (
            ("IC1088", "*", "항성"),
            ("IC1115", "**", "쌍성"),
            ("NGC1743", "Neb", "발광성운"),
        )
        for object_id, raw_type, expected in fixtures:
            with self.subTest(object_id=object_id):
                row = {
                    "id": object_id,
                    "object_type": "초신성잔해" if raw_type != "Neb" else "구상성단",
                    "type": "초신성잔해" if raw_type != "Neb" else "구상성단",
                    "ra": "-",
                    "dec": "-",
                }
                source = MetadataSource(
                    name="OpenNGC",
                    object_id=object_id,
                    object_type=openngc_object_type(raw_type),
                    raw_object_type=raw_type,
                )
                repair_from_source(row, source, AuditState())
                self.assertEqual(row["object_type"], expected)
                self.assertEqual(row["type"], expected)

    def test_non_physical_and_unknown_openngc_types_fail_closed(self) -> None:
        self.assertIsNone(openngc_object_type("Dup"))
        self.assertIsNone(openngc_object_type("Other"))
        self.assertIsNone(openngc_object_type("NonEx"))
        with self.assertRaisesRegex(ValueError, "Unknown OpenNGC object type"):
            openngc_object_type("FutureType")

    def test_direct_physical_source_beats_duplicate_cross_id_in_any_order(self) -> None:
        direct = "NGC1040;G;02:43:10;+41:30:00;Per;;;;;;;1040;"
        duplicate = "IC9999;Dup;02:43:10;+41:30:00;Per;;;;;;;1040;"
        for rows in ([direct, duplicate], [duplicate, direct]):
            with self.subTest(rows=rows):
                source = self._load_openngc_fixture(rows)["NGC1040"]
                self.assertEqual(source.object_id, "NGC1040")
                self.assertEqual(source.object_type, "은하")

    def test_cross_id_physical_source_beats_non_physical_direct_row(self) -> None:
        physical = "IC9999;G;02:43:10;+41:30:00;Per;;;;;;;1040;"
        for raw_type in ("Dup", "Other", "NonEx"):
            with self.subTest(raw_type=raw_type):
                non_physical = (
                    f"NGC1040;{raw_type};02:43:10;+41:30:00;Per;;;;;;;1040;"
                )
                source = self._load_openngc_fixture(
                    [non_physical, physical]
                )["NGC1040"]
                self.assertEqual(source.object_id, "IC9999")
                self.assertEqual(source.object_type, "은하")

    def test_supernova_remnant_family_does_not_block_open_cluster_repair(self) -> None:
        row = {
            "id": "NGC1252",
            "object_type": "초신성잔해",
            "type": "초신성잔해",
            "ra": "-",
            "dec": "-",
        }
        source = MetadataSource(
            name="OpenNGC",
            object_id="NGC1252",
            object_type="산개성단",
            raw_object_type="OCl",
        )
        repair_from_source(row, source, AuditState())
        self.assertEqual(row["object_type"], "산개성단")
        self.assertEqual(row["type"], "산개성단")

    def test_authoritative_type_replaces_unclassified_legacy_value(self) -> None:
        row = {
            "id": "NGC-AUTHORITATIVE",
            "object_type": "기타",
            "type": "기타",
            "ra": "-",
            "dec": "-",
        }
        source = MetadataSource(
            name="OpenNGC",
            object_id="NGC-AUTHORITATIVE",
            object_type="은하",
            raw_object_type="G",
        )
        repair_from_source(row, source, AuditState())
        self.assertEqual(row["object_type"], "은하")
        self.assertEqual(row["type"], "은하")

    def test_component_or_broad_region_type_remains_manual_review(self) -> None:
        row = {
            "id": "IC-COMPONENT",
            "suffix": "A",
            "object_type": "발광성운",
            "type": "발광성운",
            "ra": "-",
            "dec": "-",
        }
        source = MetadataSource(
            name="OpenNGC",
            object_id="IC-COMPONENT",
            object_type="항성",
            raw_object_type="*",
        )
        state = AuditState()
        repair_from_source(row, source, state)
        self.assertEqual(row["object_type"], "발광성운")
        self.assertIn("IC-COMPONENT", state.manual_review)

    def test_m33_openngc_source_is_authoritative_and_consistent(self) -> None:
        source = load_openngc()["M33"]
        self.assertEqual(source.object_id, "NGC0598")
        self.assertEqual(source.magnitude, "5.79")
        self.assertAlmostEqual(source.major_axis, 62.09)
        self.assertAlmostEqual(source.minor_axis, 36.73)

        row = {
            "id": "M33",
            "mag": "14.2",
            "angular_size": "0.50'",
            "major_axis": 0.5,
            "minor_axis": 41.6,
            "object_type": "은하",
            "type": "은하",
            "constellation": "삼각형자리",
            "ra": "01h 34m",
            "dec": "+30°45'",
        }
        state = AuditState()
        repair_from_source(row, source, state)
        self.assertEqual(row["mag"], "5.79")
        self.assertEqual(row["angular_size"], "62.09' × 36.73'")
        self.assertEqual(row["major_axis"], 62.09)
        self.assertEqual(row["minor_axis"], 36.73)
        self.assertIn("M33", state.auto_fixed)

    def test_coordinate_mismatch_blocks_source_application(self) -> None:
        row = {
            "id": "X",
            "mag": "10",
            "angular_size": "1'",
            "major_axis": 1.0,
            "minor_axis": None,
            "object_type": "은하",
            "type": "은하",
            "constellation": "-",
            "ra": "12h 00m",
            "dec": "+00°00'",
        }
        source = MetadataSource(
            name="OpenNGC",
            object_id="NGC1",
            magnitude="5",
            ra_degrees=0,
            dec_degrees=0,
        )
        state = AuditState()
        repair_from_source(row, source, state)
        self.assertEqual(row["mag"], "10")
        self.assertIn("X", state.manual_review)

    def test_audit_does_not_modify_when_repair_is_disabled(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            db_path = Path(temporary) / "seed.db"
            report_path = Path(temporary) / "report.json"
            conn = sqlite3.connect(db_path)
            conn.execute(
                "CREATE TABLE celestial_objects ("
                "id TEXT PRIMARY KEY, mag TEXT, angular_size TEXT, "
                "major_axis REAL, minor_axis REAL, object_type TEXT, type TEXT, "
                "constellation TEXT, ra TEXT, dec TEXT)"
            )
            conn.execute(
                "INSERT INTO celestial_objects VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                ("UNKNOWN1", "10", "2'", None, None, "은하", "은하", "-", "-", "-"),
            )
            conn.commit()
            conn.close()

            run(db_path, repair=False, report_path=report_path)
            conn = sqlite3.connect(db_path)
            value = conn.execute(
                "SELECT angular_size FROM celestial_objects WHERE id='UNKNOWN1'"
            ).fetchone()[0]
            conn.close()
            self.assertEqual(value, "2'")


if __name__ == "__main__":
    unittest.main()
