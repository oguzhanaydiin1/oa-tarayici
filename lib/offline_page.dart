import 'dart:convert';

import 'oa_theme.dart';

// Sayfa açılamayınca gösterilen OA sayfası. İnternet yoksa küçük bir oyun da var:
// OA işareti engellerin üstünden atlar (boşluk / yukarı ok / dokun).

String _hex(int argb) => '#${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

String offlinePageHtml({required String url, required String detail, required bool offline}) {
  final p = OAColors.palette;
  final bg = _hex(p.bg.toARGB32());
  final surface = _hex(p.surface.toARGB32());
  final border = _hex(p.border.toARGB32());
  final text = _hex(p.text.toARGB32());
  final muted = _hex(p.muted.toARGB32());
  final amber = _hex(p.amber.toARGB32());
  final ink = _hex(p.amberInk.toARGB32());
  final host = Uri.tryParse(url)?.host ?? url;
  final title = offline ? 'İnternet yok gibi' : 'Sayfa açılamadı';
  final sub = offline
      ? 'Bağlantın gelene kadar bir oyun? Boşluk tuşuna bas ya da ekrana dokun.'
      : '$host şu an yanıt vermiyor. Biraz sonra yeniden dene.';
  String esc(String s) => const HtmlEscape().convert(s);
  return '''<!doctype html><html lang="tr"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, user-scalable=no">
<title>${esc(title)}</title>
<style>
html,body{margin:0;height:100%;background:$bg;color:$text;font:16px/1.5 "DM Sans","Segoe UI",Roboto,system-ui,sans-serif;-webkit-user-select:none;user-select:none}
.w{max-width:720px;margin:0 auto;padding:48px 20px;box-sizing:border-box}
.k{display:inline-block;padding:4px 12px;border-radius:999px;background:$surface;border:1px solid $border;color:$muted;font-size:13px}
h1{font:800 clamp(30px,6vw,44px)/1.05 "Bricolage Grotesque","Segoe UI",sans-serif;letter-spacing:-.02em;margin:16px 0 8px}
p{color:$muted;margin:0 0 20px}
.btns{display:flex;gap:10px;flex-wrap:wrap;margin-bottom:28px}
button{all:unset;cursor:pointer;padding:10px 18px;border-radius:12px;font-weight:600;background:$surface;border:1px solid $border;color:$text}
button.p{background:$amber;color:$ink;border-color:$amber}
canvas{display:block;width:100%;height:220px;border-radius:18px;background:$surface;border:1px solid $border;touch-action:manipulation}
.s{display:flex;justify-content:space-between;color:$muted;font-size:13px;margin-top:8px}
.d{color:$muted;font-size:12px;margin-top:24px;word-break:break-all;opacity:.8}
</style></head><body><div class="w">
<span class="k">${esc(host)}</span>
<h1>${esc(title)}</h1>
<p>${esc(sub)}</p>
<div class="btns"><button class="p" id="r">Yeniden dene</button></div>
${offline ? '<canvas id="c" width="720" height="220"></canvas><div class="s"><span id="sc">Puan: 0</span><span id="hi"></span></div>' : ''}
<div class="d">${esc(detail)}</div>
</div>
<script>
document.getElementById('r').onclick=function(){try{window.flutter_inappwebview.callHandler('oaRetry');}catch(e){location.reload();}};
(function(){
var c=document.getElementById('c'); if(!c) return;
var x=c.getContext('2d'), W=720, H=220, G=180;
var best=0; try{best=+localStorage.getItem('oaOyun')||0;}catch(e){}
var y, vy, obs, t, score, speed, run=false, over=false;
function reset(){y=G;vy=0;obs=[];t=0;score=0;speed=6;over=false;}
function jump(){ if(over){reset();run=true;return;} if(!run){run=true;} if(y>=G){vy=-13;} }
addEventListener('keydown',function(e){ if(e.code==='Space'||e.code==='ArrowUp'){e.preventDefault();jump();} });
c.addEventListener('pointerdown',function(e){e.preventDefault();jump();});
function rr(px,py,w,h,r){x.beginPath();x.moveTo(px+r,py);x.arcTo(px+w,py,px+w,py+h,r);x.arcTo(px+w,py+h,px,py+h,r);x.arcTo(px,py+h,px,py,r);x.arcTo(px,py,px+w,py,r);x.closePath();}
function draw(){
  x.clearRect(0,0,W,H);
  x.strokeStyle='$border';x.lineWidth=2;x.beginPath();x.moveTo(0,G+34);x.lineTo(W,G+34);x.stroke();
  // OA işareti
  x.fillStyle='$amber';rr(60,y-34+34,34,34,9);x.fill();
  x.fillStyle='$ink';x.font='800 15px "Bricolage Grotesque","Segoe UI",sans-serif';x.textAlign='center';x.textBaseline='middle';x.fillText('OA',77,y+17);
  x.fillStyle='$muted';
  for(var i=0;i<obs.length;i++){var o=obs[i];rr(o.x,G+34-o.h,o.w,o.h,4);x.fill();}
  if(!run||over){x.fillStyle='$text';x.font='600 16px "DM Sans","Segoe UI",sans-serif';x.fillText(over?'Oyun bitti · yeniden başlamak için dokun':'Başlamak için boşluk tuşu ya da dokun',W/2,60);}
}
function step(){
  if(run&&!over){
    t++; vy+=0.75; y+=vy; if(y>G){y=G;vy=0;}
    if(t%Math.max(38,90-Math.floor(score/120))===0||obs.length===0&&t>40){obs.push({x:W,w:14+Math.random()*16,h:22+Math.random()*30});}
    for(var i=0;i<obs.length;i++){obs[i].x-=speed;}
    obs=obs.filter(function(o){return o.x>-40;});
    for(var j=0;j<obs.length;j++){var o=obs[j]; if(o.x<60+34-4&&o.x+o.w>60+4&&y+34>G+34-o.h+4){over=true;run=false; if(score>best){best=score;try{localStorage.setItem('oaOyun',best);}catch(e){}}}}
    score++; speed=6+score/600;
    document.getElementById('sc').textContent='Puan: '+Math.floor(score/5);
  }
  document.getElementById('hi').textContent=best?('En iyi: '+Math.floor(best/5)):'';
  draw(); requestAnimationFrame(step);
}
reset(); step();
})();
</script></body></html>''';
}
