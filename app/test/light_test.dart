import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:homedeck/src/models/light.dart';

// Captured from GET /api/lights so the test fails if the backend contract drifts.
const String backendPayload = '''
{
  "id": "444f8eb4a2e2",
  "name": "Living room 1",
  "room": "Living room",
  "isOn": true,
  "brightness": 70,
  "colorTempK": 2700,
  "isReachable": true,
  "updatedAt": "2026-08-17T12:59:49.3245129+00:00"
}
''';

void main() {
  test('parses a light as the backend sends it', () {
    final light = Light.fromJson(jsonDecode(backendPayload) as Map<String, dynamic>);

    expect(light.id, '444f8eb4a2e2');
    expect(light.name, 'Living room 1');
    expect(light.room, 'Living room');
    expect(light.isOn, isTrue);
    expect(light.brightness, 70);
    expect(light.colorTempK, 2700);
    expect(light.isReachable, isTrue);
    expect(light.updatedAt.isUtc, isTrue);
  });

  test('tolerates a bulb with no colour temperature', () {
    final json = jsonDecode(backendPayload) as Map<String, dynamic>;
    json['colorTempK'] = null;

    expect(Light.fromJson(json).colorTempK, isNull);
  });
}
