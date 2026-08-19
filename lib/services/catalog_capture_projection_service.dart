import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/datasources/gallery_record_link_datasource.dart';
import '../data/models/catalog_object.dart';
import '../data/models/gallery_item.dart';
import '../data/repositories/catalog_repository.dart';
import '../data/repositories/gallery_repository.dart';
import '../data/repositories/shooting_record_repository.dart';
import 'app_logger.dart';
import 'catalog_search_service.dart';

class CatalogCaptureProjection {
  const CatalogCaptureProjection({
    required this.catalogObjectId,
    required this.captured,
    required this.capturedDate,
    required this.photoCount,
    required this.localCount,
    required this.remoteCount,
    required this.deduplicatedCount,
    this.latestCapturedAt,
  });

  final String catalogObjectId;
  final bool captured;
  final String? capturedDate;
  final int photoCount;
  final int localCount;
  final int remoteCount;
  final int deduplicatedCount;
  final DateTime? latestCapturedAt;
}

class CatalogCaptureProjectionException implements Exception {
  const CatalogCaptureProjectionException(this.message);

  final String message;

  @override
  String toString() => 'CatalogCaptureProjectionException: $message';
}

/// Resolves persisted record identities through the catalog's canonical
/// primary mapping. String normalization is only used for exact ID lookup;
/// aliases and cross-catalog references are delegated to CatalogSearchService.
class CatalogCaptureIdentityResolver {
  CatalogCaptureIdentityResolver(this._searchService);

  final CatalogSearchService _searchService;

  CatalogObject? resolve(
    String identity,
    List<CatalogObject> catalog, {
    Map<String, CatalogObject>? exactByLowerId,
  }) {
    final value = identity.trim();
    if (value.isEmpty) return null;
    final lower = value.toLowerCase();
    CatalogObject? exact = exactByLowerId?[lower];
    if (exact == null) {
      for (final object in catalog) {
        if (object.id.toLowerCase() == lower) {
          exact = object;
          break;
        }
      }
    }
    final resolved = exact ?? _searchService.resolveTarget(value, catalog);
    if (resolved == null) return null;
    return CatalogSearchService.resolvePrimaryFromList(resolved, catalog);
  }
}

/// Rebuilds Catalog captured/capturedDate from active local and remote records.
///
/// The persisted catalog columns are a rebuildable projection, not the source
/// of truth. Calls are serialized so startup pull, registration, and delete do
/// not overwrite a newer projection with stale input.
class CatalogCaptureProjectionService extends ChangeNotifier {
  factory CatalogCaptureProjectionService({
    required CatalogRepository catalogRepository,
    required ShootingRecordRepository localRecords,
    required GalleryRepository galleryRepository,
    GalleryRecordLinkDataSource recordLinks =
        const EmptyGalleryRecordLinkDataSource(),
    CatalogCaptureIdentityResolver? identityResolver,
  }) => CatalogCaptureProjectionService._(
    catalogRepository,
    localRecords,
    galleryRepository,
    recordLinks,
    identityResolver ?? CatalogCaptureIdentityResolver(CatalogSearchService()),
  );

  CatalogCaptureProjectionService._(
    this._catalogRepository,
    this._localRecords,
    this._galleryRepository,
    this._recordLinks,
    this._identityResolver,
  );

  static const _tag = 'CatalogCaptureProjection';

  final CatalogRepository _catalogRepository;
  final ShootingRecordRepository _localRecords;
  final GalleryRepository _galleryRepository;
  final GalleryRecordLinkDataSource _recordLinks;
  final CatalogCaptureIdentityResolver _identityResolver;

  Future<void> _tail = Future<void>.value();
  final Set<String> _dirtyIdentities = <String>{};

  Set<String> get dirtyIdentities => Set.unmodifiable(_dirtyIdentities);

  Future<CatalogCaptureProjection> reconcileObject(
    String catalogObjectId, {
    bool includeRemote = true,
  }) => _serialized(() async {
    try {
      final context = await _loadContext(includeRemote: includeRemote);
      final canonical = _identityResolver.resolve(
        catalogObjectId,
        context.catalog,
        exactByLowerId: context.exactByLowerId,
      );
      if (canonical == null) {
        throw CatalogCaptureProjectionException(
          'Catalog identity was not found: $catalogObjectId',
        );
      }
      final outcome = await _projectOne(canonical, context);
      _dirtyIdentities.remove(catalogObjectId);
      if (outcome.changed) notifyListeners();
      return outcome.projection;
    } catch (error) {
      _dirtyIdentities.add(catalogObjectId);
      rethrow;
    }
  });

