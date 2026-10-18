import '../../utils/user_session.dart';

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import 'teacher_dashboard_screen.dart';
import 'teacher_analytics_screen.dart';
import 'teacher_profile_screen.dart';

// ── 1. The Data Model ──
class StudentAttendance {
  final String name;
  final String time;
  final String rollNo;
  final bool isPresent;

  const StudentAttendance(this.name, this.time, this.rollNo, this.isPresent);
}

class TeacherAttendanceReportScreen extends StatefulWidget {
  const TeacherAttendanceReportScreen({super.key});

  @override
  State<TeacherAttendanceReportScreen> createState() =>
      _TeacherAttendanceReportScreenState();
}

class _TeacherAttendanceReportScreenState
    extends State<TeacherAttendanceReportScreen> {
  // ── 2. The Raw Data ──
  List<StudentAttendance> get _students => UserSession.attendance
      .map(
        (r) => StudentAttendance(
          r['name']!,
          '${r['subject']} - ${r['date']} ${r['time']}',
          r['rollNo']!,
          true,
        ),
      )
      .toList();

  // ── 3. State Variables for Search & Filter ──
  String _searchQuery = '';
  String _currentFilter = 'All';

  // ── 4. The Filter Logic ──
  List<StudentAttendance> get _filteredStudents {
    return _students.where((student) {
      final matchesSearch =
          student.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          student.rollNo.contains(_searchQuery);

      bool matchesFilter = true;
      if (_currentFilter == 'Present') matchesFilter = student.isPresent;
      if (_currentFilter == 'Absent') matchesFilter = !student.isPresent;

      return matchesSearch && matchesFilter;
    }).toList();
  }

  // ── 5. Filter Bottom Sheet ──
  void _showFilterSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Filter Attendance',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 16),
              _buildFilterOption('All'),
              _buildFilterOption('Present'),
              _buildFilterOption('Absent'),
              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFilterOption(String filterName) {
    return ListTile(
      title: Text(
        filterName,
        style: const TextStyle(
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
      ),
      selected: _currentFilter == filterName,
      leading: Icon(
        _currentFilter == filterName
            ? Icons.radio_button_checked
            : Icons.radio_button_unchecked,
      ),
      contentPadding: EdgeInsets.zero,
      onTap: () {
        setState(() => _currentFilter = filterName);
        Navigator.pop(context); // Close sheet
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final studentsToDisplay = _filteredStudents;

    return SafeArea(
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.background,
          elevation: 0,
          scrolledUnderElevation: 0,
          leading: IconButton(
            icon: const Icon(
              Icons.arrow_back_ios_new_rounded,
              color: AppColors.textPrimary,
              size: 20,
            ),
            onPressed: () => Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const TeacherDashboardScreen()),
            ),
          ),
          title: const Text(
            'Attendance Report',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          centerTitle: true,
        ),
        body: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            children: [
              const SizedBox(height: 16),
              // ── Search & Filter Row ──
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      onChanged: (value) =>
                          setState(() => _searchQuery = value),
                      style: const TextStyle(fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'Search...',
                        hintStyle: const TextStyle(
                          color: AppColors.textDisabledLight,
                        ),
                        prefixIcon: const Icon(
                          Icons.search_rounded,
                          color: AppColors.textSecondary,
                          size: 20,
                        ),
                        filled: true,
                        fillColor: AppColors.cardSurface,
                        contentPadding: const EdgeInsets.symmetric(vertical: 0),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: AppColors.dividerLight,
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: AppColors.dividerLight,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  GestureDetector(
                    onTap: _showFilterSheet,
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _currentFilter != 'All'
                            ? AppColors.primary.withValues(alpha: 0.1)
                            : AppColors.cardSurface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _currentFilter != 'All'
                              ? AppColors.primary
                              : AppColors.dividerLight,
                        ),
                      ),
                      child: Icon(
                        Icons.filter_list_rounded,
                        color: _currentFilter != 'All'
                            ? AppColors.primary
                            : AppColors.textSecondary,
                        size: 20,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // ── Table Headers ──
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: Text('Student', style: _headerStyle()),
                  ),
                  Expanded(
                    flex: 1,
                    child: Text('Roll No', style: _headerStyle()),
                  ),
                  SizedBox(
                    width: 70,
                    child: Text(
                      'Status',
                      style: _headerStyle(),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // ── Student List (Horizontal Box Design) ──
              Expanded(
                child: studentsToDisplay.isEmpty
                    ? const Center(
                        child: Text(
                          'No students found.',
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                      )
                    : ListView.builder(
                        itemCount: studentsToDisplay.length,
                        itemBuilder: (context, index) {
                          final student = studentsToDisplay[index];
                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppColors.dividerLight),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  flex: 2,
                                  child: Row(
                                    children: [
                                      const CircleAvatar(
                                        radius: 18,
                                        backgroundColor: Color(0xFFF1F5F9),
                                        child: Icon(
                                          Icons.person,
                                          color: Color(0xFF94A3B8),
                                          size: 20,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              student.name,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w700,
                                                fontSize: 13,
                                                color: AppColors.textPrimary,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              student.time,
                                              style: const TextStyle(
                                                color: AppColors.textSecondary,
                                                fontSize: 11,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Expanded(
                                  flex: 1,
                                  child: Text(
                                    student.rollNo,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                ),
                                SizedBox(
                                  width: 75,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 6,
                                      horizontal: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      color: student.isPresent
                                          ? AppColors.success.withValues(
                                              alpha: 0.1,
                                            )
                                          : AppColors.error.withValues(
                                              alpha: 0.1,
                                            ),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: student.isPresent
                                            ? AppColors.success
                                            : AppColors.error,
                                      ),
                                    ),
                                    alignment: Alignment.center,
                                    child: Text(
                                      student.isPresent ? 'Present' : 'Absent',
                                      style: TextStyle(
                                        color: student.isPresent
                                            ? AppColors.success
                                            : AppColors.error,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),

        // ── 6. Bottom Navigation Bar ──
        bottomNavigationBar: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(
              top: BorderSide(color: AppColors.dividerLight, width: 1),
            ),
          ),
          child: SafeArea(
            child: BottomNavigationBar(
              currentIndex: 1, // Attendance is index 1
              onTap: (i) {
                if (i == 0) {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const TeacherDashboardScreen(),
                    ),
                  );
                } else if (i == 2) {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const TeacherAnalyticsScreen(),
                    ),
                  );
                } else if (i == 3) {
                  // ── NEW: Added Profile routing ──
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const TeacherProfileScreen(),
                    ),
                  );
                }
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

  TextStyle _headerStyle() => const TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
  );
}
