class TcBackendSyncGate {
  Future<void> _tail = Future<void>.value();

  Future<void> runExclusive(Future<void> Function() action) {
    final run = _tail.then((_) => action());
    _tail = run.then<void>((_) {}, onError: (_, _) {});
    return run;
  }
}
