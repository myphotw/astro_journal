#!/usr/bin/env python3

from __future__ import annotations

import unittest

from enrich_catalog_metadata import lookup_openngc


class OpenNgcLookupContractTest(unittest.TestCase):
    def test_missing_catalog_is_not_treated_as_messier(self) -> None:
        messier = {8: {"id": "M8", "name": "Lagoon Nebula"}}

        result = lookup_openngc(
            {"id": "solar_8", "number": 8},
            {},
            {},
            messier,
        )

        self.assertIsNone(result)

    def test_solar_catalog_never_uses_same_number_messier_metadata(self) -> None:
        messier = {8: {"id": "M8", "name": "Lagoon Nebula"}}

        result = lookup_openngc(
            {"id": "solar_8", "catalog": "solar", "number": 8},
            {},
            {},
            messier,
        )

        self.assertIsNone(result)

    def test_explicit_messier_catalog_still_resolves(self) -> None:
        m8 = {"id": "M8", "name": "Lagoon Nebula"}

        result = lookup_openngc(
            {"id": "M8", "catalog": "messier", "number": 8},
            {},
            {},
            {8: m8},
        )

        self.assertIs(result, m8)


if __name__ == "__main__":
    unittest.main()
