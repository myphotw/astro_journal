"""Scan project for CJK/Hanzi in DB and assets."""
import json
import os
import re
import sqlite3

HANZI = re.compile(r"[\u4e00-\u9fff\u3400-\u4dbf\uf900-\ufaff]")
CJK = re.compile(
    r"[\u2e80-\u2eff\u2f00-\u2fdf\u3000-\u303f\u31c0-\u31ef"
    r"\u3200-\u32ff\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff]"
)


def scan_db(path: str) -> None:
    if not os.path.exists(path):
        print(f"missing {path}")
        return
    conn = sqlite3.connect(path)
    cols = [
        "id",
        "name",
        "common_name",
        "constellation",
        "description",
        "search_keywords",
        "aliases_json",
        "cross_catalog_refs_json",
    ]
    found = 0
    for row in conn.execute(
        f"SELECT {', '.join(cols)} FROM celestial_objects"
    ):
        rid = row[0]
        for col, val in zip(cols[1:], row[1:]):
            if val and HANZI.search(str(val)):
                print(f"DB {path} {rid} {col}: {str(val)[:120]}")
                found += 1
    print(f"{path}: {found} hanzi field hits")
    conn.close()


def scan_tree(root: str) -> None:
    for dirpath, _, files in os.walk(root):
        for name in files:
            if not name.endswith((".json", ".dart")):
                continue
            path = os.path.join(dirpath, name)
            text = open(path, encoding="utf-8").read()
            if HANZI.search(text):
                print(f"FILE {path}")
                for line in text.splitlines():
                    if HANZI.search(line):
                        print(f"  {line.strip()[:120]}")


if __name__ == "__main__":
    scan_db("assets/database/catalog_seed.db")
    scan_tree("assets")
    scan_tree("lib")
