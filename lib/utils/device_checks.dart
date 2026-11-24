/// Browser build: device identity and Wi-Fi name are not available to web pages.
/// The backend rejects Wi-Fi-required sessions from browsers, so students must
/// use the Android app for those sessions.
library;

const bool nativeChecksSupported = false;

Future<Map<String, dynamic>> deviceIdentity() async => {};

Future<Map<String, dynamic>> wifiStatus() async => {
  'wifi_permission': 'unsupported',
};
