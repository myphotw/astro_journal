import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:astro_journal/services/tc_backend_settings_service.dart';
import 'package:astro_journal/services/tc_backend_startup_resume_service.dart';
import 'package:astro_journal/services/tc_backend_pull_sync_coordinator.dart';
import 'package:astro_journal/services/tc_backend_sync_coordinator.dart';

void main() {
  late TcBackendSettingsService settings;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    settings = TcBackendSettingsService();
  });

  test('enabled and configured backend starts one drain', () async {
    await settings.save(
      const TcBackendSettings(
        baseUrl: 'https://backend.example',
        enabled: true,
      ),
    );
    final runner = _DuplicateProtectedRunner();
    await TcBackendStartupResumeService(settings, runner).resume();
    expect(runner.calls, 1);
  });

  test('disabled or unconfigured backend does not drain', () async {
    final runner = _FakeRunner();
    await TcBackendStartupResumeService(settings, runner).resume();
    await settings.save(const TcBackendSettings(baseUrl: '', enabled: false));
    await TcBackendStartupResumeService(settings, runner).resume();
    expect(runner.calls, 0);
  });

  test('drain failure is isolated from startup', () async {
    await settings.save(
      const TcBackendSettings(
        baseUrl: 'https://backend.example',
        enabled: true,
      ),
    );
    final runner = _FakeRunner(error: StateError('offline'));
    await TcBackendStartupResumeService(settings, runner).resume();
    expect(runner.calls, 1);
  });

  test('two callers can rely on the coordinator drain guard', () async {
    await settings.save(
      const TcBackendSettings(
        baseUrl: 'https://backend.example',
        enabled: true,
      ),
    );
    final runner = _DuplicateProtectedRunner();
    final service = TcBackendStartupResumeService(settings, runner);
    await Future.wait([service.resume(), service.resume()]);
    expect(runner.calls, 1);
  });

  test('startup composite runs push before incremental pull', () async {
    await settings.save(
      const TcBackendSettings(
        baseUrl: 'https://backend.example',
        enabled: true,
      ),
    );
    final order = <String>[];
    final runner = TcBackendCompositeSyncRunner([
      _OrderRunner('push', order),
      _OrderRunner('pull', order),
    ]);

    await TcBackendStartupResumeService(settings, runner).resume();

    expect(order, ['push', 'pull']);
  });
}

class _FakeRunner implements TcBackendDrainRunner {
  _FakeRunner({this.error});
  final Object? error;
  int calls = 0;
  @override
  Future<void> drain() async {
    calls++;
    if (error != null) throw error!;
  }
}

class _DuplicateProtectedRunner implements TcBackendDrainRunner {
  bool _running = false;
  int calls = 0;
  @override
  Future<void> drain() async {
    if (_running) return;
    _running = true;
    calls++;
    await Future<void>.delayed(Duration.zero);
    _running = false;
  }
}

class _OrderRunner implements TcBackendDrainRunner {
  _OrderRunner(this.name, this.order);
  final String name;
  final List<String> order;

  @override
  Future<void> drain() async {
    order.add(name);
  }
}
