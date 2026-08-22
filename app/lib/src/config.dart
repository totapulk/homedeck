import 'package:flutter/foundation.dart' show kIsWeb;

/// Where the backend lives.
///
/// The web build is served by the backend itself, so it can ask the origin it was loaded from
/// and needs no address compiled into it. A native build has no such hint and must be told:
///
///     flutter run --dart-define=HOMEDECK_API=http://192.168.1.23:5080
///
/// The same applies to `flutter run -d chrome`, where the page comes from Flutter's dev server
/// rather than from the backend.
class HomeDeckConfig {
  const HomeDeckConfig._();

  static const String _configured = String.fromEnvironment('HOMEDECK_API');

  static Uri get apiBaseUrl {
    if (_configured.isNotEmpty) return Uri.parse(_configured);
    if (kIsWeb) return Uri.parse(Uri.base.origin);
    return Uri.parse('http://localhost:5080');
  }
}
