import sqlite3
import sys

sys.stdout.reconfigure(encoding="utf-8")

paths = [
    r"D:\999. etc\astro_journal\tools\seestar_stardb\StarDB_6.5.2_encrypted.db",
]

for p in paths:
    print("===", p)
    try:
        conn = sqlite3.connect(p)
        tables = [
            r[0]
            for r in conn.execute(
                "SELECT name FROM sqlite_master WHERE type='table'"
            )
        ]
        print("tables:", tables)
        for t in tables:
            cols = [r[1] for r in conn.execute(f"PRAGMA table_info('{t}')")]
            print(f"  {t}: {cols}")
        conn.close()
    except Exception as e:
        print("ERROR:", repr(e))
