import sqlite3
import sys
import json

sys.stdout.reconfigure(encoding="utf-8")

DB = r"D:\999. etc\astro_journal\assets\database\catalog_seed.db"
conn = sqlite3.connect(DB)
conn.row_factory = sqlite3.Row

total = conn.execute("SELECT COUNT(*) FROM celestial_objects").fetchone()[0]
print("total objects:", total)

print("\n-- by catalog --")
for row in conn.execute(
    "SELECT catalog, COUNT(*) c FROM celestial_objects GROUP BY catalog ORDER BY c DESC"
):
    print(f"  {row['catalog']:12} {row['c']}")

print("\n-- data_source distribution --")
for row in conn.execute(
    "SELECT data_source, COUNT(*) c FROM celestial_objects GROUP BY data_source ORDER BY c DESC"
):
    print(f"  {row['data_source']}: {row['c']}")

print("\n-- seestar_supported --")
for row in conn.execute(
    "SELECT seestar_supported, COUNT(*) c FROM celestial_objects GROUP BY seestar_supported"
):
    print(f"  {row['seestar_supported']}: {row['c']}")

print("\n-- field fill rates --")
fields = [
    "common_name",
    "description",
    "angular_size",
    "major_axis",
    "minor_axis",
    "mag",
    "aliases_json",
    "search_keywords",
]
for f in fields:
    filled = conn.execute(
        f"SELECT COUNT(*) FROM celestial_objects WHERE {f} IS NOT NULL AND TRIM({f}) != '' AND {f} != '-'"
    ).fetchone()[0]
    print(f"  {f:16} {filled}/{total}  ({100*filled/total:.1f}%)")

print("\n-- mag numeric parse rate --")
ok = 0
bad = 0
for (m,) in conn.execute("SELECT mag FROM celestial_objects"):
    try:
        float(str(m))
        ok += 1
    except Exception:
        bad += 1
print(f"  parseable mag: {ok}, non-numeric: {bad}")

print("\n-- object_type distribution (top 25) --")
for row in conn.execute(
    "SELECT object_type, COUNT(*) c FROM celestial_objects GROUP BY object_type ORDER BY c DESC LIMIT 25"
):
    print(f"  {row['object_type']}: {row['c']}")

print("\n-- sample common_name-present non-messier rows --")
for row in conn.execute(
    "SELECT id, catalog, name, common_name, mag, angular_size FROM celestial_objects "
    "WHERE catalog != 'messier' AND common_name IS NOT NULL AND TRIM(common_name) != '' "
    "LIMIT 20"
):
    print(f"  {row['id']:10} {row['catalog']:10} cn={row['common_name']!r} mag={row['mag']} sz={row['angular_size']}")

conn.close()
