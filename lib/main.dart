import 'dart:async';
import 'dart:convert';
import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';
import 'dart:math' show Random, max, min;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:background_downloader/background_downloader.dart' as bd;
import 'web_env.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'account.dart';
import 'account_sheet.dart';
import 'package:app_links/app_links.dart';

import 'adblock.dart';
import 'downloads.dart';
import 'extras.dart';
import 'markets.dart';
import 'news.dart';
import 'read_later.dart';
import 'tab_groups.dart';
import 'tts.dart';
import 'flow.dart';
import 'games.dart';
import 'radio.dart';
import 'updater.dart';
import 'vault.dart';
import 'oa_theme.dart';
import 'offline_page.dart';
import 'page_tools.dart';
import 'passwords.dart';
import 'qr_page.dart';
import 'reader.dart';
import 'search.dart';
import 'sidebar.dart';
import 'smart.dart';
import 'start_mobile.dart';
import 'start_page.dart';
import 'wallpaper.dart';
import 'weather.dart';

part 'settings_screen.dart';

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
    accentNotifier.value = prefs.getString('accent') ?? 'turuncu';
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
    accentNotifier.addListener(_onTheme);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    themeModeNotifier.removeListener(_onTheme);
    accentNotifier.removeListener(_onTheme);
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
    return withAccent(dark ? kOADark : kOALight, accentById(accentNotifier.value));
  }

  @override
  Widget build(BuildContext context) {
    final p = _palette();
    OAColors.use(p);
    SystemChrome.setSystemUIOverlayStyle(oaSystemOverlay(p));
    return MaterialApp(
      title: 'Pusula Browser',
      debugShowCheckedModeBanner: false,
      theme: buildOATheme(p),
      home: BrowserPage(key: _pageKey),
    );
  }
}

final _pageKey = GlobalKey<_BrowserPageState>();

/// OA hesabıyla eşitlenen öbür cihaz ve açık sekmeleri.
class RemoteDevice {
  RemoteDevice(this.id, this.name, this.platform, this.at, this.tabs);
  final String id;
  final String name;
  final String platform;
  final DateTime at;
  final List<Map<String, String>> tabs;

