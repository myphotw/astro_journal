#!/usr/bin/env python3

import unittest
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from catalog_identity import IdentityEvidence, validate_merge


class CatalogIdentityValidationTest(unittest.TestCase):
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
