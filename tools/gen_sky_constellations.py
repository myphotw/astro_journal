# -*- coding: utf-8 -*-
"""Regenerate sky_map_constellation_catalog.dart from Stellarium Western lines + HYG.

Sources:
- tools/constellationship.fab (Stellarium skycultures/western)
- tools/hip_subset.json (HYG v40 subset for HIPs used in lines)
"""
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FAB = ROOT / "tools" / "constellationship.fab"
HIP_JSON = ROOT / "tools" / "hip_subset.json"
OUT = ROOT / "lib" / "data" / "sky_map" / "sky_map_constellation_catalog.dart"

# IAU abbr → (id, nameKo, nameEn)
NAMES: dict[str, tuple[str, str, str]] = {
    "And": ("and", "안드로메다자리", "Andromeda"),
    "Ant": ("ant", "공기펌프자리", "Antlia"),
    "Aps": ("aps", "극락조자리", "Apus"),
    "Aql": ("aql", "독수리자리", "Aquila"),
    "Aqr": ("aqr", "물병자리", "Aquarius"),
    "Ara": ("ara", "제단자리", "Ara"),
    "Ari": ("ari", "양자리", "Aries"),
    "Aur": ("aur", "마차부자리", "Auriga"),
    "Boo": ("boo", "목동자리", "Bootes"),
    "Cae": ("cae", "조각칼자리", "Caelum"),
    "Cam": ("cam", "기린자리", "Camelopardalis"),
    "Cap": ("cap", "염소자리", "Capricornus"),
    "Car": ("car", "용골자리", "Carina"),
    "Cas": ("cas", "카시오페아자리", "Cassiopeia"),
    "Cen": ("cen", "센타우루스자리", "Centaurus"),
    "Cep": ("cep", "세페우스자리", "Cepheus"),
    "Cet": ("cet", "고래자리", "Cetus"),
    "Cha": ("cha", "카멜레온자리", "Chamaeleon"),
    "Cir": ("cir", "컴퍼스자리", "Circinus"),
    "CMa": ("cma", "큰개자리", "Canis Major"),
    "CMi": ("cmi", "작은개자리", "Canis Minor"),
    "Cnc": ("cnc", "게자리", "Cancer"),
    "Col": ("col", "비둘기자리", "Columba"),
    "Com": ("com", "머리털자리", "Coma Berenices"),
    "CrA": ("cra", "남쪽왕관자리", "Corona Australis"),
    "CrB": ("crb", "북쪽왕관자리", "Corona Borealis"),
    "Crt": ("crt", "컵자리", "Crater"),
    "Cru": ("cru", "남십자자리", "Crux"),
    "Crv": ("crv", "까마귀자리", "Corvus"),
    "CVn": ("cvn", "사냥개자리", "Canes Venatici"),
    "Cyg": ("cyg", "백조자리", "Cygnus"),
    "Del": ("del", "돌고래자리", "Delphinus"),
    "Dor": ("dor", "황새치자리", "Dorado"),
    "Dra": ("dra", "용자리", "Draco"),
    "Equ": ("equ", "조랑말자리", "Equuleus"),
    "Eri": ("eri", "에리다누스자리", "Eridanus"),
    "For": ("for", "화로자리", "Fornax"),
    "Gem": ("gem", "쌍둥이자리", "Gemini"),
    "Gru": ("gru", "두루미자리", "Grus"),
    "Her": ("her", "헤르쿨레스자리", "Hercules"),
    "Hor": ("hor", "시계자리", "Horologium"),
    "Hya": ("hya", "바다뱀자리", "Hydra"),
    "Hyi": ("hyi", "물뱀자리", "Hydrus"),
    "Ind": ("ind", "인디언자리", "Indus"),
    "Lac": ("lac", "도마뱀자리", "Lacerta"),
    "Leo": ("leo", "사자자리", "Leo"),
    "Lep": ("lep", "토끼자리", "Lepus"),
    "Lib": ("lib", "천칭자리", "Libra"),
    "LMi": ("lmi", "작은사자자리", "Leo Minor"),
    "Lup": ("lup", "이리자리", "Lupus"),
    "Lyn": ("lyn", "살쾡이자리", "Lynx"),
    "Lyr": ("lyr", "거문고자리", "Lyra"),
    "Men": ("men", "테이블산자리", "Mensa"),
    "Mic": ("mic", "현미경자리", "Microscopium"),
    "Mon": ("mon", "외뿔소자리", "Monoceros"),
    "Mus": ("mus", "파리자리", "Musca"),
    "Nor": ("nor", "자자리", "Norma"),
    "Oct": ("oct", "팔분의자리", "Octans"),
    "Oph": ("oph", "뱀주인자리", "Ophiuchus"),
    "Ori": ("ori", "오리온자리", "Orion"),
    "Pav": ("pav", "공작자리", "Pavo"),
    "Peg": ("peg", "페가수스자리", "Pegasus"),
    "Per": ("per", "페르세우스자리", "Perseus"),
    "Phe": ("phe", "불사조자리", "Phoenix"),
    "Pic": ("pic", "화가자리", "Pictor"),
    "PsA": ("psa", "남쪽물고기자리", "Piscis Austrinus"),
    "Psc": ("psc", "물고기자리", "Pisces"),
    "Pup": ("pup", "고물자리", "Puppis"),
    "Pyx": ("pyx", "나침반자리", "Pyxis"),
    "Ret": ("ret", "그물자리", "Reticulum"),
    "Scl": ("scl", "조각가자리", "Sculptor"),
    "Sco": ("sco", "전갈자리", "Scorpius"),
    "Sct": ("sct", "방패자리", "Scutum"),
    "Ser": ("ser", "뱀자리", "Serpens"),
    "Sex": ("sex", "육분의자리", "Sextans"),
    "Sge": ("sge", "화살자리", "Sagitta"),
    "Sgr": ("sgr", "궁수자리", "Sagittarius"),
    "Tau": ("tau", "황소자리", "Taurus"),
    "Tel": ("tel", "망원경자리", "Telescopium"),
    "TrA": ("tra", "남쪽삼각자리", "Triangulum Australe"),
    "Tri": ("tri", "삼각자리", "Triangulum"),
    "Tuc": ("tuc", "큰부리새자리", "Tucana"),
    "UMa": ("uma", "큰곰자리", "Ursa Major"),
    "UMi": ("umi", "작은곰자리", "Ursa Minor"),
    "Vel": ("vel", "돛자리", "Vela"),
    "Vir": ("vir", "처녀자리", "Virgo"),
    "Vol": ("vol", "날치자리", "Volans"),
    "Vul": ("vul", "여우자리", "Vulpecula"),
}


