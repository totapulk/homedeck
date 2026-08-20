import 'dart:async';

import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../state/light_store.dart';

/// Fades the panel down when nobody is using it, and back up the moment somebody is.
///
/// A wall panel that blanks itself is useless — you cannot see the state of the house at a
/// glance — and one at full brightness is a lamp nobody asked for. Dimming keeps it readable
/// in a dark room while staying out of the way.
///
/// Waking is driven by deliberate input only: a touch, or a hand on the knob. A light changing
/// somewhere else in the house is not a reason to light up the hallway at three in the morning.
class AmbientDim extends StatefulWidget {
  const AmbientDim({
    super.key,
    required this.child,
    this.idleAfter = const Duration(seconds: 45),
    this.dimTo = 0.86,
    this.keepAwake = true,
  });

  final Widget child;
  final Duration idleAfter;

  /// Holds the screen on so the panel decides its own brightness rather than being blanked by
  /// a system timeout. Without it the knob would turn a light on and the panel showing that
  /// light would stay black.
  final bool keepAwake;

  /// How much black to lay over the panel. Not fully opaque on purpose: the room should still
  /// be readable from across it.
  final double dimTo;

  @override
  State<AmbientDim> createState() => _AmbientDimState();
}

class _AmbientDimState extends State<AmbientDim> {
  Timer? _idle;
  bool _dim = false;
  int _seenInteractions = -1;

  @override
  void initState() {
    super.initState();
    _restartIdleTimer();
    if (widget.keepAwake) _holdScreenOn(true);
  }

  @override
  void dispose() {
    _idle?.cancel();
    if (widget.keepAwake) _holdScreenOn(false);
    super.dispose();
  }

  static Future<void> _holdScreenOn(bool on) async {
    try {
      await WakelockPlus.toggle(enable: on);
    } catch (_) {
      // Browsers grant this only after a gesture, and a test harness has no plugin at all.
      // Losing it costs the ambient behaviour, not the app: the screen simply goes back to
      // following the system timeout.
    }
  }

  void _restartIdleTimer() {
    _idle?.cancel();
    _idle = Timer(widget.idleAfter, () {
      if (mounted) setState(() => _dim = true);
    });
  }

  void _wake() {
    _restartIdleTimer();
    if (_dim) setState(() => _dim = false);
  }

  @override
  Widget build(BuildContext context) {
    final store = LightScope.of(context);

    if (store.interactions != _seenInteractions) {
      _seenInteractions = store.interactions;
      // Waking during build would be a side effect in the wrong place; the frame after is soon
      // enough for something a human is watching.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _wake();
      });
    }

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _wake(),
      child: Stack(
        children: [
          widget.child,
          Positioned.fill(
            // While dimmed the overlay is solid to touch, so the tap that wakes the panel is
            // swallowed here rather than switching off a light by accident. Awake, it is
            // ignored entirely and the controls below are reachable as usual.
            child: IgnorePointer(
              ignoring: !_dim,
              child: AnimatedOpacity(
                opacity: _dim ? widget.dimTo : 0,
                duration: const Duration(milliseconds: 700),
                curve: Curves.easeOut,
                child: const ColoredBox(color: Colors.black),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
