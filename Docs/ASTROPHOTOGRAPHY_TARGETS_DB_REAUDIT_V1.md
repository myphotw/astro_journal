# AstroJournal 유명 천체사진 대상 설치 DB 재대조 v1

## 범위와 결론

원본 검토 CSV **21개 데이터 행**을 **20개 검토 단위**로 재대조했다. NGC 896 검토 행 1·13만 묶었고, 서로 다른 천체인 NGC 896과 IC 1795를 병합하지 않았다. 검토 단위 20개 중 대상에 대응하는 DB 레코드를 확인한 것은 **11개**다(주 ID 10개와 W3 묶음의 IC 1795 1개). 이름·좌표가 훼손된 `NGC40` 식별자 행까지 포함하면 관련 DB 행을 찾은 단위는 **12개**다. 단, NGC 896 자체의 독립 행은 없고, 이 사실은 별칭 정정 건에 별도로 기록했다.

| 최종 상태 | 건수 | 판정 대상 |
| --- | ---: | --- |
| CONFIRMED | 0 | 별도 조치 없는 검토 단위 없음 |
| ALIAS_CORRECTION | 3 | NGC 896 / IC 1795, Thor’s Helmet, Caroline’s Rose |
| DB_COORDINATE_ERROR | 1 | Bubble Nebula |
| DB_IDENTITY_ERROR | 1 | Bow-Tie Nebula |
| TYPE_REVIEW | 7 | Coalsack, Cat’s Paw, Iris, NGC 1333, NGC 7129, Spaghetti, NGC 2244 |
| ALREADY_REGISTERED | 0 | 미등록 후보가 다른 ID로 존재한다는 증거 없음 |
| NOT_REGISTERED | 8 | Cartwheel, Tadpole, Medusa, Pipe, B72, B142/B143, B86, B68 |
| UNVERIFIED | 0 | 검토 단위 전체 판정 보류 없음. 일부 세부 관계·광역 중심은 아래에 별도 보류 표시 |

상태는 검토 단위마다 한 가지다. 예를 들어 C99는 좌표가 **없는** 유형 재검토, NGC 40은 좌표도 틀리지만 다른 천체의 이름과 좌표가 함께 연결된 식별 오류다. 부수 문제는 해당 항목에만 기록했고 상태 건수에 중복 포함하지 않았다. `NOT_REGISTERED`는 이 설치 DB의 카탈로그에서 발견되지 않았다는 뜻이지 후보에서 제외한다는 뜻이 아니다.

## 입력 및 DB 무결성

| 입력 | 위치와 사용 범위 |
| --- | --- |
| 검토 원본 | `C:\Users\user\Downloads\astrophotography_targets_review_register_v1.csv` · 21행 · SHA-256 `043AFFC5C5404EF1CBFDA731CE6FB52B52AE1A37F4187A1AF06C1C0F67526D5B` |
| 기존 후보 원본 | `C:\Users\user\Downloads\astrophotography_targets_candidate_v1.csv` · 99행 · SHA-256 `76E089CFE7C64416F73D104D3330C0B1A2B4976BFE82482F5E4A444B0487211A` |
| 기존 대조 결과 | [ASTROPHOTOGRAPHY_TARGETS_DB_AUDIT_V1.md](ASTROPHOTOGRAPHY_TARGETS_DB_AUDIT_V1.md) · 기존 대상·구성원과 비교. 1차 문서는 설치 DB 이름과 스키마·행 수를 기록하지만 절대 경로는 본문에 없으므로, 당시 조회 경로 및 [Windows 앱 DB 경로 결정 코드](../lib/core/database/sqflite_bootstrap.dart)로 동일 파일임을 확인 |
| 실제 대조 DB | `C:\Users\user\AppData\Roaming\com.example\astro_journal\databases\astro_journal.db` · `user_version=36` · 천체 13,562행 · 기준 코드 HEAD `0cb1281` |
| 프로젝트 번들 seed | `D:\999. etc\astro_journal\assets\database\catalog_seed.db` · `user_version=0` · 11,218,944바이트 · SHA-256 `D235AA29E12A3BFB83A5B6813C986040FE30480B2021CBD61A869D37477B083F` |

설치 DB는 SQLite `readOnly: true`로 열고 `PRAGMA query_only=ON`을 적용했다(`query_only=1` 확인). 데이터는 `SELECT`로만 읽었으며 촬영·장비·동기화 레코드는 조회하지 않았다. 설치 DB의 `-wal` 및 `-shm` 파일은 확인 시점에 없었다. NAS는 사용하지 않았다.

| 설치 DB 파일 | 조회 전 | 조회 후 |
| --- | --- | --- |
| 크기 | 17,199,104바이트 | 17,199,104바이트 |
| 수정 시각(UTC) | `2026-11-18T04:04:41.1773611Z` | `2026-11-18T04:04:41.1773611Z` |
| SHA-256 | `E1FF484DF8595D38259A8CC6A931C3E203BFC25FC439EB649451246578D7C276` | `E1FF484DF8595D38259A8CC6A931C3E203BFC25FC439EB649451246578D7C276` |

