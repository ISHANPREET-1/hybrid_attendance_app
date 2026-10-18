import 'teacher_details_screen.dart';
import '../../utils/app_actions.dart';

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

// Screens for Navigation
import 'teacher_dashboard_screen.dart';
import 'teacher_attendance_report_screen.dart';
import 'teacher_analytics_screen.dart';
import '../role_selection/role_selection_screen.dart'; // Adjust path if needed

// Global User Session Data
import '../../utils/user_session.dart';

class TeacherProfileScreen extends StatelessWidget {
  const TeacherProfileScreen({super.key});

  // Helper for Settings Rows
  Widget _buildSettingTile(
    BuildContext context,
    IconData icon,
    String title, {
    bool isDestructive = false,
    VoidCallback? onTap,
  }) {
    return Material(
      type: MaterialType.transparency,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: isDestructive
                ? AppColors.error.withValues(alpha: 0.1)
                : AppColors.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            color: isDestructive ? AppColors.error : AppColors.primary,
            size: 20,
          ),
        ),
        title: Text(
          title,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: isDestructive ? AppColors.error : AppColors.textPrimary,
          ),
        ),
        trailing: const Icon(
          Icons.chevron_right_rounded,
          color: AppColors.textSecondary,
          size: 20,
        ),
        onTap:
            onTap ??
            () => showAppInfo(
              context,
              'Local demo',
              'This feature requires a connected backend. Profiles and demo attendance are saved locally.',
            ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.background,
          elevation: 0,
          scrolledUnderElevation: 0,
          automaticallyImplyLeading: false, // Hide back button for main tabs
          title: const Text(
            'Profile',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          centerTitle: true,
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Dynamic Profile Header Card ──
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.dividerLight),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.03),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    const CircleAvatar(
                      radius: 40,
                      backgroundColor: Color(0xFFF1F5F9),
                      child: Icon(
                        Icons.person,
                        size: 40,
                        color: Color(0xFF94A3B8),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // 1. Dynamic Name
                    Text(
                      'Prof. ${UserSession.teacherName}',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),

                    // 2. Dynamic Department
                    Text(
                      UserSession.teacherDept,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Divider(color: AppColors.dividerLight),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        // 3. Dynamic Faculty ID
                        _buildProfileStat('Faculty ID', UserSession.teacherId),
                        Container(
                          height: 40,
                          width: 1,
                          color: AppColors.dividerLight,
                        ),
                        _buildProfileStat(
                          'Classes',
                          '4 Active',
                        ), // Leaving this hardcoded for now
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              // ── Settings Section ──
              const Text(
                'Account Settings',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.dividerLight),
                ),
                child: Column(
                  children: [
                    _buildSettingTile(
                      context,
                      Icons.person_outline_rounded,
                      'Edit Personal Details',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const TeacherDetailsScreen(),
                        ),
                      ),
                    ),
                    const Divider(color: AppColors.dividerLight, height: 1),
                    _buildSettingTile(
                      context,
                      Icons.notifications_outlined,
                      'Notification Preferences',
                    ),
                    const Divider(color: AppColors.dividerLight, height: 1),
                    _buildSettingTile(
                      context,
                      Icons.lock_outline_rounded,
                      'Privacy & Security',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              const Text(
                'App & Support',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.dividerLight),
                ),
                child: Column(
                  children: [
                    _buildSettingTile(
                      context,
                      Icons.help_outline_rounded,
                      'Help Center',
                    ),
                    const Divider(color: AppColors.dividerLight, height: 1),
                    _buildSettingTile(
                      context,
                      Icons.logout_rounded,
                      'Log Out',
                      isDestructive: true,
                      onTap: () {
                        // Return to Role Selection / Login screen
                        Navigator.pushAndRemoveUntil(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const RoleSelectionScreen(),
                          ),
                          (Route<dynamic> route) => false,
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // ── Bottom Navigation Bar ──
        bottomNavigationBar: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(
              top: BorderSide(color: AppColors.dividerLight, width: 1),
            ),
          ),
          child: SafeArea(
            child: BottomNavigationBar(
              currentIndex: 3, // Profile is index 3
              onTap: (i) {
                if (i == 0) {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const TeacherDashboardScreen(),
                    ),
                  );
                } else if (i == 1) {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          const TeacherAttendanceReportScreen(),
                    ),
                  );
                } else if (i == 2) {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const TeacherAnalyticsScreen(),
                    ),
                  );
                }
                // If i == 3, do nothing (we are already here)
              },
              type: BottomNavigationBarType.fixed,
              backgroundColor: Colors.transparent,
              elevation: 0,
              selectedItemColor: AppColors.primary,
              unselectedItemColor: AppColors.textSecondary,
              selectedLabelStyle: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
              unselectedLabelStyle: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w400,
              ),
              items: const [
                BottomNavigationBarItem(
                  icon: Icon(Icons.home_outlined),
                  activeIcon: Icon(Icons.home),
                  label: 'Home',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.assignment_turned_in_outlined),
                  activeIcon: Icon(Icons.assignment_turned_in_rounded),
                  label: 'Attendance',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.analytics_outlined),
                  activeIcon: Icon(Icons.analytics_rounded),
                  label: 'Analytics',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.person_outline),
                  activeIcon: Icon(Icons.person),
                  label: 'Profile',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProfileStat(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
