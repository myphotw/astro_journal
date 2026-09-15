#!/usr/bin/env python3

import unittest
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from catalog_identity import IdentityEvidence, type_family, validate_merge


class CatalogIdentityValidationTest(unittest.TestCase):
    def test_canonical_object_type_families_are_covered(self) -> None:
        self.assertEqual(type_family("초신성잔해"), "supernova_remnant")
        self.assertEqual(type_family("산개성단"), "open_cluster")
        self.assertEqual(type_family("구상성단"), "globular_cluster")
        self.assertEqual(type_family("은하"), "galaxy")
        self.assertEqual(type_family("행성상성운"), "planetary_nebula")
        self.assertEqual(type_family("발광성운"), "nebula")
        self.assertEqual(type_family("반사성운"), "nebula")
        self.assertEqual(type_family("암흑성운"), "nebula")
        self.assertEqual(type_family("항성"), "star")
        self.assertEqual(type_family("쌍성"), "double_star")

    def test_alias_similarity_is_not_authoritative_identity(self) -> None:
        errors = validate_merge(
            IdentityEvidence("A", object_type="은하"),
            IdentityEvidence("B", object_type="은하"),
            authoritative=False,
        )
        self.assertIn("missing authoritative cross-catalog mapping", errors)

    def test_coordinate_mismatch_blocks_merge(self) -> None:
        errors = validate_merge(
            IdentityEvidence("A", 0.0, 0.0, "Aqr", "은하"),
            IdentityEvidence("B", 20.0, 0.0, "Aqr", "은하"),
            authoritative=True,
        )
        self.assertTrue(any("coordinate separation" in error for error in errors))

    def test_incompatible_object_types_block_merge(self) -> None:
        errors = validate_merge(
            IdentityEvidence("A", object_type="은하"),
            IdentityEvidence("B", object_type="산개성단"),
            authoritative=True,
        )
        self.assertIn("object type mismatch galaxy/open_cluster", errors)


if __name__ == "__main__":
    unittest.main()
