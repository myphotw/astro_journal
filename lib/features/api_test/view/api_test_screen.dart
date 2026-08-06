import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/models/api_test_result.dart';
import '../../../data/models/weather_data.dart';
import '../viewmodel/api_test_view_model.dart';

class ApiTestScreen extends StatefulWidget {
  const ApiTestScreen({super.key});

  @override
  State<ApiTestScreen> createState() => _ApiTestScreenState();
}

class _ApiTestScreenState extends State<ApiTestScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ApiTestViewModel>().checkStorage();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('API 테스트'),
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          _DevBanner(),
          SizedBox(height: 16),
          _GpsTestCard(),
          SizedBox(height: 12),
          _AstronomyTestCard(),
          SizedBox(height: 12),
          _WeatherTestCard(),
          SizedBox(height: 12),
          _MapTestCard(),
          SizedBox(height: 12),
          _StorageTestCard(),
          SizedBox(height: 24),
        ],
      ),
    );
  }
}

// ── Dev Banner ──────────────────────────────────────────────────────────────

class _DevBanner extends StatelessWidget {
  const _DevBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(Icons.bug_report_outlined,
              size: 16, color: Colors.amber.shade300),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '개발/장애 확인 전용 화면입니다.',
              style: TextStyle(
                color: Colors.amber.shade300,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Shared Widgets ──────────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: AppColors.messier,
                fontWeight: FontWeight.w700,
                fontSize: 14,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _TestResultCard extends StatelessWidget {
  const _TestResultCard({required this.result});

  final ApiTestResult result;

  @override
  Widget build(BuildContext context) {
    final color = result.success ? Colors.green : Colors.red;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                result.success ? Icons.check_circle_outline : Icons.error_outline,
                size: 16,
                color: color,
              ),
              const SizedBox(width: 6),
              Text(
                result.success ? 'API 성공' : 'API 실패',
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
              const Spacer(),
              if (result.responseTimeMs != null)
                Text(
                  '${result.responseTimeMs} ms',
                  style: TextStyle(color: color, fontSize: 12),
                ),
            ],
          ),
          if (result.statusCode != null) ...[
            const SizedBox(height: 4),
            _InfoRow(
              label: 'HTTP',
              value: result.statusCode.toString(),
              valueColor: color,
            ),
          ],
          const SizedBox(height: 4),
          _InfoRow(label: '메시지', value: result.message),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
    this.valueColor,
  });

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 72,
          child: Text(
            label,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              color: valueColor ?? AppColors.textPrimary,
              fontSize: 12,
              fontFamily: 'monospace',
            ),
          ),
        ),
      ],
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.label,
    required this.onPressed,
    this.loading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: loading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.messier.withValues(alpha: 0.15),
          foregroundColor: AppColors.messier,
          side: BorderSide(color: AppColors.messier.withValues(alpha: 0.4)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: loading
            ? const SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.messier,
                ),
              )
            : Text(label),
      ),
    );
  }
}

// ── GPS Test Card ───────────────────────────────────────────────────────────

class _GpsTestCard extends StatelessWidget {
  const _GpsTestCard();

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ApiTestViewModel>();

    return _SectionCard(
      title: '① GPS 테스트',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PrimaryButton(
            label: '현재 위치 가져오기',
            loading: vm.gpsLoading,
            onPressed: () => context.read<ApiTestViewModel>().testGps(),
          ),
          if (vm.gpsPermission != null || vm.gpsServiceEnabled != null) ...[
            const SizedBox(height: 12),
            _GpsResultWidget(vm: vm),
          ],
        ],
      ),
    );
  }
}

class _GpsResultWidget extends StatelessWidget {
  const _GpsResultWidget({required this.vm});

  final ApiTestViewModel vm;

  @override
  Widget build(BuildContext context) {
    final hasLocation = vm.gpsLocation != null;
    final color = vm.gpsError != null
        ? Colors.red
        : hasLocation
            ? Colors.green
            : Colors.orange;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (vm.gpsPermission != null)
            _InfoRow(label: '권한', value: vm.gpsPermission!.label),
          _InfoRow(
            label: 'GPS 활성',
            value: vm.gpsServiceEnabled == true ? '켜짐' : '꺼짐',
          ),
          if (vm.gpsError != null)
            _InfoRow(label: '오류', value: vm.gpsError!, valueColor: Colors.red),
          if (vm.gpsLocation != null) ...[
            _InfoRow(
              label: '위도',
              value: vm.gpsLocation!.latitude.toStringAsFixed(6),
            ),
            _InfoRow(
              label: '경도',
              value: vm.gpsLocation!.longitude.toStringAsFixed(6),
            ),
            _InfoRow(
              label: '정확도',
              value: '±${vm.gpsLocation!.accuracy.toStringAsFixed(1)} m',
            ),
            _InfoRow(
              label: '측정 시간',
              value: _formatTime(vm.gpsLocation!.timestamp),
            ),
          ],
        ],
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final local = dt.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}:'
        '${local.second.toString().padLeft(2, '0')}';
  }
}

