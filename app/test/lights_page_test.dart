import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homedeck/src/api/homedeck_api.dart';
import 'package:homedeck/src/state/light_store.dart';
import 'package:homedeck/src/ui/lights_page.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const String _twoRooms = '''
[
  {"id":"a1","name":"Reading lamp","room":"Living room","isOn":true,"brightness":70,
   "colorTempK":2700,"isReachable":true,"updatedAt":"2026-08-17T12:59:49Z"},
  {"id":"b2","name":"Desk","room":"Office","isOn":false,"brightness":0,
   "colorTempK":null,"isReachable":false,"updatedAt":"2026-08-17T12:59:49Z"}
]
''';

Future<void> pumpLights(WidgetTester tester, String body) async {
  final store = LightStore(
    HomeDeckApi(
      baseUrl: Uri.parse('http://backend'),
      client: MockClient((_) async => http.Response(body, 200)),
    ),
  );

  await tester.pumpWidget(
    MaterialApp(home: LightScope(store: store, child: const LightsPage())),
  );
  await store.load();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('groups lights under their room and spells out their state', (tester) async {
    await pumpLights(tester, _twoRooms);

    expect(find.text('LIVING ROOM'), findsOneWidget);
    expect(find.text('OFFICE'), findsOneWidget);
    expect(find.text('Reading lamp'), findsOneWidget);
    expect(find.text('70% · 2700K'), findsOneWidget);

    // An unreachable bulb keeps its place in the list instead of disappearing from it.
    expect(find.text('Desk'), findsOneWidget);
    expect(find.text('Not responding'), findsOneWidget);
  });

  testWidgets('the switch commands the backend and the tile follows', (tester) async {
    final commands = <String>[];
    final store = LightStore(
      HomeDeckApi(
        baseUrl: Uri.parse('http://backend'),
        client: MockClient((request) async {
          if (request.method == 'GET') return http.Response(_twoRooms, 200);
          commands.add(request.body);
          return http.Response(
            '{"id":"a1","name":"Reading lamp","room":"Living room","isOn":false,'
            '"brightness":0,"colorTempK":2700,"isReachable":true,'
            '"updatedAt":"2026-08-17T13:10:00Z"}',
            200,
          );
        }),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(home: LightScope(store: store, child: const LightsPage())),
    );
    await store.load();
    await tester.pumpAndSettle();

    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();

    expect(commands.single, '{"isOn":false}');
    expect(find.text('Off'), findsOneWidget);
  });

  testWidgets('a light that cannot be reached cannot be commanded', (tester) async {
    await pumpLights(tester, _twoRooms);

    final switches = tester.widgetList<Switch>(find.byType(Switch)).toList();
    expect(switches.first.onChanged, isNotNull);
    expect(switches.last.onChanged, isNull);
  });

  testWidgets('offers a retry when the backend cannot be reached', (tester) async {
    final store = LightStore(
      HomeDeckApi(
        baseUrl: Uri.parse('http://backend'),
        client: MockClient((_) async => throw http.ClientException('refused')),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(home: LightScope(store: store, child: const LightsPage())),
    );
    await store.load();
    await tester.pumpAndSettle();

    expect(find.text('Try again'), findsOneWidget);
  });
}
