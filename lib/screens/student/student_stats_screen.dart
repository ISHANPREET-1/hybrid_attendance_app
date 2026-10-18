import '../attendance_analytics.dart';

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import 'widgets/dashboard_widgets.dart';
import 'student_dashboard_screen.dart';
import 'student_schedule_screen.dart';
import 'student_profile_screen.dart';

class StudentStatsScreen extends StatelessWidget {
  const StudentStatsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // ── NEW: Defining the sleek teal color to match the pie chart ──

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        automaticallyImplyLeading: false,
        title: const Text(
          'Analytics',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
      ),
      body: const AttendanceAnalytics(studentOnly: true),
      bottomNavigationBar: DashboardBottomNav(
        currentIndex: 2, // Stats is index 2
        onTap: (i) {
          if (i == 0) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (context) => const StudentDashboardScreen(),
              ),
            );
          }
          if (i == 1) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (context) => const StudentScheduleScreen(),
              ),
            );
          }
          if (i == 2) return; // Already here
          if (i == 3) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (context) => const StudentProfileScreen(),
              ),
            );
          }
        },
      ),
    );
  }
}

// ─── Helper Widget for Progress Bars ───
