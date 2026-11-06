import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hybrid_attendance_app/main.dart';
import 'package:hybrid_attendance_app/utils/portal_store.dart';

PortalStore session(String role) {
  final store = PortalStore()..loading = false;
  store.user = {
    'id': 'u1',
    'name': 'Test User',
    'role': role,
    'email': 'test@college.test',
    'roll_no': role == 'student' ? 'CS001' : null,
    'department': 'Computer Science',
    'mobile': '',
  };
  store.state = {
    'server_time': 1793898000,
    'courses': [
      {
        'id': 'c1',
        'code': 'OS101',
        'title': 'Operating Systems',
        'teacher_id': 't1',
        'room': 'Lab 3B',
        'archived': 0,
      },
    ],
    'sessions': [
      {
        'id': 's1',
        'course_id': 'c1',
        'status': 'open',
        'starts_at': 1793897000,
        'ends_at': 1793899000,
        'latitude': null,
        'network_required': 0,
        if (role != 'student') 'code': '123456',
        if (role != 'student') 'code_expires_at': 1793898030,
      },
    ],
    'reports': [
      {
        'student_id': 'u1',
        'name': 'Test User',
        'roll_no': 'CS001',
        'course_code': 'OS101',
        'title': 'Operating Systems',
        'date': '2026-11-05',
        'session_id': 's1',
        'status': 'open',
        'ends_at': 1793899000,
        'recorded_at': null,
        'attendance_status': 'Pending',
      },
    ],
    'roster': [
      {
        'id': 'e1',
        'course_id': 'c1',
        'student_id': 'u1',
        'name': 'Test User',
        'email': 'test@college.test',
        'roll_no': 'CS001',
      },
    ],
    'devices': [
      {
        'id': 'd1',
        'user_id': 'u1',
        'name': 'Test User',
        'email': 'test@college.test',
        'label': 'Phone Chrome',
        'status': 'pending',
        'created_at': 1793897000,
      },
    ],
    'notices': [
      {
        'id': 'n1',
        'course_id': 'c1',
        'body': 'Bring your lab notebook',
        'created_at': 1793897000,
      },
    ],
    'users': [
      {
        'id': 't1',
        'name': 'Teacher',
        'email': 'teacher@college.test',
        'role': 'teacher',
        'roll_no': null,
      },
    ],
    'audit': [],
    'current_device_id': 'd1',
    'campus_network_available': false,
  };
  return store;
}

void main() {
  testWidgets('Login and registration dialog display without a role selector', (
    tester,
  ) async {
    final store = PortalStore()
      ..loading = false
      ..setupRequired = true;
    addTearDown(store.dispose);
    await tester.pumpWidget(HybridAttendanceApp(store: store));
    expect(find.text('Hybrid Attendance'), findsOneWidget);
    expect(find.text('First administrator setup'), findsOneWidget);
    await tester.tap(find.text('Create an account'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Create your account'));
    await tester.pumpAndSettle();
    expect(find.byType(TextFormField), findsNWidgets(5));
    expect(tester.takeException(), isNull);
  });

  for (final role in ['student', 'teacher', 'admin']) {
    testWidgets('$role pages render on a phone without layout errors', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = session(role);
      addTearDown(store.dispose);
      await tester.pumpWidget(HybridAttendanceApp(store: store));
      await tester.pumpAndSettle();
      for (final page in [
        'Classes',
        'Sessions',
        'Reports',
        'Announcements',
        'Devices',
        if (role == 'admin') 'Administration',
        'Profile',
      ]) {
        await tester.tap(find.byTooltip('Open navigation menu'));
        await tester.pumpAndSettle();
        await tester.tap(find.text(page).last);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '$role $page');
      }
    });
  }

  testWidgets(
    'Teacher opens a real session form and student has no management actions',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final teacher = session('teacher');
      addTearDown(teacher.dispose);
      await tester.pumpWidget(HybridAttendanceApp(store: teacher));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sessions').last);
      await tester.pumpAndSettle();
      expect(find.text('123456'), findsOneWidget);
      await tester.tap(find.text('Open session'));
      await tester.pumpAndSettle();
      expect(find.text('Open attendance session'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      final student = session('student');
      addTearDown(student.dispose);
      await tester.pumpWidget(HybridAttendanceApp(store: student));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sessions').last);
      await tester.pumpAndSettle();
      expect(find.text('Open session'), findsNothing);
      expect(find.text('123456'), findsNothing);
      expect(find.text('Check in with classroom code'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
