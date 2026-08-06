# Astro Journal

> 천체사진 촬영자를 위한 개인 관측 기록 앱

Astro Journal은 Seestar 및 일반 천체사진 촬영자를 위한 개인 천체관측 기록 앱입니다.

촬영한 천체를 기록하고, 사진과 관측 정보를 관리하며, Messier 진행률을 확인할 수 있는 것을 목표로 합니다.

---

# 프로젝트 목표

복잡한 기능보다 실제 관측 시 편하게 사용할 수 있는 앱을 만드는 것을 목표로 합니다.

- 빠른 기록

- 쉬운 사용

- 오프라인 사용 가능 (Offline First)

---

# 개발 환경

- Flutter (Stable)

- Android 우선

- SQLite

- MVVM Architecture

- Repository Pattern

- Material Design 3

---

# MVP 기능

## 1. 천체 카탈로그

기본 제공

- Messier (M1 ~ M110)

- 대표 NGC

- 대표 IC

- 대표 Sh2

※ NGC, IC, Sh2는 유명한 대상만 제공합니다.

---

## 2. 촬영 기록

촬영한 날짜와 장소를 기록합니다.

예시

2026-07-20

홍천

촬영 대상

- M8

- M20

- M17

메모 작성 가능

---

## 3. 사진 업로드

갤러리에서 사진 선택

↓

앱 내부 저장소로 복사

↓

EXIF 정보 자동 추출

가능한 경우 자동 입력

- 촬영시간

- GPS

- 장비명

- 노출시간

- ISO

- F값

---

## 4. 갤러리

촬영한 기록 조회

조회 방식

- 날짜별

- 대상별

사진과 메모를 함께 확인할 수 있습니다.

---

## 5. 통계

간단한 촬영 통계 제공

- Messier 진행률

- 총 촬영 대상 수

- 총 사진 수

---

## 6. 메인 화면

상단

오늘의 추천 대상 4개

하단 메뉴

- Catalog

- Shooting

- Gallery

- Statistics

---

# 데이터 저장

사진은 갤러리 원본을 수정하지 않습니다.

선택한 사진은 앱 내부 저장소로 복사하여 관리합니다.

SQLite에는

- 사진 경로

- 촬영 정보

- 메모

등을 저장합니다.

---

# 프로젝트 구조

```

lib/

│

├── models/

├── database/

├── repository/

├── services/

├── screens/

├── widgets/

└── main.dart

```

---

# 개발 원칙

- MVVM 구조 유지

- Repository Pattern 유지

- 실제 동작하는 코드 작성

- Mock 데이터 사용 금지

- TODO 코드 남기지 않기

- 기능은 하나씩 구현

- 구현 후 APK 테스트

---

# 개발 순서

1. 천체 카탈로그

2. 촬영 기록

3. 사진 업로드

4. EXIF 자동 입력

5. 갤러리

6. 통계

7. 메인 추천 화면

각 기능은 구현 후 반드시 아래를 실행합니다.

```

flutter analyze

flutter build apk

```

오류가 없을 때 다음 기능을 진행합니다.

---

# 향후 기능

MVP 완료 후 추가 예정

- Weather API

- 버킷리스트

- 즐겨찾기

- 추천 알고리즘 개선

- Synology NAS 백업

현재는 구현하지 않습니다.

---

# Cursor 개발 규칙

프로젝트를 시작하기 전에 반드시 [README.md](http://README.md)를 읽고 프로젝트를 이해합니다.

작업 절차

1. 변경 계획 설명

2. 변경 파일 목록 제시

3. 사용자 승인

4. 구현

5. flutter analyze

6. flutter build apk

7. 완료 보고

한 번에 여러 기능을 구현하지 않고 기능 단위로 개발합니다.

---

# 프로젝트 목표

Astro Journal은 화려한 기능보다 **실제 천체사진 촬영자가 자주 사용하는 기록 앱**을 만드는 것을 목표로 합니다.

빠르고 단순하며 안정적인 사용 경험을 가장 중요하게 생각합니다.