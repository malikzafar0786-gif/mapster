#!/usr/bin/env bash
# Map Overlay - one-step project setup (macOS / Linux)
set -e

APP=map_overlay

if ! command -v flutter >/dev/null 2>&1; then
  echo "Flutter not found. Install it first: https://docs.flutter.dev/get-started/install"
  exit 1
fi

# 1. Create a fresh Android project
flutter create --org com.example --project-name "$APP" --platforms=android "$APP"

# 2. Put our app code in
cp lib/main.dart "$APP/lib/main.dart"

cd "$APP"

# 3. Add packages
flutter pub add flutter_map latlong2 file_picker pdfx image archive path_provider open_filex geolocator

# 4. Add Internet + Location permissions
MANIFEST=android/app/src/main/AndroidManifest.xml
if ! grep -q ACCESS_FINE_LOCATION "$MANIFEST"; then
  perl -0pi -e 's#<application#<uses-permission android:name="android.permission.INTERNET"/>\n    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>\n    <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>\n    <application#' "$MANIFEST"
fi

echo
echo "Done. Connect your phone (USB debugging on) and run:"
echo "  cd $APP && flutter run"
echo "To build an APK:"
echo "  flutter build apk --release"
