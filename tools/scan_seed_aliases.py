import json
import re
import sqlite3

HANZI = re.compile(r"[\u4e00-\u9fff\u3400-\u4dbf\uf900-\ufaff]")

conn = sqlite3.connect("assets/database/catalog_seed.db")
rows = conn.execute(
    "SELECT id, aliases_json, cross_catalog_refs_json, name, common_name, description, search_keywords "
    "FROM celestial_objects"
).fetchall()

hits = []
for row in rows:
    rid = row[0]
    for col, val in zip(
        [
            "aliases_json",
            "cross_catalog_refs_json",
            "name",
            "common_name",
            "description",
            "search_keywords",
        ],
        row[1:],
    ):
        if val and HANZI.search(str(val)):
            hits.append((rid, col, str(val)[:200]))

print(f"hanzi hits: {len(hits)}")
for h in hits[:30]:
    print(h)

# non-ascii aliases without hanzi (korean etc)
alias_hits = []
for rid, aj, *_ in rows:
    if not aj:
        continue
    if HANZI.search(aj):
        alias_hits.append((rid, aj))
print(f"alias rows with hanzi: {len(alias_hits)}")
for rid, aj in alias_hits[:10]:
    print(rid, aj)

conn.close()
