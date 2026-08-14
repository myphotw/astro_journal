#!/usr/bin/env python3
"""Rebuild and verify all generated AstroJournal catalog artifacts."""

from __future__ import annotations

import subprocess
import sys
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def run(*command: str) -> None:
    print("+", " ".join(command), flush=True)
    subprocess.run(command, cwd=ROOT, check=True)


def main() -> int:
    # Identity and unit validation run before any generated artifact is changed.
    run(sys.executable, "-m", "unittest", "tools/test_catalog_identity.py")
    flutter = shutil.which("flutter.bat") or shutil.which("flutter")
    if not flutter:
        raise RuntimeError("Flutter SDK was not found on PATH")
    flutter_bin = Path(flutter).resolve().parent
    dart = flutter_bin / "cache" / "dart-sdk" / "bin" / (
        "dart.exe" if sys.platform == "win32" else "dart"
    )
    if not dart.is_file():
        raise RuntimeError("Bundled Dart SDK was not found under the Flutter SDK")
    run(
        str(dart),
        "--suppress-analytics",
        "run",
        "tools/generate_seestar_catalog.dart",
    )
    run(sys.executable, "tools/enrich_catalog_metadata.py")
    run(sys.executable, "tools/dedup_catalog_duplicates.py")
    run(sys.executable, "tools/repair_catalog_seed.py")
    run(sys.executable, "tools/audit_catalog_integrity.py")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
