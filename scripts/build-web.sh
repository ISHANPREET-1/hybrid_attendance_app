#!/usr/bin/env bash
set -euo pipefail
python3 -m pip install -r requirements.txt
python3 -m backend.manage migrate
# Pin the SDK for repeatable builds; only official Flutter sources are used.
FLUTTER_VERSION=3.47.9
if ! command -v flutter >/dev/null 2>&1; then
  git clone --depth 1 --branch "$FLUTTER_VERSION" https://github.com/flutter/flutter.git /tmp/hybrid-flutter
  export PATH="/tmp/hybrid-flutter/bin:$PATH"
fi
flutter config --no-analytics
flutter pub get
flutter build web --release --no-web-resources-cdn
