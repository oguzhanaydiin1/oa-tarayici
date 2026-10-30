import 'dart:convert';
import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'oa_theme.dart';

/// Bir indirme: listede gösterilir, bitince açılabilir.
class DownloadItem {
  DownloadItem({
    required this.id,
    required this.name,
    required this.url,
    required this.time,
    this.status = 'enqueued',
    this.progress = 0,
    this.path,
    this.size,
  });

  final String id;
  String name;
  final String url;
  final DateTime time;

  /// enqueued, running, paused, complete, failed, canceled, notFound
  String status;
  double progress;
  String? path;
  int? size;
  DownloadTask? task;

  bool get active => status == 'enqueued' || status == 'running' || status == 'waitingToRetry';
  bool get done => status == 'complete';

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'url': url,
        'time': time.toIso8601String(),
        'status': active ? 'failed' : status, // yarıda kalan, uygulama kapanınca başarısız sayılır
        'path': path,
        'size': size,
      };

  static DownloadItem fromJson(Map j) => DownloadItem(
        id: j['id'].toString(),
        name: j['name'].toString(),
        url: j['url'].toString(),
        time: DateTime.tryParse(j['time'].toString()) ?? DateTime.now(),
        status: j['status']?.toString() ?? 'failed',
        path: j['path']?.toString(),
        size: j['size'] is int ? j['size'] as int : null,
      );
}

/// İndirme yöneticisi. İndirmeler arka planda sürer (Android'de sistem iş kuyruğu).
/// Biten dosya Android'de telefonun İndirilenler klasörüne, Windows'ta kullanıcının
/// İndirilenler klasörüne kaydedilir.
class Downloads extends ChangeNotifier {
  final List<DownloadItem> items = [];
  SharedPreferences? _prefs;

  int get activeCount => items.where((i) => i.active).length;

  Future<void> init(SharedPreferences prefs) async {
    _prefs = prefs;
    try {
      final raw = prefs.getString('downloads');
      if (raw != null) {
        items.addAll((jsonDecode(raw) as List).whereType<Map>().map(DownloadItem.fromJson));
      }
    } catch (_) {}
    notifyListeners();
  }

  void _save() {
    _prefs?.setString('downloads', jsonEncode(items.take(100).map((i) => i.toJson()).toList()));
  }

  static String _safeName(String name) {
    final n = name.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_').trim();
    return n.isEmpty ? 'indirme' : (n.length > 120 ? n.substring(n.length - 120) : n);
  }

  /// Windows: aynı adda dosya varsa "ad (1).uzantı" yapar.
  static String _uniqueIn(String dir, String name) {
    if (!File('$dir${Platform.pathSeparator}$name').existsSync()) return name;
    final dot = name.lastIndexOf('.');
    final base = dot > 0 ? name.substring(0, dot) : name;
    final ext = dot > 0 ? name.substring(dot) : '';
    for (var i = 1; i < 1000; i++) {
      final n = '$base ($i)$ext';
      if (!File('$dir${Platform.pathSeparator}$n').existsSync()) return n;
    }
    return name;
  }

  /// İndirmeyi başlatır. [keepPrivate]: dosya uygulamanın kendi klasöründe kalır
  /// (güncelleme paketleri için); [openWhenDone]: bitince dosyayı açar.
  Future<DownloadItem?> start(
    String url, {
    String? suggestedName,
    Map<String, String> headers = const {},
    bool openWhenDone = false,
    bool keepPrivate = false,
  }) async {
    if (!url.startsWith('http')) return null;
    DownloadTask task;
    final common = (
      headers: headers,
      updates: Updates.statusAndProgress,
      allowPause: true,
      retries: 2,
    );
    if (Platform.isWindows && !keepPrivate) {
      final dir = (await getDownloadsDirectory())?.path ??
          (await getApplicationDocumentsDirectory()).path;
      task = DownloadTask(
        url: url,
        filename: suggestedName == null ? null : _safeName(suggestedName),
        baseDirectory: BaseDirectory.root,
        directory: dir,
        headers: common.headers,
        updates: common.updates,
        allowPause: common.allowPause,
        retries: common.retries,
      );
      if (suggestedName == null) {
        task = await task.withSuggestedFilename(unique: true);
      } else {
        task = task.copyWith(filename: _uniqueIn(dir, task.filename));
      }
    } else {
      task = DownloadTask(
        url: url,
        filename: suggestedName == null ? null : _safeName(suggestedName),
        baseDirectory: BaseDirectory.applicationDocuments,
        directory: 'indirilenler',
        headers: common.headers,
        updates: common.updates,
        allowPause: common.allowPause,
        retries: common.retries,
      );
      if (suggestedName == null) task = await task.withSuggestedFilename(unique: true);
    }

    final item = DownloadItem(
      id: task.taskId,
      name: task.filename,
      url: url,
      time: DateTime.now(),
    )..task = task;
    items.insert(0, item);
    notifyListeners();

    FileDownloader()
        .download(
      task,
      onProgress: (p) {
        if (p >= 0) {
          item.progress = p;
          notifyListeners();
        }
      },
      onStatus: (s) {
        item.status = s.name;
        notifyListeners();
      },
    )
        .then((r) async {
      item.status = r.status.name;
      if (r.status == TaskStatus.complete) {
        var path = await task.filePath();
        try {
          item.size = await File(path).length();
        } catch (_) {}
        if (Platform.isAndroid && !keepPrivate) {
          final moved = await FileDownloader().moveToSharedStorage(task, SharedStorage.downloads);
          if (moved != null) path = moved;
        }
        item.path = path;
        item.progress = 1;
      }
      notifyListeners();
      _save();
      if (r.status == TaskStatus.complete && openWhenDone) open(item);
    });
    _save();
    return item;
  }

