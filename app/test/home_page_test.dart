import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homedeck/src/api/homedeck_api.dart';
import 'package:homedeck/src/models/fishing.dart';
import 'package:homedeck/src/state/fishing_store.dart';
import 'package:homedeck/src/state/light_store.dart';
import 'package:homedeck/src/state/vacuum_store.dart';
import 'package:homedeck/src/ui/home_page.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const String _forecast = '''
{
  "lakeName": "Jyväsjärvi",
  "best": {"id":"ahven","name":"Ahven","emoji":"AH","index":79},
  "species": [
    {"id":"ahven","name":"Ahven","emoji":"AH","index":79},
    {"id":"hauki","name":"Hauki","emoji":"HA","index":58}
  ],
  "comment": "Ukko nyokkailee.",
  "weather": {"airTempC":18.6,"windMs":3,"pressureHpa":1006,
              "pressureTrend":"hitaasti_laskeva","cloud":"pilvinen",
              "waterTempC":17,"waterSource":"syke"},
  "isAvailable": true,
  "updatedAt": "2026-08-22T15:03:10Z"
}
''';

const String _oneLight = '''
[
  {"id":"a1","name":"Reading lamp","room":"Living room","isOn":true,"brightness":70,
   "colorTempK":2700,"isReachable":true,"updatedAt":"2026-08-22T12:59:49Z"}
]
''';

HomeDeckApi _api(String Function(http.Request request) reply) => HomeDeckApi(
  baseUrl: Uri.parse('http://backend'),
  client: MockClient((request) async => http.Response(reply(request), 200)),
);

const String _docked =
    '{"name":"Robotti-imuri","activity":"Docked","batteryPercent":100,'
    '"isSimulated":true,"updatedAt":"2026-08-22T12:00:00Z"}';

Future<LightStore> _pumpHome(
  WidgetTester tester, {
  String fishing = _forecast,
  String vacuum = _docked,
}) async {
  String reply(http.Request request) {
    final path = request.url.path;
    if (path.startsWith('/api/fishing')) return fishing;
    if (path.startsWith('/api/vacuum')) return vacuum;
    return _oneLight;
  }

  final lights = LightStore(_api(reply));
  final robot = VacuumStore(_api(reply));
  final fish = FishingStore(_api(reply));

  await tester.pumpWidget(
    MaterialApp(
      home: LightScope(
        store: lights,
        child: VacuumScope(
          store: robot,
          child: FishingScope(store: fish, child: const HomePage()),
        ),
      ),
    ),
  );

  await lights.load();
  await robot.load();
  await fish.load();
  await tester.pumpAndSettle();

  return lights;
}

void main() {
  group('one shell, three modules', () {
    testWidgets('opens on the lights and shows nothing from the other modules', (tester) async {
      await _pumpHome(tester);

      expect(find.text('Reading lamp'), findsOneWidget);
      expect(find.text('JYVÄSJÄRVI'), findsNothing);
    });

    testWidgets('the rail swaps the module without disturbing the others', (tester) async {
      await _pumpHome(tester);

      await tester.tap(find.text('Kala'));
      await tester.pumpAndSettle();

      expect(find.text('JYVÄSJÄRVI'), findsOneWidget);
      expect(find.text('Ukko nyokkailee.'), findsOneWidget);

      // Leaving the lights must not unload them: the store outlives the panel.
      expect(find.text('Reading lamp'), findsNothing);
      await tester.tap(find.text('Valot'));
      await tester.pumpAndSettle();
      expect(find.text('Reading lamp'), findsOneWidget);
    });

    testWidgets('the vacuum has a tab of its own rather than a banner over the lights', (tester) async {
      await _pumpHome(tester);

      await tester.tap(find.text('Imuri'));
      await tester.pumpAndSettle();

      expect(find.text('Robotti-imuri'), findsOneWidget);
      expect(find.text('Imuroi'), findsOneWidget);
    });
  });

  group('when the vacuum cannot be reached', () {
    Future<void> openVacuum(WidgetTester tester, {required String vacuum}) async {
      await _pumpHome(tester, vacuum: vacuum);
      await tester.tap(find.text('Imuri'));
      await tester.pumpAndSettle();
    }

    testWidgets('a missing sidecar says so, and says where to look', (tester) async {
      await openVacuum(
        tester,
        vacuum: '{"name":"Robotti-imuri","activity":"Unknown","batteryPercent":null,'
            '"isSimulated":false,"isReachable":false,'
            '"updatedAt":"2026-08-22T12:00:00Z"}',
      );

      expect(find.text('Sidecar ei vastaa'), findsOneWidget);
      expect(find.textContaining('systemctl status homedeck-dreame'), findsOneWidget);

      // Nothing to command, so the button does not pretend otherwise.
      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNull);
    });

    testWidgets('a sidecar that answered unhappily quotes it rather than shrugging', (tester) async {
      await openVacuum(
        tester,
        vacuum: '{"name":"Robotti-imuri","activity":"Unknown","batteryPercent":null,'
            '"isSimulated":false,"isReachable":true,"problem":"the cloud rejected these credentials",'
            '"updatedAt":"2026-08-22T12:00:00Z"}',
      );

      expect(find.text('the cloud rejected these credentials'), findsOneWidget);
      expect(find.text('Sidecar ei vastaa'), findsNothing);
    });

    testWidgets('the vendor state is shown as fine print when there is one', (tester) async {
      await openVacuum(
        tester,
        vacuum: '{"name":"Robotti-imuri","activity":"Docked","batteryPercent":100,'
            '"isSimulated":false,"raw":"CHARGING_COMPLETED",'
            '"updatedAt":"2026-08-22T12:00:00Z"}',
      );

      expect(find.text('CHARGING_COMPLETED'), findsOneWidget);
      expect(find.text('Sidecar vastaa'), findsOneWidget);
    });
  });

  group('the fishing forecast', () {
    testWidgets('leads with the species most likely to bite', (tester) async {
      await _pumpHome(tester);
      await tester.tap(find.text('Kala'));
      await tester.pumpAndSettle();

      expect(find.text('79'), findsOneWidget);
      expect(find.text('paras veto tänään'), findsOneWidget);

      // The conditions the index was computed from, so the number is arguable rather than magic.
      expect(find.text('17 °C vesi'), findsOneWidget);
      expect(find.text('1006 hPa · laskee hitaasti'), findsOneWidget);
    });

    testWidgets('says when the water temperature was guessed rather than measured', (tester) async {
      await _pumpHome(
        tester,
        fishing: _forecast.replaceAll('"waterSource":"syke"', '"waterSource":"estimate"'),
      );
      await tester.tap(find.text('Kala'));
      await tester.pumpAndSettle();

      expect(find.text('17 °C vesi (arvio)'), findsOneWidget);
    });

    testWidgets('an unconfigured lake explains itself instead of showing zeroes', (tester) async {
      await _pumpHome(
        tester,
        fishing: '{"lakeName":"Lake","species":[],"isAvailable":false,'
            '"updatedAt":"2026-08-22T15:03:10Z"}',
      );
      await tester.tap(find.text('Kala'));
      await tester.pumpAndSettle();

      expect(find.textContaining('appsettings.local.json'), findsOneWidget);
      expect(find.text('0'), findsNothing);
    });
  });

  group('the forecast model', () {
    test('keeps the order the far end sorted them into', () {
      final fishing = Fishing.fromJson({
        'lakeName': 'Jyväsjärvi',
        'species': [
          {'id': 'ahven', 'name': 'Ahven', 'emoji': 'AH', 'index': 79},
          {'id': 'hauki', 'name': 'Hauki', 'emoji': 'HA', 'index': 58},
        ],
        'isAvailable': true,
        'updatedAt': '2026-08-22T15:03:10Z',
      });

      // Kala Ukko ranked them; re-sorting here would be a second opinion nobody asked for.
      expect(fishing.species.map((s) => s.id), ['ahven', 'hauki']);
    });

    test('a response missing everything optional is still a forecast object', () {
      final fishing = Fishing.fromJson({'isAvailable': false});

      expect(fishing.isAvailable, isFalse);
      expect(fishing.best, isNull);
      expect(fishing.weather, isNull);
      expect(fishing.species, isEmpty);
    });
  });
}
