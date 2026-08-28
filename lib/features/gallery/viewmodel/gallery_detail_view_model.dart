import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../data/models/shooting_record.dart';
import '../../../data/models/plate_solve_queue.dart';
import '../../../services/photo_overlay_service.dart';

class GalleryDetailRefreshResult {
  const GalleryDetailRefreshResult({
    required this.record,
    required this.hasPendingNasSync,
  });

  final ShootingRecord record;
  final bool hasPendingNasSync;
}

typedef GalleryDetailRecordRefresher =
    Future<GalleryDetailRefreshResult> Function(ShootingRecord record);

/// 사진 상세 화면의 페이지 탐색 상태 및 천체 Overlay 상태를 관리한다.
class GalleryDetailViewModel extends ChangeNotifier {
  GalleryDetailViewModel({
    required List<ShootingRecord> records,
    required int initialIndex,
    this.overlayService,
    this.recordRefresher,
    bool initialHasPendingNasSync = false,
    this.liveRefreshInterval = const Duration(seconds: 4),
  })  : _records = List<ShootingRecord>.from(records),
        _hasPendingNasSync = initialHasPendingNasSync,
        _currentIndex = records.isEmpty
            ? 0
            : initialIndex.clamp(0, records.length - 1);

  final List<ShootingRecord> _records;
  int _currentIndex;
  final PhotoOverlayService? overlayService;
  final GalleryDetailRecordRefresher? recordRefresher;
  final Duration liveRefreshInterval;
  bool _hasPendingNasSync;
  int _refreshRevision = 0;

  /// 사진 ID → Overlay 계산 결과 캐시 (같은 세션 내 재계산 방지).
  final Map<String, PhotoOverlayResult> _overlayCache = {};
  final Set<String> _loadingOverlayFor = {};

  /// 기본 OFF — ON일 때만 Plate Solve 오버레이를 계산한다 (스와이프 랙 방지).
  bool _overlayEnabled = false;
  bool _showTarget = true;
  bool _showNearby = true;

  List<ShootingRecord> get records => List.unmodifiable(_records);
  int get currentIndex => _currentIndex;
  int get totalCount => _records.length;
  bool get canSwipe => _records.length > 1;
  String? get positionLabel =>
      canSwipe ? '${_currentIndex + 1} / ${_records.length}' : null;

  ShootingRecord get currentRecord => _records[_currentIndex];
  int get refreshRevision => _refreshRevision;
  bool get needsLiveRefresh {
    if (_records.isEmpty) return false;
    final status = currentRecord.plateSolveQueueStatus;
    return _hasPendingNasSync ||
        status == PlateSolveQueueStatus.waiting ||
        status == PlateSolveQueueStatus.processing;
  }

  Future<void> refreshCurrentRecord() async {
    final refresher = recordRefresher;
    if (refresher == null || _records.isEmpty) return;
    final requestedId = currentRecord.id;
    final result = await refresher(currentRecord);
    if (_records.isEmpty || currentRecord.id != requestedId) return;
    _hasPendingNasSync = result.hasPendingNasSync;
    _refreshRevision++;
    final idx = _records.indexWhere((record) => record.id == requestedId);
    if (idx < 0) return;
    final previous = _records[idx];
    _records[idx] = result.record;
    if (previous.plateSolve != result.record.plateSolve ||
        previous.celestialObjectId != result.record.celestialObjectId) {
      _overlayCache.remove(requestedId);
    }
    notifyListeners();
    if (_overlayEnabled && previous.plateSolve != result.record.plateSolve) {
      ensureOverlayLoaded(requestedId);
    }
  }

  // ── Overlay 상태 ─────────────────────────────────────────────────────────

  bool get overlayEnabled => _overlayEnabled;
  bool get showTarget => _showTarget;
  bool get showNearby => _showNearby;
  /// [recordId] 사진이 현재 Overlay를 로딩 중인지 여부.
  bool isOverlayLoadingFor(String recordId) =>
      _loadingOverlayFor.contains(recordId);

  /// [recordId] 사진의 Overlay 계산 결과 (아직 로딩 전이면 null).
  PhotoOverlayResult? overlayFor(String recordId) => _overlayCache[recordId];

  void toggleOverlayEnabled() {
    _overlayEnabled = !_overlayEnabled;
    notifyListeners();
    if (_overlayEnabled && _records.isNotEmpty) {
      // 사용자가 켠 뒤에만 현재 사진 오버레이 계산
      ensureOverlayLoaded(currentRecord.id);
    }
  }

  void toggleShowTarget() {
    _showTarget = !_showTarget;
    notifyListeners();
  }

  void toggleShowNearby() {
    _showNearby = !_showNearby;
    notifyListeners();
  }

  /// 오버레이 메뉴를 열 때 호출 — 필요할 때만 로드한다.
  void requestOverlayForCurrent() {
    if (_records.isEmpty) return;
    ensureOverlayLoaded(currentRecord.id);
  }