  Future<List<CatalogCaptureProjection>> reconcileAll({
    bool includeRemote = true,
  }) => _serialized(() async {
    final context = await _loadContext(includeRemote: includeRemote);
    final targetIds = <String>{};
    for (final fact in context.facts) {
      targetIds.add(fact.catalogObjectId);
    }
    for (final object in context.catalog) {
      if (!object.captured) continue;
      final canonical = _identityResolver.resolve(
        object.id,
        context.catalog,
        exactByLowerId: context.exactByLowerId,
      );
      targetIds.add(canonical?.id ?? object.id);
    }
    for (final dirty in _dirtyIdentities) {
      final canonical = _identityResolver.resolve(
        dirty,
        context.catalog,
        exactByLowerId: context.exactByLowerId,
      );
      if (canonical != null) targetIds.add(canonical.id);
    }

    final byId = {for (final object in context.catalog) object.id: object};
    final results = <CatalogCaptureProjection>[];
    var changed = false;
    for (final id in targetIds) {
      final object = byId[id];
      if (object == null) {
        AppLogger.info(_tag, 'Skipping missing canonical catalog id=$id');
        _dirtyIdentities.add(id);
        continue;
      }
      try {
        final outcome = await _projectOne(object, context);
        results.add(outcome.projection);
        changed = changed || outcome.changed;
        _dirtyIdentities.remove(id);
      } catch (error, stackTrace) {
        _dirtyIdentities.add(id);
        AppLogger.error(_tag, error, stackTrace);
      }
    }

    // A secondary row may carry an old V1 flag even though its primary row is
    // now canonical. Clear it so only the canonical row owns the projection.
    for (final object in context.catalog) {
      if (!object.captured || object.effectivePrimaryId == object.id) continue;
      try {
        changed =
            await _write(
              object,
              const CatalogCaptureProjection(
                catalogObjectId: '',
                captured: false,
                capturedDate: null,
                photoCount: 0,
                localCount: 0,
                remoteCount: 0,
                deduplicatedCount: 0,
                latestCapturedAt: null,
              ),
            ) ||
            changed;
      } catch (error, stackTrace) {
        _dirtyIdentities.add(object.id);
        AppLogger.error(_tag, error, stackTrace);
      }
    }
    if (changed) notifyListeners();
    return results;
  });

