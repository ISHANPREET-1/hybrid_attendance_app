import 'package:flutter/material.dart';

import '../../utils/user_session.dart';

class AttendanceFlowScreen extends StatefulWidget {
  final String subject;
  final String courseCode;
  const AttendanceFlowScreen({
    super.key,
    this.subject = 'Operating Systems',
    this.courseCode = '82703',
  });
  @override
  State<AttendanceFlowScreen> createState() => _AttendanceFlowScreenState();
}

class _AttendanceFlowScreenState extends State<AttendanceFlowScreen> {
  bool _saving = false;
  String? _error;
  Future<void> _record() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await UserSession.recordAttendance(widget.subject, widget.courseCode);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not save attendance. Please retry.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final recorded = UserSession.hasAttendance(widget.courseCode);
    return Scaffold(
      appBar: AppBar(title: const Text('Attendance')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                widget.subject,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              Text('Course code: ${widget.courseCode}'),
              const SizedBox(height: 24),
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Text(
                    'Local demo: attendance is stored on this device. Classroom Wi-Fi, device approval and physical presence are not verified. Verified attendance requires a backend and platform integrations.',
                  ),
                ),
              ),
              const SizedBox(height: 24),
              if (recorded)
                const ListTile(
                  leading: Icon(Icons.check_circle, color: Colors.green),
                  title: Text('Demo attendance recorded for today'),
                ),
              if (_error != null)
                Text(_error!, style: const TextStyle(color: Colors.red)),
              FilledButton(
                onPressed: recorded || _saving ? null : _record,
                child: Text(
                  _saving
                      ? 'Saving...'
                      : recorded
                      ? 'Recorded'
                      : 'Record demo attendance',
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Back to classes'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
