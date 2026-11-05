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

# Geliştirici araçları uyarısı: eklenti her sayfada konsol mesajlarını yakalamak için DevTools'un
# "Runtime" bölümünü açıyordu (Runtime.enable). TV+ gibi canlı yayın siteleri bunu "geliştirici araçları
# açık" diye algılayıp yayını durduruyordu. Uygulama konsol mesajlarını kullanmıyor; Runtime.evaluate
# (JavaScript çalıştırma) bu açılmadan da çalışır. Çağrı Runtime.disable'a çevrilir.
if grep -q 'L"Runtime.enable"' "$f"; then
  sed -i --follow-symlinks 's/L"Runtime.enable"/L"Runtime.disable"/' "$f"
  echo "DevTools Runtime.enable kapatıldı"
else
  echo "::warning title=eklenti::Runtime.enable bulunamadı (eklenti sürümü değişmiş olabilir)"
fi

# Korumalı video sekmenin içinde: InAppBrowser'ın "CHILD" penceresi başlık çubuksuz, kenarsız ve saydamlık
# katmanı olmadan (katmanlı pencerede korumalı video gösterilmeyebilir) uygulamanın içine yerleşir.
# Ayrı pencere de saydam değilse katmansız açılır.
b=windows/flutter/ephemeral/.plugin_symlinks/flutter_inappwebview_windows/windows/in_app_browser/in_app_browser.cpp
if [[ -f "$b" ]] && grep -qF '(WS_CHILDWINDOW | WS_OVERLAPPEDWINDOW)' "$b" && grep -qF 'WS_EX_LAYERED,            // Optional window styles.' "$b"; then
  perl -0pi -e 's/\(WS_CHILDWINDOW \| WS_OVERLAPPEDWINDOW\)/(WS_CHILD | WS_CLIPSIBLINGS | WS_CLIPCHILDREN)/' "$b"
  perl -0pi -e 's/WS_EX_LAYERED,            \/\/ Optional window styles\./(settings->windowType == InAppBrowserWindowType::window \&\& settings->windowAlphaValue < 1.0) ? WS_EX_LAYERED : 0,/' "$b"
  perl -0pi -e 's/(    SetLayeredWindowAttributes\(m_hWnd, 0, \(BYTE\)\(255 \* settings->windowAlphaValue\), LWA_ALPHA\);\n)/    if (settings->windowType == InAppBrowserWindowType::window) {\n      if (settings->windowAlphaValue < 1.0) {\n  $1      }\n    } else {\n      SetWindowLongPtr(parentWindow, GWL_STYLE, GetWindowLongPtr(parentWindow, GWL_STYLE) | WS_CLIPCHILDREN);\n      SetWindowPos(m_hWnd, HWND_TOP, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);\n    }\n/' "$b"
  grep -q 'WS_CLIPSIBLINGS | WS_CLIPCHILDREN' "$b" && grep -q 'HWND_TOP' "$b" && echo "Gömülü pencere düzeltmesi uygulandı" || echo "::warning title=eklenti::Gömülü pencere düzeltmesi eksik uygulandı"
else
  echo "::warning title=eklenti::Gömülü pencere düzeltmesi uygulanamadı ($b)"
fi
