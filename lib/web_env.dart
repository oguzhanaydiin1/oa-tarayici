import 'dart:io' show Platform;

import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// Windows'ta bütün web görünümlerinin paylaştığı Edge (WebView2) ortamı.
///
/// Edge varsayılan olarak, kullanıcı sayfaya dokunmadan ses başlatılmasına izin vermiyor
/// ("NotAllowedError: play() failed because the user didn't interact with the document first").
/// Radyo çalmak için bu kural kapatılır. Edge aynı veri klasörünü kullanan tüm görünümlerin
/// aynı ayarla açılmasını istediği için sekmeler, radyo ve çerezler bu ortamı birlikte kullanır.
WebViewEnvironment? oaWebEnv;

Future<void> initWebEnv() async {
  if (!Platform.isWindows) return;
  try {
    oaWebEnv = await WebViewEnvironment.create(
      settings: WebViewEnvironmentSettings(
        additionalBrowserArguments: '--autoplay-policy=no-user-gesture-required',
      ),
    );
  } catch (_) {
    oaWebEnv = null; // olmazsa varsayılan ortamla devam
  }
}

CookieManager oaCookies() => CookieManager.instance(webViewEnvironment: oaWebEnv);
