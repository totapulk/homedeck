import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homedeck/src/api/homedeck_api.dart';
import 'package:homedeck/src/state/light_store.dart';
import 'package:homedeck/src/ui/ambient_dim.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Comfortably longer than the steps pumpAndSettle takes, so settling an animation cannot
/// quietly age the panel back into idleness.
const Duration _idle = Duration(seconds: 5);
const Duration _pastIdle = Duration(seconds: 6);

double dimness(WidgetTester tester) =>
    tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity;

Future<(LightStore, List<String>)> pumpPanel(WidgetTester tester) async {
  final store = LightStore(
    HomeDeckApi(
      baseUrl: Uri.parse('http://backend'),
      client: MockClient((_) async => http.Response('[]', 200)),
    ),
  );
  final taps = <String>[];

  await tester.pumpWidget(
    MaterialApp(
      home: LightScope(
        store: store,
        child: AmbientDim(
          idleAfter: _idle,
          child: Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => taps.add('tap'),
                child: const Text('Lights off'),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  return (store, taps);
}

Future<void> goIdle(WidgetTester tester) async {
  await tester.pump(_pastIdle);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('starts awake and fades down once nobody is using it', (tester) async {
    await pumpPanel(tester);
    expect(dimness(tester), 0);

    await goIdle(tester);

    // Dimmed, not blanked: the state of the house stays readable from across the room.
    expect(dimness(tester), greaterThan(0.5));
    expect(dimness(tester), lessThan(1));
  });

  testWidgets('a hand on the knob brings it back', (tester) async {
    final (store, _) = await pumpPanel(tester);
    await goIdle(tester);
    expect(dimness(tester), greaterThan(0.5));

    store.noteInteraction();
    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle();

    expect(dimness(tester), 0);
  });

  testWidgets('a light changing on its own does not wake it', (tester) async {
    final (store, _) = await pumpPanel(tester);
    await goIdle(tester);

    // Someone flipping a switch elsewhere in the house is not a reason to light up a hallway
    // at three in the morning.
    await store.load();
    await tester.pump();
    await tester.pumpAndSettle();

    expect(dimness(tester), greaterThan(0.5));
  });

  testWidgets('the tap that wakes it does not also press what is under it', (tester) async {
    final (_, taps) = await pumpPanel(tester);
    await goIdle(tester);

    await tester.tap(find.byType(ElevatedButton), warnIfMissed: false);
    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle();

    expect(taps, isEmpty, reason: 'the first touch in a dark room only wakes the panel');
    expect(dimness(tester), 0);
  });

  testWidgets('a second tap reaches the controls as usual', (tester) async {
    final (_, taps) = await pumpPanel(tester);
    await goIdle(tester);

    await tester.tap(find.byType(ElevatedButton), warnIfMissed: false);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ElevatedButton));
    await tester.pumpAndSettle();

    expect(taps, hasLength(1));
  });
}
