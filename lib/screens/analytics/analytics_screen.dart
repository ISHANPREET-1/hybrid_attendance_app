import '../../utils/app_actions.dart';

import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

import '../../theme/app_theme.dart';

// ═════════════════════════════════════════════════════════════════════════════
//  MOCK DATA  — swap these lists with real API data from your backend
// ═════════════════════════════════════════════════════════════════════════════

/// Bar chart: attendance % per subject
class _SubjectStat {
  final String subject; // short label
  final String fullName; // tooltip
  final double percent; // 0–100
  const _SubjectStat(this.subject, this.fullName, this.percent);
}

const _subjectStats = [
  _SubjectStat('DSA', 'Data Structures', 88),
  _SubjectStat('OS', 'Operating Sys.', 72),
  _SubjectStat('DBMS', 'Database Mgmt', 95),
  _SubjectStat('CN', 'Computer Nets', 65),
  _SubjectStat('SE', 'Software Eng.', 80),
  _SubjectStat('AI', 'Artificial Int.', 58),
];

/// Line chart: weekly overall attendance trend (Mon–Fri, last 3 weeks)
class _TrendPoint {
  final double x; // week offset
  final double y; // percent
  const _TrendPoint(this.x, this.y);
}

// Week 1
const _week1 = [
  _TrendPoint(0, 82),
  _TrendPoint(1, 75),
  _TrendPoint(2, 90),
  _TrendPoint(3, 68),
  _TrendPoint(4, 85),
];
// Week 2
const _week2 = [
  _TrendPoint(0, 70),
  _TrendPoint(1, 80),
  _TrendPoint(2, 72),
  _TrendPoint(3, 88),
  _TrendPoint(4, 78),
];
// Week 3 (current)
const _week3 = [
  _TrendPoint(0, 88),
  _TrendPoint(1, 92),
  _TrendPoint(2, 85),
  _TrendPoint(3, 95),
  _TrendPoint(4, 78),
];

// ── Deep-dark colour tokens local to this screen ──────────────────────────────
const _bg = Color(0xFF0D0F18);
const _card = Color(0xFF161827);
const _cardBdr = Color(0xFF252740);
const _grid = Color(0xFF1E2035);
const _textHi = Color(0xFFF0F0FF);
const _textLo = Color(0xFF7B7E9A);
const _accent1 = Color(0xFF6C63FF); // violet – bar primary
const _accent2 = Color(0xFF00D4AA); // teal   – line week 3
const _accent3 = Color(0xFF4C9EFF); // blue   – line week 2
const _accent4 = Color(0xFFFF6B8A); // rose   – line week 1

// ═════════════════════════════════════════════════════════════════════════════
//  SCREEN
// ═════════════════════════════════════════════════════════════════════════════
class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});
  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fadeCtrl;
  late final Animation<double> _fadeAnim;
  int _touchedBar = -1;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 550),
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
    return Scaffold(
      backgroundColor: _bg,
      appBar: _buildAppBar(context),
      body: FadeTransition(
        opacity: _fadeAnim,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
          physics: const BouncingScrollPhysics(),
          children: [
            // ── Period selector ──────────────────────────────────────────
            _PeriodSelector(),
            const SizedBox(height: 24),

            // ── Overview chips ───────────────────────────────────────────
            _OverviewRow(),
            const SizedBox(height: 24),

            // ── Bar chart card ───────────────────────────────────────────
            const _SectionLabel('Attendance (%)'),
            const SizedBox(height: 12),
            _ChartCard(
              height: 240,
              child: _SubjectBarChart(
                stats: _subjectStats,
                touched: _touchedBar,
                onTouch: (i) => setState(() => _touchedBar = i),
              ),
            ),

            const SizedBox(height: 24),

            // ── Line chart card ──────────────────────────────────────────
            const _SectionLabel('Trend Analytics'),
            const SizedBox(height: 12),
            _ChartCard(
              height: 220,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _LineLegend(),
                  const SizedBox(height: 16),
                  const Expanded(child: _TrendLineChart()),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // ── Bottom stats row ─────────────────────────────────────────
            _BottomStatsRow(),
          ],
        ),
      ),
    );
  }

  AppBar _buildAppBar(BuildContext context) => AppBar(
    backgroundColor: _bg,
    elevation: 0,
    scrolledUnderElevation: 0,
    centerTitle: false,
    leading: IconButton(
      icon: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _cardBdr, width: 1),
        ),
        child: const Icon(
          Icons.arrow_back_ios_new_rounded,
          size: 16,
          color: _textHi,
        ),
      ),
      onPressed: () => Navigator.pop(context),
    ),
    title: const Text(
      'Analytics',
      style: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: _textHi,
        letterSpacing: -0.3,
      ),
    ),
    actions: [
      IconButton(
        icon: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: _card,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _cardBdr, width: 1),
          ),
          child: const Icon(Icons.share_rounded, size: 17, color: _textHi),
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