def esc(s: str) -> str:
    return s.replace("\\", "\\\\").replace("'", "\\'")


def main() -> None:
    hips: dict[str, list] = json.loads(HIP_JSON.read_text(encoding="utf-8"))
    # hip -> (raDeg, decDeg, mag, proper)
    hip_data = {int(k): v for k, v in hips.items()}

    used_hips: set[int] = set()
    constellations: list[tuple[str, str, str, str, list[tuple[int, int]]]] = []

    for line in FAB.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split()
        abbr = parts[0]
        nseg = int(parts[1])
        nums = [int(x) for x in parts[2:]]
        if len(nums) < nseg * 2:
            # truncated line in file — use available pairs
            nseg = len(nums) // 2
        pairs = [(nums[i], nums[i + 1]) for i in range(0, nseg * 2, 2)]
        # drop pairs missing from HYG (should be none)
        pairs = [p for p in pairs if p[0] in hip_data and p[1] in hip_data]
        if not pairs:
            continue
        meta = NAMES.get(abbr)
        if meta is None:
            cid = abbr.lower()
            meta = (cid, f"{abbr}자리", abbr)
        cid, name_ko, name_en = meta
        for a, b in pairs:
            used_hips.add(a)
            used_hips.add(b)
        constellations.append((cid, name_ko, name_en, abbr, pairs))

    # Prefer brighter stars first for stable id ordering
    star_hips = sorted(used_hips, key=lambda h: (hip_data[h][2], h))

    star_lines: list[str] = []
    for hip in star_hips:
        ra, dec, mag, proper = hip_data[hip]
        sid = f"hip{hip}"
        name = proper.strip() if proper and str(proper).strip() else f"HIP {hip}"
        name_ko = name  # proper names are Latin/English; keep as display name
        star_lines.append(
            "    SkyMapStar("
            f"id: '{sid}', name: '{esc(name)}', nameKo: '{esc(name_ko)}', "
            f"raDeg: {ra:.4f}, decDeg: {dec:.4f}, magnitude: {mag:.2f}),"
        )

    const_blocks: list[str] = []
    for cid, name_ko, name_en, _abbr, pairs in constellations:
        star_ids = sorted({f"hip{a}" for a, b in pairs} | {f"hip{b}" for a, b in pairs})
        ids_block = ",\n        ".join(f"'{s}'" for s in star_ids)
        line_block = "\n".join(
            f"        ConstellationLine(startStarId: 'hip{a}', endStarId: 'hip{b}'),"
            for a, b in pairs
        )
        const_blocks.append(
            f"""    SkyMapConstellation(
      id: '{cid}',
      name: '{esc(name_ko)}',
      nameEn: '{esc(name_en)}',
      starIds: [
        {ids_block},
      ],
      lines: [
{line_block}
      ],
    ),"""
        )

    content = f"""import '../models/sky_map_constellation.dart';

/// Sky map constellation catalog (J2000 RA/DEC degrees).
///
/// Stick figures from Stellarium Western `constellationship.fab`
/// (traditional Western / S&T-style lines). Star positions from HYG.
/// IAU publishes boundaries only — not stick-figure lines.
abstract final class SkyMapConstellationCatalog {{
  static const stars = <SkyMapStar>[
{chr(10).join(star_lines)}
  ];

  static final Map<String, SkyMapStar> starsById = {{
    for (final s in stars) s.id: s,
  }};

  static const constellations = <SkyMapConstellation>[
{chr(10).join(const_blocks)}
  ];
}}
"""
    OUT.write_text(content, encoding="utf-8")
    print(
        f"wrote {OUT} stars={len(star_hips)} constellations={len(constellations)}"
    )


if __name__ == "__main__":
    main()
