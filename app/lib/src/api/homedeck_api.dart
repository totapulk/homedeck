import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/light.dart';
import '../models/light_command.dart';

class HomeDeckApiException implements Exception {
  const HomeDeckApiException(this.message);

  final String message;

  @override
  String toString() => 'HomeDeckApiException: $message';
}

class HomeDeckApi {
  HomeDeckApi({required this.baseUrl, http.Client? client})
    : _client = client ?? http.Client();

  static const Duration _timeout = Duration(seconds: 5);

  final Uri baseUrl;
  final http.Client _client;

  Future<List<Light>> fetchLights() async {
    final response = await _send(() => _client.get(baseUrl.resolve('api/lights')));
    final body = jsonDecode(response.body) as List<dynamic>;
    return [
      for (final entry in body) Light.fromJson(entry as Map<String, dynamic>),
    ];
  }

  /// Returns the light as the bulb confirmed it, which is not always what was asked for.
  Future<Light> applyCommand(String id, LightCommand command) async {
    final response = await _send(
      () => _client.post(
        baseUrl.resolve('api/lights/$id/state'),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode(command.toJson()),
      ),
      // 503 still carries the light: the request was fine, the bulb did not answer, and that
      // is a state worth showing rather than an error to swallow.
      alsoAccept: const {503},
    );

    return Light.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<http.Response> _send(
    Future<http.Response> Function() request, {
    Set<int> alsoAccept = const {},
  }) async {
    final http.Response response;
    try {
      response = await request().timeout(_timeout);
    } on TimeoutException {
      throw HomeDeckApiException('The backend at $baseUrl did not answer in time.');
    } catch (error) {
      throw HomeDeckApiException('Cannot reach the backend at $baseUrl.');
    }

    if (response.statusCode >= 400 && !alsoAccept.contains(response.statusCode)) {
      throw HomeDeckApiException(
        'The backend answered ${response.statusCode}.',
      );
    }

    return response;
  }

  void dispose() => _client.close();
}
