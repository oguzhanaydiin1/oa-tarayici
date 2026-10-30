import 'dart:async';
import 'dart:convert';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'account.dart';
import 'account_sheet.dart';
import 'adblock.dart';
import 'oa_theme.dart';
import 'qr_page.dart';
import 'reader.dart';
import 'search.dart';
import 'smart.dart';
import 'start_page.dart';
import 'wallpaper.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Tema seçimini açılışta oku; yanlış temada bir an görünmesin.
  try {
    final prefs = await SharedPreferences.getInstance();
    themeModeNotifier.value = themeModeFromString(prefs.getString('theme'));
  } catch (_) {}
  runApp(BrowserApp());
}

class BrowserApp extends StatefulWidget {
  BrowserApp({super.key});

  @override
  State<BrowserApp> createState() => _BrowserAppState();
}

class _BrowserAppState extends State<BrowserApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    themeModeNotifier.addListener(_onTheme);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    themeModeNotifier.removeListener(_onTheme);
    super.dispose();
  }

  void _onTheme() => setState(() {});

  // Sistem teması değişince ("Sistem" seçiliyse) uygulama da değişsin.
  @override
  void didChangePlatformBrightness() => setState(() {});

  OAPalette _palette() {
    final mode = themeModeNotifier.value;
    final dark = mode == ThemeMode.dark ||
        (mode == ThemeMode.system &&
            WidgetsBinding.instance.platformDispatcher.platformBrightness ==
                Brightness.dark);
    return dark ? kOADark : kOALight;
  }

  @override
  Widget build(BuildContext context) {
    final p = _palette();
    OAColors.use(p);
    SystemChrome.setSystemUIOverlayStyle(oaSystemOverlay(p));
    return MaterialApp(
      title: 'OA Tarayıcı',
      debugShowCheckedModeBanner: false,
      theme: buildOATheme(p),
      home: BrowserPage(key: _pageKey),
    );
  }
}

final _pageKey = GlobalKey<_BrowserPageState>();

/// Tek bir sekmenin durumu.
class TabData {
  TabData({this.incognito = false}) : id = UniqueKey().toString();

  final String id;
  final bool incognito;

  /// OA başlangıç sayfası gösteriliyor mu? Sayfa arkada açık kalır, geri dönülebilir.
  bool showStart = true;

  /// Web görünümü bir kez oluşturuldu mu?
  bool webStarted = false;

  /// Web görünümü oluşturulurken açılacak ilk adres.
  String? pendingUrl;

  String url = '';
  String title = '';
  double progress = 1;
  bool canGoBack = false;
  bool canGoForward = false;

  /// Yeni sayfa ekrana gelene kadar web görünümünü örten perde. Başlangıç sayfasından
  /// bir siteye gidilince sekmede önceden açık kalan sayfa (ya da boş beyaz ekran) görünmesin.
  bool covering = false;
  bool coverLoadStarted = false;
  InAppWebViewController? controller;

  /// Android: sayfayı aşağı çekince yenileme.
  PullToRefreshController? pullToRefresh;

  String get displayTitle {
    if (showStart) return incognito ? 'Gizli sekme' : 'Yeni sekme';
    if (title.isNotEmpty) return title;
    return host.isEmpty ? 'Yükleniyor…' : host;
  }

  String get host {
    final u = Uri.tryParse(url);
    if (u == null || u.host.isEmpty) return url;
    return u.host.replaceFirst(RegExp(r'^www\.'), '');
  }
}

class BrowserPage extends StatefulWidget {
  BrowserPage({super.key});

  @override
  State<BrowserPage> createState() => _BrowserPageState();
}

class _BrowserPageState extends State<BrowserPage> {
  final List<TabData> _tabs = [];
  int _current = 0;

  final TextEditingController _urlCtl = TextEditingController();
  final FocusNode _urlFocus = FocusNode();

  /// Telefon düzeninde adres çubuğu düzenleniyor mu? (Düzenlenmiyorken yalnız alan adı görünür.)
  bool _editing = false;

  SharedPreferences? _prefs;
  final OAAccount _account = OAAccount();
  List<QuickLink> _quick = List.of(kDefaultQuickLinks);

  // Reklam engelleme
  bool _adblockOn = true;
  Set<String> _adblockAllow = {};

  // Başlangıç sayfası arka planı ve okuma modu yazı boyu
  String _wallpaperId = 'none';
  String? _wallpaperPath;
  int _readerSize = 19;

  // Eşitleme: her koleksiyonun son yerel değişiklik zamanı
  DateTime _bookmarksUpdated = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  DateTime _quickUpdated = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  Timer? _syncTimer;
  bool _wasSignedIn = false;
  DateTime? _lastSync;

  // Akıllı adres çubuğu cevabı
  SmartAnswer? _answer;
  List<Map<String, String>> _bookmarks = [];
  List<Map<String, String>> _history = [];

  // Arama
  SearchEngine _engine = kEngines.first;
  bool _suggestOn = true;
  List<Suggestion> _suggestions = [];
  int _selected = -1;
  bool _showSuggestions = false;
  Timer? _debounce;
  int _suggestRequest = 0;

  TabData get _tab => _tabs[_current];

  /// Telefon düzeni: Android ve iOS'ta; bilgisayarda pencere çok daraltılınca da.
  bool _isMobile(BuildContext context) =>
      Platform.isAndroid ||
      Platform.isIOS ||
      MediaQuery.sizeOf(context).width < 520;

  @override
  void initState() {
    super.initState();
    _tabs.add(TabData());
    _loadStorage();
    _account.addListener(_onAccount);
    _account.load().then((_) {
      _account.syncToWebView();
      _syncNow();
    });
    // Ok tuşları öneri listesinde gezsin; odaktaki düğümde yakalanır, metin kutusundan önce.
    _urlFocus.onKeyEvent = _onAddressKey;
    _urlFocus.addListener(() {
      if (!_urlFocus.hasFocus) {
        // Öneriye dokunma, odak kaybından sonra gelir; kısa bir gecikmeyle kapat.
        Future.delayed(Duration(milliseconds: 150), () {
          if (mounted && !_urlFocus.hasFocus) {
            setState(() {
              _showSuggestions = false;
              _editing = false;
              _urlCtl.text = _addressText(_tab);
            });
          }
        });
      } else {
        _urlCtl.selection =
            TextSelection(baseOffset: 0, extentOffset: _urlCtl.text.length);
      }
    });
  }

  void _onAccount() {
    if (!mounted) return;
    setState(() {});
    // Yeni giriş yapıldıysa hemen eşitle.
    if (_account.signedIn && !_wasSignedIn) _syncNow();
    _wasSignedIn = _account.signedIn;
  }

  // ---------------------------------------------------------------- Eşitleme

  /// Yer imleri ve hızlı erişim OA hesabıyla eşitlenir: hangi taraf daha yeni değiştiyse o kazanır.
  Future<void> _syncNow() async {
    if (!_account.signedIn || _prefs == null) return;
    final server = await _account.pullSync();
    if (server == null || !mounted) return; // sunucu eşitlemeyi henüz desteklemiyor ya da ağ yok
    var changed = false;
    final sb = server['bookmarks'];
    if (sb != null && sb.updated.isAfter(_bookmarksUpdated)) {
      _bookmarks = sb.data
          .whereType<Map>()
          .map((m) => {for (final e in m.entries) e.key.toString(): e.value.toString()})
          .toList();
      _bookmarksUpdated = sb.updated;
      _save('bookmarks', _bookmarks, touch: false);
      changed = true;
    }
    final sq = server['quick'];
    if (sq != null && sq.updated.isAfter(_quickUpdated)) {
      _quick = sq.data.whereType<Map>().map(QuickLink.fromJson).where((l) => l.url.isNotEmpty).toList();
      _quickUpdated = sq.updated;
      _saveQuick(touch: false);
      changed = true;
    }
    if (changed) setState(() {});
    final push = <String, SyncItem>{};
    if (sb == null || _bookmarksUpdated.isAfter(sb.updated)) {
      push['bookmarks'] = SyncItem(_bookmarksUpdated, _bookmarks);
    }
    if (sq == null || _quickUpdated.isAfter(sq.updated)) {
      push['quick'] = SyncItem(_quickUpdated, _quick.map((q) => q.toJson()).toList());
    }
    if (push.isNotEmpty) await _account.pushSync(push);
    _lastSync = DateTime.now();
  }