// ── Astronomy Test Card ─────────────────────────────────────────────────────

class _AstronomyTestCard extends StatelessWidget {
  const _AstronomyTestCard();

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ApiTestViewModel>();

    return _SectionCard(
      title: '② Astronomy API 테스트',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '저장된 Application ID / Secret을 사용합니다.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 10),
          _PrimaryButton(
            label: '테스트',
            loading: vm.astronomyLoading,
            onPressed: () =>
                context.read<ApiTestViewModel>().testAstronomy(),
          ),
          if (vm.astronomyResult != null) ...[
            const SizedBox(height: 12),
            _TestResultCard(result: vm.astronomyResult!),
            if (vm.astronomyResult!.success &&
                vm.astronomyResult!.data != null) ...[
              const SizedBox(height: 8),
              _JsonPreview(
                data: vm.astronomyResult!.data!,
                viewModel: vm,
              ),
            ],
          ],
        ],
      ),
    );
  }
}

// ── Weather Test Card ───────────────────────────────────────────────────────

class _WeatherTestCard extends StatelessWidget {
  const _WeatherTestCard();

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ApiTestViewModel>();

    return _SectionCard(
      title: '③ Weather API 테스트',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '현재 GPS 위치를 사용합니다.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 10),
          _PrimaryButton(
            label: '테스트',
            loading: vm.weatherLoading,
            onPressed: () =>
                context.read<ApiTestViewModel>().testWeather(),
          ),
          if (vm.weatherResult != null) ...[
            const SizedBox(height: 12),
            _TestResultCard(result: vm.weatherResult!),
            if (vm.weatherData != null) ...[
              const SizedBox(height: 8),
              _WeatherDataWidget(data: vm.weatherData!),
            ],
            if (vm.weatherResult!.success &&
                vm.weatherResult!.data != null) ...[
              const SizedBox(height: 8),
              _JsonPreview(
                data: vm.weatherResult!.data!,
                viewModel: vm,
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _WeatherDataWidget extends StatelessWidget {
  const _WeatherDataWidget({required this.data});

  final WeatherData data;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blueGrey.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blueGrey.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _InfoRow(
              label: '기온',
              value: '${data.temperature.toStringAsFixed(1)} °C'),
          _InfoRow(
              label: '체감온도',
              value: '${data.feelsLike.toStringAsFixed(1)} °C'),
          _InfoRow(label: '습도', value: '${data.humidity} %'),
          _InfoRow(
              label: '풍속',
              value: '${data.windSpeed.toStringAsFixed(1)} m/s'),
          _InfoRow(
              label: '풍향',
              value: '${data.windDirectionLabel} (${data.windDegree}°)'),
          _InfoRow(label: '기압', value: '${data.pressure} hPa'),
          _InfoRow(label: '구름량', value: '${data.cloudCoverage} %'),
          _InfoRow(
              label: '가시거리',
              value: '${(data.visibility / 1000).toStringAsFixed(1)} km'),
          _InfoRow(
              label: '일출',
              value: _formatTime(data.sunrise)),
          _InfoRow(
              label: '일몰',
              value: _formatTime(data.sunset)),
          if (data.description.isNotEmpty)
            _InfoRow(label: '날씨', value: data.description),
          if (data.cityName.isNotEmpty)
            _InfoRow(label: '도시', value: data.cityName),
        ],
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final local = dt.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }
}

// ── Map API Test Card ───────────────────────────────────────────────────────

class _MapTestCard extends StatelessWidget {
  const _MapTestCard();

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ApiTestViewModel>();

    return _SectionCard(
      title: '④ Map API 테스트',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'API Key 확인 · GPS 위치 · Reverse Geocoding · 지도 표시 가능 여부',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 10),
          _PrimaryButton(
            label: '지도 테스트',
            loading: vm.mapLoading,
            onPressed: () => context.read<ApiTestViewModel>().testMap(),
          ),
          if (vm.mapResult != null) ...[
            const SizedBox(height: 12),
            _TestResultCard(result: vm.mapResult!),
            if (vm.mapResult!.success && vm.mapGeoResult != null) ...[
              const SizedBox(height: 8),
              _MapResultWidget(
                vm: vm,
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _MapResultWidget extends StatelessWidget {
  const _MapResultWidget({required this.vm});

  final ApiTestViewModel vm;

  @override
  Widget build(BuildContext context) {
    final geo = vm.mapGeoResult;
    final loc = vm.mapGpsLocation;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.green.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _InfoRow(
            label: 'API 인증',
            value: 'API Key 확인됨',
            valueColor: Colors.green,
          ),
          if (geo != null) ...[
            _InfoRow(label: '촬영지명', value: geo.locationName),
            _InfoRow(label: '현재 주소', value: geo.address),
          ],
          if (loc != null) ...[
            _InfoRow(
              label: '위도',
              value: loc.latitude.toStringAsFixed(6),
            ),
            _InfoRow(
              label: '경도',
              value: loc.longitude.toStringAsFixed(6),
            ),
          ],
          _InfoRow(
            label: '지도 표시',
            value: vm.hasGoogleMapsKey == true ? '가능' : '불가 (API Key 없음)',
            valueColor: vm.hasGoogleMapsKey == true ? Colors.green : Colors.red,
          ),
          if (vm.mapResult?.responseTimeMs != null)
            _InfoRow(
              label: '응답시간',
              value: '${vm.mapResult!.responseTimeMs} ms',
            ),
          if (vm.mapResult?.statusCode != null)
            _InfoRow(
              label: 'HTTP',
              value: vm.mapResult!.statusCode.toString(),
            ),
          if (vm.mapResult?.data != null) ...[
            const SizedBox(height: 4),
            _JsonPreview(data: vm.mapResult!.data!, viewModel: vm),
          ],
        ],
      ),
    );
  }
}

// ── Secure Storage Test Card ────────────────────────────────────────────────

class _StorageTestCard extends StatelessWidget {
  const _StorageTestCard();

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ApiTestViewModel>();

    return _SectionCard(
      title: '⑤ Secure Storage 테스트',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PrimaryButton(
            label: '저장 상태 확인',
            loading: vm.storageLoading,
            onPressed: () =>
                context.read<ApiTestViewModel>().checkStorage(),
          ),
          if (!vm.storageLoading &&
              (vm.hasAstronomySecret != null ||
                  vm.hasWeatherKey != null ||
                  vm.hasGoogleMapsKey != null)) ...[
            const SizedBox(height: 12),
            _StorageResultWidget(vm: vm),
          ],
        ],
      ),
    );
  }
}

class _StorageResultWidget extends StatelessWidget {
  const _StorageResultWidget({required this.vm});

