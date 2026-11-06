import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hybrid_attendance_app/utils/backend_api.dart';
import 'package:hybrid_attendance_app/utils/portal_store.dart';

void main() {
  tearDown(() {
    BackendApi.csrf = null;
    BackendApi.client.close();
    BackendApi.client = http.Client();
  });

  test(
    'Login uses server-assigned role, loads state and sends CSRF on mutations',
    () async {
      final user = {
        'id': 'student-1',
        'name': 'Student',
        'email': 'student@college.test',
        'role': 'student',
      };
      final requested = <String>[];
      BackendApi.client = MockClient((req) async {
        requested.add(req.url.path);
        if (req.url.path == '/api/auth/login') {
          expect(jsonDecode(req.body)['email'], 'student@college.test');
          return http.Response(
            jsonEncode({'user': user, 'csrf': 'csrf-secret'}),
            200,
          );
        }
        if (req.url.path == '/api/profile') {
          expect(req.headers['X-CSRF-Token'], 'csrf-secret');
          return http.Response('{"message":"Saved"}', 200);
        }
        return http.Response(
          jsonEncode({'user': user, 'courses': [], 'reports': []}),
          200,
        );
      });
      final store = PortalStore();
      await store.authenticate('login', {
        'email': 'student@college.test',
        'password': 'password',
      });
      expect(store.user!['role'], 'student');
      expect(BackendApi.csrf, 'csrf-secret');
      await store.mutate('profile', {'name': 'Updated'});
      expect(requested, contains('/api/profile'));
      store.dispose();
    },
  );

  test('Expired session clears all previously loaded private state', () async {
    BackendApi.client = MockClient(
      (_) async => http.Response('{"error":"Session expired"}', 401),
    );
    final store = PortalStore()
      ..user = {'id': '1', 'role': 'admin'}
      ..state = {
        'users': [
          {'email': 'private'},
        ],
      };
    await store.refresh();
    expect(store.user, isNull);
    expect(store.state, isEmpty);
    store.dispose();
  });

  test('Failed write throws an actionable server error', () async {
    BackendApi.client = MockClient(
      (_) async => http.Response('{"error":"Browser needs approval"}', 403),
    );
    await expectLater(
      BackendApi.request('attendance', {'session_id': 's'}),
      throwsA(
        isA<ApiException>().having(
          (e) => e.message,
          'message',
          'Browser needs approval',
        ),
      ),
    );
  });

  test(
    'Connection errors retain the last loaded records with a visible error',
    () async {
      BackendApi.client = MockClient(
        (_) async => throw http.ClientException('Offline'),
      );
      final store = PortalStore()
        ..user = {'id': '1'}
        ..state = {
          'reports': [
            {'name': 'Saved record'},
          ],
        };
      await store.refresh();
      expect(store.error, isNotNull);
      expect(store.list('reports').length, 1);
      store.dispose();
    },
  );
}
