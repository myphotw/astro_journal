# 유명천체 Favorites 초기 전환

초기 데이터는 `AstroJournal_Famous_Targets_Local_DB_Audit.xlsx`의 `채택_ID` 시트에서 검증한 고유 ID 317개다. `scripts/famous_celestial_objects_initial_ids.json`은 운영 전환에만 사용한다. 앱에는 이 파일을 포함하지 않으며 시작·복귀 시 기존 Favorites API에서 조회만 한다.

## 최초 1회

1. 실제 AstroJournal이 사용하는 TC-Backend **HTTPS 주소**를 확인한다. 토큰은 기존 `TC_BACKEND_AUTH_TOKEN` 환경 변수 또는 스크립트의 보안 입력으로 전달한다. 명령줄 인자나 저널에 토큰을 기록하지 않는다.
2. PowerShell 7에서 미리보기를 실행한다. GET만 호출한다. 예상 서버와 등록·추가·삭제 수를 확인한다.
3. 작업이 끝날 때까지 Windows·Android 앱과 같은 목록을 수정할 수 있는 다른 클라이언트를 모두 종료한다. 작업은 한 PC에서, 기본 저널 경로를 유지한 상태로 한 번만 진행한다.
4. `-Apply -ClientsClosed`로 실행한다. 서버 응답을 로컬 저널에 먼저 남기고, 누락 ID를 추가한다. 317개가 모두 서버에 있는 것을 확인한 뒤에만 목록 밖의 ID를 삭제한다. 공통 ID는 삭제·재등록하지 않는다. 마지막 GET의 ID 집합이 승인 목록과 정확히 같을 때만 완료로 표시한다.

```powershell
$origin = 'https://<확인한-서버-주소>'
./scripts/initialize_famous_celestial_objects.ps1 -BaseUrl $origin
./scripts/initialize_famous_celestial_objects.ps1 -BaseUrl $origin -Apply -ClientsClosed
```

미리보기에서 삭제 예정이 0개라면 `-ForbidRemovals`를 추가할 수 있다. 목록이 달라져 삭제가 필요해져도 삭제를 시작하지 않는다.

## 중단 또는 검증 실패

기본 저널은 `%LOCALAPPDATA%\AstroJournal\famous-catalog-v1\state.json`이다. 이 파일을 삭제하거나 새 PC·저널로 초기화를 다시 실행하지 않는다. 완료한 저널은 재적용을 막는다. 기존 API에는 서버 수준의 전환 표시나 트랜잭션이 없어, 다른 PC에서 새 저널을 만들면 이 보호를 공유하지 못한다.

네트워크 장애 등으로 중단되면 클라이언트를 닫은 상태에서 동일 주소와 저널로 `-Resume -ClientsClosed`를 실행한다. 초기 목록으로 복구하려면 `-Rollback -ClientsClosed`를 사용한다. 롤백은 원래 ID를 먼저 복원하고 확인한 뒤 초기화에서 추가한 ID를 제거한다. 삭제된 항목의 최초 등록 시각은 API 계약상 복구할 수 없고, 서버 연결이 복구될 때까지 재개 또는 롤백은 완료할 수 없다. 저널의 원본과 새 목록 어느 쪽에도 없는 ID를 발견하면 중단한다.