  Future<T> _serialized<T>(Future<T> Function() operation) {
    final completer = Completer<T>();
    _tail = _tail.then((_) async {
      try {
        completer.complete(await operation());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  Future<_ProjectionContext> _loadContext({required bool includeRemote}) async {
    final catalog = await _catalogRepository.getAll(listOnly: true);
    final exactByLowerId = {
      for (final object in catalog) object.id.toLowerCase(): object,
    };
    final local = await _localRecords.getAll();
    final remote = includeRemote
        ? (await _galleryRepository.getSnapshot()).items
        : const <GalleryItem>[];
    final links = includeRemote
        ? await _recordLinks.localIdsByBackendRecordId()
        : const <String, String>{};

    final localKeys = <String, String>{};
    for (final record in local) {
      final photoUri = record.photoUri?.trim();
      localKeys[record.id] = photoUri == null || photoUri.isEmpty
          ? 'local-record:${record.id}'
          : 'local-file:$photoUri';
    }

    final facts = <_CaptureFact>[];
    for (final record in local) {
      final target = _identityResolver.resolve(
        record.celestialObjectId,
        catalog,
        exactByLowerId: exactByLowerId,
      );
      if (target == null) {
        AppLogger.info(
          _tag,
          'Ignoring local record with unknown catalog id=${record.celestialObjectId}',
        );
        continue;
      }
      facts.add(
        _CaptureFact(
          catalogObjectId: target.id,
          identityKey: localKeys[record.id]!,
          capturedAt: record.capturedAt,
          local: true,
        ),
      );
    }

    for (final item in remote) {
      final target = _identityResolver.resolve(
        item.catalogObjectId,
        catalog,
        exactByLowerId: exactByLowerId,
      );
      if (target == null) {
        AppLogger.info(
          _tag,
          'Ignoring remote record with unknown catalog id=${item.catalogObjectId}',
        );
        continue;
      }
      final linkedLocalId = links[item.backendRecordId];
      final linkedKey = linkedLocalId == null ? null : localKeys[linkedLocalId];
      final fileId = item.backendFileId.trim();
      facts.add(
        _CaptureFact(
          catalogObjectId: target.id,
          identityKey:
              linkedKey ??
              (fileId.isNotEmpty
                  ? 'remote-file:$fileId'
                  : 'remote-record:${item.backendRecordId}'),
          capturedAt: item.capturedAt,
          local: false,
        ),
      );
    }
    return _ProjectionContext(
      catalog: catalog,
      exactByLowerId: exactByLowerId,
      facts: facts,
    );
  }

  Future<_ProjectionOutcome> _projectOne(
    CatalogObject object,
    _ProjectionContext context,
  ) async {
    final matching = context.facts
        .where((fact) => fact.catalogObjectId == object.id)
        .toList(growable: false);
    final unique = <String, DateTime>{};
    final localKeys = <String>{};
    final remoteKeys = <String>{};
    for (final fact in matching) {
      final previous = unique[fact.identityKey];
      if (previous == null || fact.capturedAt.isAfter(previous)) {
        unique[fact.identityKey] = fact.capturedAt;
      }
      (fact.local ? localKeys : remoteKeys).add(fact.identityKey);
    }
    DateTime? latest;
    for (final value in unique.values) {
      if (latest == null || value.isAfter(latest)) latest = value;
    }
    final result = CatalogCaptureProjection(
      catalogObjectId: object.id,
      captured: unique.isNotEmpty,
      capturedDate: latest == null ? null : _date(latest),
      photoCount: unique.length,
      localCount: localKeys.length,
      remoteCount: remoteKeys.length,
      deduplicatedCount: matching.length - unique.length,
      latestCapturedAt: latest,
    );
    final changed = await _write(object, result);
    AppLogger.info(
      _tag,
      'id=${object.id} local=${result.localCount} remote=${result.remoteCount} '
      'dedup=${result.deduplicatedCount} captured=${result.captured} '
      'count=${result.photoCount}',
    );
    return _ProjectionOutcome(projection: result, changed: changed);
  }

  Future<bool> _write(
    CatalogObject current,
    CatalogCaptureProjection projection,
  ) async {
    if (current.captured == projection.captured &&
        current.capturedDate == projection.capturedDate) {
      return false;
    }
    final repository = _catalogRepository;
    final int affected;
    if (repository is CatalogCaptureProjectionWriter) {
      affected = await (repository as CatalogCaptureProjectionWriter)
          .updateCaptureProjection(
            current.id,
            captured: projection.captured,
            capturedDate: projection.capturedDate,
          );
    } else {
      await repository.updateCaptured(
        current.id,
        captured: projection.captured,
        capturedDate: projection.capturedDate,
      );
      affected = await repository.getById(current.id) == null ? 0 : 1;
    }
    if (affected == 0) {
      throw CatalogCaptureProjectionException(
        'Catalog projection updated 0 rows for id=${current.id}',
      );
    }
    AppLogger.info(_tag, 'id=${current.id} affectedRows=$affected');
    return true;
  }

  static String _date(DateTime value) {
    final local = value.toLocal();
    return '${local.year.toString().padLeft(4, '0')}-'
        '${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')}';
  }
}

class _ProjectionContext {
  const _ProjectionContext({
    required this.catalog,
    required this.exactByLowerId,
    required this.facts,
  });

  final List<CatalogObject> catalog;
  final Map<String, CatalogObject> exactByLowerId;
  final List<_CaptureFact> facts;
}

class _ProjectionOutcome {
  const _ProjectionOutcome({required this.projection, required this.changed});

  final CatalogCaptureProjection projection;
  final bool changed;
}

class _CaptureFact {
  const _CaptureFact({
    required this.catalogObjectId,
    required this.identityKey,
    required this.capturedAt,
    required this.local,
  });

  final String catalogObjectId;
  final String identityKey;
  final DateTime capturedAt;
  final bool local;
}
