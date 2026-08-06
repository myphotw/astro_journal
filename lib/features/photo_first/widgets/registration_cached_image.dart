import 'package:flutter/material.dart';

import '../models/registration_session.dart';

/// 등록 세션의 [MemoryImage]를 고정 표시한다.
///
/// 부모 리빌드·단계 전환과 무관하게 동일 [ImageProvider]를 재사용한다.
class RegistrationCachedImage extends StatelessWidget {
  const RegistrationCachedImage({
    super.key,
    required this.session,
    this.height = 180,
    this.onTap,
  });

  final RegistrationSession session;
  final double height;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final provider = session.displayThumbnailProvider;
    final child = RepaintBoundary(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          height: height,
          width: double.infinity,
          child: provider == null
              ? const ColoredBox(
                  color: Color(0xFF1A1A2E),
                  child: Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                )
              : Image(
                  image: provider,
                  height: height,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  filterQuality: FilterQuality.low,
                  errorBuilder: (_, _, _) => const ColoredBox(
                    color: Color(0xFF1A1A2E),
                    child: Center(
                      child: Icon(
                        Icons.broken_image_outlined,
                        color: Colors.white54,
                        size: 40,
                      ),
                    ),
                  ),
                ),
        ),
      ),
    );

    if (onTap == null) return child;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          children: [
            child,
            Positioned(
              right: 10,
              bottom: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.zoom_out_map, size: 18, color: Colors.white),
                    SizedBox(width: 6),
                    Text(
                      '전체보기',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
