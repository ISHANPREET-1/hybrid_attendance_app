import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hybrid_attendance_app/main.dart';
import 'package:hybrid_attendance_app/screens/admin/admin_device_approval_screen.dart';
import 'package:hybrid_attendance_app/screens/student/student_dashboard_screen.dart';
import 'package:hybrid_attendance_app/screens/student/student_schedule_screen.dart';
import 'package:hybrid_attendance_app/screens/student/student_stats_screen.dart';
import 'package:hybrid_attendance_app/screens/student/student_profile_screen.dart';
import 'package:hybrid_attendance_app/screens/teacher/teacher_dashboard_screen.dart';
import 'package:hybrid_attendance_app/screens/teacher/teacher_analytics_screen.dart';
import 'package:hybrid_attendance_app/screens/teacher/teacher_profile_screen.dart';

import 'package:hybrid_attendance_app/utils/user_session.dart';
import 'package:hybrid_attendance_app/screens/student/attendance_flow_screen.dart';
import 'package:hybrid_attendance_app/screens/teacher/teacher_attendance_report_screen.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await UserSession.load();
    UserSession.studentName = 'Test Student';
    UserSession.studentRollNo = '12345';
  });

  testWidgets('Role selector opens student registration', (tester) async {
    await tester.pumpWidget(const HybridAttendanceApp());
    await tester.tap(find.text('Student'));
    await tester.pumpAndSettle();
    expect(find.byType(TextFormField), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  test(
    'Profiles and attendance survive reload and prevent daily duplicates',
    () async {
      await UserSession.save();
      await UserSession.recordAttendance('Operating Systems', '82703');
      await UserSession.recordAttendance('Operating Systems', '82703');
      expect(UserSession.attendance.length, 1);
      UserSession.studentName = 'Changed';
      await UserSession.load();
      expect(UserSession.studentName, 'Test Student');
      expect(UserSession.hasAttendance('82703'), isTrue);
      UserSession.studentRollNo = '67890';
      expect(UserSession.hasAttendance('82703'), isFalse);
    },
  );

  testWidgets('Recording attendance reaches the teacher report', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: AttendanceFlowScreen()));
    await tester.tap(find.text('Record demo attendance'));
    await tester.pumpAndSettle();
    expect(find.text('Demo attendance recorded for today'), findsOneWidget);
    expect(UserSession.attendance.length, 1);
    await tester.pumpWidget(
      const MaterialApp(home: TeacherAttendanceReportScreen()),
    );
    await tester.pumpAndSettle();
    expect(find.text('Test Student'), findsOneWidget);
    expect(find.text('12345'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('Main screens render on a phone without layout errors', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final screen in <Widget>[
      const StudentDashboardScreen(),
      const StudentScheduleScreen(),
      const StudentStatsScreen(),
      const StudentProfileScreen(),
      const TeacherDashboardScreen(),
      const TeacherAnalyticsScreen(),
      const TeacherProfileScreen(),
      const AdminDeviceApprovalScreen(),
      const TeacherAttendanceReportScreen(),
    ]) {
      await tester.pumpWidget(MaterialApp(home: screen));
      await tester.pumpAndSettle();
      expect(
        tester.takeException(),
        isNull,
        reason: screen.runtimeType.toString(),
      );
    }
  });
}