  /// Yerel bir değişiklikten 2 saniye sonra eşitle (art arda değişiklikler tek istekte gider).
  void _scheduleSync() {
    if (!_account.signedIn) return;
    _syncTimer?.cancel();
    _syncTimer = Timer(const Duration(seconds: 2), _syncNow);
  }

  @override
  void dispose() {
    _account.removeListener(_onAccount);
    _account.dispose();
    _syncTimer?.cancel();
    _debounce?.cancel();
    _urlCtl.dispose();
    _urlFocus.dispose();
    super.dispose();
  }

  String _addressText(TabData t) => t.showStart ? '' : t.url;

  // ---------------------------------------------------------------- Depolama

  Future<void> _loadStorage() async {
    _prefs = await SharedPreferences.getInstance();
    setState(() {
      _bookmarks = _decode(_prefs!.getStringList('bookmarks'));
      _history = _decode(_prefs!.getStringList('history'));
      _engine = engineById(_prefs!.getString('engine'));
      _suggestOn = _prefs!.getBool('suggest') ?? true;
      _adblockOn = _prefs!.getBool('adblock') ?? true;
      _adblockAllow = (_prefs!.getStringList('adblock_allow') ?? []).toSet();
      _wallpaperId = _prefs!.getString('wallpaper') ?? 'none';
      _wallpaperPath = _prefs!.getString('wallpaper_path');
      _readerSize = _prefs!.getInt('reader_size') ?? 19;
      DateTime t(String k) =>
          DateTime.tryParse(_prefs!.getString(k) ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
      _bookmarksUpdated = t('bookmarks_updated');
      _quickUpdated = t('quick_updated');
      final q = _prefs!.getString('quick');
      if (q != null) {
        try {
          _quick = (jsonDecode(q) as List)
              .whereType<Map>()
              .map(QuickLink.fromJson)
              .where((l) => l.url.isNotEmpty)
              .toList();
        } catch (_) {}
      }
    });
  }

  void _saveQuick({bool touch = true}) {
    _prefs?.setString('quick', jsonEncode(_quick.map((q) => q.toJson()).toList()));
    if (touch) {
      _quickUpdated = DateTime.now().toUtc();
      _scheduleSync();
    }
    _prefs?.setString('quick_updated', _quickUpdated.toIso8601String());
  }

  void _reorderQuick(int from, int to) {
    setState(() {
      final item = _quick.removeAt(from);
      _quick.insert(to.clamp(0, _quick.length), item);
    });
    _saveQuick();
  }

  void _onQuickAction(QuickAction action, int i) {
    switch (action) {
      case QuickAction.open:
        _go(_quick[i].url);
      case QuickAction.openNewTab:
        _addTab(url: _quick[i].url, incognito: _tab.incognito);
      case QuickAction.edit:
        _editQuick(i);
      case QuickAction.remove:
        final removed = _quick[i];
        setState(() => _quick.removeAt(i));
        _saveQuick();
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(
            content: Text('"${removed.name}" kaldırıldı'),
            action: SnackBarAction(
              label: 'Geri al',
              textColor: OAColors.accent,
              onPressed: () {
                setState(() => _quick.insert(i.clamp(0, _quick.length), removed));
                _saveQuick();
              },
            ),
          ));
    }
  }

