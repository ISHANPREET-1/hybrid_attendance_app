import '../../utils/app_actions.dart';

import 'package:flutter/material.dart';
import 'package:hybrid_attendance_app/theme/app_theme.dart';

// ═════════════════════════════════════════════════════════════════════════════
//  MODEL  — replace with real API response from Arpit's backend
// ═════════════════════════════════════════════════════════════════════════════

enum RequestType { deviceChange, newDevice }

enum RequestStatus { pending, approved, rejected }

class DeviceRequest {
  final String id; // UUID from PostgreSQL
  final String studentName;
  final String rollNo;
  final String requestedDeviceId; // device fingerprint
  final String
  currentDeviceId; // nullable in real DB — empty = new registration
  final RequestType type;
  final DateTime submittedAt;
  RequestStatus status;

  DeviceRequest({
    required this.id,
    required this.studentName,
    required this.rollNo,
    required this.requestedDeviceId,
    this.currentDeviceId = '',
    required this.type,
    required this.submittedAt,
    this.status = RequestStatus.pending,
  });
}

// ── Mock data ─────────────────────────────────────────────────────────────────
// TODO (Arpit): replace with GET /api/admin/device-requests
List<DeviceRequest> _mockRequests = [
  DeviceRequest(
    id: 'req-001',
    studentName: 'Aanya Sharma',
    rollNo: '1007521',
    requestedDeviceId: 'iPhone 14 Pro • A2F9B1C3',
    currentDeviceId: 'iPhone 11 • 8D3E2A1F',
    type: RequestType.deviceChange,
    submittedAt: DateTime.now().subtract(const Duration(minutes: 12)),
  ),
  DeviceRequest(
    id: 'req-002',
    studentName: 'Bilal Hassan',
    rollNo: '1007753',
    requestedDeviceId: 'Samsung S23 • F1C4D7B9',
    currentDeviceId: '',
    type: RequestType.newDevice,
    submittedAt: DateTime.now().subtract(const Duration(minutes: 35)),
  ),
  DeviceRequest(
    id: 'req-003',
    studentName: 'Priya Nair',
    rollNo: '1007923',
    requestedDeviceId: 'Pixel 7 • C8A1E3F2',
    currentDeviceId: 'Pixel 6 • 2B9D4F7A',
    type: RequestType.deviceChange,
    submittedAt: DateTime.now().subtract(const Duration(hours: 1)),
  ),
  DeviceRequest(
    id: 'req-004',
    studentName: 'Dev Patel',
    rollNo: '1007533',
    requestedDeviceId: 'OnePlus 11 • 7E3A9C2D',
    currentDeviceId: '',
    type: RequestType.newDevice,
    submittedAt: DateTime.now().subtract(const Duration(hours: 2)),
  ),
  DeviceRequest(
    id: 'req-005',
    studentName: 'Fatima Zaidi',
    rollNo: '1007882',
    requestedDeviceId: 'iPhone 13 • D5B8A2C1',
    currentDeviceId: 'iPhone XR • 3F7E1D9B',
    type: RequestType.deviceChange,
    submittedAt: DateTime.now().subtract(const Duration(hours: 3)),
  ),
];

// ═════════════════════════════════════════════════════════════════════════════
//  SCREEN
// ═════════════════════════════════════════════════════════════════════════════
class AdminDeviceApprovalScreen extends StatefulWidget {
  const AdminDeviceApprovalScreen({super.key});

  @override
  State<AdminDeviceApprovalScreen> createState() =>
      _AdminDeviceApprovalScreenState();
}

