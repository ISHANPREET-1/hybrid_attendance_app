import '../role_selection/role_selection_screen.dart';
import '../../utils/app_actions.dart';

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import 'widgets/dashboard_widgets.dart';
import 'student_dashboard_screen.dart';
import 'student_schedule_screen.dart';
import 'student_stats_screen.dart';

// ── NEW: Import the global session file ──
import '../../utils/user_session.dart';

class StudentProfileScreen extends StatelessWidget {
  const StudentProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        automaticallyImplyLeading: false,
        title: const Text(
          'Profile',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            children: [
              // ── User Identity Card ─────────────────────────────────
              Container(
                padding: const EdgeInsets.all(24),
                decoration: AppDecorations.card(isDark: false),
                child: Column(
                  children: [
                    Container(
                      width: 80,
                      height: 80,
                      decoration: const BoxDecoration(
                        color: AppColors.primaryLight,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          UserSession.studentName.isNotEmpty
                              ? UserSession.studentName[0].toUpperCase()
                              : 'S',
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      UserSession.studentName,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${UserSession.studentRollNo} • ${UserSession.studentEmail}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 14,
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),

              // ── Settings List ──────────────────────────────────────
              const SectionHeader(title: 'Account & Settings'),
              Container(
                decoration: AppDecorations.card(isDark: false),
                child: Column(
                  children: [
                    _ProfileTile(
                      icon: Icons.devices_rounded,
                      title: 'Linked Devices',
                      subtitle: 'Manage your registered phone',
                      onTap: () => showAppInfo(
                        context,
                        'Local demo',
                        'This feature requires a connected backend. Profiles and demo attendance are saved locally.',
                      ),
                    ),
                    const Divider(height: 1, color: AppColors.dividerLight),
                    _ProfileTile(
                      icon: Icons.notifications_outlined,
                      title: 'Notifications',
                      subtitle: 'Alerts and updates',
                      onTap: () => showAppInfo(
                        context,
                        'Local demo',
                        'This feature requires a connected backend. Profiles and demo attendance are saved locally.',
                      ),
                    ),
                    const Divider(height: 1, color: AppColors.dividerLight),
                    _ProfileTile(
                      icon: Icons.help_outline_rounded,
                      title: 'Help & Support',
                      subtitle: 'Contact administration',
                      onTap: () => showAppInfo(
                        context,
                        'Local demo',
                        'This feature requires a connected backend. Profiles and demo attendance are saved locally.',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // ── Logout Button ──────────────────────────────────────
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(
                        builder: (_) => const RoleSelectionScreen(),
                      ),
                      (route) => false,
                    );
                  },
                  icon: const Icon(
                    Icons.logout_rounded,
                    color: AppColors.error,
                  ),
                  label: const Text(
                    'Log Out',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.error,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFCE8E6),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
              // Add extra padding at the bottom for the BottomNav
              const SizedBox(height: 100),
            ],
          ),
        ),
      ),
      bottomNavigationBar: DashboardBottomNav(
        currentIndex: 3,
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
          if (i == 2) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (context) => const StudentStatsScreen(),
              ),
            );
          }
        },
      ),
    );
  }
}

// ─── Helper Widget for List Tiles ───────────────────────────────────────
class _ProfileTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ProfileTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: AppColors.primary, size: 22),
        ),
        title: Text(
          title,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
        ),
        trailing: const Icon(
          Icons.chevron_right_rounded,
          color: AppColors.textSecondary,
        ),
        onTap: onTap,
      ),
    );
  }
}
