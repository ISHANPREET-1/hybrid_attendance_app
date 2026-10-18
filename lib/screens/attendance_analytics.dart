import 'package:flutter/material.dart';

import '../utils/user_session.dart';

class AttendanceAnalytics extends StatelessWidget {
  final bool studentOnly;
  const AttendanceAnalytics({super.key, this.studentOnly = false});
  @override
  Widget build(BuildContext context) {
    final records = UserSession.attendance
        .where((r) => !studentOnly || r['rollNo'] == UserSession.studentRollNo)
        .toList();
    final bySubject = <String, int>{};
    for (final r in records) {
      bySubject.update(r['subject']!, (n) => n + 1, ifAbsent: () => 1);
    }
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          'Local demo attendance',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 12),
        const Text(
          'These records are saved on this device. Attendance percentages and absences require a class roster and scheduled sessions.',
        ),
        const SizedBox(height: 24),
        Card(
          child: ListTile(
            leading: const Icon(Icons.fact_check_outlined),
            title: Text('${records.length} attendance records'),
            subtitle: Text(
              '${records.map((r) => r['date']).toSet().length} days recorded',
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (records.isEmpty)
          const Text(
            'No attendance yet. Open an active class from the student schedule to record demo attendance.',
          ),
        ...bySubject.entries.map(
          (e) => Card(
            child: ListTile(
              title: Text(e.key),
              trailing: Text('${e.value} records'),
            ),
          ),
        ),
        ...records.reversed
            .take(10)
            .map(
              (r) => ListTile(
                title: Text(r['subject']!),
                subtitle: Text('${r['name']} - ${r['date']} ${r['time']}'),
              ),
            ),
      ],
    );
  }
}
