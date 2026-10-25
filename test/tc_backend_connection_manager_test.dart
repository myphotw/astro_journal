import 'dart:async';

import 'package:astro_journal/data/models/tc_backend_models.dart';
import 'package:astro_journal/services/tc_backend_auth_service.dart';
import 'package:astro_journal/services/tc_backend_connection_manager.dart';
import 'package:astro_journal/services/tc_backend_service.dart';
import 'package:astro_journal/services/tc_backend_settings_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const internal = 'http://internal.test:8000';
  const external = 'https://external.test:8443';

  TcBackendSettingsService settings() => TcBackendSettingsService(
    useBuildConfiguration: true,
    buildBaseUrl: '',
    buildInternalUrl: internal,
    buildExternalUrl: external,
  );

  TcBackendConnectionManager manager({
    required Map<String, List<TcBackendCheckResult>> results,
    Stream<void>? changes,
    Duration debounce = Duration.zero,
    List<String>? calls,
    List<Duration>? timeouts,
  }) => TcBackendConnectionManager(
    settingsService: settings(),
    authHeaders: TcBackendAuthHeaders(const EmptyTcBackendTokenStore()),
    networkChanges: changes ?? const Stream.empty(),
    networkChangeDebounce: debounce,
    serviceFactory: (baseUrl, timeout) => _FakeService(baseUrl, () {
      calls?.add(baseUrl);
      timeouts?.add(timeout);
      return results[baseUrl]!.removeAt(0);
    }),
  );

  test('prefers the internal endpoint when both are available', () async {
    final calls = <String>[];
    final subject = manager(
      calls: calls,
      results: {
        internal: [_connected()],
        external: [_connected()],
      },
    );

    await subject.reconnect();

    expect(calls, [internal]);
    expect(subject.selectedEndpoint?.kind, TcBackendEndpointKind.internal);
    subject.dispose();
  });

  test('falls back to external after internal transport failure', () async {
    final subject = manager(
      results: {
        internal: [_unreachable()],
        external: [_connected()],
      },
    );

    await subject.reconnect();

    expect(subject.status, TcBackendConnectionStatus.connected);
    expect(subject.selectedEndpoint?.baseUrl, external);
    subject.dispose();
  });

  test('uses one second internally and two seconds externally', () async {
    final timeouts = <Duration>[];
    final subject = manager(
      timeouts: timeouts,
      results: {
        internal: [_unreachable()],
        external: [_connected()],
      },
    );

    await subject.reconnect();

    expect(timeouts, const [Duration(seconds: 1), Duration(seconds: 2)]);
    subject.dispose();
  });

  test('reports failure when neither endpoint is usable', () async {
    final subject = manager(
      results: {
        internal: [_unreachable()],
        external: [_securityError()],
      },
    );

    await subject.reconnect();

    expect(subject.status, TcBackendConnectionStatus.securityError);
    expect(subject.selectedEndpoint, isNull);
    expect(subject.lastCheckedEndpoint?.baseUrl, external);
    subject.dispose();
  });

  test(
    'authentication failure stays distinct and does not try fallback',
    () async {
      final calls = <String>[];
      final subject = manager(
        calls: calls,
        results: {
          internal: [_authenticationFailed()],
          external: [_connected()],
        },
      );

      await subject.reconnect();

      expect(calls, [internal]);
      expect(subject.status, TcBackendConnectionStatus.authenticationFailed);
      expect(subject.selectedEndpoint?.baseUrl, internal);
      subject.dispose();
    },
  );

  test('network change switches external back to available internal', () async {
    final changes = StreamController<void>.broadcast();
    final subject = manager(
      changes: changes.stream,
      results: {
        internal: [_unreachable(), _connected()],
        external: [_connected()],
      },
    );
    subject.start();
    await _waitUntil(() => subject.selectedEndpoint?.baseUrl == external);
    expect(subject.selectedEndpoint?.baseUrl, external);

    changes.add(null);
    await _waitUntil(() => subject.selectedEndpoint?.baseUrl == internal);

    expect(subject.selectedEndpoint?.baseUrl, internal);
    await changes.close();
    subject.dispose();
  });

  test(
    'network change switches internal to external without restart',
    () async {
      final changes = StreamController<void>.broadcast();
      final subject = manager(
        changes: changes.stream,
        results: {
          internal: [_connected(), _unreachable()],
          external: [_connected()],
        },
      );
      subject.start();
      await _waitUntil(() => subject.selectedEndpoint?.baseUrl == internal);

      changes.add(null);
      await _waitUntil(() => subject.selectedEndpoint?.baseUrl == external);

      expect(subject.status, TcBackendConnectionStatus.connected);
      await changes.close();
      subject.dispose();
    },
  );

  test('failed connection recovers on a later network event', () async {
    final changes = StreamController<void>.broadcast();
    final subject = manager(
      changes: changes.stream,
      results: {
        internal: [_unreachable(), _unreachable()],
        external: [_unreachable(), _connected()],
      },
    );
    subject.start();
    await _waitUntil(
      () => subject.status == TcBackendConnectionStatus.unreachable,
    );

    changes.add(null);
    await _waitUntil(() => subject.selectedEndpoint?.baseUrl == external);

    expect(subject.status, TcBackendConnectionStatus.connected);
    await changes.close();
    subject.dispose();
  });

  test('simultaneous reconnect requests are serialized', () async {
    final completer = Completer<TcBackendCheckResult>();
    var calls = 0;
    final subject = TcBackendConnectionManager(
      settingsService: settings(),
      authHeaders: TcBackendAuthHeaders(const EmptyTcBackendTokenStore()),
      networkChanges: const Stream.empty(),
      serviceFactory: (baseUrl, timeout) => _AsyncFakeService(baseUrl, () {
        calls++;
        return completer.future;
      }),
    );

    final first = subject.reconnect();
    final second = subject.reconnect();
    completer.complete(_connected());
    await Future.wait([first, second]);

    expect(calls, 1);
    expect(subject.status, TcBackendConnectionStatus.connected);
    subject.dispose();
  });

  test('pause stops network events and resume performs one check', () async {
    final changes = StreamController<void>.broadcast();
    final calls = <String>[];
    final subject = manager(
      changes: changes.stream,
      calls: calls,
      results: {
        internal: [_connected(), _connected()],
        external: [_connected()],
      },
    );
    subject.start();
    await _waitUntil(() => calls.length == 1);
    await subject.pause();

    changes.add(null);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(calls, hasLength(1));

    subject.resume();
    await _waitUntil(() => calls.length == 2);
    await changes.close();
    subject.dispose();
  });
}

