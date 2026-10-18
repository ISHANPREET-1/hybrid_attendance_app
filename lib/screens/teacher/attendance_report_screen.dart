import '../../utils/app_actions.dart';

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

// ── Model ─────────────────────────────────────────────────────────────────────
enum AttendanceStatus { present, absent }

class _Student {
  final String name;
  final String rollNo;
  final String timestamp;
  final AttendanceStatus status;
  const _Student({
    required this.name,
    required this.rollNo,
    required this.timestamp,
    required this.status,
  });
}

// ── Mock data ─────────────────────────────────────────────────────────────────
const _allStudents = [
  _Student(
    name: 'Aanya Sharma',
    rollNo: '1007521',
    timestamp: '5:02 PM',
    status: AttendanceStatus.present,
  ),
  _Student(
    name: 'Bilal Hassan',
    rollNo: '1007753',
    timestamp: '5:03 PM',
    status: AttendanceStatus.absent,
  ),
  _Student(
    name: 'Priya Nair',
    rollNo: '1007923',
    timestamp: '5:01 PM',
    status: AttendanceStatus.present,
  ),
  _Student(
    name: 'Dev Patel',
    rollNo: '1007533',
    timestamp: '5:04 PM',
    status: AttendanceStatus.absent,
  ),
  _Student(
    name: 'Sara Khan',
    rollNo: '1007941',
    timestamp: '5:05 PM',
    status: AttendanceStatus.absent,
  ),
  _Student(
    name: 'Rohan Mehta',
    rollNo: '1007851',
    timestamp: '5:02 PM',
    status: AttendanceStatus.present,
  ),
  _Student(
    name: 'Sneha Pillai',
    rollNo: '1007753',
    timestamp: '5:06 PM',
    status: AttendanceStatus.present,
  ),
  _Student(
    name: 'Karan Verma',
    rollNo: '1007771',
    timestamp: '5:03 PM',
    status: AttendanceStatus.absent,
  ),
  _Student(
    name: 'Fatima Zaidi',
    rollNo: '1007882',
    timestamp: '5:07 PM',
    status: AttendanceStatus.present,
  ),
  _Student(
    name: 'Arjun Iyer',
    rollNo: '1007634',
    timestamp: '5:01 PM',
    status: AttendanceStatus.present,
  ),
  _Student(
    name: 'Nisha Gupta',
    rollNo: '1007910',
    timestamp: '5:08 PM',
    status: AttendanceStatus.absent,
  ),
  _Student(
    name: 'Tarun Bose',
    rollNo: '1007456',
    timestamp: '5:04 PM',
    status: AttendanceStatus.present,
  ),
];

// ── Filter enum ───────────────────────────────────────────────────────────────
enum _Filter { all, present, absent }

// ═════════════════════════════════════════════════════════════════════════════
//  SCREEN
// ═════════════════════════════════════════════════════════════════════════════
class AttendanceReportScreen extends StatefulWidget {
  const AttendanceReportScreen({super.key});

  @override
  State<AttendanceReportScreen> createState() => _AttendanceReportScreenState();
}