  Future<bool> open(DownloadItem item) async {
    try {
      final t = item.task;
      // Uygulamanın kendi klasöründeki dosya (güncelleme paketi) görevle açılır.
      if (t != null && item.path != null && item.path == await t.filePath()) {
        return await FileDownloader().openFile(task: t);
      }
      if (item.path != null) return await FileDownloader().openFile(filePath: item.path!);
    } catch (e) {
      debugPrint('Dosya açılamadı: $e');
    }
    return false;
  }

  Future<void> cancel(DownloadItem item) async {
    final t = item.task;
    if (t != null) await FileDownloader().cancelTaskWithId(t.taskId);
    item.status = 'canceled';
    notifyListeners();
    _save();
  }

  void remove(DownloadItem item) {
    items.remove(item);
    notifyListeners();
    _save();
  }

  void clearFinished() {
    items.removeWhere((i) => !i.active);
    notifyListeners();
    _save();
  }
}

String formatBytes(int? b) {
  if (b == null) return '';
  if (b < 1024) return '$b B';
  if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(0)} KB';
  if (b < 1024 * 1024 * 1024) return '${(b / 1024 / 1024).toStringAsFixed(1).replaceAll('.', ',')} MB';
  return '${(b / 1024 / 1024 / 1024).toStringAsFixed(2).replaceAll('.', ',')} GB';
}

/// İndirilenler listesi (alttan açılır).
class DownloadsSheet extends StatelessWidget {
  const DownloadsSheet({super.key, required this.downloads, required this.onToast});
  final Downloads downloads;
  final void Function(String) onToast;

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      builder: (_, scroll) => ListenableBuilder(
        listenable: downloads,
        builder: (context, _) {
          final items = downloads.items;
          return Column(
            children: [
              ListTile(
                title: Text('İndirilenler', style: oaDisplay(20)),
                subtitle: Text(Platform.isAndroid
                    ? 'Dosyalar telefonun İndirilenler klasörüne kaydedilir'
                    : 'Dosyalar İndirilenler klasörüne kaydedilir'),
                trailing: items.any((i) => !i.active)
                    ? TextButton(onPressed: downloads.clearFinished, child: const Text('Listeyi temizle'))
                    : null,
              ),
              const Divider(height: 1),
              Expanded(
                child: items.isEmpty
                    ? Center(
                        child: Text('Henüz bir şey indirmedin.',
                            style: TextStyle(color: OAColors.muted)))
                    : ListView.builder(
                        controller: scroll,
                        itemCount: items.length,
                        itemBuilder: (_, i) => _row(context, items[i]),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _row(BuildContext context, DownloadItem it) {
    final (IconData icon, Color color, String sub) = switch (it.status) {
      'complete' => (Icons.check_circle, OAColors.green, formatBytes(it.size)),
      'failed' => (Icons.error_outline, OAColors.danger, 'İndirilemedi'),
      'notFound' => (Icons.error_outline, OAColors.danger, 'Dosya bulunamadı (404)'),
      'canceled' => (Icons.cancel_outlined, OAColors.muted, 'İptal edildi'),
      'paused' => (Icons.pause_circle_outline, OAColors.muted, 'Duraklatıldı'),
      _ => (Icons.downloading, OAColors.accent, 'İndiriliyor… %${(it.progress * 100).round()}'),
    };
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(it.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(sub),
          if (it.active)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: LinearProgressIndicator(value: it.progress > 0 ? it.progress : null),
            ),
        ],
      ),
      onTap: it.done
          ? () async {
              final ok = await downloads.open(it);
              if (!ok) onToast('Dosya açılamadı. İndirilenler klasöründe: ${it.name}');
            }
          : null,
      trailing: it.active
          ? IconButton(
              tooltip: 'İptal et',
              icon: const Icon(Icons.close),
              onPressed: () => downloads.cancel(it),
            )
          : IconButton(
              tooltip: 'Listeden kaldır',
              icon: const Icon(Icons.delete_outline),
              onPressed: () => downloads.remove(it),
            ),
    );
  }
}