  /// [recordId] Overlay가 없으면 계산한다.
  ///
  /// **자동으로 호출하지 말 것** — 스와이프/페이지 빌드에서 돌리면
  /// Plate Solve·이미지 probe가 메인 isolate를 막아 랙이 난다.
  /// Overlay ON 또는 사용자가 옵션을 열 때만 호출한다.
  Future<void> ensureOverlayLoaded(String recordId) async {
    final service = overlayService;
    if (service == null) return;
    if (_overlayCache.containsKey(recordId) ||
        _loadingOverlayFor.contains(recordId)) {
      return;
    }
    ShootingRecord? record;
    for (final item in _records) {
      if (item.id == recordId) {
        record = item;
        break;
      }
    }
    if (record == null) return;

    _loadingOverlayFor.add(recordId);
    // 로딩 스피너는 다음 프레임에만 반영 (스와이프 제스처와 경합 완화)
    scheduleMicrotask(notifyListeners);

    // UI 스레드에 한 프레임 양보한 뒤 무거운 계산
    await Future<void>.delayed(Duration.zero);
    if (!_loadingOverlayFor.contains(recordId)) return;

    final result = await service.buildOverlay(record);

    _loadingOverlayFor.remove(recordId);
    _overlayCache[recordId] = result;
    notifyListeners();
  }

  void onPageChanged(int index) {
    if (index < 0 || index >= _records.length) return;
    if (index == _currentIndex) return;
    _currentIndex = index;
    notifyListeners();
    // Overlay가 켜진 경우에만 현재 사진 로드 (인접 페이지 프리로드 안 함)
    if (_overlayEnabled) {
      ensureOverlayLoaded(currentRecord.id);
    }
  }

  void updateRecord(ShootingRecord updated) {
    final idx = _records.indexWhere((r) => r.id == updated.id);
    if (idx < 0) return;
    final previous = _records[idx];
    _records[idx] = updated;
    // Plate Solve/대상이 바뀌었을 수 있으므로 Overlay 캐시를 무효화한다.
    if (previous.plateSolve != updated.plateSolve ||
        previous.celestialObjectId != updated.celestialObjectId) {
      _overlayCache.remove(updated.id);
    }
    notifyListeners();
    if (_overlayEnabled &&
        (previous.plateSolve != updated.plateSolve ||
            previous.celestialObjectId != updated.celestialObjectId)) {
      ensureOverlayLoaded(updated.id);
    }
  }

  /// 현재 기록을 삭제한 뒤 남은 기록 수를 반환한다.
  int removeRecord(String recordId) {
    final idx = _records.indexWhere((r) => r.id == recordId);
    if (idx < 0) return _records.length;

    _records.removeAt(idx);
    _overlayCache.remove(recordId);
    _loadingOverlayFor.remove(recordId);
    if (_records.isEmpty) {
      _currentIndex = 0;
    } else if (_currentIndex >= _records.length) {
      _currentIndex = _records.length - 1;
    }
    notifyListeners();
    if (_overlayEnabled && _records.isNotEmpty) {
      ensureOverlayLoaded(currentRecord.id);
    }
    return _records.length;
  }

  /// 사진이 있는 기록만 추출하고, 원본 순서를 유지한다.
  static List<ShootingRecord> photoRecordsFrom(List<ShootingRecord> records) {
    return records
        .where((r) => r.photoUri != null && r.photoUri!.isNotEmpty)
        .toList();
  }

  static int indexOfRecord(List<ShootingRecord> records, ShootingRecord record) {
    return records.indexWhere((r) => r.id == record.id);
  }
}

/// One-shot, non-blocking refresh scheduler for the currently visible detail.
/// It reschedules only while NAS or Plate Solve work remains non-terminal.
class GalleryDetailLiveRefreshController {
  GalleryDetailLiveRefreshController({
    required this.interval,
    required this.shouldRefresh,
    required this.refresh,
  });

  final Duration interval;
  final bool Function() shouldRefresh;
  final Future<void> Function() refresh;
  Timer? _timer;
  bool _active = true;
  bool _refreshing = false;
  bool _disposed = false;

  bool get hasScheduledRefresh => _timer?.isActive == true;

  void start() => synchronize();

  void synchronize() {
    if (_disposed || !_active || !shouldRefresh()) {
      _timer?.cancel();
      _timer = null;
      return;
    }
    if (_refreshing || _timer?.isActive == true) return;
    _timer = Timer(interval, () => unawaited(refreshNow()));
  }

  Future<void> refreshNow({bool force = false}) async {
    if (_disposed || !_active || _refreshing || (!force && !shouldRefresh())) {
      return;
    }
    _timer?.cancel();
    _timer = null;
    _refreshing = true;
    try {
      await refresh();
    } catch (_) {
      // The next one-shot refresh remains available. The concrete refresher
      // owns diagnostic logging and user-visible error policy.
    } finally {
      _refreshing = false;
      synchronize();
    }
  }

  void pause() {
    _active = false;
    _timer?.cancel();
    _timer = null;
  }

  void resume() {
    if (_disposed) return;
    _active = true;
    if (shouldRefresh()) unawaited(refreshNow());
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
  }
}
