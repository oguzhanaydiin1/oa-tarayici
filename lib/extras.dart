// Sayfa yardımcıları (2): çerez pencerelerini kapatma, sitelere karanlık mod, yakınlaştırma,
// ve Chrome / Edge / Firefox'tan içe aktarma.

import 'package:flutter_inappwebview/flutter_inappwebview.dart';

// ---------------------------------------------------------------- Çerez pencereleri

/// Sitelerdeki "çerezleri kabul et" pencerelerinde reddet / yalnız gerekli düğmesine basar;
/// bulamazsa birkaç saniye sonra pencereyi gizler ve sayfanın kaydırma kilidini açar.
UserScript cookieBannerScript(Set<String> allowedSites) => UserScript(
      groupName: 'oa-cerez',
      injectionTime: UserScriptInjectionTime.AT_DOCUMENT_END,
      forMainFrameOnly: true,
      source: '''
(function(){
  try {
    if (window.__oaCookie) return; window.__oaCookie = 1;
    var allowed = ${_jsList(allowedSites)};
    var h = location.hostname.replace(/^www\\./, '');
    for (var a = 0; a < allowed.length; a++) { if (h === allowed[a] || h.endsWith('.' + allowed[a])) return; }
    var sel = ['#onetrust-reject-all-handler', '#CybotCookiebotDialogBodyButtonDecline',
      '#CybotCookiebotDialogBodyLevelButtonLevelOptinDeclineAll', '#didomi-notice-disagree-button',
      '.didomi-continue-without-agreeing', 'button.fc-cta-do-not-consent',
      '.qc-cmp2-summary-buttons button[mode="secondary"]', '.cc-deny', '.cky-btn-reject', '#cookiescript_reject',
      '.osano-cm-denyAll', '[data-testid="uc-deny-all-button"]', '.iubenda-cs-reject-btn',
      '#tarteaucitronAllDenied2', '.cmplz-deny', '.cm-btn-danger', '#truste-consent-required'];
    var words = /^(t[üu]m[üu]n[üu] reddet|hepsini reddet|reddet|kabul etmiyorum|yaln[ıi]zca (gerekli|zorunlu)( (çerezler|olanlar)[ıi]?)?( (kabul et|izin ver))?|sadece (gerekli|zorunlu)( (çerezler|olanlar)[ıi]?)?( (kabul et|izin ver))?|zorunlu (çerezler|olanlar)|gerekli olanlar[ıi] kabul et|reject all|reject|decline( all)?|deny( all)?|only (necessary|essential)( cookies)?|necessary only|use necessary cookies only|continue without accepting|refuse all)\$/i;
    var hide = ['#onetrust-banner-sdk', '#onetrust-consent-sdk', '#CybotCookiebotDialog', '#didomi-host',
      '.fc-consent-root', '.qc-cmp2-container', '#usercentrics-root', '.cky-consent-container',
      '#cookiescript_injected', '.osano-cm-window', '.cc-window', '#cmpbox', '#cmpbox2', '.cmplz-cookiebanner',
      '#cookie-law-info-bar', '.cookie-notice-container', '#cookie-notice'];
    var done = false, timer = null;
    function txt(e) { return (e.innerText || e.textContent || e.value || '').replace(/\\s+/g, ' ').trim(); }
    function visible(e) { return !!(e.offsetWidth || e.offsetHeight || e.getClientRects().length); }
    function attempt() {
      if (done) return;
      for (var i = 0; i < sel.length; i++) {
        var b = document.querySelector(sel[i]);
        if (b && visible(b)) { b.click(); done = true; return; }
      }
      var cands = document.querySelectorAll('button,a[role=button],[role=button],input[type=button],input[type=submit]');
      for (var j = 0; j < cands.length; j++) {
        var c = cands[j], t = txt(c);
        if (!t || t.length > 48 || !words.test(t) || !visible(c)) continue;
        var p = c, ok = false;
        for (var k = 0; k < 10 && p; k++) {
          var pt = ((p.id || '') + ' ' + (typeof p.className === 'string' ? p.className : '') + ' ' +
            ((p.getAttribute && p.getAttribute('aria-label')) || '')).toLowerCase();
          if (/cookie|consent|gdpr|kvkk|çerez|cerez|cmp|privacy/.test(pt)) { ok = true; break; }
          p = p.parentElement;
        }
        if (!ok) {
          var box = c.closest('div,section,aside,dialog,form');
          for (var m = 0; m < 4 && box && !ok; m++) {
            if (/çerez|cookie|kvkk|kişisel veri/i.test(txt(box).slice(0, 800))) ok = true;
            box = box.parentElement;
          }
        }
        if (ok) { c.click(); done = true; return; }
      }
    }
    attempt();
    var obs = new MutationObserver(function () {
      if (done || timer) return;
      timer = setTimeout(function () { timer = null; attempt(); }, 250);
    });
    obs.observe(document.documentElement, { childList: true, subtree: true });
    setTimeout(function () {
      obs.disconnect();
      if (done) return;
      var css = document.createElement('style');
      css.textContent = hide.join(',') + '{display:none!important}';
      (document.head || document.documentElement).appendChild(css);
      var any = hide.some(function (s) { return document.querySelector(s); });
      if (any) {
        document.documentElement.style.setProperty('overflow', 'auto', 'important');
        if (document.body) document.body.style.setProperty('overflow', 'auto', 'important');
      }
    }, 6000);
  } catch (e) {}
})();
''',
    );

