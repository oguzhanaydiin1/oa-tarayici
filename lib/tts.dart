import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'oa_theme.dart';

// Sesli okuma: sayfanın yazısını cihazın kendi Türkçe sesiyle okur (Android ve Windows'un
// konuşma motoru; ek ücret ya da internet gerekmez).

enum ReadState { idle, playing, paused }

class ReadAloud extends ChangeNotifier {
  final FlutterTts _tts = FlutterTts();
  bool _ready = false;
  List<String> _parts = [];
  int index = 0;
  String title = '';
  ReadState state = ReadState.idle;
  double speed = 1.0;
  int _run = 0; // her başlatmada artar; eski döngü kendini bitirir

  bool get active => state != ReadState.idle;
  int get total => _parts.length;
  double get progress => _parts.isEmpty ? 0 : (index / _parts.length).clamp(0, 1).toDouble();

  Future<void> _init() async {
    if (_ready) return;
    _ready = true;
    try {
      await _tts.awaitSpeakCompletion(true);
      await _tts.setLanguage('tr-TR');
      await _tts.setVolume(1);
    } catch (_) {}
  }

  /// Uzun yazıyı cümle sınırlarından ~350 karakterlik parçalara böler.
  static List<String> split(String text) {
    final clean = text.replaceAll(RegExp(r'[ \t ]+'), ' ').replaceAll(RegExp(r'\n\s*\n+'), '\n').trim();
    final sentences = RegExp(r'[^.!?…\n]+[.!?…]*[\s\n]*').allMatches(clean).map((m) => m.group(0)!.trim()).where((s) => s.isNotEmpty);
    final out = <String>[];
    final buf = StringBuffer();
    for (final s in sentences) {
      if (buf.length + s.length > 350 && buf.isNotEmpty) {
        out.add(buf.toString());
        buf.clear();
      }
      if (buf.isNotEmpty) buf.write(' ');
      buf.write(s);
    }
    if (buf.isNotEmpty) out.add(buf.toString());
    return out;
  }

  Future<void> start(String text, String title) async {
    await _init();
    _parts = split(text);
    if (_parts.isEmpty) return;
    this.title = title;
    index = 0;
    await _play();
  }

  Future<void> _play() async {
    final run = ++_run;
    state = ReadState.playing;
    notifyListeners();
    try {
      // Android: 0.5 normal hız; Windows'un motoru da aynı ölçeği kullanır.
      await _tts.setSpeechRate((0.5 * speed).clamp(0.1, 1.0));
    } catch (_) {}
    while (run == _run && index < _parts.length) {
      try {
        await _tts.speak(_parts[index]);
      } catch (_) {
        break;
      }
      if (run != _run) return;
      index++;
      notifyListeners();
    }
    if (run == _run) {
      state = ReadState.idle;
      index = 0;
      notifyListeners();
    }
  }

  Future<void> pause() async {
    _run++;
    await _tts.stop();
    state = ReadState.paused;
    notifyListeners();
  }

  Future<void> resume() async => _play();

  Future<void> stop() async {
    _run++;
    await _tts.stop();
    state = ReadState.idle;
    _parts = [];
    index = 0;
    notifyListeners();
  }

  Future<void> skip(int d) async {
    if (_parts.isEmpty) return;
    _run++;
    await _tts.stop();
    index = (index + d).clamp(0, _parts.length - 1);
    await _play();
  }

  Future<void> setSpeed(double v) async {
    speed = v;
    if (state == ReadState.playing) {
      _run++;
      await _tts.stop();
      await _play();
    } else {
      notifyListeners();
    }
  }
}

/// Okurken alt çubuğun üstünde duran küçük denetim şeridi.
class ReadAloudBar extends StatelessWidget {
  const ReadAloudBar({super.key, required this.tts});
  final ReadAloud tts;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: tts,
      builder: (context, _) {
        if (!tts.active) return const SizedBox.shrink();
        final playing = tts.state == ReadState.playing;
        return Container(
          decoration: BoxDecoration(color: OAColors.surface, border: Border(top: BorderSide(color: OAColors.border))),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            LinearProgressIndicator(value: tts.progress, minHeight: 2, backgroundColor: Colors.transparent),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 2, 6, 2),
              child: Row(children: [
                Icon(Icons.record_voice_over_outlined, size: 20, color: OAColors.amber),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    Text(tts.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: OAColors.text, fontSize: 13.5, fontWeight: FontWeight.w600)),
                    Text('Sesli okuma · ${tts.index + 1}/${tts.total}', style: TextStyle(color: OAColors.muted, fontSize: 12)),
                  ]),
                ),
                IconButton(tooltip: 'Geri', icon: const Icon(Icons.replay_10, size: 22), onPressed: () => tts.skip(-1)),
                IconButton(
                  tooltip: playing ? 'Duraklat' : 'Devam',
                  icon: Icon(playing ? Icons.pause_circle_filled : Icons.play_circle_fill, size: 32, color: OAColors.amber),
                  onPressed: playing ? tts.pause : tts.resume,
                ),
                IconButton(tooltip: 'İleri', icon: const Icon(Icons.forward_10, size: 22), onPressed: () => tts.skip(1)),
                PopupMenuButton<double>(
                  tooltip: 'Hız',
                  initialValue: tts.speed,
                  onSelected: tts.setSpeed,
                  itemBuilder: (_) => [
                    for (final v in const [0.75, 1.0, 1.25, 1.5, 1.75])
                      PopupMenuItem(value: v, child: Text('${v.toString().replaceAll('.', ',')}×')),
                  ],
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                    child: Text('${tts.speed.toString().replaceAll('.', ',')}×', style: TextStyle(color: OAColors.text2, fontWeight: FontWeight.w600)),
                  ),
                ),
                IconButton(tooltip: 'Durdur', icon: const Icon(Icons.close, size: 20), onPressed: tts.stop),
              ]),
            ),
          ]),
        );
      },
    );
  }
}
