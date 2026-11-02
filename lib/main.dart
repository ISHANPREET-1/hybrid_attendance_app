import 'package:flutter/material.dart';

import 'dart:async';

import 'theme/app_theme.dart';
import 'utils/user_session.dart';
import 'screens/role_selection/role_selection_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await UserSession.load();
  // Local preferences retain profile form values; attendance comes from SQLite.
  UserSession.attendance.clear();
  await UserSession.refresh();
  Timer.periodic(const Duration(seconds: 5), (_) => UserSession.refresh());
  runApp(const HybridAttendanceApp());
}

class HybridAttendanceApp extends StatelessWidget {
  const HybridAttendanceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Hybrid Attendance',
      theme: AppTheme.lightTheme,
      builder: (context, child) => Column(
        children: [
          ValueListenableBuilder<String?>(
            valueListenable: UserSession.backendError,
            builder: (context, error, _) => error == null
                ? const SizedBox.shrink()
                : Material(
                    color: Colors.amber.shade100,
                    child: SafeArea(
                      bottom: false,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(error),
                      ),
                    ),
                  ),
          ),
          Expanded(child: child!),
        ],
      ),
      home: const RoleSelectionScreen(),
    );
  }
}
