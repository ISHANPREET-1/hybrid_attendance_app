import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import '../utils/backend_api.dart';
import '../utils/portal_store.dart';

String stamp(dynamic value) {
  if (value is! num) return '';
  final d = DateTime.fromMillisecondsSinceEpoch(
    (value * 1000).round(),
    isUtc: true,
  ).add(const Duration(hours: 5, minutes: 30));
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')} IST';
}

class FieldSpec {
  final String keyName, label;
  final bool optional, secret;
  final String initial;
  final Map<String, String>? options;
  const FieldSpec(
    this.keyName,
    this.label, {
    this.optional = false,
    this.secret = false,
    this.initial = '',
    this.options,
  });
}

class EntryDialog extends StatefulWidget {
  final String title;
  final List<FieldSpec> fields;
  const EntryDialog({super.key, required this.title, required this.fields});
  @override
  State<EntryDialog> createState() => _EntryDialogState();
}

class _EntryDialogState extends State<EntryDialog> {
  final formKey = GlobalKey<FormState>();
  final controls = <String, TextEditingController>{};
  @override
  void initState() {
    super.initState();
    for (final f in widget.fields) {
      controls[f.keyName] = TextEditingController(text: f.initial);
    }
  }

  @override
  void dispose() {
    for (final controller in controls.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SizedBox(
      width: 440,
      child: SingleChildScrollView(
        child: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: widget.fields
                .map(
                  (f) => Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: f.options != null
                        ? DropdownButtonFormField<String>(
                            initialValue: f.options!.containsKey(f.initial)
                                ? f.initial
                                : null,
                            isExpanded: true,
                            decoration: InputDecoration(labelText: f.label),
                            items: f.options!.entries
                                .map(
                                  (e) => DropdownMenuItem(
                                    value: e.key,
                                    child: Text(
                                      e.value,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) =>
                                controls[f.keyName]!.text = value ?? '',
                            validator: (value) => value == null && !f.optional
                                ? 'Choose an option'
                                : null,
                          )
                        : TextFormField(
                            controller: controls[f.keyName],
                            obscureText: f.secret,
                            decoration: InputDecoration(labelText: f.label),
                            maxLines: f.secret
                                ? 1
                                : (f.keyName == 'body' ? 4 : 1),
                            validator: (value) =>
                                !f.optional &&
                                    (value == null || value.trim().isEmpty)
                                ? 'Required'
                                : null,
                          ),
                  ),
                )
                .toList(),
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          if (formKey.currentState!.validate()) {
            Navigator.pop(
              context,
              controls.map((key, value) => MapEntry(key, value.text)),
            );
          }
        },
        child: const Text('Continue'),
      ),
    ],
  );
}

class AuthScreen extends StatefulWidget {
  final PortalStore store;
  const AuthScreen({super.key, required this.store});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  String mode = 'login';
  bool busy = false;
  String? error;
  Future<void> submit() async {
    final fields = <FieldSpec>[
      if (mode == 'setup')
        const FieldSpec(
          'setup_token',
          'Administrator setup token',
          secret: true,
        ),
      if (mode == 'reset')
        const FieldSpec('token', 'One-time reset token', secret: true),
      if (mode != 'reset') const FieldSpec('email', 'Email'),
      if (mode == 'register' || mode == 'setup') ...[
        const FieldSpec('name', 'Full name'),
        if (mode == 'register') ...[
          const FieldSpec(
            'roll_no',
            'Roll number (required for students)',
            optional: true,
          ),
          const FieldSpec(
            'invitation',
            'Staff invitation token (optional)',
            optional: true,
            secret: true,
          ),
        ],
      ],
      FieldSpec(
        'password',
        mode == 'login' ? 'Password' : 'Password (12–128 characters)',
        secret: true,
      ),
    ];
    final data = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => EntryDialog(title: title, fields: fields),
    );
    if (data == null) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (mode == 'reset') {
        await BackendApi.request('auth/reset', data);
        if (!mounted) return;
        setState(() {
          mode = 'login';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Password reset. Sign in with your new password.'),
          ),
        );
      } else {
        await widget.store.authenticate(mode, data);
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  String get title => switch (mode) {
    'register' => 'Create your account',
    'setup' => 'Set up administrator',
    'reset' => 'Reset password',
    _ => 'Sign in',
  };
  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(
                    Icons.fact_check_outlined,
                    size: 52,
                    color: Color(0xff197565),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Hybrid Attendance',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(title, style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 12),
                  Text(switch (mode) {
                    'setup' =>
                      'Create the first administrator using ADMIN_SETUP_TOKEN. Local setup token: .tools/setup-token.txt.',
                    'register' =>
                      'Students can register. Teachers and additional administrators need a one-time invitation from an administrator.',
                    'reset' =>
                      'Ask your administrator for a one-time password reset token. Tokens expire after one hour.',
                    _ => 'Your account determines your role and course access.',
                  }),
                  if (error != null || widget.store.error != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        error ?? widget.store.error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: busy ? null : submit,
                    child: Text(busy ? 'Please wait…' : title),
                  ),
                  TextButton(
                    onPressed: busy
                        ? null
                        : () => setState(() {
                            mode = mode == 'register' ? 'login' : 'register';
                            error = null;
                          }),
                    child: Text(
                      mode == 'register'
                          ? 'Already registered? Sign in'
                          : 'Create an account',
                    ),
                  ),
                  if (mode != 'login')
                    TextButton(
                      onPressed: busy
                          ? null
                          : () => setState(() => mode = 'login'),
                      child: const Text('Back to sign in'),
                    ),
                  if (mode == 'login')
                    TextButton(
                      onPressed: busy
                          ? null
                          : () => setState(() => mode = 'reset'),
                      child: const Text('Reset password'),
                    ),
                  if (widget.store.setupRequired)
                    TextButton(
                      onPressed: busy
                          ? null
                          : () => setState(() => mode = 'setup'),
                      child: const Text('First administrator setup'),
                    ),
                  if (widget.store.error != null)
                    TextButton(
                      onPressed: busy ? null : widget.store.initialize,
                      child: const Text('Retry connection'),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class PortalScreen extends StatefulWidget {
  final PortalStore store;
  const PortalScreen({super.key, required this.store});
  @override
  State<PortalScreen> createState() => _PortalScreenState();
}

class _PortalScreenState extends State<PortalScreen> {
  int tab = 0;
  bool busy = false;
  bool dialogOpen = false;
  String query = '';
  PortalStore get store => widget.store;
  bool get student => store.user!['role'] == 'student';
  bool get admin => store.user!['role'] == 'admin';
  List<String> get pages => [
    'Overview',
    'Classes',
    'Sessions',
    'Reports',
    'Announcements',
    'Devices',
    if (admin) 'Administration',
    'Profile',
  ];
  static const icons = [
    Icons.dashboard_outlined,
    Icons.school_outlined,
    Icons.schedule,
    Icons.bar_chart,
    Icons.campaign_outlined,
    Icons.devices,
    Icons.admin_panel_settings_outlined,
    Icons.person_outline,
  ];
  List<Map<String, dynamic>> get courses => store.list('courses');
  String courseName(dynamic id) =>
      courses
          .where((c) => c['id'] == id)
          .map((c) => '${c['code']} · ${c['title']}')
          .firstOrNull ??
      'Course';
  Map<String, String> get courseOptions => {
    for (final c in courses.where((c) => c['archived'] != 1))
      c['id']: '${c['code']} · ${c['title']}',
  };

  Future<void> run(Future<void> Function() action) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<T?> dialog<T>(Widget Function(BuildContext) builder) async {
    setState(() => dialogOpen = true);
    try {
      return await showDialog<T>(context: context, builder: builder);
    } finally {
      if (mounted) setState(() => dialogOpen = false);
    }
  }

  Future<Map<String, dynamic>?> form(String title, List<FieldSpec> fields) =>
      dialog<Map<String, dynamic>>(
        (_) => EntryDialog(title: title, fields: fields),
      );

  Future<void> actionForm(
    String title,
    String endpoint,
    List<FieldSpec> fields, [
    Map<String, dynamic> extra = const {},
  ]) async {
    final data = await form(title, fields);
    if (data == null) return;
    final result = await store.mutate(endpoint, {...extra, ...data});
    if (result['token'] != null && mounted) {
      await dialog<void>(
        (_) => AlertDialog(
          title: const Text('One-time account token'),
          content: SelectableText('${result['message']}\n\n${result['token']}'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Done'),
            ),
          ],
        ),
      );
    }
  }

  Future<bool> confirm(String text) async =>
      await dialog<bool>(
        (_) => AlertDialog(
          title: const Text('Please confirm'),
          content: Text(text),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Confirm'),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> openSession() async {
    final data = await form('Open attendance session', [
      FieldSpec('course_id', 'Course', options: courseOptions),
      const FieldSpec(
        'start_time',
        'Start (optional): YYYY-MM-DD HH:MM in IST',
        optional: true,
      ),
      const FieldSpec('minutes', 'Duration in minutes (1–240)', initial: '15'),
      const FieldSpec(
        'location',
        'Classroom location check',
        initial: 'off',
        options: {
          'off': 'Code + approved browser',
          'on': 'Also use my current location as classroom center',
          'manual': 'Use classroom coordinates entered below',
        },
      ),
      const FieldSpec(
        'latitude',
        'Classroom latitude (manual mode)',
        optional: true,
      ),
      const FieldSpec(
        'longitude',
        'Classroom longitude (manual mode)',
        optional: true,
      ),
      const FieldSpec(
        'radius_m',
        'Location radius in metres (30–5000)',
        initial: '150',
      ),
      FieldSpec(
        'network',
        'Campus network check',
        initial: 'off',
        options: {
          'off': 'Off',
          if (store.state['campus_network_available'] == true)
            'on': 'Require configured campus network',
        },
      ),
    ]);
    if (data == null) return;
    final payload = <String, dynamic>{
      'course_id': data['course_id'],
      'minutes': int.tryParse(data['minutes']) ?? 0,
      'radius_m': int.tryParse(data['radius_m']) ?? 0,
      'network_required': data['network'] == 'on',
      'start_time': data['start_time'],
    };
    if (data['location'] == 'on') {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 30),
        ),
      );
      if (pos.accuracy > (payload['radius_m'] as int)) {
        throw Exception(
          'Location is too imprecise. Try outdoors or on a phone.',
        );
      }
      payload.addAll({'latitude': pos.latitude, 'longitude': pos.longitude});
    } else if (data['location'] == 'manual') {
      final lat = double.tryParse(data['latitude']);
      final lon = double.tryParse(data['longitude']);
      if (lat == null || lon == null) {
        throw Exception('Enter both classroom latitude and longitude');
      }
      payload.addAll({'latitude': lat, 'longitude': lon});
    }
    await store.mutate('sessions/open', payload);
  }

  Future<void> checkIn(Map<String, dynamic> session) async {
    final data = await form('Enter the current classroom code', [
      const FieldSpec('code', 'Six-digit code shown by your teacher'),
    ]);
    if (data == null) return;
    final payload = <String, dynamic>{
      'session_id': session['id'],
      'code': data['code'],
    };
    if (session['latitude'] != null) {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 30),
        ),
      );
      payload.addAll({
        'latitude': pos.latitude,
        'longitude': pos.longitude,
        'accuracy': pos.accuracy,
      });
    }
    await store.mutate('attendance', payload);
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Attendance recorded')));
    }
  }

  Widget button(
    String label,
    Future<void> Function() action, {
    IconData? icon,
  }) => FilledButton.tonal(
    onPressed: busy ? null : () => run(action),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[Icon(icon, size: 18), const SizedBox(width: 8)],
        Flexible(child: Text(label, textAlign: TextAlign.center)),
      ],
    ),
  );

  Widget panel(String title, List<Widget> children) => Card(
    margin: const EdgeInsets.only(bottom: 16),
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    ),
  );

  Widget empty(String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 20),
    child: Text(text),
  );

  Widget overview() {
    final reports = store.list('reports');
    final present = reports
        .where((r) => r['attendance_status'] == 'Present')
        .length;
    final absent = reports
        .where((r) => r['attendance_status'] == 'Absent')
        .length;
    final open = store
        .list('sessions')
        .where((s) => s['status'] == 'open')
        .length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Welcome, ${store.user!['name']}',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 8),
        Text(
          '${store.user!['role'].toString().toUpperCase()} · ${store.user!['email']}',
        ),
        const SizedBox(height: 24),
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            for (final item in [
              ('Classes', '${courses.where((c) => c['archived'] != 1).length}'),
              ('Open sessions', '$open'),
              ('Present records', '$present'),
              ('Absences', '$absent'),
            ])
              SizedBox(
                width: 210,
                child: panel(item.$1, [
                  Text(
                    item.$2,
                    style: Theme.of(context).textTheme.headlineLarge,
                  ),
                ]),
              ),
          ],
        ),
        panel('Getting started', [
          Text(
            student
                ? 'Request approval for this browser in Devices. Your teacher adds your registered email to a class. When a session opens, enter the code shown in the classroom.'
                : admin
                ? 'Invite teachers in Administration, review browser requests in Devices, and manage classes and rosters.'
                : 'Create a class, enroll registered students by email, then open an attendance session. Display its rotating code to the class and close the session when finished.',
          ),
        ]),
        panel('Attendance checks', const [
          Text(
            'Check-in requires a signed-in student, a session roster entry, an approved browser and a rotating classroom code. Teachers may also require browser location and a configured campus network. Browser location can be spoofed; browser approval does not identify physical hardware.',
          ),
        ]),
      ],
    );
  }

  Widget classPage() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (!student)
        Align(
          alignment: Alignment.centerLeft,
          child: button(
            'Create class',
            () => actionForm('Create class', 'courses', [
              const FieldSpec('code', 'Unique course code'),
              const FieldSpec('title', 'Subject'),
              const FieldSpec('room', 'Room', optional: true),
              if (admin)
                FieldSpec(
                  'teacher_id',
                  'Teacher',
                  options: {
                    for (final u
                        in store
                            .list('users')
                            .where((u) => u['role'] == 'teacher'))
                      u['id']: '${u['name']} · ${u['email']}',
                  },
                ),
            ]),
            icon: Icons.add,
          ),
        ),
      const SizedBox(height: 16),
      if (courses.isEmpty)
        empty(
          student
              ? 'You are not enrolled in any classes yet. Give your registered email to your teacher.'
              : 'Create a class to get started.',
        ),
      for (final course in courses)
        panel('${course['code']} · ${course['title']}', [
          Text(
            '${course['room']} ${course['archived'] == 1 ? '· Archived' : ''}',
          ),
          const SizedBox(height: 12),
          if (!student && course['archived'] != 1)
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                button(
                  'Edit class',
                  () => actionForm(
                    'Edit class',
                    'courses/update',
                    [
                      FieldSpec('code', 'Course code', initial: course['code']),
                      FieldSpec('title', 'Subject', initial: course['title']),
                      FieldSpec(
                        'room',
                        'Room',
                        initial: course['room'],
                        optional: true,
                      ),
                    ],
                    {'course_id': course['id']},
                  ),
                ),
                button(
                  'Enroll student',
                  () => actionForm(
                    'Enroll a registered student',
                    'roster/add',
                    [const FieldSpec('email', 'Student email')],
                    {'course_id': course['id']},
                  ),
                ),
                button('Archive class', () async {
                  if (await confirm(
                    'Archive this class and close its sessions? Existing reports will be retained.',
                  )) {
                    await store.mutate('courses/archive', {
                      'course_id': course['id'],
                    });
                  }
                }),
              ],
            ),
          const SizedBox(height: 12),
          for (final member
              in store
                  .list('roster')
                  .where((r) => r['course_id'] == course['id']))
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('${member['name']} · ${member['roll_no']}'),
              subtitle: Text(member['email']),
              trailing: student
                  ? null
                  : IconButton(
                      tooltip: 'Remove from current roster',
                      icon: const Icon(Icons.person_remove_outlined),
                      onPressed: busy
                          ? null
                          : () => run(() async {
                              if (await confirm(
                                'Remove ${member['name']} from this class? Past session rosters and reports will be retained.',
                              )) {
                                await store.mutate('roster/remove', {
                                  'course_id': course['id'],
                                  'email': member['email'],
                                });
                              }
                            }),
                    ),
            ),
        ]),
    ],
  );

  Widget sessionPage() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (!student)
        Align(
          alignment: Alignment.centerLeft,
          child: button('Open session', openSession, icon: Icons.play_arrow),
        ),
      const SizedBox(height: 16),
      if (store.list('sessions').isEmpty) empty('No attendance sessions yet.'),
      for (final session in store.list('sessions'))
        panel(courseName(session['course_id']), [
          Text('${stamp(session['starts_at'])} → ${stamp(session['ends_at'])}'),
          Text(
            'Status: ${session['status']} · ${session['latitude'] != null ? 'Location required · ' : ''}${session['network_required'] == 1 ? 'Campus network required' : 'No network restriction'}',
          ),
          const SizedBox(height: 12),
          if (session['status'] == 'open') ...[
            if (!student) ...[
              SelectableText(
                '${session['code'] ?? ''}',
                style: const TextStyle(
                  fontSize: 42,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 6,
                ),
              ),
              Text(
                'Code changes every 30 seconds. Valid until ${stamp(session['code_expires_at'])}. Refreshes automatically.',
              ),
              const SizedBox(height: 12),
              button('Close session', () async {
                if (await confirm(
                  'Close attendance now? Students who have not checked in will be marked absent.',
                )) {
                  await store.mutate('sessions/close', {
                    'session_id': session['id'],
                  });
                }
              }),
            ] else if (store
                .list('reports')
                .any(
                  (r) =>
                      r['session_id'] == session['id'] &&
                      r['attendance_status'] == 'Present',
                ))
              const Text(
                'Attendance recorded',
                style: TextStyle(
                  color: Colors.green,
                  fontWeight: FontWeight.bold,
                ),
              )
            else
              button(
                session['latitude'] != null
                    ? 'Check in with code and location'
                    : 'Check in with classroom code',
                () => checkIn(session),
              ),
          ],
        ]),
    ],
  );

  Widget reportPage() {
    final reports = store.list('reports');
    final filtered = reports
        .where(
          (r) =>
              '${r['name']} ${r['roll_no']} ${r['course_code']} ${r['title']} ${r['date']} ${r['attendance_status']}'
                  .toLowerCase()
                  .contains(query.toLowerCase()),
        )
        .toList();
    final now = store.state['server_time'] as num? ?? 0;
    final completed = filtered
        .where(
          (r) =>
              r['status'] != 'cancelled' &&
              (r['status'] == 'closed' || (r['ends_at'] as num) <= now),
        )
        .toList();
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final r in completed) {
      groups
          .putIfAbsent(
            '${r['course_code']} · ${r['name']} (${r['roll_no']})',
            () => [],
          )
          .add(r);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            button('Export all CSV', () async {
              if (!await launchUrl(
                Uri.base.resolve('/api/reports.csv'),
                webOnlyWindowName: '_blank',
              )) {
                throw Exception('Could not open the CSV download');
              }
            }, icon: Icons.download),
          ],
        ),
        const SizedBox(height: 16),
        TextField(
          decoration: const InputDecoration(
            labelText: 'Search student, course, date or status',
            prefixIcon: Icon(Icons.search),
          ),
          onChanged: (v) => setState(() => query = v),
        ),
        const SizedBox(height: 16),
        panel('Attendance percentages', [
          const Text(
            'Only completed sessions count toward percentages. Open sessions remain pending until they close.',
          ),
          if (groups.isEmpty) empty('No completed sessions match your search.'),
          for (final e in groups.entries)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(e.key),
              subtitle: Text(
                '${e.value.where((r) => r['attendance_status'] == 'Present').length} / ${e.value.length} completed sessions',
              ),
              trailing: Text(
                '${(100 * e.value.where((r) => r['attendance_status'] == 'Present').length / e.value.length).toStringAsFixed(0)}%',
              ),
            ),
        ]),
        if (filtered.isEmpty) empty('No attendance records yet.'),
        for (final r in filtered)
          Card(
            child: ListTile(
              title: Text('${r['name']} · ${r['roll_no']}'),
              subtitle: Text(
                '${r['course_code']} · ${r['date']}\n${r['recorded_at'] != null ? 'Recorded ${stamp(r['recorded_at'])}' : 'Not recorded'}',
              ),
              isThreeLine: true,
              trailing: Text(
                r['attendance_status'],
                style: TextStyle(
                  color: r['attendance_status'] == 'Absent'
                      ? Colors.red.shade700
                      : r['attendance_status'] == 'Present'
                      ? Colors.green.shade700
                      : Colors.orange.shade800,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget noticePage() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (!student)
        Align(
          alignment: Alignment.centerLeft,
          child: button(
            'Post announcement',
            () => actionForm('Post announcement', 'notices', [
              FieldSpec('course_id', 'Course', options: courseOptions),
              const FieldSpec('body', 'Announcement (up to 1000 characters)'),
            ]),
            icon: Icons.add,
          ),
        ),
      const SizedBox(height: 16),
      if (store.list('notices').isEmpty)
        empty('No announcements for your classes.'),
      for (final notice in store.list('notices'))
        panel(courseName(notice['course_id']), [
          Text(notice['body']),
          const SizedBox(height: 8),
          Text(stamp(notice['created_at'])),
        ]),
    ],
  );

  Widget devicePage() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      panel('Browser approval', [
        const Text(
          'Approval is tied to this browser’s secure cookie. Clearing cookies or switching browsers requires a new approval. An administrator can approve one browser per student at a time. This does not identify physical hardware.',
        ),
        if (student) ...[
          const SizedBox(height: 12),
          button(
            'Request approval for this browser',
            () => actionForm('Describe this browser', 'devices/request', [
              const FieldSpec('label', 'Example: My phone · Chrome'),
            ]),
          ),
        ],
      ]),
      if (store.list('devices').isEmpty) empty('No browser approval requests.'),
      for (final device in store.list('devices'))
        panel(
          '${device['label']} ${device['id'] == store.state['current_device_id'] ? '· This browser' : ''}',
          [
            Text('${device['name']} · ${device['email']}'),
            Text(
              'Status: ${device['status']} · Requested ${stamp(device['created_at'])}',
            ),
            if (admin) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  for (final status in ['approved', 'rejected', 'revoked'])
                    button(
                      switch (status) {
                        'approved' => 'Approve',
                        'rejected' => 'Reject',
                        _ => 'Revoke',
                      },
                      () async {
                        if (await confirm(
                          'Set this browser to $status? Approving it revokes any other approved browser for this student.',
                        )) {
                          await store.mutate('devices/review', {
                            'device_id': device['id'],
                            'status': status,
                          });
                        }
                      },
                    ),
                ],
              ),
            ],
          ],
        ),
    ],
  );

  Widget administration() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          button(
            'Invite staff',
            () => actionForm(
              'Create staff invitation',
              'invitations',
              [
                const FieldSpec('email', 'Recipient email'),
                const FieldSpec(
                  'role',
                  'Account role',
                  initial: 'teacher',
                  options: {'teacher': 'Teacher', 'admin': 'Administrator'},
                ),
              ],
              {'purpose': 'signup'},
            ),
          ),
          button(
            'Issue password reset',
            () => actionForm(
              'Create password reset token',
              'invitations',
              [const FieldSpec('email', 'Account email')],
              {'purpose': 'reset', 'role': 'student'},
            ),
          ),
        ],
      ),
      const SizedBox(height: 16),
      panel('Accounts', [
        for (final user in store.list('users'))
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('${user['name']} · ${user['role']}'),
            subtitle: Text(
              '${user['email']}${user['roll_no'] != null ? ' · ${user['roll_no']}' : ''}',
            ),
          ),
      ]),
      panel('Recent audit activity', [
        for (final event in store.list('audit'))
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(event['action']),
            subtitle: Text(
              '${stamp(event['created_at'])}\nTarget: ${event['target_id']}\nActor: ${event['actor_id']}',
            ),
            isThreeLine: true,
          ),
      ]),
    ],
  );

  Widget profilePage() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      panel('Your profile', [
        Text(
          '${store.user!['name']}\n${store.user!['email']}\nRole: ${store.user!['role']}\n${store.user!['roll_no'] ?? ''}\n${store.user!['department']}\n${store.user!['mobile']}',
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            button(
              'Edit profile',
              () => actionForm('Edit your profile', 'profile', [
                FieldSpec('name', 'Name', initial: store.user!['name']),
                FieldSpec(
                  'department',
                  'Department',
                  optional: true,
                  initial: store.user!['department'],
                ),
                FieldSpec(
                  'mobile',
                  'Mobile',
                  optional: true,
                  initial: store.user!['mobile'],
                ),
              ]),
            ),
            button(
              'Change password',
              () => actionForm(
                'Change password (signs out all sessions)',
                'password',
                [
                  const FieldSpec(
                    'current_password',
                    'Current password',
                    secret: true,
                  ),
                  const FieldSpec(
                    'password',
                    'New password (12–128 characters)',
                    secret: true,
                  ),
                ],
              ),
            ),
          ],
        ),
      ]),
    ],
  );

  Widget content() => switch (pages[tab]) {
    'Overview' => overview(),
    'Classes' => classPage(),
    'Sessions' => sessionPage(),
    'Reports' => reportPage(),
    'Announcements' => noticePage(),
    'Devices' => devicePage(),
    'Administration' => administration(),
    _ => profilePage(),
  };

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 1050;
    final nav = ListView(
      children: [
        const Padding(
          padding: EdgeInsets.all(20),
          child: Text(
            'HYBRID\nATTENDANCE',
            style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 2),
          ),
        ),
        for (var i = 0; i < pages.length; i++)
          ListTile(
            selected: tab == i,
            leading: Icon(
              pages[i] == 'Profile' ? Icons.person_outline : icons[i],
            ),
            title: Text(pages[i]),
            onTap: () {
              setState(() {
                tab = i;
                query = '';
              });
              if (!wide) Navigator.pop(context);
            },
          ),
      ],
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(pages[tab]),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: busy ? null : () => run(store.refresh),
            icon: const Icon(Icons.refresh),
          ),
          TextButton.icon(
            onPressed: busy ? null : () => run(store.logout),
            icon: const Icon(Icons.logout),
            label: const Text('Sign out'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      drawer: wide ? null : Drawer(child: SafeArea(child: nav)),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (wide)
            SizedBox(
              width: 240,
              child: Material(color: Colors.white, child: nav),
            ),
          Expanded(
            child: Column(
              children: [
                if (busy && !dialogOpen) const LinearProgressIndicator(),
                if (store.error != null)
                  Material(
                    color: Colors.amber.shade100,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        'Connection problem: ${store.error}. Showing the last successfully loaded data.',
                      ),
                    ),
                  ),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: store.refresh,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: EdgeInsets.all(wide ? 32 : 16),
                      children: [
                        Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 1150),
                            child: content(),
                          ),
                        ),
                      ],
                    ),
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
