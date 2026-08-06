import json
from pathlib import Path

path = Path("assets/catalog/seestar_catalog.json")
with path.open(encoding="utf-8-sig") as f:
    data = json.load(f)


def bad_ra(ra: str | None) -> bool:
    ra = (ra or "").strip()
    return ra in ("", "-") or "h" not in ra.lower()


missing = [x for x in data if bad_ra(x.get("ra"))]
print("missing count:", len(missing))
for x in missing:
    print(
        f"{x.get('id')}\t{x.get('catalog')}\t{x.get('displayName') or x.get('name')}"
    )
