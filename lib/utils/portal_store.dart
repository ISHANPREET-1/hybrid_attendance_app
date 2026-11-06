import 'dart:async';
import 'package:flutter/foundation.dart';
import 'backend_api.dart';

class PortalStore extends ChangeNotifier {
  Map<String, dynamic>? user;
  Map<String, dynamic> state = {};
  String? error;
  bool loading = true;
  bool setupRequired = false;
  bool _refreshing = false;
  Timer? _timer;

  List<Map<String, dynamic>> list(String key) => (state[key] as List? ?? [])
      .map((r) => Map<String, dynamic>.from(r))
      .toList();

  Future<void> initialize() async {
    try {
      setupRequired =
          (await BackendApi.request('auth/status'))['setup_required'] == true;
      try {
        final result = await BackendApi.request('auth/me');
        user = Map<String, dynamic>.from(result['user']);
        BackendApi.csrf = result['csrf'];
        await refresh();
      } on ApiException catch (e) {
        if (e.status != 401) rethrow;
      }
    } catch (e) {
      error = e.toString();
    } finally {
      loading = false;
      notifyListeners();
    }
    _timer ??= Timer.periodic(const Duration(seconds: 10), (_) => refresh());
  }

  Future<void> authenticate(String action, Map<String, dynamic> data) async {
    final result = await BackendApi.request('auth/$action', data);
    user = Map<String, dynamic>.from(result['user']);
    BackendApi.csrf = result['csrf'];
    setupRequired = false;
    state = {};
    error = null;
    await refresh();
    notifyListeners();
  }

  Future<void> refresh() async {
    if (user == null || _refreshing) return;
    _refreshing = true;
    try {
      state = await BackendApi.request('state');
      user = Map<String, dynamic>.from(state['user']);
      error = null;
    } catch (e) {
      if (e is ApiException && e.status == 401) {
        user = null;
        state = {};
        BackendApi.csrf = null;
      }
      error = e.toString();
    } finally {
      _refreshing = false;
      notifyListeners();
    }
  }

  Future<Map<String, dynamic>> mutate(
    String action,
    Map<String, dynamic> data,
  ) async {
    final result = await BackendApi.request(action, data);
    if (action == 'password') {
      user = null;
      state = {};
      BackendApi.csrf = null;
      notifyListeners();
    } else {
      await refresh();
    }
    return result;
  }

  Future<void> logout() async {
    await BackendApi.request('auth/logout', {});
    user = null;
    state = {};
    error = null;
    BackendApi.csrf = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
