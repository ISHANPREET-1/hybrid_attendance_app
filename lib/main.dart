import 'package:flutter/material.dart';
import 'screens/portal.dart';
import 'utils/portal_store.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const HybridAttendanceApp());
}

class HybridAttendanceApp extends StatefulWidget {
  final PortalStore? store;
  const HybridAttendanceApp({super.key, this.store});
  @override
  State<HybridAttendanceApp> createState() => _HybridAttendanceAppState();
}

class _HybridAttendanceAppState extends State<HybridAttendanceApp> {
  late final PortalStore store;
  @override
  void initState() {
    super.initState();
    store = widget.store ?? PortalStore();
    if (widget.store == null) store.initialize();
  }

  @override
  void dispose() {
    if (widget.store == null) store.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Hybrid Attendance',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      colorSchemeSeed: const Color(0xff197565),
      scaffoldBackgroundColor: const Color(0xfff4f7f6),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
      ),
    ),
    home: ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        if (store.loading) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return store.user == null
            ? AuthScreen(store: store)
            : PortalScreen(key: ValueKey(store.user!['id']), store: store);
      },
    ),
  );
}
