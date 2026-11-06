import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

// Touchpad ile kaydırma (Windows). Touchpad iki parmak hareketini küçük adımlarla verir; bunlar her
// karede bir toplanır ve sayfada parmağın altındaki kaydırılabilir alana piksel piksel uygulanır.
// Parmak kalkınca hareket hızla orantılı biçimde yavaşlayarak devam eder (dokunmatik ekrandaki gibi).
// Sayfanın kendi kaydırma kodu varsa (haritalar, tablolar) önce ona bir tekerlek olayı gönderilir.

UserScript touchpadScript() => UserScript(
      groupName: 'oa-touchpad',
      injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
      forMainFrameOnly: false,
      source: r'''
(function(){
  if (window.__oaPan) return;
  function scrollable(e, vertical, d){
    var s = getComputedStyle(e), o = vertical ? s.overflowY : s.overflowX;
    if (o !== 'auto' && o !== 'scroll' && o !== 'overlay') return false;
    if (vertical) {
      if (e.scrollHeight <= e.clientHeight + 1) return false;
      return d < 0 ? e.scrollTop > 0 : e.scrollTop + e.clientHeight < e.scrollHeight - 1;
    }
    if (e.scrollWidth <= e.clientWidth + 1) return false;
    return d < 0 ? e.scrollLeft > 0 : e.scrollLeft + e.clientWidth < e.scrollWidth - 1;
  }
  window.__oaPan = function(dx, dy, x, y){
    var el = document.elementFromPoint(x, y) || document.body;
    // Aynı siteden bir çerçevenin üstündeyse onun içinde kaydır
    if (el && el.tagName === 'IFRAME') {
      try { var r = el.getBoundingClientRect(); if (el.contentWindow.__oaPan) { el.contentWindow.__oaPan(dx, dy, x - r.left, y - r.top); return; } } catch (e) {}
    }
    // Sayfanın kendi tekerlek kodu (harita, kaydırmalı liste) isterse onu kullansın
    try {
      var w = new WheelEvent('wheel', { deltaX: dx, deltaY: dy, deltaMode: 0, clientX: x, clientY: y, bubbles: true, cancelable: true, composed: true });
      if (el && !el.dispatchEvent(w)) return;
    } catch (e) {}
    var vertical = Math.abs(dy) >= Math.abs(dx), d = vertical ? dy : dx;
    for (var e = el; e && e !== document.body && e !== document.documentElement; e = e.parentElement || (e.getRootNode && e.getRootNode().host)) {
      if (scrollable(e, vertical, d)) { e.scrollBy({ left: dx, top: dy, behavior: 'instant' }); return; }
    }
    window.scrollBy({ left: dx, top: dy, behavior: 'instant' });
  };
})();
''',
    );

class TouchpadScroll extends StatefulWidget {
  const TouchpadScroll({super.key, required this.controller, required this.child});

  final InAppWebViewController? Function() controller;
  final Widget child;

  @override
  State<TouchpadScroll> createState() => _TouchpadScrollState();
}

class _TouchpadScrollState extends State<TouchpadScroll> {
  double _dx = 0, _dy = 0;
  Offset _at = Offset.zero;
  bool _queued = false;
  final List<(int, Offset)> _recent = [];
  Timer? _fling;

  @override
  void dispose() {
    _fling?.cancel();
    super.dispose();
  }

  /// Bir karede biriken hareket sayfaya tek seferde gider.
  void _flush() {
    _queued = false;
    final dx = _dx, dy = _dy;
    _dx = 0;
    _dy = 0;
    if (dx.abs() < 0.05 && dy.abs() < 0.05) return;
    final c = widget.controller();
    if (c == null) return;
    // Parmaklar yukarı → sayfa aşağı kayar (Windows'un touchpad yönüyle aynı)
    c.evaluateJavascript(
        source: 'window.__oaPan&&window.__oaPan(${(-dx).toStringAsFixed(2)},${(-dy).toStringAsFixed(2)},'
            '${_at.dx.toStringAsFixed(0)},${_at.dy.toStringAsFixed(0)})');
  }

  void _push(Offset d) {
    _dx += d.dx;
    _dy += d.dy;
    if (_queued) return;
    _queued = true;
    SchedulerBinding.instance.scheduleFrameCallback((_) => _flush());
    SchedulerBinding.instance.scheduleFrame();
  }

  void _start(PointerPanZoomStartEvent e) {
    _fling?.cancel();
    _recent.clear();
    _at = e.localPosition;
  }

  void _update(PointerPanZoomUpdateEvent e) {
    final now = DateTime.now().millisecondsSinceEpoch;
    _recent.add((now, e.panDelta));
    _recent.removeWhere((s) => now - s.$1 > 100);
    _push(e.panDelta);
  }

  void _end(PointerPanZoomEndEvent e) {
    final now = DateTime.now().millisecondsSinceEpoch;
    _recent.removeWhere((s) => now - s.$1 > 80);
    if (_recent.length < 2) return;
    final span = (now - _recent.first.$1).clamp(16, 100);
    var v = _recent.fold<Offset>(Offset.zero, (a, s) => a + s.$2) / span.toDouble(); // px/ms
    if (v.distance < 0.25) return;
    if (v.distance > 8) v = v / v.distance * 8;
    _fling = Timer.periodic(const Duration(milliseconds: 16), (t) {
      _push(v * 16);
      v = v * 0.95;
      if (v.distance < 0.02) t.cancel();
    });
  }

  @override
  Widget build(BuildContext context) => Listener(
        onPointerPanZoomStart: _start,
        onPointerPanZoomUpdate: _update,
        onPointerPanZoomEnd: _end,
        // Fareyle dokunulunca kayma durur
        onPointerDown: (_) => _fling?.cancel(),
        onPointerSignal: (_) => _fling?.cancel(),
        child: widget.child,
      );
}