String _jsList(Iterable<String> items) =>
    '[${items.map((s) => '"${s.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"').join(',')}]';

// ---------------------------------------------------------------- Sitelere karanlık mod

/// Sayfayı koyu gösterir (renkleri ters çevirir, resim ve videoları olduğu gibi bırakır).
/// Sayfa zaten koyuysa dokunmaz. Sonuç: "on" | "off" | "zaten".
String darkModeJs(bool on) => '''
(function(on){
  var id = '__oadark', s = document.getElementById(id);
  if (!on) { if (s) s.remove(); return 'off'; }
  if (s) return 'on';
  function lum(c) {
    var m = (c || '').match(/[\\d.]+/g);
    if (!m || m.length < 3) return -1;
    if (m.length > 3 && +m[3] === 0) return -1;
    return (0.2126 * m[0] + 0.7152 * m[1] + 0.0722 * m[2]) / 255;
  }
  var b = document.body ? lum(getComputedStyle(document.body).backgroundColor) : -1;
  if (b < 0) b = lum(getComputedStyle(document.documentElement).backgroundColor);
  if (b < 0) b = 1;
  if (b < 0.3) return 'zaten';
  s = document.createElement('style'); s.id = id;
  s.textContent = 'html{filter:invert(1) hue-rotate(180deg)!important;background:#fff!important}' +
    'img,video,picture,canvas,iframe,embed,object,svg image,[style*="background-image"]{filter:invert(1) hue-rotate(180deg)!important}';
  (document.head || document.documentElement).appendChild(s);
  return 'on';
})($on)
''';

// ---------------------------------------------------------------- Yakınlaştırma

String zoomJs(int percent) => percent == 100
    ? "document.documentElement.style.zoom='';"
    : "document.documentElement.style.zoom='${(percent / 100).toStringAsFixed(2)}';";

// ---------------------------------------------------------------- İçe aktarma

String _unescape(String s) => s
    .replaceAll('&amp;', '&')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll('&#x27;', "'")
    .trim();

/// Chrome / Edge / Firefox'un dışa aktardığı yer imleri dosyası (Netscape HTML biçimi).
List<Map<String, String>> parseBookmarksHtml(String html) {
  final out = <Map<String, String>>[];
  final re = RegExp(r'''<a\s[^>]*?href\s*=\s*["']([^"']+)["'][^>]*>(.*?)</a>''', caseSensitive: false, dotAll: true);
  for (final m in re.allMatches(html)) {
    final url = _unescape(m.group(1)!);
    if (!url.startsWith('http')) continue;
    var title = _unescape(m.group(2)!.replaceAll(RegExp(r'<[^>]+>'), ''));
    if (title.isEmpty) title = Uri.tryParse(url)?.host ?? url;
    out.add({'title': title, 'url': url});
  }
  return out;
}

class ImportedLogin {
  const ImportedLogin(this.url, this.user, this.pass);
  final String url;
  final String user;
  final String pass;
}

