import 'dart:async';

import 'package:flutter/foundation.dart';
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
        // Scanning with the radio off is not an error worth reporting, it is a thing to wait
        // for: a user turning Bluetooth on later should find the knob works, without restarting
        // anything. Some platform implementations also fail badly rather than politely when
        // asked to scan with no radio.
        if (!await FlutterBluePlus.isSupported) {
          _status.add(ControllerStatus.disconnected);
          return;
        }
        await FlutterBluePlus.adapterState.firstWhere(
          (state) => state == BluetoothAdapterState.on,
        );

        _status.add(ControllerStatus.searching);

        if (await _findKnob() case final device?) {
          _log('found ${device.remoteId}, connecting');
          await _stayAttached(device);
        } else {
          _log('no knob answered the scan');
        }
      } catch (error, stack) {
        // Adapter off, permission refused, knob unplugged mid-handshake. All of them mean the
        // same thing for the retry loop — but swallowing them silently turns "the badge never
        // lights up" into an unanswerable question, so they are always logged.
        _log('$error', stack);
      }

      _status.add(ControllerStatus.disconnected);
      if (_running) await Future<void>.delayed(_retryDelay);
    }
  }

  static void _log(String message, [StackTrace? stack]) {
    debugPrint('[knob] $message');
    if (stack != null) debugPrintStack(stackTrace: stack, maxFrames: 6);
  }

  Future<BluetoothDevice?> _findKnob() async {
    final found = Completer<BluetoothDevice?>();

    // The platform filter is a hint, not a guarantee: some backends hand back everything they
    // heard. Confirming the service in the advertisement ourselves is cheap, and the failure it
    // prevents — connecting to a stranger's headphones and waiting for knob events that will
    // never come — is a confusing one to debug.
    final subscription = FlutterBluePlus.scanResults.listen((results) {
      if (found.isCompleted) return;

      for (final result in results) {
        final advertised = result.advertisementData.serviceUuids;
        _log(
          'candidate ${result.device.remoteId} "${result.advertisementData.advName}" '
          'services=[${advertised.map((uuid) => uuid.str).join(', ')}]',
        );

        if (!advertised.contains(serviceUuid)) continue;

        found.complete(result.device);
        return;
      }
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

    // connectionState replays the current state the moment it is listened to, and that state is
    // "disconnected" because connecting has not been asked for yet. Treating that reply as a
    // disconnection would end the attachment before it began — which it did, on every other
    // attempt, depending on whether the platform still had the device cached as connected.
    var attached = false;

    final connection = device.connectionState.listen((state) {
      _log('connection state: ${state.name}');
      if (state == BluetoothConnectionState.disconnected && attached && !disconnected.isCompleted) {
        disconnected.complete();
      }
    });

    StreamSubscription<List<int>>? values;
    try {
      // License.nonprofit is the accurate choice for a personal portfolio project;
      // flutter_blue_plus 2.x asks for a paid licence for for-profit use.
      //
      // mtu: null skips MTU negotiation. Notifications here are three bytes, so a larger MTU
      // buys nothing, and negotiating one is a step that some platform backends handle badly.
      await device.connect(license: License.nonprofit, mtu: null);

      // connect() resolves optimistically on some backends, before the link is actually up, and
      // discoverServices then fails with "device is not connected". Waiting for the state the
      // connection claims to have reached turns a coin flip into a connection.
      await device.connectionState
          .firstWhere((state) => state == BluetoothConnectionState.connected)
          .timeout(const Duration(seconds: 10));

      _log('connected, discovering services');

      final services = await device.discoverServices();
      _log('discovered ${services.length} service(s): '
          '${services.map((service) => service.uuid.str).join(', ')}');

      final service = services.firstWhere((service) => service.uuid == serviceUuid);
      final characteristic = service.characteristics.firstWhere(
        (characteristic) => characteristic.uuid == eventsUuid,
      );

      values = characteristic.onValueReceived.listen(_decode);
      await characteristic.setNotifyValue(true);
      _log('subscribed to events');

      attached = true;
      _status.add(ControllerStatus.connected);

      // Setting up took a few round trips; the knob may already have gone in the meantime, and
      // the listener would have ignored that while attached was still false.
      if (!device.isConnected && !disconnected.isCompleted) disconnected.complete();

      await disconnected.future;
      _log('knob went away');
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
