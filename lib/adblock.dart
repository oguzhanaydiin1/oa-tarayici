import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// Reklam ve izleyici engelleme.
///
/// İki katman:
///  1. Ağ engelleme: listedeki reklam/izleyici alan adlarına giden istekler hiç yapılmaz.
///     Android'de web motorunun kendi içerik engelleyicisi (hızlı, yerel) kullanılır;
///     Windows'ta her istek [shouldBlock] ile kontrol edilir.
///  2. Görünür reklam gizleme: sayfaya eklenen küçük bir stil, bilinen reklam kutularını gizler
///     (iki platformda da).
///
/// Liste bilinçli olarak kısa ve elle seçilmiş: siteleri bozmadan en yaygın reklam ağlarını
/// ve izleyicileri kapsar. İleride EasyList gibi büyük listeler indirilebilir.
class AdBlock {
  AdBlock._();

  static const domains = <String>[
    // Google reklam ve ölçüm
    'doubleclick.net', 'googlesyndication.com', 'googleadservices.com',
    'google-analytics.com', 'googletagmanager.com', 'googletagservices.com',
    'adservice.google.com', 'adservice.google.com.tr', 'app-measurement.com',
    // Büyük reklam ağları ve borsalar
    'amazon-adsystem.com', 'adnxs.com', 'criteo.com', 'criteo.net', 'taboola.com',
    'outbrain.com', 'rubiconproject.com', 'pubmatic.com', 'openx.net', 'casalemedia.com',
    'smartadserver.com', 'adsrvr.org', 'adform.net', 'adroll.com', 'teads.tv',
    'sharethrough.com', '33across.com', 'media.net', 'mgid.com', 'revcontent.com',
    'yieldmo.com', 'triplelift.com', 'sovrn.com', 'lijit.com', 'contextweb.com',
    'indexww.com', 'bidswitch.net', 'districtm.io', 'admixer.net', 'adtelligent.com',
    'yahoo-adserver.com', 'advertising.com', 'zedo.com', 'adition.com', 'adhese.com',
    'improvedigital.com', 'seedtag.com', 'richaudience.com', 'onetag-sys.com',
    // Açılır pencere ve rahatsız edici reklamlar
    'popads.net', 'popcash.net', 'propellerads.com', 'adcash.com', 'exoclick.com',
    'juicyads.com', 'trafficjunky.net', 'hilltopads.net', 'adsterra.com', 'clickadu.com',
    // Türkiye'de yaygın reklam ve ölçüm ağları
    'admatic.com.tr', 'adhood.com', 'reklamstore.com', 'gemius.pl', 'hit.gemius.pl',
    'tr.hit.gemius.pl', 'effectivemeasure.net', 'mc.yandex.ru', 'mc.yandex.com.tr',
    'mc.yandex.com', 'an.yandex.ru', 'adfox.ru', 'yandexadexchange.net',
    // İzleyiciler ve analiz
    'scorecardresearch.com', 'quantserve.com', 'quantcount.com', 'bluekai.com',
    'demdex.net', 'everesttech.net', 'mathtag.com', 'moatads.com', 'adsafeprotected.com',
    'doubleverify.com', 'chartbeat.com', 'chartbeat.net', 'hotjar.com', 'hotjar.io',
    'clarity.ms', 'mixpanel.com', 'segment.io', 'segment.com', 'amplitude.com',
    'fullstory.com', 'mouseflow.com', 'crazyegg.com', 'luckyorange.com', 'newrelic.com',
    'nr-data.net', 'krxd.net', 'exelator.com', 'tapad.com', 'agkn.com', 'rlcdn.com',
    'adsymptotic.com', 'id5-sync.com', 'liadm.com', 'zeotap.com', 'permutive.com',
    // Sosyal ağ izleme pikselleri (giriş düğmelerini bozmamak için yalnız piksel alanları)
    'connect.facebook.net', 'pixel.facebook.com', 'analytics.tiktok.com',
    'ads-twitter.com', 'static.ads-twitter.com', 'ads.linkedin.com', 'px.ads.linkedin.com',
    'bat.bing.com', 'ct.pinterest.com', 'sc-static.net', 'tr.snapchat.com',
  ];

  static final Set<String> _set = domains.toSet();

  /// Adres listedeki bir alan adına (ya da alt alan adına) mı gidiyor?
  static bool isAdHost(String host) {
    var h = host.toLowerCase();
    while (true) {
      if (_set.contains(h)) return true;
      final i = h.indexOf('.');
      if (i < 0 || i == h.length - 1) return false;
      h = h.substring(i + 1);
    }
  }

  /// Bu sayfada engelleme kapalı mı? (kullanıcının "bu sitede kapat" listesi)
  static bool isAllowedSite(String pageHost, Set<String> allowedSites) {
    var h = pageHost.toLowerCase().replaceFirst(RegExp(r'^www\.'), '');
    while (h.contains('.')) {
      if (allowedSites.contains(h)) return true;
      h = h.substring(h.indexOf('.') + 1);
    }
    return false;
  }

  /// Windows: istek engellenmeli mi?
  static bool shouldBlock(Uri url, {required String pageHost, required Set<String> allowedSites}) {
    if (!url.scheme.startsWith('http')) return false;
    if (isAllowedSite(pageHost, allowedSites)) return false;
    if (url.host == pageHost) return false; // sitenin kendi istekleri
    return isAdHost(url.host);
  }