/// Chrome / Edge (name,url,username,password,note) ve Firefox ("url","username","password",…) şifre dosyası.
List<ImportedLogin> parsePasswordsCsv(String csv) {
  final rows = _csvRows(csv.replaceFirst('﻿', ''));
  if (rows.isEmpty) return [];
  final head = rows.first.map((h) => h.trim().toLowerCase()).toList();
  int col(List<String> names) {
    for (final n in names) {
      final i = head.indexOf(n);
      if (i >= 0) return i;
    }
    return -1;
  }

  final iu = col(['url', 'origin', 'website', 'login_uri', 'web site']);
  final in_ = col(['username', 'login', 'user', 'login_username', 'kullanıcı adı']);
  final ip = col(['password', 'login_password', 'şifre']);
  if (iu < 0 || ip < 0) return [];
  final out = <ImportedLogin>[];
  for (final r in rows.skip(1)) {
    if (r.length <= iu || r.length <= ip) continue;
    final url = r[iu].trim();
    final pass = r[ip];
    if (!url.startsWith('http') || pass.isEmpty) continue;
    out.add(ImportedLogin(url, in_ >= 0 && r.length > in_ ? r[in_].trim() : '', pass));
  }
  return out;
}

List<List<String>> _csvRows(String s) {
  final rows = <List<String>>[];
  var row = <String>[];
  final cell = StringBuffer();
  var quoted = false;
  for (var i = 0; i < s.length; i++) {
    final ch = s[i];
    if (quoted) {
      if (ch == '"') {
        if (i + 1 < s.length && s[i + 1] == '"') {
          cell.write('"');
          i++;
        } else {
          quoted = false;
        }
      } else {
        cell.write(ch);
      }
    } else if (ch == '"') {
      quoted = true;
    } else if (ch == ',') {
      row.add(cell.toString());
      cell.clear();
    } else if (ch == '\n' || ch == '\r') {
      if (ch == '\r' && i + 1 < s.length && s[i + 1] == '\n') i++;
      row.add(cell.toString());
      cell.clear();
      if (row.any((c) => c.isNotEmpty)) rows.add(row);
      row = <String>[];
    } else {
      cell.write(ch);
    }
  }
  if (cell.isNotEmpty || row.isNotEmpty) {
    row.add(cell.toString());
    if (row.any((c) => c.isNotEmpty)) rows.add(row);
  }
  return rows;
}

// ---------------------------------------------------------------- Fare hareketleri (bilgisayar)

/// Sağ tuşa basılı tutup çekince: sola geri, sağa ileri, yukarı yenile, aşağı sekmeyi kapat.
/// Hareket olduysa sağ tık menüsü açılmaz.
UserScript mouseGestureScript() => UserScript(
      groupName: 'oa-hareket',
      injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
      forMainFrameOnly: true,
      source: r'''
(function(){
  if (window.__oaGest) return; window.__oaGest = 1;
  var sx = 0, sy = 0, down = false, moved = false, block = 0;
  addEventListener('mousedown', function(e){ if (e.button === 2) { down = true; moved = false; sx = e.clientX; sy = e.clientY; } }, true);
  addEventListener('mousemove', function(e){
    if (!down) return;
    if (Math.abs(e.clientX - sx) > 50 || Math.abs(e.clientY - sy) > 50) moved = true;
  }, true);
  addEventListener('mouseup', function(e){
    if (e.button !== 2 || !down) return;
    down = false;
    if (!moved) return;
    var dx = e.clientX - sx, dy = e.clientY - sy;
    var d = Math.abs(dx) > Math.abs(dy) ? (dx < 0 ? 'L' : 'R') : (dy < 0 ? 'U' : 'D');
    block = Date.now();
    try { window.flutter_inappwebview.callHandler('oaGesture', d); } catch (x) {}
  }, true);
  addEventListener('contextmenu', function(e){
    if (moved || Date.now() - block < 500) { e.preventDefault(); e.stopPropagation(); moved = false; }
  }, true);
})();
''',
    );

// ---------------------------------------------------------------- Pencere boyutu (bilgisayar)

/// Bazı siteler (canlı yayın, sınav) pencerenin dış boyutu ile sayfa alanı arasındaki farka bakıp
/// "geliştirici araçları açık" sanıyor. Bizde bu fark sekme şeridi, araç çubuğu ve kenar çubuğundan
/// geliyor. Sayfaya dış boyut, sayfa alanına yakın gösterilir.
UserScript windowSizeScript() => UserScript(
      groupName: 'oa-boyut',
      injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
      forMainFrameOnly: false,
      source: r'''
(function(){
  try {
    var d = function(n, f){ Object.defineProperty(window, n, { get: f, configurable: true }); };
    d('outerWidth', function(){ return window.innerWidth; });
    d('outerHeight', function(){ return window.innerHeight + 74; });
  } catch (e) {}
})();
''',
    );