// ═════════════════════════════════════════════════════════════════════════════
//  PERIOD SELECTOR  (week / month / semester chips)
// ═════════════════════════════════════════════════════════════════════════════
class _PeriodSelector extends StatefulWidget {
  @override
  State<_PeriodSelector> createState() => _PeriodSelectorState();
}

class _PeriodSelectorState extends State<_PeriodSelector> {
  int _sel = 1;
  final _labels = ['Week', 'Month', 'Semester'];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _cardBdr, width: 1),
      ),
      child: Row(
        children: List.generate(_labels.length, (i) {
          final sel = i == _sel;
          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _sel = i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 9),
                decoration: BoxDecoration(
                  color: sel ? _accent1 : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  _labels[i],
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: sel ? FontWeight.w600 : FontWeight.w400,
                    color: sel ? AppColors.white : _textLo,
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  OVERVIEW CHIPS ROW
// ═════════════════════════════════════════════════════════════════════════════
class _OverviewRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        Expanded(child: _OverviewChip('Avg.', '79%', _accent2)),
        SizedBox(width: 10),
        Expanded(child: _OverviewChip('Best', '95%', _accent1)),
        SizedBox(width: 10),
        Expanded(child: _OverviewChip('Lowest', '58%', _accent4)),
      ],
    );
  }
}

class _OverviewChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _OverviewChip(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.25), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: _textLo,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: color,
              letterSpacing: -0.5,
            ),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  SECTION LABEL
// ═════════════════════════════════════════════════════════════════════════════
class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w600,
      color: _textHi,
      letterSpacing: -0.2,
    ),
  );
}

// ═════════════════════════════════════════════════════════════════════════════
//  CHART CARD WRAPPER
// ═════════════════════════════════════════════════════════════════════════════
class _ChartCard extends StatelessWidget {
  final Widget child;
  final double height;
  const _ChartCard({required this.child, required this.height});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _cardBdr, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: child,
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  SUBJECT BAR CHART  (fl_chart BarChart)
// ═════════════════════════════════════════════════════════════════════════════
class _SubjectBarChart extends StatelessWidget {
  final List<_SubjectStat> stats;
  final int touched;
  final ValueChanged<int> onTouch;
  const _SubjectBarChart({
    required this.stats,
    required this.touched,
    required this.onTouch,
  });

  @override
  Widget build(BuildContext context) {
    return BarChart(
      BarChartData(
        maxY: 100,
        minY: 0,
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => _cardBdr,
            tooltipRoundedRadius: 10,
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              final s = stats[groupIndex];
              return BarTooltipItem(
                '${s.fullName}\n',
                const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: _textLo,
                ),
                children: [
                  TextSpan(
                    text: '${s.percent.toInt()}%',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: _accent1,
                    ),
                  ),
                ],
              );
            },
          ),
          touchCallback: (event, response) {
            if (event is FlTapUpEvent || event is FlPanUpdateEvent) {
              onTouch(response?.spot?.touchedBarGroupIndex ?? -1);
            }
          },
        ),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: 25,
          getDrawingHorizontalLine: (_) =>
              const FlLine(color: _grid, strokeWidth: 1, dashArray: [4, 4]),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: 25,
              reservedSize: 34,
              getTitlesWidget: (v, _) => Text(
                '${v.toInt()}%',
                style: const TextStyle(fontSize: 10, color: _textLo),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (v, _) {
                final i = v.toInt();
                if (i < 0 || i >= stats.length) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    stats[i].subject,
                    style: TextStyle(
                      fontSize: 10,
                      color: i == touched ? _accent1 : _textLo,
                      fontWeight: i == touched
                          ? FontWeight.w600
                          : FontWeight.w400,
                    ),
                  ),
                );
              },
            ),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
        ),
        barGroups: stats.asMap().entries.map((e) {
          final i = e.key;
          final stat = e.value;
          final isTouched = i == touched;
          final pct = stat.percent;

          // Colour: danger (<70) = rose, ok (70–84) = teal, great (≥85) = violet
          final barColor = pct < 70
              ? _accent4
              : pct < 85
              ? _accent3
              : _accent1;

          return BarChartGroupData(
            x: i,
            barRods: [
              BarChartRodData(
                toY: pct,
                width: isTouched ? 18 : 14,
                borderRadius: BorderRadius.circular(6),
                gradient: LinearGradient(
                  colors: [barColor.withValues(alpha: 0.6), barColor],
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                ),
                backDrawRodData: BackgroundBarChartRodData(
                  show: true,
                  toY: 100,
                  color: _grid,
                ),
              ),
            ],
            showingTooltipIndicators: isTouched ? [0] : [],
          );
        }).toList(),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  LINE CHART LEGEND
