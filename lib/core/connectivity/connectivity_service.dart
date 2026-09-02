import 'dart:async';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Centralized service for tracking network connectivity and real internet reachability.
class ConnectivityService {
  final Connectivity _connectivity;
  final _connectionController = StreamController<bool>.broadcast();
  StreamSubscription<List<ConnectivityResult>>? _subscription;

  bool _isOnline = true; // Optimistic default until checked

  ConnectivityService({Connectivity? connectivity})
      : _connectivity = connectivity ?? Connectivity();

  bool get isOnline => _isOnline;
  bool get isOffline => !_isOnline;
  Stream<bool> get onConnectivityChanged => _connectionController.stream;

  Future<void> initialize() async {
    try {
      final initialResults = await _connectivity.checkConnectivity();
      _isOnline = await _checkReachability(initialResults);
    } catch (_) {
      _isOnline = false;
    }
    _connectionController.add(_isOnline);

    _subscription = _connectivity.onConnectivityChanged.listen((results) async {
      final reachable = await _checkReachability(results);
      if (reachable != _isOnline) {
        _isOnline = reachable;
        _connectionController.add(_isOnline);
      }
    });
  }

  /// Verifies active internet reachability.
  Future<bool> _checkReachability(List<ConnectivityResult> results) async {
    final hasNetwork = results.any((r) =>
        r == ConnectivityResult.wifi ||
        r == ConnectivityResult.mobile ||
        r == ConnectivityResult.ethernet ||
        r == ConnectivityResult.vpn);

    if (!hasNetwork) return false;

    // Perform an active reachability check
    try {
      final lookup = await InternetAddress.lookup('dns.google')
          .timeout(const Duration(seconds: 3));
      return lookup.isNotEmpty && lookup[0].rawAddress.isNotEmpty;
    } catch (_) {
      // Fallback probe
      try {
        final fallback = await InternetAddress.lookup('1.1.1.1')
            .timeout(const Duration(seconds: 3));
        return fallback.isNotEmpty && fallback[0].rawAddress.isNotEmpty;
      } catch (_) {
        return false;
      }
    }
  }

  /// Manually force a reachability check (e.g. before triggering a sync)
  Future<bool> checkConnection() async {
    try {
      final results = await _connectivity.checkConnectivity();
      final reachable = await _checkReachability(results);
      if (reachable != _isOnline) {
        _isOnline = reachable;
        _connectionController.add(_isOnline);
      }
      return _isOnline;
    } catch (_) {
      _isOnline = false;
      _connectionController.add(false);
      return false;
    }
  }

  void dispose() {
    _subscription?.cancel();
    _connectionController.close();
  }
}

// ── Riverpod Providers ──

final connectivityServiceProvider = Provider<ConnectivityService>((ref) {
  final service = ConnectivityService();
  service.initialize();
  ref.onDispose(() => service.dispose());
  return service;
});

final isOnlineProvider = StreamProvider<bool>((ref) {
  final service = ref.watch(connectivityServiceProvider);
  return Stream<bool>.multi((controller) {
    controller.add(service.isOnline);
    final sub = service.onConnectivityChanged.listen(controller.add);
    controller.onCancel = () => sub.cancel();
  });
});
