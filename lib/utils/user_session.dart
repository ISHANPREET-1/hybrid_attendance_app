import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class UserSession {
  static String teacherName = 'Teacher';
  static String teacherEmail = '';
  static String teacherId = 'FAC-0000';
  static String teacherDept = 'General';
  static String studentName = 'Student';
  static String studentRollNo = '000000';
  static String studentEmail = '';
  static String studentMobile = '';
  static String studentDepartment = '';
  static String studentSemester = '';
  static String studentSection = '';
  static final List<Map<String, String>> attendance = [];
  static final revision = ValueNotifier<int>(0);

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final profile = prefs.getString('profiles');
    if (profile != null) {
      final data = jsonDecode(profile) as Map<String, dynamic>;
      teacherName = data['teacherName'] ?? 'Teacher';
      teacherId = data['teacherId'] ?? 'FAC-0000';
      teacherDept = data['teacherDept'] ?? 'General';
      studentName = data['studentName'] ?? 'Student';
      studentRollNo = data['studentRollNo'] ?? '000000';
      studentEmail = data['studentEmail'] ?? '';
      studentMobile = data['studentMobile'] ?? '';
      studentDepartment = data['studentDepartment'] ?? '';
      studentSemester = data['studentSemester'] ?? '';
      studentSection = data['studentSection'] ?? '';
    }
    attendance.clear();
    final records = prefs.getString('attendance');
    if (records != null) {
      attendance.addAll(
        (jsonDecode(records) as List).map((r) => Map<String, String>.from(r)),
      );
    }
  }

  static Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString(
      'profiles',
      jsonEncode({
        'teacherName': teacherName,
        'teacherId': teacherId,
        'teacherDept': teacherDept,
        'studentName': studentName,
        'studentRollNo': studentRollNo,
        'studentEmail': studentEmail,
        'studentMobile': studentMobile,
        'studentDepartment': studentDepartment,
        'studentSemester': studentSemester,
        'studentSection': studentSection,
      }),
    )) {
      throw StateError('Profile could not be saved');
    }
  }

  static bool hasAttendance(String courseCode) => attendance.any(
    (r) =>
        r['rollNo'] == studentRollNo &&
        r['courseCode'] == courseCode &&
        r['date'] == DateTime.now().toIso8601String().substring(0, 10),
  );

  static Future<void> recordAttendance(
    String subject,
    String courseCode,
  ) async {
    if (hasAttendance(courseCode)) return;
    final now = DateTime.now();
    final record = {
      'name': studentName,
      'rollNo': studentRollNo,
      'subject': subject,
      'courseCode': courseCode,
      'date': now.toIso8601String().substring(0, 10),
      'time':
          '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}',
    };
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString(
      'attendance',
      jsonEncode([...attendance, record]),
    )) {
      throw StateError('Attendance could not be saved');
    }
    attendance.add(record);
    revision.value++;
  }
}
