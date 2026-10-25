import 'package:connectivity_plus/connectivity_plus.dart';

class TcBackendNetworkMonitor {
  TcBackendNetworkMonitor({Connectivity? connectivity})
    : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;

  Stream<void> get changes => _connectivity.onConnectivityChanged.map((_) {});
}