class _AdminDeviceApprovalScreenState extends State<AdminDeviceApprovalScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fadeCtrl;
  late final Animation<double> _fadeAnim;

  // ── Current filter tab ────────────────────────────────────────────────────
  RequestStatus _tab = RequestStatus.pending;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _fadeCtrl.forward();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  List<DeviceRequest> get _filtered =>
      _mockRequests.where((r) => r.status == _tab).toList();

  int _count(RequestStatus s) =>
      _mockRequests.where((r) => r.status == s).length;

  // ── Backend hooks — Arpit: replace bodies with real API calls ─────────────

  /// TODO (Arpit): PUT /api/admin/device-requests/{id}/approve
  /// SQL: UPDATE device_requests SET status='approved', updated_at=NOW()
  ///      WHERE id = :id;
  ///      UPDATE students SET device_id = device_requests.requested_device_id
  ///      WHERE student_id = device_requests.student_id;
  Future<void> _onApprove(DeviceRequest req) async {
    // Show confirmation first
    final confirmed = await _showConfirmDialog(
      context,
      title: 'Approve Request?',
      body:
          'This updates a sample request only. No device or account will be bound.',
      actionLabel: 'Approve',
      actionColor: AppColors.success,
    );
    if (!confirmed || !mounted) return;

    // Optimistic UI update
    setState(() => req.status = RequestStatus.approved);

    _showSnack('✓  Approved for ${req.studentName}', AppColors.success);
  }

  /// TODO (Arpit): PUT /api/admin/device-requests/{id}/reject
  /// SQL: UPDATE device_requests SET status='rejected', updated_at=NOW()
  ///      WHERE id = :id;
  Future<void> _onReject(DeviceRequest req) async {
    final confirmed = await _showConfirmDialog(
      context,
      title: 'Reject Request?',
      body: 'This will deny the device change for ${req.studentName}.',
      actionLabel: 'Reject',
      actionColor: AppColors.error,
    );
    if (!confirmed || !mounted) return;

    setState(() => req.status = RequestStatus.rejected);

    _showSnack('✕  Rejected for ${req.studentName}', AppColors.error);
  }

  void _showSnack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          msg,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: AppColors.white,
          ),
        ),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;
    final items = _filtered;

    return Scaffold(
      backgroundColor: context.appBackground,
      appBar: _buildAppBar(isDark),
      body: FadeTransition(
        opacity: _fadeAnim,
        child: Column(
          children: [
            // ── Summary strip ──────────────────────────────────────────────
            _SummaryStrip(
              pending: _count(RequestStatus.pending),
              approved: _count(RequestStatus.approved),
              rejected: _count(RequestStatus.rejected),
              isDark: isDark,
            ),

            // ── Tab bar ────────────────────────────────────────────────────
            _TabBar(
              current: _tab,
              counts: {
                RequestStatus.pending: _count(RequestStatus.pending),
                RequestStatus.approved: _count(RequestStatus.approved),
                RequestStatus.rejected: _count(RequestStatus.rejected),
              },
              onSelect: (t) => setState(() => _tab = t),
            ),

            const SizedBox(height: 4),

            // ── Request list ───────────────────────────────────────────────
            Expanded(
              child: items.isEmpty
                  ? _EmptyState(tab: _tab)
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                      physics: const BouncingScrollPhysics(),
                      itemCount: items.length,
                      itemBuilder: (_, i) => _RequestCard(
                        request: items[i],
                        isDark: isDark,
                        onApprove: () => _onApprove(items[i]),
                        onReject: () => _onReject(items[i]),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  AppBar _buildAppBar(bool isDark) => AppBar(
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
      'Device approvals (demo)',
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
            Icons.refresh_rounded,
            size: 18,
            color: context.appTextPrimary,
          ),
        ),
        // TODO (Arpit): call GET /api/admin/device-requests on tap
        onPressed: () => showAppInfo(
          context,
          'Sample requests',
          'These requests are sample data. No backend is connected.',
        ),
      ),
      const SizedBox(width: 4),
    ],
  );
}

// ═════════════════════════════════════════════════════════════════════════════
//  SUMMARY STRIP
// ═════════════════════════════════════════════════════════════════════════════
class _SummaryStrip extends StatelessWidget {
  final int pending;
  final int approved;
  final int rejected;
  final bool isDark;
  const _SummaryStrip({
    required this.pending,
    required this.approved,
    required this.rejected,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: AppDecorations.card(isDark: isDark),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Device Requests',
                  style: AppTextStyles.headlineSmall(
                    context.appTextPrimary,
                  ).copyWith(fontSize: 14),
                ),
                const SizedBox(height: 2),
                Text(
                  'Sample requests - no devices are linked',
                  style: AppTextStyles.bodySmall(context.appTextSecondary),
                ),
              ],
            ),
          ),
          _Badge('$pending', 'Pending', AppColors.warning),
          const SizedBox(width: 12),
          _Badge('$approved', 'Approved', AppColors.success),
          const SizedBox(width: 12),
          _Badge('$rejected', 'Rejected', AppColors.error),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String value;
  final String label;
  final Color color;
  const _Badge(this.value, this.label, this.color);

  @override
  Widget build(BuildContext context) => Column(
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

// ═════════════════════════════════════════════════════════════════════════════
//  TAB BAR
// ═════════════════════════════════════════════════════════════════════════════
class _TabBar extends StatelessWidget {
  final RequestStatus current;
  final Map<RequestStatus, int> counts;
  final ValueChanged<RequestStatus> onSelect;
  const _TabBar({
    required this.current,
    required this.counts,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    const tabs = [
      (RequestStatus.pending, 'Pending', AppColors.warning),
      (RequestStatus.approved, 'Approved', AppColors.success),
      (RequestStatus.rejected, 'Rejected', AppColors.error),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: tabs.map((t) {
          final (status, label, color) = t;
          final sel = current == status;
          final count = counts[status] ?? 0;
          return Expanded(
            child: GestureDetector(
              onTap: () => onSelect(status),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(vertical: 9),
                decoration: BoxDecoration(
                  color: sel ? color.withValues(alpha: 0.12) : context.appCard,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: sel
                        ? color.withValues(alpha: 0.45)
                        : context.appDivider,
                    width: sel ? 1.5 : 1,
                  ),
                ),
                child: Column(
                  children: [
                    Text(
                      '$count',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: sel ? color : context.appTextSecondary,
                      ),
                    ),
                    Text(
                      label,
                      style: AppTextStyles.caption(
                        sel ? color : context.appTextSecondary,
                      ),
                    ),
                  ],
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
//  REQUEST CARD
// ═════════════════════════════════════════════════════════════════════════════
class _RequestCard extends StatelessWidget {
  final DeviceRequest request;
  final bool isDark;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  const _RequestCard({
    required this.request,
    required this.isDark,
    required this.onApprove,
    required this.onReject,
  });

  String get _initials {
    final p = request.studentName.trim().split(' ');
    return p.length >= 2 ? '${p[0][0]}${p[1][0]}' : p[0][0];
  }

  String get _timeAgo {
    final diff = DateTime.now().difference(request.submittedAt);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  bool get _isPending => request.status == RequestStatus.pending;
  bool get _isApproved => request.status == RequestStatus.approved;

  @override
  Widget build(BuildContext context) {
    final typeLabel = request.type == RequestType.deviceChange
        ? 'Device change request'
        : 'New device registration';
    final typeColor = request.type == RequestType.deviceChange
        ? AppColors.warning
        : AppColors.primary;

    return Container(
      margin: const EdgeInsets.only(top: 10),
      decoration: BoxDecoration(
        color: context.appCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.appDivider, width: 1),
        boxShadow: isDark
            ? []
            : [
                BoxShadow(
                  color: AppColors.black.withValues(alpha: 0.05),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
      ),
      child: Column(
        children: [
          // ── Header ────────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Avatar
                Container(
                  width: 44,
                  height: 44,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [AppColors.primary, AppColors.primaryLight],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      _initials,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.white,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),

                // Name + meta
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              request.studentName,
                              style: AppTextStyles.bodyMedium(
                                context.appTextPrimary,
                              ).copyWith(fontWeight: FontWeight.w600),
                            ),
                          ),
                          Text(
                            _timeAgo,
                            style: AppTextStyles.caption(
                              context.appTextSecondary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Wrap(
                        spacing: 10,
                        runSpacing: 6,
                        children: [
                          _InfoChip(Icons.badge_outlined, request.rollNo),
                          // Type pill
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: typeColor.withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              typeLabel,
                              style: AppTextStyles.caption(typeColor),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Status badge (non-pending)
                if (!_isPending) ...[
                  const SizedBox(width: 8),
                  _StatusPill(isApproved: _isApproved),
                ],
              ],
            ),
          ),

          // ── Device info block ──────────────────────────────────────────────
          Container(
            margin: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark
                  ? AppColors.inputFillDark
                  : AppColors.inputFillLight,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: context.appDivider, width: 1),
            ),
            child: Column(
              children: [
                if (request.currentDeviceId.isNotEmpty) ...[
                  _DeviceRow(
                    label: 'Current Device',
                    value: request.currentDeviceId,
                    icon: Icons.phonelink_off_rounded,
                    color: AppColors.error,
                  ),
                  Divider(height: 16, color: context.appDivider),
                ],
                _DeviceRow(
                  label: request.type == RequestType.deviceChange
                      ? 'Requested Device'
                      : 'New Device',
                  value: request.requestedDeviceId,
                  icon: Icons.smartphone_rounded,
                  color: AppColors.success,
                ),
                // Device ID reference for backend
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    children: [
                      Icon(
                        Icons.fingerprint_rounded,
                        size: 12,
                        color: context.appTextSecondary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Request ID: ${request.id}',
                        style: AppTextStyles.caption(context.appTextSecondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── Action buttons (only for pending) ─────────────────────────────
          if (_isPending)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Row(
                children: [
                  Expanded(
                    child: _ActionBtn(
                      label: 'Approve',
                      icon: Icons.check_rounded,
                      color: AppColors.success,
                      bgColor: AppColors.successLight,
                      onPressed: onApprove,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _ActionBtn(
                      label: 'Reject',
                      icon: Icons.close_rounded,
                      color: AppColors.error,
                      bgColor: AppColors.errorLight,
                      onPressed: onReject,
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

// ── Device row inside the device info block ───────────────────────────────────
class _DeviceRow extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const _DeviceRow({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 16, color: color),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: AppTextStyles.caption(context.appTextSecondary),
              ),
              Text(
                value,
                style: AppTextStyles.bodySmall(
                  context.appTextPrimary,
                ).copyWith(fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Action button ─────────────────────────────────────────────────────────────
class _ActionBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final Color bgColor;
  final VoidCallback onPressed;
  const _ActionBtn({
    required this.label,
    required this.icon,
    required this.color,
    required this.bgColor,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.35), width: 1),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 17, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: AppTextStyles.labelMedium(
                color,
              ).copyWith(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Info chip ─────────────────────────────────────────────────────────────────
class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _InfoChip(this.icon, this.label);

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 11, color: context.appTextSecondary),
      const SizedBox(width: 3),
      Text(label, style: AppTextStyles.bodySmall(context.appTextSecondary)),
    ],
  );
}

// ── Status pill for resolved requests ────────────────────────────────────────
class _StatusPill extends StatelessWidget {
  final bool isApproved;
  const _StatusPill({required this.isApproved});

  @override
  Widget build(BuildContext context) {
    final color = isApproved ? AppColors.success : AppColors.error;
    final bg = isApproved ? AppColors.successLight : AppColors.errorLight;
    final label = isApproved ? 'Approved' : 'Rejected';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label, style: AppTextStyles.caption(color)),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  EMPTY STATE
// ═════════════════════════════════════════════════════════════════════════════
class _EmptyState extends StatelessWidget {
  final RequestStatus tab;
  const _EmptyState({required this.tab});

  @override
  Widget build(BuildContext context) {
    final msgs = {
      RequestStatus.pending: ('No pending requests', Icons.inbox_rounded),
      RequestStatus.approved: (
        'No approved requests yet',
        Icons.check_circle_outline_rounded,
      ),
      RequestStatus.rejected: ('No rejected requests', Icons.cancel_outlined),
    };
    final (msg, icon) = msgs[tab]!;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 52,
            color: context.appTextSecondary.withValues(alpha: 0.35),
          ),
          const SizedBox(height: 12),
          Text(msg, style: AppTextStyles.bodyMedium(context.appTextSecondary)),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  CONFIRM DIALOG  (reusable)
// ═════════════════════════════════════════════════════════════════════════════
// ... (Keep your imports and DeviceRequest/mock data code as is)

// FIX: Updated _showConfirmDialog to be Light-Theme only
Future<bool> _showConfirmDialog(
  BuildContext context, {
  required String title,
  required String body,
  required String actionLabel,
  required Color actionColor,
}) async {
  return await showDialog<bool>(
        context: context,
        builder: (ctx) {
          return AlertDialog(
            backgroundColor: AppColors.cardLight,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Text(
              title,
              style: AppTextStyles.headlineSmall(AppColors.textPrimaryDark),
            ),
            content: Text(
              body,
              style: AppTextStyles.bodyMedium(AppColors.textSecondaryDark),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(
                  'Cancel',
                  style: AppTextStyles.labelMedium(AppColors.textSecondaryDark),
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: actionColor,
                  foregroundColor: AppColors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  elevation: 0,
                ),
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(
                  actionLabel,
                  style: AppTextStyles.labelMedium(AppColors.white),
                ),
              ),
            ],
          );
        },
      ) ??
      false;
}
