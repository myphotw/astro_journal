# 성도 V2 태양계 천체력

## 범위

- 표시 대상: `solar_1` 태양, `solar_2` 달, `solar_3`~`solar_9` 수성~해왕성
- 지원 시각: 2000-01-01 00:00:00 UTC ~ 2100-12-31 23:59:59 UTC
- 계산은 네트워크를 사용하지 않으며 카탈로그의 정적 `ra`/`dec` 필드를
  변경하지 않는다.
- 지원 범위 밖에서는 기존 성도는 유지하고 태양계 마커만 표시하지 않는다.

## 계산 방식

`astronomia 1.1.1`의 순수 Dart 구현을 사용한다.

- 라이선스: MIT
- 원본: <https://github.com/dmvvilela/astronomia>
- 행성: VSOP87B, date-of-date 세차, 광행시간, 황도 광행차, FK5 보정,
  장동 및 실제 황도경사를 적용한 apparent RA/Dec
- 태양 마커: VSOP87 지구 궤도로부터 계산한 apparent RA/Dec
- 달: Meeus *Astronomical Algorithms* 47장 주기항, 장동, 실제 황도경사,
  지구 타원체 관측자 위치와 지평시차를 적용한 topocentric RA/Dec
- 시간척도: UTC Julian Day와 2000년 이후 ΔT 근사로 JDE(TT)를 구분
- Alt/Az: AstroJournal의 기존 `CelestialPositionService.computeAltAz()` 사용

기존 `SkyMapSunPositionService`는 낮·박명 배경을 위해 그대로 유지한다.
새 서비스는 태양계 마커의 정밀 동적 좌표만 담당한다. 행성의 연주시차는
1분각 목표에 비해 작아 geocentric apparent 좌표를 사용하며, 달에는 반드시
관측지 지평시차를 적용한다. 대기 굴절은 적용하지 않는다.

## 정확도 검증

`test/solar_system_ephemeris_service_test.dart`는 JPL Horizons DE441의
2026-01-01 00:00:00 UTC, 서울(동경 126.9780°, 북위 37.5665°) topocentric
apparent RA/Dec를 고정 기준값으로 사용한다. 태양·달·7개 행성 모두 구면
각거리 오차 1분각 이하를 요구한다.

이 검증은 해당 기준 시각의 회귀 정확도를 보장한다. 2000~2100 전체 기간의
모든 날짜를 JPL DE441과 전수 비교한 것은 아니므로, 지원 기간 전체에 대한
1분각 정확도는 라이브러리 알고리즘과 경계 계산 테스트를 근거로 한 목표이며
완전 검증으로 간주하지 않는다.

JPL 기준값 출처:

- Horizons API: <https://ssd-api.jpl.nasa.gov/doc/horizons.html>
- Horizons 시스템: <https://ssd.jpl.nasa.gov/horizons/>

## 갱신 및 성능

날짜·시간 또는 관측지가 바뀔 때만 천체력을 갱신한다. 확대·축소와 화면
드래그는 저장된 RA/Dec/Alt/Az를 다시 투영할 뿐 천체력을 다시 계산하지
않는다. 동일 초·관측지 결과는 최대 512개까지 메모리 캐시에 유지하며,
시간 Slider의 연속 입력은 기존 ViewModel의 프레임 단위 병합을 그대로
사용한다.
