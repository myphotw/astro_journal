import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../services/api_key_service.dart';
import '../../../services/astronomy_service.dart';
import '../../../services/plate_solve/astrometry_net_provider.dart';
import '../../../services/plate_solve_settings_service.dart';
import '../../../services/weather_service.dart';
import '../viewmodel/settings_view_model.dart';

class ApiSettingsScreen extends StatelessWidget {
  const ApiSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('API 관리'),
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _AstronomyApiCard(
            astronomyService: context.read<AstronomyService>(),
          ),
          const SizedBox(height: 12),
          _WeatherApiCard(
            weatherService: context.read<WeatherService>(),
          ),
          const SizedBox(height: 12),
          _AstrometryApiCard(
            provider: context.read<AstrometryNetProvider>(),
            settingsService: context.read<PlateSolveSettingsService>(),
          ),
          const SizedBox(height: 12),
          _GoogleMapsApiCard(),
        ],
      ),
    );
  }
}

// ── Shared helpers ──────────────────────────────────────────────────────────

class _ApiCard extends StatelessWidget {
  const _ApiCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppColors.surface,
      margin: EdgeInsets.zero,
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
              ),
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }
}

class _SecureField extends StatefulWidget {
  const _SecureField({
    required this.label,
    required this.controller,
    this.obscured = false,
  });

  final String label;
  final TextEditingController controller;
  final bool obscured;

  @override
  State<_SecureField> createState() => _SecureFieldState();
}

class _SecureFieldState extends State<_SecureField> {
  late bool _obscure;

  @override
  void initState() {
    super.initState();
    _obscure = widget.obscured;
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      obscureText: _obscure,
      style: const TextStyle(
        color: AppColors.textPrimary,
        fontSize: 13,
        fontFamily: 'monospace',
      ),
      decoration: InputDecoration(
        labelText: widget.label,
        labelStyle:
            const TextStyle(color: AppColors.textSecondary, fontSize: 13),
        enabledBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: AppColors.textSecondary),
        ),
        focusedBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: AppColors.messier),
        ),
        suffixIcon: widget.obscured
            ? IconButton(
                icon: Icon(
                  _obscure ? Icons.visibility_off : Icons.visibility,
                  size: 18,
                  color: AppColors.textSecondary,
                ),
                onPressed: () => setState(() => _obscure = !_obscure),
              )
            : null,
      ),
    );
  }
}

// ── Astronomy API Card ──────────────────────────────────────────────────────

class _AstronomyApiCard extends StatefulWidget {
  const _AstronomyApiCard({required this.astronomyService});

  final AstronomyService astronomyService;

  @override
  State<_AstronomyApiCard> createState() => _AstronomyApiCardState();
}

class _AstronomyApiCardState extends State<_AstronomyApiCard> {
  final _idController = TextEditingController();
  final _secretController = TextEditingController();
  bool _saving = false;
  bool _testing = false;
  String? _testMessage;
  bool? _testSuccess;

  @override
  void initState() {
    super.initState();
    _loadSavedValues();
  }

  @override
  void dispose() {
    _idController.dispose();
    _secretController.dispose();
    super.dispose();
  }

  Future<void> _loadSavedValues() async {
    final vm = context.read<SettingsViewModel>();
    _idController.text = vm.apiKeys[ApiKeyType.astronomyAppId] ?? '';
  }

  Future<void> _save() async {
    final id = _idController.text.trim();
    final secret = _secretController.text.trim();
    if (id.isEmpty && secret.isEmpty) {
      _showSnack('Application ID 또는 Secret을 입력해주세요.');
      return;
    }

    setState(() => _saving = true);
    final vm = context.read<SettingsViewModel>();
    if (id.isNotEmpty) await vm.saveApiKey(ApiKeyType.astronomyAppId, id);
    if (secret.isNotEmpty) {
      await vm.saveApiKey(ApiKeyType.astronomyAppSecret, secret);
    }
    if (mounted) {
      setState(() => _saving = false);
      _showSnack('Astronomy API 인증 정보가 저장되었습니다.');
    }
  }

  Future<void> _test() async {
    setState(() {
      _testing = true;
      _testMessage = null;
      _testSuccess = null;
    });
    final result = await widget.astronomyService.testConnection();
    if (mounted) {
      setState(() {
        _testing = false;
        _testSuccess = result.success;
        _testMessage = result.success
            ? '성공 · HTTP ${result.statusCode} · ${result.responseTimeMs} ms'
            : result.message;
      });
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return _ApiCard(
      title: 'Astronomy API',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SecureField(
            label: 'Application ID',
            controller: _idController,
          ),
          const SizedBox(height: 12),
          _SecureField(
            label: 'Application Secret',
            controller: _secretController,
            obscured: true,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _ActionButton(
                  label: '저장',
                  loading: _saving,
                  onPressed: _save,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ActionButton(
                  label: '연결 테스트',
                  loading: _testing,
                  onPressed: _test,
                  outlined: true,
                ),
              ),
            ],
          ),
          if (_testMessage != null) ...[
            const SizedBox(height: 10),
            _InlineTestResult(success: _testSuccess!, message: _testMessage!),
          ],
        ],
      ),
    );
  }
}