TcBackendCheckResult _connected() => const TcBackendCheckResult(
  status: TcBackendConnectionStatus.connected,
  message: 'connected',
);

TcBackendCheckResult _unreachable() => const TcBackendCheckResult(
  status: TcBackendConnectionStatus.unreachable,
  message: 'unreachable',
);

TcBackendCheckResult _securityError() => const TcBackendCheckResult(
  status: TcBackendConnectionStatus.securityError,
  message: 'tls',
);

TcBackendCheckResult _authenticationFailed() => const TcBackendCheckResult(
  status: TcBackendConnectionStatus.authenticationFailed,
  message: 'auth',
);

class _FakeService extends TcBackendService {
  _FakeService(String baseUrl, this._result) : super(baseUrl: baseUrl);

  final TcBackendCheckResult Function() _result;

  @override
  Future<TcBackendCheckResult> checkCompatibility() async => _result();
}

class _AsyncFakeService extends TcBackendService {
  _AsyncFakeService(String baseUrl, this._result) : super(baseUrl: baseUrl);

  final Future<TcBackendCheckResult> Function() _result;

  @override
  Future<TcBackendCheckResult> checkCompatibility() => _result();
}

Future<void> _waitUntil(bool Function() predicate) async {
  for (var attempt = 0; attempt < 50; attempt++) {
    if (predicate()) return;
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
  fail('Condition was not reached in time.');
}