  /// Engellenen istek için boş cevap.
  static WebResourceResponse emptyResponse() => WebResourceResponse(
        contentType: 'text/plain',
        contentEncoding: 'utf-8',
        data: Uint8List(0),
        statusCode: 204,
        reasonPhrase: 'No Content',
      );

  static String _escape(String d) => d.replaceAll('.', r'\.');

  /// Android: web motorunun yerel içerik engelleyici kuralları.
  static List<ContentBlocker> contentBlockers(Set<String> allowedSites) {
    if (!Platform.isAndroid) return const [];
    final unless = [for (final s in allowedSites) '*$s'];
    // Tek bir düzenli ifade: ^https?://(alt.)*(alanadi1|alanadi2|...)[/:]
    final pattern =
        '^https?://([a-z0-9-]+\\.)*(${domains.map(_escape).join('|')})([/:?]|\$)';
    return [
      ContentBlocker(
        trigger: ContentBlockerTrigger(
          urlFilter: pattern,
          unlessDomain: unless,
        ),
        action: ContentBlockerAction(type: ContentBlockerActionType.BLOCK),
      ),
    ];
  }

  /// Bilinen reklam kutularını gizleyen stil (iki platformda da).
  static const cosmeticCss = '''
ins.adsbygoogle, .adsbygoogle, [id^="google_ads_"], [id^="div-gpt-ad"], [id^="gpt-ad"],
[data-ad-slot], [data-ad-unit], [data-google-query-id], iframe[src*="doubleclick.net"],
iframe[src*="googlesyndication"], iframe[id^="google_ads_iframe"], .trc_related_container,
[id^="taboola-"], .taboola, .OUTBRAIN, .ob-widget, [data-widget-id][class*="outbrain"],
.mgbox, [id^="mgid_"], .ad-slot, .ad-banner, .ad-container, .ad-wrapper, .adsbox,
.advertisement, .reklam, .reklam-alani, [class*="reklam-"], [id*="reklam-"],
[aria-label="Advertisement"], [aria-label="Reklam"] { display: none !important; }
''';

  static UserScript cosmeticScript(Set<String> allowedSites) => UserScript(
        groupName: 'oa-adblock',
        injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
        source: '''
(function(){
  try {
    if (window.__oaAdblock) return; window.__oaAdblock = true;
    var allowed = ${_jsList(allowedSites)};
    var h = location.hostname.replace(/^www\\./, '');
    while (h.indexOf('.') > 0) { if (allowed.indexOf(h) >= 0) return; h = h.slice(h.indexOf('.') + 1); }
    var css = ${_jsString(cosmeticCss)};
    var add = function(){
      var s = document.createElement('style'); s.id = 'oa-adblock'; s.textContent = css;
      (document.head || document.documentElement).appendChild(s);
    };
    if (document.documentElement) add(); else document.addEventListener('DOMContentLoaded', add);
    // Reklamı engellenen kutular sayfada boş beyaz alan bırakmasın: adı reklam olan, içi boş kutular gizlenir
    var adName = /(^|[\\s_-])(ad|ads|adv|advert|advertising|banner|reklam|dfp|gpt|sponsor|masthead-ad)([\\s_-]|\\d|\$)/i;
    function visibleMedia(el){
      var m = el.querySelectorAll('img,video,iframe,canvas,svg,picture');
      for (var i = 0; i < m.length; i++) { var r = m[i].getBoundingClientRect(); if (r.width > 20 && r.height > 20) return true; }
      return false;
    }
    function sweep(){
      try {
        var els = document.querySelectorAll('div[id],div[class],aside,section[class]');
        for (var i = 0; i < els.length && i < 4000; i++) {
          var e = els[i];
          if (e.__oaSeen) continue;
          var name = (e.id || '') + ' ' + (typeof e.className === 'string' ? e.className : '');
          if (!adName.test(name)) continue;
          var r = e.getBoundingClientRect();
          if (r.height < 40) continue;
          if ((e.innerText || '').replace(/reklam|advertisement|sponsorlu|ads?/gi, '').trim().length > 0) { e.__oaSeen = 1; continue; }
          if (visibleMedia(e)) continue;
          if (getComputedStyle(e).backgroundImage !== 'none') { e.__oaSeen = 1; continue; }
          e.style.setProperty('display', 'none', 'important');
          e.__oaSeen = 1;
        }
      } catch (x) {}
    }
    var t = null;
    var schedule = function(){ if (t) return; t = setTimeout(function(){ t = null; sweep(); }, 700); };
    document.addEventListener('DOMContentLoaded', function(){
      schedule();
      try { new MutationObserver(schedule).observe(document.documentElement, { childList: true, subtree: true }); } catch (x) {}
    });
    setTimeout(sweep, 3000); setTimeout(sweep, 8000);
  } catch (e) {}
})();
''',
      );

  static String _jsList(Set<String> items) => '[${items.map(_jsString).join(',')}]';

  static String _jsString(String s) =>
      "'${s.replaceAll('\\', r'\\').replaceAll("'", r"\'").replaceAll('\n', ' ')}'";
}