  static RemoteDevice fromJson(String id, Map m, DateTime at) => RemoteDevice(
        id,
        m['name']?.toString() ?? 'Cihaz',
        m['platform']?.toString() ?? '',
        at,
        [
          for (final t in (m['tabs'] as List? ?? const []).whereType<Map>())
            {'url': t['u']?.toString() ?? '', 'title': t['t']?.toString() ?? ''}
        ],
      );
}

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

  /// Okuma listesinden açılan kayıtlı yazı (adres yerine bu sayfa gösterilir).
  String? pendingHtml;

  /// Sekme grubu (bilgisayar).
  String? groupId;

  /// Sekme uyutma: uzun süre bakılmayan sekmenin sayfası bellekten çıkarılır, dokununca yeniden açılır.
  DateTime lastActive = DateTime.now();
  bool sleeping = false;

  /// Sabitlenmiş sekme: şeridin başında küçük simge, kapatma düğmesi yok, uyutulmaz.
  bool pinned = false;

  /// Açılamayan sayfanın adresi (OA hata sayfası gösterilirken adres çubuğunda bu kalır).
  String? errorUrl;

  /// Sekme önizlemesi için sayfanın küçük resmi (sekmeden ayrılırken alınır).
  Uint8List? thumb;

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

  /// Her değişiklikte artar; açık Ayarlar ekranı kendini yeniler.
  final ValueNotifier<int> _rev = ValueNotifier(0);

  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    _rev.value++;
  }

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

  /// Android: sesli arama (telefonun konuşma tanıma ekranı).
  static const _ses = MethodChannel('oa/ses');

  // Haber akışı, döviz ve altın, okuma listesi
  final NewsService _news = NewsService();
  final MarketService _market = MarketService();
  final GameService _games = GameService();
  bool _showGames = true;
  final ReadingList _reading = ReadingList();
  bool _showNews = true;
  bool _showMarkets = true;

  // Kenar çubuğu (bilgisayar)
  List<SideApp> _sideApps = defaultSideApps();
  bool _sidebarOn = Platform.isWindows;
  String? _sideOpen;
  String? _sideLast;
  final Set<String> _sideLoaded = {};
  final Map<String, int> _sideBadges = {};
  final Map<String, InAppWebViewController> _sideCtl = {};
  double _panelW = 420;
  final TabData _sideTab = TabData();

  // Sesli okuma
  final ReadAloud _tts = ReadAloud();

  // Bölünmüş ekran (bilgisayar): sol ve sağ sekmenin kimliği
  (String, String)? _split;
  double _splitRatio = 0.5;

  // Fare hareketleri (Windows)
  bool _gesturesOn = Platform.isWindows;

  // Sekme uyutma
  int _sleepMinutes = 30;
  Timer? _sleepTimer;

  // Sekme grupları ve dikey sekmeler (bilgisayar)
  final List<TabGroup> _groups = [];
  bool _verticalTabs = false;

  // Çerez pencereleri, sitelere karanlık mod, site başına yakınlaştırma
  bool _cookieOn = true;
  bool _darkAll = false;
  Set<String> _darkSites = {};
  Map<String, int> _siteZoom = {};

  // Eşitleme: bu cihaz, öbür cihazlar, şifre kasası
  final Vault _vault = Vault();
  String _deviceId = '';
  bool _syncTabs = true;
  bool _syncHistory = true;
  List<RemoteDevice> _devices = [];
  String? _lastTabsSig;
  int _inboxSeen = 0;

  // OA Akış
  final ValueNotifier<List<Map>> _flow = ValueNotifier(<Map>[]);
  bool _flowOpen = false;
  Timer? _flowPoll;
  int _historyCleared = 0;

  String get _deviceName => Platform.isAndroid
      ? 'Android telefon'
      : (Platform.localHostname.trim().isEmpty ? 'Windows bilgisayar' : Platform.localHostname.trim());

  // Şifreler
  final PasswordStore _passwords = PasswordStore();

  // Başlangıç sayfasında saat, tarih ve hava durumu
  final WeatherService _wx = WeatherService();
  bool _showClock = true;
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
  Timer? _syncPoll;
  DateTime _lastSyncAt = DateTime.fromMillisecondsSinceEpoch(0);
  bool _appVisible = true;
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
    _passwords.onLocalChange = () {
      if (_vault.enabled) _scheduleSync();
    };
    // Açıkken de ara ara eşitle (öbür cihazda eklenenler gelsin).
    _sleepTimer = Timer.periodic(const Duration(minutes: 1), (_) => _checkSleep());
    _syncPoll = Timer.periodic(const Duration(minutes: 2), (_) {
      if (_account.signedIn && _appVisible) _syncNow();
    });
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
    _reading.addListener(_onAccount);
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
  bool _syncing = false;

  Future<void> _syncNow() async {
    if (_syncing) return; // bir önceki eşitleme sürüyor
    _syncing = true;
    try {
      await _syncOnce();
    } finally {
      _syncing = false;
    }
  }

  Future<void> _syncOnce() async {
    _lastSyncAt = DateTime.now();
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
    try {
      await _syncExtras(server, push);
    } catch (_) {}
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
    _syncPoll?.cancel();
    _flowPoll?.cancel();
    _sleepTimer?.cancel();
    _findCtl.dispose();
    _wx.dispose();
    _news.dispose();
    _market.dispose();
    _games.dispose();
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
    _wx.init(_prefs!);
    _deviceId = _prefs!.getString('device_id') ?? '';
    if (_deviceId.isEmpty) {
      final r = Random.secure();
      _deviceId = List.generate(16, (_) => r.nextInt(16).toRadixString(16)).join();
      _prefs!.setString('device_id', _deviceId);
    }
    _syncTabs = _prefs!.getBool('sync_tabs') ?? true;
    _syncHistory = _prefs!.getBool('sync_history') ?? true;
    _inboxSeen = _prefs!.getInt('inbox_seen') ?? 0;
    try {
      _flow.value = [for (final e in (jsonDecode(_prefs!.getString('flow_log') ?? '[]') as List).whereType<Map>()) e];
    } catch (_) {}
    _historyCleared = _prefs!.getInt('history_cleared') ?? 0;
    await _vault.load();
    _news.init(_prefs!);
    _market.init(_prefs!);
    _games.init(_prefs!);
    _reading.init(_prefs!);
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
      _showClock = _prefs!.getBool('show_clock') ?? true;
      _cookieOn = _prefs!.getBool('cookie_block') ?? true;
      _showNews = _prefs!.getBool('show_news') ?? true;
      _showGames = _prefs!.getBool('show_games') ?? true;
      _showMarkets = _prefs!.getBool('show_markets') ?? true;
      _verticalTabs = _prefs!.getBool('vertical_tabs') ?? false;
      _sidebarOn = _prefs!.getBool('sidebar_on') ?? Platform.isWindows;
      _panelW = (_prefs!.getDouble('panel_w') ?? 420).clamp(320, 760).toDouble();
      _sleepMinutes = _prefs!.getInt('sleep_min') ?? 30;
      _gesturesOn = _prefs!.getBool('gestures') ?? Platform.isWindows;
      try {
        final sa = _prefs!.getString('sidebar_items');
        if (sa != null) {
          _sideApps = (jsonDecode(sa) as List).whereType<Map>().map(SideApp.fromJson).whereType<SideApp>().toList();
        }
      } catch (_) {}
      _darkAll = _prefs!.getBool('dark_all') ?? false;
      _darkSites = (_prefs!.getStringList('dark_sites') ?? []).toSet();
      try {
        _siteZoom = Map<String, int>.from(
            (jsonDecode(_prefs!.getString('site_zoom') ?? '{}') as Map).map((k, v) => MapEntry(k.toString(), (v as num).toInt())));
      } catch (_) {}
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
                SwitchListTile(
                  value: _cookieOn,
                  activeThumbColor: OAColors.amberInk,
                  activeTrackColor: OAColors.amber,
                  title: const Text('Çerez pencerelerini kendiliğinden reddet',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text('"Çerezleri kabul et" pencerelerinde reddet / yalnız gerekli seçilir'),
                  onChanged: (v) {
                    _setCookieBlock(v);
                    setSheet(() {});
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
                const Divider(height: 20),
                StatefulBuilder(
                  builder: (ctx, setD) => SwitchListTile(
                    value: _darkAll,
                    activeThumbColor: OAColors.amberInk,
                    activeTrackColor: OAColors.amber,
                    secondary: const Icon(Icons.contrast),
                    title: const Text('Bütün siteleri koyu göster', style: TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: const Text('Karanlık modu olmayan siteler de koyu görünür'),
                    onChanged: (v) {
                      _setDarkAll(v);
                      setD(() {});
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _openAccount() {
    final mobile = _isMobile(context);
    _account.refreshIfStale(); // hesap menüsü açılırken fotoğraf/ad güncel olsun
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
    entry['at'] = DateTime.now().millisecondsSinceEpoch.toString();
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

  void _toggleClock() {
    setState(() => _showClock = !_showClock);
    _prefs?.setBool('show_clock', _showClock);
  }

  // ----------------------------------------------------------------- Site görünümü: yakınlaştırma, karanlık mod

  bool _isDarkSite(String host) => _darkAll || _darkSites.contains(host);
  int _zoomOf(String host) => _siteZoom[host] ?? 100;

  /// Sayfa açılınca o sitenin yakınlaştırmasını ve karanlık modunu uygular.
  Future<void> _applySiteLook(TabData t) async {
    final c = t.controller;
    if (c == null || t.showStart) return;
    final host = t.host;
    try {
      final z = _zoomOf(host);
      if (z != 100) await c.evaluateJavascript(source: zoomJs(z));
      if (_isDarkSite(host)) await c.evaluateJavascript(source: darkModeJs(true));
    } catch (_) {}
  }

  void _setZoom(int percent) {
    final host = _tab.host;
    if (_tab.showStart || host.isEmpty) return;
    final z = percent.clamp(30, 300);
    setState(() {
      if (z == 100) {
        _siteZoom.remove(host);
      } else {
        _siteZoom[host] = z;
      }
    });
    _prefs?.setString('site_zoom', jsonEncode(_siteZoom));
    _tab.controller?.evaluateJavascript(source: zoomJs(z));
  }

  void _zoomStep(int d) {
    if (_tab.showStart) return;
    const steps = [30, 50, 67, 75, 80, 90, 100, 110, 125, 150, 175, 200, 250, 300];
    final cur = _zoomOf(_tab.host);
    var i = steps.indexWhere((s) => s >= cur);
    if (i < 0) i = steps.length - 1;
    if (steps[i] != cur && d < 0) i++;
    final next = steps[(i + d).clamp(0, steps.length - 1)];
    _setZoom(next);
    _toast('Yakınlaştırma: %$next');
  }

  void _showZoom() {
    if (_tab.showStart) {
      _toast('Önce bir sayfa aç');
      return;
    }
    final host = _tab.host;
    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final z = _zoomOf(host);
          void set(int v) {
            _setZoom(v);
            setSheet(() {});
          }

          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Yakınlaştırma', style: oaDisplay(22)),
                const SizedBox(height: 4),
                Text('$host için hatırlanır', style: TextStyle(color: OAColors.muted)),
                const SizedBox(height: 14),
                Row(children: [
                  IconButton.filledTonal(onPressed: () => set(z - 10), icon: const Icon(Icons.remove)),
                  Expanded(
                    child: Slider(
                      value: z.toDouble().clamp(30, 300),
                      min: 30,
                      max: 300,
                      divisions: 27,
                      label: '%$z',
                      onChanged: (v) => set(v.round()),
                    ),
                  ),
                  IconButton.filledTonal(onPressed: () => set(z + 10), icon: const Icon(Icons.add)),
                ]),
                Row(children: [
                  Text('%$z', style: oaDisplay(26)),
                  const Spacer(),
                  TextButton(onPressed: z == 100 ? null : () => set(100), child: const Text('Sıfırla (%100)')),
                ]),
                if (!Platform.isAndroid)
                  Text('Kısayol: Ctrl + / Ctrl − / Ctrl 0', style: TextStyle(color: OAColors.faint, fontSize: 13)),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _toggleDarkSite() async {
    final t = _tab;
    final host = t.host;
    if (t.showStart || host.isEmpty) {
      _toast('Önce bir sayfa aç');
      return;
    }
    final on = !_isDarkSite(host);
    setState(() {
      if (on) {
        _darkSites.add(host);
      } else {
        _darkSites.remove(host);
      }
    });
    _prefs?.setStringList('dark_sites', _darkSites.toList());
    if (!on && _darkAll) {
      _toast('"Bütün siteleri koyu göster" açık; Görünüm ayarından kapatabilirsin');
      return;
    }
    final r = await t.controller?.evaluateJavascript(source: darkModeJs(on));
    if (on && r == 'zaten') _toast('Bu site zaten koyu');
  }

  Future<void> _setDarkAll(bool v) async {
    setState(() => _darkAll = v);
    _prefs?.setBool('dark_all', v);
    for (final t in _tabs) {
      if (t.showStart) continue;
      try {
        await t.controller?.evaluateJavascript(source: darkModeJs(_isDarkSite(t.host)));
      } catch (_) {}
    }
  }

  // ----------------------------------------------------------------- Çerez pencereleri

  Future<void> _setCookieBlock(bool v) async {
    setState(() => _cookieOn = v);
    _prefs?.setBool('cookie_block', v);
    for (final t in _tabs) {
      try {
        await t.controller?.removeUserScriptsByGroupName(groupName: 'oa-cerez');
        if (v) await t.controller?.addUserScript(userScript: cookieBannerScript(_adblockAllow));
      } catch (_) {}
    }
  }

  // ----------------------------------------------------------------- Sesli arama

  Future<void> _voiceSearch() async {
    try {
      final t = await _ses.invokeMethod<String>('dinle');
      if (t != null && t.trim().isNotEmpty && mounted) {
        _urlFocus.unfocus();
        setState(() {
          _editing = false;
          _showSuggestions = false;
        });
        _go(t.trim());
      }
    } on PlatformException catch (e) {
      _toast(e.message ?? 'Sesli arama açılamadı');
    } catch (_) {
      _toast('Sesli arama açılamadı');
    }
  }

  // ----------------------------------------------------------------- Ekran görüntüsü (Windows)

  Future<void> _fullScreenshot() async {
    final t = _tab;
    final c = t.controller;
    if (t.showStart || c == null) {
      _toast('Önce bir sayfa aç');
      return;
    }
    _toast('Ekran görüntüsü alınıyor…');
    try {
      final m = await c.callDevToolsProtocolMethod(methodName: 'Page.getLayoutMetrics');
      final size = (m is Map ? (m['cssContentSize'] ?? m['contentSize']) : null) as Map?;
      final w = ((size?['width'] as num?) ?? 1280).toDouble();
      final h = (((size?['height'] as num?) ?? 2000).toDouble()).clamp(1.0, 16000.0);
      final r = await c.callDevToolsProtocolMethod(methodName: 'Page.captureScreenshot', parameters: {
        'format': 'png',
        'captureBeyondViewport': true,
        'clip': {'x': 0, 'y': 0, 'width': w, 'height': h, 'scale': 1},
      });
      final data = r is Map ? r['data']?.toString() : null;
      if (data == null || data.isEmpty) throw Exception('boş');
      final dir = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
      final now = DateTime.now();
      String two(int v) => v.toString().padLeft(2, '0');
      final name = 'Ekran görüntüsü ${t.host} ${now.year}-${two(now.month)}-${two(now.day)} ${two(now.hour)}.${two(now.minute)}.${two(now.second)}.png'
          .replaceAll(RegExp(r'[\\/:*?"<>|]'), '-');
      final f = File('${dir.path}${Platform.pathSeparator}$name');
      await f.writeAsBytes(base64Decode(data));
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(h >= 16000 ? 'Kaydedildi (çok uzun sayfa: ilk 16000 piksel): İndirilenler' : 'Tam sayfa ekran görüntüsü İndirilenler klasörüne kaydedildi'),
          duration: const Duration(seconds: 5),
          action: SnackBarAction(label: 'Aç', onPressed: () => Process.run('explorer.exe', [f.path])),
        ));
    } catch (_) {
      _toast('Ekran görüntüsü alınamadı');
    }
  }

  // ----------------------------------------------------------------- İçe aktarma (Chrome, Edge, Firefox)

  void _showImport() {
    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (ctx) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Başka tarayıcıdan içe aktar', style: oaDisplay(22)),
            const SizedBox(height: 6),
            Text('Chrome, Edge ya da Firefox\'tan yer imlerini ve şifreleri tek seferde al.',
                style: TextStyle(color: OAColors.muted)),
            const SizedBox(height: 16),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.star_border),
              title: const Text('Yer imleri (.html dosyası)', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('Chrome: Yer imleri → Yer imi yöneticisi → ⋮ → Yer imlerini dışa aktar'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.pop(ctx);
                _importBookmarks();
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.key_outlined),
              title: const Text('Şifreler (.csv dosyası)', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('Chrome: Google Şifre Yöneticisi → Ayarlar → Şifreleri dışa aktar'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.pop(ctx);
                _importPasswords();
              },
            ),
            const SizedBox(height: 8),
            Text(
              'Şifre dosyası şifreleri açık metin olarak içerir: içe aktardıktan sonra dosyayı silmeni öneririz.',
              style: TextStyle(color: OAColors.faint, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Future<String?> _pickText(List<String> ext) async {
    try {
      final r = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ext, withData: true);
      final f = r?.files.single;
      if (f == null) return null;
      final bytes = f.bytes ?? (f.path != null ? await File(f.path!).readAsBytes() : null);
      if (bytes == null) return null;
      return utf8.decode(bytes, allowMalformed: true);
    } catch (_) {
      _toast('Dosya açılamadı');
      return null;
    }
  }

  Future<void> _importBookmarks() async {
    final text = await _pickText(['html', 'htm']);
    if (text == null) return;
    final list = parseBookmarksHtml(text);
    if (list.isEmpty) {
      _toast('Dosyada yer imi bulunamadı');
      return;
    }
    final have = _bookmarks.map((b) => b['url']).toSet();
    final add = [for (final b in list) if (have.add(b['url'])) b];
    setState(() => _bookmarks.addAll(add));
    _save('bookmarks', _bookmarks);
    _toast(add.isEmpty ? 'Yer imlerinin hepsi zaten vardı' : '${add.length} yer imi içe aktarıldı');
  }

  Future<void> _importPasswords() async {
    final text = await _pickText(['csv']);
    if (text == null) return;
    final list = parsePasswordsCsv(text);
    if (list.isEmpty) {
      _toast('Dosyada şifre bulunamadı (Chrome, Edge ya da Firefox şifre dosyası olmalı)');
      return;
    }
    final n = await _passwords.importMany([
      for (final l in list) (PasswordStore.originOf(l.url), l.user, l.pass),
    ]);
    _toast(n == 0 ? 'Şifrelerin hepsi zaten kayıtlıydı' : '$n şifre içe aktarıldı');
  }

  // ----------------------------------------------------------------- Haber, döviz, okuma listesi

  void _toggleNews() {
    setState(() => _showNews = !_showNews);
    _prefs?.setBool('show_news', _showNews);
  }

  void _toggleGames() {
    setState(() => _showGames = !_showGames);
    _prefs?.setBool('show_games', _showGames);
  }

  void _toggleMarkets() {
    setState(() => _showMarkets = !_showMarkets);
    _prefs?.setBool('show_markets', _showMarkets);
  }

  Future<void> _saveForLater() async {
    final t = _tab;
    final c = t.controller;
    if (t.showStart || c == null) {
      _toast('Önce bir yazı aç');
      return;
    }
    _toast('Kaydediliyor…');
    final r = await _reading.save(c, t.url);
    _toast(switch (r) {
      SaveResult.saved => 'Okuma listesine eklendi; internetsiz de okunur',
      SaveResult.already => 'Bu yazı zaten okuma listende',
      SaveResult.notArticle => 'Bu sayfada kaydedilecek bir yazı bulunamadı',
      SaveResult.failed => 'Kaydedilemedi',
    });
  }

  void _showReadingList() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => ReadingListSheet(list: _reading, onOpen: _openArticle),
    );
  }

  Future<void> _openArticle(SavedArticle a) async {
    final html = await _reading.html(a);
    if (html == null) {
      _toast('Kayıtlı yazı bulunamadı; çevrimiçi sürümü açılıyor');
      _addTab(url: a.url);
      return;
    }
    _reading.markRead(a);
    setState(() {
      final t = TabData()
        ..showStart = false
        ..webStarted = true
        ..pendingHtml = html
        ..pendingUrl = a.url
        ..url = a.url
        ..title = a.title;
      _tabs.add(t);
      _current = _tabs.length - 1;
      _urlCtl.text = _addressText(t);
      _showSuggestions = false;
    });
  }

  // ----------------------------------------------------------------- Sekme grupları ve dikey sekmeler

  TabGroup? _groupOf(TabData t) {
    final id = t.groupId;
    if (id == null) return null;
    for (final g in _groups) {
      if (g.id == id) return g;
    }
    return null;
  }

  /// Sekmeyi grubun öbür sekmelerinin yanına taşır.
  void _moveIntoGroup(TabData t, TabGroup g) {
    final selected = _tab;
    _tabs.remove(t);
    t.groupId = g.id;
    final last = _tabs.lastIndexWhere((x) => x.groupId == g.id);
    if (last >= 0) {
      _tabs.insert(last + 1, t);
    } else {
      _tabs.add(t);
    }
    _current = _tabs.indexOf(selected);
  }

  Future<void> _newGroupFor(TabData t) async {
    final r = await editGroupDialog(context, color: _groups.length % kGroupColors.length);
    if (r == null || !mounted) return;
    final g = TabGroup(id: UniqueKey().toString(), name: r.$1, color: r.$2);
    setState(() {
      _groups.add(g);
      _moveIntoGroup(t, g);
    });
    _saveSessionSoon();
  }

  void _addToGroup(TabData t, TabGroup g) {
    setState(() => _moveIntoGroup(t, g));
    _saveSessionSoon();
  }

  void _ungroupTab(TabData t) {
    setState(() {
      t.groupId = null;
      _groups.removeWhere((g) => !_tabs.any((x) => x.groupId == g.id));
    });
    _saveSessionSoon();
  }

  Future<void> _editGroup(TabGroup g) async {
    final r = await editGroupDialog(context, name: g.name, color: g.color, isNew: false);
    if (r == null) return;
    setState(() {
      g.name = r.$1;
      g.color = r.$2;
    });
    _saveSessionSoon();
  }

  void _toggleGroup(TabGroup g) {
    setState(() {
      g.collapsed = !g.collapsed;
      // Açık sekme daraltılan gruptaysa grubun dışındaki bir sekmeye geç.
      if (g.collapsed && _tab.groupId == g.id) {
        final other = _tabs.indexWhere((x) => x.groupId != g.id);
        if (other >= 0) _current = other;
      }
    });
    _saveSessionSoon();
  }

  void _ungroupAll(TabGroup g) {
    setState(() {
      for (final t in _tabs) {
        if (t.groupId == g.id) t.groupId = null;
      }
      _groups.remove(g);
    });
    _saveSessionSoon();
  }

  void _closeGroup(TabGroup g) {
    final ids = [for (final t in _tabs) if (t.groupId == g.id) t.id];
    for (final id in ids) {
      final i = _tabs.indexWhere((x) => x.id == id);
      if (i >= 0) _closeTab(i);
    }
    setState(() => _groups.remove(g));
  }

  Future<void> _tabMenu(int i, Offset pos) async {
    final t = _tabs[i];
    final g = _groupOf(t);
    final v = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx + 1, pos.dy + 1),
      items: [
        PopupMenuItem(value: 'pin', child: Text(t.pinned ? 'Sabitlemeyi kaldır' : 'Sekmeyi sabitle')),
        if (!t.pinned) const PopupMenuItem(value: 'new', child: Text('Yeni gruba ekle…')),
        for (final x in _groups)
          if (x.id != t.groupId)
            PopupMenuItem(
              value: 'g:${x.id}',
              child: Row(children: [
                CircleAvatar(radius: 6, backgroundColor: x.c),
                const SizedBox(width: 10),
                Text('"${x.name.isEmpty ? 'Adsız grup' : x.name}" grubuna ekle'),
              ]),
            ),
        if (g != null) const PopupMenuItem(value: 'out', child: Text('Gruptan çıkar')),
        const PopupMenuDivider(),
        if (!t.showStart) const PopupMenuItem(value: 'later', child: Text('Sonra oku listesine ekle')),
        if (i != _current && !t.sleeping && !t.showStart) const PopupMenuItem(value: 'sleep', child: Text('Bu sekmeyi uyut')),
        if (i != _current && Platform.isWindows) const PopupMenuItem(value: 'split', child: Text('Açık sekmeyle yan yana göster')),
        if (_split != null && Platform.isWindows) const PopupMenuItem(value: 'unsplit', child: Text('Yan yana görünümü kapat')),
        const PopupMenuItem(value: 'sleepall', child: Text('Diğer sekmeleri uyut')),
        const PopupMenuItem(value: 'close', child: Text('Sekmeyi kapat')),
      ],
    );
    if (v == null || !mounted) return;
    if (v == 'pin') {
      _togglePin(t);
    } else if (v == 'new') {
      _newGroupFor(t);
    } else if (v.startsWith('g:')) {
      final x = _groups.firstWhere((e) => e.id == v.substring(2));
      _addToGroup(t, x);
    } else if (v == 'out') {
      _ungroupTab(t);
    } else if (v == 'later') {
      _selectTab(_tabs.indexOf(t));
      _saveForLater();
    } else if (v == 'split') {
      _splitWith(t);
    } else if (v == 'unsplit') {
      _closeSplit();
    } else if (v == 'sleep') {
      if (!await _sleepTab(t)) _toast('Bu sekme şu an uyutulamıyor (ses ya da video çalıyor olabilir)');
    } else if (v == 'sleepall') {
      _sleepOthers();
    } else if (v == 'close') {
      _closeTab(_tabs.indexOf(t));
    }
  }

  Future<void> _groupMenu(TabGroup g, Offset pos) async {
    final v = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx + 1, pos.dy + 1),
      items: [
        PopupMenuItem(value: 'fold', child: Text(g.collapsed ? 'Grubu genişlet' : 'Grubu daralt')),
        const PopupMenuItem(value: 'edit', child: Text('Adını ve rengini değiştir')),
        const PopupMenuItem(value: 'add', child: Text('Gruba yeni sekme ekle')),
        const PopupMenuItem(value: 'ungroup', child: Text('Grubu dağıt')),
        const PopupMenuItem(value: 'close', child: Text('Gruptaki sekmeleri kapat')),
      ],
    );
    if (v == null || !mounted) return;
    switch (v) {
      case 'fold':
        _toggleGroup(g);
      case 'edit':
        _editGroup(g);
      case 'add':
        _addTab();
        _addToGroup(_tab, g);
      case 'ungroup':
        _ungroupAll(g);
      case 'close':
        _closeGroup(g);
    }
  }

  void _toggleVerticalTabs() {
    setState(() => _verticalTabs = !_verticalTabs);
    _prefs?.setBool('vertical_tabs', _verticalTabs);
  }

  /// Sekme şeridindeki öğeler: grup başlıkları ve sekmeler (daraltılan grupların sekmeleri gizli).
  List<Widget> _tabEntries({required bool vertical}) {
    final out = <Widget>[];
    String? prevGroup;
    for (var i = 0; i < _tabs.length; i++) {
      final t = _tabs[i];
      final g = _groupOf(t);
      if (g != null && g.id != prevGroup) out.add(_groupChip(g, vertical: vertical));
      prevGroup = g?.id;
      if (g != null && g.collapsed && i != _current) continue;
      out.add(_tabChip(i, vertical: vertical));
    }
    return out;
  }

  Widget _groupChip(TabGroup g, {required bool vertical}) {
    final count = _tabs.where((t) => t.groupId == g.id).length;
    final label = Row(
      mainAxisSize: vertical ? MainAxisSize.max : MainAxisSize.min,
      children: [
        Icon(g.collapsed ? Icons.chevron_right : Icons.expand_more, size: 16, color: const Color(0xFF14110A)),
        const SizedBox(width: 2),
        Flexible(
          child: Text(
            g.name.isEmpty ? (g.collapsed ? '$count' : '') : (g.collapsed ? '${g.name} · $count' : g.name),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Color(0xFF14110A), fontSize: 12.5, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
    return GestureDetector(
      onTap: () => _toggleGroup(g),
      onSecondaryTapUp: (d) => _groupMenu(g, d.globalPosition),
      onLongPressStart: (d) => _groupMenu(g, d.globalPosition),
      child: Tooltip(
        message: 'Tıkla: daralt / genişlet · sağ tıkla: grup seçenekleri',
        child: Container(
          margin: vertical ? const EdgeInsets.fromLTRB(8, 10, 8, 4) : const EdgeInsets.fromLTRB(6, 12, 2, 6),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          height: vertical ? 28 : null,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: g.c, borderRadius: BorderRadius.circular(8)),
          child: label,
        ),
      ),
    );
  }

  Widget _tabChip(int i, {required bool vertical}) {
    final t = _tabs[i];
    final selected = i == _current;
    final g = _groupOf(t);
    final row = Row(
      children: [
        if (t.incognito)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Icon(Icons.visibility_off, size: 14, color: OAColors.blue),
          ),
        if (t.sleeping)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Tooltip(message: 'Uykuda: tıklayınca yeniden açılır', child: Icon(Icons.bedtime_outlined, size: 14, color: OAColors.faint)),
          ),
        Expanded(
          child: Text(
            t.displayTitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: selected ? OAColors.text : (t.sleeping ? OAColors.faint : OAColors.muted),
            ),
          ),
        ),
        if (t.pinned)
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: Icon(Icons.push_pin, size: 13, color: OAColors.faint),
          )
        else
          IconButton(
            iconSize: 14,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            icon: const Icon(Icons.close),
            onPressed: () => _closeTab(i),
          ),
      ],
    );
    // Sabitlenmiş sekme yatay şeritte yalnız sitenin simgesi
    if (t.pinned && !vertical) {
      return GestureDetector(
        onTap: () => _selectTab(i),
        onSecondaryTapUp: (d) => _tabMenu(i, d.globalPosition),
        child: Tooltip(
          message: t.displayTitle,
          waitDuration: const Duration(milliseconds: 400),
          child: Container(
            width: 46,
            margin: const EdgeInsets.fromLTRB(2, 8, 0, 0),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? OAColors.surface : Colors.transparent,
              border: selected
                  ? Border(
                      top: BorderSide(color: OAColors.border),
                      left: BorderSide(color: OAColors.border),
                      right: BorderSide(color: OAColors.border),
                    )
                  : null,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Opacity(
              opacity: t.sleeping ? 0.5 : 1,
              child: SiteIcon(url: t.url, letter: t.host.isEmpty ? '•' : t.host[0].toUpperCase(), size: 20),
            ),
          ),
        ),
      );
    }
    final Decoration deco;
    if (vertical) {
      deco = BoxDecoration(
        color: selected ? OAColors.surface : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        border: Border(
          left: BorderSide(color: g?.c ?? (selected ? OAColors.amber : Colors.transparent), width: 3),
        ),
      );
    } else {
      deco = BoxDecoration(
        color: selected ? OAColors.surface : Colors.transparent,
        border: selected
            ? Border(
                top: BorderSide(color: g?.c ?? OAColors.border, width: g != null ? 2 : 1),
                left: BorderSide(color: OAColors.border),
                right: BorderSide(color: OAColors.border),
              )
            : Border(bottom: BorderSide(color: g?.c ?? Colors.transparent, width: 2)),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
      );
    }
    final chip = GestureDetector(
      onTap: () => _selectTab(i),
      onSecondaryTapUp: (d) => _tabMenu(i, d.globalPosition),
      onTertiaryTapUp: (_) => _closeTab(i),
      child: Container(
        width: vertical ? null : 184,
        height: vertical ? 38 : null,
        margin: vertical ? const EdgeInsets.fromLTRB(8, 2, 8, 0) : const EdgeInsets.fromLTRB(2, 8, 0, 0),
        padding: const EdgeInsets.only(left: 12),
        decoration: deco,
        child: row,
      ),
    );
    if (t.showStart || i == _current) return chip;
    // Fareyle üzerine gelince sayfanın küçük resmi
    return Tooltip(
      richMessage: WidgetSpan(child: _tabPreview(t)),
      waitDuration: const Duration(milliseconds: 550),
      preferBelow: !vertical,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: OAColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: OAColors.border2),
        boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 18, offset: Offset(0, 6))],
      ),
      child: chip,
    );
  }

  Widget _verticalTabBar() {
    return Container(
      width: 250,
      decoration: BoxDecoration(
        color: OAColors.bg2,
        border: Border(right: BorderSide(color: OAColors.line)),
      ),
      child: Column(
        children: [
          SizedBox(
            height: 50,
            child: Row(children: [
              const Padding(padding: EdgeInsets.fromLTRB(12, 0, 8, 0), child: OAMark()),
              Expanded(child: Text('Sekmeler · ${_tabs.length}', style: TextStyle(color: OAColors.muted, fontSize: 13))),
              IconButton(
                tooltip: 'Yatay sekmeler',
                icon: const Icon(Icons.view_week_outlined, size: 20),
                onPressed: _toggleVerticalTabs,
              ),
            ]),
          ),
          Expanded(
            child: ListView(padding: const EdgeInsets.only(bottom: 8), children: _tabEntries(vertical: true)),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Yeni sekme'),
                onPressed: () => _addTab(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ----------------------------------------------------------------- Eşitleme: sekmeler, geçmiş, şifreler

  /// Geçmişleri birleştirir: her adresin en yeni ziyareti kalır, silme işaretinden eskiler düşer.
  List<Map<String, String>> _mergeHistory(List<Map<String, String>> local, List<dynamic> remote) {
    var cleared = _historyCleared;
    final byUrl = <String, Map<String, String>>{};
    int at(Map<String, String> e) => int.tryParse(e['at'] ?? '') ?? 0;
    void add(Map<String, String> e) {
      final u = e['url'] ?? '';
      if (u.isEmpty) return;
      final old = byUrl[u];
      if (old == null || at(e) > at(old)) byUrl[u] = e;
    }

    for (final m in remote.whereType<Map>()) {
      final c = int.tryParse(m['clear']?.toString() ?? '');
      if (c != null) {
        cleared = max(cleared, c);
        continue;
      }
      add({for (final e in m.entries) e.key.toString(): e.value.toString()});
    }
    for (final e in local) {
      add(Map<String, String>.from(e));
    }
    if (cleared > _historyCleared) {
      _historyCleared = cleared;
      _prefs?.setInt('history_cleared', cleared);
    }
    final list = byUrl.values.where((e) => at(e) == 0 ? cleared == 0 : at(e) > cleared).toList()
      ..sort((a, b) => at(b).compareTo(at(a)));
    return list.take(300).toList();
  }

  Future<void> _syncExtras(Map<String, SyncItem> server, Map<String, SyncItem> push) async {
    final now = DateTime.now().toUtc();

    // Öbür cihazlardaki sekmeler
    final devs = <RemoteDevice>[];
    server.forEach((k, v) {
      if (!k.startsWith('tabs:') || k == 'tabs:$_deviceId' || v.data.isEmpty) return;
      final m = v.data.first;
      if (m is! Map || now.difference(v.updated) > const Duration(days: 30)) return;
      devs.add(RemoteDevice.fromJson(k.substring(5), m, v.updated));
    });
    devs.sort((a, b) => b.at.compareTo(a.at));
    if (mounted) setState(() => _devices = devs);

    // Bu cihazın sekmeleri
    final mine = server['tabs:$_deviceId'];
    if (_syncTabs) {
      final tabs = [
        for (final t in _tabs)
          if (!t.incognito && !t.showStart && t.url.startsWith('http')) {'u': t.url, 't': t.displayTitle}
      ].take(60).toList();
      final sig = jsonEncode(tabs);
      if (sig != _lastTabsSig || mine == null || now.difference(mine.updated) > const Duration(hours: 6)) {
        push['tabs:$_deviceId'] = SyncItem(now, [
          {'name': _deviceName, 'platform': Platform.isAndroid ? 'android' : 'windows', 'tabs': tabs}
        ]);
        _lastTabsSig = sig;
      }
    } else if (mine != null && mine.data.isNotEmpty) {
      push['tabs:$_deviceId'] = SyncItem(now, []);
    }

    // Bu cihaza gönderilen sekmeler
    final inbox = server['inbox:$_deviceId'];
    if (inbox != null && inbox.data.isNotEmpty) {
      final got = [
        for (final m in inbox.data.whereType<Map>())
          if (((m['at'] as num?)?.toInt() ?? 0) > _inboxSeen) m
      ];
      // Sunucudaki zamandan yalnız 1 ms sonrası: bu arada yeni bir şey gönderildiyse silinmez.
      push['inbox:$_deviceId'] = SyncItem(inbox.updated.toUtc().add(const Duration(milliseconds: 1)), []);
      if (got.isNotEmpty) {
        _inboxSeen = got.map((m) => (m['at'] as num).toInt()).reduce(max);
        _prefs?.setInt('inbox_seen', _inboxSeen);
        await _flowReceive(got);
      }
    }

    // Geçmiş
    if (_syncHistory) {
      final sh = server['history'];
      final merged = _mergeHistory(_history, sh?.data ?? const []);
      String sig(Iterable<dynamic> l) => jsonEncode([for (final e in l.whereType<Map>()) e['url']]);
      if (sig(merged) != sig(_history)) {
        _history = merged;
        _save('history', _history);
      }
      final serverEntries = (sh?.data ?? const []).whereType<Map>().where((m) => m['clear'] == null);
      final serverClear = (sh?.data ?? const []).whereType<Map>().any((m) => m['clear']?.toString() == '$_historyCleared');
      if (sig(merged) != sig(serverEntries) || (_historyCleared > 0 && !serverClear)) {
        push['history'] = SyncItem(now, [
          if (_historyCleared > 0) {'clear': '$_historyCleared'},
          ...merged,
        ]);
      }
    }

    // Şifreler (cihazda şifrelenmiş kasa)
    if (_vault.enabled) {
      final sv = server['vault'];
      Map? remote;
      var problem = false;
      if (sv != null && sv.data.isNotEmpty && sv.data.first is Map) {
        final box = sv.data.first as Map;
        remote = _vault.sameSalt(box) ? await _vault.open(box) : null;
        problem = remote == null;
      }
      if (problem) {
        await _vault.disable();
        _toast('Şifre eşitlemesi başka bir parolayla kurulmuş. Eşitleme ayarlarından parolayı yeniden gir.');
      } else {
        if (remote != null) await _passwords.mergeRemote(remote);
        final local = _passwords.exportData();
        if (remote == null ||
            PasswordStore.canonical(local) != PasswordStore.canonical(Map<String, dynamic>.from(remote))) {
          push['vault'] = SyncItem(now, [await _vault.seal(local)]);
        }
      }
    }
  }

  void _showReceivedTabs(List<Map> got) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(got.length == 1 ? 'Sana bir sekme gönderildi' : 'Sana ${got.length} sekme gönderildi'),
        content: SizedBox(
          width: 420,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            for (final m in got)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.send_to_mobile_outlined),
                title: Text(m['t']?.toString().isNotEmpty == true ? m['t'].toString() : m['u'].toString(),
                    maxLines: 2, overflow: TextOverflow.ellipsis),
                subtitle: Text('${m['from'] ?? 'Öbür cihaz'} · ${Uri.tryParse(m['u'].toString())?.host ?? ''}'),
                onTap: () {
                  Navigator.pop(ctx);
                  _addTab(url: m['u'].toString());
                },
              ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Kapat')),
          if (got.length > 1)
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                for (final m in got) {
                  _addTab(url: m['u'].toString());
                }
              },
              child: const Text('Hepsini aç'),
            ),
        ],
      ),
    );
  }

  String _agoText(DateTime d) {
    final m = DateTime.now().toUtc().difference(d.toUtc()).inMinutes;
    if (m < 2) return 'şimdi';
    if (m < 60) return '$m dk önce';
    if (m < 60 * 24) return '${m ~/ 60} sa önce';
    return '${m ~/ (60 * 24)} gün önce';
  }

  bool _needSignIn(String what) {
    if (_account.signedIn) return false;
    _toast('$what için OA Labs hesabınla giriş yap (bilgisayarda ve telefonda aynı hesap)');
    _openAccount();
    return true;
  }

  Future<void> _showDevices() async {
    if (_needSignIn('Öbür cihazlardaki sekmeleri görmek')) return;
    await _syncNow();
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        maxChildSize: 0.95,
        builder: (ctx, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(8, 16, 8, 24),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Text('Öbür cihazlardaki sekmeler', style: oaDisplay(22)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text('OA hesabınla giriş yaptığın öbür cihazlarda açık olan sekmeler.',
                  style: TextStyle(color: OAColors.muted)),
            ),
            if (_devices.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Henüz başka cihaz yok. Telefonunda ya da bilgisayarında Pusula\'yı açıp aynı hesapla giriş yap.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: OAColors.muted),
                ),
              ),
            for (final d in _devices) ...[
              ListTile(
                leading: Icon(d.platform == 'android' ? Icons.smartphone : Icons.computer, color: OAColors.amber),
                title: Text(d.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text('${d.tabs.length} sekme · ${_agoText(d.at)}'),
              ),
              for (final t in d.tabs)
                ListTile(
                  contentPadding: const EdgeInsets.only(left: 56, right: 16),
                  dense: true,
                  title: Text(t['title']!.isEmpty ? t['url']! : t['title']!, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(Uri.tryParse(t['url']!)?.host ?? '', maxLines: 1),
                  onTap: () {
                    Navigator.pop(ctx);
                    _addTab(url: t['url']);
                  },
                ),
              const Divider(height: 12),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _sendTab() async {
    final t = _tab;
    if (t.showStart || !t.url.startsWith('http')) {
      _toast('Önce göndermek istediğin sayfayı aç');
      return;
    }
    if (_needSignIn('Sekme göndermek')) return;
    if (_devices.isEmpty) await _syncNow();
    if (!mounted) return;
    if (_devices.isEmpty) {
      _toast('Başka cihaz bulunamadı: öbür cihazda Pusula\'da aynı hesapla giriş yap');
      return;
    }
    final d = await showModalBottomSheet<RemoteDevice>(
      context: context,
      useSafeArea: true,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(8, 16, 8, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text('Sekmeyi gönder', style: oaDisplay(22)),
          ),
          for (final d in _devices)
            ListTile(
              leading: Icon(d.platform == 'android' ? Icons.smartphone : Icons.computer),
              title: Text(d.name, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text('Son görülme: ${_agoText(d.at)}'),
              onTap: () => Navigator.pop(ctx, d),
            ),
        ]),
      ),
    );
    if (d == null) return;
    final ok = await _flowPush(FlowDevice(d.id, d.name, d.platform == 'android'), {'u': t.url, 't': t.displayTitle});
    _toast(ok ? '${d.name} cihazına gönderildi; orada Pusula açılınca gelir' : 'Gönderilemedi, internet bağlantını kontrol et');
  }

  void _showSyncSettings() {
    if (_needSignIn('Eşitleme')) return;
    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(8, 16, 8, 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Text('Eşitleme', style: oaDisplay(22)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text('${_account.user?.email ?? ''} hesabıyla giriş yapılan bütün cihazlar eşitlenir. Bu cihaz: $_deviceName',
                  style: TextStyle(color: OAColors.muted)),
            ),
            const ListTile(
              leading: Icon(Icons.check_circle, color: Color(0xFF5BC48C)),
              title: Text('Yer imleri ve hızlı erişim', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text('Her zaman eşitlenir'),
            ),
            SwitchListTile(
              value: _syncTabs,
              activeThumbColor: OAColors.amberInk,
              activeTrackColor: OAColors.amber,
              secondary: const Icon(Icons.tab_outlined),
              title: const Text('Açık sekmeler', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('Öbür cihazların bu cihazdaki sekmeleri görebilsin; sekme gönderme'),
              onChanged: (v) {
                setState(() => _syncTabs = v);
                _prefs?.setBool('sync_tabs', v);
                setS(() {});
                _syncNow();
              },
            ),
            SwitchListTile(
              value: _syncHistory,
              activeThumbColor: OAColors.amberInk,
              activeTrackColor: OAColors.amber,
              secondary: const Icon(Icons.history),
              title: const Text('Geçmiş', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('Gizli sekmeler hiçbir zaman kaydedilmez'),
              onChanged: (v) {
                setState(() => _syncHistory = v);
                _prefs?.setBool('sync_history', v);
                setS(() {});
                _syncNow();
              },
            ),
            ListTile(
              leading: Icon(_vault.enabled ? Icons.lock : Icons.lock_open_outlined,
                  color: _vault.enabled ? OAColors.green : null),
              title: const Text('Şifreler', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(_vault.enabled
                  ? 'Açık · uçtan uca şifreli (eşitleme parolanla)'
                  : 'Kapalı · açmak için bir eşitleme parolası belirle'),
              trailing: TextButton(
                onPressed: () async {
                  if (_vault.enabled) {
                    await _vault.disable();
                  } else {
                    Navigator.pop(ctx);
                    await _enableVault();
                    return;
                  }
                  setS(() {});
                },
                child: Text(_vault.enabled ? 'Kapat' : 'Aç'),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: FilledButton.icon(
                icon: const Icon(Icons.sync),
                label: const Text('Şimdi eşitle'),
                onPressed: () async {
                  await _syncNow();
                  _toast('Eşitlendi');
                },
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Future<void> _enableVault() async {
    final server = await _account.pullSync();
    final sv = server?['vault'];
    final box = (sv != null && sv.data.isNotEmpty && sv.data.first is Map) ? sv.data.first as Map : null;
    if (!mounted) return;
    final p1 = TextEditingController();
    final p2 = TextEditingController();
    final pass = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Şifre eşitleme parolası'),
        content: SizedBox(
          width: 420,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              box == null
                  ? 'Şifrelerin cihazdan bu parolayla şifrelenmiş olarak çıkar; OA Labs dahil kimse içini göremez. '
                      'Öbür cihazında da aynı parolayı yazacaksın. Parolayı unutursan eşitlenen şifreler açılamaz '
                      '(cihazdaki şifrelerin silinmez).'
                  : 'Öbür cihazında şifre eşitlemesi açık. Orada belirlediğin eşitleme parolasını yaz.',
              style: TextStyle(color: OAColors.muted, height: 1.4),
            ),
            const SizedBox(height: 14),
            TextField(controller: p1, obscureText: true, autofocus: true, decoration: const InputDecoration(labelText: 'Eşitleme parolası')),
            if (box == null) ...[
              const SizedBox(height: 10),
              TextField(controller: p2, obscureText: true, decoration: const InputDecoration(labelText: 'Parolayı tekrar yaz')),
            ],
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Vazgeç')),
          FilledButton(
            onPressed: () {
              if (box == null && p1.text != p2.text) {
                ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Parolalar aynı değil')));
                return;
              }
              Navigator.pop(ctx, p1.text);
            },
            child: const Text('Şifre eşitlemeyi aç'),
          ),
        ],
      ),
    );
    if (pass == null || !mounted) return;
    _toast('Anahtar hazırlanıyor…');
    final err = await _vault.enable(pass, box);
    if (err != null) {
      _toast(err);
      return;
    }
    await _syncNow();
    _toast('Şifre eşitlemesi açık');
  }

  // ----------------------------------------------------------------- Sekme uyutma

  int get _sleepingCount => _tabs.where((t) => t.sleeping).length;

  Future<void> _checkSleep() async {
    if (_sleepMinutes <= 0 || !mounted) return;
    final now = DateTime.now();
    for (final t in List.of(_tabs)) {
      if (now.difference(t.lastActive).inMinutes < _sleepMinutes) continue;
      await _sleepTab(t);
    }
  }

  /// Sekmenin sayfasını bellekten çıkarır; sekmeye dönünce sayfa yeniden açılır.
  /// Ses ya da video çalan sekme uyutulmaz.
  Future<bool> _sleepTab(TabData t) async {
    if (t == _tab || t.sleeping || t.pinned || !t.webStarted || t.showStart || t.incognito || t.pendingHtml != null) return false;
    if (!t.url.startsWith('http')) return false;
    try {
      final playing = await t.controller?.evaluateJavascript(
          source: "[].some.call(document.querySelectorAll('video,audio'),function(m){return !m.paused&&!m.muted&&m.currentTime>0})");
      if (playing == true) return false;
    } catch (_) {}
    if (!mounted || t == _tab) return false;
    _disposeTab(t);
    setState(() {
      t
        ..sleeping = true
        ..webStarted = false
        ..pendingUrl = t.url
        ..controller = null
        ..keepAlive = null
        ..pullToRefresh = null;
    });
    return true;
  }

  Future<void> _sleepOthers() async {
    var n = 0;
    for (final t in List.of(_tabs)) {
      if (await _sleepTab(t)) n++;
    }
    _toast(n == 0 ? 'Uyutulacak sekme yok' : '$n sekme uyutuldu; dokununca yeniden açılır');
  }

  void _setSleepMinutes(int m) {
    setState(() => _sleepMinutes = m);
    _prefs?.setInt('sleep_min', m);
  }

  // ----------------------------------------------------------------- Kenar çubuğu (bilgisayar)

  void _saveSideApps() => _prefs?.setString('sidebar_items', jsonEncode(_sideApps.map((e) => e.toJson()).toList()));

  void _toggleSidebar() {
    setState(() {
      _sidebarOn = !_sidebarOn;
      if (!_sidebarOn) _sideOpen = null;
    });
    _prefs?.setBool('sidebar_on', _sidebarOn);
  }

  void _toggleSide(SideApp a) {
    setState(() {
      if (_sideOpen == a.id) {
        _sideOpen = null;
      } else {
        _sideOpen = a.id;
        _sideLast = a.id;
        _sideLoaded.add(a.id);
      }
    });
  }

  void _unloadSide(SideApp a) {
    setState(() {
      _sideLoaded.remove(a.id);
      _sideCtl.remove(a.id);
      _sideBadges.remove(a.id);
      if (_sideOpen == a.id) _sideOpen = null;
      if (_sideLast == a.id) _sideLast = null;
    });
  }

  void _removeSideApp(SideApp a) {
    _unloadSide(a);
    setState(() => _sideApps.removeWhere((x) => x.id == a.id));
    _saveSideApps();
  }

  void _moveSideApp(SideApp a, int d) {
    final i = _sideApps.indexOf(a);
    final j = i + d;
    if (i < 0 || j < 0 || j >= _sideApps.length) return;
    setState(() {
      _sideApps.removeAt(i);
      _sideApps.insert(j, a);
    });
    _saveSideApps();
  }

  Future<void> _sideMenu(SideApp a, Offset pos) async {
    final v = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx + 1, pos.dy + 1),
      items: [
        _mi('tab', Icons.open_in_new, 'Sekmede aç'),
        if (_sideLoaded.contains(a.id) && a.id != kSideRadio) _mi('reload', Icons.refresh, 'Yeniden yükle'),
        if (_sideLoaded.contains(a.id) && a.id != kSideRadio) _mi('unload', Icons.power_settings_new, 'Kapat (bellekten çıkar)'),
        const PopupMenuDivider(),
        _mi('remove', Icons.remove_circle_outline, 'Kenar çubuğundan kaldır'),
      ],
    );
    switch (v) {
      case 'tab':
        _addTab(url: a.url);
      case 'reload':
        _sideCtl[a.id]?.reload();
      case 'unload':
        _unloadSide(a);
      case 'remove':
        _removeSideApp(a);
    }
  }

  Future<void> _addSideApp() async {
    final have = _sideApps.map((e) => e.url).toSet();
    final options = [...defaultSideApps(), ...suggestedSideApps()].where((e) => !have.contains(e.url)).toList();
    final name = TextEditingController();
    final url = TextEditingController();
    final r = await showDialog<SideApp>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Kenar çubuğuna ekle'),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (options.isNotEmpty) ...[
                Text('Öneriler', style: TextStyle(color: OAColors.muted, fontSize: 13)),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final o in options)
                    ActionChip(
                      avatar: SiteIcon(url: o.url, letter: o.name[0], size: 20),
                      label: Text(o.name),
                      onPressed: () => Navigator.pop(ctx, o),
                    ),
                ]),
                const SizedBox(height: 18),
              ],
              Text('Ya da istediğin bir site', style: TextStyle(color: OAColors.muted, fontSize: 13)),
              const SizedBox(height: 8),
              TextField(controller: name, decoration: const InputDecoration(labelText: 'Adı')),
              const SizedBox(height: 8),
              TextField(
                controller: url,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(labelText: 'Adres', hintText: 'https://…'),
              ),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Vazgeç')),
          FilledButton(
            onPressed: () {
              var u = url.text.trim();
              if (u.isEmpty) return;
              if (!u.startsWith('http')) u = 'https://$u';
              final n = name.text.trim().isEmpty ? (Uri.tryParse(u)?.host ?? u) : name.text.trim();
              Navigator.pop(ctx, SideApp('ozel-${DateTime.now().millisecondsSinceEpoch}', n, u));
            },
            child: const Text('Ekle'),
          ),
        ],
      ),
    );
    if (r == null) return;
    setState(() => _sideApps.add(r));
    _saveSideApps();
    _toggleSide(r);
  }

  Widget _sideWebView(SideApp a) {
    // OA Radyo: uygulamanın kendi radyosu (web sayfası değil; aynı çalar, mini çalarla birlikte)
    if (a.id == kSideRadio) return RadioSheet(radio: _radio, embedded: true);
    return InAppWebView(
      key: ValueKey('kenar-${a.id}'),
      webViewEnvironment: oaWebEnv,
      initialUrlRequest: URLRequest(url: WebUri(a.url)),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        mediaPlaybackRequiresUserGesture: false,
        isInspectable: false,
      ),
      onWebViewCreated: (c) => _sideCtl[a.id] = c,
      onTitleChanged: (c, title) {
        final n = unreadFromTitle(title);
        if ((_sideBadges[a.id] ?? 0) != n) setState(() => _sideBadges[a.id] = n);
      },
      onCreateWindow: (c, action) async {
        final u = action.request.url;
        if (u != null) _addTab(url: u.toString());
        return false;
      },
      onPermissionRequest: (c, req) => _onPermissionRequest(_sideTab, req),
      onDownloadStartRequest: (c, req) => _download(req.url.toString(), name: req.suggestedFilename, from: _sideTab),
    );
  }

  /// Açılan panel. Kapatılınca da arkada açık kalır (müzik çalmaya, mesajlar gelmeye devam eder).
  Widget _sidePanel() {
    final open = _sideOpen != null && _sidebarOn && !_miniVideo;
    final loaded = _sideApps.where((a) => _sideLoaded.contains(a.id)).toList();
    final showId = _sideOpen ?? _sideLast;
    final idx = loaded.indexWhere((a) => a.id == showId);
    final app = idx >= 0 ? loaded[idx] : null;
    return Offstage(
      offstage: !open,
      child: SizedBox(
        width: _panelW,
        child: Stack(children: [
          Container(
            decoration: BoxDecoration(
              color: OAColors.bg,
              border: Border(right: BorderSide(color: OAColors.line)),
            ),
            child: Column(children: [
              Container(
                height: 46,
                padding: const EdgeInsets.only(left: 12, right: 4),
                decoration: BoxDecoration(color: OAColors.surface, border: Border(bottom: BorderSide(color: OAColors.border))),
                child: Row(children: [
                  if (app != null && app.id == kSideRadio) Icon(Icons.radio_rounded, size: 22, color: OAColors.amber),
                  if (app != null && app.id != kSideRadio) SiteIcon(url: app.url, letter: app.name[0], size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(app?.name ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
                  IconButton(
                    tooltip: 'Yeniden yükle',
                    iconSize: 18,
                    icon: const Icon(Icons.refresh),
                    onPressed: app == null || app.id == kSideRadio ? null : () => _sideCtl[app.id]?.reload(),
                  ),
                  IconButton(
                    tooltip: 'Sekmede aç',
                    iconSize: 18,
                    icon: const Icon(Icons.open_in_new),
                    onPressed: app == null || app.id == kSideRadio ? null : () => _addTab(url: app.url),
                  ),
                  IconButton(
                    tooltip: 'Paneli kapat',
                    iconSize: 18,
                    icon: const Icon(Icons.chevron_left),
                    onPressed: () => setState(() => _sideOpen = null),
                  ),
                ]),
              ),
              Expanded(
                child: loaded.isEmpty
                    ? const SizedBox.shrink()
                    : IndexedStack(
                        index: idx < 0 ? 0 : idx,
                        children: [for (final a in loaded) KeyedSubtree(key: ValueKey('panel-${a.id}'), child: _sideWebView(a))],
                      ),
              ),
            ]),
          ),
          // Sağ kenardan sürükleyerek genişlik
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            width: 6,
            child: MouseRegion(
              cursor: SystemMouseCursors.resizeLeftRight,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onHorizontalDragUpdate: (d) => setState(() => _panelW = (_panelW + d.delta.dx).clamp(320, 760).toDouble()),
                onHorizontalDragEnd: (_) => _prefs?.setDouble('panel_w', _panelW),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  // ----------------------------------------------------------------- Hata sayfası ve çevrimdışı oyun

  void _showErrorPage(TabData t, String url, WebResourceError err) {
    final kind = '${err.type}'.toUpperCase();
    final d = err.description.toUpperCase();
    // İptal edilen yüklemeler (kullanıcı durdurdu, yönlendirme) hata değildir.
    if (kind.contains('CANCEL') || kind.contains('ABORT') || d.contains('ERR_ABORTED') || d.contains('CANCEL')) return;
    if (!url.startsWith('http')) return;
    final offline = ['HOST_LOOKUP', 'NOT_CONNECTED', 'DISCONNECTED', 'NAME_NOT_RESOLVED', 'INTERNET', 'CANNOT_CONNECT', 'TIMEOUT', 'TIMED_OUT', 'NETWORK']
        .any((k) => kind.contains(k) || d.contains(k));
    t.errorUrl = url;
    t.controller?.loadData(
      data: offlinePageHtml(url: url, detail: err.description, offline: offline),
      baseUrl: WebUri('about:blank'),
    );
    if (mounted) setState(() => t.url = url);
  }

  // ----------------------------------------------------------------- Sabitlenmiş sekmeler

  void _togglePin(TabData t) {
    final selected = _tab;
    setState(() {
      _tabs.remove(t);
      t.pinned = !t.pinned;
      if (t.pinned) t.groupId = null;
      final firstUnpinned = _tabs.indexWhere((x) => !x.pinned);
      _tabs.insert(firstUnpinned < 0 ? _tabs.length : firstUnpinned, t);
      _current = _tabs.indexOf(selected);
    });
    _saveSessionSoon();
    if (t.sleeping) _toast(t.pinned ? 'Sekme sabitlendi' : 'Sabitleme kaldırıldı');
  }

  // ----------------------------------------------------------------- QR ile paylaş

  void _showQrShare() {
    final t = _tab;
    if (t.showStart || !t.url.startsWith('http')) {
      _toast('Önce paylaşmak istediğin sayfayı aç');
      return;
    }
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Telefonla okut'),
        content: SizedBox(
          width: 300,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
              child: QrImageView(data: t.url, size: 240, backgroundColor: Colors.white),
            ),
            const SizedBox(height: 12),
            Text(t.displayTitle, maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center,
                style: TextStyle(color: OAColors.text, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(t.host, style: TextStyle(color: OAColors.muted, fontSize: 13)),
          ]),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: t.url));
              _toast('Bağlantı kopyalandı');
            },
            child: const Text('Bağlantıyı kopyala'),
          ),
          FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Tamam')),
        ],
      ),
    );
  }

  // ----------------------------------------------------------------- Vurgu rengi ve temalar

  void _setAccent(String id) {
    accentNotifier.value = id;
    _prefs?.setString('accent', id);
    setState(() {});
  }

  void _applyPreset(String accent, String wallpaper) {
    _setAccent(accent);
    _setWallpaper(wallpaper);
  }

  void _setGestures(bool v) {
    setState(() => _gesturesOn = v);
    _prefs?.setBool('gestures', v);
    for (final t in _tabs) {
      try {
        t.controller?.removeUserScriptsByGroupName(groupName: 'oa-hareket');
        if (v) t.controller?.addUserScript(userScript: mouseGestureScript());
      } catch (_) {}
    }
  }

  // ----------------------------------------------------------------- Komut kutusu (Ctrl+K)

  static String _norm(String s) => s
      .toLowerCase()
      .replaceAll('ı', 'i')
      .replaceAll('i̇', 'i')
      .replaceAll('ş', 's')
      .replaceAll('ğ', 'g')
      .replaceAll('ü', 'u')
      .replaceAll('ö', 'o')
      .replaceAll('ç', 'c');

  List<(IconData, String, String, VoidCallback)> _commands() {
    void menu(String v) => _onMenu(v);
    final page = !_tab.showStart;
    return [
      (Icons.add, 'Yeni sekme', 'ac', () => _addTab()),
      (Icons.visibility_off_outlined, 'Yeni gizli sekme', 'incognito', () => _addTab(incognito: true)),
      (Icons.star_border, 'Yer imleri', 'bookmark', () => menu('bookmarks')),
      (Icons.history, 'Geçmiş', 'history', () => menu('history')),
      (Icons.download_outlined, 'İndirilenler', 'download', () => menu('downloads')),
      (Icons.bookmark_added_outlined, 'Okuma listesi', 'sonra oku', () => menu('readlist')),
      (Icons.devices_outlined, 'Öbür cihazlardaki sekmeler', 'telefon bilgisayar eşitleme', () => menu('devices')),
      (Icons.radio_outlined, 'OA Radyo', 'muzik', () => menu('radio')),
      if (_closedTabs.isNotEmpty) (Icons.restore, 'Kapatılan sekmeyi geri aç', 'geri getir', () => menu('reopen')),
      (Icons.settings_outlined, 'Ayarlar', 'tercihler', () => _openSettings()),
      for (final sec in _visibleSections) (sec.icon, 'Ayarlar: ${sec.name}', sec.sub, () => _openSettings(sec.id)),
      (Icons.contrast, 'Tema: ${themeModeNotifier.value == ThemeMode.dark ? 'açık temaya geç' : 'koyu temaya geç'}', 'koyu acik gece', () {
        final m = themeModeNotifier.value == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
        themeModeNotifier.value = m;
        _prefs?.setString('theme', themeModeToString(m));
      }),
      for (final a in kAccents) (Icons.palette_outlined, 'Vurgu rengi: ${a.name}', 'renk tema', () => _setAccent(a.id)),
      (Icons.dark_mode_outlined, 'Bütün siteleri koyu göster: ${_darkAll ? 'kapat' : 'aç'}', 'karanlik', () => _setDarkAll(!_darkAll)),
      (Icons.shield_outlined, 'Reklam engelleme: ${_adblockOn ? 'kapat' : 'aç'}', 'reklam', () {
        _adblockOn = !_adblockOn;
        _applyAdblock();
      }),
      if (Platform.isWindows) (Icons.view_sidebar_outlined, 'Kenar çubuğu: ${_sidebarOn ? 'gizle' : 'göster'}', 'whatsapp dock', _toggleSidebar),
      if (Platform.isWindows) (Icons.view_week_outlined, 'Dikey sekmeler: ${_verticalTabs ? 'kapat' : 'aç'}', 'sekme', _toggleVerticalTabs),
      (Icons.bedtime_outlined, 'Diğer sekmeleri uyut', 'bellek performans', _sleepOthers),
      (Icons.delete_sweep_outlined, 'Geçmişi temizle', 'sil', _clearHistory),
      (Icons.file_download_outlined, 'Chrome / Firefox\'tan içe aktar', 'import', _showImport),
      (Icons.key_outlined, 'Şifreler', 'parola', _showPasswords),
      (Icons.system_update_outlined, 'Güncellemeleri denetle', 'surum', () => _checkUpdate(manual: true)),
      if (page) ...[
        (Icons.push_pin_outlined, _tab.pinned ? 'Sekmenin sabitlemesini kaldır' : 'Sekmeyi sabitle', 'pin', () => _togglePin(_tab)),
        (Icons.find_in_page_outlined, 'Sayfada bul', 'ara', () => menu('find')),
        (Icons.qr_code_2, 'QR kod ile telefona aktar', 'paylas', _showQrShare),
        (Icons.send_to_mobile_outlined, 'Bu sekmeyi öbür cihaza gönder', 'paylas', () => menu('send')),
        (Icons.swap_horiz_rounded, 'OA Akış: öbür cihaza not, fotoğraf, dosya gönder', 'akis flow not dosya foto', () => menu('flow')),
        (Icons.bookmark_add_outlined, 'Sonra oku listesine ekle', 'kaydet', () => menu('later')),
        (Icons.chrome_reader_mode_outlined, 'Okuma modu', 'reader', () => menu('reader')),
        (Icons.record_voice_over_outlined, 'Sesli oku', 'tts seslendir dinle oku', () => menu('tts')),
        if (Platform.isWindows)
          (Icons.vertical_split_outlined, _split == null ? 'Yan yana yeni sekme' : 'Yan yana görünümü kapat', 'split bolunmus ekran',
              () => menu(_split == null ? 'splitnew' : 'unsplit')),
        (Icons.translate, 'Türkçeye çevir', 'translate', () => menu('translate')),
        (Icons.picture_as_pdf_outlined, 'PDF olarak kaydet', 'yazdir', () => menu('pdf')),
        if (Platform.isWindows) (Icons.screenshot_monitor_outlined, 'Tam sayfa ekran görüntüsü', 'resim', () => menu('shot')),
        (Icons.zoom_in, 'Yakınlaştırma', 'zoom', () => menu('zoom')),
      ],
      for (var i = 0; i < _tabs.length; i++)
        if (i != _current) (Icons.tab_outlined, 'Sekmeye git: ${_tabs[i].displayTitle}', _tabs[i].host, () => _selectTab(i)),
      if (Platform.isWindows)
        for (final a in _sideApps) (Icons.view_sidebar_outlined, 'Kenar çubuğu: ${a.name}', 'uygulama', () {
          if (!_sidebarOn) _toggleSidebar();
          if (_sideOpen != a.id) _toggleSide(a);
        }),
      for (final b in _bookmarks.take(50)) (Icons.star_border, 'Yer imi: ${b['title'] ?? ''}', b['url'] ?? '', () => _go(b['url'] ?? '')),
    ];
  }

  Future<void> _showCommands() async {
    final all = _commands();
    final ctl = TextEditingController();
    var sel = 0;
    await showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Kapat',
      barrierColor: Colors.black45,
      pageBuilder: (ctx, _, __) => StatefulBuilder(builder: (ctx, setD) {
        final q = _norm(ctl.text.trim());
        final words = q.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
        final hits = [
          for (final c in all)
            if (words.every((w) => _norm('${c.$2} ${c.$3}').contains(w))) c
        ];
        final raw = ctl.text.trim();
        final extra = <(IconData, String, String, VoidCallback)>[
          if (raw.isNotEmpty) (looksLikeUrl(raw) ? Icons.public : Icons.search, looksLikeUrl(raw) ? 'Git: $raw' : '"$raw" için ${_engine.name} ile ara', '', () => _go(raw)),
        ];
        final list = [...(hits.length > 9 ? hits.sublist(0, 9) : hits), ...extra];
        if (sel >= list.length) sel = list.isEmpty ? 0 : list.length - 1;
        void run(int i) {
          if (i < 0 || i >= list.length) return;
          Navigator.pop(ctx);
          list[i].$4();
        }

        return Align(
          alignment: const Alignment(0, -0.6),
          child: Material(
            color: OAColors.surface,
            elevation: 12,
            borderRadius: BorderRadius.circular(18),
            child: SizedBox(
              width: min(600, MediaQuery.sizeOf(ctx).width - 32),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Focus(
                  onKeyEvent: (_, e) {
                    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
                    if (e.logicalKey == LogicalKeyboardKey.arrowDown) {
                      setD(() => sel = (sel + 1) % max(1, list.length));
                      return KeyEventResult.handled;
                    }
                    if (e.logicalKey == LogicalKeyboardKey.arrowUp) {
                      setD(() => sel = (sel - 1 + list.length) % max(1, list.length));
                      return KeyEventResult.handled;
                    }
                    if (e.logicalKey == LogicalKeyboardKey.enter || e.logicalKey == LogicalKeyboardKey.numpadEnter) {
                      run(sel);
                      return KeyEventResult.handled;
                    }
                    if (e.logicalKey == LogicalKeyboardKey.escape) {
                      Navigator.pop(ctx);
                      return KeyEventResult.handled;
                    }
                    return KeyEventResult.ignored;
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: TextField(
                      controller: ctl,
                      autofocus: true,
                      style: TextStyle(color: OAColors.text, fontSize: 16),
                      decoration: InputDecoration(
                        hintText: 'Bir komut, sekme, ayar ya da arama yaz…',
                        prefixIcon: Icon(Icons.bolt, color: OAColors.amber),
                        fillColor: OAColors.bg2,
                      ),
                      onChanged: (_) => setD(() => sel = 0),
                    ),
                  ),
                ),
                if (list.isNotEmpty) Divider(height: 1, color: OAColors.line),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 440),
                  child: ListView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    itemCount: list.length,
                    itemBuilder: (_, i) => Material(
                      color: i == sel ? OAColors.amber.withValues(alpha: 0.14) : Colors.transparent,
                      child: ListTile(
                        dense: true,
                        leading: Icon(list[i].$1, size: 20, color: i == sel ? OAColors.accent : OAColors.text2),
                        title: Text(list[i].$2, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: OAColors.text, fontSize: 14.5)),
                        trailing: i == sel ? Text('Enter', style: TextStyle(color: OAColors.faint, fontSize: 12)) : null,
                        onTap: () => run(i),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                  child: Text('↑ ↓ seç · Enter çalıştır · Esc kapat', style: TextStyle(color: OAColors.faint, fontSize: 12)),
                ),
              ]),
            ),
          ),
        );
      }),
    );
  }

  // ----------------------------------------------------------------- OA Akış

  void _flowSave() {
    final l = _flow.value;
    final keep = l.length > 150 ? l.sublist(l.length - 150) : l;
    _prefs?.setString('flow_log', jsonEncode(keep));
  }

  void _flowAdd(Map m) {
    final copy = Map<String, dynamic>.from(m)..remove('d');
    _flow.value = [..._flow.value, copy];
    _flowSave();
  }

  /// Bir kaydı öbür cihazın gelen kutusuna yazar.
  Future<bool> _flowPush(FlowDevice d, Map item) async {
    final server = await _account.pullSync();
    if (server == null) return false;
    final entry = <String, dynamic>{
      ...Map<String, dynamic>.from(item)..remove('p'),
      'from': _deviceName,
      'at': DateTime.now().millisecondsSinceEpoch,
    };
    final list = [...?server['inbox:${d.id}']?.data.whereType<Map>(), entry];
    // En çok 20 kayıt ve ~900 KB: eskiler düşer (alıcı açılmadıysa)
    while (list.length > 20 || (list.length > 1 && jsonEncode(list).length > 900000)) {
      list.removeAt(0);
    }
    final r = await _account.pushSync({'inbox:${d.id}': SyncItem(DateTime.now().toUtc(), list)});
    if (r == null) return false;
    _flowAdd({...entry, 'p': item['p'], 'out': true, 'to': d.name});
    return true;
  }

  List<FlowDevice> get _flowDevices => [for (final d in _devices) FlowDevice(d.id, d.name, d.platform == 'android')];

  /// Gelen dosyayı İndirilenler'e kaydeder; kaydın yolunu döndürür.
  Future<String?> _flowSaveFile(Map m) async {
    try {
      final bytes = base64Decode(m['d'].toString());
      final dir = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
      var name = (m['n']?.toString() ?? 'dosya').replaceAll(RegExp(r'[\\/:*?"<>|\r\n\t]'), '-').trim();
      if (name.isEmpty) name = 'dosya';
      final dot = name.lastIndexOf('.');
      final base = dot > 0 ? name.substring(0, dot) : name;
      final ext = dot > 0 ? name.substring(dot) : '';
      final sep = Platform.pathSeparator;
      var f = File('${dir.path}$sep$name');
      for (var n = 2; await f.exists(); n++) {
        f = File('${dir.path}$sep$base ($n)$ext');
      }
      await f.writeAsBytes(bytes);
      if (Platform.isAndroid) {
        // Telefonun İndirilenler klasöründe de görünsün (uygulamadaki kopya akışta gösterilir)
        try {
          final tmp = await getTemporaryDirectory();
          final c = await f.copy('${tmp.path}$sep${f.uri.pathSegments.last}');
          await bd.FileDownloader().moveFileToSharedStorage(c.path, bd.SharedStorage.downloads);
        } catch (_) {}
      }
      return f.path;
    } catch (_) {
      return null;
    }
  }

  void _flowOpenFile(String path) {
    if (Platform.isWindows) {
      Process.run('explorer.exe', [path]);
    } else {
      bd.FileDownloader().openFile(filePath: path);
    }
  }

  /// Senkronda gelen kutusundan alınan kayıtlar.
  Future<void> _flowReceive(List<Map> got) async {
    final tabs = <Map>[];
    var extra = 0;
    for (final m in got) {
      final e = Map<String, dynamic>.from(m);
      if (flowKind(e) == 'file' && e['d'] != null) e['p'] = await _flowSaveFile(e);
      _flowAdd(e);
      if (!e.containsKey('k')) {
        tabs.add(e); // eski "sekme gönder" kaydı
      } else {
        extra++;
      }
    }
    if (!mounted || _flowOpen) return;
    if (tabs.isNotEmpty) _showReceivedTabs(tabs);
    if (extra > 0) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(extra == 1 ? 'OA Akış: öbür cihazdan yeni bir şey geldi' : 'OA Akış: öbür cihazdan $extra yeni şey geldi'),
          duration: const Duration(seconds: 6),
          action: SnackBarAction(label: 'Göster', onPressed: () => _showFlow()),
        ));
    }
  }

  Future<void> _showFlow({String? text}) async {
    if (_needSignIn('OA Akış')) return;
    if (_devices.isEmpty) await _syncNow();
    if (!mounted || _flowOpen) return;
    _flowOpen = true;
    // Akış açıkken gelenler hemen görünsün diye sık sık bakılır
    _flowPoll?.cancel();
    _flowPoll = Timer.periodic(const Duration(seconds: 8), (_) {
      if (_account.signedIn) _syncNow();
    });
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: OAColors.bg,
      constraints: const BoxConstraints(maxWidth: 680),
      builder: (ctx) => FractionallySizedBox(
        heightFactor: 0.88,
        child: FlowSheet(
          log: _flow,
          devices: _flowDevices,
          initialText: text,
          onSend: _flowPush,
          onOpenUrl: (u) {
            Navigator.pop(ctx);
            _addTab(url: u);
          },
          onOpenFile: _flowOpenFile,
          onClear: () {
            _flow.value = [];
            _flowSave();
          },
        ),
      ),
    );
    _flowOpen = false;
    _flowPoll?.cancel();
    _flowPoll = null;
  }

  // ----------------------------------------------------------------- Sekme önizlemesi

  Future<void> _captureThumb(TabData t) async {
    final c = t.controller;
    if (c == null || t.showStart || t.sleeping || t.errorUrl != null) return;
    try {
      if (Platform.isWindows) {
        final m = await c.callDevToolsProtocolMethod(methodName: 'Page.getLayoutMetrics');
        final vp = m is Map ? (m['cssLayoutViewport'] ?? m['layoutViewport']) : null;
        final w = (vp is Map ? (vp['clientWidth'] as num?) : null)?.toDouble() ?? 1280;
        final h = (vp is Map ? (vp['clientHeight'] as num?) : null)?.toDouble() ?? 800;
        final r = await c.callDevToolsProtocolMethod(methodName: 'Page.captureScreenshot', parameters: {
          'format': 'jpeg',
          'quality': 55,
          'clip': {'x': 0, 'y': 0, 'width': w, 'height': h, 'scale': 400 / w},
        });
        final data = r is Map ? r['data']?.toString() : null;
        if (data != null) t.thumb = base64Decode(data);
      } else {
        final b = await c.takeScreenshot(
          screenshotConfiguration: ScreenshotConfiguration(compressFormat: CompressFormat.JPEG, quality: 40),
        );
        if (b != null) t.thumb = b;
      }
    } catch (_) {}
  }

  Widget _tabPreview(TabData t) {
    return SizedBox(
      width: 260,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text(t.displayTitle,
            maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: OAColors.text, fontWeight: FontWeight.w600, fontSize: 13)),
        const SizedBox(height: 2),
        Text(t.sleeping ? '${t.host} · uykuda' : t.host, style: TextStyle(color: OAColors.muted, fontSize: 12)),
        if (t.thumb != null && !t.incognito) ...[
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.memory(t.thumb!,
                width: 260, height: 150, fit: BoxFit.cover, alignment: Alignment.topCenter, cacheWidth: 520, gaplessPlayback: true),
          ),
        ],
      ]),
    );
  }

  // ----------------------------------------------------------------- Bölünmüş ekran (bilgisayar)

  void _splitWith(TabData other) {
    final cur = _tab;
    if (identical(other, cur)) return;
    setState(() {
      _split = (cur.id, other.id);
      if (other.sleeping) {
        other
          ..sleeping = false
          ..webStarted = true;
      }
    });
  }

  void _closeSplit() => setState(() => _split = null);

  /// Bölünmüş ekranda tıklanan tarafı etkin sekme yapar (adres çubuğu ona geçer).
  void _focusPane(TabData t) {
    final i = _tabs.indexOf(t);
    if (i < 0 || i == _current) return;
    setState(() {
      _current = i;
      t.lastActive = DateTime.now();
      _urlCtl.text = _addressText(t);
    });
  }

  // ----------------------------------------------------------------- Sesli okuma

  Future<void> _readAloud() async {
    final t = _tab;
    final c = t.controller;
    if (t.showStart || c == null) {
      _toast('Önce okunacak bir sayfa aç');
      return;
    }
    try {
      final ready = await c.evaluateJavascript(source: 'typeof Readability === "function"');
      if (ready != true) await c.evaluateJavascript(source: await rootBundle.loadString('assets/readability.js'));
      final r = await c.evaluateJavascript(source: r"""
(function(){
  var t = '', title = document.title;
  try {
    var a = new Readability(document.cloneNode(true), { charThreshold: 300 }).parse();
    if (a && a.textContent && a.textContent.trim().length > 200) { t = a.textContent; title = a.title || title; }
  } catch (e) {}
  if (!t) t = (document.body && document.body.innerText) || '';
  return JSON.stringify({ title: title, text: t.slice(0, 60000) });
})()
""");
      final j = jsonDecode(r.toString()) as Map;
      final text = j['text']?.toString() ?? '';
      if (text.trim().length < 20) {
        _toast('Bu sayfada okunacak yazı bulunamadı');
        return;
      }
      final title = (j['title']?.toString() ?? '').trim();
      if (_radio.playing) await _radio.toggle(); // radyo susar
      await _tts.start(title.isEmpty ? text : '$title. $text', title.isEmpty ? t.displayTitle : title);
    } catch (_) {
      _toast('Sesli okuma başlatılamadı');
    }
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
        title: const Text('Pusula geçen sefer beklenmedik şekilde kapandı'),
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
    _appVisible = state == AppLifecycleState.resumed || state == AppLifecycleState.inactive;
    // Öbür cihazdaki değişiklikler: uygulamaya dönünce eşitle.
    if (state == AppLifecycleState.resumed &&
        _account.signedIn &&
        DateTime.now().difference(_lastSyncAt) > const Duration(seconds: 20)) {
      _syncNow();
    }
    // Sitede değişen hesap bilgileri (ad, profil fotoğrafı) da gelsin.
    if (state == AppLifecycleState.resumed) _account.refreshIfStale();
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
      // Yeni sekme açık sekmenin hemen yanına gelir (en sona değil).
      final at = _tabs.isEmpty ? 0 : (_current + 1).clamp(0, _tabs.length);
      if (_tabs.isNotEmpty && _current < _tabs.length) {
        final g = _tabs[_current].groupId;
        // Bir grubun ortasına açılırsa o gruba katılır; grup bölünmesin.
        if (g != null && at < _tabs.length && _tabs[at].groupId == g) t.groupId = g;
        _tabs[_current].lastActive = DateTime.now();
      }
      _tabs.insert(at, t);
      _current = at;
      _urlCtl.text = _addressText(t);
      _showSuggestions = false;
    });
    _saveSessionSoon();
    // Boş yeni sekmede imleç doğrudan arama kutusunda: tıklamadan yazılır.
    if (url == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_isMobile(context)) {
          _startEditing();
        } else {
          _urlFocus.requestFocus();
          _urlCtl.selection = TextSelection(baseOffset: 0, extentOffset: _urlCtl.text.length);
        }
      });
    }
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
    if (i != _current && _current < _tabs.length) _captureThumb(_tabs[_current]);
    // Bölünmüş ekrandaki sekmelerden biri değilse yan yana görünüm kapanır.
    final sp = _split;
    if (sp != null && i < _tabs.length && _tabs[i].id != sp.$1 && _tabs[i].id != sp.$2) _split = null;
    if (i != _current) _closeFind();
    final now = DateTime.now();
    if (_current < _tabs.length) _tabs[_current].lastActive = now;
    final next = _tabs[i];
    next.lastActive = now;
    if (next.sleeping) {
      next
        ..sleeping = false
        ..webStarted = true
        ..pendingUrl = next.url
        ..covering = true
        ..coverLoadStarted = false;
    }
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
          {'url': t.url, 'title': t.displayTitle, if (t.groupId != null) 'g': t.groupId!, if (t.pinned) 'p': '1'}
    ];
    final current = _tabs[_current];
    final idx = current.incognito || current.showStart
        ? -1
        : tabs.indexWhere((m) => m['url'] == current.url);
    final usedGroups = {for (final t in tabs) t['g']};
    _prefs?.setString('session', jsonEncode({
      'tabs': tabs,
      'current': idx,
      'groups': [for (final g in _groups) if (usedGroups.contains(g.id)) g.toJson()],
    }));
  }

  void _restoreSession() {
    try {
      final raw = _prefs?.getString('session');
      if (raw == null) return;
      final j = jsonDecode(raw) as Map;
      final list = (j['tabs'] as List).whereType<Map>().toList();
      if (list.isEmpty) return;
      setState(() {
        for (final g in (j['groups'] as List? ?? const []).whereType<Map>()) {
          final tg = TabGroup.fromJson(g);
          if (tg != null) _groups.add(tg);
        }
        for (final m in list) {
          final url = m['url'].toString();
          final gid = m['g']?.toString();
          _tabs.add(TabData()
            ..showStart = false
            ..webStarted = true
            ..pendingUrl = url
            ..url = url
            ..groupId = _groups.any((g) => g.id == gid) ? gid : null
            ..pinned = m['p'] != null
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
        if (u != null) _onLink(u);
      });
      _linkSub = _appLinks!.uriLinkStream.listen(_onLink);
    } catch (_) {}
  }

  String? _lastLink;
  DateTime _lastLinkAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// Dışarıdan gelen adres: web bağlantısı, ya da ana ekran widget'ı / simge kısayolu
  /// (oatarayici://ara, yeni, gizli, qr, radyo, hava).
  void _onLink(Uri u) {
    if (!mounted) return;
    // Açılış bağlantısı hem getInitialLink hem akıştan gelebilir: aynısını iki kez açma.
    final now = DateTime.now();
    if (u.toString() == _lastLink && now.difference(_lastLinkAt) < const Duration(seconds: 3)) return;
    _lastLink = u.toString();
    _lastLinkAt = now;
    if (u.scheme.startsWith('http')) {
      _addTab(url: u.toString());
      return;
    }
    if (u.scheme != 'oatarayici') return;
    switch (u.host) {
      case 'ara':
        _addTab();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _startEditing();
        });
      case 'yeni':
        _addTab();
      case 'gizli':
        _addTab(incognito: true);
      case 'qr':
        _scanQr();
      case 'radyo':
        _showRadio();
      case 'hava':
        showWeatherDetails(context, _wx);
    }
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
      if (manual) _toast('Pusula güncel ($appVersion)');
      return;
    }
    final u = info;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        duration: const Duration(seconds: 12),
        content: Text('Pusula ${u.version} hazır'),
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
      applicationName: 'Pusula Browser',
      applicationVersion: appVersion,
      applicationIcon: const PusulaMark(size: 72),
      applicationLegalese: 'OA Labs\'ten · © 2026 Oğuzhan Aydın',
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
          SingleActivator(LogicalKeyboardKey.comma, control: true): () => _openSettings(),
          SingleActivator(LogicalKeyboardKey.keyK, control: true): _showCommands,
          SingleActivator(LogicalKeyboardKey.equal, control: true): () => _zoomStep(1),
          SingleActivator(LogicalKeyboardKey.numpadAdd, control: true): () => _zoomStep(1),
          SingleActivator(LogicalKeyboardKey.minus, control: true): () => _zoomStep(-1),
          SingleActivator(LogicalKeyboardKey.numpadSubtract, control: true): () => _zoomStep(-1),
          SingleActivator(LogicalKeyboardKey.digit0, control: true): () => _setZoom(100),
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
            onCustomize: () => _openSettings('baslangic'),
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
            weatherCard: _showClock || _showMarkets
                ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    if (_showClock) ClockWeatherCard(wx: _wx),
                    if (_showClock && _showMarkets) const SizedBox(height: 10),
                    if (_showMarkets) MarketStrip(market: _market),
                  ])
                : null,
            news: (_showNews || _showGames) && !t.incognito
                ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
                    if (_showGames) GameCorner(games: _games, onOpen: (u) => _go(u), compact: true),
                    if (_showGames && _showNews) const SizedBox(height: 18),
                    if (_showNews) NewsFeed(news: _news, onOpen: (u) => _go(u), compact: true),
                  ])
                : null,
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
            corner: (_showClock || _showMarkets) && !compact
                ? Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
                    if (_showClock) ClockWeatherCorner(wx: _wx),
                    if (_showClock && _showMarkets) const SizedBox(height: 12),
                    if (_showMarkets) SizedBox(width: 330, child: MarketStrip(market: _market, alignEnd: true)),
                  ])
                : null,
            news: (_showNews || _showGames) && !t.incognito && !compact
                ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
                    if (_showGames) GameCorner(games: _games, onOpen: (u) => _go(u)),
                    if (_showGames && _showNews) const SizedBox(height: 22),
                    if (_showNews) NewsFeed(news: _news, onOpen: (u) => _go(u)),
                  ])
                : null,
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
    final sp = _split;
    TabData? find(String id) {
      for (final t in _tabs) {
        if (t.id == id) return t;
      }
      return null;
    }

    final left = sp == null ? null : find(sp.$1);
    final right = sp == null ? null : find(sp.$2);
    final split = left != null && right != null && !_miniVideo && !compact && (identical(_tab, left) || identical(_tab, right));
    // Her sekme aynı yapıda tutulur (anahtarlı), böylece yan yana görünüme geçip çıkınca
    // ya da sekmeler yer değiştirince sayfalar yeniden yüklenmez.
    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth;
      final lw = (w * _splitRatio).clamp(240.0, max(240.0, w - 240.0));
      Widget slot(TabData t) {
        final isLeft = split && identical(t, left);
        final isRight = split && identical(t, right);
        final visible = split ? (isLeft || isRight) : identical(t, _tab);
        return Positioned(
          key: ValueKey(t.id),
          left: isRight ? lw + 3 : 0,
          top: 0,
          bottom: 0,
          right: isLeft ? w - lw + 3 : 0,
          child: Offstage(
            offstage: !visible,
            child: Listener(
              onPointerDown: split ? (_) => _focusPane(t) : null,
              child: Stack(fit: StackFit.expand, children: [
                _tabContent(t, compact: compact),
                IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(
                          color: split && identical(t, _tab) ? OAColors.amber.withValues(alpha: 0.6) : Colors.transparent, width: 2),
                    ),
                  ),
                ),
              ]),
            ),
          ),
        );
      }

      return Stack(children: [
        for (final t in _tabs) slot(t),
        if (split) ...[
        Positioned(
          key: const ValueKey('bolucu'),
          left: lw - 3,
          top: 0,
          bottom: 0,
          width: 6,
          child: MouseRegion(
            cursor: SystemMouseCursors.resizeLeftRight,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragUpdate: (d) => setState(() => _splitRatio = ((lw + d.delta.dx) / w).clamp(0.2, 0.8)),
              child: ColoredBox(color: OAColors.line),
            ),
          ),
        ),
        Positioned(
          key: const ValueKey('bolucu-kapat'),
          left: lw - 14,
          top: 8,
          child: Tooltip(
            message: 'Yan yana görünümü kapat',
            child: Material(
              color: OAColors.surface2,
              shape: CircleBorder(side: BorderSide(color: OAColors.border2)),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: _closeSplit,
                child: const Padding(padding: EdgeInsets.all(5), child: Icon(Icons.close, size: 14)),
              ),
            ),
          ),
        ),
        ],
      ]);
    });
  }


  // ---------------------------------------------------------------- Bilgisayar düzeni

  Widget _buildDesktop() {
    return SafeArea(
      child: Row(
        children: [
          if (_verticalTabs && !_miniVideo) KeyedSubtree(key: const ValueKey('dikey'), child: _verticalTabBar()),
          Expanded(
            key: const ValueKey('masaustu'),
            child: _desktopMain(),
          ),
        ],
      ),
    );
  }

  Widget _desktopMain() {
    return Column(
        children: [
          // Küçük pencerede video izlenirken yalnız sayfa görünür. (Sayfanın bulunduğu Expanded
          // anahtarla korunur; üstteki çubuklar kalkınca web görünümü yeniden oluşturulmaz.)
          if (!_miniVideo) ...[
            if (!_verticalTabs) _buildTabBar(),
            _buildToolbar(),
            if (_findOpen) _findBar(top: true),
            RadioMiniBar(radio: _radio, onOpen: _showRadio),
            ReadAloudBar(tts: _tts),
            _buildProgress(),
          ],
          Expanded(
            key: const ValueKey('sayfalar'),
            // Kenar çubuğu ve paneli adres çubuğunun altında, yalnız sayfanın yanında durur.
            child: Stack(children: [
              Positioned.fill(
                child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_sidebarOn && !_miniVideo && Platform.isWindows)
                  SidebarDock(
                    key: const ValueKey('dock'),
                    apps: _sideApps,
                    active: _sideOpen,
                    loaded: _sideLoaded,
                    badges: _sideBadges,
                    onTap: _toggleSide,
                    onMenu: _sideMenu,
                    onAdd: _addSideApp,
                  ),
                // Paneller (kapalıyken de arkada açık kalır)
                if (Platform.isWindows) KeyedSubtree(key: const ValueKey('panel'), child: _sidePanel()),
                Expanded(
                  key: const ValueKey('sayfa-alani'),
                  child: _pageArea(),
                ),
              ],
                ),
              ),
              // Adres çubuğunun önerileri sayfanın ve kenar çubuğunun üstünde, tam genişlikte
              if (_showSuggestions)
                Positioned(
                  top: 6,
                  left: 12,
                  right: 12,
                  child: _suggestionPanel(),
                ),
            ]),
          ),
        ],
    );
  }

  Widget _pageArea() {
    return Stack(
              children: [
                _pages(compact: false),
                // Windows: radyo sayfası burada, 1×1 piksel (bkz. RadioPlayer.host)
                Positioned(left: 0, bottom: 0, child: ListenableBuilder(listenable: _radio, builder: (_, __) => _radio.host())),
                if (_miniVideo) _miniExitButton(),
              ],
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
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                ..._tabEntries(vertical: false),
                // "+" en son sekmenin hemen yanında (Chrome gibi)
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
                  child: Center(
                    child: IconButton(
                      tooltip: 'Yeni sekme (Ctrl+T)',
                      icon: const Icon(Icons.add, size: 20),
                      onPressed: () => _addTab(),
                    ),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Dikey sekmeler',
            icon: Icon(Icons.view_sidebar_outlined, size: 20),
            onPressed: _toggleVerticalTabs,
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
            tooltip: 'Menü',
            onSelected: _onMenu,
            itemBuilder: (_) => [
              _mi('new', Icons.add, 'Yeni sekme', 'Ctrl+T'),
              _mi('incognito', Icons.visibility_off_outlined, 'Yeni gizli sekme'),
              const PopupMenuDivider(),
              _mi('bookmarks', Icons.star_border, 'Yer imleri'),
              _mi('history', Icons.history, 'Geçmiş'),
              _mi('downloads', Icons.download_outlined,
                  _downloads.activeCount > 0 ? 'İndirilenler (${_downloads.activeCount} sürüyor)' : 'İndirilenler', 'Ctrl+J'),
              _mi('readlist', Icons.bookmark_added_outlined, 'Okuma listesi', _reading.unread > 0 ? '${_reading.unread}' : null),
              _mi('devices', Icons.devices_outlined, 'Öbür cihazlar'),
              _mi('radio', Icons.radio_outlined, 'OA Radyo'),
              if (_closedTabs.isNotEmpty) _mi('reopen', Icons.restore, 'Kapatılan sekmeyi geri aç', 'Ctrl+Shift+T'),
              if (!_tab.showStart) ...[
                const PopupMenuDivider(),
                _mi('page', Icons.article_outlined, 'Bu sayfa', '›'),
              ],
              const PopupMenuDivider(),
              _mi('commands', Icons.bolt, 'Komut kutusu', 'Ctrl+K'),
              _mi('settings', Icons.settings_outlined, 'Ayarlar', 'Ctrl+,'),
            ],
          ),
        ],
      ),
    );
  }

  PopupMenuItem<String> _mi(String v, IconData icon, String label, [String? hint]) => PopupMenuItem(
        value: v,
        height: 42,
        child: Row(children: [
          Icon(icon, size: 19, color: OAColors.text2),
          const SizedBox(width: 12),
          Expanded(child: Text(label)),
          if (hint != null) ...[
            const SizedBox(width: 16),
            Text(hint, style: TextStyle(color: OAColors.faint, fontSize: 12.5)),
          ],
        ]),
      );

  /// "Bu sayfa" alt menüsü (bilgisayar): sayfaya özel araçlar.
  Future<void> _pageMenu() async {
    final size = MediaQuery.sizeOf(context);
    final v = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(size.width - 320, 100, 16, 0),
      items: [
        _mi('find', Icons.find_in_page_outlined, 'Sayfada bul', 'Ctrl+F'),
        _mi('later', Icons.bookmark_add_outlined, 'Sonra oku listesine ekle'),
        _mi('send', Icons.send_to_mobile_outlined, 'Öbür cihaza gönder'),
        _mi('flow', Icons.swap_horiz_rounded, 'OA Akış'),
        _mi('qrshare', Icons.qr_code_2, 'QR kod ile telefona aktar'),
        _mi('pin', Icons.push_pin_outlined, _tab.pinned ? 'Sabitlemeyi kaldır' : 'Sekmeyi sabitle'),
        if (_quick.length < kMaxQuickLinks) _mi('quick', Icons.add_to_home_screen_outlined, 'Hızlı erişime ekle'),
        const PopupMenuDivider(),
        _mi('tts', Icons.record_voice_over_outlined, 'Sesli oku'),
        if (Platform.isWindows)
          _split == null
              ? _mi('splitnew', Icons.vertical_split_outlined, 'Yan yana yeni sekme')
              : _mi('unsplit', Icons.vertical_split, 'Yan yana görünümü kapat'),
        _mi('reader', Icons.chrome_reader_mode_outlined, 'Okuma modu'),
        _mi('translate', Icons.translate, 'Türkçeye çevir'),
        _mi('darksite', Icons.contrast, 'Koyu göster', _isDarkSite(_tab.host) ? 'açık' : 'kapalı'),
        _mi('zoom', Icons.zoom_in, 'Yakınlaştırma', '%${_zoomOf(_tab.host)}'),
        const PopupMenuDivider(),
        _mi('pdf', Icons.picture_as_pdf_outlined, 'PDF olarak kaydet', 'Ctrl+P'),
        if (Platform.isWindows) _mi('shot', Icons.screenshot_monitor_outlined, 'Tam sayfa ekran görüntüsü'),
        _mi('pip', Icons.picture_in_picture_alt_outlined, 'Videoyu küçük pencerede izle'),
        _mi('adblock', Icons.shield_outlined, 'Bu sitede reklam engelleme'),
      ],
    );
    if (v != null) _onMenu(v);
  }

  /// Ayarlar: uygulamanın üzerine yandan kayarak açılan ekran.
  void _openSettings([String? section]) {
    Navigator.of(context).push(PageRouteBuilder(
      transitionDuration: const Duration(milliseconds: 260),
      reverseTransitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (_, __, ___) => SettingsScreen(page: this, initial: section),
      transitionsBuilder: (_, anim, __, child) => SlideTransition(
        position: Tween(begin: const Offset(1, 0), end: Offset.zero)
            .animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic)),
        child: child,
      ),
    ));
  }

  void _clearHistory() {
    setState(() => _history.clear());
    _save('history', _history);
    // Eşitlemede öbür cihazlardaki geçmiş de silinsin.
    _historyCleared = DateTime.now().millisecondsSinceEpoch;
    _prefs?.setInt('history_cleared', _historyCleared);
    _scheduleSync();
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
        _showList('Geçmiş', _history, onClear: _clearHistory);
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
      case 'clock':
        _toggleClock();
      case 'zoom':
        _showZoom();
      case 'darksite':
        _toggleDarkSite();
      case 'shot':
        _fullScreenshot();
      case 'import':
        _showImport();
      case 'voice':
        _voiceSearch();
      case 'later':
        _saveForLater();
      case 'readlist':
        _showReadingList();
      case 'news':
        _toggleNews();
      case 'markets':
        _toggleMarkets();
      case 'vtabs':
        _toggleVerticalTabs();
      case 'devices':
        _showDevices();
      case 'send':
        _sendTab();
      case 'flow':
        _showFlow();
      case 'syncset':
        _openSettings('hesap');
      case 'settings':
        _openSettings();
      case 'page':
        _pageMenu();
      case 'qrshare':
        _showQrShare();
      case 'pin':
        _togglePin(_tab);
      case 'tts':
        _readAloud();
      case 'unsplit':
        _closeSplit();
      case 'splitnew':
        final cur = _tab;
        _addTab();
        final added = _tab;
        setState(() => _split = (cur.id, added.id));
      case 'commands':
        _showCommands();
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
            if (!_editing) ReadAloudBar(tts: _tts),
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
            tooltip: 'Sesli ara',
            icon: const Icon(Icons.mic_none),
            onPressed: _voiceSearch,
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
              item(Icons.schedule, 'Saat ve hava durumu: ${_showClock ? 'açık' : 'kapalı'}', _toggleClock),
              item(Icons.currency_lira, 'Döviz ve altın: ${_showMarkets ? 'açık' : 'kapalı'}', _toggleMarkets),
              item(Icons.sports_esports_outlined, 'Oyun köşesi: ${_showGames ? 'açık' : 'kapalı'}', _toggleGames),
              item(Icons.newspaper_outlined, 'Haber akışı: ${_showNews ? 'açık' : 'kapalı'}', _toggleNews),
              if (_showNews) item(Icons.rss_feed, 'Haber kaynakları', () => showNewsSources(context, _news)),
              if (_showClock)
                item(Icons.location_city_outlined,
                    'Hava durumu şehri: ${_wx.city?.name ?? 'seçilmedi'}', () => pickCity(context, _wx)),
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
        Widget tool(IconData icon, String label, String value) => InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () {
                Navigator.pop(ctx);
                _onMenu(value);
              },
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(color: OAColors.surface2, borderRadius: BorderRadius.circular(14)),
                  child: Icon(icon, size: 21, color: OAColors.text),
                ),
                const SizedBox(height: 5),
                Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: OAColors.text2)),
              ]),
            );
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
              // Sayfa araçları: tek satırda simgeler
              if (!_tab.showStart) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                  child: Text('BU SAYFA',
                      style: TextStyle(color: OAColors.faint, fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.8)),
                ),
                GridView.count(
                  crossAxisCount: 5,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  childAspectRatio: 0.95,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  children: [
                    tool(Icons.find_in_page_outlined, 'Bul', 'find'),
                    tool(Icons.bookmark_add_outlined, 'Sonra oku', 'later'),
                    tool(Icons.send_to_mobile_outlined, 'Gönder', 'send'),
                    tool(Icons.swap_horiz_rounded, 'OA Akış', 'flow'),
                    tool(Icons.chrome_reader_mode_outlined, 'Okuma', 'reader'),
                    tool(Icons.record_voice_over_outlined, 'Sesli oku', 'tts'),
                    tool(Icons.translate, 'Çevir', 'translate'),
                    tool(Icons.contrast, _isDarkSite(_tab.host) ? 'Koyu: açık' : 'Koyu', 'darksite'),
                    tool(Icons.zoom_in, '%${_zoomOf(_tab.host)}', 'zoom'),
                    tool(Icons.picture_as_pdf_outlined, 'PDF', 'pdf'),
                    tool(Icons.picture_in_picture_alt_outlined, 'Küçük video', 'pip'),
                    tool(Icons.add_to_home_screen_outlined, 'Hızlı erişim', 'quick'),
                    tool(Icons.push_pin_outlined, _tab.pinned ? 'Sabit: açık' : 'Sabitle', 'pin'),
                  ],
                ),
                Divider(height: 16),
              ],
              item(Icons.add, 'Yeni sekme', 'new'),
              item(Icons.visibility_off_outlined, 'Yeni gizli sekme', 'incognito'),
              Divider(height: 16),
              item(Icons.star_border, 'Yer imleri', 'bookmarks'),
              item(Icons.history, 'Geçmiş', 'history'),
              item(Icons.download_outlined,
                  _downloads.activeCount > 0 ? 'İndirilenler (${_downloads.activeCount} sürüyor)' : 'İndirilenler',
                  'downloads'),
              item(Icons.bookmark_added_outlined,
                  _reading.unread > 0 ? 'Okuma listesi (${_reading.unread})' : 'Okuma listesi', 'readlist'),
              item(Icons.devices_outlined, 'Öbür cihazlar', 'devices'),
              item(Icons.radio_outlined, 'OA Radyo', 'radio'),
              if (Platform.isAndroid) item(Icons.qr_code_scanner, 'QR kod okut', 'qr'),
              if (_closedTabs.isNotEmpty) item(Icons.restore, 'Kapatılan sekmeyi geri aç', 'reopen'),
              Divider(height: 16),
              item(Icons.settings_outlined, 'Ayarlar', 'settings'),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showTabSwitcher() async {
    await _captureThumb(_tab);
    if (!mounted) return;
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
            if (t.thumb != null && !t.showStart && !t.incognito)
              Expanded(
                child: Image.memory(t.thumb!, fit: BoxFit.cover, alignment: Alignment.topCenter, cacheWidth: 400, gaplessPlayback: true),
              )
            else
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
      initialUrlRequest: t.pendingHtml == null ? URLRequest(url: WebUri(t.pendingUrl ?? t.url)) : null,
      initialData: t.pendingHtml == null
          ? null
          : InAppWebViewInitialData(data: t.pendingHtml!, baseUrl: WebUri(t.pendingUrl ?? 'about:blank')),
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
        if (_cookieOn) cookieBannerScript(_adblockAllow),
        if (_gesturesOn && Platform.isWindows) mouseGestureScript(),
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
        c.addJavaScriptHandler(handlerName: 'oaGesture', callback: (args) {
          if (t != _tab || args.isEmpty) return;
          switch (args.first.toString()) {
            case 'L':
              _back();
            case 'R':
              _forward();
            case 'U':
              t.controller?.reload();
            case 'D':
              _closeTab(_tabs.indexOf(t));
          }
        });
        c.addJavaScriptHandler(handlerName: 'oaRetry', callback: (_) {
          final u = t.errorUrl ?? t.url;
          if (u.startsWith('http')) c.loadUrl(urlRequest: URLRequest(url: WebUri(u)));
        });
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
        // OA hata sayfası yüklenirken adres çubuğunda açılamayan adres kalsın.
        if (t.errorUrl != null && !url.toString().startsWith('http')) return;
        t.errorUrl = null;
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
        _applySiteLook(t);
      },
      onScrollChanged: (c, x, y) => _onScroll(t, y),
      onReceivedError: (c, req, err) {
        if (req.isForMainFrame ?? true) _uncover(t);
        t.pullToRefresh?.endRefreshing();
        if (req.isForMainFrame ?? false) _showErrorPage(t, req.url.toString(), err);
      },
      onLoadStop: (c, url) async {
        t.pullToRefresh?.endRefreshing();
        _readSiteColor(t);
        if (t.coverLoadStarted) _uncover(t);
        _refreshNavState(t);
        _addHistory(t);
        _autofill(t);
        _applySiteLook(t);
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
        if (t.errorUrl != null && !url.toString().startsWith('http')) return;
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
      // Site izin isteyince (bildirim, konum, kamera…) mutlaka cevap verilmeli: Windows eklentisi
      // cevapsız kalan izin isteğinde çöküyordu (flutter_inappwebview_windows 0.6.0).
      onPermissionRequest: (c, req) => _onPermissionRequest(t, req),
    );
  }

  // ---------------------------------------------------------------- Site izinleri

  static final Set<PermissionResourceType> _autoGrant = {
    PermissionResourceType.AUTOPLAY, // sesli/görüntülü içerik kendiliğinden başlasın
    PermissionResourceType.PROTECTED_MEDIA_ID, // korumalı videolar (dizi/film siteleri)
  };

  String _permName(PermissionResourceType r) {
    if (r == PermissionResourceType.CAMERA) return 'kamera';
    if (r == PermissionResourceType.MICROPHONE) return 'mikrofon';
    if (r == PermissionResourceType.CAMERA_AND_MICROPHONE) return 'kamera ve mikrofon';
    if (r == PermissionResourceType.GEOLOCATION) return 'konum';
    if (r == PermissionResourceType.NOTIFICATIONS) return 'bildirim gönderme';
    if (r == PermissionResourceType.CLIPBOARD_READ) return 'kopyaladıklarını okuma';
    if (r == PermissionResourceType.MIDI_SYSEX) return 'MIDI cihazları';
    if (r == PermissionResourceType.FILE_READ_WRITE) return 'dosya okuma/yazma';
    if (r == PermissionResourceType.LOCAL_FONTS) return 'yüklü yazı tipleri';
    if (r == PermissionResourceType.WINDOW_MANAGEMENT) return 'pencere yönetimi';
    if (r == PermissionResourceType.OTHER_SENSORS) return 'cihaz sensörleri';
    if (r == PermissionResourceType.MULTIPLE_AUTOMATIC_DOWNLOADS) return 'birden çok dosya indirme';
    if (r == PermissionResourceType.DEVICE_ORIENTATION_AND_MOTION) return 'cihaz hareketi';
    return r.toString().toLowerCase();
  }

  Map<String, dynamic> _sitePerms() {
    try {
      return Map<String, dynamic>.from(jsonDecode(_prefs?.getString('site_perms') ?? '{}') as Map);
    } catch (_) {
      return {};
    }
  }

  Future<PermissionResponse> _onPermissionRequest(TabData t, PermissionRequest req) async {
    final resources = req.resources;
    PermissionResponse answer(bool grant) => PermissionResponse(
        resources: resources, action: grant ? PermissionResponseAction.GRANT : PermissionResponseAction.DENY);
    try {
      if (resources.isEmpty) return answer(false);
      if (resources.every(_autoGrant.contains)) return answer(true);
      final host = req.origin.host.replaceFirst(RegExp(r'^www\.'), '');
      final key = '$host|${resources.map((r) => r.toString()).join(',')}';
      final saved = _sitePerms();
      if (!t.incognito && saved[key] is bool) return answer(saved[key] as bool);
      if (!mounted) return answer(false);
      var remember = true;
      final grant = await showDialog<bool>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setD) => AlertDialog(
            title: Text('${host.isEmpty ? 'Bu site' : host} izin istiyor'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(resources.map(_permName).join(', '), style: TextStyle(color: OAColors.text, fontSize: 16)),
                if (!t.incognito) ...[
                  const SizedBox(height: 12),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: remember,
                    onChanged: (v) => setD(() => remember = v ?? true),
                    title: const Text('Bu site için hatırla'),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Engelle')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('İzin ver')),
            ],
          ),
        ),
      );
      final g = grant ?? false;
      if (grant != null && remember && !t.incognito) {
        saved[key] = g;
        _prefs?.setString('site_perms', jsonEncode(saved));
      }
      return answer(g);
    } catch (_) {
      return answer(false);
    }
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
