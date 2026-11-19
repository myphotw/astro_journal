# AstroJournal 유명 촬영 대상 후보 v1 — 설치 DB 대조

대조 기준: 설치된 Windows 앱의 `astro_journal.db`, `PRAGMA user_version=36`, `celestial_objects` 13,562행. 번들 seed나 NAS DB로 대체하지 않았다. 참조 소스 버전: 저장소 HEAD `0cb1281`. SQLite `readOnly` 및 `query_only`로 천체 카탈로그 필드만 조회했다.

입력: `astrophotography_targets_candidate_v1.csv`의 99행(A 55, B 44). 후보명·카탈로그 번호·별칭·입력 유형·등급 및 순서를 보존했다. `CSV 행`은 헤더를 1행으로 센 번호다. 지역 관계에서 추가 확인한 ID는 기존 후보에 대응되는 레코드이지 신규 후보가 아니다.

## 판정 및 해석

- DB의 `id`, `catalog`/`num`(접미사 보존), `primary_catalog_id`, 이름·공통명, `aliases_json`, `cross_catalog_refs_json`, `object_type`/`type`, RA/Dec 및 각지름을 확인했다. 검색 키에서 공백·대소문자·번호 선행 0을 정규화하고 `Caldwell`/`C`, `Barnard`/`B`를 통일했다. `NGC 7318A/B`와 `C33/C34`는 개별 명칭으로 확인했다. 이름 일치만으로 정체성을 인정하지 않았다.
- CSV에 RA/Dec 열이 없다. NGC/IC는 [OpenNGC J2000 기준 데이터](https://github.com/mattiaverga/OpenNGC/blob/be3cd6c5498806a2fbb2f7e0452ef802dbb02be0/database_files/NGC.csv), [필드 정의](https://github.com/mattiaverga/OpenNGC/blob/master/NGC_guide.txt), 일부는 [SIMBAD](https://simbad.cds.unistra.fr/simbad/) 및 [Sharpless 관측 아틀라스](https://reinervogel.net/Sharpless/Sharpless_data_e.html)의 위치와 비교했다. DB 좌표는 원문이며 별도 좌표 epoch 필드는 확인되지 않았다. `Δ`는 표기값을 비교해 얻은 대권 거리로, 분 단위 DB 좌표의 반올림이나 확장 천체의 중심 정의 차이를 포함한다. 고정 허용치로만 판정하지 않았다. `—` 또는 좌표 `- / -`는 해당 기준 또는 DB 위치가 없어 수치 검증하지 못했음을 뜻한다.
- `MATCH`: 같은 천체 또는 집계 대상의 DB 정체성 확인. 실제 DB 별칭 행도 함께 나열한다. `POSSIBLE_MATCH`: DB ID는 찾았으나 위치·명칭·유형을 함께 확인하기에는 충돌 또는 결측이 있다. `MULTIPLE_MATCH`: 여러 영역·구성 레코드가 대응한다. 일부가 없는 경우 또는 구성 후보에 충돌이 있는 경우 주석으로 구분한다. `NOT_FOUND`: 검색한 설치 DB에서 해당 대상의 레코드를 확인하지 못했다. `INVALID_OR_UNCERTAIN`: CSV 식별자가 다른 천체를 가리키는 등 입력 해석 자체를 보류해야 한다.
- 동일 물체의 카탈로그 별칭(예: `C70 → NGC300`)과 같은 촬영 프레임의 다른 객체(예: `NGC4038`, `NGC4039`)는 다르게 취급했다. 서로 가까운 좌표만으로 연결·병합하지 않았다. 장비 적합성, 관측 가능성, 원본 등급은 판정에 쓰지 않았다.

## 카탈로그별 대조 통계

분모는 입력 후보의 주 카탈로그이며, 구성원과 교차 별칭은 중복 집계하지 않는다. 설치 DB 행 수는 별도 열이다.

| 입력 주 카탈로그 | MATCH | POSSIBLE_MATCH | MULTIPLE_MATCH | NOT_FOUND | INVALID_OR_UNCERTAIN | 후보 합계 | 같은 계열의 설치 DB 행 |
|---|---:|---:|---:|---:|---:|---:|---:|
| Abell | 0 | 0 | 0 | 1 | 0 | 1 | 0 |
| Barnard (B) | 0 | 0 | 1 | 5 | 0 | 6 | 0 |
| Caldwell | 0 | 1 | 0 | 0 | 0 | 1 | 74 |
| ESO | 0 | 0 | 0 | 1 | 0 | 1 | 0 |
| IC | 9 | 0 | 6 | 0 | 0 | 15 | 5,163 |
| LDN | 0 | 0 | 1 | 0 | 0 | 1 | 0 |
| NGC | 49 | 6 | 11 | 1 | 2 | 69 | 7,715 |
| Sharpless (Sh2) | 3 | 1 | 0 | 0 | 0 | 4 | 202 |
| UGC | 0 | 0 | 0 | 1 | 0 | 1 | 0 |
| **합계** | 61 | 8 | 19 | 9 | 2 | 99 | — |

등급별 같은 분류 순서: A = 32 / 5 / 14 / 2 / 2 (55), B = 29 / 3 / 5 / 7 / 0 (44). 그 외 설치 카탈로그: Messier 110, Milky Way 1, RCW 147, Solar 14, Star 19, vdB 117. 해당 분류의 독립 행이 없더라도 다른 카탈로그의 교차 표기는 있을 수 있다.

## 후보별 결과

`DB 내부 ID`는 `celestial_objects.id` 실제 값이다. `이름·유형·좌표`는 연결한 DB 레코드별 값으로, 복합 영역의 중심이나 CSV 좌표를 의미하지 않는다. 기준 좌표는 주 ID(이중성단은 양쪽 구성원) 기준이며 DB 별칭을 동일 좌표로 합산하지 않았다.

| CSV 행 | 등급 | 후보명 | 주 번호 / 입력 별칭 | 입력 유형 | 분류 | DB 내부 ID → 이름 · 유형 · RA/Dec | 외부 기준 RA/Dec · Δ | 판정 근거 |
|---:|:---:|---|---|---|---|---|---|---|
| 2 | A | Rosette Nebula | NGC 2237<br>NGC 2238; NGC 2239; NGC 2246; NGC 2244; C49 | Emission nebula/cluster | `MULTIPLE_MATCH` | `NGC2237` → 장미 성운 · 발광성운 · 06h 32m / +04°57'<br>`NGC2238` → NGC 2238 · 발광성운 · 06h 31m / +05°01'<br>`NGC2239` → NGC 2239 · 발광성운 · 06h 32m / +04°51'<br>`NGC2244` → 장미 성단 · 발광성운 · 06h 31m / +04°52'<br>`NGC2246` → NGC 2246 · 발광성운 · 06h 33m / +05°08'<br>`C50` → 장미 성단 · 발광성운 · 06h 31m / +04°52' | 06:30:54.61 / +05:02:57.0 (OpenNGC) · 17.3′ | C49는 NGC2237의 DB 별칭. NGC2237/2238/2246은 성운 영역, NGC2244/C50은 중심 성단(동일 DB 연결). NGC2239는 DB 교차 참조와 OpenNGC에서 NGC2244 계열로 연결되므로 별도 물리 구성으로 중복 계산하지 않음. DB의 성단 유형은 발광성운으로 저장됨. |
| 3 | A | California Nebula | NGC 1499<br>Sh2-220 | Emission nebula | `MATCH` | `NGC1499` → 캘리포니아 성운 · 발광성운 · 04h 03m / +36°22' | 04:03:14.42 / +36:22:02.9 (OpenNGC) · 2.9′ | DB 주 ID·유형과 기준 위치가 부합. DB 미등록 독립 표기/참조: Sh2-220. |
| 4 | A | Heart Nebula | IC 1805<br>Sh2-190; Melotte 15 | Emission nebula/cluster | `MATCH` | `IC1805` → 하트 성운 · 발광성운 · 02h 32m / +61°27' | 02:32:41.51 / +61:27:24.8 (OpenNGC) · 5.0′ | W4 하트 성운 표제와 좌표·유형 일치. Sh2-190·Melotte 15(중심 성단)의 독립 DB 행 미확인. W3/4/5 광역 관계는 아래 참조. |
| 5 | A | Soul Nebula | IC 1848<br>Sh2-199 | Emission nebula | `MULTIPLE_MATCH` | `IC1848` → 영혼 성운 · 발광성운 · 02h 51m / +60°25'<br>`IC1871` → IC 1871 · 발광성운 · 02h 57m / +60°40' | 02:51:10.59 / +60:24:08.9 (OpenNGC) · 1.6′ | W5 소울의 앱 표제 IC1848과 내부 밝은 구역 IC1871(Sh2-201 참조)을 구분. Sh2-199 독립 행 미확인. 원본 후보는 한 건 그대로 유지. |
| 6 | A | North America Nebula | NGC 7000<br>C20; Sh2-117 | Emission nebula | `MATCH` | `NGC7000` → 북아메리카 성운 · 발광성운 · 20h 58m / +44°20' | 20:59:17.14 / +44:31:43.6 (OpenNGC) · 18.1′ | C20 별칭. OpenNGC 중심과 18.1′ 차이는 넓은 성운의 중심 정의 차이 후보. IC5070은 함께 촬영할 수 있는 이웃이지만 본 행의 동의어는 아님. |
| 7 | A | Pelican Nebula | IC 5070 | Emission nebula | `MULTIPLE_MATCH` | `IC5070` → Pelican Nebula · 발광성운 · 20h 51m 00.7s / +44° 24' 05.4"<br>`IC5067` → IC 5067 · 구상성단 · 20h 48m / +44°22' | 20:51:00.72 / +44:24:05.4 (OpenNGC) · 0.0′ | IC5070은 정확히 일치. IC5067은 Pelican 이름을 공유하고 좁은 영역의 분리 레코드이나 DB 유형이 구상성단(외부 Other), 구성 행으로만 포함. IC5068은 약 115′ 떨어진 별도 대상으로 제외. |
| 8 | A | Elephant's Trunk | IC 1396A<br>IC 1396; vdB 142; Sh2-131 | Emission/dark nebula | `MULTIPLE_MATCH` | `IC1396A` → 코끼리 코 성운 A · 발광성운 · - / -<br>`IC1396` → 코끼리 코 성운 · 발광성운 · 21h 39m / +57°30'<br>`vdB142` → vdB 142 · 반사성운 · 21h 37m / +57°30' | — | IC1396A는 코끼리 코 세부 구역(좌표 없음), vdB142는 관련 반사 구역, IC1396은 상위 영역(Sh2-131). IC1396B는 IC1396 토큰에 걸리나 같은 돌출부라는 증거 부족으로 제외. |
| 9 | A | Horsehead region | B 33<br>IC 434; NGC 2023 | Dark/emission nebula complex | `MULTIPLE_MATCH` | `IC434` → 말머리 성운 · 발광성운 · 05h 41m / -02°24'<br>`NGC2023` → NGC 2023 · 반사성운 · 05h 42m / -02°16' | — | B33 암흑 구름 독립 행 없음. IC434는 B33 별칭을 갖지만 실제로는 배경 발광 성운. NGC2023은 사진 영역의 별도 반사성운. NGC2024는 인접 대상(행 10)으로 별도 처리. |
| 10 | A | Flame Nebula | NGC 2024<br>Sh2-277 | Emission nebula | `MATCH` | `NGC2024` → 불꽃 성운 · 발광성운 · 05h 41m 42.57s / -01°51'22.6" | 05:41:42.57 / -01:51:22.6 (OpenNGC) · 0.0′ | NGC2024 이름·좌표가 불꽃 성운과 일치. IC434도 DB 이름 검색에 걸리지만 약 34.3′ 떨어진 배경 성운. Sh2-277의 영역 사용이 자료마다 달라 단일 천체의 엄밀한 동의어로 쓰지 않음. |
| 11 | A | Running Man Nebula | NGC 1977<br>NGC 1973; NGC 1975 | Reflection nebula/cluster | `MULTIPLE_MATCH` | `NGC1977` → NGC 1977 · 발광성운 · 05h 35m / -04°49'<br>`NGC1973` → NGC 1973 · 발광성운 · 05h 35m / -04°44'<br>`NGC1975` → 러닝맨 성운 · 발광성운 · 05h 35m 17.9s / -04° 41' 06.8" | 05:35:15.80 / -04:50:39.6 (OpenNGC) · 4.3′ | 세 인접 레코드가 러닝맨 촬영 영역을 이룸. DB는 발광성운으로 통일했으나 CSV는 반사/성단 혼합, OpenNGC의 중심 NGC1977은 성단+성운. |
| 12 | A | Crescent Nebula | NGC 6888<br>C27; Sh2-105 | Emission nebula | `MATCH` | `NGC6888` → 초승달 성운 · 발광성운 · 20h 12m / +38°21' | 20:12:06.55 / +38:21:17.8 (OpenNGC) · 1.3′ | DB 주 ID·유형과 기준 위치가 부합. DB 미등록 독립 표기/참조: Sh2-105. |
| 13 | A | Bubble Nebula | NGC 7635<br>C11; Sh2-162 | Emission nebula | `POSSIBLE_MATCH` | `NGC7635` → 거품 성운 · 발광성운 · 23h 20m / +61°55' | 23:20:45.60 / +61:12:44.5 (OpenNGC) · 42.6′ | 이름/번호/C11과 유형은 일치하나 DB 적위 +61°55′와 OpenNGC/NASA 기준 약 +61°12′가 42.6′ 어긋남. |
| 14 | A | Wizard Nebula | NGC 7380<br>Sh2-142 | Emission nebula/cluster | `MULTIPLE_MATCH` | `NGC7380` → NGC 7380 · 발광성운 · 22h 48m / +58°04'<br>`Sh2-142` → 발광성운 · 발광성운 · - / - | 22:47:21.01 / +58:07:56.7 (OpenNGC) · 6.5′ | NGC7380(성단+성운 표제)과 그 주변 Sh2-142 영역. Sh2-142 DB 좌표 없음. 두 레코드를 동일 점 좌표에 병합하지 않음. |
| 15 | A | Monkey Head Nebula | NGC 2174<br>Sh2-252 | Emission nebula | `MULTIPLE_MATCH` | `NGC2174` → NGC 2174 · 발광성운 · 06h 09m / +20°38'<br>`NGC2175` → 원숭이 머리 성운 · 발광성운 · 06h 09m 39.6s / +20° 29' 15.3"<br>`IC2159` → IC 2159 · 발광성운 · 06h 10m / +20°26' | 06:09:23.62 / +20:39:34.5 (OpenNGC) · 5.7′ | NASA의 성운 표제는 NGC2174/Sh2-252. 인접 NGC2175도 DB에 원숭이 머리 이름으로 있고 OpenNGC에서 성단+성운으로 분리; 두 좌표 중심이 다름. 이름과 지역 단위 차이를 보존. IC2159는 같은 광역 Sh2-252의 인접 부분으로 추가 기록. |
| 16 | A | Thor's Helmet | NGC 2359<br>C25; Sh2-298 | Emission nebula | `INVALID_OR_UNCERTAIN` | `NGC2359` → NGC 2359 · 발광성운 · 07h 19m / -13°12'<br>`Sh2-298` → 토르의 헬멧 · 발광성운 · - / - | 07:18:30.98 / -13:13:37.9 (OpenNGC) · 7.2′ | 의도한 대상은 NGC2359 및 좌표 없는 Sh2-298. 입력 C25는 다른 천체 NGC2419(구상성단)를 가리켜 복합 구성에서 제외. |
| 17 | A | Pacman Nebula | NGC 281<br>IC 11; Sh2-184 | Emission nebula | `MATCH` | `NGC281` → NGC 281 · 발광성운 · 00h 52m 59.4s / +56° 37' 18.8" | 00:52:59.35 / +56:37:18.8 (OpenNGC) · 0.0′ | DB NGC281은 OpenNGC 좌표와 일치. OpenNGC IC0011은 NGC0281로 가는 중복 항목이며 설치 DB에 IC11 독립 행 없음. |
| 18 | A | Tadpole Nebula | IC 410<br>Sh2-236 | Emission nebula | `MATCH` | `IC410` → 올챙이 성운 · 발광성운 · 05h 22m / +33°24' | 05:22:42.00 / +33:22:00.0 (OpenNGC) · 9.0′ | DB 주 ID·유형과 기준 위치가 부합. DB 미등록 독립 표기/참조: Sh2-236. |
| 19 | A | Flaming Star Nebula | IC 405<br>Sh2-229 | Emission/reflection nebula | `MATCH` | `IC405` → 불꽃별 성운 · 발광성운 · 05h 16m / +34°16' | 05:16:29.48 / +34:21:22.2 (OpenNGC) · 8.1′ | DB 주 ID·유형과 기준 위치가 부합. DB 미등록 독립 표기/참조: Sh2-229. |
| 20 | A | Seagull Nebula | IC 2177<br>Sh2-292; Sh2-296 | Emission nebula complex | `MULTIPLE_MATCH` | `IC2177` → 갈매기 성운 · 반사성운 · 07h 05m / -10°42'<br>`Sh2-296` → Seagull's Wings · 발광성운 · - / -<br>`Sh2-295` → vdB 90 · 발광성운 · 07h 03m / -11°29'<br>`vdB90` → vdB 90 · 반사성운 · 07h 03m / -11°28'<br>`Sh2-297` → vdB 94 · 발광성운 · 07h 05m / -12°20'<br>`vdB94` → vdB 94 · 반사성운 · 07h 05m / -12°20' | 07:04:36.91 / -10:28:15.8 (OpenNGC) · 14.9′ | IC2177은 관용 표제/머리 쪽 표기, Sh2-296은 날개(좌표 없음), Sh2-295/297과 각 vdB90/94는 부속 구역·교차표기. Sh2-292 독립 행 미확인. IC2177의 반사 분류를 영역 전체의 유형으로 확대하지 않음. |
| 21 | A | Cave Nebula | Sh2-155<br>C9 | Emission/reflection/dark complex | `MATCH` | `C9` → 동굴 성운 · 발광성운 · 22h 56m / +62°37' | 22:56:43.2 / +62:37:04 (Sharpless 아틀라스) · 5.0′ | DB 내부 ID C9로 Sh2-155 직접 교차 참조. 두 명칭의 알려진 지역과 DB 좌표가 일치; Sh2-155 독립 DB 행 없음. |
| 22 | A | Cocoon Nebula | IC 5146<br>C19; Sh2-125; B168 | Emission/reflection nebula | `MATCH` | `IC5146` → 고치 성운 · 발광성운 · 21h 53m / +47°16'<br>`C19` → 고치 성운 · 발광성운 · 21h 53m / +47°16' | 21:53:28.76 / +47:16:00.9 (OpenNGC) · 4.9′ | C19는 IC5146의 같은 좌표 별칭 행. Sh2-125는 같은 성운 표기, B168은 연결된 암흑 띠이며 독립 DB 행 미확인. |
| 23 | A | Tulip Nebula | Sh2-101 | Emission nebula | `MATCH` | `Sh2-101` → 발광성운 · 발광성운 · 20h 00m / +35°18' | 19:59:56.8 / +35:17:27 (Sharpless 아틀라스) · 0.9′ | DB 이름은 일반형 ‘발광성운’이지만 Sharpless ID·유형과 외부 위치가 일치. |
| 24 | A | Cat's Paw Nebula | NGC 6334<br>Sh2-8 | Emission nebula | `POSSIBLE_MATCH` | `NGC6334` → 고양이 발 성운 · 초신성잔해 · 17h 19m / -35°57' | 17:20:49.70 / -36:06:09.8 (OpenNGC) · 24.0′ | Cat’s Paw 이름/ID는 일치. CSV·ESA의 별 형성 성운과 달리 DB는 초신성잔해, OpenNGC도 다른 중심을 SNR로 표기(24.0′ 차이). 외부 자료와 정확한 중심/유형의 재확인 필요. NGC6357과는 별개. |
| 25 | A | Lobster Nebula | NGC 6357<br>Sh2-11; Pismis 24 | Emission nebula/cluster | `MATCH` | `NGC6357` → 전쟁과 평화 성운 · 발광성운 · 17h 24m / -34°12' | 17:24:43.57 / -34:12:04.8 (OpenNGC) · 9.0′ | ‘전쟁과 평화’와 Lobster가 같은 성운. Pismis 24는 내부 성단이나 DB 독립 행 미확인. Lobster 이름에 걸린 M17은 다른 좌표의 성운. NGC6334/ Sh2-157과는 별개. |
| 26 | B | Lobster Claw Nebula | Sh2-157 | Emission nebula | `MATCH` | `Sh2-157` → 랍스터 집게 성운 · 발광성운 · 23h 16m / +60°02' | 23:16:03.94 / +60:02:00.9 (SIMBAD) · 0.5′ | Lobster Claw는 NGC6357(Lobster)과 다른 천체. DB 좌표가 SIMBAD 기준과 약 0.5′. |
| 27 | B | Fish Head Nebula | IC 1795 | Emission nebula | `MATCH` | `IC1795` → IC 1795 · 발광성운 · 02h 26m 32.0s / +62° 02' 29.9" | 02:26:31.96 / +62:02:29.9 (OpenNGC) · 0.0′ | W3 성운. 인접 NGC896은 다른 구성 구역으로 본 ID의 대체로 사용하지 않음. |
| 28 | A | Iris Nebula | NGC 7023<br>C4 | Reflection nebula | `POSSIBLE_MATCH` | `NGC7023` → 붓꽃 성운 · 발광성운 · 21h 00m / +68°10' | 21:01:35.62 / +68:10:10.4 (OpenNGC) · 8.9′ | Iris 이름·C4·좌표는 부합하지만 DB는 발광성운, NASA C4는 반사성운으로 설명. |
| 29 | A | Witch Head Nebula | IC 2118<br>Ced 41 | Reflection nebula | `MATCH` | `IC2118` → 마녀머리 성운 · 반사성운 · 05h 06m / -07°13' | 05:04:55.44 / -07:15:56.3 (OpenNGC) · 16.3′ | OpenNGC는 IC2118을 NGC1909 중복 표기로 연결; DB에는 IC2118 한 행. 확장 성운 중심 차이 약 16.3′. |
| 30 | B | Blue Horsehead Nebula | IC 4592 | Reflection nebula | `MATCH` | `IC4592` → 파란 말머리 성운 · 반사성운 · 16h 12m / -19°28' | 16:11:58.67 / -19:27:16.8 (OpenNGC) · 0.8′ | DB 주 ID·유형과 기준 위치가 부합. |
| 31 | A | Rho Ophiuchi complex | IC 4604<br>IC 4603; IC 4605; Barnard clouds | Reflection/dark nebula complex | `MULTIPLE_MATCH` | `IC4604` → rho Oph Nebula · 발광성운 · 16h 25m 31.2s / -23° 26' 11.7"<br>`IC4603` → IC 4603 · 발광성운 · 16h 25m 24.5s / -24° 28' 06.1"<br>`IC4605` → IC 4605 · 발광성운 · 16h 30m 12.5s / -25° 06' 54.6" | 16:25:31.17 / -23:26:11.7 (OpenNGC) · 0.0′ | 세 반사/암흑 구역의 넓은 촬영 범위. DB는 세 행 모두 발광성운으로 기록. ‘Barnard clouds’는 번호 미지정 표현이며 검사한 B42/44/45/51의 독립 행도 미확인. |
| 32 | B | Ghost of Cassiopeia | IC 63<br>IC 59 | Emission/reflection nebula complex | `MULTIPLE_MATCH` | `IC63` → IC 63 · 발광성운 · 00h 59m 28.8s / +60° 54' 42.1"<br>`IC59` → IC 59 · 반사성운 · 00h 57m / +61°09' | 00:59:28.84 / +60:54:42.1 (OpenNGC) · 0.0′ | Ghost의 명명 대상은 IC63. CSV가 IC59도 명시하여 별도 인접 구역으로 포함; 동일 개체 별칭은 아님. |
| 33 | B | Northern Trifid Nebula | NGC 1579 | Emission/reflection nebula | `MATCH` | `NGC1579` → 북쪽 삼렬 성운 · 발광성운 · 04h 30m / +35°16' | 04:30:13.80 / +35:16:10.0 (OpenNGC) · 2.8′ | DB 주 ID·유형과 기준 위치가 부합. |
| 34 | B | NGC 1333 | NGC 1333 | Reflection nebula/star-forming region | `POSSIBLE_MATCH` | `NGC1333` → NGC 1333 · 발광성운 · 03h 29m / +31°25' | 03:28:55.2 / +31:22:12 (OpenNGC) · 3.0′ | ID·좌표는 일치하나 DB 발광성운, CSV 반사성운/별 형성 영역, OpenNGC 성단+성운. 같은 영역에 대한 유형 검증 필요. |
| 35 | B | NGC 1491 | NGC 1491<br>Sh2-206 | Emission nebula | `MATCH` | `NGC1491` → NGC 1491 · 발광성운 · 04h 03m 13.6s / +51° 18' 57.9" | 04:03:13.56 / +51:18:57.9 (OpenNGC) · 0.0′ | DB 주 ID·유형과 기준 위치가 부합. DB 미등록 독립 표기/참조: Sh2-206. |
| 36 | B | NGC 2170 | NGC 2170 | Reflection nebula complex | `MATCH` | `NGC2170` → NGC 2170 · 반사성운 · 06h 08m / -06°24' | 06:07:31.82 / -06:23:57.5 (OpenNGC) · 7.0′ | DB 주 ID·유형과 기준 위치가 부합. |
| 37 | B | NGC 7129 | NGC 7129 | Reflection nebula/cluster | `POSSIBLE_MATCH` | `NGC7129` → NGC 7129 · 발광성운 · 21h 43m / +66°07' | 21:42:59.03 / +66:06:46.7 (OpenNGC) · 0.2′ | 좌표는 일치하나 DB 발광성운, CSV 반사성운/성단, OpenNGC 성단+성운. 같은 영역에 대한 유형 검증 필요. |
| 38 | B | NGC 7822 | NGC 7822<br>Ced 214; Sh2-171 | Emission nebula/cluster | `MULTIPLE_MATCH` | `NGC7822` → NGC 7822 · 발광성운 · 00h 05m / +67°09'<br>`Sh2-171` → 북쪽 삼각형 성운 · 발광성운 · 00h 03m / +67°09' | 00:03:35.35 / +67:09:41.9 (OpenNGC) · 8.2′ | 두 DB 행이 같은 광역 복합체를 가리키나 공간 범위 정의가 다름. Ced 214와 Berkeley 59 독립 행 미확인; NGC7822의 DB 교차 참조가 Sh2-171을 포함. |
| 39 | B | NGC 896 | NGC 896 | Emission nebula | `NOT_FOUND` | — | 02:25:27.82 / +62:01:09.7 (OpenNGC) | NGC896 자체 행·교차 ID 없음. IC1795는 약 7.6′ 인접한 W3 구성원으로 동일 객체가 아님. 관계 표에만 기록. |
| 40 | A | Cone Nebula region | NGC 2264<br>Christmas Tree Cluster; Sh2-273 | Emission/dark nebula/cluster | `MULTIPLE_MATCH` | `NGC2264` → 크리스마스 트리 성단 · 산개성단 · 06h 41m / +09°54'<br>`Sh2-273` → 크리스마스 트리 성운 · 발광성운 · - / - | 06:40:58.25 / +09:53:43.7 (OpenNGC) · 0.5′ | NGC2264는 성단/성운 영역 표제, Sh2-273은 광역 발광 구역(좌표 없음). Cone 암흑 기둥 자체의 독립 행은 미확인. |
| 41 | B | NGC 2023 | NGC 2023 | Reflection nebula | `MATCH` | `NGC2023` → NGC 2023 · 반사성운 · 05h 42m / -02°16' | 05:41:38.39 / -02:15:32.5 (OpenNGC) · 5.4′ | DB 주 ID·유형과 기준 위치가 부합. |
| 42 | B | Fighting Dragons of Ara | NGC 6188<br>RCW 108 | Emission nebula | `MATCH` | `NGC6188` → 가장자리 성운 · 발광성운 · 16h 40m / -48°47' | 16:40:05.84 / -48:39:44.2 (OpenNGC) · 7.3′ | NGC6188의 ID·영역 위치가 부합. RCW108 독립 행 미확인. NGC6193은 주변 성단, NGC6164/6165는 넓은 사진에서 함께 보일 수 있는 다른 대상. |
| 43 | B | NGC 6726/6727 region | NGC 6726<br>NGC 6727; NGC 6729; IC 4812 | Reflection nebula complex | `MULTIPLE_MATCH` | `NGC6726` → NGC 6726 · 반사성운 · 19h 02m / -36°53'<br>`NGC6727` → NGC 6727 · 반사성운 · 19h 02m / -36°53'<br>`NGC6729` → NGC 6729 · 발광성운 · 19h 01m 55.4s / -36° 57' 27.5"<br>`IC4812` → IC 4812 · 발광성운 · 19h 01m / -37°04' | 19:01:39.30 / -36:53:28.7 (OpenNGC) · 4.2′ | 후보가 명시한 네 행. NGC6726/6727의 DB 좌표는 분 단위로 같지만 OpenNGC 세부 중심은 다름. 인근 NGC6723은 별도 구상성단. |
| 44 | A | Spaghetti Nebula | Sh2-240<br>Simeis 147 | Supernova remnant | `POSSIBLE_MATCH` | `Sh2-240` → 발광성운 · 발광성운 · 05h 39m / +28°02' | 05:41:00.2 / +28:06:14 (Sharpless 아틀라스의 영역 중심) · 26.9′ | DB 이름/별칭과 ID는 맞으나 DB는 발광성운, NASA/IAC 자료는 초신성잔해로 분류. |
| 45 | A | Jellyfish Nebula | IC 443<br>Sh2-248 | Supernova remnant | `MATCH` | `IC443` → 해파리 성운 · 초신성잔해 · 06h 17m / +22°47' | 06:16:37.41 / +22:31:54.0 (OpenNGC) · 16.0′ | DB 주 ID·유형과 기준 위치가 부합. DB 미등록 독립 표기/참조: Sh2-248. |
| 46 | A | Veil Nebula complex | NGC 6960<br>NGC 6992; NGC 6995; NGC 6974; NGC 6979; C33/C34 | Supernova remnant complex | `MULTIPLE_MATCH` | `NGC6960` → 서쪽 베일 성운 · 초신성잔해 · 20h 45m 58.2s / +30° 35' 42.5"<br>`NGC6992` → 동쪽 베일 성운 · 초신성잔해 · 20h 56m / +31°43'<br>`NGC6995` → 베일 성운 · 초신성잔해 · 20h 57m 10.8s / +31° 14' 06.6"<br>`NGC6974` → NGC 6974 · 초신성잔해 · 20h 51m / +31°50'<br>`NGC6979` → NGC 6979 · 초신성잔해 · 20h 51m / +32°02'<br>`Sh2-103` → 발광성운 · 발광성운 · - / - | 20:45:58.18 / +30:35:42.5 (OpenNGC) · 0.0′ | 서부 NGC6960=C34, 동부 NGC6992/6995(외부 C33 범위, DB C33은 NGC6992 참조), NGC6974/6979는 내부/북부 필라멘트. C33·C34 별도 DB 행 없음. Sh2-103은 외부 문헌의 상위 Cygnus Loop 표기 후보로 함께 기록했으나 DB에는 좌표가 없고 발광성운으로 저장되어 지역 대응만 인정. |
| 47 | A | Sculptor Galaxy | NGC 253<br>C65 | Galaxy | `MATCH` | `NGC253` → 조각가 은하 · 은하 · 00h 47m / -25°17' | 00:47:33.12 / -25:17:17.6 (OpenNGC) · 7.5′ | ID와 C65 일치. 동일 영문 별칭이 NGC55에도 있지만 다른 위치의 은하로 제외. |
| 48 | A | Needle Galaxy | NGC 4565<br>C38 | Galaxy | `MATCH` | `NGC4565` → 바늘 은하 · 은하 · 12h 36m / +25°59' | 12:36:20.78 / +25:59:15.6 (OpenNGC) · 4.7′ | ID와 C38 일치. 같은 이름이 걸리는 IC3543은 적위가 약 18′ 다른 별도 DB 행. |
| 49 | A | Whale Galaxy | NGC 4631<br>C32 | Galaxy | `MATCH` | `NGC4631` → 고래 은하 · 은하 · 12h 42m / +32°32' | 12:42:08.01 / +32:32:29.4 (OpenNGC) · 1.8′ | DB 주 ID·유형과 기준 위치가 부합. |
| 50 | A | Fireworks Galaxy | NGC 6946<br>C12 | Galaxy | `MATCH` | `NGC6946` → 불꽃놀이 은하 · 은하 · 20h 34m / +60°09' | 20:34:52.32 / +60:09:14.1 (OpenNGC) · 6.5′ | DB 주 ID·유형과 기준 위치가 부합. |
| 51 | A | NGC 891 | NGC 891<br>C23 | Galaxy | `MATCH` | `NGC891` → NGC 891 · 은하 · 02h 22m / +42°21' | 02:22:33.41 / +42:20:56.9 (OpenNGC) · 6.2′ | DB 주 ID·유형과 기준 위치가 부합. |
| 52 | A | NGC 2403 | NGC 2403<br>C7 | Galaxy | `MATCH` | `NGC2403` → NGC 2403 · 은하 · 07h 36m / +65°36' | 07:36:51.40 / +65:36:09.2 (OpenNGC) · 5.3′ | DB 주 ID·유형과 기준 위치가 부합. |
| 53 | A | Centaurus A | NGC 5128<br>C77 | Galaxy | `MATCH` | `NGC5128` → 센타우루스 A · 은하 · 13h 25m / -43°01' | 13:25:27.62 / -43:01:08.8 (OpenNGC) · 5.1′ | DB 주 ID·유형과 기준 위치가 부합. |
| 54 | A | Antennae Galaxies | NGC 4038<br>NGC 4039; C60 | Interacting galaxies | `MULTIPLE_MATCH` | `NGC4038` → 안테나 은하 · 은하 · 12h 01m / -18°52'<br>`C60` → 안테나 은하 · 은하 · 12h 01m / -18°52'<br>`NGC4039` → Antennae Galaxies · 은하 · 12h 01m 53.5s / -18° 53' 10.3"<br>`C61` → Antennae Galaxies · 은하 · 12h 01m 53.5s / -18° 53' 10.3" | 12:01:53.01 / -18:52:03.4 (OpenNGC) · 12.5′ | 상호작용 은하 두 개. C60→NGC4038, C61→NGC4039는 각각 동일 천체의 별칭 행. CSV에 C61은 없지만 DB의 해당 구성 별칭으로 기록. |
| 55 | A | Stephan's Quintet | NGC 7317<br>NGC 7318A/B; NGC 7319; NGC 7320 | Galaxy group | `MULTIPLE_MATCH` | `NGC7317` → NGC 7317 · 은하 · 22h 36m / +33°57'<br>`NGC7318` → NGC 7318A · 은하 · 22h 36m / +33°58'<br>`NGC7319` → NGC 7319 · 은하 · 22h 36m / +33°59'<br>`NGC7320` → NGC 7320A · 은하 · 22h 37m / +33°48' | 22:35:51.88 / +33:56:41.6 (OpenNGC) · 1.7′ | NGC7318 행은 A를 이름으로 사용, B 독립 행 없음. NGC7320 행은 번호상 구성 후보이나 DB 좌표가 SIMBAD NGC7320과 약 14.7′ 차이; 확정 구성에서 보류. NGC7320C는 별체이고 입력에 없음. |
| 56 | B | Deer Lick Group | NGC 7331<br>NGC 7335; NGC 7336; NGC 7337; NGC 7340 | Galaxy/group | `MULTIPLE_MATCH` | `NGC7331` → NGC 7331 · 은하 · 22h 37m / +34°25'<br>`NGC7335` → NGC 7335 · 은하 · 22h 37m / +34°27'<br>`NGC7336` → NGC 7336 · 은하 · 22h 37m / +34°29'<br>`NGC7337` → NGC 7337 · 은하 · 22h 37m / +34°22'<br>`NGC7340` → NGC 7340 · 은하 · 22h 38m / +34°25' | 22:37:04.01 / +34:24:55.9 (OpenNGC) · 0.8′ | 명시한 다섯 은하의 같은 촬영 프레임. 가깝게 보인다는 사실을 물리적으로 결합된 동일 은하로 해석하지 않음. |
| 57 | B | Splinter Galaxy | NGC 5907 | Galaxy | `MATCH` | `NGC5907` → NGC 5907 · 은하 · 15h 15m 53.8s / +56° 19' 43.6" | 15:15:53.77 / +56:19:43.6 (OpenNGC) · 0.0′ | DB 주 ID·유형과 기준 위치가 부합. |
| 58 | B | Barnard's Galaxy | NGC 6822<br>IC 4895 | Irregular galaxy | `MATCH` | `NGC6822` → 바너드 은하 · 은하 · 19h 44m / -14°48'<br>`IC4895` → 바너드 은하 · 은하 · 19h 44m / -14°48' | 19:44:57.74 / -14:48:12.4 (OpenNGC) · 14.0′ | NGC6822·IC4895는 같은 좌표와 대표 ID 연결. C57은 DB 교차 별칭이고 별도 행은 없음. |
| 59 | B | NGC 2903 | NGC 2903 | Galaxy | `MATCH` | `NGC2903` → NGC 2903 · 은하 · 09h 32m / +21°30' | 09:32:10.11 / +21:30:03.0 (OpenNGC) · 2.4′ | DB 주 ID·유형과 기준 위치가 부합. |
| 60 | B | NGC 925 | NGC 925 | Galaxy | `MATCH` | `NGC925` → NGC 925 · 은하 · 02h 27m 16.9s / +33° 34' 45.0" | 02:27:16.88 / +33:34:45.0 (OpenNGC) · 0.0′ | DB 주 ID·유형과 기준 위치가 부합. |
| 61 | A | Hamburger Galaxy | NGC 3628 | Galaxy | `MATCH` | `NGC3628` → 팬케이크 은하 · 은하 · 11h 20m / +13°35' | 11:20:16.97 / +13:35:22.9 (OpenNGC) · 4.1′ | DB 주 ID·유형과 기준 위치가 부합. |
| 62 | B | IC 342 | IC 342<br>C5 | Galaxy | `MATCH` | `IC342` → 숨겨진 은하 · 은하 · 03h 46m / +68°06' | 03:46:48.50 / +68:05:46.9 (OpenNGC) · 4.5′ | DB 주 ID·유형과 기준 위치가 부합. |
| 63 | B | NGC 4236 | NGC 4236<br>C3 | Galaxy | `MATCH` | `NGC4236` → NGC 4236 · 은하 · 12h 16m / +69°28' | 12:16:42.12 / +69:27:45.3 (OpenNGC) · 3.7′ | DB 주 ID·유형과 기준 위치가 부합. |
| 64 | B | NGC 300 | NGC 300<br>C70 | Galaxy | `MATCH` | `NGC300` → NGC 300 · 은하 · 00h 54m / -37°41'<br>`C70` → NGC 300 · 은하 · 00h 54m / -37°41' | 00:54:53.48 / -37:41:03.8 (OpenNGC) · 10.6′ | 동일 천체의 DB 별칭 행: C70 → NGC300. |
| 65 | B | NGC 4945 | NGC 4945<br>C83 | Galaxy | `MATCH` | `NGC4945` → NGC 4945 · 은하 · 13h 05m 27.5s / -49° 28' 05.6"<br>`C83` → NGC 4945 · 은하 · 13h 05m 27.5s / -49° 28' 05.6" | 13:05:27.48 / -49:28:05.6 (OpenNGC) · 0.0′ | 동일 천체의 DB 별칭 행: C83 → NGC4945. |
| 66 | B | NGC 55 | NGC 55<br>C72 | Galaxy | `MATCH` | `NGC55` → NGC 55 · 은하 · 00h 15m / -39°11' | 00:14:53.60 / -39:11:47.9 (OpenNGC) · 1.5′ | DB 주 ID·유형과 기준 위치가 부합. |
| 67 | B | NGC 247 | NGC 247<br>C62 | Galaxy | `MATCH` | `NGC247` → NGC 247 · 은하 · 00h 47m 08.5s / -20° 45' 37.4"<br>`C62` → NGC 247 · 은하 · 00h 47m 08.5s / -20° 45' 37.4" | 00:47:08.55 / -20:45:37.4 (OpenNGC) · 0.0′ | 동일 천체의 DB 별칭 행: C62 → NGC247. |
| 68 | B | Cartwheel Galaxy | ESO 350-40<br>PGC 2248 | Ring galaxy | `NOT_FOUND` | — | 00:37:41.11 / -33:42:58.52 (SIMBAD) | ESO 350-40/PGC 2248와 Cartwheel 이름·보조 번호에서 대응 행 없음. 외부 기준 위치 00:37:41.11 −33:42:58.52. |
| 69 | B | Tadpole Galaxy | UGC 10214<br>Arp 188 | Interacting galaxy | `NOT_FOUND` | — | — | UGC 10214, Arp 188, PGC 57129 및 이름에 해당하는 행 없음. |
| 70 | A | Cat's Eye Nebula | NGC 6543<br>C6 | Planetary nebula | `MATCH` | `NGC6543` → 고양이눈 성운 · 행성상성운 · 17h 58m / +66°38'<br>`C6` → 고양이눈 성운 · 행성상성운 · 17h 58m / +66°38' | 17:58:33.39 / +66:37:59.5 (OpenNGC) · 3.3′ | 동일 천체의 DB 별칭 행: C6 → NGC6543. |
| 71 | A | Helix Nebula | NGC 7293<br>C63 | Planetary nebula | `MATCH` | `NGC7293` → 쌍가락지 성운 · 행성상성운 · 22h 29m / -20°50' | 22:29:38.57 / -20:50:14.4 (OpenNGC) · 9.0′ | DB 주 ID·유형과 기준 위치가 부합. |
| 72 | A | Eskimo Nebula | NGC 2392<br>C39 | Planetary nebula | `MATCH` | `NGC2392` → 에스키모 성운 · 행성상성운 · 07h 29m / +20°55'<br>`C39` → 에스키모 성운 · 행성상성운 · 07h 29m / +20°55' | 07:29:10.76 / +20:54:42.6 (OpenNGC) · 2.5′ | 동일 천체의 DB 별칭 행: C39 → NGC2392. |
| 73 | A | Saturn Nebula | NGC 7009<br>C55 | Planetary nebula | `MATCH` | `NGC7009` → Saturn Nebula · 행성상성운 · 21h 04m 10.8s / -11° 21' 47.7"<br>`C55` → Saturn Nebula · 행성상성운 · 21h 04m 10.8s / -11° 21' 47.7" | 21:04:10.79 / -11:21:47.7 (OpenNGC) · 0.0′ | 동일 천체의 DB 별칭 행: C55 → NGC7009. |
| 74 | B | Blue Snowball Nebula | NGC 7662<br>C22 | Planetary nebula | `MATCH` | `NGC7662` → Copeland's Blue Snowball · 행성상성운 · 23h 25m 53.9s / +42° 32' 05.8"<br>`C22` → Copeland's Blue Snowball · 행성상성운 · 23h 25m 53.9s / +42° 32' 05.8" | 23:25:53.90 / +42:32:05.8 (OpenNGC) · 0.0′ | 동일 천체의 DB 별칭 행: C22 → NGC7662. |
| 75 | B | Blinking Planetary Nebula | NGC 6826<br>C15 | Planetary nebula | `MATCH` | `NGC6826` → 깜박이는 행성상성운 · 행성상성운 · 19h 44m / +50°31'<br>`C15` → 깜박이는 행성상성운 · 행성상성운 · 19h 44m / +50°31' | 19:44:48.11 / +50:31:30.1 (OpenNGC) · 7.7′ | 동일 천체의 DB 별칭 행: C15 → NGC6826. |
| 76 | A | Bug Nebula | NGC 6302<br>C69 | Planetary nebula | `MATCH` | `NGC6302` → Bug Nebula · 행성상성운 · 17h 13m 44.6s / -37° 06' 11.3"<br>`C69` → Bug Nebula · 행성상성운 · 17h 13m 44.6s / -37° 06' 11.3" | 17:13:44.63 / -37:06:11.3 (OpenNGC) · 0.0′ | 동일 천체의 DB 별칭 행: C69 → NGC6302. |
| 77 | B | Southern Ring Nebula | NGC 3132<br>C74 | Planetary nebula | `MATCH` | `NGC3132` → Eight-Burst Nebula · 행성상성운 · 10h 07m 01.7s / -40° 26' 11.7"<br>`C74` → Eight-Burst Nebula · 행성상성운 · 10h 07m 01.7s / -40° 26' 11.7" | 10:07:01.73 / -40:26:11.7 (OpenNGC) · 0.0′ | NGC3132/C74 좌표·유형으로 일치. DB에서 같은 이름이 검색되는 NGC6563은 다른 위치. |
| 78 | B | Skull Nebula | NGC 246<br>C56 | Planetary nebula | `MATCH` | `NGC246` → NGC 246 · 행성상성운 · 00h 47m 03.4s / -11° 52' 19.0"<br>`C56` → NGC 246 · 행성상성운 · 00h 47m 03.4s / -11° 52' 19.0" | 00:47:03.36 / -11:52:19.0 (OpenNGC) · 0.0′ | 동일 천체의 DB 별칭 행: C56 → NGC246. |
| 79 | B | Medusa Nebula | Abell 21<br>Sh2-274 | Planetary nebula | `NOT_FOUND` | — | 07:29:06.4 / +13:15:43 (Sharpless 아틀라스) | Abell 21 / Sh2-274 / PN A66 21 및 이름 대응 없음. ESO가 동일 천체로 확인. |
| 80 | B | Ghost of Jupiter | NGC 3242<br>C59 | Planetary nebula | `MATCH` | `NGC3242` → Jupiter's Ghost Nebula · 행성상성운 · 10h 24m 46.1s / -18° 38' 32.0"<br>`C59` → Jupiter's Ghost Nebula · 행성상성운 · 10h 24m 46.1s / -18° 38' 32.0" | 10:24:46.08 / -18:38:32.0 (OpenNGC) · 0.0′ | 동일 천체의 DB 별칭 행: C59 → NGC3242. |
| 81 | B | Bow-Tie Nebula | NGC 40<br>C2 | Planetary nebula | `POSSIBLE_MATCH` | `NGC40` → 불꽃별 성운 · 행성상성운 · 05h 16m / +34°16' | 00:13:01.03 / +72:31:19.0 (OpenNGC) · 3195.7′ | NGC40/C2 번호·행성상성운 유형은 맞지만 DB 이름과 좌표가 IC405(Flaming Star)와 동일. 실제 NGC40 J2000 좌표와 약 53.26° 차이. |
| 82 | A | Double Cluster | NGC 869<br>NGC 884; C14 | Open cluster pair | `MATCH` | `C14` → 이중 성단 · 산개성단 · 02h 19m / +57°08' | NGC869 02:18:58.56 / +57:07:02.1<br>NGC884 02:22:32.10 / +57:08:38.8 | 이중 성단 전체를 정확히 가리키는 집계 행. NGC869·884 독립 DB 레코드는 없음. DB 좌표는 두 성단 중 NGC869 쪽에 가까움; C14를 둘 중 하나의 동의어로 저장하지 말 것. |
| 83 | A | Owl Cluster | NGC 457<br>C13 | Open cluster | `MATCH` | `NGC457` → 올빼미 성단 · 산개성단 · 01h 19m / +58°20'<br>`C13` → 올빼미 성단 · 산개성단 · 01h 19m / +58°20' | 01:19:32.65 / +58:17:26.5 (OpenNGC) · 5.0′ | 동일 천체의 DB 별칭 행: C13 → NGC457. |
| 84 | A | Caroline's Rose Cluster | NGC 7789<br>C40 | Open cluster | `INVALID_OR_UNCERTAIN` | `NGC7789` → NGC 7789 · 산개성단 · 23h 57m / +56°43' | 23:57:24.06 / +56:42:29.8 (OpenNGC) · 3.3′ | 의도한 NGC7789 산개성단은 존재. 입력 C40은 DB와 NASA에서 NGC3626 은하로 확인되어 제외. |
| 85 | A | Jewel Box Cluster | NGC 4755<br>C94 | Open cluster | `MATCH` | `NGC4755` → Herschel's Jewel Box · 산개성단 · 12h 53m 37.1s / -60° 21' 22.7"<br>`C94` → Herschel's Jewel Box · 산개성단 · 12h 53m 37.1s / -60° 21' 22.7" | 12:53:37.08 / -60:21:22.7 (OpenNGC) · 0.0′ | 동일 천체의 DB 별칭 행: C94 → NGC4755. |
| 86 | B | Wishing Well Cluster | NGC 3532<br>C91 | Open cluster | `MATCH` | `NGC3532` → Wishing Well Cluster · 산개성단 · 11h 05m 47.8s / -58° 46' 13.8"<br>`C91` → Wishing Well Cluster · 산개성단 · 11h 05m 47.8s / -58° 46' 13.8" | 11:05:47.82 / -58:46:13.8 (OpenNGC) · 0.0′ | 동일 천체의 DB 별칭 행: C91 → NGC3532. |
| 87 | B | NGC 663 | NGC 663<br>C10 | Open cluster | `MATCH` | `NGC663` → NGC 663 · 산개성단 · 01h 46m 16.0s / +61° 13' 05.5"<br>`C10` → NGC 663 · 산개성단 · 01h 46m 16.0s / +61° 13' 05.5" | 01:46:16.05 / +61:13:05.5 (OpenNGC) · 0.0′ | 동일 천체의 DB 별칭 행: C10 → NGC663. |
| 88 | B | NGC 188 | NGC 188<br>C1 | Open cluster | `MATCH` | `NGC188` → NGC 188 · 산개성단 · 00h 44m / +85°20'<br>`C1` → NGC 188 · 산개성단 · 00h 44m / +85°20' | 00:47:27.53 / +85:16:10.7 (OpenNGC) · 5.7′ | 동일 천체의 DB 별칭 행: C1 → NGC188. |
| 89 | B | Tau Canis Majoris Cluster | NGC 2362 | Open cluster | `MATCH` | `NGC2362` → NGC 2362 · 산개성단 · 07h 18m 41.5s / -24° 57' 15.1"<br>`C64` → NGC 2362 · 산개성단 · 07h 18m 41.5s / -24° 57' 15.1" | 07:18:41.47 / -24:57:15.1 (OpenNGC) · 0.0′ | 동일 천체의 DB 별칭 행: C64 → NGC2362. |
| 90 | A | Omega Centauri | NGC 5139<br>C80 | Globular cluster | `MATCH` | `NGC5139` → 오메가 센타우리 · 구상성단 · 13h 26m / -47°29'<br>`C80` → 오메가 센타우리 · 구상성단 · 13h 26m / -47°29' | 13:26:45.89 / -47:28:36.7 (OpenNGC) · 7.8′ | 동일 천체의 DB 별칭 행: C80 → NGC5139. |
| 91 | A | 47 Tucanae | NGC 104<br>C106 | Globular cluster | `MATCH` | `NGC104` → 47 Tuc Cluster · 구상성단 · 00h 24m 05.4s / -72° 04' 53.2"<br>`C106` → 47 Tuc Cluster · 구상성단 · 00h 24m 05.4s / -72° 04' 53.2" | 00:24:05.36 / -72:04:53.2 (OpenNGC) · 0.0′ | 동일 천체의 DB 별칭 행: C106 → NGC104. |
| 92 | B | NGC 6397 | NGC 6397<br>C86 | Globular cluster | `MATCH` | `NGC6397` → NGC 6397 · 구상성단 · 17h 40m 41.4s / -53° 40' 25.3"<br>`C86` → NGC 6397 · 구상성단 · 17h 40m 41.4s / -53° 40' 25.3" | 17:40:41.36 / -53:40:25.3 (OpenNGC) · 0.0′ | 동일 천체의 DB 별칭 행: C86 → NGC6397. |
| 93 | B | NGC 6752 | NGC 6752<br>C93 | Globular cluster | `MATCH` | `NGC6752` → NGC 6752 · 구상성단 · 19h 10m 51.8s / -59° 58' 54.7"<br>`C93` → NGC 6752 · 구상성단 · 19h 10m 51.8s / -59° 58' 54.7" | 19:10:51.78 / -59:58:54.7 (OpenNGC) · 0.0′ | 동일 천체의 DB 별칭 행: C93 → NGC6752. |
| 94 | A | Pipe Nebula complex | B 59<br>B 65; B 66; B 67; B 78 | Dark nebula complex | `NOT_FOUND` | — | — | B59/65/66/67/78 및 LDN 1746/1773 독립 행 없음. 후보는 여러 암흑 구름으로 구성된 Pipe 전체. |
| 95 | A | Coalsack Nebula | Caldwell 99 | Dark nebula | `POSSIBLE_MATCH` | `C99` → Caldwell 99 · 은하 · - / - | — | C99 ID는 맞지만 DB 타입 ‘은하’, 좌표 없음. NASA C99는 Coalsack 암흑성운. |
| 96 | B | Snake Nebula | B 72 | Dark nebula | `NOT_FOUND` | — | — | B72 및 LDN66에 해당하는 행 없음. |
| 97 | A | Barnard's E Nebula | B 142<br>B 143 | Dark nebula | `NOT_FOUND` | — | — | B142와 B143에 해당하는 행 모두 없음. 같은 숫자의 vdB 천체는 번호 체계가 달라 제외. |
| 98 | B | Ink Spot Nebula | B 86<br>NGC 6520 vicinity | Dark nebula | `NOT_FOUND` | — | — | B86 암흑성운 없음. NGC6520은 인접 산개성단(‘vicinity’), 대체 불가. |
| 99 | B | Barnard 68 | B 68 | Dark nebula | `NOT_FOUND` | — | — | B68 및 LDN57에 해당하는 행 없음. |
| 100 | B | Dark Shark Nebula | LDN 1235<br>vdB 150 | Dark nebula | `MULTIPLE_MATCH` | `vdB149` → vdB 149 · 반사성운 · 22h 09m / +72°53'<br>`vdB150` → vdB 150 · 발광성운 · - / - | — | LDN1235 암흑 중심은 독립 행 없음. APOD가 같은 촬영 프레임에 명시한 두 반사성운만 확인. vdB150은 DB에 좌표가 없고 발광성운으로 있어 별도 주의. |

## 복합 촬영 영역과 구성원

아래 표는 기존 후보 간 관계 또는 후보별 물리 구성/DB 별칭을 구분한다. 부속 행의 포함은 중심 천체와의 동일성이나 데이터 병합을 뜻하지 않는다.

| CSV 행·영역 | 개별 객체와 관계 |
|---|---|
| 2 · 장미 | `NGC2237`, `NGC2238`, `NGC2246`은 성운 부분. `NGC2244`는 중심 성단이며 `C50`과 `NGC2239` 대응을 중복 성단으로 세지 않는다. `C49`는 DB에서 성운 쪽 교차 표기. [NASA Rosette](https://science.nasa.gov/image-article/apod-2025-july-16-the-rosette-nebula-from-decam/) |
| 4/5/27/39 · 하트·소울 광역 | `IC1805`=W4, `IC1848`=W5 표제, `IC1871`=W5 내부 부분, `IC1795`=W3 구성. `NGC896`은 W3의 별도 구역이나 DB 없음. Melotte 15의 독립 행은 없으며, 같은 화면에 보일 수 있는 `NGC1027`을 하트의 일치 ID로 쓰지 않았다. [ESA 복합체](https://www.esa.int/ESA_Multimedia/Images/2017/09/Herschel_s_view_of_new_stars_and_molecular_clouds) · [W3 연구](https://doi.org/10.1088/0004-6256/150/3/80) · [IC1871](https://apod.nasa.gov/apod/ap181128.html) |
| 6/7 · 북아메리카·펠리컨 | `NGC7000`과 `IC5070`은 다른 후보. `IC5067`은 `IC5070` 내부 능선. [NASA APOD Pelican](https://apod.nasa.gov/apod/ap071019.html) |
| 8 · 코끼리 코 | `IC1396` 상위 영역 → `IC1396A` 어두운 돌출부, `vdB142` 관련 반사 구역. `IC1396B`는 다른 레코드. [Spitzer 연구](https://arxiv.org/abs/astro-ph/0406308) |
| 9/10/41 · 말머리 주변 | B33 실물과 `IC434` 배경은 동일 천체가 아니다. `NGC2023`은 반사성운, `NGC2024`는 넓은 프레임에서 함께 촬영하는 독립 후보. [NASA APOD Horsehead](https://science.nasa.gov/image-article/apod-2023-november-20-the-horsehead-nebula/) |
| 11, 14, 15 · 성운+성단 영역 | 러닝맨 `NGC1973/1975/1977`; Wizard `NGC7380`과 `Sh2-142`; Monkey Head `NGC2174/2175`와 광역 영역 내 `IC2159`. 각 후보의 행은 나누지 않았다. [NASA Monkey Head](https://science.nasa.gov/asset/hubble/pillars-in-the-monkey-head-nebula/) · [Sh2-252 연구](https://arxiv.org/abs/1103.2293) |
| 20 · 갈매기 | `IC2177` 관용 표제, `Sh2-296` 날개, `Sh2-295`/`vdB90` 및 `Sh2-297`/`vdB94` 부속 영역과 관련 표기. `Sh2-292` 독립 DB 행 없음. [ESO](https://eso.org/public/news/eso1913/) |
| 24/25/26 · 고양이발·랍스터 | `NGC6334`와 `NGC6357`은 전갈자리에서 한 프레임에 함께 찍히는 **서로 다른 성운**. Pismis 24는 후자의 내부 성단(독립 행 없음). `Sh2-157`(Lobster Claw)은 별도 위치의 후보. [ESA 공동 프레임](https://www.esa.int/ESA_Multimedia/Images/2016/04/Herschel_s_view_of_the_War_and_Peace_and_Cat_s_Paw_nebulas) · [Pismis 24](https://www.esa.int/media/glittering-glimpse-of-star-birth) |
| 31/32/38/40/43 · 기타 복합 성운 | Rho Oph `IC4603/4604/4605`; Cassiopeia `IC63`와 `IC59`(별개); `NGC7822`와 `Sh2-171`(상·하위 범위 유의); Cone 주변 `NGC2264`와 `Sh2-273`; 크라운오스트랄리스 `NGC6726/6727/6729` 및 `IC4812`. 포함 또는 인접 관계는 후보 표 참조. [ESA IC63](https://esahubble.org/news/heic1818/) |
| 46 · 베일 | `NGC6960` 서쪽, `NGC6992/6995` 동쪽, `NGC6974/6979` 내부·북쪽. `Sh2-103`은 광역 DB 후보며 좌표와 유형이 불완전하다. [NASA 동쪽 베일](https://science.nasa.gov/mission/hubble/science/explore-the-night-sky/hubble-caldwell-catalog/caldwell-33/) |
| 54/55/56 · 복합 은하 | 안테나 두 은하와 각각의 `C60/C61`; 스테판 관련 `NGC7317/7318/7319` 및 보류 `NGC7320`, 7318B 독립 행 없음; Deer Lick `NGC7331/7335/7336/7337/7340`의 투영 프레임. [NASA 스테판](https://science.nasa.gov/asset/hubble/stephans-quintet-5/) |
| 82 · 이중 성단 | `C14`는 두 산개성단을 한 행으로 나타낸 것. `NGC869`와 `NGC884`의 개별 행을 찾지 못했다. [NASA Caldwell](https://science.nasa.gov/mission/hubble/science/explore-the-night-sky/hubble-caldwell-catalog/) |
| 94/97/100 · 암흑성운 프레임 | Pipe 다섯 Barnard 성분과 Barnard E 두 성분의 DB 행은 미확인. Dark Shark는 `LDN1235` 자체 미확인, `vdB149`와 `vdB150`만 같은 프레임의 관련 행. [ESO Pipe](https://www.eso.org/public/images/yb/) · [NASA APOD Shark](https://science.nasa.gov/image-article/apod-2025-march-18-ldn-1235-the-shark-nebula/) |

## 미발견·입력 보류 목록

**NOT_FOUND (9):** 39 NGC 896 (NGC 896, B); 68 Cartwheel Galaxy (ESO 350-40, B); 69 Tadpole Galaxy (UGC 10214, B); 79 Medusa Nebula (Abell 21, B); 94 Pipe Nebula complex (B 59, A); 96 Snake Nebula (B 72, B); 97 Barnard's E Nebula (B 142, A); 98 Ink Spot Nebula (B 86, B); 99 Barnard 68 (B 68, B).

**INVALID_OR_UNCERTAIN (2):** 16 Thor's Helmet (NGC 2359, A); 84 Caroline's Rose Cluster (NGC 7789, A). 의도한 DB 행은 후보 표에 표시했지만, 잘못된 입력 별칭을 채택하지 않았다.

**POSSIBLE_MATCH (8):** 13 Bubble Nebula → `NGC7635`; 24 Cat's Paw Nebula → `NGC6334`; 28 Iris Nebula → `NGC7023`; 34 NGC 1333 → `NGC1333`; 37 NGC 7129 → `NGC7129`; 44 Spaghetti Nebula → `Sh2-240`; 81 Bow-Tie Nebula → `NGC40`; 95 Coalsack Nebula → `C99`.

## 이름·번호·좌표 충돌

| 사례 | 확인 결과 |
|---|---|
| 13 · Bubble | `NGC7635` DB +61°55′ vs OpenNGC +61°12′44.5″. NASA 촬영 위치도 +61°12′ 부근. 주변 `Sh2-159`가 더 가깝지만(35.1′) 다른 식별자이므로 대체하지 않았다. [NASA 좌표](https://science.nasa.gov/asset/hubble/bubble-nebula-ngc-7635/) |
| 16 · Thor | CSV `C25`는 `NGC2419` 구상성단. `NGC2359`와 적위·종류 모두 다름. [NASA Caldwell 25](https://science.nasa.gov/mission/hubble/science/explore-the-night-sky/hubble-caldwell-catalog/caldwell-25/) |
| 24/28/34/37/44 · 유형 | `NGC6334`, `NGC7023`, `NGC1333`, `NGC7129`, `Sh2-240`은 위치·식별자가 상당 부분 부합하지만 대상 유형이 충돌. [ESA Cat’s Paw](https://www.esa.int/ESA_Multimedia/Images/2016/04/Herschel_s_view_of_the_War_and_Peace_and_Cat_s_Paw_nebulas) · [NASA Iris](https://science.nasa.gov/mission/hubble/science/explore-the-night-sky/hubble-caldwell-catalog/caldwell-4/) · [IAC Spaghetti](https://www.iac.es/es/divulgacion/galeria-multimedia/elemento-multimedia/remnant-supernova-sharpless-2-240-simeis-147-or-spaghetti-nebula) |
| 7/10/25/47/48/77 · 이름 중복 | `IC5067`은 펠리컨 내부로 포함하되 DB의 구상성단 유형은 채택하지 않음. `IC434`(Flame), `M17`(Lobster), `NGC55`(Sculptor), `IC3543`(Needle), `NGC6563`(Southern Ring)은 이름 검색 결과로만 확인하여 해당 대상과 동일시하지 않았다. |
| 39 · NGC896 | 외부 기준과 DB `IC1795`가 약 7.6′ 떨어짐. 연구 문헌에서 다른 W3 구성 구역으로 구분되어 매칭하지 않았다. [W3 연구](https://doi.org/10.1088/0004-6256/150/3/80) |
| 55 · NGC7320 | DB `NGC7320` / `22h 37m +33°48′`와 [SIMBAD NGC7320](https://simbad.cds.unistra.fr/simbad/sim-basic?Ident=NGC+7320)의 `22:36:03.41 +33:56:53.6`은 약 14.7′ 차이. 다른 그룹 행들도 같은 시분 단위로 반올림되어 좌표 근접만으로 대응시키지 않았다. |
| 81 · Bow-Tie | `NGC40` DB가 ‘불꽃별 성운’ 및 `05h 16m +34°16′`을 사용해 `IC405`와 겹친다. [NASA Caldwell 2](https://science.nasa.gov/mission/hubble/science/explore-the-night-sky/hubble-caldwell-catalog/caldwell-2/)와 OpenNGC는 NGC40/세페우스자리(약 53.26° 차이)를 지지한다. |
| 84 · Caroline’s Rose | `C40`은 `NGC3626` 은하이며 `NGC7789` 산개성단과 무관. [NASA Caldwell 40](https://science.nasa.gov/mission/hubble/science/explore-the-night-sky/hubble-caldwell-catalog/caldwell-40/) |
| 95 · Coalsack | `C99` 행은 이름 ‘Caldwell 99’, 유형 은하, 좌표 없음. [NASA Caldwell 99](https://science.nasa.gov/mission/hubble/science/explore-the-night-sky/hubble-caldwell-catalog/caldwell-99/)는 암흑성운을 가리키므로 해당 DB 행을 확정하지 않았다. |

대표 공간 확인: Cartwheel과 가장 가까운 저장 좌표의 천체는 `NGC131` (99.8′), Medusa는 `NGC2395` (36.8′)였으며 기록된 이름과 유형상 같은 천체가 아니다. `NOT_FOUND`는 이 설치 DB에서 확인하지 못했다는 뜻이며, 다른 기기·NAS 카탈로그나 모든 외부 카탈로그에 천체가 없다는 뜻이 아니다.

DB, 카탈로그, 소스 코드, A/B 등급과 Messier 표시 정책은 변경하지 않았다.