// ── Weather API Card ────────────────────────────────────────────────────────

class _WeatherApiCard extends StatefulWidget {
  const _WeatherApiCard({required this.weatherService});

  final WeatherService weatherService;

  @override
  State<_WeatherApiCard> createState() => _WeatherApiCardState();
}

class _WeatherApiCardState extends State<_WeatherApiCard> {
  final _keyController = TextEditingController();
  bool _saving = false;
  bool _testing = false;
  String? _testMessage;
  bool? _testSuccess;

  // Seoul coordinates for quick connection test.
  static const _testLat = 37.5665;
  static const _testLon = 126.9780;

  @override
  void initState() {
    super.initState();
    _loadSavedValues();
  }

  @override
  void dispose() {
    _keyController.dispose();
    super.dispose();
  }

  void _loadSavedValues() {
    final vm = context.read<SettingsViewModel>();
    _keyController.text = vm.apiKeys[ApiKeyType.weather] ?? '';
  }

  Future<void> _save() async {
    final key = _keyController.text.trim();
    if (key.isEmpty) {
      _showSnack('API Key를 입력해주세요.');
      return;
    }
    setState(() => _saving = true);
    await context.read<SettingsViewModel>().saveApiKey(ApiKeyType.weather, key);
    if (mounted) {
      setState(() => _saving = false);
      _showSnack('Weather API Key가 저장되었습니다.');
    }
  }

  Future<void> _test() async {
    setState(() {
      _testing = true;
      _testMessage = null;
      _testSuccess = null;
    });
    final result = await widget.weatherService.testConnection(_testLat, _testLon);
    if (mounted) {
      setState(() {
        _testing = false;
        _testSuccess = result.success;
        _testMessage = result.success
            ? '성공 · HTTP ${result.statusCode} · ${result.responseTimeMs} ms'
            : result.message;
      });
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return _ApiCard(
      title: 'Weather API',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SecureField(label: 'API Key', controller: _keyController),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _ActionButton(
                  label: '저장',
                  loading: _saving,
                  onPressed: _save,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ActionButton(
                  label: '연결 테스트',
                  loading: _testing,
                  onPressed: _test,
                  outlined: true,
                ),
              ),
            ],
          ),
          if (_testMessage != null) ...[
            const SizedBox(height: 10),
            _InlineTestResult(success: _testSuccess!, message: _testMessage!),
          ],
        ],
      ),
    );
  }
}

// ── Astrometry.net API Card ─────────────────────────────────────────────────

class _AstrometryApiCard extends StatefulWidget {
  const _AstrometryApiCard({
    required this.provider,
    required this.settingsService,
  });

  final AstrometryNetProvider provider;
  final PlateSolveSettingsService settingsService;

  @override
  State<_AstrometryApiCard> createState() => _AstrometryApiCardState();
}

class _AstrometryApiCardState extends State<_AstrometryApiCard> {
  final _keyController = TextEditingController();
  bool _saving = false;
  bool _testing = false;
  String? _testMessage;
  bool? _testSuccess;

