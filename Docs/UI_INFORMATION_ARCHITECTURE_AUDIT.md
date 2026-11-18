# AstroJournal UI 정보 구조 조사

## 1. 조사 개요 및 조사 범위

- 기준: 현재 작업 트리의 Flutter `lib/` 화면·셸·ViewModel·서비스 연결 코드를 읽어 확인했다. 실행 화면, 서버 운영 상태, 성능은 검증하지 않았다.
- 구분: **현재 구현**은 코드에서 진입 경로를 확인한 내용이고, **제안**은 향후 메뉴 재설계안이다. 제안은 기능 구현 완료를 뜻하지 않는다.
- 범위: Windows PC의 상단 메뉴, 비-Windows의 하단 탐색, 그 아래 화면·시트·다이얼로그 및 주요 교차 진입. 전수 조사 대상은 *현재 앱에서 연결된 경로*다. 소스에 클래스만 남은 화면은 별도로 표시한다.
- 작업 시작 시 기존 수정 파일은 `Docs/BUILD_CONFIGURATION.md`, `scripts/android_release_signing.ps1`이었다. 이 문서는 그 변경과 별개이며 소스·데이터·설정은 수정하지 않는다.
- 앱 분기: `AstroJournalApp`는 Windows에서 `PcMainShell`, 그 외에서 `MainShell`을 연다 (`lib/app.dart:188-192`). 메뉴 상태는 `AppNavigationNotifier`가 공유하며, 셸마다 하위 Navigator/탭 본문을 보유한다 (`lib/core/navigation/app_navigation_notifier.dart:6-33`, `lib/shared/widgets/pc_main_shell.dart:37-74`, `lib/shared/widgets/main_shell.dart:40-68`).

## 2. 현재 전체 메뉴 트리

Windows 상단에는 **8개 진입점**이 있다. 표시 순서와 내부 인덱스는 다르다 (`lib/shared/widgets/pc_main_shell.dart:45-74,176-184`).

```text
PC 상단
├─ 홈 → PcHomeScreen
├─ 사진 등록 → PcPhotoRegistrationScreen
├─ 천체 카탈로그 → CatalogScreen
├─ 갤러리 → GalleryScreen
├─ 광해지도 → LightPollutionMapScreen → WindowsLightPollutionMapScreen
├─ 성도 → SkyMapScreen
├─ 통계 → StatsScreen
└─ 설정 → SettingsScreen
```

비-Windows 하단에는 **7개 진입점**이 있다. `사진 등록`은 탭 본문이 아니라 등록 화면을 여는 동작이고, 설정은 홈 상단 버튼에서 연다 (`lib/shared/widgets/main_shell.dart:47-68,156-158,249-298`, `lib/features/home/view/home_screen.dart:173-183`).

```text
모바일 하단
├─ 홈 → HomeScreen → 상단 설정 버튼 → SettingsScreen
├─ 카탈로그 → CatalogScreen
├─ 갤러리 → GalleryScreen
├─ 광해지도 → LightPollutionMapScreen
├─ 성도 → SkyMapScreen
├─ 통계 → StatsScreen
└─ 사진 등록 → 사진 등록 라우트 → PcPhotoRegistrationScreen
```

공통 하위 구조: 카탈로그 **11개 탭**(전체, Messier, NGC, IC, Caldwell, Sh2, RCW, vdB, 별, 태양계, 은하수), 갤러리 **2개 보기**(대상별/날짜별), 설정 **6개 섹션**(추천 대상, 관측지, 장비, 서비스 연결, 백업/가져오기, 초기화). 광해 위치 카드에는 광해정보/기상정보 **2개 탭**이 있다 (`lib/features/catalog/view/catalog_screen.dart:60-83`, `lib/features/gallery/view/gallery_screen.dart:222-240`, `lib/features/settings/view/settings_screen.dart:35-67`, `lib/features/light_pollution_map/widgets/light_pollution_location_card.dart:234-256`). 이 숫자는 고정된 메뉴·탭·설정 섹션의 수이며 팝업 액션까지 합산한 수가 아니다.

## 3. 메뉴별 상세 기능 목록

