import 'dart:async';
import 'dart:convert';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'web_env.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'account.dart';
import 'account_sheet.dart';
import 'package:app_links/app_links.dart';

import 'adblock.dart';
import 'downloads.dart';
import 'radio.dart';
import 'updater.dart';
import 'oa_theme.dart';
import 'page_tools.dart';
import 'passwords.dart';
import 'qr_page.dart';
import 'reader.dart';
import 'search.dart';
import 'smart.dart';
import 'start_mobile.dart';
import 'start_page.dart';
import 'wallpaper.dart';

/// Windows'ta tarayıcı olarak bir bağlantıyla açılınca adres argüman olarak gelir.
String? _launchUrl;

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  _launchUrl = args.firstWhere((a) => a.startsWith('http'), orElse: () => '');
  if (_launchUrl!.isEmpty) _launchUrl = null;
  // Ekranın tamamına çiz: saatin olduğu üst şerit ve alttaki çizgi bölgesini uygulama boyar.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  // Tema seçimini açılışta oku; yanlış temada bir an görünmesin.
  try {
    final prefs = await SharedPreferences.getInstance();
    themeModeNotifier.value = themeModeFromString(prefs.getString('theme'));
  } catch (_) {}
  await initWebEnv(); // Windows: Edge ortamı (radyo için sesin kendiliğinden başlamasına izin)
  await initRadioBackground(); // Android: radyo arka planda çalar, bildirimde kontrol edilir
  if (Platform.isWindows) {
    try {
      await windowManager.ensureInitialized(); // videoyu küçük pencerede izleme
    } catch (_) {}
  }
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

  /// Sitenin rengi (theme-color ya da sayfa zemini): telefonda saatin olduğu üst şerit bu renge boyanır.
  Color? siteColor;

  /// Telefonda aşağı kaydırınca alt çubuk incelir; yukarı kaydırınca geri açılır.
  int lastScrollY = 0;
  InAppWebViewController? controller;

  /// Android: sayfayı aşağı çekince yenileme.
  PullToRefreshController? pullToRefresh;

  /// Android: sekme ekranda değilken web görünümü ağaçtan çıkarılır ama sayfa bellekte kalır.
  /// (Arka plandaki web görünümleri Android'de öne çizilebiliyor: başka sekmenin sayfası görünüyordu.)
  InAppWebViewKeepAlive? keepAlive;

  /// Gizli sekme kilidi kapalıyken gizli sekmelerin başlığı da gösterilmez.
  static bool lockedIncognito = false;

  String get displayTitle {
    if (incognito && lockedIncognito) return 'Gizli sekme (kilitli)';
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

class _BrowserPageState extends State<BrowserPage> with WidgetsBindingObserver {
  final List<TabData> _tabs = [];

  /// Windows: OA Tarayıcı açıkken yeniden açılınca (ör. bir bağlantıyla) adres buradan gelir.
  static const _single = MethodChannel('oa/tek_pencere');

  /// Android: resim içinde resim (videoyu küçük pencerede izleme).
  static const _pip = MethodChannel('oa/pip');

  // Sayfada bul
  bool _findOpen = false;
  final TextEditingController _findCtl = TextEditingController();
  final FocusNode _findFocus = FocusNode();
  int _findCount = 0;
  int _findIndex = 0;
  Timer? _findDebounce;

  // Videoyu küçük pencerede izleme
  bool _miniVideo = false;
  Rect? _savedBounds;
  bool _savedMax = false;

  // Gizli sekme kilidi
  bool _incognitoLock = false;
  bool _locked = false;
  bool _unlocking = false;

  // Şifreler
  final PasswordStore _passwords = PasswordStore();
  String? _lastPwPrompt;
  int _current = 0;

  final TextEditingController _urlCtl = TextEditingController();
  final FocusNode _urlFocus = FocusNode();

  /// Telefon düzeninde adres çubuğu düzenleniyor mu? (Düzenlenmiyorken yalnız alan adı görünür.)
  bool _editing = false;

  SharedPreferences? _prefs;
  final OAAccount _account = OAAccount();
  final Downloads _downloads = Downloads();
  final RadioPlayer _radio = RadioPlayer();
  AppLinks? _appLinks;
  StreamSubscription<Uri>? _linkSub;
  Timer? _sessionTimer;

  /// Son kapatılan sekmeler (geri açmak için), en yenisi sonda.
  final List<Map<String, String>> _closedTabs = [];
  List<QuickLink> _quick = List.of(kDefaultQuickLinks);

  // Reklam engelleme
  bool _adblockOn = true;
  Set<String> _adblockAllow = {};

  // Başlangıç sayfası arka planı ve okuma modu yazı boyu
  String _wallpaperId = 'glow';
  Set<String> _hiddenPromos = {};
  String? _wallpaperPath;
  int _readerSize = 19;

  // Eşitleme: her koleksiyonun son yerel değişiklik zamanı
  DateTime _bookmarksUpdated = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  DateTime _quickUpdated = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  Timer? _syncTimer;
  bool _wasSignedIn = false;

  /// Telefonda alt çubuk inceltilmiş mi (sayfa aşağı kaydırıldı).
  bool _barCollapsed = false;

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
    WidgetsBinding.instance.addObserver(this);
    _passwords.load();
    if (Platform.isWindows) WidgetsBinding.instance.addPostFrameCallback((_) => _showLastCrash());
    if (Platform.isWindows) {
      _single.setMethodCallHandler((call) async {
        if (call.method != 'ac' || !mounted) return null;
        final lines = (call.arguments?.toString() ?? '').split('\n');
        final url = lines.firstWhere((a) => a.startsWith('http'), orElse: () => '');
        if (url.isNotEmpty) _addTab(url: url);
        return null;
      });
    }
    if (Platform.isAndroid) {
      _pip.setMethodCallHandler((call) async {
        if (call.method == 'degisti' && call.arguments == false) _exitMiniVideo();
        return null;
      });
    }
    _loadStorage().then((_) {
      _restoreSession();
      _listenLinks();
      Future.delayed(const Duration(seconds: 6), () => _checkUpdate());
    });
    _downloads.addListener(_onAccount);
    _radio.addListener(_onAccount);
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
  }

  /// Yerel bir değişiklikten 2 saniye sonra eşitle (art arda değişiklikler tek istekte gider).
  void _scheduleSync() {
    if (!_account.signedIn) return;
    _syncTimer?.cancel();
    _syncTimer = Timer(const Duration(seconds: 2), _syncNow);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _findDebounce?.cancel();
    _findCtl.dispose();
    _findFocus.dispose();
    _account.removeListener(_onAccount);
    _account.dispose();
    _downloads.removeListener(_onAccount);
    _radio.removeListener(_onAccount);
    _linkSub?.cancel();
    _sessionTimer?.cancel();
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
    await _downloads.init(_prefs!);
    await _radio.init(_prefs!);
    setState(() {
      _bookmarks = _decode(_prefs!.getStringList('bookmarks'));
      _history = _decode(_prefs!.getStringList('history'));
      _engine = engineById(_prefs!.getString('engine'));
      _suggestOn = _prefs!.getBool('suggest') ?? true;
      _adblockOn = _prefs!.getBool('adblock') ?? true;
      _adblockAllow = (_prefs!.getStringList('adblock_allow') ?? []).toSet();
      _wallpaperId = _prefs!.getString('wallpaper') ?? 'glow';
      _hiddenPromos = (_prefs!.getStringList('promo_hidden') ?? []).toSet();
      _wallpaperPath = _prefs!.getString('wallpaper_path');
      _readerSize = _prefs!.getInt('reader_size') ?? 19;
      _incognitoLock = _prefs!.getBool('incognito_lock') ?? false;
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

  // ---------------------------------------------------------------- Sitenin rengi

  /// Sitenin rengi: önce <meta name="theme-color"> (karanlık/aydınlık mod için media'lısı dahil),
  /// yoksa sayfanın zemin rengi; o da saydamsa beyaz (tarayıcıların varsayılan zemini).
  static const _siteColorJs = '''
(function(){
  try {
    var ms = document.querySelectorAll('meta[name="theme-color"]');
    for (var i = 0; i < ms.length; i++) {
      var m = ms[i];
      if (!m.media || window.matchMedia(m.media).matches) { if (m.content) return m.content; }
    }
    var pick = function(el){ if (!el) return null; var c = getComputedStyle(el).backgroundColor;
      return (!c || c === 'transparent' || /rgba\\([^)]*,\\s*0\\)/.test(c)) ? null : c; };
    var top = document.elementFromPoint(window.innerWidth / 2, 2);
    return pick(top) || pick(document.body) || pick(document.documentElement) || '#ffffff';
  } catch (e) { return null; }
})()''';

  Future<void> _readSiteColor(TabData t) async {
    final c = t.controller;
    if (c == null) return;
    try {
      final r = await c.evaluateJavascript(source: _siteColorJs);
      final color = parseCssColor(r?.toString());
      if (color != null && color != t.siteColor && mounted) {
        setState(() => t.siteColor = color);
      }
    } catch (_) {}
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
    _saveSessionSoon();
  }

  void _toast(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(text),
        duration: Duration(milliseconds: 1400),
      ));
  }

  // ----------------------------------------------------------------- Çökme kaydı (Windows)

  /// Uygulama geçen sefer beklenmedik şekilde kapandıysa nedeni gösterilir
  /// (Windows giriş noktası %LOCALAPPDATA%\OA Tarayici\cokme.txt dosyasına yazar).
  Future<void> _showLastCrash() async {
    final base = Platform.environment['LOCALAPPDATA'];
    if (base == null) return;
    final dir = '$base\\OA Tarayici';
    final f = File('$dir\\cokme.txt');
    if (!await f.exists()) return;
    String text;
    try {
      text = utf8.decode(await f.readAsBytes(), allowMalformed: true).trim();
      final shown = File('$dir\\cokme_gosterildi.txt');
      if (await shown.exists()) await shown.delete();
      await f.rename(shown.path);
    } catch (_) {
      return;
    }
    if (!mounted || text.isEmpty) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('OA Tarayıcı geçen sefer beklenmedik şekilde kapandı'),
        content: SizedBox(
          width: 620,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Kapanmanın nedeni aşağıda. Bu bilgiyi geliştiriciye iletirsen sorun düzeltilebilir.',
                    style: TextStyle(color: OAColors.muted)),
                const SizedBox(height: 12),
                SelectableText(text, style: const TextStyle(fontFamily: 'Consolas', fontSize: 12)),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: text));
              _toast('Kopyalandı');
            },
            child: const Text('Kopyala'),
          ),
          FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Tamam')),
        ],
      ),
    );
  }

  // ----------------------------------------------------------------- Gizli sekme kilidi

  void _setLocked(bool v) {
    _locked = v;
    TabData.lockedIncognito = v;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      // Uygulamadan çıkınca gizli sekmeler kilitlenir (küçük pencerede video izlerken değil).
      if (_incognitoLock && !_unlocking && !_miniVideo && _tabs.any((t) => t.incognito) && !_locked) {
        setState(() => _setLocked(true));
      }
    } else if (state == AppLifecycleState.resumed) {
      if (_locked && _tab.incognito) _unlock();
    }
  }

  Future<void> _unlock() async {
    if (_unlocking) return;
    _unlocking = true;
    final ok = await DeviceLock.verify('Gizli sekmeleri açmak için kimliğini doğrula');
    _unlocking = false;
    if (ok && mounted) setState(() => _setLocked(false));
  }

  Future<void> _toggleIncognitoLock() async {
    if (!_incognitoLock) {
      if (!await DeviceLock.supported()) {
        _toast(Platform.isWindows
            ? 'Bunun için Windows Hello (PIN, parmak izi ya da yüz) açık olmalı'
            : 'Bunun için telefonda ekran kilidi (PIN, desen, parmak izi) açık olmalı');
        return;
      }
      if (!await DeviceLock.verify('Gizli sekme kilidini açmak için kimliğini doğrula')) return;
    }
    setState(() => _incognitoLock = !_incognitoLock);
    _prefs?.setBool('incognito_lock', _incognitoLock);
    _toast(_incognitoLock
        ? 'Gizli sekme kilidi açık: uygulamadan çıkınca gizli sekmeler kilitlenir'
        : 'Gizli sekme kilidi kapalı');
  }

  Widget _lockCover() {
    return ColoredBox(
      color: OAColors.bg,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_outline, size: 56, color: OAColors.amber),
              const SizedBox(height: 16),
              Text('Gizli sekmeler kilitli',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: OAColors.text)),
              const SizedBox(height: 8),
              Text(
                Platform.isWindows ? 'Açmak için Windows Hello ile doğrula.' : 'Açmak için parmak izi, yüz ya da ekran kilidiyle doğrula.',
                textAlign: TextAlign.center,
                style: TextStyle(color: OAColors.muted),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                icon: const Icon(Icons.fingerprint),
                label: const Text('Kilidi aç'),
                onPressed: _unlock,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ----------------------------------------------------------------- Sayfada bul

  void _openFind() {
    if (_tab.showStart || _tab.controller == null) {
      _toast('Önce bir sayfa aç');
      return;
    }
    setState(() => _findOpen = true);
    _findCtl.selection = TextSelection(baseOffset: 0, extentOffset: _findCtl.text.length);
    WidgetsBinding.instance.addPostFrameCallback((_) => _findFocus.requestFocus());
    if (_findCtl.text.isNotEmpty) _runFind(_findCtl.text, now: true);
  }

  void _runFind(String q, {bool now = false}) {
    _findDebounce?.cancel();
    _findDebounce = Timer(Duration(milliseconds: now ? 0 : 250), () async {
      final c = _tab.controller;
      if (c == null) return;
      try {
        final r = await c.evaluateJavascript(source: '$kFindJs\nwindow.__oaFind.find(${jsonEncode(q)})');
        final n = r is num ? r.toInt() : 0;
        if (mounted) {
          setState(() {
            _findCount = n;
            _findIndex = n > 0 ? 1 : 0;
          });
        }
      } catch (_) {}
    });
  }

  Future<void> _findStep(int d) async {
    if (_findCount == 0) return;
    final r = await _tab.controller?.evaluateJavascript(source: 'window.__oaFind ? window.__oaFind.go($d) : 0');
    if (r is num && mounted) setState(() => _findIndex = r.toInt());
  }

  void _closeFind({TabData? tab}) {
    if (!_findOpen) return;
    (tab ?? _tab).controller?.evaluateJavascript(source: 'window.__oaFind && window.__oaFind.clear()');
    setState(() {
      _findOpen = false;
      _findCount = 0;
      _findIndex = 0;
    });
  }

  Widget _findBar({required bool top}) {
    final side = BorderSide(color: OAColors.border);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 4, 6, 4),
      decoration: BoxDecoration(
        color: OAColors.surface,
        border: top ? Border(bottom: side) : Border(top: side),
      ),
      child: Row(
        children: [
          Icon(Icons.search, size: 20, color: OAColors.muted),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _findCtl,
              focusNode: _findFocus,
              textInputAction: TextInputAction.search,
              style: TextStyle(color: OAColors.text, fontSize: 15),
              decoration: const InputDecoration.collapsed(hintText: 'Sayfada bul'),
              onChanged: (v) => _runFind(v),
              onSubmitted: (_) {
                _findStep(1);
                _findFocus.requestFocus();
              },
            ),
          ),
          if (_findCtl.text.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(_findCount == 0 ? 'Bulunamadı' : '$_findIndex / $_findCount',
                  style: TextStyle(color: _findCount == 0 ? OAColors.danger : OAColors.muted, fontSize: 13)),
            ),
          IconButton(
            tooltip: 'Önceki',
            icon: const Icon(Icons.keyboard_arrow_up),
            onPressed: _findCount > 0 ? () => _findStep(-1) : null,
          ),
          IconButton(
            tooltip: 'Sonraki',
            icon: const Icon(Icons.keyboard_arrow_down),
            onPressed: _findCount > 0 ? () => _findStep(1) : null,
          ),
          IconButton(tooltip: 'Kapat', icon: const Icon(Icons.close), onPressed: _closeFind),
        ],
      ),
    );
  }

  // ----------------------------------------------------------------- PDF

  Future<void> _savePdf() async {
    final t = _tab;
    final c = t.controller;
    if (t.showStart || c == null) {
      _toast('Önce bir sayfa aç');
      return;
    }
    if (Platform.isAndroid) {
      // Android'in yazdırma ekranı: yazıcı olarak "PDF olarak kaydet" seçilir.
      try {
        await c.printCurrentPage();
      } catch (_) {
        _toast('Yazdırma ekranı açılamadı');
      }
      return;
    }
    try {
      final r = await c.callDevToolsProtocolMethod(
        methodName: 'Page.printToPDF',
        parameters: {'printBackground': true, 'preferCSSPageSize': true},
      );
      final data = r is Map ? r['data']?.toString() : null;
      if (data == null || data.isEmpty) throw Exception('boş');
      final dir = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
      var name = (t.title.isEmpty ? t.host : t.title).replaceAll(RegExp(r'[\\/:*?"<>|\r\n\t]'), ' ').trim();
      if (name.length > 80) name = name.substring(0, 80).trim();
      if (name.isEmpty) name = 'sayfa';
      final sep = Platform.pathSeparator;
      var f = File('${dir.path}$sep$name.pdf');
      for (var n = 2; await f.exists(); n++) {
        f = File('${dir.path}$sep$name ($n).pdf');
      }
      await f.writeAsBytes(base64Decode(data));
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text('PDF kaydedildi: İndirilenler/${f.uri.pathSegments.last}'),
          duration: const Duration(seconds: 5),
          action: SnackBarAction(label: 'Aç', onPressed: () => Process.run('explorer.exe', [f.path])),
        ));
    } catch (_) {
      _toast('PDF kaydedilemedi');
    }
  }

  // ----------------------------------------------------------------- Videoyu küçük pencerede izle

  Future<void> _startMiniVideo() async {
    final t = _tab;
    final c = t.controller;
    if (t.showStart || c == null) {
      _toast('Önce video olan bir sayfa aç');
      return;
    }
    if (_findOpen) _closeFind();
    dynamic r;
    try {
      r = await c.evaluateJavascript(source: kVideoMiniJs);
    } catch (_) {}
    if (r is! List || r.length < 2) {
      _toast('Bu sayfada video bulunamadı');
      return;
    }
    final w = (r[0] is num ? (r[0] as num).toInt() : 16).clamp(1, 10000);
    final h = (r[1] is num ? (r[1] as num).toInt() : 9).clamp(1, 10000);
    if (Platform.isAndroid) {
      setState(() => _miniVideo = true);
      bool ok = false;
      try {
        ok = await _pip.invokeMethod<bool>('gir', {'w': w, 'h': h}) ?? false;
      } catch (_) {}
      if (!ok) {
        await _exitMiniVideo();
        _toast('Bu telefon küçük pencereyi desteklemiyor');
      }
    } else if (Platform.isWindows) {
      try {
        _savedMax = await windowManager.isMaximized();
        if (_savedMax) await windowManager.unmaximize();
        final b = await windowManager.getBounds();
        _savedBounds = b;
        const width = 520.0;
        final height = (width * h / w).clamp(180.0, 900.0) + 32; // + pencere başlığı
        setState(() => _miniVideo = true);
        await windowManager.setAlwaysOnTop(true);
        await windowManager.setBounds(Rect.fromLTWH(
            b.right - width - 16 < 0 ? b.left : b.right - width - 16,
            b.bottom - height - 16 < 0 ? b.top : b.bottom - height - 16,
            width,
            height));
      } catch (_) {
        await _exitMiniVideo();
        _toast('Küçük pencere açılamadı');
      }
    }
  }

  Future<void> _exitMiniVideo() async {
    if (!_miniVideo) return;
    setState(() => _miniVideo = false);
    _tab.controller?.evaluateJavascript(source: kVideoMiniExitJs);
    if (Platform.isWindows) {
      try {
        await windowManager.setAlwaysOnTop(false);
        if (_savedBounds != null) await windowManager.setBounds(_savedBounds!);
        if (_savedMax) await windowManager.maximize();
      } catch (_) {}
    }
  }

  Widget _miniExitButton() {
    return Positioned(
      top: 8,
      right: 8,
      child: Material(
        color: Colors.black54,
        shape: const StadiumBorder(),
        child: IconButton(
          tooltip: 'Küçük pencereden çık',
          icon: const Icon(Icons.open_in_full, color: Colors.white),
          onPressed: _exitMiniVideo,
        ),
      ),
    );
  }

  // ----------------------------------------------------------------- Şifreler

  void _onPasswordSubmitted(TabData t, List<dynamic> args) {
    if (t.incognito || args.length < 2) return;
    final user = args[0]?.toString() ?? '';
    final pass = args[1]?.toString() ?? '';
    if (pass.isEmpty) return;
    final origin = PasswordStore.originOf(t.url);
    if (origin.isEmpty || _passwords.never.contains(origin)) return;
    final existing = _passwords.find(origin, user);
    if (existing != null && existing.pass == pass) {
      _passwords.touch(existing);
      return;
    }
    final key = '$origin|$user|$pass';
    if (_lastPwPrompt == key) return;
    _lastPwPrompt = key;
    _askSavePassword(origin, user, pass, update: existing != null);
  }

  void _askSavePassword(String origin, String user, String pass, {required bool update}) {
    final host = (Uri.tryParse(origin)?.host ?? origin).replaceFirst(RegExp(r'^www\.'), '');
    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.key_outlined, color: OAColors.amber),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(update ? 'Şifre güncellensin mi?' : 'Şifre kaydedilsin mi?',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: OAColors.text)),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text('$host · ${user.isEmpty ? 'kullanıcı adı yok' : user}',
                style: TextStyle(color: OAColors.text2, fontSize: 15)),
            const SizedBox(height: 6),
            Text('Şifre yalnız bu cihazın güvenli deposunda saklanır; bir dahaki girişte kendiliğinden doldurulur.',
                style: TextStyle(color: OAColors.muted, fontSize: 13)),
            const SizedBox(height: 16),
            Row(
              children: [
                if (!update)
                  TextButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _passwords.neverFor(origin);
                    },
                    child: const Text('Bu sitede asla'),
                  ),
                const Spacer(),
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Şimdi değil')),
                const SizedBox(width: 6),
                FilledButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _passwords.upsert(origin, user, pass);
                    _toast(update ? 'Şifre güncellendi' : 'Şifre kaydedildi');
                  },
                  child: Text(update ? 'Güncelle' : 'Kaydet'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Kayıtlı giriş varsa sayfadaki giriş formunu doldurur.
  Future<void> _autofill(TabData t) async {
    if (t.incognito) return;
    final origin = PasswordStore.originOf(t.url);
    if (origin.isEmpty) return;
    final list = _passwords.forOrigin(origin);
    if (list.isEmpty) return;
    final e = list.first;
    // Giriş formu sayfa açıldıktan biraz sonra gelebilir (tek sayfalık uygulamalar).
    for (final wait in const [0, 1500]) {
      if (wait > 0) await Future.delayed(Duration(milliseconds: wait));
      if (PasswordStore.originOf(t.url) != origin) return;
      try {
        final ok = await t.controller?.evaluateJavascript(source: passwordFillJs(e.user, e.pass));
        if (ok == true) {
          if (t == _tab && mounted) _toast('Kayıtlı giriş dolduruldu${e.user.isEmpty ? '' : ': ${e.user}'}');
          return;
        }
      } catch (_) {
        return;
      }
    }
  }

  Future<void> _showPasswords() async {
    if (!await DeviceLock.verify('Kayıtlı şifreleri görmek için kimliğini doğrula')) return;
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => PasswordsSheet(store: _passwords),
    );
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
    _saveSessionSoon();
  }

  void _disposeTab(TabData t) {
    final k = t.keepAlive;
    // Web görünümü ağaçtan çıktıktan sonra bellekteki sayfayı da bırak.
    if (k != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => InAppWebViewController.disposeKeepAlive(k));
    }
  }

  void _closeTab(int i) {
    final closing = _tabs[i];
    if (!closing.incognito && !closing.showStart && closing.url.isNotEmpty) {
      _closedTabs.add({'url': closing.url, 'title': closing.displayTitle});
      if (_closedTabs.length > 10) _closedTabs.removeAt(0);
    }
    _disposeTab(closing);
    _saveSessionSoon();
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
    if (i != _current) _closeFind();
    setState(() {
      _barCollapsed = false;
      _current = i;
      _urlCtl.text = _addressText(_tab);
      _showSuggestions = false;
    });
    _saveSessionSoon();
    if (_locked && _tab.incognito) _unlock();
  }

  void _reopenClosedTab() {
    if (_closedTabs.isEmpty) {
      _toast('Kapatılan sekme yok');
      return;
    }
    final t = _closedTabs.removeLast();
    _addTab(url: t['url']);
  }

  // ---------------------------------------------------------------- Oturum (sekmeleri geri yükleme)

  /// Açık sekmeler (gizli sekmeler hariç) kaydedilir; uygulama yeniden açılınca geri gelir.
  void _saveSessionSoon() {
    _sessionTimer?.cancel();
    _sessionTimer = Timer(const Duration(milliseconds: 600), _saveSession);
  }

  void _saveSession() {
    final tabs = [
      for (final t in _tabs)
        if (!t.incognito && !t.showStart && t.url.startsWith('http'))
          {'url': t.url, 'title': t.displayTitle}
    ];
    final current = _tabs[_current];
    final idx = current.incognito || current.showStart
        ? -1
        : tabs.indexWhere((m) => m['url'] == current.url);
    _prefs?.setString('session', jsonEncode({'tabs': tabs, 'current': idx}));
  }

  void _restoreSession() {
    try {
      final raw = _prefs?.getString('session');
      if (raw == null) return;
      final j = jsonDecode(raw) as Map;
      final list = (j['tabs'] as List).whereType<Map>().toList();
      if (list.isEmpty) return;
      setState(() {
        for (final m in list) {
          final url = m['url'].toString();
          _tabs.add(TabData()
            ..showStart = false
            ..webStarted = true
            ..pendingUrl = url
            ..url = url
            ..title = m['title']?.toString() ?? '');
        }
        // İlk (boş) başlangıç sekmesi kalsın; kaldığın sekme açılsın.
        final cur = j['current'] is int ? j['current'] as int : -1;
        _current = cur >= 0 && cur < list.length ? cur + 1 : 0;
        _urlCtl.text = _addressText(_tab);
      });
    } catch (_) {}
  }

  // ---------------------------------------------------------------- Dışarıdan gelen bağlantılar

  /// Başka bir uygulamada bir bağlantıya dokununca (varsayılan tarayıcıysak) ya da Windows'ta
  /// bağlantıyla açılınca adres yeni sekmede açılır.
  void _listenLinks() {
    if (_launchUrl != null) {
      _addTab(url: _launchUrl);
      _launchUrl = null;
    }
    if (!Platform.isAndroid) return;
    try {
      _appLinks = AppLinks();
      _appLinks!.getInitialLink().then((u) {
        if (u != null && u.scheme.startsWith('http')) _addTab(url: u.toString());
      });
      _linkSub = _appLinks!.uriLinkStream.listen((u) {
        if (u.scheme.startsWith('http') && mounted) _addTab(url: u.toString());
      });
    } catch (_) {}
  }

  // ---------------------------------------------------------------- Güncelleme

  Future<void> _checkUpdate({bool manual = false}) async {
    if (!manual) {
      final last = DateTime.tryParse(_prefs?.getString('update_checked') ?? '');
      if (last != null && DateTime.now().difference(last) < const Duration(hours: 12)) return;
    }
    _prefs?.setString('update_checked', DateTime.now().toIso8601String());
    UpdateInfo? info;
    try {
      info = await Updater.check();
    } catch (_) {
      if (manual) _toast('Güncelleme denetlenemedi. İnternet bağlantını kontrol et.');
      return;
    }
    if (!mounted) return;
    if (info == null) {
      if (manual) _toast('OA Tarayıcı güncel ($appVersion)');
      return;
    }
    final u = info;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        duration: const Duration(seconds: 12),
        content: Text('OA Tarayıcı ${u.version} hazır'),
        action: SnackBarAction(
          label: 'Güncelle',
          textColor: OAColors.accent,
          onPressed: () => _installUpdate(u),
        ),
      ));
  }

  Future<void> _installUpdate(UpdateInfo u) async {
    _toast('Güncelleme indiriliyor…');
    await _downloads.start(u.assetUrl, suggestedName: u.assetName, openWhenDone: true, keepPrivate: true);
  }

  // ---------------------------------------------------------------- İndirmeler ve radyo

  Future<void> _download(String url, {String? name, required TabData from}) async {
    if (!url.startsWith('http')) {
      _toast('Bu dosya türü indirilemiyor');
      return;
    }
    final headers = <String, String>{};
    try {
      final cookies = await oaCookies().getCookies(url: WebUri(url));
      if (cookies.isNotEmpty) headers['Cookie'] = cookies.map((c) => '${c.name}=${c.value}').join('; ');
      if (from.url.startsWith('http')) headers['Referer'] = from.url;
    } catch (_) {}
    final item = await _downloads.start(url, suggestedName: name, headers: headers);
    if (item == null || !mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text('İndiriliyor: ${item.name}'),
        action: SnackBarAction(label: 'İndirilenler', textColor: OAColors.accent, onPressed: _showDownloads),
      ));
  }

  void _showDownloads() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => DownloadsSheet(downloads: _downloads, onToast: _toast),
    );
  }

  void _showRadio() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => RadioSheet(radio: _radio),
    );
  }

  void _showAbout() {
    showAboutDialog(
      context: context,
      applicationName: 'OA Tarayıcı',
      applicationVersion: appVersion,
      applicationIcon: const OAMark(size: 44),
      applicationLegalese: '© 2026 OA Labs · Oğuzhan Aydın',
    );
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
      _barCollapsed = false;
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
          SingleActivator(LogicalKeyboardKey.keyT, control: true, shift: true): _reopenClosedTab,
          SingleActivator(LogicalKeyboardKey.keyJ, control: true): _showDownloads,
          SingleActivator(LogicalKeyboardKey.keyW, control: true): () =>
              _closeTab(_current),
          SingleActivator(LogicalKeyboardKey.keyL, control: true): () =>
              mobile ? _startEditing() : _urlFocus.requestFocus(),
          SingleActivator(LogicalKeyboardKey.keyF, control: true): _openFind,
          SingleActivator(LogicalKeyboardKey.keyP, control: true): _savePdf,
          if (_findOpen) const SingleActivator(LogicalKeyboardKey.escape): _closeFind,
          if (_miniVideo) const SingleActivator(LogicalKeyboardKey.escape): _exitMiniVideo,
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
        // Android'de yalnız görünen sayfanın web görünümü ağaçta durur (keepAlive ile bellekte kalır);
        // Windows'ta gizli web görünümü sorun çıkarmadığı için Offstage ile tutulur.
        if (t.webStarted && Platform.isAndroid && !t.showStart) _buildWebView(t),
        if (t.webStarted && !Platform.isAndroid) Offstage(offstage: t.showStart, child: _buildWebView(t)),
        if (t.webStarted && !t.showStart && t.covering) _loadingCover(t),
        if (t.showStart && compact)
          MobileStartPage(
            incognito: t.incognito,
            engineName: _engine.name,
            quickLinks: _quick,
            onGo: (input) => _go(input),
            onQuickAction: _onQuickAction,
            onQuickAdd: () => _editQuick(null),
            onQuickReorder: _reorderQuick,
            onSearch: _startEditing,
            onCustomize: _showCustomize,
            onAccount: _openAccount,
            onRadio: _showRadio,
            onAdblock: _showAdblockSettings,
            onQr: Platform.isAndroid ? _scanQr : null,
            adblockOn: _adblockOn,
            signedIn: _account.signedIn,
            userName: _account.user?.name,
            hiddenPromos: _hiddenPromos,
            onHidePromo: (id) {
              setState(() => _hiddenPromos.add(id));
              _prefs?.setStringList('promo_hidden', _hiddenPromos.toList());
            },
            wallpaperId: _wallpaperId,
            wallpaperPath: _wallpaperPath,
          )
        else if (t.showStart)
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
        if (t.incognito && _locked) Positioned.fill(child: _lockCover()),
      ],
    );
  }

  Widget _pages({required bool compact}) {
    if (Platform.isAndroid) {
      // Yalnız açık sekme çizilir; diğer sekmelerin sayfaları keepAlive ile bellekte bekler.
      return KeyedSubtree(key: ValueKey(_tab.id), child: _tabContent(_tab, compact: compact));
    }
    return IndexedStack(
      index: _current,
      children: [for (final t in _tabs) _tabContent(t, compact: compact)],
    );
  }

  // ---------------------------------------------------------------- Bilgisayar düzeni

  Widget _buildDesktop() {
    return SafeArea(
      child: Column(
        children: [
          // Küçük pencerede video izlenirken yalnız sayfa görünür. (Sayfanın bulunduğu Expanded
          // anahtarla korunur; üstteki çubuklar kalkınca web görünümü yeniden oluşturulmaz.)
          if (!_miniVideo) ...[
            _buildTabBar(),
            _buildToolbar(),
            if (_findOpen) _findBar(top: true),
            RadioMiniBar(radio: _radio, onOpen: _showRadio),
            _buildProgress(),
          ],
          Expanded(
            key: const ValueKey('sayfalar'),
            child: Stack(
              children: [
                _pages(compact: false),
                // Windows: radyo sayfası burada, 1×1 piksel (bkz. RadioPlayer.host)
                Positioned(left: 0, bottom: 0, child: ListenableBuilder(listenable: _radio, builder: (_, __) => _radio.host())),
                if (_miniVideo) _miniExitButton(),
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
              PopupMenuItem(
                  value: 'downloads',
                  child: Text(_downloads.activeCount > 0
                      ? 'İndirilenler (${_downloads.activeCount} sürüyor)'
                      : 'İndirilenler')),
              if (_closedTabs.isNotEmpty)
                PopupMenuItem(value: 'reopen', child: Text('Kapatılan sekmeyi geri aç (Ctrl+Shift+T)')),
              PopupMenuItem(value: 'radio', child: Text('OA Radyo')),
              if (!_tab.showStart && _quick.length < kMaxQuickLinks)
                PopupMenuItem(value: 'quick', child: Text('Bu sayfayı hızlı erişime ekle')),
              if (!_tab.showStart) ...[
                PopupMenuDivider(),
                PopupMenuItem(value: 'find', child: Text('Sayfada bul (Ctrl+F)')),
                PopupMenuItem(value: 'pdf', child: Text('PDF olarak kaydet (Ctrl+P)')),
                PopupMenuItem(value: 'pip', child: Text('Videoyu küçük pencerede izle')),
                PopupMenuItem(value: 'reader', child: Text('Okuma modu')),
                PopupMenuItem(value: 'translate', child: Text('Türkçeye çevir')),
              ],
              PopupMenuDivider(),
              PopupMenuItem(value: 'passwords', child: Text('Şifreler')),
              PopupMenuItem(
                  value: 'lock',
                  child: Text('Gizli sekme kilidi: ${_incognitoLock ? 'açık' : 'kapalı'}')),
              PopupMenuItem(value: 'adblock', child: Text('Reklam engelleme')),
              PopupMenuItem(value: 'engine', child: Text('Arama motoru')),
              PopupMenuItem(value: 'theme', child: Text('Görünüm: koyu / açık')),
              PopupMenuItem(value: 'update', child: Text('Güncellemeleri denetle')),
              PopupMenuItem(value: 'about', child: Text('Hakkında')),
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
      case 'downloads':
        _showDownloads();
      case 'radio':
        _showRadio();
      case 'reopen':
        _reopenClosedTab();
      case 'update':
        _checkUpdate(manual: true);
      case 'about':
        _showAbout();
      case 'sync':
        _syncNow().then((_) => _toast('Eşitlendi'));
      case 'quick':
        _editQuick(null);
      case 'tabs':
        _showTabSwitcher();
      case 'find':
        _openFind();
      case 'pdf':
        _savePdf();
      case 'pip':
        _startMiniVideo();
      case 'passwords':
        _showPasswords();
      case 'lock':
        _toggleIncognitoLock();
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

  /// Üst şeridin rengi: başlangıç sayfasında uygulamanın zemini, sitede sitenin rengi.
  Color get _topBandColor =>
      _tab.showStart || _tab.siteColor == null ? OAColors.bg : _tab.siteColor!;

  Widget _buildMobile() {
    final band = _topBandColor;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: oaSystemOverlay(OAColors.palette, statusBackground: band),
      child: Column(
        children: [
          // Başlangıç sayfasında arka plan saatin olduğu şeridin altına kadar uzanır.
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            height: (_tab.showStart && !_editing) || _miniVideo ? 0 : MediaQuery.paddingOf(context).top,
            color: band,
          ),
          Expanded(
            key: const ValueKey('sayfalar'),
            child: Stack(
              children: [
                _pages(compact: true),
                Positioned(left: 0, bottom: 0, child: ListenableBuilder(listenable: _radio, builder: (_, __) => _radio.host())),
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
          if (!_miniVideo) ...[
            if (_findOpen && !_editing) _findBar(top: false),
            if (!_editing) RadioMiniBar(radio: _radio, onOpen: _showRadio),
            _buildProgress(),
            _buildBottomBar(),
          ],
        ],
      ),
    );
  }

  bool get _showCollapsed => _barCollapsed && !_editing && !_tab.showStart;

  void _expandBar() {
    if (_barCollapsed) setState(() => _barCollapsed = false);
  }

  /// Telefonda sayfa kaydırılınca alt çubuğu incelt / aç.
  void _onScroll(TabData t, int y) {
    if (t != _tab || !_isMobile(context)) return;
    final dy = y - t.lastScrollY;
    if (dy.abs() < 12) return;
    t.lastScrollY = y;
    final collapse = dy > 0 && y > 80;
    final expand = dy < 0 || y < 40;
    if (collapse && !_barCollapsed) {
      setState(() => _barCollapsed = true);
    } else if (expand && _barCollapsed) {
      setState(() => _barCollapsed = false);
    }
  }

  /// İnce alt çubuk: yalnız kilit ve alan adı; dokununca açılır.
  Widget _collapsedBar() {
    final t = _tab;
    final secure = t.url.startsWith('https');
    return Material(
      color: OAColors.surface,
      child: InkWell(
        onTap: _expandBar,
        child: Container(
          decoration: BoxDecoration(border: Border(top: BorderSide(color: OAColors.border))),
          child: SafeArea(
            top: false,
            child: SizedBox(
              height: 34,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(secure ? Icons.lock_outline : Icons.public,
                      size: 13, color: secure ? OAColors.green : OAColors.muted),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(t.host,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    return AnimatedSize(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      alignment: Alignment.bottomCenter,
      child: _showCollapsed ? _collapsedBar() : _fullBottomBar(),
    );
  }

  Widget _fullBottomBar() {
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
              if (_editing)
                _mobileAddressEditor()
              else if (!_tab.showStart)
                _mobileAddressPill(),
              if (!_editing) ...[
                if (!_tab.showStart) SizedBox(height: 4),
                _tab.showStart ? _mobileStartActions() : _mobileActions(),
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

  /// Başlangıç sayfasındaki alt sıra: arama sayfadaki kutuda olduğundan adres çubuğu yok.
  Widget _mobileStartActions() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        IconButton(
          tooltip: 'İleri',
          icon: const Icon(Icons.arrow_forward_ios, size: 22),
          onPressed: _canForward ? _forward : null,
        ),
        IconButton(
          tooltip: 'Ara',
          icon: const Icon(Icons.search, size: 26),
          onPressed: _startEditing,
        ),
        IconButton(
          tooltip: 'Menü',
          icon: const Icon(Icons.menu, size: 26),
          onPressed: _showMobileMenu,
        ),
        IconButton(
          tooltip: 'Yer imleri',
          icon: const Icon(Icons.bookmarks_outlined, size: 24),
          onPressed: () => _onMenu('bookmarks'),
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
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: OAColors.text2),
            ),
          ),
        ),
      ],
    );
  }

  /// Başlangıç sayfasının sağ üstündeki "Özelleştir" düğmesi.
  void _showCustomize() {
    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      builder: (ctx) {
        Widget item(IconData icon, String label, VoidCallback onTap) => ListTile(
              leading: Icon(icon),
              title: Text(label, style: const TextStyle(fontSize: 16)),
              onTap: () {
                Navigator.pop(ctx);
                onTap();
              },
            );
        return Padding(
          padding: const EdgeInsets.fromLTRB(8, 16, 8, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text('Özelleştir', style: oaDisplay(22)),
              ),
              item(Icons.wallpaper_outlined, 'Arka plan', _showWallpaperPicker),
              item(OAColors.isDark ? Icons.dark_mode_outlined : Icons.light_mode_outlined,
                  'Görünüm: koyu / açık', _showThemeSettings),
              item(Icons.search, 'Arama motoru: ${_engine.name}', _showSearchSettings),
              item(Icons.add_box_outlined, 'Hızlı erişime site ekle', () => _editQuick(null)),
              if (_hiddenPromos.isNotEmpty)
                item(Icons.view_carousel_outlined, 'Gizlenen kartları geri getir', () {
                  setState(() => _hiddenPromos.clear());
                  _prefs?.setStringList('promo_hidden', []);
                }),
            ],
          ),
        );
      },
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
              item(Icons.download_outlined,
                  _downloads.activeCount > 0 ? 'İndirilenler (${_downloads.activeCount} sürüyor)' : 'İndirilenler',
                  'downloads'),
              if (_closedTabs.isNotEmpty) item(Icons.restore, 'Kapatılan sekmeyi geri aç', 'reopen'),
              item(Icons.radio_outlined, 'OA Radyo', 'radio'),
              if (Platform.isAndroid) item(Icons.qr_code_scanner, 'QR kod okut', 'qr'),
              if (!_tab.showStart) ...[
                item(Icons.find_in_page_outlined, 'Sayfada bul', 'find'),
                item(Icons.picture_in_picture_alt_outlined, 'Videoyu küçük pencerede izle', 'pip'),
                item(Icons.picture_as_pdf_outlined, 'Yazdır / PDF olarak kaydet', 'pdf'),
                item(Icons.chrome_reader_mode_outlined, 'Okuma modu', 'reader'),
                item(Icons.translate, 'Türkçeye çevir', 'translate'),
              ],
              if (!_tab.showStart && _quick.length < kMaxQuickLinks)
                item(Icons.add_to_home_screen_outlined, 'Bu sayfayı hızlı erişime ekle', 'quick'),
              Divider(height: 16),
              item(_siteBlocking ? Icons.shield : Icons.shield_outlined,
                  'Reklam engelleme: ${_adblockOn ? (_siteBlocking ? 'açık' : 'bu sitede kapalı') : 'kapalı'}', 'adblock'),
              item(Icons.search, 'Arama motoru: ${_engine.name}', 'engine'),
              item(Icons.key_outlined, 'Şifreler', 'passwords'),
              item(_incognitoLock ? Icons.lock_outline : Icons.lock_open_outlined,
                  'Gizli sekme kilidi: ${_incognitoLock ? 'açık' : 'kapalı'}', 'lock'),
              item(Icons.wallpaper_outlined, 'Başlangıç sayfası arka planı', 'wallpaper'),
              if (_account.signedIn) item(Icons.sync, 'Şimdi eşitle', 'sync'),
              item(Icons.system_update_outlined, 'Güncellemeleri denetle', 'update'),
              item(Icons.info_outline, 'Hakkında · $appVersion', 'about'),
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
      webViewEnvironment: oaWebEnv,
      keepAlive: Platform.isAndroid ? (t.keepAlive ??= InAppWebViewKeepAlive()) : null,
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
      initialUserScripts: UnmodifiableListView([
        if (_adblockOn) AdBlock.cosmeticScript(_adblockAllow),
        // Şifre kaydetme (gizli sekmede değil)
        if (!t.incognito)
          UserScript(
            groupName: 'oa-sifre',
            source: kPasswordCaptureJs,
            injectionTime: UserScriptInjectionTime.AT_DOCUMENT_END,
            forMainFrameOnly: true,
          ),
      ]),
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
        if (!t.incognito) {
          c.addJavaScriptHandler(handlerName: 'oaPassword', callback: (args) => _onPasswordSubmitted(t, args));
        }
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
        t.lastScrollY = 0;
        if (t == _tab && _barCollapsed) setState(() => _barCollapsed = false);
        if (url == null) return;
        setState(() {
          t.url = url.toString();
          t.progress = 0.05;
          t.coverLoadStarted = true;
        });
        if (t == _tab && !_urlFocus.hasFocus && !t.showStart) _urlCtl.text = t.url;
      },
      onPageCommitVisible: (c, url) {
        _uncover(t);
        _readSiteColor(t);
      },
      onScrollChanged: (c, x, y) => _onScroll(t, y),
      onReceivedError: (c, req, err) {
        if (req.isForMainFrame ?? true) _uncover(t);
        t.pullToRefresh?.endRefreshing();
      },
      onLoadStop: (c, url) async {
        t.pullToRefresh?.endRefreshing();
        _readSiteColor(t);
        if (t.coverLoadStarted) _uncover(t);
        _refreshNavState(t);
        _addHistory(t);
        _autofill(t);
        // Sayfa değiştiyse eski arama sonuçları geçersiz: yeniden ara.
        if (_findOpen && t == _tab && _findCtl.text.isNotEmpty) _runFind(_findCtl.text, now: true);
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
      onDownloadStartRequest: (c, req) =>
          _download(req.url.toString(), name: req.suggestedFilename, from: t),
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
