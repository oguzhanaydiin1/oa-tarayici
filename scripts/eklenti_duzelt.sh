#!/usr/bin/env bash
# flutter_inappwebview_android, yeni Android Gradle eklentisinin artık kabul etmediği
# 'proguard-android.txt' dosyasını kullanıyor. Paket güncellenene kadar pub önbelleğinde düzeltilir.
set -euo pipefail
CACHE="${PUB_CACHE:-$HOME/.pub-cache}"
found=0
for f in "$CACHE"/hosted/pub.dev/flutter_inappwebview_android-*/android/build.gradle; do
  [[ -f "$f" ]] || continue
  sed -i "s/proguard-android.txt/proguard-android-optimize.txt/g" "$f"
  echo "Düzeltildi: $f"; found=1
done
[[ $found -eq 1 ]] || echo "flutter_inappwebview_android bulunamadı (düzeltme gerekmedi)"

# Bazı eklentiler (ör. file_picker 8) eski bir Android SDK ile derleniyor; yeni Flutter
# bağımlılıkları en az 36 istiyor. Eklentilerin derleme SDK'sını 36'ya çıkar (davranışı değiştirmez).
for f in "$CACHE"/hosted/pub.dev/*/android/build.gradle "$CACHE"/hosted/pub.dev/*/android/build.gradle.kts; do
  [[ -f "$f" ]] || continue
  if grep -qE 'compileSdk(Version)?\s*(=\s*)?(2[0-9]|3[0-5])\b' "$f"; then
    sed -i -E 's/(compileSdk(Version)?\s*(=\s*)?)(2[0-9]|3[0-5])\b/\136/' "$f"
    echo "compileSdk 36: $f"
  fi
done
