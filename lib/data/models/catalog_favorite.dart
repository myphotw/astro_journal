class CatalogFavorite {
  const CatalogFavorite({
    required this.catalogObjectId,
    required this.createdAt,
    required this.updatedAt,
  });

  final String catalogObjectId;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory CatalogFavorite.fromJson(Map<String, dynamic> json) {
    final id = json['catalog_object_id']?.toString().trim();
    final createdAt = DateTime.tryParse(json['created_at']?.toString() ?? '');
    final updatedAt = DateTime.tryParse(json['updated_at']?.toString() ?? '');
    if (id == null || id.isEmpty || createdAt == null || updatedAt == null) {
      throw const FormatException('Invalid catalog favorite payload.');
    }
    return CatalogFavorite(
      catalogObjectId: id,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'catalog_object_id': catalogObjectId,
    'created_at': createdAt.toUtc().toIso8601String(),
    'updated_at': updatedAt.toUtc().toIso8601String(),
  };
}

class CatalogFavoriteDeleteResult {
  const CatalogFavoriteDeleteResult({
    required this.catalogObjectId,
    required this.deleted,
  });

  final String catalogObjectId;
  final bool deleted;

  factory CatalogFavoriteDeleteResult.fromJson(Map<String, dynamic> json) {
    final id = json['catalog_object_id']?.toString().trim();
    final deleted = json['deleted'];
    if (id == null || id.isEmpty || deleted is! bool) {
      throw const FormatException('Invalid catalog favorite delete payload.');
    }
    return CatalogFavoriteDeleteResult(catalogObjectId: id, deleted: deleted);
  }
}
