import '../../utils/app_actions.dart';

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import 'widgets/dashboard_widgets.dart';
import 'student_schedule_screen.dart';
import 'student_stats_screen.dart';
import 'student_profile_screen.dart';
// ── ADD THIS LINE ──
import '../../utils/user_session.dart';

// ═══════════════════════════════════════════════════════════════════════════════
//  STUDENT DASHBOARD SCREEN
// ═══════════════════════════════════════════════════════════════════════════════

class StudentDashboardScreen extends StatefulWidget {
  const StudentDashboardScreen({super.key});

  @override
  State<StudentDashboardScreen> createState() => _StudentDashboardScreenState();
}

class _StudentDashboardScreenState extends State<StudentDashboardScreen>
    with SingleTickerProviderStateMixin {
  int _navIndex = 0;

  late final AnimationController _fadeCtrl;
  late final Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _fadeCtrl.forward();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Calculate responsive metrics based on current screen width
    final screenWidth = MediaQuery.of(context).size.width;
    // On wider screens (tablets), use more padding. On smaller (phones), use 20px.
    final horizontalPadding = screenWidth > 600 ? 40.0 : 20.0;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: FadeTransition(
        opacity: _fadeAnim,
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            // ── Sticky app bar (Now accepting dynamic padding) ──────────
            _DashboardAppBar(horizontalPadding: horizontalPadding),

            // ── Body sections ───────────────────────────────────────────
            SliverPadding(
              // Using the dynamic horizontal padding calculated above
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                4,
                horizontalPadding,
                32,
              ),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  // ── Today's Classes ────────────────────────────────────
                  const TodaysClassesSection(),
                  const SizedBox(height: 28),

                  // ── Attendance Summary ─────────────────────────────────
                  const AttendanceSummarySection(),
                  const SizedBox(height: 28),

                  // ── Weekly Timetable + Notifications (side-by-side) ───
                  const DashboardBottomRow(),
                ]),
              ),
            ),
          ],
        ),
      ),

      // ── Bottom Navigation ─────────────────────────────────────────────
      bottomNavigationBar: DashboardBottomNav(
        currentIndex: _navIndex,
        onTap: (i) {
          if (_navIndex == i) return;

          setState(() => _navIndex = i);

          if (i == 0) {
            Navigator.popUntil(context, (route) => route.isFirst);
          } else if (i == 1) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (context) => const StudentScheduleScreen(),
              ),
            );
          } else if (i == 2) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (context) => const StudentStatsScreen(),
              ),
            );
          } else if (i == 3) {
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
  } // Closes the build method
} // Closes the _StudentDashboardScreenState class

// ═══════════════════════════════════════════════════════════════════════════════
//  SLIVER APP BAR
// ═══════════════════════════════════════════════════════════════════════════════

class _DashboardAppBar extends StatelessWidget {
  final double horizontalPadding;
  const _DashboardAppBar({required this.horizontalPadding});

  @override
  Widget build(BuildContext context) {
    // Dynamically calculate font size based on screen width
    final screenWidth = MediaQuery.of(context).size.width;
    final fontSize = screenWidth > 400 ? 22.0 : 18.0;

    return SliverAppBar(
      pinned: true,
      floating: false,
      expandedHeight: 90,
      backgroundColor: AppColors.background,
      elevation: 0,
      scrolledUnderElevation: 0,
      automaticallyImplyLeading: false,
      flexibleSpace: FlexibleSpaceBar(
        collapseMode: CollapseMode.pin,
        background: Container(
          color: AppColors.background,
          // Use the responsive padding passed from the parent
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            45,
            horizontalPadding,
            0,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Greeting with dynamic font size
              Expanded(
                child: Text(
                  'Welcome, ${UserSession.studentName}',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: fontSize,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                    letterSpacing: -0.4,
                  ),
                ),
              ),
              // Notification bell
              _IconBtn(
                icon: Icons.notifications_outlined,
                badge: true,
                onTap: () => showAppInfo(
                  context,
                  'Local demo',
                  'This feature requires a connected backend. Profiles and demo attendance are saved locally.',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final bool badge;
  final VoidCallback onTap;
  const _IconBtn({required this.icon, required this.onTap, this.badge = false});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.cardSurface,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: AppColors.black.withValues(alpha: 0.06),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: const Icon(
              Icons.notifications_none_rounded,
              color: AppColors.textPrimary,
              size: 22,
            ),
          ),
          if (badge)
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: AppColors.error,
                  shape: BoxShape.circle,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