| 현재 메뉴 | 실제 화면·기능 | 하위 화면·팝업·다른 화면 연결 | PC/모바일 차이 |
| --- | --- | --- | --- |
| 홈 | 관측지/장비/추적 방식, 관측 환경·날씨, 추천 대상, 스케줄, 천문 이벤트 | 관측지 상세·목록·현재 위치 저장, 이벤트 전체 목록; 모바일은 관측 상세·추천 상세/전체·스케줄 순서/수동추가 시트 및 월별/계절별 계획 | PC는 3/2/1열 대시보드, 모바일은 세로 흐름과 상세 시트. 동일 `HomeViewModel` 사용 (`lib/features/home/view/pc_home_screen.dart:110-175,203-359`, `lib/features/home/view/home_screen.dart:218-335,356-530`) |
| 사진 등록 | 사진 선택·대기열·미리보기·천체 검색·촬영/장비/위치/필터/메모 입력·사진별 저장 | 원본 확대, 위치 검색/지도, 중복/대상 불일치 확인, 저장 결과; 카탈로그 상세에서도 진입 | 같은 `PcPhotoRegistrationScreen`을 사용하되 PC는 3열, 좁은 폭/모바일은 세로 배치 (`lib/features/desktop/view/pc_photo_registration_screen.dart:37-83,414-494,621-663,704-832`) |
| 카탈로그 | 11개 카탈로그 탭, 검색, 정렬, 촬영 여부/천체 종류 필터, 사용자 천체 추가, 계절별 대상 탐색 | 천체 상세·연속 넘김, 즐겨찾기, 성도 위치, 노출 가이드·다중 밤 구도 참조·장비 추천·관측지별 촬영 가능성, 관련 사진, 해당 천체로 사진 등록 (`lib/features/catalog/view/catalog_screen.dart:60-83,213-232,290-447,522-729`; `lib/features/catalog/view/catalog_detail_screen.dart:79-120,224-322,251-322,517-615,887-958`) | 본체는 공통; PC와 모바일 진입 메뉴 위치만 다름 |
| 갤러리 | 대상별/날짜별 보기, 검색, 천체 분류·촬영일·장소·즐겨찾기 필터, 정렬, 증분 새로고침 | 사진 상세/연속 탐색·확대, 촬영정보 편집, 대상 변경, 즐겨찾기·대표 사진·삭제, Plate Solve·동기화 재시도 (`lib/features/gallery/view/gallery_screen.dart:109-196,222-400,662-817,978-1032`; `lib/features/gallery/view/gallery_detail_screen.dart:575-978,1172-1340,1451-2152,2892-3139`) | 화면과 ViewModel은 공통; 그리드가 가용 폭에 따라 반응형 |
| 광해지도 | 위치 검색, 저장 관측지, 지도 이동/선택, 광해 레이어·등급, 현재/선택 위치의 광해·기상정보 | 저장 관측지 추가/삭제, 위치 카드의 광해정보/기상정보 탭, 지도 검색·자동완성 (`lib/features/light_pollution_map/view/light_pollution_map_screen.dart:258-410`, `lib/features/light_pollution_map/widgets/light_pollution_map_search_bar.dart:139-204`, `lib/features/light_pollution_map/widgets/light_pollution_location_card.dart:234-256`) | Windows는 `WindowsLightPollutionMapScreen`/별도 지도 렌더러, 모바일은 지도 화면; ViewModel과 검색·정보 위젯 공유 (`lib/features/light_pollution_map/view/light_pollution_map_screen.dart:230-232`, `lib/features/light_pollution_map/view/windows_light_pollution_map_screen.dart:191-356`) |
| 성도 | 관측지·날짜/시간 선택, 하늘 이동/확대, 검색·선택, 별/별자리/카탈로그·태양계/은하수/시야/장비 FOV 표시 | 필터 시트(일반/즐겨찾기 모드 포함), 별자리별 대상 시트, 성도 자체의 선택 천체 상세·즐겨찾기 (`lib/features/sky_map/view/sky_map_screen.dart:121-141,176-258,430-550,612-719`, `lib/features/sky_map/widgets/sky_map_filter_sheet.dart:44-218`, `lib/features/sky_map/widgets/sky_map_constellation_objects_sheet.dart:15-190`) | 넓은 폭은 상단 제어 행, 좁은 폭은 분할 배치. 대상 상세는 Windows 다이얼로그/모바일 바텀 시트 (`lib/features/sky_map/widgets/sky_map_object_detail_sheet.dart:19-27`) |
| 통계 | 촬영 KPI, 월별 차트, 대상 상위 목록, 종류별 비율, 카탈로그 진행, 연도별 성과 | 월별 상세 바텀 시트, 연도 선택 (`lib/features/stats/view/stats_screen.dart:15-79`, `lib/features/stats/view/widgets/monthly_stats_bottom_sheet.dart:14-75`) | 공통 `StatsScreen` |
| 설정 | 추천 필터, 관측지, 장비, 서비스 연결, 백업/가져오기, 초기화 | 추천 설정 화면, 관측지 목록·상세·편집·시야 측정, 장비 목록·편집, 연결/동기화 상태, ZIP 내보내기·가져오기, 확인 다이얼로그 (`lib/features/settings/view/settings_screen.dart:35-67,115-278`) | PC 상단 메뉴/모바일 홈 버튼으로 진입. 설정 내부 화면은 공통 |

## 4. 화면 및 진입 경로

