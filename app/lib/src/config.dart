/// Where the backend lives. Overridden at build time, because the same source runs on a
/// phone (LAN address), in a browser next to the backend (localhost) and on an emulator.
///
///     flutter run --dart-define=HOMEDECK_API=http://192.168.1.23:5080
class HomeDeckConfig {
  const HomeDeckConfig._();

  static const String _apiBaseUrl = String.fromEnvironment(
    'HOMEDECK_API',
    defaultValue: 'http://localhost:5080',
  );

  static Uri get apiBaseUrl => Uri.parse(_apiBaseUrl);
}
