/// Android device identity and classroom Wi-Fi detection.
///
/// Device identity sent to the backend:
/// * install_uuid - random UUID v4 created on first launch and kept in Android
///   Keystore-backed secure storage. It changes when the app is reinstalled or
///   its data is cleared, which forces a new administrator approval.
/// * device_hash - SHA-256 of Settings.Secure.ANDROID_ID plus the device model.
///   ANDROID_ID is unique per (device, user, app-signing key) on Android 8+ and
///   survives reinstalls, so it detects one phone being registered to two
///   students. It is not tamper-proof hardware attestation (rooted phones can
///   change it), so it is one layer among several.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:geolocator/geolocator.dart';
import 'package:network_info_plus/network_info_plus.dart';

const _channel = MethodChannel('hybrid_attendance/device');
const _storage = FlutterSecureStorage();
const _uuidKey = 'attendance_install_uuid';

bool get nativeChecksSupported => Platform.isAndroid;

String _uuidV4() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-'
      '${hex.substring(16, 20)}-${hex.substring(20)}';
}

Future<Map<String, dynamic>> deviceIdentity() async {
  if (!Platform.isAndroid) return {};
  var install = await _storage.read(key: _uuidKey);
  if (install == null || install.length != 36) {
    install = _uuidV4();
    await _storage.write(key: _uuidKey, value: install);
  }
  final info = Map<String, dynamic>.from(
    await _channel.invokeMethod<Map>('identity') ?? const {},
  );
  final androidId = (info['androidId'] ?? '').toString();
  final model = (info['model'] ?? '').toString();
  if (androidId.isEmpty) {
    throw Exception('Could not read this phone\'s Android ID');
  }
  final hash = sha256
      .convert(utf8.encode('hybrid-attendance-v1|$androidId|$model'))
      .toString();
  return {
    'install_uuid': install,
    'device_hash': hash,
    'platform': 'android',
    'model': model,
  };
}

/// Reads the connected Wi-Fi SSID. Android only exposes it with location
/// permission granted and location services switched on.
Future<Map<String, dynamic>> wifiStatus() async {
  if (!Platform.isAndroid) return {'wifi_permission': 'unsupported'};
  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }
  if (permission == LocationPermission.denied ||
      permission == LocationPermission.deniedForever) {
    return {'wifi_permission': 'denied'};
  }
  if (!await Geolocator.isLocationServiceEnabled()) {
    return {
      'wifi_permission': 'granted',
      'wifi_ssid': null,
      'wifi_note': 'Turn on Location so Android can report the Wi-Fi name.',
    };
  }
  final ssid = await NetworkInfo().getWifiName();
  return {'wifi_permission': 'granted', 'wifi_ssid': ssid};
}
