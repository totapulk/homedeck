import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'controller_input.dart';

/// The physical knob, over BLE.
///
/// Nothing above this class knows that Bluetooth is involved: it produces the same events as
/// [MockControllerInput], which is what made the whole pipeline buildable months of evenings
/// before the hardware arrived.
class BleControllerInput implements ControllerInput {
  static final Guid serviceUuid = Guid('4d1c1a00-8b6e-4f3a-9f2d-1c7a5e9b3d40');
  static final Guid eventsUuid = Guid('4d1c1a01-8b6e-4f3a-9f2d-1c7a5e9b3d40');

  static const int _eventRotate = 0x01;
  static const int _eventPress = 0x02;

  static const Duration _scanTimeout = Duration(seconds: 15);
  static const Duration _retryDelay = Duration(seconds: 5);

  final StreamController<ControllerEvent> _events =
      StreamController<ControllerEvent>.broadcast();
  final StreamController<ControllerStatus> _status =
      StreamController<ControllerStatus>.broadcast();

  BluetoothDevice? _device;
  bool _running = false;

  @override
  Stream<ControllerEvent> get events => _events.stream;

  @override
  Stream<ControllerStatus> get status => _status.stream;

  @override
  Future<void> start() async {
    if (_running) return;
    _running = true;
    unawaited(_hunt());
  }

  @override
  Future<void> stop() async {
    _running = false;
    await _device?.disconnect();
    _device = null;
    _status.add(ControllerStatus.disconnected);
  }

  /// Looks for the knob, stays attached to it, and starts looking again when it goes away.
  ///
  /// A knob on a shelf loses power, goes out of range and comes back; treating that as an error
  /// to report would mean a wall panel that needs a human to restart it.
  Future<void> _hunt() async {
    while (_running) {
      try {
        _status.add(ControllerStatus.searching);

        if (await _findKnob() case final device?) {
          await _stayAttached(device);
        }
      } catch (_) {
        // Adapter off, permission refused, knob unplugged mid-handshake. All of them mean the
        // same thing here: try again in a moment.
      }

      _status.add(ControllerStatus.disconnected);
      if (_running) await Future<void>.delayed(_retryDelay);
    }
  }

  Future<BluetoothDevice?> _findKnob() async {
    final found = Completer<BluetoothDevice?>();

    final subscription = FlutterBluePlus.scanResults.listen((results) {
      if (results.isEmpty || found.isCompleted) return;
      found.complete(results.first.device);
    });

    try {
      // Filtering by service UUID rather than by name: the name lives in the scan response and
      // is decoration, while the service is the actual contract.
      await FlutterBluePlus.startScan(
        withServices: [serviceUuid],
        timeout: _scanTimeout,
        webOptionalServices: [serviceUuid],
      );

      return await found.future.timeout(_scanTimeout, onTimeout: () => null);
    } finally {
      await subscription.cancel();
      await FlutterBluePlus.stopScan();
    }
  }

  /// Connects, subscribes, and returns only once the knob has gone away again.
  Future<void> _stayAttached(BluetoothDevice device) async {
    _device = device;
    final disconnected = Completer<void>();

    final connection = device.connectionState.listen((state) {
      if (state == BluetoothConnectionState.disconnected && !disconnected.isCompleted) {
        disconnected.complete();
      }
    });

    StreamSubscription<List<int>>? values;
    try {
      // License.nonprofit is the accurate choice for a personal portfolio project;
      // flutter_blue_plus 2.x asks for a paid licence for for-profit use.
      await device.connect(license: License.nonprofit);

      final services = await device.discoverServices();
      final service = services.firstWhere((service) => service.uuid == serviceUuid);
      final characteristic = service.characteristics.firstWhere(
        (characteristic) => characteristic.uuid == eventsUuid,
      );

      values = characteristic.onValueReceived.listen(_decode);
      await characteristic.setNotifyValue(true);

      _status.add(ControllerStatus.connected);
      await disconnected.future;
    } finally {
      await values?.cancel();
      await connection.cancel();
      _device = null;
    }
  }

  /// [control, event, signed delta] — see firmware/knob/README.md.
  void _decode(List<int> payload) {
    if (payload.length < 3) return;

    final control = payload[0];
    switch (payload[1]) {
      case _eventRotate:
        // The wire carries an unsigned byte; anticlockwise is the top half of it.
        _events.add(Rotated(control, payload[2].toSigned(8)));
      case _eventPress:
        _events.add(Pressed(control));
    }
  }
}
