#!/usr/bin/env python3

from __future__ import annotations

import sqlite3
import tempfile
import unittest
from pathlib import Path

from catalog_imaging_metadata import (
    AuditState,
    MetadataSource,
    load_openngc,
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
