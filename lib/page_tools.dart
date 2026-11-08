// Sayfanın içinde çalışan küçük yardımcılar: sayfada bul, videoyu küçük pencerede izleme,
// şifre yakalama ve doldurma. Hepsi web görünümüne JavaScript olarak verilir.

/// Sayfada bul: eşleşmeleri işaretler, sayıyı döndürür; `__oaFind.go(±1)` sıradakine gider.
const String kFindJs = r'''
(function(){
  if (window.__oaFind) return;
  var marks = [], cur = -1;
  function clear(){
    for (var i = 0; i < marks.length; i++) {
      var m = marks[i], p = m.parentNode;
      if (!p) continue;
      p.replaceChild(document.createTextNode(m.textContent), m);
      p.normalize();
    }
    marks = []; cur = -1;
  }
  function paint(m, on){ m.style.background = on ? '#F2A541' : '#F7BF6E'; m.style.color = '#14110A'; m.style.borderRadius = '2px'; }
  function go(d){
    if (!marks.length) return 0;
    if (cur >= 0) paint(marks[cur], false);
    cur = (cur + d + marks.length) % marks.length;
    paint(marks[cur], true);
    try { marks[cur].scrollIntoView({ block: 'center', inline: 'nearest' }); } catch (e) {}
    return cur + 1;
  }
  function find(q){
    clear();
    if (!q || !document.body) return 0;
    var lq = q.toLocaleLowerCase('tr');
    var walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT, { acceptNode: function(n){
      var p = n.parentNode;
      if (!p) return NodeFilter.FILTER_REJECT;
      var t = p.nodeName;
      if (t === 'SCRIPT' || t === 'STYLE' || t === 'NOSCRIPT' || t === 'TEXTAREA' || t === 'OPTION') return NodeFilter.FILTER_REJECT;
      if (!n.nodeValue || n.nodeValue.toLocaleLowerCase('tr').indexOf(lq) < 0) return NodeFilter.FILTER_REJECT;
      return NodeFilter.FILTER_ACCEPT;
    }});
    var nodes = [];
    while (walker.nextNode()) nodes.push(walker.currentNode);
    for (var i = 0; i < nodes.length && marks.length < 2000; i++) {
      var n = nodes[i], s = n.nodeValue, ls = s.toLocaleLowerCase('tr');
      var frag = document.createDocumentFragment(), last = 0, pos;
      while ((pos = ls.indexOf(lq, last)) >= 0) {
        frag.appendChild(document.createTextNode(s.slice(last, pos)));
        var m = document.createElement('mark');
        m.textContent = s.slice(pos, pos + q.length);
        paint(m, false);
        frag.appendChild(m);
        marks.push(m);
        last = pos + q.length;
      }
      frag.appendChild(document.createTextNode(s.slice(last)));
      n.parentNode.replaceChild(frag, n);
    }
    if (marks.length) go(1);
    return marks.length;
  }
  window.__oaFind = { find: find, go: go, clear: clear };
})();
''';

/// Sayfadaki en büyük (tercihen çalan) videoyu tüm görünümü kaplayacak şekilde büyütür.
/// Videonun [genişlik, yükseklik] değerini, video yoksa null döndürür.
const String kVideoMiniJs = r'''
(function(){
  var vs = [].slice.call(document.querySelectorAll('video'));
  var best = null, score = 0;
  vs.forEach(function(v){
    var r = v.getBoundingClientRect();
    var a = Math.max(r.width * r.height, 1);
    if (!v.paused) a *= 4;
    if (a > score) { score = a; best = v; }
  });
  if (!best) return null;
  best.setAttribute('data-oa-mini', '1');
  // Videoyu saran kutular (YouTube oynatıcısı gibi) videonun pencereyi kaplamasını engellemesin
  for (var a = best.parentElement; a && a !== document.documentElement; a = a.parentElement) a.setAttribute('data-oa-mini-a', '1');
  var st = document.getElementById('__oamini');
  if (!st) { st = document.createElement('style'); st.id = '__oamini'; document.documentElement.appendChild(st); }
  st.textContent = 'video[data-oa-mini]{position:fixed!important;left:0!important;top:0!important;right:auto!important;bottom:auto!important;' +
    'width:100vw!important;height:100vh!important;max-width:none!important;max-height:none!important;min-width:0!important;' +
    'z-index:2147483647!important;background:#000!important;object-fit:contain!important;transform:none!important;margin:0!important;' +
    'visibility:visible!important;opacity:1!important}html,body{overflow:hidden!important}' +
    '[data-oa-mini-a]{transform:none!important;filter:none!important;contain:none!important;will-change:auto!important;z-index:2147483647!important;clip-path:none!important}';
  if (best.paused) { try { best.play(); } catch (e) {} }
  return [best.videoWidth || 16, best.videoHeight || 9];
})()
''';

