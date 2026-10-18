import 'package:flutter/material.dart';

import 'theme/app_theme.dart';
import 'utils/user_session.dart';
import 'screens/role_selection/role_selection_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await UserSession.load();
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
      home: const RoleSelectionScreen(),
    );
  }
}