// ═════════════════════════════════════════════════════════════════════════════
class _LineLegend extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        _LegendDot(_accent4, 'Week 1'),
        SizedBox(width: 16),
        _LegendDot(_accent3, 'Week 2'),
        SizedBox(width: 16),
        _LegendDot(_accent2, 'Week 3'),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot(this.color, this.label);

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 24,
        height: 3,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
      const SizedBox(width: 6),
      Text(label, style: const TextStyle(fontSize: 11, color: _textLo)),
    ],
  );
}

// ═════════════════════════════════════════════════════════════════════════════
//  TREND LINE CHART  (fl_chart LineChart)
// ═════════════════════════════════════════════════════════════════════════════
class _TrendLineChart extends StatelessWidget {
  const _TrendLineChart();

  LineChartBarData _line(List<_TrendPoint> pts, Color color, bool showDots) {
    return LineChartBarData(
      spots: pts.map((p) => FlSpot(p.x, p.y)).toList(),
      isCurved: true,
      curveSmoothness: 0.35,
      color: color,
      barWidth: 2.5,
      isStrokeCapRound: true,
      dotData: FlDotData(
        show: showDots,
        getDotPainter: (_, __, ___, ____) => FlDotCirclePainter(
          radius: 4,
          color: color,
          strokeColor: _card,
          strokeWidth: 2,
        ),
      ),
      belowBarData: BarAreaData(
        show: showDots, // only fill the active (week 3) line
        gradient: LinearGradient(
          colors: [
            color.withValues(alpha: 0.25),
            color.withValues(alpha: 0.00),
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LineChart(
      LineChartData(
        minY: 50,
        maxY: 100,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: 10,
          getDrawingHorizontalLine: (_) =>
              const FlLine(color: _grid, strokeWidth: 1, dashArray: [4, 4]),
        ),
        borderData: FlBorderData(show: false),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => _cardBdr,
            tooltipRoundedRadius: 10,
            getTooltipItems: (spots) => spots.map((s) {
              final colors = [_accent4, _accent3, _accent2];
              final idx = s.barIndex.clamp(0, 2);
              return LineTooltipItem(
                '${s.y.toInt()}%',
                TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: colors[idx],
                ),
              );
            }).toList(),
          ),
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: 10,
              reservedSize: 34,
              getTitlesWidget: (v, _) => Text(
                '${v.toInt()}%',
                style: const TextStyle(fontSize: 10, color: _textLo),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (v, _) {
                const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri'];
                final i = v.toInt();
                if (i < 0 || i >= days.length) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    days[i],
                    style: const TextStyle(fontSize: 10, color: _textLo),
                  ),
                );
              },
            ),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
        ),
        lineBarsData: [
          _line(_week1, _accent4, false),
          _line(_week2, _accent3, false),
          _line(_week3, _accent2, true),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  BOTTOM STATS ROW
// ═════════════════════════════════════════════════════════════════════════════
class _BottomStatsRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        Expanded(
          child: _BottomStatCard(
            label: 'Total Classes',
            value: '60',
            sub: 'This semester',
            icon: Icons.event_note_rounded,
            color: _accent1,
          ),
        ),
        SizedBox(width: 10),
        Expanded(
          child: _BottomStatCard(
            label: 'Streak',
            value: '5 days',
            sub: 'Current run',
            icon: Icons.local_fire_department_rounded,
            color: _accent4,
          ),
        ),
        SizedBox(width: 10),
        Expanded(
          child: _BottomStatCard(
            label: 'On Track',
            value: '4 / 6',
            sub: 'Subjects ≥ 75%',
            icon: Icons.check_circle_outline_rounded,
            color: _accent2,
          ),
        ),
      ],
    );
  }
}

class _BottomStatCard extends StatelessWidget {
  final String label;
  final String value;
  final String sub;
  final IconData icon;
  final Color color;
  const _BottomStatCard({
    required this.label,
    required this.value,
    required this.sub,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _cardBdr, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: _textHi,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: _textLo,
            ),
          ),
          Text(
            sub,
            style: TextStyle(
              fontSize: 10,
              color: _textLo.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }
}
