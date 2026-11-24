import 'dart:io';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

http.Client createClient() => NativeCookieClient();

/// Keeps server-issued login and device cookies in Android's private app data.
class NativeCookieClient extends http.BaseClient {
  final HttpClient _inner = HttpClient();
  final Future<CookieJar> _jar;

  NativeCookieClient({CookieJar? jar})
      : _jar = jar == null ? _persistentJar() : Future.value(jar);

  static Future<CookieJar> _persistentJar() async {
    final directory = await getApplicationSupportDirectory();
    return PersistCookieJar(
      storage: FileStorage('${directory.path}/attendance_cookies/'),
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
