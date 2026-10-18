import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import 'attendance_flow_screen.dart';
import 'student_dashboard_screen.dart';
import 'student_stats_screen.dart';
import 'student_profile_screen.dart';
import 'widgets/dashboard_widgets.dart';

class StudentScheduleScreen extends StatelessWidget {
  const StudentScheduleScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.cardSurface,
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(
                  color: AppColors.black.withValues(alpha: 0.06),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: const Icon(
              Icons.arrow_back_ios_new_rounded,
              size: 16,
              color: AppColors.textPrimary,
            ),
          ),
          onPressed: () => Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const StudentDashboardScreen()),
          ),
        ),
        title: const Text(
          'Today\'s Schedule',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: const [
          // ── Completed Class ──────────────────────────────────────────────
          _ScheduleCard(
            subject: 'Database Management',
            courseCode: '40835',
            time: '11:00 AM - 12:30 PM',
            room: 'Room 104',
            status: ClassStatus.completed,
          ),
          SizedBox(height: 16),

          // ── ACTIVE CLASS (This has the button!) ──────────────────────────
          _ScheduleCard(
            subject: 'Operating Systems',
            courseCode: '82703',
            time: '5:00 PM - 6:30 PM',
            room: 'Lab 3B',
            status: ClassStatus.active,
          ),
          SizedBox(height: 16),

          // ── Upcoming Class ───────────────────────────────────────────────
          _ScheduleCard(
            subject: 'Data Structures & Algorithms',
            courseCode: '40921',
            time: '7:00 PM - 8:30 PM',
            room: 'Room 201',
            status: ClassStatus.upcoming,
          ),
        ],
      ), // ── BOTTOM NAVIGATION ─────────────────────────────────────────────
      bottomNavigationBar: DashboardBottomNav(
        currentIndex: 1, // Schedule index is 1
        onTap: (i) {
          if (i == 0) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (context) => const StudentDashboardScreen(),
              ),
            );
          }
          if (i == 1) return;
          if (i == 2) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (context) => const StudentStatsScreen(),
              ),
            );
          }
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
// ─── Status Enum & Card Widget ───────────────────────────────────────────────

enum ClassStatus { completed, active, upcoming }

class _ScheduleCard extends StatelessWidget {
  final String subject;
  final String courseCode;
  final String time;
  final String room;
  final ClassStatus status;

  const _ScheduleCard({
    required this.subject,
    required this.courseCode,
    required this.time,
    required this.room,
    required this.status,
  });

  @override
  Widget build(BuildContext context) {
    final isActive = status == ClassStatus.active;
    final isCompleted = status == ClassStatus.completed;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(16),
        border: isActive
            ? Border.all(color: AppColors.primary, width: 2)
            : Border.all(color: AppColors.dividerLight, width: 1),
        boxShadow: isActive
            ? [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.15),
                  blurRadius: 15,
                  offset: const Offset(0, 5),
                ),
              ]
            : [
                BoxShadow(
                  color: AppColors.black.withValues(alpha: 0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  subject,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: isCompleted
                        ? AppColors.textSecondary
                        : AppColors.textPrimary,
                  ),
                ),
              ),
              if (isCompleted)
                const Icon(
                  Icons.check_circle_rounded,
                  color: AppColors.success,
                  size: 22,
                ),
            ],
          ),
          const SizedBox(height: 12),
          _InfoRow(
            icon: Icons.tag_rounded,
            text: 'Code: $courseCode',
            isMuted: isCompleted,
          ),
          const SizedBox(height: 6),
          _InfoRow(
            icon: Icons.access_time_rounded,
            text: time,
            isMuted: isCompleted,
          ),
          const SizedBox(height: 6),
          _InfoRow(
            icon: Icons.meeting_room_outlined,
            text: room,
            isMuted: isCompleted,
          ),

          // ── The Action Button (Only shows if class is active) ──
          if (isActive) ...[
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: () {
                  // Navigate to the Flow Screen when tapped!
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => AttendanceFlowScreen(
                        subject: subject,
                        courseCode: courseCode,
                      ),
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
                child: const Text(
                  'Mark Attendance',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String text;
  final bool isMuted;

  const _InfoRow({
    required this.icon,
    required this.text,
    required this.isMuted,
  });

  @override
  Widget build(BuildContext context) {
    final color = isMuted
        ? AppColors.textDisabledLight
        : AppColors.textSecondary;
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Text(
          text,
          style: TextStyle(
            color: color,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