const String kVideoMiniExitJs = r'''
(function(){
  var st = document.getElementById('__oamini'); if (st) st.remove();
  [].slice.call(document.querySelectorAll('video[data-oa-mini]')).forEach(function(v){ v.removeAttribute('data-oa-mini'); });
  [].slice.call(document.querySelectorAll('[data-oa-mini-a]')).forEach(function(v){ v.removeAttribute('data-oa-mini-a'); });
})();
''';

/// Giriş formları gönderilirken kullanıcı adı ve şifreyi uygulamaya bildirir (kaydetmeyi sormak için).
const String kPasswordCaptureJs = r'''
(function(){
  if (window.__oaPw) return; window.__oaPw = 1;
  var lastSent = '';
  function userFor(p){
    var ins = [].slice.call((p.form || document).querySelectorAll('input'));
    var idx = ins.indexOf(p);
    for (var j = idx - 1; j >= 0; j--) {
      var t = (ins[j].type || 'text').toLowerCase();
      if ((t === 'text' || t === 'email' || t === 'tel') && ins[j].value) return ins[j].value;
    }
    return '';
  }
  function grab(root){
    var ps = (root && root.querySelectorAll ? root : document).querySelectorAll('input[type=password]');
    var p = null;
    for (var i = 0; i < ps.length; i++) { if (ps[i].value) { p = ps[i]; break; } }
    if (!p) return;
    var u = userFor(p), key = u + '\u0000' + p.value;
    if (key === lastSent) return;
    lastSent = key;
    try { window.flutter_inappwebview.callHandler('oaPassword', u, p.value); } catch (e) {}
  }
  document.addEventListener('submit', function(e){ grab(e.target); }, true);
  document.addEventListener('click', function(e){
    var b = e.target && e.target.closest ? e.target.closest('button,input[type=submit],[role=button]') : null;
    if (!b) return;
    var f = b.form || (b.closest ? b.closest('form') : null);
    setTimeout(function(){ grab(f); }, 0);
  }, true);
  document.addEventListener('keydown', function(e){
    if (e.key === 'Enter' && e.target && e.target.type === 'password') grab(e.target.form);
  }, true);
})();
''';

/// Kayıtlı kullanıcı adı ve şifreyi sayfadaki giriş formuna yazar. Doldurduysa true döner.
String passwordFillJs(String user, String pass) => '''
(function(u, p){
  var ps = document.querySelectorAll('input[type=password]');
  if (!ps.length) return false;
  var pw = ps[0];
  function set(el, v){
    var d = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value');
    d.set.call(el, v);
    el.dispatchEvent(new Event('input', { bubbles: true }));
    el.dispatchEvent(new Event('change', { bubbles: true }));
  }
  var ins = [].slice.call((pw.form || document).querySelectorAll('input'));
  var idx = ins.indexOf(pw), ue = null;
  for (var j = idx - 1; j >= 0; j--) {
    var t = (ins[j].type || 'text').toLowerCase();
    if (t === 'text' || t === 'email' || t === 'tel') { ue = ins[j]; break; }
  }
  if (pw.value) return false;
  if (ue && !ue.value && u) set(ue, u);
  set(pw, p);
  return true;
})(${_js(user)}, ${_js(pass)})
''';

String _js(String s) {
  final b = StringBuffer('"');
  for (final r in s.runes) {
    if (r == 0x22) {
      b.write(r'\"');
    } else if (r == 0x5C) {
      b.write(r'\\');
    } else if (r < 0x20 || r == 0x2028 || r == 0x2029 || r == 0x3C) {
      b.write('\\u${r.toRadixString(16).padLeft(4, '0')}');
    } else {
      b.writeCharCode(r);
    }
  }
  b.write('"');
  return b.toString();
}
