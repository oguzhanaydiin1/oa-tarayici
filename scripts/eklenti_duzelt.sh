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
