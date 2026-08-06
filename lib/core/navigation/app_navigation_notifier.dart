import 'package:flutter/foundation.dart';

import '../../data/models/catalog_object.dart';
import '../constants/catalog_type.dart';

class AppNavigationNotifier extends ChangeNotifier {
  int _currentIndex = 0;
  CatalogType? _pendingCatalogType;
  CatalogObject? _pendingSkyMapObject;

  int get currentIndex => _currentIndex;
  CatalogType? get pendingCatalogType => _pendingCatalogType;
  CatalogObject? get pendingSkyMapObject => _pendingSkyMapObject;

  void navigateTo(int index) {
    _currentIndex = index;
    _pendingCatalogType = null;
    _pendingSkyMapObject = null;
    notifyListeners();
  }

  void navigateToCatalog(CatalogType type) {
    _pendingCatalogType = type;
    _pendingSkyMapObject = null;
    _currentIndex = 1;
    notifyListeners();
  }

  /// 성도 탭으로 이동 후 [object] 위치로 포커스 (상세 팝업은 열지 않음).
  void navigateToSkyMap(CatalogObject object) {
    _pendingSkyMapObject = object;
    _pendingCatalogType = null;
    _currentIndex = 4;
    notifyListeners();
  }

  void consumePendingCatalogType() {
    if (_pendingCatalogType != null) {
      _pendingCatalogType = null;
    }
  }

  CatalogObject? consumePendingSkyMapObject() {
    final object = _pendingSkyMapObject;
    _pendingSkyMapObject = null;
    return object;
  }
}
