import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../services/google_maps_key_readiness.dart';

/// Builds [builder] only after the native Google Maps API key is ready.
class GoogleMapGate extends StatefulWidget {
  const GoogleMapGate({
    super.key,
    required this.builder,
    this.missingKeyPlaceholder,
  });

  final WidgetBuilder builder;
  final WidgetBuilder? missingKeyPlaceholder;

  @override
  State<GoogleMapGate> createState() => _GoogleMapGateState();
}

class _GoogleMapGateState extends State<GoogleMapGate> {
  late Future<bool> _readyFuture;

  @override
  void initState() {
    super.initState();
    _readyFuture = GoogleMapsKeyReadiness.isReady();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _readyFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(
            child: SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }

        if (snapshot.data != true) {
          if (widget.missingKeyPlaceholder != null) {
            return widget.missingKeyPlaceholder!(context);
          }
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                '지도 구성을 사용할 수 없습니다. 앱 빌드 상태를 확인해 주세요.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
            ),
          );
        }

        return widget.builder(context);
      },
    );
  }
}