| 출발점 | 연결된 경로와 전달 데이터 | 근거 |
| --- | --- | --- |
| PC 사진 등록 메뉴 | 인덱스 6의 등록 화면. 다른 최상위 메뉴와 같이 별도 Navigator에 유지 | `lib/shared/widgets/pc_main_shell.dart:45-74,133-160,176-184` |
| 모바일 사진 등록 | `runPhotoFirstRegistrationFlow()`가 `PcPhotoRegistrationScreen(popWhenFinished: true)`을 Push. 별도 단계형 화면으로 이동하지 않음 | `lib/shared/widgets/main_shell.dart:156-158,280-297`, `lib/features/photo_first/photo_first_registration_flow.dart:8-11` |
| 카탈로그 상세 → 사진 등록 | 선택 천체를 `initialObject`로 전달하고, 저장 후 카탈로그·갤러리·홈·통계 갱신 | `lib/features/catalog/view/catalog_detail_screen.dart:887-958` |
| 카탈로그·홈 → 계절별 촬영 대상 | 카탈로그 도구 또는 홈 월별/계절별 액션으로 `SeasonPlannerScreen.open`; 내부에서 계절/월, 카탈로그/종류 필터, 천체 상세 진입 | `lib/features/catalog/view/catalog_screen.dart:335`, `lib/features/home/view/home_screen.dart:657-721`, `lib/features/season/view/season_planner_screen.dart:44-81,129-275,291-457` |
| 홈/설정 → 관측지 | 활성 관측지 상세·관리·현재 위치 저장; 상세에서 추적·기본 장비, 추천/조건/스케줄 요약, 시야 측정·편집 | `lib/features/home/view/pc_home_screen.dart:68-100`, `lib/features/home/view/home_screen.dart:239-266`, `lib/features/observation_site/view/observation_site_detail_screen.dart:96-116,135-230,271-377` |
| 관측지 편집 → 시야 측정/그래프 | 관측지 상세 및 편집 양쪽에서 `HorizonScanScreen` 진입; 경계 지점/차폐 구간 편집 다이얼로그 | `lib/features/observation_site/view/observation_site_detail_screen.dart:107-116`, `lib/features/settings/view/observation_site_edit_screen.dart:190-295,567` |
| 성도 → 천체 탐색 | 대상 검색·선택, 별자리 대상 목록, 성도 전용 상세 팝업·즐겨찾기. 카탈로그 상세 화면으로의 직접 이동은 이 경로에서 확인되지 않음 | `lib/features/sky_map/view/sky_map_screen.dart:121-141,430-505,612-719`, `lib/features/sky_map/widgets/sky_map_object_detail_sheet.dart:90-162` |
| 갤러리 → 사진 상세 | 대상별 정렬/필터를 펼친 사진 순서 또는 날짜별 사진 순서로 상세를 열고 연속 탐색 | `lib/features/gallery/viewmodel/gallery_view_model.dart:175-306`, `lib/features/gallery/view/gallery_screen.dart:981-1032`, `lib/features/gallery/view/gallery_detail_screen.dart:258-291` |
| 천문 이벤트 미리보기 → 전체 목록 | 홈의 공통 섹션에서 전체 목록 화면으로 이동 | `lib/features/home/view/widgets/astronomy_events_section.dart:13-125`, `lib/features/home/view/astronomy_events_screen.dart:13-119` |

코드에는 `RegistrationScreen`(구 단계형), `PhotoFirstConfirmScreen`·`MetadataReviewScreen`, `BaseExposureSettingsScreen`, `ExifDebugScreen`, `MetadataDebugScreen`도 존재한다. `lib/`의 클래스 참조 검색에서는 현재 앱 셸/활성 화면에서 이들로 들어오는 경로가 확인되지 않았다. **현재 사용 메뉴로 집계하지 않는다.** 외부 딥링크·테스트 전용 진입까지의 완전한 부재는 실행 검증 없이 단정하지 않는다 (`lib/features/photo_first/view/registration_screen.dart:31`, `lib/features/photo_first/view/photo_first_confirm_screen.dart:13`, `lib/features/catalog/view/metadata_review_screen.dart:22`, `lib/features/settings/view/base_exposure_settings_screen.dart:9`).

## 5. 홈 화면 전체 정보 분석

### 현재 구현

