# Map Overlay — PDF/JPG سے KMZ (Google Earth)

اینڈرائیڈ ایپ (Flutter) جو PDF یا JPG کو PNG میں بدل کر نقشے پر لگاتی ہے اور KMZ بنا کر Google Earth میں کھولتی ہے۔

## فیچرز
- PDF (کئی صفحات) اور JPG/PNG سے PNG بنانا
- نقشے پر دو ٹیپ سے تصویر کی جگہ اور سائز طے کرنا
- Rotation (‑180° سے 180°) اور Opacity سلائیڈر، نقشے پر لائیو پریویو
- ایپ کھلتے ہی موجودہ لوکیشن پر نقشہ
- KMZ بنا کر سیدھا Google Earth میں کھولنا

## ضروریات
1. Flutter SDK (https://docs.flutter.dev/get-started/install)
2. Android Studio / Android SDK
3. اینڈرائیڈ فون (USB debugging آن) یا ایمولیٹر
4. Google Earth ایپ فون میں انسٹال ہو

## سیٹ اپ (ایک ہی کمانڈ)
اس فولڈر کے اندر:

- Windows: `setup.bat` پر ڈبل کلک کریں
- macOS / Linux: `bash setup.sh`

یہ اسکرپٹ خود `map_overlay` پروجیکٹ بناتا ہے، `lib/main.dart` کاپی کرتا ہے، پیکجز شامل کرتا ہے اور Internet/Location permissions لگا دیتا ہے۔

## چلانا
```
cd map_overlay
flutter run
```

## APK بنانا
```
flutter build apk --release
```
فائل یہاں ملے گی: `build/app/outputs/flutter-apk/app-release.apk`

## استعمال
1. **Choose file** دبا کر PDF یا JPG منتخب کریں۔
2. نقشے پر تصویر کے اوپر بائیں کونے والی جگہ پر ٹیپ کریں۔
3. تصویر کے دائیں کنارے والی جگہ پر دوسرا ٹیپ کریں۔ اونچائی خود نکل آتی ہے۔
4. Rotation اور Opacity سے تصویر کو نقشے کے ساتھ ملائیں۔
5. **Save KMZ** دبائیں، Google Earth میں overlay کھل جائے گا۔
6. غلط جگہ لگ جائے تو نقشے پر نیا ٹیپ کریں یا **Reset** دبائیں۔

## نوٹس
- KMZ ایک وقت میں PDF کا ایک صفحہ لیتا ہے۔ دوسرے صفحے کے لیے صفحہ بدل کر دوبارہ Save KMZ کریں۔
- نقشہ OpenStreetMap کا ہے۔ عوامی ریلیز یا بہت زیادہ استعمال کے لیے اپنا tile provider استعمال کریں۔
- پیکجز کے نئے ورژن میں کبھی کبھار API نام بدل جاتے ہیں (مثلاً `RotatedOverlayImage` یا `ArchiveFile`)۔ error آئے تو اس کا متن بھیج دیں۔

## GitHub پر push کر کے APK خود بنوانا
اگر آپ کے کمپیوٹر پر Flutter نہیں ہے تو GitHub Actions APK بنا دے گا۔ اس کی فائل `.github/workflows/build-apk.yml` پیکج میں موجود ہے۔

1. GitHub پر نئی repository بنائیں۔
2. اس فولڈر کے اندر یہ کمانڈز چلائیں:
```
git init
git add .
git commit -m "Map Overlay app"
git branch -M main
git remote add origin https://github.com/USERNAME/REPO.git
git push -u origin main
```
3. GitHub میں **Actions** ٹیب کھولیں، **Build Android APK** چلتا نظر آئے گا (تقریباً 5 سے 10 منٹ)۔
4. مکمل ہونے پر اسی رن کے صفحے کے آخر میں **Artifacts** سے `map-overlay-apk` ڈاؤنلوڈ کریں، اس کے اندر `app-release.apk` ہے۔
5. APK فون میں انسٹال کریں (Unknown sources کی اجازت دینی پڑے گی)۔

ہر بار `main` برانچ پر push کرنے سے نیا APK بنتا ہے۔ Actions ٹیب سے **Run workflow** دبا کر ہاتھ سے بھی چلا سکتے ہیں۔
