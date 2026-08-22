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

The address defaults to `localhost`. That is right for the web build served next to the backend
and wrong for a phone, which needs the machine's address on the LAN.
