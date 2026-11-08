// OA Tarayıcı okuma modu. Readability.js'ten sonra sayfaya eklenir.
// window.__oaReader(opts) okuma görünümünü açar ya da kapatır; sonucu metin olarak döndürür:
//   "acik" | "kapali" | "yok" (sayfada okunacak yazı bulunamadı)
(function () {
  if (window.__oaReader) return;
  window.__oaReader = function (o) {
    var old = document.getElementById('oa-reader');
    if (old) {
      old.remove();
      document.documentElement.style.overflow = window.__oaReaderOverflow || '';
      return 'kapali';
    }
    var article;
    try {
      article = new Readability(document.cloneNode(true), { charThreshold: 300 }).parse();
    } catch (e) {
      article = null;
    }
    if (!article || !article.content || (article.textContent || '').trim().length < 300) return 'yok';

    var c = o || {};
    var host = document.createElement('div');
    host.id = 'oa-reader';
    host.setAttribute('style', 'position:fixed;inset:0;z-index:2147483647;overflow:auto;-webkit-overflow-scrolling:touch;');
    var root = host.attachShadow ? host.attachShadow({ mode: 'open' }) : host;
    var size = c.size || 19;
    root.innerHTML =
      '<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Bricolage+Grotesque:opsz,wght@12..96,800&family=DM+Sans:opsz,wght@9..40,400;9..40,600&display=swap">' +
      '<style>' +
      ':host,.wrap{all:initial}' +
      '.wrap{display:block;min-height:100%;background:' + c.bg + ';color:' + c.text + ';font:400 ' + size + 'px/1.7 "DM Sans","Segoe UI",system-ui,sans-serif;-webkit-font-smoothing:antialiased}' +
      '.bar{position:sticky;top:0;display:flex;align-items:center;gap:10px;padding:10px 16px;background:' + c.surface + ';border-bottom:1px solid ' + c.border + ';font-size:14px}' +
      '.bar b{flex:1;font-weight:600;color:' + c.muted + ';white-space:nowrap;overflow:hidden;text-overflow:ellipsis}' +
      '.bar button{all:unset;cursor:pointer;padding:6px 14px;border-radius:999px;border:1px solid ' + c.border + ';color:' + c.text + ';font-weight:600}' +
      'article{display:block;max-width:680px;margin:0 auto;padding:32px 20px 80px}' +
      'h1.t{font:800 clamp(28px,5vw,40px)/1.1 "Bricolage Grotesque","Segoe UI",sans-serif;letter-spacing:-.02em;margin:0 0 12px}' +
      '.by{color:' + c.muted + ';font-size:15px;margin:0 0 28px}' +
      'article p,article li{margin:0 0 1em}' +
      'article h2,article h3{font-family:"Bricolage Grotesque","Segoe UI",sans-serif;font-weight:800;line-height:1.2;margin:1.6em 0 .6em}' +
      'article a{color:' + c.accent + '}' +
      'article img,article video,article figure{max-width:100%;height:auto;border-radius:12px}' +
      'article figcaption{color:' + c.muted + ';font-size:14px}' +
      'article blockquote{margin:1em 0;padding:4px 0 4px 18px;border-left:3px solid ' + c.accent + ';color:' + c.muted + '}' +
      'article pre,article code{font-family:ui-monospace,Consolas,monospace;font-size:.85em;background:' + c.surface + ';border-radius:6px}' +
      'article pre{padding:12px;overflow:auto}' +
      'article table{border-collapse:collapse;display:block;overflow:auto}' +
      'article td,article th{border:1px solid ' + c.border + ';padding:6px 10px}' +
      '</style>' +
      '<div class="wrap"><div class="bar"><b></b><button type="button" data-a="-">A−</button><button type="button" data-a="+">A+</button><button type="button" data-a="x">Kapat</button></div>' +
      '<article><h1 class="t"></h1><p class="by"></p><div class="c"></div></article></div>';
    root.querySelector('.bar b').textContent = 'Okuma modu · ' + location.hostname.replace(/^www\./, '');
    root.querySelector('h1.t').textContent = article.title || document.title;
    var by = [article.byline, article.siteName].filter(Boolean).join(' · ');
    var minutes = Math.max(1, Math.round((article.textContent || '').split(/\s+/).length / 220));
    root.querySelector('.by').textContent = (by ? by + ' · ' : '') + minutes + ' dk okuma';
    root.querySelector('.c').innerHTML = article.content; // Readability içeriği temizler (script'ler çıkarılır)
    // Yazıya karışan küçük simgeler ve "bizi takip edin / abone ol" kutuları temizlenir
    (function (c) {
      var junk = /(google'?(da|\s*news)?\s*(takip|tercih)|bizi takip|takip edin|abone ol|bültenimize|whatsapp kanal|telegram kanal|follow us|subscribe|sign up for our newsletter|haberin devam[ıi]|reklam|advertisement)/i;
      c.querySelectorAll('img').forEach(function (im) {
        var w = parseInt(im.getAttribute('width') || '0', 10), h = parseInt(im.getAttribute('height') || '0', 10);
        var src = (im.getAttribute('src') || '') + ' ' + (im.getAttribute('alt') || '');
        if ((w && w < 80) || (h && h < 80) || /(icon|logo|sprite|avatar|badge|google[-_]?news|gnews|follow)/i.test(src)) {
          var p = im.closest('a,figure,p') || im; p.remove();
        } else {
          im.addEventListener('load', function () { if (im.naturalWidth && im.naturalWidth < 80) im.remove(); });
        }
      });
      c.querySelectorAll('p,div,li,span,a,h2,h3,h4').forEach(function (e) {
        var t = (e.textContent || '').trim();
        if (t.length && t.length < 90 && junk.test(t) && !e.querySelector('img')) e.remove();
      });
      c.querySelectorAll('p,div').forEach(function (e) { if (!(e.textContent || '').trim() && !e.querySelector('img,video,iframe,figure,picture')) e.remove(); });
    })(root.querySelector('.c'));
    var wrap = root.querySelector('.wrap');
    root.querySelector('.bar').addEventListener('click', function (e) {
      var a = e.target && e.target.getAttribute && e.target.getAttribute('data-a');
      if (a === 'x') {
        // Doğrudan kapat (sayfanın kendi kodu window.__oaReader'ı bozmuş olsa da çalışsın)
        try { host.parentNode && host.parentNode.removeChild(host); } catch (err) {}
        document.documentElement.style.overflow = window.__oaReaderOverflow || '';
        return;
      }
      if (a === '+' || a === '-') {
        size = Math.min(28, Math.max(14, size + (a === '+' ? 1 : -1)));
        wrap.style.fontSize = size + 'px';
        try { window.flutter_inappwebview.callHandler('oaReaderSize', size); } catch (err) {}
      }
    });
    window.__oaReaderOverflow = document.documentElement.style.overflow;
    document.documentElement.style.overflow = 'hidden';
    document.documentElement.appendChild(host);
    return 'acik';
  };
})();
