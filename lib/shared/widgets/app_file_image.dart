import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/tc_backend_auth_service.dart';

/// 파일 이미지를 화면 크기에 맞게 디코드해 전환 버벅임을 줄인다.
///
/// `Image.file`에 [cacheWidth]/[cacheHeight]를 주지 않으면 원본(수 MB~수십 MB)
/// JPEG를 통째로 디코드해 Navigator push 시 프레임이 끊긴다.
///
/// `width: double.infinity`처럼 무한대 레이아웃 폭이 오면 cache 계산에서
/// `Infinity.toInt()` 오류가 나므로, finite 값만 cache에 사용한다.
///
/// [memoryImage]가 있으면 파일 재로드 없이 동일 [MemoryImage]를 재사용한다.
class AppFileImage extends StatelessWidget {
  const AppFileImage({
    super.key,
    required this.path,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.memCacheWidth,
    this.memCacheHeight,
    this.filterQuality = FilterQuality.low,
    this.gaplessPlayback = true,
    this.errorBuilder,
    this.memoryImage,
  });

  /// 목록/썸네일용 — 높이·폭 기준으로 캐시 크기를 잡는다.
  factory AppFileImage.thumbnail({
    Key? key,
    required String path,
    double? width,
    double height = 220,
    BoxFit fit = BoxFit.cover,
    ImageErrorWidgetBuilder? errorBuilder,
    MemoryImage? memoryImage,
  }) {
    return AppFileImage(
      key: key,
      path: path,
      width: width,
      height: height,
      fit: fit,
      errorBuilder: errorBuilder,
      memoryImage: memoryImage,
    );
  }

  final String path;
  final double? width;
  final double? height;
  final BoxFit fit;
  final int? memCacheWidth;
  final int? memCacheHeight;
  final FilterQuality filterQuality;
  final bool gaplessPlayback;
  final ImageErrorWidgetBuilder? errorBuilder;

  /// 등록 세션 등에서 미리 로드한 [MemoryImage]. 있으면 파일 I/O·재디코드 방지.
  final MemoryImage? memoryImage;

  static int? _cachePx(double? logical, double dpr) {
    if (logical == null) return null;
    if (!logical.isFinite || logical <= 0) return null;
    return math.max(1, (logical * dpr).round());
  }

  static int _safeScreenPx(BuildContext context, {required bool longest}) {
    final size = MediaQuery.sizeOf(context);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final side = longest ? size.longestSide : size.shortestSide;
    if (!side.isFinite || side <= 0 || !dpr.isFinite || dpr <= 0) {
      return 1080;
    }
    return (side * dpr).round().clamp(1, 2048);
  }

  static bool _isNetworkPath(String path) {
    final uri = Uri.tryParse(path);
    return uri != null && (uri.scheme == 'http' || uri.scheme == 'https');
  }

  /// 전체보기용 ImageProvider (화면 장축 × DPR, 최대 2048).
  static ImageProvider viewerProvider(BuildContext context, String path) {
    final maxPx = _safeScreenPx(context, longest: true);
    final provider = _isNetworkPath(path)
        ? NetworkImage(path) as ImageProvider
        : FileImage(File(path));
    return ResizeImage(provider, width: maxPx);
  }

  static Future<void> precacheForViewer(BuildContext context, String path) {
    return precacheImage(viewerProvider(context, path), context);
  }

  static Future<void> precacheThumbnail(
    BuildContext context,
    String path, {
    double height = 220,
  }) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final h = _cachePx(height, dpr.isFinite && dpr > 0 ? dpr : 2.0) ?? 440;
    return precacheImage(
      ResizeImage(
        _isNetworkPath(path) ? NetworkImage(path) : FileImage(File(path)),
        height: h,
      ),
      context,
    );
  }

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final safeDpr = (dpr.isFinite && dpr > 0) ? dpr : 2.0;

    // Layout용 width는 infinity 허용. decode cache만 finite로 잡는다.
    var cw = memCacheWidth ?? _cachePx(width, safeDpr);
    var ch = memCacheHeight ?? _cachePx(height, safeDpr);

    // 폭이 infinity인 썸네일(가로 full) → 화면 폭 기준으로 cacheWidth
    if (cw == null && ch != null) {
      final screenW = MediaQuery.sizeOf(context).width;
      cw = _cachePx(screenW, safeDpr) ?? _safeScreenPx(context, longest: false);
    }
    if (cw == null && ch == null) {
      ch = _safeScreenPx(context, longest: false);
    }

    if (memoryImage != null) {
      ImageProvider provider = memoryImage!;
      if (cw != null || ch != null) {
        provider = ResizeImage(provider, width: cw, height: ch);
      }
      return RepaintBoundary(
        child: Image(
          image: provider,
          width: width,
          height: height,
          fit: fit,
          filterQuality: filterQuality,
          gaplessPlayback: gaplessPlayback,
          errorBuilder: errorBuilder,
        ),
      );
    }

    if (_isNetworkPath(path) || path.startsWith('/api/')) {
      final mediaAuth = context.read<TcBackendMediaAuthService?>();
      if (mediaAuth == null) {
        if (_isNetworkPath(path)) {
          return RepaintBoundary(child: _networkImage(path, cw, ch));
        }
      } else {
        return RepaintBoundary(
          child: FutureBuilder<TcBackendMediaRequest>(
            future: mediaAuth.requestFor(path),
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return SizedBox(width: width, height: height);
              }
              final request = snapshot.data;
              if (request == null || !_isNetworkPath(request.url)) {
                return _fileImage(cw, ch);
              }
              return _networkImage(
                request.url,
                cw,
                ch,
                headers: request.headers,
              );
            },
          ),
        );
      }
    }

    return RepaintBoundary(child: _fileImage(cw, ch));
  }

  Widget _networkImage(
    String url,
    int? cacheWidth,
    int? cacheHeight, {
    Map<String, String>? headers,
  }) => Image.network(
    url,
    headers: headers,
    width: width,
    height: height,
    fit: fit,
    cacheWidth: cacheWidth,
    cacheHeight: cacheHeight,
    filterQuality: filterQuality,
    gaplessPlayback: gaplessPlayback,
    errorBuilder: errorBuilder,
  );

  Widget _fileImage(int? cacheWidth, int? cacheHeight) => Image.file(
    File(path),
    width: width,
    height: height,
    fit: fit,
    cacheWidth: cacheWidth,
    cacheHeight: cacheHeight,
    filterQuality: filterQuality,
    gaplessPlayback: gaplessPlayback,
    errorBuilder: errorBuilder,
  );
}