  /// Hızlı erişim kutusu ekle (index null) ya da düzenle.
  Future<void> _editQuick(int? index) async {
    final old = index == null ? null : _quick[index];
    final onPage = !_tab.showStart;
    final name = TextEditingController(
        text: old?.name ?? (onPage && index == null ? _tab.displayTitle : ''));
    final url = TextEditingController(
        text: old?.url ?? (onPage && index == null ? _tab.url : ''));
    String? error;
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(old == null ? 'Hızlı erişime ekle' : 'Hızlı erişimi düzenle',
              style: oaDisplay(22)),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: name,
                  autofocus: true,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(hintText: 'Ad (ör. Haberler)'),
                ),
                SizedBox(height: 12),
                TextField(
                  controller: url,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  decoration: InputDecoration(hintText: 'Adres (ör. ornek.com)'),
                  onSubmitted: (_) => Navigator.pop(ctx, true),
                ),
                if (error != null) ...[
                  SizedBox(height: 10),
                  Text(error!, style: TextStyle(color: OAColors.danger, fontSize: 14)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Vazgeç')),
            FilledButton(
              onPressed: () {
                if (!looksLikeUrl(url.text)) {
                  setD(() => error = 'Geçerli bir adres yaz, ör. ornek.com');
                  return;
                }
                Navigator.pop(ctx, true);
              },
              style: FilledButton.styleFrom(minimumSize: Size(0, 44)),
              child: Text('Kaydet'),
            ),
          ],
        ),
      ),
    );
    if (saved != true || !looksLikeUrl(url.text)) return;
    var u = url.text.trim();
    if (!RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*://').hasMatch(u)) u = 'https://$u';
    var n = name.text.trim();
    if (n.isEmpty) n = Uri.tryParse(u)?.host.replaceFirst(RegExp(r'^www\.'), '') ?? u;
    final link = QuickLink(n, u, color: old?.url == u ? old?.color : null);
    setState(() {
      if (index == null) {
        _quick.add(link);
      } else {
        _quick[index] = link;
      }
    });
    _saveQuick();
  }

  // ---------------------------------------------------------------- Reklam engelleme

  String get _pageHost =>
      (_tab.showStart ? '' : Uri.tryParse(_tab.url)?.host ?? '').replaceFirst(RegExp(r'^www\.'), '');

  /// Bu sekmede engelleme çalışıyor mu? (genel ayar açık ve site istisna değil)
  bool get _siteBlocking =>
      _adblockOn && (_pageHost.isEmpty || !AdBlock.isAllowedSite(_pageHost, _adblockAllow));

  /// Ayar değişince açık bütün sekmelere uygula ve şu anki sayfayı yenile.
  Future<void> _applyAdblock() async {
    _prefs?.setBool('adblock', _adblockOn);
    _prefs?.setStringList('adblock_allow', _adblockAllow.toList());
    for (final t in _tabs) {
      final c = t.controller;
      if (c == null) continue;
      try {
        await c.setSettings(
          settings: InAppWebViewSettings(
            contentBlockers: _adblockOn ? AdBlock.contentBlockers(_adblockAllow) : [],
            useShouldInterceptRequest: Platform.isWindows && _adblockOn,
          ),
        );
        await c.removeUserScriptsByGroupName(groupName: 'oa-adblock');
        if (_adblockOn) await c.addUserScript(userScript: AdBlock.cosmeticScript(_adblockAllow));
      } catch (_) {}
    }
    if (!_tab.showStart) _tab.controller?.reload();
    if (mounted) setState(() {});
  }

  void _showAdblockSettings() {
    final host = _pageHost;
    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final siteAllowed = host.isNotEmpty && AdBlock.isAllowedSite(host, _adblockAllow);
          return Padding(
            padding: const EdgeInsets.fromLTRB(8, 16, 8, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                  child: Text('Reklam engelleme', style: oaDisplay(22)),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(
                    'Reklam ağlarına ve izleyicilere giden istekleri engeller, sayfadaki reklam kutularını gizler. '
                    '${AdBlock.domains.length} reklam ve izleme alan adı listede.',
                    style: TextStyle(color: OAColors.muted, height: 1.5),
                  ),
                ),
                SwitchListTile(
                  value: _adblockOn,
                  activeThumbColor: OAColors.amberInk,
                  activeTrackColor: OAColors.amber,
                  title: const Text('Reklamları ve izleyicileri engelle',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  onChanged: (v) {
                    _adblockOn = v;
                    setSheet(() {});
                    _applyAdblock();
                  },
                ),
                if (host.isNotEmpty && _adblockOn)
                  SwitchListTile(
                    value: !siteAllowed,
                    activeThumbColor: OAColors.amberInk,
                    activeTrackColor: OAColors.amber,
                    title: Text('$host sitesinde engelle',
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: const Text('Site düzgün çalışmıyorsa bu sitede kapatabilirsin'),
                    onChanged: (v) {
                      if (v) {
                        _adblockAllow.removeWhere(
                            (a) => host == a || host.endsWith('.$a'));
                      } else {
                        _adblockAllow.add(host);
                      }
                      setSheet(() {});
                      _applyAdblock();
                    },
                  ),
                if (_adblockAllow.isNotEmpty)
                  ListTile(
                    leading: const Icon(Icons.playlist_remove),
                    title: Text('Engellemenin kapalı olduğu siteler: ${_adblockAllow.length}'),
                    subtitle: Text(_adblockAllow.take(4).join(', ') +
                        (_adblockAllow.length > 4 ? '…' : '')),
                    trailing: TextButton(
                      onPressed: () {
                        _adblockAllow.clear();
                        setSheet(() {});
                        _applyAdblock();
                      },
                      child: const Text('Hepsini aç'),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ---------------------------------------------------------------- Okuma modu, çeviri, QR

  Future<void> _toggleReader() async {
    final c = _tab.controller;
    if (_tab.showStart || c == null) return;
    final r = await Reader.toggle(c, fontSize: _readerSize);
    if (r == ReaderResult.notAvailable) {
      _toast('Bu sayfada okuma modu için yeterli yazı bulunamadı');
    } else if (r == ReaderResult.failed) {
      _toast('Okuma modu açılamadı');
    }
  }

  void _translate() {
    if (_tab.showStart) return;
    final u = _tab.url;
    if (u.contains('translate.goog') || u.contains('translate.google.')) {
      _toast('Bu sayfa zaten çeviri sayfası');
      return;
    }
    _toast('Sayfa Google Çeviri ile açılıyor; sayfanın adresi Google\'a gönderilir');
    _go('https://translate.google.com/translate?sl=auto&tl=tr&u=${Uri.encodeComponent(u)}');
  }

  Future<void> _scanQr() async {
    if (!Platform.isAndroid) return;
    _urlFocus.unfocus();
    final v = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const QrPage(), fullscreenDialog: true),
    );
    if (v == null || !mounted) return;
    if (looksLikeUrl(v)) {
      _go(v);
    } else {
      Clipboard.setData(ClipboardData(text: v));
      _toast('Okunan: $v (panoya kopyalandı)');
      _go(v, forceSearch: true);
    }
  }

  // ---------------------------------------------------------------- Arka plan

  void _setWallpaper(String id, {String? path}) {
    setState(() {
      _wallpaperId = id;
      if (path != null) _wallpaperPath = path;
    });
    _prefs?.setString('wallpaper', id);
    if (path != null) _prefs?.setString('wallpaper_path', path);
  }

  Future<void> _pickPhoto() async {
    try {
      final r = await FilePicker.platform.pickFiles(type: FileType.image);
      final src = r?.files.single.path;
      if (src == null) return;
      final dir = await getApplicationSupportDirectory();
      final ext = src.contains('.') ? src.substring(src.lastIndexOf('.')) : '.jpg';
      // Her seçimde yeni ad: eski resim önbellekte kalmasın.
      final dest = '${dir.path}${Platform.pathSeparator}arka-plan-${DateTime.now().millisecondsSinceEpoch}$ext';
      await File(src).copy(dest);
      final old = _wallpaperPath;
      _setWallpaper('photo', path: dest);
      if (old != null && old != dest) {
        try {
          await File(old).delete();
        } catch (_) {}
      }
    } catch (e) {
      _toast('Fotoğraf seçilemedi');
    }
  }

  void _showWallpaperPicker() {
    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Başlangıç sayfası arka planı', style: oaDisplay(22)),
              const SizedBox(height: 16),
              Wrap(
                spacing: 14,
                runSpacing: 14,
                children: [
                  for (final w in Wallpaper.all)
                    WallpaperSwatch(
                      id: w.id,
                      label: w.name,
                      selected: _wallpaperId == w.id,
                      onTap: () {
                        _setWallpaper(w.id);
                        setSheet(() {});
                      },
                    ),
                  WallpaperSwatch(
                    id: 'photo',
                    label: 'Fotoğrafın',
                    photoPath: _wallpaperPath,
                    icon: _wallpaperPath == null ? Icons.add_photo_alternate_outlined : null,
                    selected: _wallpaperId == 'photo',
                    onTap: () async {
                      await _pickPhoto();
                      setSheet(() {});
                    },
                  ),
                ],
              ),
              if (_wallpaperId == 'photo') ...[
                const SizedBox(height: 12),
                TextButton.icon(
                  onPressed: () async {
                    await _pickPhoto();
                    setSheet(() {});
                  },
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('Başka fotoğraf seç'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- Görünüm ve hesap

  void _showThemeSettings() {
    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      builder: (ctx) => ValueListenableBuilder<ThemeMode>(
        valueListenable: themeModeNotifier,
        builder: (ctx, mode, _) {
          Widget option(ThemeMode m, IconData icon, String label, String sub) => ListTile(
                leading: Icon(icon),
                title: Text(label, style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(sub),
                trailing: Icon(
                  mode == m ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                  color: mode == m ? OAColors.accent : OAColors.border2,
                ),
                onTap: () {
                  themeModeNotifier.value = m;
                  _prefs?.setString('theme', themeModeToString(m));
                },
              );
          return Padding(
            padding: EdgeInsets.fromLTRB(8, 16, 8, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text('Görünüm', style: oaDisplay(22)),
                ),
                option(ThemeMode.system, Icons.brightness_auto_outlined, 'Sistem',
                    'Cihazın ayarına göre koyu ya da açık'),
                option(ThemeMode.dark, Icons.dark_mode_outlined, 'Koyu', 'OA Labs sitesi gibi'),
                option(ThemeMode.light, Icons.light_mode_outlined, 'Açık', 'Aydınlık ortamlar için'),
              ],
            ),
          );
        },
      ),
    );
  }

  void _openAccount() {
    final mobile = _isMobile(context);
    if (!_account.signedIn) {
      showSignIn(context, _account, mobile: mobile, openUrl: (u) => _addTab(url: u));
      return;
    }
    final summary = AccountSummary(
      account: _account,
      onManage: () {
        Navigator.of(context).pop();
        _account.syncToWebView().then((_) => _addTab(url: '${OAAccount.site}/hesabim/'));
      },
      onLogout: () {
        Navigator.of(context).pop();
        _account.logout().then((_) => _toast('Çıkış yapıldı'));
      },
    );
    if (mobile) {
      showModalBottomSheet(
        context: context,
        useSafeArea: true,
        builder: (_) => Padding(padding: EdgeInsets.fromLTRB(20, 24, 20, 16), child: summary),
      );
    } else {
      showDialog(
        context: context,
        builder: (_) => Dialog(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 400),
            child: Padding(padding: EdgeInsets.all(24), child: summary),
          ),
        ),
      );
    }
  }

  List<Map<String, String>> _decode(List<String>? raw) => (raw ?? [])
      .map((e) => Map<String, String>.from(jsonDecode(e) as Map))
      .toList();

  void _save(String key, List<Map<String, String>> list, {bool touch = true}) {
    _prefs?.setStringList(key, list.map(jsonEncode).toList());
    if (key == 'bookmarks') {
      if (touch) {
        _bookmarksUpdated = DateTime.now().toUtc();
        _scheduleSync();
      }
      _prefs?.setString('bookmarks_updated', _bookmarksUpdated.toIso8601String());
    }
  }

  bool get _isBookmarked =>
      !_tab.showStart && _bookmarks.any((b) => b['url'] == _tab.url);

  void _toggleBookmark() {
    if (_tab.showStart) return;
    final added = !_isBookmarked;
    setState(() {
      if (added) {
        _bookmarks.insert(0, {'title': _tab.displayTitle, 'url': _tab.url});
      } else {
        _bookmarks.removeWhere((b) => b['url'] == _tab.url);
      }
    });
    _save('bookmarks', _bookmarks);
    _toast(added ? 'Yer imlerine eklendi' : 'Yer imlerinden çıkarıldı');
  }

  void _pushHistory(Map<String, String> entry) {
    if (_history.isNotEmpty && _history.first['url'] == entry['url']) return;
    _history.insert(0, entry);
    if (_history.length > 300) _history.removeRange(300, _history.length);
    _save('history', _history);
  }

  void _addHistory(TabData t) {
    if (t.incognito || t.url.isEmpty || t.url == 'about:blank') return;
    _pushHistory({'title': t.displayTitle, 'url': t.url});
  }

  void _toast(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(text),
        duration: Duration(milliseconds: 1400),
      ));
  }

  // ----------------------------------------------------------------- Sekmeler

  void _addTab({String? url, bool incognito = false}) {
    setState(() {
      final t = TabData(incognito: incognito);
      if (url != null) {
        t
          ..showStart = false
          ..webStarted = true
          ..pendingUrl = url
          ..url = url;
      }
      _tabs.add(t);
      _current = _tabs.length - 1;
      _urlCtl.text = _addressText(t);
      _showSuggestions = false;
    });
  }

  void _closeTab(int i) {
    setState(() {
      if (_tabs.length == 1) {
        _tabs
          ..clear()
          ..add(TabData());
        _current = 0;
      } else {
        _tabs.removeAt(i);
        if (_current >= _tabs.length) {
          _current = _tabs.length - 1;
        } else if (i < _current) {
          _current--;
        }
      }
      _urlCtl.text = _addressText(_tab);
    });
  }

  void _selectTab(int i) {
    setState(() {
      _current = i;
      _urlCtl.text = _addressText(_tab);
      _showSuggestions = false;
    });
  }

  // ---------------------------------------------------------------- Gezinme

  /// Adres çubuğuna yazılanı URL'ye ya da seçili motorda aramaya çevirir.
  String _normalize(String input, {bool forceSearch = false}) {
    final text = input.trim();
    if (!forceSearch && looksLikeUrl(text)) {
      final hasScheme = RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*://').hasMatch(text);
      return hasScheme ? text : 'https://$text';
    }
    if (!_tab.incognito) {
      _pushHistory({'title': text, 'url': _engine.searchUrl(text, dark: OAColors.isDark), 'q': text});
    }
    return _engine.searchUrl(text, dark: OAColors.isDark);
  }

  void _go(String input, {bool forceSearch = false}) {
    if (input.trim().isEmpty) {
      _goHome();
      return;
    }
    final url = _normalize(input, forceSearch: forceSearch);
    final t = _tab;
    setState(() {
      if (t.showStart || t.controller == null) _cover(t);
      t.url = url;
      t.title = '';
      t.showStart = false;
      _showSuggestions = false;
      _editing = false;
      if (t.controller != null) {
        t.controller!.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
      } else {
        t.pendingUrl = url;
        t.webStarted = true;
      }
      _urlCtl.text = url;
    });
    _urlFocus.unfocus();
  }

  void _cover(TabData t) {
    t
      ..covering = true
      ..coverLoadStarted = false;
    // Sayfa hiç cevap vermezse perde sonsuza kadar kalmasın.
    Future.delayed(const Duration(seconds: 8), () => _uncover(t));
  }

  void _uncover(TabData t) {
    if (!t.covering || !mounted) return;
    setState(() => t.covering = false);
  }

  void _goHome() {
    setState(() {
      _tab.showStart = true;
      _tab.progress = 1;
      _showSuggestions = false;
      _editing = false;
      _urlCtl.text = '';
    });
    _urlFocus.unfocus();
  }

  bool get _canBack => !_tab.showStart;
  bool get _canForward =>
      (_tab.showStart && _tab.webStarted) || (!_tab.showStart && _tab.canGoForward);

  Future<void> _back() async {
    final t = _tab;
    if (t.showStart) return;
    if (await t.controller?.canGoBack() ?? false) {
      await t.controller!.goBack();
    } else {
      // İlk sayfadan geri: OA başlangıç sayfasına dön.
      _goHome();
    }
  }

  void _forward() {
    final t = _tab;
    if (t.showStart && t.webStarted) {
      setState(() {
        t.showStart = false;
        _urlCtl.text = t.url;
      });
    } else {
      t.controller?.goForward();
    }
  }

  void _reloadOrStop() {
    final t = _tab;
    if (t.showStart) return;
    if (t.progress < 1) {
      t.controller?.stopLoading();
    } else {
      t.controller?.reload();
    }
  }

  Future<void> _refreshNavState(TabData t) async {
    final back = await t.controller?.canGoBack() ?? false;
    final fwd = await t.controller?.canGoForward() ?? false;
    if (!mounted) return;
    setState(() {
      t.canGoBack = back;
      t.canGoForward = fwd;
    });
  }

  Future<bool> _handleSystemBack() async {
    if (_showSuggestions || _editing) {
      _urlFocus.unfocus();
      setState(() {
        _showSuggestions = false;
        _editing = false;
      });
      return true;
    }
    if (!_tab.showStart) {
      await _back();
      return true;
    }
    if (_tabs.length > 1) {
      _closeTab(_current);
      return true;
    }
    return false;
  }

  // ---------------------------------------------------------------- Öneriler

  void _onAddressChanged(String text) {
    final local = _localSuggestions(text);
    setState(() {
      _suggestions = local;
      _answer = smartAnswer(text);
      _selected = -1;
      _showSuggestions = local.isNotEmpty;
    });
    // Döviz sorusuysa ve kurlar henüz inmediyse indir, inince cevabı göster.
    if (_answer == null && looksLikeCurrency(text) && !Rates.ready) {
      Rates.load().then((_) {
        if (mounted && _urlCtl.text == text) setState(() => _answer = smartAnswer(text));
      });
    }

    _debounce?.cancel();
    // Gizli sekmede yazılanlar arama motoruna gönderilmez.
    if (!_suggestOn || _tab.incognito || text.trim().isEmpty || looksLikeUrl(text)) {
      return;
    }
    _debounce = Timer(Duration(milliseconds: 150), () async {
      final request = ++_suggestRequest;
      final remote = await fetchSuggestions(_engine, text);
      // Bu arada kullanıcı yazmaya devam ettiyse eski cevabı at.
      if (!mounted || request != _suggestRequest || _urlCtl.text != text) return;
      setState(() {
        _suggestions = _merge(_localSuggestions(text), remote);
        _showSuggestions = _urlFocus.hasFocus && _suggestions.isNotEmpty;
      });
    });
  }

  /// Cihazda olanlardan öneri: önceki aramalar, yer imleri, ziyaret edilen sayfalar.
  List<Suggestion> _localSuggestions(String raw) {
    final q = raw.trim();
    if (q.isEmpty) return [];
    final ql = q.toLowerCase();
    final out = <Suggestion>[];
    if (looksLikeUrl(q)) out.add(Suggestion(SuggestionKind.go, q, q));
    out.add(Suggestion(SuggestionKind.search, q, q));
    if (!_suggestOn) return out;

    final pastQueries = <String>{};
    for (final h in _history) {
      final pq = h['q'];
      if (pq != null && pq.toLowerCase().startsWith(ql) && pq.toLowerCase() != ql) {
        if (pastQueries.add(pq)) {
          out.add(Suggestion(SuggestionKind.pastSearch, pq, pq));
        }
      }
      if (pastQueries.length >= 2) break;
    }

    final seen = <String>{};
    void addPage(Map<String, String> p, SuggestionKind kind) {
      final url = p['url'] ?? '';
      final title = p['title'] ?? url;
      if (url.isEmpty || seen.contains(url) || p['q'] != null) return;
      if ('$title $url'.toLowerCase().contains(ql)) {
        seen.add(url);
        out.add(Suggestion(kind, url, title, url: url));
      }
    }

    for (final b in _bookmarks) {
      addPage(b, SuggestionKind.bookmark);
    }
    for (final h in _history) {
      addPage(h, SuggestionKind.page);
    }
    return out.take(5).toList();
  }

  List<Suggestion> _merge(List<Suggestion> local, List<String> remote) {
    final head = local
        .where((s) => s.kind == SuggestionKind.go || s.kind == SuggestionKind.search)
        .toList();
    final rest = local.where((s) => !head.contains(s)).toList();
    final known = local.map((s) => s.value.toLowerCase()).toSet();
    final fromEngine = remote
        .where((r) => !known.contains(r.toLowerCase()))
        .take(5)
        .map((r) => Suggestion(SuggestionKind.remote, r, r));
    return [...head, ...fromEngine, ...rest.take(3)];
  }

  void _pick(Suggestion s) => _go(s.value, forceSearch: s.isSearch);

  KeyEventResult _onAddressKey(FocusNode node, KeyEvent event) {
    if (!_showSuggestions || _suggestions.isEmpty) return KeyEventResult.ignored;
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final n = _suggestions.length;
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      setState(() => _selected = _selected + 1 >= n ? -1 : _selected + 1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      setState(() => _selected = _selected - 1 < -1 ? n - 1 : _selected - 1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      setState(() => _showSuggestions = false);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _onSubmitted(String text) {
    if (_showSuggestions && _selected >= 0 && _selected < _suggestions.length) {
      _pick(_suggestions[_selected]);
    } else {
      _go(text);
    }
  }

  void _startEditing() {
    setState(() {
      _editing = true;
      _urlCtl.text = _addressText(_tab);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _urlFocus.requestFocus();
      _urlCtl.selection =
          TextSelection(baseOffset: 0, extentOffset: _urlCtl.text.length);
    });
  }

  // ---------------------------------------------------------------- Arayüz

  @override
  Widget build(BuildContext context) {
    final mobile = _isMobile(context);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final handled = await _handleSystemBack();
        if (!handled) SystemNavigator.pop();
      },
      child: CallbackShortcuts(
        bindings: {
          SingleActivator(LogicalKeyboardKey.keyT, control: true): () => _addTab(),
          SingleActivator(LogicalKeyboardKey.keyW, control: true): () =>
              _closeTab(_current),
          SingleActivator(LogicalKeyboardKey.keyL, control: true): () =>
              mobile ? _startEditing() : _urlFocus.requestFocus(),
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            backgroundColor: OAColors.bg,
            body: mobile ? _buildMobile() : _buildDesktop(),
          ),
        ),
      ),
    );
  }

  Widget _loadingCover(TabData t) {
    return ColoredBox(
      color: OAColors.bg,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 3, color: OAColors.amber),
            ),
            const SizedBox(height: 16),
            Text(t.host, style: TextStyle(color: OAColors.muted, fontSize: 15)),
          ],
        ),
      ),
    );
  }

  Widget _tabContent(TabData t, {required bool compact}) {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (t.webStarted) Offstage(offstage: t.showStart, child: _buildWebView(t)),
        if (t.webStarted && !t.showStart && t.covering) _loadingCover(t),
        if (t.showStart)
          StartPage(
            incognito: t.incognito,
            engineName: _engine.name,
            quickLinks: _quick,
            bookmarks: _bookmarks,
            compact: compact,
            userFirstName: _account.user?.firstName,
            onGo: (input) => _go(input),
            onQuickAction: _onQuickAction,
            onQuickAdd: () => _editQuick(null),
            onQuickReorder: _reorderQuick,
            onChangeEngine: _showSearchSettings,
            onWallpaper: _showWallpaperPicker,
            wallpaperId: _wallpaperId,
            wallpaperPath: _wallpaperPath,
          ),
      ],
    );
  }

  Widget _pages({required bool compact}) => IndexedStack(
        index: _current,
        children: [for (final t in _tabs) _tabContent(t, compact: compact)],
      );

  // ---------------------------------------------------------------- Bilgisayar düzeni

  Widget _buildDesktop() {
    return SafeArea(
      child: Column(
        children: [
          _buildTabBar(),
          _buildToolbar(),
          _buildProgress(),
          Expanded(
            child: Stack(
              children: [
                _pages(compact: false),
                if (_showSuggestions)
                  Positioned(
                    top: 6,
                    left: 12,
                    right: 12,
                    child: _suggestionPanel(),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      height: 46,
      decoration: BoxDecoration(
        color: OAColors.bg2,
        border: Border(bottom: BorderSide(color: OAColors.line)),
      ),
      child: Row(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(10, 0, 6, 0),
            child: OAMark(),
          ),
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _tabs.length,
              itemBuilder: (context, i) {
                final t = _tabs[i];
                final selected = i == _current;
                return GestureDetector(
                  onTap: () => _selectTab(i),
                  child: Container(
                    width: 184,
                    margin: EdgeInsets.fromLTRB(2, 8, 0, 0),
                    padding: EdgeInsets.only(left: 14),
                    decoration: BoxDecoration(
                      color: selected ? OAColors.surface : Colors.transparent,
                      border: selected
                          ? Border(
                              top: BorderSide(color: OAColors.border),
                              left: BorderSide(color: OAColors.border),
                              right: BorderSide(color: OAColors.border),
                            )
                          : null,
                      borderRadius:
                          BorderRadius.vertical(top: Radius.circular(12)),
                    ),
                    child: Row(
                      children: [
                        if (t.incognito)
                          Padding(
                            padding: EdgeInsets.only(right: 6),
                            child: Icon(Icons.visibility_off,
                                size: 14, color: OAColors.blue),
                          ),
                        Expanded(
                          child: Text(
                            t.displayTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: selected ? OAColors.text : OAColors.muted,
                            ),
                          ),
                        ),
                        IconButton(
                          iconSize: 14,
                          padding: EdgeInsets.zero,
                          constraints:
                              BoxConstraints(minWidth: 28, minHeight: 28),
                          icon: Icon(Icons.close),
                          onPressed: () => _closeTab(i),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          IconButton(
            tooltip: 'Yeni sekme (Ctrl+T)',
            icon: Icon(Icons.add),
            onPressed: () => _addTab(),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar() {
    final loading = !_tab.showStart && _tab.progress < 1;
    final secure = !_tab.showStart && _tab.url.startsWith('https');
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      decoration: BoxDecoration(
        color: OAColors.surface,
        border: Border(bottom: BorderSide(color: OAColors.border)),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Geri',
            icon: Icon(Icons.arrow_back),
            onPressed: _canBack ? _back : null,
          ),
          IconButton(
            tooltip: 'İleri',
            icon: Icon(Icons.arrow_forward),
            onPressed: _canForward ? _forward : null,
          ),
          IconButton(
            tooltip: loading ? 'Durdur' : 'Yenile',
            icon: Icon(loading ? Icons.close : Icons.refresh),
            onPressed: _tab.showStart ? null : _reloadOrStop,
          ),
          IconButton(
            tooltip: 'Ana sayfa',
            icon: Icon(Icons.home_outlined),
            onPressed: _goHome,
          ),
          Expanded(
            child: TextField(
              controller: _urlCtl,
              focusNode: _urlFocus,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.go,
              autocorrect: false,
              onChanged: _onAddressChanged,
              onSubmitted: _onSubmitted,
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              decoration: InputDecoration(
                isDense: true,
                hintText: '${_engine.name} ile ara veya adres yaz',
                prefixIcon: Icon(
                  secure ? Icons.lock_outline : Icons.search,
                  size: 18,
                  color: secure ? OAColors.green : OAColors.muted,
                ),
                contentPadding: EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Okuma modu',
            icon: const Icon(Icons.chrome_reader_mode_outlined),
            onPressed: _tab.showStart ? null : _toggleReader,
          ),
          IconButton(
            tooltip: _siteBlocking ? 'Reklam engelleme açık' : 'Reklam engelleme kapalı',
            icon: Icon(
              _siteBlocking ? Icons.shield : Icons.shield_outlined,
              color: _siteBlocking ? OAColors.green : null,
            ),
            onPressed: _showAdblockSettings,
          ),
          IconButton(
            tooltip: 'Yer imi',
            icon: Icon(
              _isBookmarked ? Icons.star : Icons.star_border,
              color: _isBookmarked ? OAColors.amber : null,
            ),
            onPressed: _tab.showStart ? null : _toggleBookmark,
          ),
          IconButton(
            tooltip: _account.signedIn ? 'Hesabım: ${_account.user!.name}' : 'Giriş yap',
            icon: OAAvatar(name: _account.user?.name, size: 30),
            onPressed: _openAccount,
          ),
          PopupMenuButton<String>(
            onSelected: _onMenu,
            itemBuilder: (_) => [
              PopupMenuItem(value: 'new', child: Text('Yeni sekme')),
              PopupMenuItem(value: 'incognito', child: Text('Yeni gizli sekme')),
              PopupMenuDivider(),
              PopupMenuItem(value: 'bookmarks', child: Text('Yer imleri')),
              PopupMenuItem(value: 'history', child: Text('Geçmiş')),
              if (!_tab.showStart && _quick.length < kMaxQuickLinks)
                PopupMenuItem(value: 'quick', child: Text('Bu sayfayı hızlı erişime ekle')),
              if (!_tab.showStart) ...[
                PopupMenuDivider(),
                PopupMenuItem(value: 'reader', child: Text('Okuma modu')),
                PopupMenuItem(value: 'translate', child: Text('Türkçeye çevir')),
              ],
              PopupMenuDivider(),
              PopupMenuItem(value: 'adblock', child: Text('Reklam engelleme')),
              PopupMenuItem(value: 'engine', child: Text('Arama motoru')),
              PopupMenuItem(value: 'theme', child: Text('Görünüm: koyu / açık')),
              PopupMenuItem(
                  value: 'account',
                  child: Text(_account.signedIn ? 'Hesabım' : 'OA Labs hesabıyla giriş yap')),
            ],
          ),
        ],
      ),
    );
  }

  void _onMenu(String v) {
    switch (v) {
      case 'new':
        _addTab();
      case 'incognito':
        _addTab(incognito: true);
      case 'bookmarks':
        _showList('Yer imleri', _bookmarks, onClear: () {
          setState(() => _bookmarks.clear());
          _save('bookmarks', _bookmarks);
        });
      case 'history':
        _showList('Geçmiş', _history, onClear: () {
          setState(() => _history.clear());
          _save('history', _history);
        });
      case 'engine':
        _showSearchSettings();
      case 'home':
        _goHome();
      case 'theme':
        _showThemeSettings();
      case 'account':
        _openAccount();
      case 'reader':
        _toggleReader();
      case 'translate':
        _translate();
      case 'adblock':
        _showAdblockSettings();
      case 'qr':
        _scanQr();
      case 'wallpaper':
        _showWallpaperPicker();
      case 'sync':
        _syncNow().then((_) => _toast('Eşitlendi'));
      case 'quick':
        _editQuick(null);
      case 'tabs':
        _showTabSwitcher();
    }
  }

  Widget _buildProgress() {
    if (_tab.showStart || _tab.progress >= 1) return SizedBox(height: 2);
    return SizedBox(
      height: 2,
      child: LinearProgressIndicator(value: _tab.progress),
    );
  }

  // ---------------------------------------------------------------- Telefon düzeni

  Widget _buildMobile() {
    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                _pages(compact: true),
                if (_showSuggestions)
                  Positioned(
                    left: 8,
                    right: 8,
                    bottom: 8,
                    child: _suggestionPanel(),
                  ),
              ],
            ),
          ),
          _buildProgress(),
          _buildBottomBar(),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      decoration: BoxDecoration(
        color: OAColors.surface,
        border: Border(top: BorderSide(color: OAColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(12, 10, 12, 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _editing ? _mobileAddressEditor() : _mobileAddressPill(),
              if (!_editing) ...[
                SizedBox(height: 4),
                _mobileActions(),
              ] else
                SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  /// Düzenlenmiyorken: ortada alan adı, solda kilit, sağda yenile (Safari gibi).
  Widget _mobileAddressPill() {
    final t = _tab;
    final loading = !t.showStart && t.progress < 1;
    final secure = !t.showStart && t.url.startsWith('https');
    return Material(
      color: OAColors.surface2,
      shape: StadiumBorder(side: BorderSide(color: OAColors.border2)),
      child: GestureDetector(
        // Safari gibi: adres çubuğunda sağa-sola kaydırınca sekme değişir.
        onHorizontalDragEnd: (d) {
          final v = d.primaryVelocity ?? 0;
          if (v.abs() < 250 || _tabs.length < 2) return;
          final next = (_current + (v < 0 ? 1 : -1)) % _tabs.length;
          HapticFeedback.selectionClick();
          _selectTab(next < 0 ? next + _tabs.length : next);
        },
        child: InkWell(
        customBorder: StadiumBorder(),
        onTap: _startEditing,
        child: SizedBox(
          height: 48,
          child: Row(
            children: [
              SizedBox(width: 16),
              Icon(
                t.incognito
                    ? Icons.visibility_off
                    : secure
                        ? Icons.lock_outline
                        : Icons.search,
                size: 17,
                color: t.incognito
                    ? OAColors.blue
                    : secure
                        ? OAColors.green
                        : OAColors.muted,
              ),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  t.showStart ? '${_engine.name} ile ara veya adres yaz' : t.host,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: t.showStart ? FontWeight.w400 : FontWeight.w600,
                    color: t.showStart ? OAColors.faint : OAColors.text,
                  ),
                ),
              ),
              if (t.showStart)
                SizedBox(width: 40)
              else
                IconButton(
                  tooltip: loading ? 'Durdur' : 'Yenile',
                  iconSize: 20,
                  icon: Icon(loading ? Icons.close : Icons.refresh),
                  onPressed: _reloadOrStop,
                ),
              SizedBox(width: 4),
            ],
          ),
        ),
      ),
      ),
    );
  }

  Widget _mobileAddressEditor() {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _urlCtl,
            focusNode: _urlFocus,
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.go,
            autocorrect: false,
            onChanged: _onAddressChanged,
            onSubmitted: _onSubmitted,
            style: TextStyle(fontSize: 16),
            decoration: InputDecoration(
              hintText: '${_engine.name} ile ara veya adres yaz',
              fillColor: OAColors.surface2,
              prefixIcon: Icon(Icons.search, size: 18, color: OAColors.muted),
              suffixIcon: IconButton(
                tooltip: 'Temizle',
                icon: Icon(Icons.cancel, size: 18, color: OAColors.faint),
                onPressed: () {
                  _urlCtl.clear();
                  _onAddressChanged('');
                },
              ),
              contentPadding: EdgeInsets.symmetric(vertical: 13),
            ),
          ),
        ),
        if (Platform.isAndroid)
          IconButton(
            tooltip: 'QR kod okut',
            icon: const Icon(Icons.qr_code_scanner),
            onPressed: _scanQr,
          ),
        TextButton(
          onPressed: () {
            _urlFocus.unfocus();
            setState(() {
              _editing = false;
              _showSuggestions = false;
              _urlCtl.text = _addressText(_tab);
            });
          },
          child: Text('İptal', style: TextStyle(fontSize: 16)),
        ),
      ],
    );
  }

  Widget _mobileActions() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        IconButton(
          tooltip: 'Geri',
          icon: Icon(Icons.arrow_back_ios_new, size: 22),
          onPressed: _canBack ? _back : null,
        ),
        IconButton(
          tooltip: 'İleri',
          icon: Icon(Icons.arrow_forward_ios, size: 22),
          onPressed: _canForward ? _forward : null,
        ),
        IconButton(
          tooltip: _tab.showStart ? 'Yer imi' : (_isBookmarked ? 'Yer iminden çıkar' : 'Yer imi ekle'),
          icon: Icon(
            _isBookmarked ? Icons.star : Icons.star_border,
            size: 26,
            color: _isBookmarked ? OAColors.amber : null,
          ),
          onPressed: _tab.showStart ? null : _toggleBookmark,
        ),
        IconButton(
          tooltip: 'Sekmeler',
          onPressed: _showTabSwitcher,
          icon: Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border.all(color: OAColors.text2, width: 2),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Text(
              _tabs.length > 99 ? '99+' : '${_tabs.length}',
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w700, color: OAColors.text2),
            ),
          ),
        ),
        IconButton(
          tooltip: 'Menü',
          icon: Icon(Icons.more_horiz, size: 26),
          onPressed: _showMobileMenu,
        ),
      ],
    );
  }

  void _showMobileMenu() {
    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (ctx) {
        Widget item(IconData icon, String label, String value) => ListTile(
              leading: Icon(icon),
              title: Text(label, style: TextStyle(fontSize: 16)),
              onTap: () {
                Navigator.pop(ctx);
                _onMenu(value);
              },
            );
        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(8, 12, 8, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: OAColors.border2,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              ListTile(
                leading: OAAvatar(name: _account.user?.name, size: 36),
                title: Text(
                  _account.signedIn ? _account.user!.name : 'Giriş yap veya üye ol',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                subtitle: Text(_account.signedIn
                    ? _account.user!.email
                    : 'OA Labs hesabın: şifre yok, e-postana kod gelir'),
                onTap: () {
                  Navigator.pop(ctx);
                  _openAccount();
                },
              ),
              Divider(height: 16),
              item(Icons.add, 'Yeni sekme', 'new'),
              item(Icons.visibility_off_outlined, 'Yeni gizli sekme', 'incognito'),
              item(Icons.home_outlined, 'Başlangıç sayfası', 'home'),
              Divider(height: 16),
              item(Icons.star_border, 'Yer imleri', 'bookmarks'),
              item(Icons.history, 'Geçmiş', 'history'),
              if (Platform.isAndroid) item(Icons.qr_code_scanner, 'QR kod okut', 'qr'),
              if (!_tab.showStart) ...[
                item(Icons.chrome_reader_mode_outlined, 'Okuma modu', 'reader'),
                item(Icons.translate, 'Türkçeye çevir', 'translate'),
              ],
              if (!_tab.showStart && _quick.length < kMaxQuickLinks)
                item(Icons.add_to_home_screen_outlined, 'Bu sayfayı hızlı erişime ekle', 'quick'),
              Divider(height: 16),
              item(_siteBlocking ? Icons.shield : Icons.shield_outlined,
                  'Reklam engelleme: ${_adblockOn ? (_siteBlocking ? 'açık' : 'bu sitede kapalı') : 'kapalı'}', 'adblock'),
              item(Icons.search, 'Arama motoru: ${_engine.name}', 'engine'),
              item(Icons.wallpaper_outlined, 'Başlangıç sayfası arka planı', 'wallpaper'),
              if (_account.signedIn) item(Icons.sync, 'Şimdi eşitle', 'sync'),
              item(OAColors.isDark ? Icons.dark_mode_outlined : Icons.light_mode_outlined,
                  'Görünüm: ${switch (themeModeNotifier.value) { ThemeMode.dark => 'Koyu', ThemeMode.light => 'Açık', ThemeMode.system => 'Sistem' }}',
                  'theme'),
            ],
          ),
        );
      },
    );
  }

  void _showTabSwitcher() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: OAColors.bg,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          return FractionallySizedBox(
            heightFactor: 0.92,
            child: Column(
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(20, 16, 12, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _tabs.length == 1 ? '1 sekme' : '${_tabs.length} sekme',
                          style: oaDisplay(22),
                        ),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: Text('Bitti', style: TextStyle(fontSize: 16)),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: GridView.builder(
                    padding: EdgeInsets.fromLTRB(16, 8, 16, 16),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 0.78,
                    ),
                    itemCount: _tabs.length,
                    itemBuilder: (_, i) => _tabCard(i, ctx, setSheet),
                  ),
                ),
                Container(
                  padding: EdgeInsets.fromLTRB(16, 12, 16, 12),
                  decoration: BoxDecoration(
                    color: OAColors.surface,
                    border: Border(top: BorderSide(color: OAColors.border)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Navigator.pop(ctx);
                            _addTab(incognito: true);
                          },
                          icon: Icon(Icons.visibility_off_outlined, size: 18),
                          label: Text('Gizli'),
                          style: OutlinedButton.styleFrom(minimumSize: Size(0, 48)),
                        ),
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () {
                            Navigator.pop(ctx);
                            _addTab();
                          },
                          icon: Icon(Icons.add, size: 20),
                          label: Text('Yeni sekme'),
                          style: FilledButton.styleFrom(minimumSize: Size(0, 48)),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _tabCard(int i, BuildContext sheetCtx, StateSetter setSheet) {
    final t = _tabs[i];
    final selected = i == _current;
    final letter = t.showStart
        ? 'OA'
        : (t.host.isEmpty ? '?' : t.host[0].toUpperCase());
    return Material(
      color: OAColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(OARadius.lg),
        side: BorderSide(
          color: selected ? OAColors.amber : OAColors.border,
          width: selected ? 2 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          _selectTab(i);
          Navigator.pop(sheetCtx);
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(12, 6, 2, 6),
              child: Row(
                children: [
                  if (t.incognito)
                    Padding(
                      padding: EdgeInsets.only(right: 6),
                      child: Icon(Icons.visibility_off, size: 14, color: OAColors.blue),
                    ),
                  Expanded(
                    child: Text(
                      t.displayTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Sekmeyi kapat',
                    iconSize: 18,
                    visualDensity: VisualDensity.compact,
                    icon: Icon(Icons.close),
                    onPressed: () {
                      _closeTab(i);
                      setSheet(() {});
                    },
                  ),
                ],
              ),
            ),
            Expanded(
              child: Container(
                color: OAColors.bg2,
                alignment: Alignment.center,
                padding: EdgeInsets.all(12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: t.showStart ? OAColors.text : OAColors.surface2,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        letter,
                        style: oaDisplay(t.showStart ? 18 : 22,
                            color: t.showStart ? OAColors.bg : OAColors.text2),
                      ),
                    ),
                    SizedBox(height: 10),
                    Text(
                      t.showStart ? 'Başlangıç' : t.host,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, color: OAColors.muted),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- Öneri listesi

  Widget _suggestionPanel() {
    final q = _urlCtl.text.trim();
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 760),
        child: Material(
          color: OAColors.surface,
          elevation: 12,
          shadowColor: Colors.black,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(OARadius.lg),
            side: BorderSide(color: OAColors.border2),
          ),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: EdgeInsets.all(6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_answer != null) _answerRow(_answer!),
                for (var i = 0; i < _suggestions.length; i++)
                  _suggestionRow(_suggestions[i], q, i == _selected),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Hızlı cevap satırı: hesap makinesi, birim, döviz. Dokununca sonuç panoya kopyalanır.
  Widget _answerRow(SmartAnswer a) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () {
        Clipboard.setData(ClipboardData(text: a.copy ?? a.text));
        _toast('Kopyalandı: ${a.copy ?? a.text}');
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        margin: const EdgeInsets.only(bottom: 4),
        decoration: BoxDecoration(
          color: OAColors.surface2,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(Icons.calculate_outlined, size: 20, color: OAColors.accent),
            const SizedBox(width: 12),
            Expanded(
              child: Text(a.text,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: oaDisplay(20).copyWith(height: 1.2)),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(a.source, style: TextStyle(fontSize: 12, color: OAColors.faint)),
                Text('Kopyalamak için dokun',
                    style: TextStyle(fontSize: 11, color: OAColors.faint)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _suggestionRow(Suggestion s, String q, bool selected) {
    final (IconData icon, String right) = switch (s.kind) {
      SuggestionKind.go => (Icons.arrow_forward, 'Siteye git'),
      SuggestionKind.search => (Icons.search, '${_engine.name} ile ara'),
      SuggestionKind.remote => (Icons.search, ''),
      SuggestionKind.pastSearch => (Icons.history, 'Önceki arama'),
      SuggestionKind.bookmark => (Icons.star, _shortUrl(s.url)),
      SuggestionKind.page => (Icons.public, _shortUrl(s.url)),
    };
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => _pick(s),
      child: Container(
        height: 46,
        padding: EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: selected ? OAColors.surface2 : null,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(icon,
                size: 18,
                color: s.kind == SuggestionKind.go ? OAColors.amber : OAColors.muted),
            SizedBox(width: 12),
            Expanded(child: _highlight(s.label, q)),
            if (right.isNotEmpty) ...[
              SizedBox(width: 12),
              Flexible(
                child: Text(
                  right,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: OAColors.faint),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Yazılan kısmı kalın gösterir.
  Widget _highlight(String label, String q) {
    final i = q.isEmpty ? -1 : label.toLowerCase().indexOf(q.toLowerCase());
    final base = TextStyle(fontSize: 15, color: OAColors.text);
    if (i < 0) {
      return Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: base);
    }
    return Text.rich(
      TextSpan(style: base, children: [
        TextSpan(text: label.substring(0, i)),
        TextSpan(
            text: label.substring(i, i + q.length),
            style: TextStyle(fontWeight: FontWeight.w600)),
        TextSpan(text: label.substring(i + q.length)),
      ]),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  String _shortUrl(String? url) =>
      (url ?? '').replaceFirst(RegExp(r'^https?://(www\.)?'), '');

  // ---------------------------------------------------------------- Web görünümü

  Widget _buildWebView(TabData t) {
    return InAppWebView(
      key: ValueKey(t.id),
      initialUrlRequest: URLRequest(url: WebUri(t.pendingUrl ?? t.url)),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        incognito: t.incognito,
        isInspectable: true,
        supportZoom: true,
        mediaPlaybackRequiresUserGesture: false,
        contentBlockers: _adblockOn ? AdBlock.contentBlockers(_adblockAllow) : [],
        useShouldInterceptRequest: Platform.isWindows && _adblockOn,
      ),
      initialUserScripts: UnmodifiableListView(
          [if (_adblockOn) AdBlock.cosmeticScript(_adblockAllow)]),
      pullToRefreshController: t.pullToRefresh ??= Platform.isAndroid
          ? PullToRefreshController(
              settings: PullToRefreshSettings(
                  color: OAColors.amber, backgroundColor: OAColors.surface),
              onRefresh: () => t.controller?.reload(),
            )
          : null,
      // Windows: her istek burada kontrol edilir; Android'de web motorunun kendi engelleyicisi çalışır.
      shouldInterceptRequest: Platform.isWindows
          ? (c, req) async {
              if (!_adblockOn) return null;
              final pageHost = Uri.tryParse(t.url)?.host ?? '';
              return AdBlock.shouldBlock(req.url, pageHost: pageHost, allowedSites: _adblockAllow)
                  ? AdBlock.emptyResponse()
                  : null;
            }
          : null,
      onWebViewCreated: (c) {
        t.controller = c;
        c.addJavaScriptHandler(
          handlerName: 'oaReaderSize',
          callback: (args) {
            final v = args.isNotEmpty ? args.first : null;
            if (v is num) {
              _readerSize = v.toInt();
              _prefs?.setInt('reader_size', _readerSize);
            }
          },
        );
      },
      onLoadStart: (c, url) {
        if (url == null) return;
        setState(() {
          t.url = url.toString();
          t.progress = 0.05;
          t.coverLoadStarted = true;
        });
        if (t == _tab && !_urlFocus.hasFocus && !t.showStart) _urlCtl.text = t.url;
      },
      onPageCommitVisible: (c, url) => _uncover(t),
      onReceivedError: (c, req, err) {
        if (req.isForMainFrame ?? true) _uncover(t);
        t.pullToRefresh?.endRefreshing();
      },
      onLoadStop: (c, url) async {
        t.pullToRefresh?.endRefreshing();
        if (t.coverLoadStarted) _uncover(t);
        _refreshNavState(t);
        _addHistory(t);
        // Sitede giriş/çıkış yapıldıysa uygulama da öğrensin.
        if (!t.incognito && (url?.host ?? '').endsWith('oalabs.dev')) {
          _account.adoptFromWebView();
        }
      },
      onProgressChanged: (c, p) {
        setState(() => t.progress = p / 100);
        // Yeni sayfanın yarısından fazlası yüklendiyse perdeyi kaldır.
        if (t.coverLoadStarted && p >= 60) _uncover(t);
      },
      onTitleChanged: (c, title) {
        if (title == null || title.isEmpty) return;
        setState(() => t.title = title);
      },
      onUpdateVisitedHistory: (c, url, isReload) {
        if (url == null) return;
        setState(() => t.url = url.toString());
        if (t == _tab && !_urlFocus.hasFocus && !t.showStart) _urlCtl.text = t.url;
        _refreshNavState(t);
      },
      onCreateWindow: (c, action) async {
        // target=_blank bağlantıları yeni sekmede aç
        final u = action.request.url;
        if (u != null) _addTab(url: u.toString(), incognito: t.incognito);
        return false;
      },
      onDownloadStartRequest: (c, req) {
        // TODO: indirme yöneticisi (flutter_downloader / dio)
        _toast('İndirme henüz desteklenmiyor: ${req.suggestedFilename ?? req.url}');
      },
    );
  }

  // ---------------------------------------------------------------- Paneller

  void _showSearchSettings() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          void choose(SearchEngine e) {
            setState(() => _engine = e);
            setSheet(() {});
            _prefs?.setString('engine', e.id);
          }

          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.75,
            builder: (_, scroll) => ListView(
              controller: scroll,
              padding: EdgeInsets.fromLTRB(8, 16, 8, 24),
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 4),
                  child: Text('Arama motoru', style: oaDisplay(22)),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text('Adres çubuğuna yazdığın aramalar buraya gider.',
                      style: TextStyle(color: OAColors.muted)),
                ),
                for (final e in kEngines)
                  ListTile(
                    onTap: () => choose(e),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    leading: Container(
                      width: 34,
                      height: 34,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: e.id == _engine.id ? OAColors.amber : OAColors.surface2,
                        borderRadius: BorderRadius.circular(OARadius.sm),
                      ),
                      child: Text(
                        e.name[0],
                        style: oaDisplay(14,
                            color: e.id == _engine.id
                                ? OAColors.amberInk
                                : OAColors.text2),
                      ),
                    ),
                    title: Text(e.name,
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(e.note),
                    trailing: Icon(
                      e.id == _engine.id
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      color: e.id == _engine.id ? OAColors.amber : OAColors.border2,
                    ),
                  ),
                Divider(height: 24),
                SwitchListTile(
                  value: _suggestOn,
                  activeThumbColor: OAColors.amberInk,
                  activeTrackColor: OAColors.amber,
                  title: Text('Yazarken öneri göster',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text('Adres çubuğunda arama önerileri'),
                  onChanged: (v) {
                    setState(() => _suggestOn = v);
                    setSheet(() {});
                    _prefs?.setBool('suggest', v);
                  },
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(16, 4, 16, 0),
                  child: Text(
                    'Öneriler açıkken yazdıkların, sen Enter\'a basmadan da seçtiğin '
                    'arama motoruna gönderilir. Gizli sekmede arama motorundan öneri '
                    'alınmaz; yalnız yer imlerin önerilir.',
                    style: TextStyle(fontSize: 13, color: OAColors.muted, height: 1.5),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showList(
    String title,
    List<Map<String, String>> items, {
    required VoidCallback onClear,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        builder: (_, scroll) => Column(
          children: [
            ListTile(
              title: Text(title, style: oaDisplay(20)),
              trailing: items.isEmpty
                  ? null
                  : TextButton(
                      onPressed: () {
                        onClear();
                        Navigator.pop(ctx);
                      },
                      child: Text('Temizle'),
                    ),
            ),
            Divider(height: 1),
            Expanded(
              child: items.isEmpty
                  ? Center(
                      child: Text('Burada henüz bir şey yok.',
                          style: TextStyle(color: OAColors.muted)))
                  : ListView.builder(
                      controller: scroll,
                      itemCount: items.length,
                      itemBuilder: (_, i) {
                        final it = items[i];
                        final q = it['q'];
                        return ListTile(
                          dense: true,
                          leading: Icon(q != null ? Icons.search : Icons.public,
                              size: 18),
                          title: Text(it['title'] ?? '',
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text(it['url'] ?? '',
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          onTap: () {
                            Navigator.pop(ctx);
                            if (q != null) {
                              _go(q, forceSearch: true);
                            } else {
                              _go(it['url'] ?? '');
                            }
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
