# HomeDeck app

The Flutter half of [HomeDeck](../README.md): the UI, and on Android the BLE central that the
knob connects to.

One codebase, two targets. The web build has no radio, so `ControllerInput` has two
implementations — `BleControllerInput` where a radio exists, and `MockControllerInput` behind
the on-screen pad everywhere else. Both emit identical events, which is why the input pipeline
can be tested without hardware.

```
flutter run --dart-define=HOMEDECK_API=http://192.168.1.23:5080
flutter test
flutter analyze
```

A native build needs `HOMEDECK_API`; without it it looks for `localhost`, which on a phone is
the phone. The browser build is served by the backend and asks the origin it was loaded from,
so it needs nothing — except under `flutter run -d chrome`, where the page comes from Flutter's
own dev server and the define is required again.

Build it into the backend's static root with `../scripts/build-web.sh`.