두 DB의 천체 카탈로그별 행 수는 동일했다: NGC 7,715, IC 5,163, Sh2 202, Caldwell 74, Messier 110, RCW 147, vdB 117, Solar 14, Star 19, Milky 1. seed에는 천체 테이블만 있고 설치 DB에는 앱 운영 테이블도 있어 스키마와 파일 해시가 다르다. 비교 조회한 `NGC40`, `NGC7635`, `C99`, `NGC6334`, `IC1795`의 이름·유형·좌표는 두 DB에서 같았다. 즉 이 표본의 문제는 설치판에만 나타나지는 않는다. 전체 필드가 두 DB에서 동일하다고 단정하지 않았으며, 판정의 기준은 설치 DB다.

## 대조 방법

- 설치 DB의 `id`, 카탈로그와 번호, 이름·공통명, `aliases_json`, `cross_catalog_refs_json`, `primary_catalog_id`를 비교했다. 대소문자, 공백, 하이픈, 0 패딩, Caldwell/C 및 Barnard/B 표기 차이를 정규화하고, 별칭 배열의 쉼표·세미콜론 결합 표기도 미등록 후보 재검색에 포함했다. 관계를 찾는 데 사용한 교차 참조가 물리적으로 동일함을 보장하지는 않는다.
- 저장된 적경/적위 문자열을 각도로 변환하고 두 위치의 구면 대원거리를 arcmin으로 계산했다. 값은 원래 정밀도에 한계가 있는 DB 좌표로부터 산출한 **비교값**이며, 광역 성운의 영상 중심과 카탈로그 대표점, 또는 성운 중심과 중심별을 구분했다. 좌표 없음(`-/-`)은 0이 아니다.
- 미등록 후보 8개 단위의 13개 기준 지점은 유효 좌표가 있는 설치 DB 13,513행을 비교해 15′ 이내와 최근접 객체를 확인했다. 15′는 후보 검색용이지 동일 천체 판정 기준이나 광역 성운의 외곽 경계가 아니다. 위치가 없는 49개 행도 이름·ID 검색에는 포함했다.
- 아래의 검토/후보 행 번호는 CSV 헤더를 제외한 1부터의 번호다(물리 파일 줄 번호가 필요한 경우 1을 더함). 후보의 A/B 등급과 내용은 변경하지 않았다. NGC 2244의 후보 행 1은 독립 후보가 아니라 Rosette Nebula의 관련 구성원이다.
- CSV의 `matched_db_ids`는 식별자가 대응하는 실제 설치 DB 행이다. `DB_IDENTITY_ERROR`에서는 오염된 행, W3에서는 확인된 IC 1795만 포함한다. `related_db_ids`에는 잘못된 별칭, 다른 구성원, 최근접 배제 행이 들어갈 수 있으며 일치로 세지 않는다. 외부 기준 자료를 둘 이상 표기한 경우 `coordinate_difference_arcmin`은 기본 비교값 하나이며 대체 비교값과 의미는 `notes`에 남겼다.

## 항목별 검토

### A. 별칭 정정

**NGC 896 / IC 1795 (W3) · `ALIAS_CORRECTION`** — 검토 1·13, 후보 26·38.

