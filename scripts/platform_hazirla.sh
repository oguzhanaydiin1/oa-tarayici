#!/usr/bin/env bash
# Windows ve Android klasörlerini üretir ve OA Tarayıcı ayarlarını uygular.
# Kullanım (proje kökünde): bash scripts/platform_hazirla.sh windows,android
set -euo pipefail

PLATFORMS="${1:-windows,android}"

flutter create --platforms="$PLATFORMS" --org dev.oalabs --project-name oa_tarayici .
# flutter create varsayılan bir test dosyası ekler; bizim uygulamamıza uymuyor.
rm -f test/widget_test.dart

if [[ -f windows/runner/main.cpp ]]; then
  # Pencere başlığı: "OA Tarayıcı" (ı harfi ı olarak yazılır, derleyici kodlamasından bağımsız).
  sed -i 's/L"oa_tarayici"/L"OA Taray\\u0131c\\u0131"/' windows/runner/main.cpp
  # Açılış boyutu
  sed -i 's/Win32Window::Size size(1280, 720);/Win32Window::Size size(1360, 860);/' windows/runner/main.cpp
fi

if [[ -f windows/runner/Runner.rc ]]; then
  sed -i 's/VALUE "CompanyName", "dev.oalabs"/VALUE "CompanyName", "OA Labs"/' windows/runner/Runner.rc
  sed -i 's/VALUE "FileDescription", "oa_tarayici"/VALUE "FileDescription", "OA Tarayici"/' windows/runner/Runner.rc
  sed -i 's/VALUE "ProductName", "oa_tarayici"/VALUE "ProductName", "OA Tarayici"/' windows/runner/Runner.rc
fi

MANIFEST=android/app/src/main/AndroidManifest.xml
if [[ -f "$MANIFEST" ]]; then
  # İnternet izni (yoksa uygulama hiçbir sayfayı açamaz)
  if ! grep -q 'android.permission.INTERNET' "$MANIFEST"; then
    sed -i '0,/<application/s||<uses-permission android:name="android.permission.INTERNET"/>\n    <application|' "$MANIFEST"
  fi
  # Kamera (QR kod okuma). İzin, QR ekranı ilk açıldığında sorulur.
  if ! grep -q 'android.permission.CAMERA' "$MANIFEST"; then
    sed -i '0,/<application/s||<uses-permission android:name="android.permission.CAMERA"/>\n    <uses-feature android:name="android.hardware.camera" android:required="false"/>\n    <application|' "$MANIFEST"
  fi
  # Yayın sürümünde Android'in küçültme aracı (R8) QR okumanın kullandığı ML Kit sınıflarını
  # silmesin. Flutter, app/proguard-rules.pro dosyasını kendiliğinden kullanır.
  cat > android/app/proguard-rules.pro <<'RULES'
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_barcode.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_common.** { *; }
-dontwarn com.google.mlkit.**
RULES
  # Uygulama adı ve http:// sitelerine izin
  sed -i 's/android:label="oa_tarayici"/android:label="OA Tarayıcı"/' "$MANIFEST"
  if ! grep -q 'usesCleartextTraffic' "$MANIFEST"; then
    sed -i '0,/android:label="OA Tarayıcı"/s||android:label="OA Tarayıcı"\n        android:usesCleartextTraffic="true"|' "$MANIFEST"
  fi
fi

echo "Platform ayarları uygulandı: $PLATFORMS"