| 정보·액션 | PC | 모바일 | 생성·데이터 경로 |
| --- | --- | --- | --- |
| 제목·새로고침 | `오늘 밤 촬영 도우미`, 고정 상단 새로고침 | `천체 촬영 도우미`, 홈 상단 설정 및 새로고침 | `lib/features/home/view/pc_home_screen.dart:203-251`, `lib/features/home/view/home_screen.dart:163-201,218-335` |
| 관측지·장비·추적 방식 | 공통 상단 선택 영역; 관측지 상세/관리·현재 위치 저장 | 관측지수 카드 안의 동일 컨트롤 | `HomeObservationContextControls`와 활성 관측지/장비 상태 (`lib/features/home/view/pc_home_screen.dart:136-175`, `lib/features/home/view/home_screen.dart:356-400`, `lib/features/home/view/widgets/home_observation_context_controls.dart:140-298`) |
| 천문정보/관측 가능 상태 | 별도 `천문정보` 패널. 관측지수, 판정·사유, 점수 구성(있을 때), 실제 예보, 달/태양·광해 등 | 관측지수 요약 카드와 관측 상세 시트; 관측 가능 시간·조건 상세 | `ObservationEngine`, 활성 장소, 날씨, 위치/천문 계산 결과를 `HomeViewModel`에서 제공 (`lib/features/home/view/pc_home_screen.dart:363-445,474-663`, `lib/features/home/view/home_screen.dart:726-1090,1090-1902`, `lib/features/home/viewmodel/home_view_model.dart:244-282`) |
| 시간대별 기상정보 | 왼쪽 독립 표 | 관측 상세 시트의 시간별 전망/조건 | `WeatherService`, `WeatherCacheService` 및 관측 조건의 weather/시간 슬롯 (`lib/features/home/view/pc_home_screen.dart:446-473,663-1070`, `lib/features/home/view/home_screen.dart:1480-1742`, `lib/features/home/viewmodel/home_view_model.dart:269-274`) |
| 오늘 밤 추천 | 최대 4개 카드, 점수/별/근거·추천 시간·장비 칩·계획 추가/해제 | 카드 4개, 상세 시트·전체 추천 시트·계획 토글 | 카탈로그·추천 설정·관측 조건→`RecommendationEngine`→`HomeViewModel`; 장비 칩은 `EquipmentRecommendationService` (`lib/features/home/view/pc_home_screen.dart:1071-1210`, `lib/features/home/view/home_screen.dart:400-458,1974-2912`, `lib/features/home/viewmodel/home_view_model.dart:244-282,794-983`) |
| 촬영 스케줄 | 배정 항목의 시간·대상·상태/수기/고정 플래그 표시 | 타임라인 및 순서 편집·수기 대상 추가 시트 | 사용자 계획 상태와 `SchedulerEngine`의 실제 배정 결과를 `HomeViewModel`이 제공 (`lib/features/home/view/pc_home_screen.dart:1212-1304`, `lib/features/home/view/home_screen.dart:458-497,3189-3426,3688-4003`, `lib/features/home/viewmodel/home_view_model.dart:244-282,1099-1226`) |
| 향후 계획 | PC 홈 본문에서 독립 섹션 확인되지 않음 | 월별/계절별 계획 진입 | `SeasonPlannerScreen.open` (`lib/features/home/view/home_screen.dart:497-521,657-721`) |
| 다가오는 천문 이벤트 | 전체 폭 하단 섹션 | 세로 홈 하단 섹션 | 공통 `AstronomyEventsSection` 미리보기→`AstronomyEventsScreen`; `AstronomyEventsViewModel`이 repository 조회 (`lib/features/home/view/pc_home_screen.dart:257-299`, `lib/features/home/view/home_screen.dart:515-527`, `lib/features/home/view/widgets/astronomy_events_section.dart:13-125`, `lib/features/home/viewmodel/astronomy_events_view_model.dart:25-43`) |

PC 실제 배치: **고정 제목/선택 영역 → (왼쪽 천문정보+시간대별 기상 | 가운데 추천 | 오른쪽 스케줄) → 전체 폭 이벤트**. 가용 폭 1180/760 기준으로 3열/2열/1열이 된다 (`lib/features/home/view/pc_home_screen.dart:203-359`). 모바일은 하나의 스크롤에서 요약→추천→스케줄→향후 계획→이벤트 순서다 (`lib/features/home/view/home_screen.dart:356-530`).

### 분리 후보 — 제안

- 홈에는 오늘의 관측 상태, 추천·스케줄의 요약과 빠른 진입을 남기고, 상세 시간대별 기상·점수 산정 근거·전체 추천/계획 편집은 `관측` 하위 상세 화면으로 분리할 수 있다. 현재 PC 홈은 표·추천·스케줄을 한 곳에 동시에 배치하고 모바일은 같은 상세를 시트에서 제공하므로 정보 깊이가 다르다. 이는 **새 화면/메뉴 설계 제안**이지 현재 구현이 아니다.
- 이벤트는 현재 홈 미리보기 + 별도 전체 화면이 이미 있으므로 홈에는 미리보기만 남기고 전체 목록을 `관측`에서 재노출하는 방향을 검토할 수 있다. 중복 데이터 계층을 만들 필요는 없다.
- 월별/계절별 계획은 현재 모바일 홈·카탈로그에서 진입 가능하다. 홈의 주요 본문보다 `관측 계획` 또는 `라이브러리 탐색`의 보조 경로가 자연스러운지 사용자 흐름 검증이 필요하다.

## 6. 사진 및 라이브러리 기능 분석

### 현재 구현과 데이터 흐름

