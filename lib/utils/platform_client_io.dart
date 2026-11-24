import 'dart:io';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

http.Client createClient() => NativeCookieClient();

/// Stores the login and device-approval cookies encrypted with Android Keystore
/// (flutter_secure_storage). Cookies saved by earlier versions in plain app files
/// are migrated on first read and the old copy is deleted.
class SecureCookieStorage implements Storage {
  static const _prefix = 'cookie_jar:';
  final FlutterSecureStorage _secure;
  final FileStorage? _legacy;

  SecureCookieStorage({FlutterSecureStorage? secure, FileStorage? legacy})
      : _secure = secure ?? const FlutterSecureStorage(),
        _legacy = legacy;

  @override
  Future<void> init(bool persistSession, bool ignoreExpires) async {
    await _legacy?.init(persistSession, ignoreExpires);
  }

  @override
  Future<String?> read(String key) async {
    final value = await _secure.read(key: _prefix + key);
    if (value != null || _legacy == null) return value;
    final old = await _legacy.read(key);
    if (old != null) {
      await _secure.write(key: _prefix + key, value: old);
      await _legacy.delete(key);
    }
    return old;
  }

  @override
  Future<void> write(String key, String value) =>
      _secure.write(key: _prefix + key, value: value);

  @override
  Future<void> delete(String key) async {
    await _secure.delete(key: _prefix + key);
    await _legacy?.delete(key);
  }

  @override
  Future<void> deleteAll(List<String> keys) async {
    for (final key in keys) {
      await delete(key);
    }
  }
}

/// Keeps server-issued login and device cookies in encrypted app storage.
class NativeCookieClient extends http.BaseClient {
  final HttpClient _inner = HttpClient();
  final Future<CookieJar> _jar;

  NativeCookieClient({CookieJar? jar})
      : _jar = jar == null ? _persistentJar() : Future.value(jar);

  static Future<CookieJar> _persistentJar() async {
    final directory = await getApplicationSupportDirectory();
    return PersistCookieJar(
      storage: SecureCookieStorage(
        legacy: FileStorage('${directory.path}/attendance_cookies/'),
      ),
    );
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final jar = await _jar;
    final outgoing = await _inner.openUrl(request.method, request.url);
    // API redirects must never forward authentication to another host.
    outgoing.followRedirects = false;
    outgoing.contentLength = request.contentLength ?? -1;
    request.headers.forEach(outgoing.headers.set);
    outgoing.cookies.addAll(await jar.loadForRequest(request.url));
    await outgoing.addStream(request.finalize());
    final response = await outgoing.close();
    await jar.saveFromResponse(request.url, response.cookies);
    final headers = <String, String>{};
    response.headers.forEach((name, values) => headers[name] = values.join(','));
    return http.StreamedResponse(
      response,
      response.statusCode,
      contentLength: response.contentLength < 0 ? null : response.contentLength,
      headers: headers,
      request: request,
      reasonPhrase: response.reasonPhrase,
      isRedirect: response.isRedirect,
    );
  }

  @override
  void close() => _inner.close(force: true);
}
