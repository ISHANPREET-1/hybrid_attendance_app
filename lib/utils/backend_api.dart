import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'platform_client.dart'
    if (dart.library.io) 'platform_client_io.dart' as platform;

class BackendApi {
  static bool enabled = true;
  static String? csrf;
  static http.Client client = platform.createClient();
  static const _base = String.fromEnvironment('API_BASE_URL');
  static String serverUrl = _base.isNotEmpty ? _base : 'http://127.0.0.1:8080';

  static Future<void> initialize() async {
    if (!kIsWeb) {
      final preferences = await SharedPreferences.getInstance();
      serverUrl = preferences.getString('backend_server_url') ?? serverUrl;
    }
  }

  static Future<void> setServerUrl(String value) async {
    final uri = Uri.tryParse(value.trim());
    final local = uri != null &&
        ['127.0.0.1', 'localhost', '10.0.2.2'].contains(uri.host);
    if (uri == null || uri.host.isEmpty || uri.userInfo.isNotEmpty ||
        uri.hasQuery || uri.hasFragment ||
        (uri.path.isNotEmpty && uri.path != '/') ||
        (uri.scheme != 'https' && !(uri.scheme == 'http' && local))) {
      throw const FormatException('Enter an HTTPS server address, such as https://your-project.vercel.app');
    }
    final normalized = uri.origin;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString('backend_server_url', normalized);
    serverUrl = normalized;
    csrf = null;
  }

  static Future<Map<String, dynamic>> request(
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    final base = kIsWeb ? _base : serverUrl;
    final uri = Uri.parse('$base/api/$path');
    final response =
        await (body == null
                ? client.get(uri)
                : client.post(
                    uri,
                    headers: {
                      'Content-Type': 'application/json',
                      if (csrf != null) 'X-CSRF-Token': csrf!,
                    },
                    body: jsonEncode(body),
                  ))
            .timeout(const Duration(seconds: 8));
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode >= 400) {
      throw ApiException(
        data['error']?.toString() ?? 'Server request failed',
        response.statusCode,
        data,
      );
    }
    if (response.statusCode == 202) data['pending'] = true;
    return data;
  }
}

class ApiException implements Exception {
  final String message;
  final int status;
  /// Full error body, e.g. the per-layer `checks` of a rejected check-in.
  final Map<String, dynamic> data;
  ApiException(this.message, this.status, [this.data = const {}]);
  @override
  String toString() => message;
}
