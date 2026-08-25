class TcBackendSyncGate {
  Future<void> _tail = Future<void>.value();

  Future<T> runExclusive<T>(Future<T> Function() action) {
    final run = _tail.then((_) => action());
    _tail = run.then<void>((_) {}, onError: (_, _) {});
    return run;
  }
}
