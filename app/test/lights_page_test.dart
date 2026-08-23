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

/// The lights module on its own. It is a panel now rather than a page, so it needs only the
/// scope it reads from — the shell and the other modules are tested in home_page_test.dart.
Widget page(LightStore store) => MaterialApp(
  home: LightScope(store: store, child: const LightsPage()),
);

Future<void> pumpLights(WidgetTester tester, String body) async {
  final store = LightStore(
    HomeDeckApi(
      baseUrl: Uri.parse('http://backend'),
      client: MockClient((_) async => http.Response(body, 200)),
    ),
  );

  await tester.pumpWidget(page(store));
  await store.load();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('groups lights under their room and spells out their state', (tester) async {
    await pumpLights(tester, _twoRooms);

    expect(find.text('LIVING ROOM'), findsOneWidget);
    expect(find.text('OFFICE'), findsOneWidget);
    expect(find.text('Reading lamp'), findsOneWidget);
    expect(find.text('70 % · 2700 K'), findsOneWidget);

    // An unreachable bulb keeps its place in the list instead of disappearing from it.
    expect(find.text('Desk'), findsOneWidget);
    expect(find.text('Ei vastaa'), findsOneWidget);
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

    await tester.pumpWidget(page(store));
    await store.load();
    await tester.pumpAndSettle();

    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();

    expect(commands.single, '{"isOn":false}');
    expect(find.text('Pois'), findsOneWidget);
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

    await tester.pumpWidget(page(store));
    await store.load();
    await tester.pumpAndSettle();

    expect(find.text('Yritä uudelleen'), findsOneWidget);
  });

  group('how much fits', () {
    /// Density follows the width one tile ends up with, not the number of columns. Getting that
    /// wrong once already cost every wide screen its switches.
    Future<void> pumpAt(WidgetTester tester, Size size) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await pumpLights(tester, _twoRooms);
    }

    testWidgets('a phone in portrait drops the switch to fit two lamps across', (tester) async {
      await pumpAt(tester, const Size(320, 800));

      expect(find.byType(Switch), findsNothing);

      // The bulb takes over as the target, so there is still a way to turn a lamp off.
      expect(find.byIcon(Icons.lightbulb), findsOneWidget);
    });

    testWidgets('a wider screen keeps the switch, two columns or not', (tester) async {
      await pumpAt(tester, const Size(800, 600));

      expect(find.byType(Switch), findsNWidgets(2));
    });
  });
}