  bool _enabled = true;
  bool _settingsLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadSavedValues();
    _loadSettings();
  }

  @override
  void dispose() {
    _keyController.dispose();
    super.dispose();
  }

  void _loadSavedValues() {
    final vm = context.read<SettingsViewModel>();
    _keyController.text = vm.apiKeys[ApiKeyType.astrometryNet] ?? '';
  }

  Future<void> _loadSettings() async {
    final settings = await widget.settingsService.load();
    if (!mounted) return;
    setState(() {
      _enabled = settings.astrometryEnabled;
      _settingsLoaded = true;
    });
  }

  Future<void> _saveSettings() async {
    await widget.settingsService.save(
      PlateSolveSettings(
        astrometryEnabled: _enabled,
        autoSolveOnRegister: false,
      ),
    );
  }

  Future<void> _save() async {
    final key = _keyController.text.trim();
    if (key.isEmpty) {
      _showSnack('API Key를 입력해주세요.');
      return;
    }
    setState(() => _saving = true);
    await context
        .read<SettingsViewModel>()
        .saveApiKey(ApiKeyType.astrometryNet, key);
    if (mounted) {
      setState(() => _saving = false);
      _showSnack('Astrometry.net API Key가 저장되었습니다.');
    }
  }

  Future<void> _test() async {
    setState(() {
      _testing = true;
      _testMessage = null;
      _testSuccess = null;
    });
    final result = await widget.provider.testConnection();
    if (mounted) {
      setState(() {
        _testing = false;
        _testSuccess = result.success;
        _testMessage = result.success
            ? '성공 · HTTP ${result.statusCode} · ${result.responseTimeMs} ms'
            : result.message;
      });
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return _ApiCard(
      title: 'Astrometry.net API',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SecureField(
            label: 'API Key',
            controller: _keyController,
            obscured: true,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _ActionButton(
                  label: '저장',
                  loading: _saving,
                  onPressed: _save,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ActionButton(
                  label: '연결 테스트',
                  loading: _testing,
                  onPressed: _test,
                  outlined: true,
                ),
              ),
            ],
          ),
          if (_testMessage != null) ...[
            const SizedBox(height: 10),
            _InlineTestResult(success: _testSuccess!, message: _testMessage!),
          ],
          if (_settingsLoaded) ...[
            const SizedBox(height: 14),
            const Divider(color: AppColors.textSecondary, height: 1),
            const SizedBox(height: 8),
            _SwitchRow(
              label: '활성화',
              subtitle: '갤러리 사진 상세에서 Plate Solve를 사용할 수 있습니다.',
              value: _enabled,
              onChanged: (value) {
                setState(() => _enabled = value);
                _saveSettings();
              },
            ),
          ],
        ],
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.label,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ),
        Switch(
          value: value,
          activeThumbColor: AppColors.messier,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

// ── Google Maps API Card ────────────────────────────────────────────────────

class _GoogleMapsApiCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final vm = context.watch<SettingsViewModel>();
    final current = vm.apiKeys[ApiKeyType.googleMaps];
    final hasKey = current != null && current.isNotEmpty;
    final masked = hasKey
        ? (current.length <= 8
            ? '••••••••'
            : '${current.substring(0, 4)}••••${current.substring(current.length - 4)}')
        : null;

    return _ApiCard(
      title: 'Google Maps API',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasKey) ...[
            Text(
              masked!,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontFamily: 'monospace',
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 4),
          ],
          Text(
            hasKey
                ? '등록됨 — Geocoding·Static Map·GoogleMap에 동일 키가 사용됩니다.'
                : '미등록',
            style: TextStyle(
              color: hasKey
                  ? AppColors.textSecondary
                  : AppColors.textSecondary.withValues(alpha: 0.5),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => _showEditDialog(context, vm, current),
                child: Text(
                  hasKey ? '수정' : '등록',
                  style: const TextStyle(color: AppColors.messier),
                ),
              ),
              if (hasKey) ...[
                const SizedBox(width: 4),
                TextButton(
                  onPressed: () => _confirmDelete(context, vm),
                  child: const Text(
                    '삭제',
                    style: TextStyle(color: Colors.redAccent),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _showEditDialog(
    BuildContext context,
    SettingsViewModel vm,
    String? current,
  ) async {
    final controller = TextEditingController(text: current ?? '');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text(
          'Google Maps API Key',
          style: TextStyle(color: AppColors.textPrimary, fontSize: 15),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontFamily: 'monospace',
            fontSize: 13,
          ),
          decoration: const InputDecoration(
            labelText: 'API Key',
            labelStyle: TextStyle(color: AppColors.textSecondary),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('취소',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('저장',
                style: TextStyle(color: AppColors.messier)),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await vm.saveApiKey(ApiKeyType.googleMaps, controller.text);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Google Maps API Key가 저장되었습니다.')),
        );
      }
    }
  }

  Future<void> _confirmDelete(
    BuildContext context,
    SettingsViewModel vm,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Google Maps API Key 삭제',
            style: TextStyle(color: AppColors.textPrimary)),
        content: const Text('삭제할까요?',
            style: TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('취소',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('삭제',
                style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await vm.deleteApiKey(ApiKeyType.googleMaps);
    }
  }
}

// ── Shared small widgets ────────────────────────────────────────────────────

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.outlined = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    if (outlined) {
      return OutlinedButton(
        onPressed: loading ? null : onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.messier,
          side: const BorderSide(color: AppColors.messier),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: loading
            ? const SizedBox(
                height: 16,
                width: 16,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppColors.messier),
              )
            : Text(label, style: const TextStyle(fontSize: 13)),
      );
    }

    return ElevatedButton(
      onPressed: loading ? null : onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.messier,
        foregroundColor: Colors.black,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: loading
          ? const SizedBox(
              height: 16,
              width: 16,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Colors.black),
            )
          : Text(label, style: const TextStyle(fontSize: 13)),
    );
  }
}

class _InlineTestResult extends StatelessWidget {
  const _InlineTestResult({required this.success, required this.message});

  final bool success;
  final String message;

  @override
  Widget build(BuildContext context) {
    final color = success ? Colors.green : Colors.redAccent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(
            success ? Icons.check_circle_outline : Icons.error_outline,
            size: 14,
            color: color,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: color, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