- 등록: 파일 선택/복사 또는 드롭 → 사진별 `RegistrationSession` 대기열 → EXIF/Plate Solve 보강과 대상·날짜·장비 UUID·필터·초점거리·노출/스택/적산·위치/메모 확인 → `PhotoFirstRegistrationViewModel.registerPhoto()` → `PhotoRegistrationService.registerPhotoRecord()` → `ShootingRecordRepository` 저장. 화면은 성공 세션을 제거하고 실패 세션을 남기며 갤러리/통계/홈을 갱신한다 (`lib/features/desktop/view/pc_photo_registration_screen.dart:138-175,213-267,311-375,414-494,621-832`, `lib/features/photo_first/viewmodel/photo_first_registration_view_model.dart:122-133`, `lib/services/photo_registration_service.dart:344-615`). 내부 Outbox/API의 계약 변경은 이 조사 범위 밖이다.
- 장비/필터: 활성 장비는 `EquipmentRepository`에서 조회하고 선택 장비의 `effectiveCaptureCapability.filters`만 선택지로 만든다. 기존 저장·EXIF 필터가 목록에 없으면 `기존 필터` 텍스트로 보존한다. 장비 변경 시 `focalLengthMm` 자동값을 갱신한다 (`lib/features/desktop/view/pc_photo_registration_screen.dart:139-141,704-788,835-848`).
- 카탈로그: `CatalogRepository`/검색 서비스로 천체를 검색·분류·정렬하고 상세에서 실제 관측/촬영 가이드, 장비 추천, 해당 대상의 사진, 사진 등록으로 연결한다 (`lib/features/catalog/view/catalog_screen.dart:60-83,290-447`, `lib/features/catalog/view/catalog_detail_screen.dart:224-322,517-615,887-958`). 태양계·별·은하수도 카탈로그 탭에 포함된다.
- 갤러리: `GalleryViewModel`이 촬영 기록과 카탈로그를 합쳐 날짜/장소/종류/검색/즐겨찾기 필터를 적용한다. 대상별 보기에서는 사진이 있는 대상만 그룹을 만들고 대표 사진·사진 수를 정한다. 그 그룹 순서대로 사진을 펼쳐 상세 연속 탐색에 사용하며, 날짜별 보기는 날짜 정렬된 사진 목록을 사용한다 (`lib/features/gallery/viewmodel/gallery_view_model.dart:67-100,151-360`). 상세에서 기록 정보(촬영일시·장비·적산·스택/노출/필터·ISO/F값/초점거리·위치/메모)를 표시·편집하고 대표/즐겨찾기/삭제·확대·Plate Solve 기능을 제공한다 (`lib/features/gallery/view/gallery_detail_screen.dart:575-978,1172-1340,1451-2152,2892-3139`).
- 새 사진 확인은 `GalleryIncrementalRefreshService`를 호출한다. 앱 foreground 복귀 시에도 갤러리 증분 갱신 경로가 있다. 목록 갱신은 `GalleryViewModel.load()`를 재사용한다 (`lib/features/gallery/view/gallery_screen.dart:57-66,109-140`, `lib/app.dart:69-88`, `lib/features/gallery/viewmodel/gallery_view_model.dart:372-425`). 구조 개편에서 이 동기화 트리거/상태를 빼면 안 된다.

### 확인된 중복·개선 검토

- 천체의 **발견/탐색**은 카탈로그, 성도, 홈 추천, 계절별 화면에 걸쳐 있고, **내 사진의 탐색**은 카탈로그 상세의 사진 영역과 갤러리에 걸쳐 있다. 데이터는 공유하나 진입 맥락이 다르다. 하나를 없애기보다 상세↔갤러리의 일관된 이동과 필터 전달을 설계해야 한다.
- PC 등록과 모바일 등록은 화면·저장 경로가 공통이므로 메뉴 재배치 시 동일 등록 화면에 도달하도록 유지해야 한다. 카탈로그의 `initialObject` 선택과 돌아온 후 상태 갱신도 보존 대상이다.
- 갤러리 촬영 기록 편집과 등록 화면은 역할이 다르다. 등록을 `촬영`, 소장 사진 탐색을 `라이브러리`로 분리하더라도 기록 편집은 갤러리 상세의 맥락 액션으로 유지하는 편이 자연스럽다(제안).

## 7. 관측 및 천문 기능 분석

| 기능 | 현재 역할·연결 | 재배치 시 주의 |
| --- | --- | --- |
| 오늘 밤 촬영 도우미 | 홈의 중심. 선택 관측지·장비·추적 모드와 관측 상태, 추천, 사용자 계획, 실제 스케줄을 한 ViewModel에서 조합 (`lib/features/home/viewmodel/home_view_model.dart:244-282,618,794-983,1099-1226`) | `관측`으로 옮기더라도 홈 요약과 동일 상태를 공유해야 하며 사용자 planned와 실제 scheduled를 혼동하면 안 됨 |
| 추천·스케줄 | `RecommendationEngine`과 `SchedulerEngine`, 설정 필터 및 장비 추천을 사용. 모바일은 편집 시트, PC는 주로 요약 카드와 계획 토글 (`lib/features/home/view/home_screen.dart:400-497,3688-4003`, `lib/features/home/view/pc_home_screen.dart:1071-1304`) | PC/모바일의 노출 액션 차이를 메뉴 설계에서 명시. 이동만으로 기능 동등성을 가정하지 않음 |
| 성도 | 같은 관측지/선택 시각의 실제 위치를 렌더링하는 탐색 도구. 검색·필터·대상 상세·FOV·시야 경계가 있음 (`lib/features/sky_map/view/sky_map_screen.dart:176-258,430-719`) | 성도의 관측지/시간 상태와 홈의 ‘오늘 밤’ 상태는 사용 목적이 다를 수 있으므로 강제 동기화 여부를 별도 결정 |
| 광해지도 | 장소 검색/선택과 Bortle·SQM 및 해당 위치 날씨. 저장 관측지 목록과 연결 (`lib/features/light_pollution_map/view/light_pollution_map_screen.dart:258-410`, `lib/features/light_pollution_map/widgets/light_pollution_location_card.dart:234-256`) | 관측지 선택, 지도에서의 임의 위치 선택, 관측지 편집의 의미를 구분. 장소 관리 기능을 지도 복제본으로 만들지 않음 |
| 관측지 관리·시야 | 설정의 관측지 목록→상세→편집·시야 측정. 상세는 추천/조건/스케줄 요약도 보임 (`lib/features/settings/view/observation_site_list_screen.dart:23-150`, `lib/features/observation_site/view/observation_site_detail_screen.dart:135-377`) | `관측`에서 진입을 추가해도 관리 화면과 저장 모델은 하나만 유지 |
| 월별/계절별 계획 | 홈/카탈로그에서 별도 화면으로 열어 계절·월·카탈로그/종류를 탐색 (`lib/features/season/view/season_planner_screen.dart:44-81,129-275,291-457`) | 카탈로그 탐색과 관측 계획 양쪽에 걸친 기능. 주 소속을 정하고 다른 쪽에는 링크만 둘 수 있음 |
| 천문 이벤트 | 홈 미리보기와 전체 화면 (`lib/features/home/view/widgets/astronomy_events_section.dart:13-125`) | 홈 미리보기와 관측 하위 전체 목록을 같은 ViewModel/repository로 연결 |

