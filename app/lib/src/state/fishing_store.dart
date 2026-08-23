import 'dart:async';

import 'package:flutter/widgets.dart';

import '../api/homedeck_api.dart';
import '../models/fishing.dart';

/// The bite forecast for one lake.
///
/// Polled far more slowly than anything else here, because the weather behind it is only
/// published every ten minutes and the backend caches it for exactly that long. Asking more
/// often would cost requests and learn nothing.
class FishingStore extends ChangeNotifier {
  FishingStore(this._api, {this.interval = const Duration(minutes: 15)});

  final Duration interval;

  final HomeDeckApi _api;

  Fishing? _fishing;
  String? _error;
  bool _busy = false;
  Timer? _poll;
  bool _watching = false;

  Fishing? get fishing => _fishing;

  String? get error => _error;

  bool get busy => _busy;

  void watch() {
    if (_watching) return;
    _watching = true;
    unawaited(load());
  }

  Future<void> load() async {
    if (_busy) return;

    _busy = true;
    notifyListeners();

    try {
      _fishing = await _api.fetchFishing();
      _error = null;
    } on HomeDeckApiException catch (failure) {
      _error = failure.message;
    } finally {
      _busy = false;
      _poll?.cancel();
      if (_watching) _poll = Timer(interval, load);
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _watching = false;
    _poll?.cancel();
    super.dispose();
  }
}

class FishingScope extends InheritedNotifier<FishingStore> {
  const FishingScope({super.key, required FishingStore store, required super.child})
    : super(notifier: store);

  static FishingStore of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<FishingScope>();
    assert(scope != null, 'No FishingScope above this widget.');
    return scope!.notifier!;
  }
}
