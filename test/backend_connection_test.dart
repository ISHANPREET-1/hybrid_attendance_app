import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hybrid_attendance_app/utils/backend_api.dart';
import 'package:hybrid_attendance_app/utils/user_session.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    BackendApi.enabled = true;
    UserSession.attendance.clear();
    UserSession.studentRollNo = 'TEST-1';
    UserSession.studentName = 'Test Student';
  });

  tearDown(() {
    BackendApi.client.close();
    BackendApi.client = http.Client();
    BackendApi.enabled = false;
    UserSession.backendError.value = null;
  });

  test('Attendance uses the API and the server-authoritative record', () async {
    BackendApi.client = MockClient((request) async {
      expect(request.url.path, '/api/attendance');
      expect(request.method, 'POST');
      expect(jsonDecode(request.body)['rollNo'], 'TEST-1');
      return http.Response(
        jsonEncode({
          'record': {
            'name': 'Server Name',
            'rollNo': 'TEST-1',
            'subject': 'OS',
            'courseCode': '82703',
            'date': '2026-11-02',
            'time': '12:30',
          },
        }),
        201,
      );
    });
    await UserSession.recordAttendance('OS', '82703');
    expect(UserSession.attendance.single['name'], 'Server Name');
  });

  test('A failed attendance request never creates a local success', () async {
    BackendApi.client = MockClient(
      (_) async => http.Response('{"error":"Database unavailable"}', 500),
    );
    await expectLater(
      UserSession.recordAttendance('OS', '82703'),
      throwsStateError,
    );
    expect(UserSession.attendance, isEmpty);
  });

  test(
    'Server refresh replaces browser records and exposes network errors',
    () async {
      UserSession.attendance.add({'name': 'Old browser record'});
      BackendApi.client = MockClient(
        (_) async => http.Response('{"records":[]}', 200),
      );
      await UserSession.refresh();
      expect(UserSession.attendance, isEmpty);
      expect(UserSession.backendError.value, isNull);
      BackendApi.client = MockClient(
        (_) async => throw http.ClientException('Offline'),
      );
      await UserSession.refresh();
      expect(UserSession.backendError.value, isNotNull);
    },
  );
}