**통합 가능성(제안):** 홈 대시보드 자체를 ‘관측’으로 단순 이동하는 대신, `관측` 아래 **오늘 밤**, **성도**, **광해/관측지**, **천문 이벤트**를 사용 목적별로 묶고 홈은 요약·빠른 진입으로 두는 안을 검토한다. 관측지·시간·장비 컨텍스트의 공유 범위는 먼저 정의해야 한다.

## 8. 통계 및 설정 기능 분석

### 통계 — 현재 구현

`StatsScreen`에는 촬영 결과 KPI, 월별 추이, 대상 상위, 대상 유형 비율, 카탈로그별 진행, 연도별 성과가 있다. 월을 누르면 적산시간/건수/신규 대상 등의 세부 시트를 연다. `StatsViewModel`은 canonical `ShootingRecordRepository`와 `CatalogRepository`를 받아 `StatsAnalyticsService`로 집계한다 (`lib/features/stats/view/stats_screen.dart:15-79`, `lib/features/stats/view/widgets/monthly_stats_bottom_sheet.dart:14-75`, `lib/features/stats/viewmodel/stats_view_model.dart:80-113`). 이름은 ‘통계’지만 현재 코드에서 독립적인 관측 세션 통계 전용 화면은 확인되지 않았다. 촬영 기록을 기반으로 한 분석과 앞으로 계획할 관측은 구분해야 한다.

### 설정 — 현재 구현

| 섹션 | 실제 하위 기능 | 근거 |
| --- | --- | --- |
| 추천 대상 설정 | 카탈로그·천체 종류별 추천 필터 화면 | `lib/features/settings/view/settings_screen.dart:187-224`, `lib/features/settings/view/recommendation_settings_screen.dart:111-248` |
| 관측지 관리 | 저장 장소 목록/즐겨찾기·추가/상세/편집, 주소·좌표·Bortle/SQM·추적·기본 장비·시야 경계/차폐 구간·시야 측정 | `lib/features/settings/view/settings_screen.dart:150-177`, `lib/features/settings/view/observation_site_list_screen.dart:23-150`, `lib/features/settings/view/observation_site_edit_screen.dart:963-1290` |
| 장비 관리 | 촬영/안시 장비·아이피스 등록/수정/활성/삭제; 촬영 모드·노출·Gain·필터·채널 capability 편집 | `lib/features/settings/view/settings_screen.dart:115-145`, `lib/features/settings/view/equipment_list_screen.dart:27-105`, `lib/features/settings/view/equipment_form_screen.dart:227-280`, `lib/features/settings/widgets/equipment_capture_capability_editor.dart:184-699` |
| 서비스 연결 | 백엔드/Maps/날씨/주소/Plate Solve 상태, 재연결·동기화 재시도·Outbox 진행 | `lib/features/settings/widgets/tc_backend_settings_section.dart:49-120,170-211` |
| 백업/가져오기 | DB·사진 ZIP 내보내기/가져오기 및 확인 UI | `lib/features/settings/view/settings_screen.dart:231-278,300-591` |
| 초기화 | 단계별 확인 후 앱 데이터 초기화 | `lib/features/settings/widgets/astrojournal_reset_section.dart:22-33,115-242` |

**분리 후보(제안):** 관측지와 장비는 단순 환경설정보다 반복적으로 사용하는 기준정보 관리 기능이다. 새 `관측`/`촬영` 영역에서 빠른 진입을 제공할 수 있지만 실제 편집·삭제 책임은 중복하지 않는다. 서비스 연결·백업·초기화는 설정에 남기는 편이 기능 성격상 명확하다. `기준정보`라는 독립 최상위 메뉴가 필요한지는 사용 빈도 확인 후 결정한다.

## 9. 기능 중복 및 구조적 문제점

