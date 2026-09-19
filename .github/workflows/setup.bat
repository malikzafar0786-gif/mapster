@echo off
REM Map Overlay - one-step project setup (Windows)

where flutter >nul 2>nul
if errorlevel 1 (
  echo Flutter not found. Install it first: https://docs.flutter.dev/get-started/install
  exit /b 1
)

call flutter create --org com.example --project-name map_overlay --platforms=android map_overlay
if errorlevel 1 exit /b 1

copy /Y lib\main.dart map_overlay\lib\main.dart

cd map_overlay
call flutter pub add flutter_map latlong2 file_picker pdfx image archive path_provider open_filex geolocator
powershell -NoProfile -ExecutionPolicy Bypass -File ..\patch_manifest.ps1

echo.
echo Done. Connect your phone (USB debugging on) and run:
echo   cd map_overlay
echo   flutter run
echo To build an APK:
echo   flutter build apk --release
