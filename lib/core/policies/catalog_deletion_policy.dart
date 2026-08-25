/// Catalog 대상 삭제 가능 여부를 한 곳에서 판정한다.
///
/// 기존 앱이 생성한 사용자 대상은 UUID v4를 ID로 사용한다. 번들 seed DB의
/// 13,557개 ID에는 UUID v4가 없으므로, 별도 schema migration 없이 이 규칙을
/// 기존 사용자 데이터에도 적용할 수 있다. 새 사용자 대상에는 명시적인 tag도
/// 함께 저장하여 향후 ID 정책이 바뀌어도 소유권을 보존한다.
abstract final class CatalogDeletionPolicy {
  static const String userCreatedTag = 'astrojournal:user-created';
  static const String deletedTag = 'astrojournal:deleted';

  static final RegExp _uuidV4 = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-4[0-9a-fA-F]{3}-'
    r'[89aAbB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
  );

  static bool isCustom({required String id, Iterable<String> tags = const []}) {
    return tags.contains(userCreatedTag) || _uuidV4.hasMatch(id);
  }

  static bool isDeleted(Iterable<String> tags) => tags.contains(deletedTag);

  static bool canDelete({
    required String id,
    Iterable<String> tags = const [],
  }) {
    return isCustom(id: id, tags: tags) && !isDeleted(tags);
  }
}