1. **홈의 책임 과밀:** PC 홈에 관측 조건 표, 추천, 실제 스케줄, 이벤트가 모두 직접 나타나고 모바일은 여러 상세 시트/계획 도구가 홈에 집중된다 (`lib/features/home/view/pc_home_screen.dart:203-299`, `lib/features/home/view/home_screen.dart:289-335,356-530`). 요약과 심화 작업의 경계가 흐리다.
2. **플랫폼별 메뉴 비대칭:** PC는 8개 상단 메뉴(설정 포함), 모바일은 7개 하단 진입점(설정은 홈)이며 모바일 사진 등록은 탭이 아닌 라우트다. 메뉴명을 일대일로 옮기면 뒤로가기·상태 유지가 달라진다 (`lib/shared/widgets/pc_main_shell.dart:37-74,176-184`, `lib/shared/widgets/main_shell.dart:40-68,156-158,249-298`).
3. **대상 탐색의 다중 출발점:** 카탈로그 상세, 홈 추천, 성도, 계절 계획, 갤러리 대상별 보기에서 같은 천체를 다른 맥락으로 보여준다. 이는 중복 구현만의 문제가 아니라 탐색/계획/내 사진이라는 서로 다른 작업을 한 메뉴 축에 놓지 못한 정보 구조 문제다 (6·7절 근거).
4. **관측지·장비의 교차 소속:** 둘 다 설정에서 관리하지만 홈에서 선택하고 관측지 상세는 오늘 조건·추천·스케줄까지 보여준다. 선택과 관리의 명칭/위치를 분리하되 상태를 두 벌 만들지 않아야 한다 (`lib/features/home/view/widgets/home_observation_context_controls.dart:140-298`, `lib/features/observation_site/view/observation_site_detail_screen.dart:135-377`).
5. **PC/모바일 작업 깊이 차이:** PC 홈 추천/스케줄은 요약과 계획 토글 위주이고 모바일은 추천 상세·전체 추천·순서/수기 편집 시트가 있다. 통합 메뉴를 설계할 때 ‘공통 데이터’와 ‘공통 액션’을 구별해야 한다 (`lib/features/home/view/pc_home_screen.dart:1071-1304`, `lib/features/home/view/home_screen.dart:289-335,400-497`).
6. **소스에만 남은 화면:** 구 단계형 등록 및 일부 디버그/기준 노출 화면은 현재 앱의 진입 경로를 찾지 못했다. 존재만으로 신규 메뉴에 넣으면 안 된다 (4절).

## 10. 새로운 메뉴 구조 제안

아래는 **정보 구조 가설**이다. 새 기능을 만들자는 뜻이 아니며, 실제 코드 이동·메뉴 변경 전 사용자 결정과 플랫폼별 UX 검증이 필요하다.

```text
홈
  오늘의 관측/촬영 요약, 최근 사진·통계로의 빠른 진입(기존 데이터를 재사용)
촬영
  사진 등록; 촬영 기록 편집은 해당 사진 상세의 맥락 액션
라이브러리
  전체 카탈로그(11개 탭) · 천체 상세 · 갤러리(대상별/날짜별)
관측
  오늘 밤(관측 조건/추천/촬영 스케줄/시간대별 날씨)
  성도 · 광해지도 · 관측지 조회/관리 진입 · 계절별 대상 · 천문 이벤트 전체 목록
분석
  기존 촬영 통계/월별 상세
설정
  추천 필터 · 장비 관리 · 관측지 관리(관측에서도 바로가기)
  서비스 연결 · 백업/가져오기 · 초기화
```

추천 이유: `홈`은 실행 요약, `촬영`은 입력/기록 생성, `라이브러리`는 천체 지식과 소장 사진 탐색, `관측`은 장소·하늘·조건·계획, `분석`은 완료 기록의 집계, `설정`은 기준정보와 시스템 관리라는 **사용자 작업 목적**을 기준으로 묶는다. 관측지 관리는 관측 흐름의 주요 진입을 추가하되 편집 화면은 하나만 유지한다. PC의 8개 버튼을 단순 6개 버튼으로 바꾸거나 모바일 하단에 6개를 그대로 늘리는 구현안은 아직 확정하지 않는다.

## 11. 기존 메뉴와 신규 메뉴의 매핑표

