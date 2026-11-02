import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class BackendApi {
  static bool enabled = true;
  static http.Client client = http.Client();
  static const _base = String.fromEnvironment('API_BASE_URL');

  static Future<Map<String, dynamic>> request(
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    final base = _base.isNotEmpty
        ? _base
        : (kIsWeb ? '' : 'http://127.0.0.1:8080');
    final uri = Uri.parse('$base/api/$path');
    final response =
        await (body == null
                ? client.get(uri)
                : client.post(
                    uri,
                    headers: {'Content-Type': 'application/json'},
                    body: jsonEncode(body),
                  ))
            .timeout(const Duration(seconds: 8));
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode >= 400) {
      throw StateError(data['error']?.toString() ?? 'Server request failed');
    }
    return data;
  }
}
