import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// Whether the device currently has any network connectivity. Screens and
/// the outbox sync engine read this to decide whether to call the server
/// directly or queue work for later (Flutter API Guide section 10).
final ValueNotifier<bool> isOnline = ValueNotifier<bool>(true);

StreamSubscription<List<ConnectivityResult>>? _subscription;

Future<void> initConnectivity() async {
  final initial = await Connectivity().checkConnectivity();
  isOnline.value = _hasConnection(initial);

  _subscription ??= Connectivity().onConnectivityChanged.listen((results) {
    isOnline.value = _hasConnection(results);
  });
}

bool _hasConnection(List<ConnectivityResult> results) =>
    results.any((r) => r != ConnectivityResult.none);