| 현재 위치 | 제안 주 소속 | 보조 진입/유지할 맥락 | 비고 |
| --- | --- | --- | --- |
| 홈 PC·모바일 | 홈 요약 + 관측/오늘 밤 상세 | 홈의 추천·스케줄 요약 링크 | 현재 `HomeViewModel` 공유 유지 |
| 사진 등록 메뉴·하단 액션 | 촬영/사진 등록 | 카탈로그 상세의 대상 사전 선택 | 동일 등록 화면·저장 경로 유지 |
| 천체 카탈로그 | 라이브러리/카탈로그 | 계절별에서 천체 상세 링크; 성도/추천에서 카탈로그 상세로 가는 연결은 별도 설계 대상 | 11개 탭·필터 보존 |
| 갤러리 | 라이브러리/내 사진 | 카탈로그 상세의 해당 대상 사진 | 대상별/날짜별/상세 탐색 보존 |
| 광해지도 | 관측/장소·광해 | 관측지 상세/관리 진입 | 지도 임의 위치와 저장 관측지 구별 |
| 성도 | 관측/성도 | 카탈로그 상세의 성도 위치 링크 | 독립 시각·시점·필터 보존 |
| 통계 | 분석/촬영 통계 | 갤러리에서 관련 집계로 진입 가능성 검토 | 미구현 관측 통계 추가로 오인 금지 |
| 설정/추천 필터 | 설정/추천 기준 | 관측 추천 화면에서 설정 바로가기 검토 | 기존 설정 화면 재사용 |
| 설정/관측지·장비 관리 | 설정/기준정보; 관측·촬영에서 바로가기 | 홈 선택 컨트롤과 연결 | 데이터/편집 책임 중복 금지 |
| 설정/연결·백업·초기화 | 설정/시스템 | 없음 | 위험 작업은 깊은 확인 단계 유지 |
| 홈/천문 이벤트 전체 | 관측/천문 이벤트 | 홈 미리보기 유지 | 같은 repository 재사용 |
| 홈·카탈로그/계절별 계획 | 관측/계절별 계획(후보) | 카탈로그 탐색 링크 유지 | 주 소속은 사용 목적 검증 후 확정 |

## 12. 기능 이동 및 통합 시 주의사항

- 메뉴/셸 변경은 Windows `IndexedStack`·탭별 Navigator와 모바일 6개 본문 + 등록 라우트의 뒤로가기/상태 유지 계약을 함께 다뤄야 한다. `AppNavigationNotifier`의 기존 인덱스 기반 이동도 재매핑 대상이다 (`lib/shared/widgets/pc_main_shell.dart:37-74,94-160`, `lib/shared/widgets/main_shell.dart:40-68,196-298`, `lib/core/navigation/app_navigation_notifier.dart:6-33`).
- 홈·성도·광해지도가 관측지를 사용하더라도 ‘현재 위치’, ‘저장 관측지’, ‘지도 임의 선택’은 동일 상태가 아니다. 장비/추적·날짜/시간까지 무조건 한 전역 상태로 만들지 않는다.
- 사진 등록의 `RegistrationSession`별 실패 보존, 중복 확인, 카탈로그 사전 선택, 완료 후 갤러리·홈·통계 갱신을 유지한다. 메뉴 변경을 저장/Outbox/API 변경과 결합하지 않는다 (`lib/features/desktop/view/pc_photo_registration_screen.dart:414-538`).
- 갤러리의 증분 새로고침·foreground 갱신과 촬영 기록의 정렬/필터/대상 간 연속 탐색을 유지한다 (`lib/app.dart:69-88`, `lib/features/gallery/view/gallery_screen.dart:57-66`, `lib/features/gallery/viewmodel/gallery_view_model.dart:151-360`).
- 카탈로그와 성도의 서버 공유 즐겨찾기 버튼은 같은 컨트롤러를 사용한다. 메뉴 재배치 시 화면마다 별도 목록을 만들지 않는다 (`lib/features/catalog/view/catalog_detail_screen.dart:102`, `lib/features/sky_map/view/sky_map_screen.dart:46-51`, `lib/features/sky_map/widgets/sky_map_object_detail_sheet.dart:162`).
- 관측지/장비 CRUD와 백업·초기화는 데이터 영향이 큰 기능이다. 신규 빠른 진입을 더하더라도 기존 확인·권한·동기화 흐름은 유지한다.
- 새 정보 구조에서 홈을 얼마나 축약할지는 PC/모바일 별 현재 상세 접근성을 비교해 결정해야 한다. 이번 문서만으로 실제 화면 크기, 접근 빈도, 클릭 수의 우열은 증명되지 않는다.

## 13. 추가 확인이 필요한 사항

1. Windows/Android 실제 화면에서 긴 메뉴명, 좁은 창, 접근성/키보드 조작, 시트 높이 등 시각·사용성 검증. 본 조사는 실행하지 않았다.
2. 추천/스케줄의 PC와 모바일 액션 차이를 의도적으로 유지할지, 공통 상세 화면/경로를 제공할지 결정.
3. 계절별 계획의 주 소속(`관측`의 계획 vs `라이브러리`의 탐색), 천문 이벤트의 상위 명칭, 홈의 요약 수준 결정.
4. `촬영`을 사진 등록만의 최상위 메뉴로 둘지, 기존 촬영 기록(갤러리)과 함께 묶을지 사용자 실제 작업 흐름 확인.
5. `분석`이라는 이름 아래 현재 촬영 결과 통계만 있는 상태를 어떻게 표기할지 결정. 관측 통계 신규 구현은 이 제안에 포함되지 않는다.
6. 구 단계형 등록/디버그/기준 노출 화면의 외부 진입·향후 유지 정책. 현재 `lib/` 참조에서는 앱 진입을 찾지 못했으나 제거 판단은 별도 조사 필요.
7. 현재 미커밋 변경을 포함한 정확한 출시 버전과 사용자별 실제 메뉴 사용 빈도·동선. 본 문서는 작업 트리 기준 정적 조사다.