class _AttendanceReportScreenState extends State<AttendanceReportScreen>
    with SingleTickerProviderStateMixin {
  final _searchCtrl = TextEditingController();
  final _searchFocus = FocusNode();
  _Filter _filter = _Filter.all;
  String _query = '';

  late final AnimationController _fadeCtrl;
  late final Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() => setState(() => _query = _searchCtrl.text));
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _fadeCtrl.forward();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _searchFocus.dispose();
    _fadeCtrl.dispose();
    super.dispose();
  }

  List<_Student> get _filtered {
    return _allStudents.where((s) {
      final matchFilter =
          _filter == _Filter.all ||
          (_filter == _Filter.present &&
              s.status == AttendanceStatus.present) ||
          (_filter == _Filter.absent && s.status == AttendanceStatus.absent);
      final matchQuery =
          _query.isEmpty ||
          s.name.toLowerCase().contains(_query.toLowerCase()) ||
          s.rollNo.contains(_query);
      return matchFilter && matchQuery;
    }).toList();
  }

  int get _presentCount =>
      _allStudents.where((s) => s.status == AttendanceStatus.present).length;
  int get _absentCount =>
      _allStudents.where((s) => s.status == AttendanceStatus.absent).length;

  void _showFilterSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: context.appCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _FilterSheet(
        current: _filter,
        onSelect: (f) {
          setState(() => _filter = f);
          Navigator.pop(context);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;
    final students = _filtered;

    return Scaffold(
      backgroundColor: context.appBackground,
      appBar: _buildAppBar(isDark),
      body: FadeTransition(
        opacity: _fadeAnim,
        child: Column(
          children: [
            // ── Summary strip ──────────────────────────────────────────────
            _SummaryStrip(
              total: _allStudents.length,
              present: _presentCount,
              absent: _absentCount,
              isDark: isDark,
            ),

            // ── Search + filter bar ────────────────────────────────────────
            _SearchBar(
              controller: _searchCtrl,
              focusNode: _searchFocus,
              isDark: isDark,
              onFilter: _showFilterSheet,
              activeFilter: _filter,
            ),

            // ── Filter chips ───────────────────────────────────────────────
            _FilterChips(
              current: _filter,
              onSelect: (f) => setState(() => _filter = f),
            ),

            const SizedBox(height: 4),

            // ── Student list ───────────────────────────────────────────────
            Expanded(
              child: students.isEmpty
                  ? _EmptyState(query: _query)
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      physics: const BouncingScrollPhysics(),
                      itemCount: students.length,
                      itemBuilder: (_, i) => _StudentTile(
                        student: students[i],
                        index: i,
                        isDark: isDark,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  AppBar _buildAppBar(bool isDark) {
    return AppBar(
      backgroundColor: context.appBackground,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      leading: IconButton(
        icon: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: context.appCard,
            borderRadius: BorderRadius.circular(10),
            boxShadow: isDark
                ? []
                : [
                    BoxShadow(
                      color: AppColors.black.withValues(alpha: 0.06),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
          ),
          child: Icon(
            Icons.arrow_back_ios_new_rounded,
            size: 16,
            color: context.appTextPrimary,
          ),
        ),
        onPressed: () => Navigator.pop(context),
      ),
      title: Text(
        'Attendance Report',
        style: AppTextStyles.headlineSmall(context.appTextPrimary),
      ),
      actions: [
        IconButton(
          icon: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: context.appCard,
              borderRadius: BorderRadius.circular(10),
              boxShadow: isDark
                  ? []
                  : [
                      BoxShadow(
                        color: AppColors.black.withValues(alpha: 0.06),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
            ),
            child: Icon(
              Icons.download_rounded,
              size: 17,
              color: context.appTextPrimary,
            ),
          ),
          onPressed: () => showAppInfo(
            context,
            'Local demo',
            'This feature requires a connected backend. Profiles and demo attendance are saved locally.',
          ),
        ),
        const SizedBox(width: 4),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  SUMMARY STRIP  (total / present / absent inline badges)
// ═════════════════════════════════════════════════════════════════════════════
class _SummaryStrip extends StatelessWidget {
  final int total;
  final int present;
  final int absent;
  final bool isDark;
  const _SummaryStrip({
    required this.total,
    required this.present,
    required this.absent,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: AppDecorations.card(isDark: isDark),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'DSA • Section A',
                  style: AppTextStyles.headlineSmall(
                    context.appTextPrimary,
                  ).copyWith(fontSize: 14),
                ),
                const SizedBox(height: 2),
                Text(
                  'Course: 40703  •  5:00 PM  •  June 17',
                  style: AppTextStyles.bodySmall(context.appTextSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _StatBadge('$total', 'Total', AppColors.primary),
          const SizedBox(width: 8),
          _StatBadge('$present', 'Present', AppColors.success),
          const SizedBox(width: 8),
          _StatBadge('$absent', 'Absent', AppColors.error),
        ],
      ),
    );
  }
}

class _StatBadge extends StatelessWidget {
  final String value;
  final String label;
  final Color color;
  const _StatBadge(this.value, this.label, this.color);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: color,
            letterSpacing: -0.5,
          ),
        ),
        Text(label, style: AppTextStyles.caption(color.withValues(alpha: 0.8))),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  SEARCH BAR
// ═════════════════════════════════════════════════════════════════════════════
class _SearchBar extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isDark;
  final VoidCallback onFilter;
  final _Filter activeFilter;
  const _SearchBar({
    required this.controller,
    required this.focusNode,
    required this.isDark,
    required this.onFilter,
    required this.activeFilter,
  });

  @override
  Widget build(BuildContext context) {
    final hasActiveFilter = activeFilter != _Filter.all;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: [
          Expanded(
            child: TextFormField(
              controller: controller,
              focusNode: focusNode,
              style: AppTextStyles.bodyMedium(context.appTextPrimary),
              decoration: InputDecoration(
                hintText: 'Search student or roll no.',
                hintStyle: AppTextStyles.bodyMedium(
                  context.appTextSecondary,
                ).copyWith(fontSize: 13),
                prefixIcon: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Icon(
                    Icons.search_rounded,
                    size: 20,
                    color: context.appTextSecondary,
                  ),
                ),
                prefixIconConstraints: const BoxConstraints(
                  minWidth: 44,
                  minHeight: 44,
                ),
                suffixIcon: controller.text.isNotEmpty
                    ? IconButton(
                        icon: Icon(
                          Icons.close_rounded,
                          size: 18,
                          color: context.appTextSecondary,
                        ),
                        onPressed: controller.clear,
                      )
                    : null,
                filled: true,
                fillColor: isDark
                    ? AppColors.inputFillDark
                    : AppColors.inputFillLight,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 13,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: context.appDivider, width: 1),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(
                    color: AppColors.primary,
                    width: 1.5,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: onFilter,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: hasActiveFilter ? AppColors.primary : context.appCard,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: hasActiveFilter
                      ? AppColors.primary
                      : context.appDivider,
                  width: 1,
                ),
                boxShadow: isDark
                    ? []
                    : [
                        BoxShadow(
                          color: AppColors.black.withValues(alpha: 0.06),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Icon(
                    Icons.tune_rounded,
                    size: 20,
                    color: hasActiveFilter
                        ? AppColors.white
                        : context.appTextPrimary,
                  ),
                  if (hasActiveFilter)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        width: 7,
                        height: 7,
                        decoration: const BoxDecoration(
                          color: AppColors.error,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  FILTER CHIPS
// ═════════════════════════════════════════════════════════════════════════════
class _FilterChips extends StatelessWidget {
  final _Filter current;
  final ValueChanged<_Filter> onSelect;
  const _FilterChips({required this.current, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Row(
        children: _Filter.values.map((f) {
          final selected = current == f;
          final label = f.name[0].toUpperCase() + f.name.substring(1);
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => onSelect(f),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: selected ? AppColors.primary : context.appCard,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: selected ? AppColors.primary : context.appDivider,
                    width: 1,
                  ),
                ),
                child: Text(
                  label,
                  style: AppTextStyles.labelSmall(
                    selected ? AppColors.white : context.appTextSecondary,
                  ).copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  STUDENT TILE
// ═════════════════════════════════════════════════════════════════════════════
class _StudentTile extends StatelessWidget {
  final _Student student;
  final int index;
  final bool isDark;
  const _StudentTile({
    required this.student,
    required this.index,
    required this.isDark,
  });

  String get _initials {
    final parts = student.name.trim().split(' ');
    if (parts.length >= 2) return parts[0][0] + parts[1][0];
    return parts[0][0];
  }

  // Cycle through a few accent colors for avatars
  Color get _avatarColor {
    const colors = [
      Color(0xFF1E2D5A),
      Color(0xFF5856D6),
      Color(0xFF007AFF),
      Color(0xFF34C759),
      Color(0xFFFF9500),
      Color(0xFFFF2D55),
    ];
    return colors[index % colors.length];
  }

  @override
  Widget build(BuildContext context) {
    final isPresent = student.status == AttendanceStatus.present;

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: context.appCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.appDivider, width: 1),
        boxShadow: isDark
            ? []
            : [
                BoxShadow(
                  color: AppColors.black.withValues(alpha: 0.04),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: Row(
        children: [
          // Avatar
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: _avatarColor,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                _initials,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.white,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),

          // Name + roll + timestamp
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  student.name,
                  style: AppTextStyles.bodyMedium(
                    context.appTextPrimary,
                  ).copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Icon(
                      Icons.badge_outlined,
                      size: 11,
                      color: context.appTextSecondary,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      student.rollNo,
                      style: AppTextStyles.bodySmall(context.appTextSecondary),
                    ),
                    const SizedBox(width: 10),
                    Icon(
                      Icons.access_time_rounded,
                      size: 11,
                      color: context.appTextSecondary,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      student.timestamp,
                      style: AppTextStyles.bodySmall(context.appTextSecondary),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Status pill
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: isPresent ? AppColors.successLight : AppColors.errorLight,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: isPresent ? AppColors.success : AppColors.error,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  isPresent ? 'Present' : 'Absent',
                  style: AppTextStyles.caption(
                    isPresent ? AppColors.success : AppColors.error,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  EMPTY STATE
// ═════════════════════════════════════════════════════════════════════════════
class _EmptyState extends StatelessWidget {
  final String query;
  const _EmptyState({required this.query});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.person_search_rounded,
            size: 56,
            color: context.appTextSecondary.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 14),
          Text(
            query.isEmpty ? 'No students found' : 'No results for "$query"',
            style: AppTextStyles.bodyMedium(context.appTextSecondary),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  FILTER BOTTOM SHEET
// ═════════════════════════════════════════════════════════════════════════════
class _FilterSheet extends StatelessWidget {
  final _Filter current;
  final ValueChanged<_Filter> onSelect;
  const _FilterSheet({required this.current, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: context.appDivider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Filter by Status',
            style: AppTextStyles.headlineSmall(context.appTextPrimary),
          ),
          const SizedBox(height: 16),
          ..._Filter.values.map((f) {
            final selected = current == f;
            final label = f.name[0].toUpperCase() + f.name.substring(1);
            final color = f == _Filter.present
                ? AppColors.success
                : f == _Filter.absent
                ? AppColors.error
                : AppColors.primary;
            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  f == _Filter.present
                      ? Icons.check_circle_outline_rounded
                      : f == _Filter.absent
                      ? Icons.cancel_outlined
                      : Icons.people_outline_rounded,
                  size: 20,
                  color: color,
                ),
              ),
              title: Text(
                label,
                style: AppTextStyles.bodyMedium(
                  context.appTextPrimary,
                ).copyWith(fontWeight: FontWeight.w500),
              ),
              trailing: selected
                  ? const Icon(
                      Icons.check_rounded,
                      color: AppColors.primary,
                      size: 20,
                    )
                  : null,
              onTap: () => onSelect(f),
            );
          }),
        ],
      ),
    );
  }
}