- 식별자: NGC 896. 관련 표기: Fish Head Nebula (IC 1795); NGC 896은 별도 구역.
- 설치 DB: IC1795: IC 1795 · IC1795: 발광성운 · IC1795: 02h 26m 32.0s / +62° 02' 29.9".
- 외부 기준: W3의 인접 성운·별 형성 구역 · IC1795 02:26:31.96 / +62:02:29.9; NGC896 02:25:27.82 / +62:01:09.7. DB 대비 0.0′.
- 판정: AL 교차목록 5·6번은 LBN 645를 함께 쓰나 연구 논문과 OpenNGC는 구역/중심을 분리. 설치 DB에는 IC1795만 있고 NGC896·NGC0896 직접 ID·별칭은 없음. 0.0′은 IC1795끼리의 비교. NGC896 기준→IC1795 DB는 7.6′. NGC896 원본 검토 두 행을 합쳤지만 후보 CSV의 두 천체를 합치지 않음.
- 권고: W3 구성 관계만 기록. NGC896을 IC1795의 동일 객체 별칭으로 추가하지 않음.
- 출처: [W3 관측 연구](https://doi.org/10.1088/0004-6256/150/3/80) · [Astronomical League 교차목록](https://www.astroleague.org/files/u3/BrightNebulaRev1.pdf) · [OpenNGC 고정본](https://raw.githubusercontent.com/mattiaverga/OpenNGC/be3cd6c5498806a2fbb2f7e0452ef802dbb02be0/database_files/NGC.csv).

**Thor's Helmet · `ALIAS_CORRECTION`** — 검토 2, 후보 15.

- 식별자: NGC 2359. 관련 표기: Sh2-298 (유효); C25 (제외); LBN 1041; GUM 4.
- 설치 DB: NGC2359: NGC 2359; Sh2-298: Sh2-298 (공통명 토르의 헬멧) · NGC2359: 발광성운; Sh2-298: 발광성운 · NGC2359: 07h 19m / -13°12'; Sh2-298: - / -. 비교·배제 행: `NGC2419`.
- 외부 기준: 발광/H II 영역 · NGC2359 07:18:30.98 / -13:13:37.9; NGC2419 07:38:07.95 / +38:52:47.9. DB 대비 7.2′.
- 판정: NGC2359의 DB 교차 참조는 Sh2-298. Sh2-298 독립 행에 좌표가 없고 C25 독립 행도 없음. C25는 NGC2419 구상성단의 별칭으로 정상 연결. 7.2′는 NGC2359↔OpenNGC. Sh2-298 행은 -/- 및 별자리 고물자리, NGC2359 행은 큰개자리로 차이가 있어 보조 확인.
- 권고: 후보 별칭 C25 제거를 검토. Sh2-298 유지.
- 출처: [NASA Caldwell 25](https://science.nasa.gov/mission/hubble/science/explore-the-night-sky/hubble-caldwell-catalog/caldwell-25/) · [OpenNGC 고정본](https://raw.githubusercontent.com/mattiaverga/OpenNGC/be3cd6c5498806a2fbb2f7e0452ef802dbb02be0/database_files/NGC.csv) · [Sharpless 위치 목록](https://reinervogel.net/Sharpless/Sharpless_data_e.html).

**Caroline's Rose Cluster · `ALIAS_CORRECTION`** — 검토 3, 후보 83.

- 식별자: NGC 7789. 관련 표기: Caroline's Rose; White Rose Cluster; C40 (제외).
- 설치 DB: NGC7789: NGC 7789 · NGC7789: 산개성단 · NGC7789: 23h 57m / +56°43'. 비교·배제 행: `C40` · `NGC3626` · `NGC3632`.
- 외부 기준: 산개성단 · NGC7789 23:57:24.06 / +56:42:29.8; C40/NGC3626 11:20:03.81 / +18:21:24.6. DB 대비 3.3′.
- 판정: C40 DB 행의 primary_catalog_id는 NGC3626 은하. NGC3632는 OpenNGC·DB의 NGC3626 역사 교차 ID로 추적되며 성단과 무관. 오류는 후보 별칭에 있음. DB는 C40을 은하에 연결.
- 권고: 후보 별칭 C40 제거를 검토. NGC7789 유지.
- 출처: [NASA Caldwell 40](https://science.nasa.gov/mission/hubble/science/explore-the-night-sky/hubble-caldwell-catalog/caldwell-40/) · [OpenNGC 고정본](https://raw.githubusercontent.com/mattiaverga/OpenNGC/be3cd6c5498806a2fbb2f7e0452ef802dbb02be0/database_files/NGC.csv).

### B. DB 오류 의심

**Bubble Nebula · `DB_COORDINATE_ERROR`** — 검토 4, 후보 12.

- 식별자: NGC 7635. 관련 표기: C11; Sh2-162; LBN 548.
- 설치 DB: NGC7635: 거품 성운 · NGC7635: 발광성운 · NGC7635: 23h 20m / +61°55'.
- 외부 기준: 발광/H II 성운 · OpenNGC 23:20:45.60 / +61:12:44.5; NASA Hubble 23:20:48.3 / +61:12:06.12. DB 대비 42.6′.
- 판정: DB 이름·NGC·C11·천체 유형이 일치. OpenNGC와 Hubble 촬영 위치 모두 DB보다 남쪽 약 43′. Sh2-162 독립 DB 행/별칭 없음. 좌표차 열은 OpenNGC와 비교. Hubble 기준 43.3′. 사진 중심과 카탈로그 중심은 서로 다른 기준.
- 권고: 후속 작업에서 원본 좌표의 유입 경로와 수정 범위 확인.
- 출처: [NASA Hubble 관측 위치](https://science.nasa.gov/asset/hubble/bubble-nebula-ngc-7635/) · [NASA Caldwell 11](https://science.nasa.gov/mission/hubble/science/explore-the-night-sky/hubble-caldwell-catalog/caldwell-11/) · [OpenNGC 고정본](https://raw.githubusercontent.com/mattiaverga/OpenNGC/be3cd6c5498806a2fbb2f7e0452ef802dbb02be0/database_files/NGC.csv) · [Sharpless 위치 목록](https://reinervogel.net/Sharpless/Sharpless_data_e.html).

**Bow-Tie Nebula · `DB_IDENTITY_ERROR`** — 검토 5, 후보 80.

- 식별자: NGC 40. 관련 표기: C2; PN G120.0+09.8.
- 설치 DB: NGC40: 불꽃별 성운 · NGC40: 행성상성운 · NGC40: 05h 16m / +34°16'. 비교·배제 행: `IC405`.
- 외부 기준: 행성상성운 · NGC40 00:13:01.03 / +72:31:19.0; IC405 05:16:29.48 / +34:21:22.2. DB 대비 3195.7′.
- 판정: NGC40과 IC405의 DB name·common_name·RA/Dec가 정확히 같음. NGC40의 행성상성운 유형과 C2/Bow-Tie 별칭은 정상. IC405는 잘못 연결된 정보의 대조 행일 뿐 일치 레코드가 아님. 두 올바른 외부 좌표가 다름.
- 권고: NGC40 ID·C2는 유지하고 이름·좌표 및 데이터 공급원을 조사.
- 출처: [NASA Caldwell 2](https://science.nasa.gov/mission/hubble/science/explore-the-night-sky/hubble-caldwell-catalog/caldwell-2/) · [OpenNGC 고정본](https://raw.githubusercontent.com/mattiaverga/OpenNGC/be3cd6c5498806a2fbb2f7e0452ef802dbb02be0/database_files/NGC.csv).

**Coalsack Nebula · `TYPE_REVIEW`** — 검토 6, 후보 94.

- 식별자: Caldwell 99. 관련 표기: C99; Caldwell 99; Coalsack Nebula.
- 설치 DB: C99: Caldwell 99 · C99: 은하 · C99: - / -.
- 외부 기준: 암흑성운/암흑 구름 · SIMBAD 12:31:19.0 / -63:44:36; Caldwell 성도 12h53.0m / -63:00. 동일 대상 DB 좌표가 없어 차이 미계산.
- 판정: NASA는 C99=Coalsack 암흑성운. DB의 ID와 표제는 맞지만 은하로 등록되고 좌표·별자리·크기가 없음. 다른 특정 천체를 복제했다는 증거 없음. 외부 두 표기 간 약 152.4′. DB 좌표가 없으므로 오차 미계산. 좌표 표기 차이만으로 다른 천체라고 판단하지 않음.
- 권고: 은하 분류와 좌표 누락 검토. 광역 영역의 기준 중심은 별도 결정.
- 출처: [NASA Caldwell 99](https://science.nasa.gov/mission/hubble/science/explore-the-night-sky/hubble-caldwell-catalog/caldwell-99/) · [CDS SIMBAD](https://simbad.cds.unistra.fr/simbad/sim-id?Ident=NAME+Coalsack+Nebula) · [Caldwell 성도](https://oaklandastronomy.net/ObservationMaterials/Caldwell_Telrad_Charts.pdf).

### C. 천체 유형

**Cat's Paw Nebula · `TYPE_REVIEW`** — 검토 7, 후보 23.

- 식별자: NGC 6334. 관련 표기: Sh2-8; RCW 127; Gum 64.
- 설치 DB: NGC6334: 고양이 발 성운 · NGC6334: 초신성잔해 · NGC6334: 17h 19m / -35°57'. 비교·배제 행: `NGC6357` · `NGC253`.
- 외부 기준: 발광/H II 별 형성 영역; OpenNGC는 SNR · OpenNGC 17:20:49.70 / -36:06:09.8; ESO 촬영 중심 17:19:58.02 / -35:57:47.06; SIMBAD 17:20:52.42 / -36:07:50.4. DB 대비 24.0′.
- 판정: ESO의 물리 설명은 수소가 이온화되는 별 형성 성운. OpenNGC의 SNR 분류는 설치 DB와 같아 출처 간 불일치. Sh2-8·RCW127 별칭/독립 행 없음. ESO 중심과는 11.8′. 비교 대상 NGC6357은 랍스터 성운, C65는 DB에서도 NGC253으로 연결되어 이 대상의 별칭이 아님.
- 권고: 유형을 검토하고 광역 천체의 기준 중심을 확정하기 전 좌표 오류는 단정하지 않음.
- 출처: [ESO Cat’s Paw와 Lobster](https://www.eso.org/public/news/eso1705/) · [ESO 촬영 중심](https://www.eso.org/public/images/eso1003a/) · [CDS SIMBAD](https://simbad.cds.unistra.fr/simbad/sim-basic?Ident=NGC+6334) · [OpenNGC 고정본](https://raw.githubusercontent.com/mattiaverga/OpenNGC/be3cd6c5498806a2fbb2f7e0452ef802dbb02be0/database_files/NGC.csv) · [Sharpless 위치 목록](https://reinervogel.net/Sharpless/Sharpless_data_e.html) · [NASA Caldwell 65](https://science.nasa.gov/mission/hubble/science/explore-the-night-sky/hubble-caldwell-catalog/caldwell-65/).

**Iris Nebula · `TYPE_REVIEW`** — 검토 8, 후보 27.

- 식별자: NGC 7023. 관련 표기: C4; LBN 487.
- 설치 DB: NGC7023: 붓꽃 성운 · NGC7023: 발광성운 · NGC7023: 21h 00m / +68°10'.
- 외부 기준: 반사성운; OpenNGC 일반 성운(Neb) · 21:01:35.62 / +68:10:10.4. DB 대비 8.9′.
- 판정: NASA Caldwell 4의 반사 성운 설명과 DB 발광성운 유형이 다름. C4는 DB 별칭·교차 참조이고 독립 행 없음.
- 권고: 반사성운 분류를 검토. 같은 객체는 유지.
- 출처: [NASA Caldwell 4](https://science.nasa.gov/mission/hubble/science/explore-the-night-sky/hubble-caldwell-catalog/caldwell-4/) · [OpenNGC 고정본](https://raw.githubusercontent.com/mattiaverga/OpenNGC/be3cd6c5498806a2fbb2f7e0452ef802dbb02be0/database_files/NGC.csv).

**NGC 1333 · `TYPE_REVIEW`** — 검토 9, 후보 33.

- 식별자: NGC 1333. 관련 표기: vdB 17; LBN 741; Embryo Nebula.
- 설치 DB: NGC1333: NGC 1333 · NGC1333: 발광성운 · NGC1333: 03h 29m / +31°25'.
- 외부 기준: 반사성운/별 형성 영역; OpenNGC 성단+성운 · 03:28:55.2 / +31:22:12. DB 대비 3.0′.
- 판정: NASA는 반사성운 안 별 형성 영역. Astronomical League는 R, OpenNGC는 Cl+N, DB는 발광성운. Astronomical League 대표 위치 03h29.3m +31°25′도 별도로 확인.
- 권고: 반사 성운과 포함된 젊은 별 집단을 기술. 동일 ID 유지.
- 출처: [NASA Hubble NGC1333](https://science.nasa.gov/asset/hubble/ngc-1333/) · [Astronomical League 교차목록](https://www.astroleague.org/files/u3/BrightNebulaRev1.pdf) · [OpenNGC 고정본](https://raw.githubusercontent.com/mattiaverga/OpenNGC/be3cd6c5498806a2fbb2f7e0452ef802dbb02be0/database_files/NGC.csv).

**NGC 7129 · `TYPE_REVIEW`** — 검토 10, 후보 36.

- 식별자: NGC 7129. 관련 표기: vdB 146; LBN 497; IC 5134 (DB 교차 참조, 동의어 확정 아님).
- 설치 DB: NGC7129: NGC 7129 · NGC7129: 발광성운 · NGC7129: 21h 43m / +66°07'. 비교·배제 행: `IC5132`.
- 외부 기준: 반사성운+젊은 산개성단/별 형성 영역 · 21:42:59.03 / +66:06:46.7. DB 대비 0.2′.
- 판정: 공개 연구에 젊은 성단과 반사성운이 확인됨. DB IC5132가 LBN 497 및 공통명을 공유하나 별도 ID·좌표. IC5134는 독립 실물 행을 확인하지 못함. IC5132(21h43m +66°10′)는 NGC7129 외부 중심에서 3.2′. 역사적 개별 성분 표기는 별도 검토.
- 권고: 발광성운 분류와 IC 연결을 별도로 재검토. 인접 IC 행은 병합하지 않음.
- 출처: [NGC7129 성단 관측 연구](https://arxiv.org/abs/1503.06230) · [NASA APOD NGC7129](https://science.nasa.gov/image-article/apod-2007-september-13-ngc-7129-and-ngc-7142/) · [OpenNGC 고정본](https://raw.githubusercontent.com/mattiaverga/OpenNGC/be3cd6c5498806a2fbb2f7e0452ef802dbb02be0/database_files/NGC.csv).

**Spaghetti Nebula · `TYPE_REVIEW`** — 검토 11, 후보 43.

- 식별자: Sh2-240. 관련 표기: Simeis 147; SNR G180.0-01.7; LBN 822.
- 설치 DB: Sh2-240: Sh2-240 (공통명 발광성운) · Sh2-240: 발광성운 · Sh2-240: 05h 39m / +28°02'.
- 외부 기준: 초신성 잔해 · 05:41:00.2 / +28:06:14 (Sharpless 관측 목록 중심). DB 대비 26.9′.
- 판정: eROSITA 연구는 SNR로 분류. DB 광역 크기 200′×180′에서 26.9′의 중심차만으로 잘못된 천체 또는 좌표 오기로 보지 않음. 필라멘트의 발광 특성은 물리적 분류 SNR과 구분.
- 권고: 초신성 잔해 유형으로 재검토. 광역 중심 정의는 별도 확인.
- 출처: [eROSITA 관측 연구](https://arxiv.org/abs/2401.17312) · [Sharpless 위치 목록](https://reinervogel.net/Sharpless/Sharpless_data_e.html).

**NGC 2244 · `TYPE_REVIEW`** — 검토 12, 후보 1 (관련 영역).

- 식별자: NGC 2244. 관련 표기: C50; Rosette Cluster; 장미 성운은 상위 촬영 영역.
- 설치 DB: NGC2244: 장미 성단; C50: 장미 성단 · NGC2244: 발광성운; C50: 발광성운 · NGC2244: 06h 31m / +04°52'; C50: 06h 31m / +04°52'. 비교·배제 행: `NGC2237` · `NGC2238` · `NGC2239` · `NGC2246`.
- 외부 기준: 산개성단 · 06:31:55.56 / +04:56:34.6 (OpenNGC). DB 대비 14.6′.
- 판정: C50 primary_catalog_id=NGC2244, 두 DB 행 모두 장미 성단이라는 이름과 동일 좌표이나 발광성운으로 분류됨. 외부 자료는 장미 성운 내부의 산개성단으로 구분. NGC2239는 OpenNGC/DB의 교차 참조와 두 성단을 구분하는 연구가 충돌. 병합 보류. 14.6′는 두 DB 행 모두 동일.
- 권고: 두 로컬 연결 행의 유형 검토. 중심 성단과 C49 성운 분리.
- 출처: [NASA APOD Rosette](https://science.nasa.gov/image-article/apod-2025-july-16-the-rosette-nebula-from-decam/) · [OpenNGC 고정본](https://raw.githubusercontent.com/mattiaverga/OpenNGC/be3cd6c5498806a2fbb2f7e0452ef802dbb02be0/database_files/NGC.csv) · [NGC2244/2239 관측 연구](https://arxiv.org/abs/0901.0833).

### D. 미등록 재검색

**Cartwheel Galaxy · `NOT_REGISTERED`** — 검토 14, 후보 67.

- 식별자: ESO 350-40. 관련 표기: PGC 2248; ESO 350-IG 040; Cartwheel.
- 설치 DB: 대응 행 없음. 비교·배제 행: `NGC131`.
- 외부 기준: 충돌 고리은하 · 00:37:41.11 / -33:42:58.5. 동일 대상 DB 좌표가 없어 차이 미계산.
- 판정: ESO/PGC/공통명 검색 결과 없음. 기준 위치 15′ 안 DB 행 없음. 최근접 NGC131은 99.8′. 근접 DB 행은 매칭이 아님.
- 권고: 현재 설치판 미등록으로 보고. 후보는 유지.
- 출처: [CDS SIMBAD](https://simbad.harvard.edu/simbad/sim-id?Ident=NAME+Cartwheel&Name=NAME+Cartwheel&Radius=submit%3Dsubmit) · [NASA Webb Cartwheel](https://science.nasa.gov/asset/webb/cartwheel-galaxy-nircam-and-miri-composite-compass-image/).

**Tadpole Galaxy · `NOT_REGISTERED`** — 검토 15, 후보 68.

- 식별자: UGC 10214. 관련 표기: Arp 188/APG 188; PGC 57129; VV 29; MCG +09-26-056; 2MASX J16060394+5525313.
- 설치 DB: 대응 행 없음. 비교·배제 행: `NGC6088`.
- 외부 기준: 조석 꼬리가 있는 상호작용 은하 · 16:06:03.91 / +55:25:31.6. 동일 대상 DB 좌표가 없어 차이 미계산.
- 판정: UGC/Arp/PGC 및 정규화 별칭 검색 결과 없음. 15′ 안 DB 행 없음. 최근접 NGC6088(129.1′). 양쪽 자료의 UGC 10214=Arp 188 식별과 좌표는 일관됨.
- 권고: 현재 설치판 미등록으로 보고. 후보는 유지.
- 출처: [CDS SIMBAD](https://simbad.u-strasbg.fr/simbad/sim-id?Ident=Tadpole+Galaxy) · [Spitzer Tadpole 연구](https://arxiv.org/abs/astro-ph/0510788).

**Medusa Nebula · `NOT_REGISTERED`** — 검토 16, 후보 78.

- 식별자: Abell 21. 관련 표기: PN A66 21; Sh2-274; PK 205+14.1; PN G205.1+14.2; Medusa Nebula.
- 설치 DB: 대응 행 없음. 비교·배제 행: `NGC2395`.
- 외부 기준: 행성상성운 · 07:29:02.71 / +13:14:48.6 (중심별). 동일 대상 DB 좌표가 없어 차이 미계산.
- 판정: SIMBAD에서 일반 Abell 21 조회는 00:20:38.75 +28:41:40.5 은하단으로 연결. Medusa는 PN A66 21. 올바른 위치 15′ 안 DB 행 없음. 최근접 NGC2395는 산개성단(36.6′)으로 제외.
- 권고: 현재 설치판 미등록으로 보고. Abell 번호에는 PN 접두어를 명시.
- 출처: [CDS SIMBAD](https://simbad.cds.unistra.fr/simbad/sim-id?Ident=PN+A66+21) · [ESO Medusa](https://www.eso.org/public/news/eso1520/) · [CDS SIMBAD (별도 조회)](https://simbad.u-strasbg.fr/simbad/sim-id?Ident=Abell+21).

**Pipe Nebula complex · `NOT_REGISTERED`** — 검토 17, 후보 93.

- 식별자: B 59. 관련 표기: B59; B65; B66; B67; B78 (복합체 구성원).
- 설치 DB: 대응 행 없음. 비교·배제 행: `NGC6293` · `NGC6355` · `NGC6369`.
- 외부 기준: 암흑성운 복합체 · B59 17:11:23 / -27:29; B65 17:19:36 / -26:42; B66 17:19:57 / -26:53; B67 17:20:57 / -26:51; B78 17:32 / -25:35. 동일 대상 DB 좌표가 없어 차이 미계산.
- 판정: Barnard 및 관련 표기 검색 결과 없음. ESO는 5개를 Pipe 구성원으로 구분. 모든 구성 중심 15′ 안 DB 행 없음. 최근접: B59 NGC6293 57.1′; B65/B66/B67 NGC6355 62.7/63.0/50.7′; B78 NGC6369 116.4′. 중심 근접 검색은 넓은 성운의 외곽까지 검사한 것이 아님.
- 권고: 복합체와 5개 구성원 단위를 구분해서 유지.
- 출처: [ESO Pipe 구성](https://www.eso.org/public/news/eso1233/) · [CDS Barnard 좌표표](https://vizier.cfa.harvard.edu/vizier/ftp/cats/7/220A/barnard.dat) · [CDS 좌표표 정의](https://cdsarc.cds.unistra.fr/viz-bin/ReadMe/VII/220A?format=html&tex=true).

**Snake Nebula · `NOT_REGISTERED`** — 검토 18, 후보 95.

- 식별자: B 72. 관련 표기: Barnard 72; B072; LDN 66; Snake Nebula.
- 설치 DB: 대응 행 없음. 비교·배제 행: `NGC6369`.
- 외부 기준: 암흑성운 · 17:23:35 / -23:37. 동일 대상 DB 좌표가 없어 차이 미계산.
- 판정: Barnard·Lynds·공통명 검색 결과 없음. 15′ 안 DB 행 없음. 최근접 NGC6369(74.9′)는 행성상성운. Pipe 인근에 있지만 Pipe 구성원으로 취급하지 않음.
- 권고: 현재 설치판 미등록으로 보고. B68과 별개의 객체로 유지.
- 출처: [CDS Barnard 좌표표](https://vizier.cfa.harvard.edu/vizier/ftp/cats/7/220A/barnard.dat) · [CDS 좌표표 정의](https://cdsarc.cds.unistra.fr/viz-bin/ReadMe/VII/220A?format=html&tex=true).

**Barnard's E Nebula · `NOT_REGISTERED`** — 검토 19, 후보 96.

- 식별자: B 142. 관련 표기: B142; B143 (두 구성원); Barnard E; TGU H367 (B142).
- 설치 DB: 대응 행 없음. 비교·배제 행: `NGC6803`.
- 외부 기준: 암흑성운 두 개의 촬영 영역 · B142 19:39:41 / +10:31; B143 19:41:25 / +11:00. 동일 대상 DB 좌표가 없어 차이 미계산.
- 판정: 두 Barnard 번호·정규화 별칭을 찾지 못함. 15′ 안 DB 행 없음. NGC6803은 행성상성운. 최근접 NGC6803은 B142에서 131.2′, B143에서 163.9′.
- 권고: B142와 B143을 동의어로 합치지 않고 E 모양 촬영 영역으로 기술.
- 출처: [CDS Barnard 좌표표](https://vizier.cfa.harvard.edu/vizier/ftp/cats/7/220A/barnard.dat) · [CDS 좌표표 정의](https://cdsarc.cds.unistra.fr/viz-bin/ReadMe/VII/220A?format=html&tex=true).

**Ink Spot Nebula · `NOT_REGISTERED`** — 검토 20, 후보 97.

- 식별자: B 86. 관련 표기: Barnard 86; B086; Ink Spot Nebula; NGC 6520 인접 (동의어 아님).
- 설치 DB: 대응 행 없음. 비교·배제 행: `NGC6520`.
- 외부 기준: 암흑성운 · 18:03:01 / -27:52. 동일 대상 DB 좌표가 없어 차이 미계산.
- 판정: 15′ 안 NGC6520만 발견. 약 1.0′ 거리에 있으나 DB와 ESO 모두 별개의 산개성단으로 식별. 인접 행 NGC6520: 18h03m / -27°53′. 이 거리값은 동일 천체 오차가 아님.
- 권고: 인접 성단 NGC6520을 매칭하지 않고 B86 미등록으로 유지.
- 출처: [ESO B86와 NGC6520](https://www.eso.org/public/news/eso1307/) · [CDS Barnard 좌표표](https://vizier.cfa.harvard.edu/vizier/ftp/cats/7/220A/barnard.dat) · [CDS 좌표표 정의](https://cdsarc.cds.unistra.fr/viz-bin/ReadMe/VII/220A?format=html&tex=true).

**Barnard 68 · `NOT_REGISTERED`** — 검토 21, 후보 98.

- 식별자: B 68. 관련 표기: Barnard 68; B068; LDN 57.
- 설치 DB: 대응 행 없음. 비교·배제 행: `NGC6325`.
- 외부 기준: 암흑성운 · 17:22:36 / -23:47 (Barnard 목록). 동일 대상 DB 좌표가 없어 차이 미계산.
- 판정: Barnard·Lynds 별칭 검색 결과 없음. 15′ 안 DB 행 없음. NGC6325(63.2′)는 구상성단. 암흑성운의 위치는 출처가 선택한 피크/중심에 따라 달라질 수 있음.
- 권고: 현재 설치판 미등록으로 보고. B86·B72와 병합하지 않음.
- 출처: [CDS Barnard 좌표표](https://vizier.cfa.harvard.edu/vizier/ftp/cats/7/220A/barnard.dat) · [CDS 좌표표 정의](https://cdsarc.cds.unistra.fr/viz-bin/ReadMe/VII/220A?format=html&tex=true).

## 기존 1차 보고서에서 추가 확인한 6건

이 절의 내용은 위 20개 분류 건수에 포함하지 않는다.

| 대상 | 설치 DB 재조회 및 외부 확인 | 처리 제안 |
| --- | --- | --- |
| Stephan’s Quintet | `NGC7317`, `NGC7318`, `NGC7319`, `NGC7320` 존재. `NGC7318`은 NGC 7318A로 표시되며 OpenNGC A 기준과 0.7′ 차이; 7318B 독립 행은 없다. `NGC7320` 이름·교차 참조에는 ‘NGC 7320A’가 있고, DB `22h37m / +33°48′`와 SIMBAD NGC 7320 `22:36:03.41 / +33:56:53.6`은 **14.7′** 차이. 7320C도 독립 DB 행 없음. [NASA Hubble](https://science.nasa.gov/asset/hubble/stephans-quintet-5/) · [SIMBAD NGC 7320](https://simbad.cds.unistra.fr/simbad/sim-basic?Ident=NGC+7320) · [OpenNGC](https://raw.githubusercontent.com/mattiaverga/OpenNGC/be3cd6c5498806a2fbb2f7e0452ef802dbb02be0/database_files/NGC.csv) | 7320의 이름·좌표 공급원을 별도 검증. 외부 이미지의 앞쪽 은하 NGC 7320 및 별도 7320C를 A 표기로 자동 치환하지 않음. |
| Veil Nebula | 서부 `NGC6960`(C34), 동부 `NGC6992`(C33)·`NGC6995`, 필라멘트 `NGC6974`·`NGC6979`, 인접한 동부 필라멘트 `IC1340`이 각각 존재. 앞의 레코드들은 초신성잔해, 넓은 Cygnus Loop 관계인 `Sh2-103`은 발광성운·좌표 없음. Caldwell 33·34 독립 행 없음. [NASA C33](https://science.nasa.gov/mission/hubble/science/explore-the-night-sky/hubble-caldwell-catalog/caldwell-33/) · [NASA C34](https://science.nasa.gov/mission/hubble/science/explore-the-night-sky/hubble-caldwell-catalog/caldwell-34/) · [Sharpless 위치 목록](https://reinervogel.net/Sharpless/Sharpless_data_e.html) | 상위 촬영 영역과 개별 필라멘트를 분리. `Sh2-103`의 유형·공간 데이터는 별도 검토. |
| Rosette Nebula | `NGC2237`(C49 교차 참조), `NGC2238`, `NGC2246`은 성운 관련. 중앙 `NGC2244`와 연결 행 `C50`은 산개성단이며 DB 두 행 모두 발광성운. `NGC2239`는 DB에서 NGC2244를 교차 참조하고 OpenNGC도 묶지만, 두 성단을 별개로 분석한 연구가 있다. [NASA APOD](https://science.nasa.gov/image-article/apod-2025-july-16-the-rosette-nebula-from-decam/) · [NGC2244/2239 관측 연구](https://arxiv.org/abs/0901.0833) | 광역 성운과 성단을 나눔. 역사적 NGC2239 매핑은 출처 차이를 해소할 때까지 보류. |
| Elephant Trunk | DB `IC1396`은 ‘코끼리 코 성운’·`21h39m / +57°30′`; `IC1396A`와 `IC1396B`는 둘 다 명칭·별칭을 공유하며 좌표 없음. `vdB142`는 반사성운·`21h37m / +57°30′`. 외부 관측은 광역 IC1396 내부의 밝은 테두리 구상체 IC1396A를 Elephant Trunk로 기술한다. [Spitzer 관측 연구](https://arxiv.org/abs/astro-ph/0406308) | `vdB142`는 반사성운 성분/관련 표기로 기록. 광역 IC1396 전체 또는 좌표 없는 IC1396B와 동일 객체로 연결하지 않음. IC1396B의 동일성은 미확인. |
| Horsehead | B33 독립 행 없음. 배경 발광성운 `IC434`에 B33·Horsehead와 **Flame Nebula**가 모두 별칭으로 들어 있음. `NGC2023`은 인접 반사성운, `NGC2024`는 독립된 불꽃 성운이며 그 행에도 Flame Nebula 별칭이 존재. [NASA APOD Horsehead](https://science.nasa.gov/image-article/apod-2023-november-20-the-horsehead-nebula/) · [OpenNGC](https://raw.githubusercontent.com/mattiaverga/OpenNGC/be3cd6c5498806a2fbb2f7e0452ef802dbb02be0/database_files/NGC.csv) | B33 암흑구름과 배경 IC434를 분리. IC434에 중복 연결된 Flame Nebula를 별칭 정정 대상으로 검토. |
| Double Cluster | DB `C14`는 이중 성단·산개성단, `02h19m / +57°08′`. `NGC869`와 `NGC884` 독립 행과 해당 교차 참조는 모두 없음. OpenNGC 기준 각각 `02:18:58.56 / +57:07:02.1`, `02:22:32.10 / +57:08:38.8`; C14 대표점은 각각 1.0′와 28.8′ 떨어짐. [NASA Caldwell 14](https://science.nasa.gov/mission/hubble/science/explore-the-night-sky/hubble-caldwell-catalog/caldwell-14/) · [OpenNGC](https://raw.githubusercontent.com/mattiaverga/OpenNGC/be3cd6c5498806a2fbb2f7e0452ef802dbb02be0/database_files/NGC.csv) | C14를 한 성단의 별칭이 아니라 두 성단의 집계 대상으로 유지. |

## 후속 확인 및 변경하지 않은 사항

1. **우선 검토:** NGC 40 이름·좌표 오염과 NGC 7635 좌표 오차의 원천 데이터 및 배포 경로. 설치·seed에서 같은 값이 확인되지만 발생 시점은 추적하지 않았다.
2. **별칭 검토:** 후보의 C25·C40 연결을 그대로 가져오지 않으며 W3에는 영역 관계를 사용한다. `IC434`의 Flame Nebula, `IC5132`/NGC7129의 LBN 497 공유, `NGC7320`의 ‘A’ 표기는 별도로 검토한다.
3. **유형·광역 중심:** Coalsack의 대표점, Cat’s Paw의 출처별 유형과 좌표, Simeis 147의 중심, NGC 2239 역사적 식별이 남아 있다. 차이가 있다는 사실을 기록했으며 자동 덮어쓰기나 병합 근거로 삼지 않는다.
4. **미등록:** 새 레코드 생성·후보 제외는 이번 단계에서 하지 않았다. 향후 검토 시 광역 촬영 영역과 구성원의 관계를 별도로 저장할지 먼저 결정한다.

생성한 결과는 이 보고서와 [대조 결과 CSV](astrophotography_targets_reaudit_v1.csv)뿐이다. 소스, DB, seed, 후보/검토 원본, 마이그레이션, Git 이력 및 배포 설정은 변경하지 않았다.
