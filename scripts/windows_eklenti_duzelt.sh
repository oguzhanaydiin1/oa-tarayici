#!/usr/bin/env bash
# flutter_inappwebview_windows düzeltmeleri (flutter pub get'ten sonra çalıştırılır).
#
# Fare tekerleği: Flutter bir tekerlek tıkını (Windows: 120 birim) 60 piksel olarak verir; eklenti
# bunu 6 ile çarpıp 360 birim (3 tık) olarak web motoruna gönderiyordu, sayfa 3 kat hızlı kayıyordu.
# 2 ile çarpınca bir tık yine bir tık olur ve Windows'taki "bir seferde kaydırılacak satır" ayarı geçerli olur.
set -euo pipefail

f=windows/flutter/ephemeral/.plugin_symlinks/flutter_inappwebview_windows/windows/in_app_webview/in_app_webview.cpp
if [[ ! -f "$f" ]]; then
  echo "::warning title=eklenti::$f bulunamadı, tekerlek düzeltmesi uygulanmadı"
  exit 0
fi
if grep -q 'kScrollMultiplier = 6' "$f"; then
  sed -i --follow-symlinks 's/kScrollMultiplier = 6;/kScrollMultiplier = 2;/' "$f"
  echo "Fare tekerleği hızı düzeltildi"
else
  echo "::warning title=eklenti::kScrollMultiplier bulunamadı (eklenti sürümü değişmiş olabilir)"
fi

# İzin isteği: Dart tarafı cevap veremezse (ör. WebView2'nin yeni bir izin türünü eklenti tanımıyor,
# ya da sekme kapanmış) cevap boş gelir; eklenti boşu kontrol etmeden okuyup uygulamayı çökertiyordu
# (çökme kaydı: flutter_inappwebview_windows_plugin.dll, 0xc0000005). Boşsa izin reddedilir.
d=windows/flutter/ephemeral/.plugin_symlinks/flutter_inappwebview_windows/windows/in_app_webview/webview_channel_delegate.cpp
old='return std::make_shared<PermissionResponse>(std::get<flutter::EncodableMap>(*value));'
if [[ -f "$d" ]] && grep -qF "$old" "$d"; then
  perl -0pi -e 's/return std::make_shared<PermissionResponse>\(std::get<flutter::EncodableMap>\(\*value\)\);/return (value == nullptr || !std::holds_alternative<flutter::EncodableMap>(*value)) ? std::make_shared<PermissionResponse>(std::nullopt, std::nullopt) : std::make_shared<PermissionResponse>(std::get<flutter::EncodableMap>(*value));/' "$d"
  echo "İzin isteği çökmesi düzeltildi"
else
  echo "::warning title=eklenti::İzin isteği düzeltmesi uygulanamadı ($d)"
fi