  final ApiTestViewModel vm;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.textSecondary.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _StorageRow(
            label: 'Google Maps Key',
            value: vm.hasGoogleMapsKey == true ? '저장됨' : '미저장',
            stored: vm.hasGoogleMapsKey == true,
          ),
          const SizedBox(height: 8),
          _StorageRow(
            label: 'Astronomy ID',
            value: vm.maskedAstronomyId ?? '미저장',
            stored: vm.maskedAstronomyId != null,
          ),
          const SizedBox(height: 8),
          _StorageRow(
            label: 'Astronomy Secret',
            value: vm.hasAstronomySecret == true ? '저장됨' : '미저장',
            stored: vm.hasAstronomySecret == true,
          ),
          const SizedBox(height: 8),
          _StorageRow(
            label: 'Weather API Key',
            value: vm.hasWeatherKey == true ? '저장됨' : '미저장',
            stored: vm.hasWeatherKey == true,
          ),
        ],
      ),
    );
  }
}

class _StorageRow extends StatelessWidget {
  const _StorageRow({
    required this.label,
    required this.value,
    required this.stored,
  });

  final String label;
  final String value;
  final bool stored;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 11,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(
                  color: stored ? AppColors.textPrimary : AppColors.textSecondary,
                  fontSize: 13,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: stored
                ? Colors.green.withValues(alpha: 0.15)
                : Colors.grey.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            stored ? '저장됨' : '미저장',
            style: TextStyle(
              color: stored ? Colors.greenAccent : AppColors.textSecondary,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

// ── JSON Preview ────────────────────────────────────────────────────────────

class _JsonPreview extends StatefulWidget {
  const _JsonPreview({required this.data, required this.viewModel});

  final Map<String, dynamic> data;
  final ApiTestViewModel viewModel;

  @override
  State<_JsonPreview> createState() => _JsonPreviewState();
}

class _JsonPreviewState extends State<_JsonPreview> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final preview = widget.viewModel.jsonPreview(widget.data);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Row(
            children: [
              Icon(
                _expanded ? Icons.expand_less : Icons.expand_more,
                size: 16,
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: 4),
              Text(
                _expanded ? 'JSON 숨기기' : '응답 JSON 보기',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        if (_expanded && preview != null) ...[
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              preview,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 10,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ],
    );
  }
}
