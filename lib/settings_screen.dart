part of 'main.dart';

// Ayarlar: uygulamanın üzerine açılan ayrı ekran (sekme açmaz; sekmeler arkada bekler).
// Bilgisayarda solda başlıklar, sağda ayarlar; telefonda önce başlık listesi, dokununca başlığın ekranı.

class _Section {
  const _Section(this.id, this.name, this.icon, this.sub);
  final String id;
  final String name;
  final IconData icon;
  final String sub;
}

final _sections = <_Section>[
  _Section('hesap', tx('Hesap ve eşitleme', 'Account and sync'), Icons.person_outline, tx('OA Labs hesabın ve cihazlar arasında eşitlenenler', 'Your OA Labs account and what syncs between devices')),
  _Section('gorunum', tx('Görünüm', 'Appearance'), Icons.light_mode_outlined, tx('Tema ve sayfaların görünüşü', 'Theme and how pages look')),
  _Section('baslangic', tx('Başlangıç sayfası', 'Start page'), Icons.home_outlined, tx('Yeni sekmede ne görünsün?', 'What should a new tab show?')),
  _Section('kenar', tx('Kenar çubuğu', 'Sidebar'), Icons.view_sidebar_outlined, tx('WhatsApp, Gmail, Spotify… soldaki panelde', 'WhatsApp, Gmail, Spotify… in the left panel')),
  _Section('performans', tx('Performans', 'Performance'), Icons.speed, tx('Sekme uyutma ve bellek', 'Tab sleeping and memory')),
  _Section('arama', tx('Arama', 'Search'), Icons.search, tx('Adres çubuğu ve arama motoru', 'Address bar and search engine')),
  _Section('gizlilik', tx('Gizlilik ve güvenlik', 'Privacy and security'), Icons.shield_outlined, tx('Reklamlar, izleyiciler, çerezler ve kilit', 'Ads, trackers, cookies and lock')),
  _Section('sifreler', tx('Şifreler', 'Passwords'), Icons.key_outlined, tx('Kayıtlı girişler ve içe aktarma', 'Saved logins and import')),
  _Section('siteler', tx('Site ayarları', 'Site settings'), Icons.public, tx('Siteye özel izinler ve tercihler', 'Per-site permissions and preferences')),
  _Section('indirme', tx('İndirilenler', 'Downloads'), Icons.download_outlined, tx('İndirilen dosyalar', 'Downloaded files')),
  _Section('radyo', 'OA Radyo', Icons.radio_outlined, tx('Yerleşik radyo', 'Built-in radio')),
  _Section('hakkinda', tx('Hakkında', 'About'), Icons.info_outline, tx('Sürüm ve güncellemeler', 'Version and updates')),
];

/// Ayarlardaki tek satır (arama için başlığı ve açıklaması tutulur).
class _Item {
  _Item(this.title, this.sub, this.build);
  final String title;
  final String sub;
  final Widget Function() build;
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.page, this.initial});
  final _BrowserPageState page;
  final String? initial;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

List<_Section> get _visibleSections => [
      for (final s in _sections)
        if (s.id != 'kenar' || Platform.isWindows) s
    ];

class _SettingsScreenState extends State<SettingsScreen> {
  String? _sel; // telefonda null: başlık listesi
  String _q = '';
  final _qCtl = TextEditingController();

  _BrowserPageState get p => widget.page;

  @override
  void initState() {
    super.initState();
    _sel = widget.initial;
    p._rev.addListener(_refresh);
  }

  @override
  void dispose() {
    p._rev.removeListener(_refresh);
    _qCtl.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  // ------------------------------------------------------------- Satır yapıları

  Widget _row(IconData icon, String title, {String? sub, Widget? trailing, VoidCallback? onTap, Color? iconColor}) {
    return ListTile(
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(color: OAColors.surface2, borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, size: 19, color: iconColor ?? OAColors.text2),
      ),
      title: Text(title, style: TextStyle(fontWeight: FontWeight.w600, color: OAColors.text, fontSize: 15)),
      subtitle: sub == null ? null : Text(sub, style: TextStyle(color: OAColors.muted, fontSize: 13)),
      trailing: trailing ?? (onTap != null ? Icon(Icons.chevron_right, color: OAColors.faint) : null),
      onTap: onTap,
    );
  }

  Widget _switch(IconData icon, String title, bool value, ValueChanged<bool> onChanged, {String? sub}) {
    return _row(icon, title,
        sub: sub,
        onTap: () => onChanged(!value),
        trailing: Switch(
          value: value,
          activeThumbColor: OAColors.amberInk,
          activeTrackColor: OAColors.amber,
          onChanged: onChanged,
        ));
  }

  Widget _value(String v) => Row(mainAxisSize: MainAxisSize.min, children: [
        Text(v, style: TextStyle(color: OAColors.text2, fontSize: 13.5)),
        const SizedBox(width: 4),
        Icon(Icons.chevron_right, color: OAColors.faint),
      ]);

  Widget _card(String? head, List<Widget> rows) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: OAColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: OAColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (head != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 2),
            child: Text(head.toUpperCase(),
                style: TextStyle(color: OAColors.faint, fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.8)),
          ),
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) Divider(height: 1, color: OAColors.line),
          rows[i],
        ],
      ]),
    );
  }

  // ------------------------------------------------------------- Başlıkların içeriği

  /// Her başlığın kartları: (kart başlığı, satırlar).
  List<(String?, List<_Item>)> _content(String id) {
    final mobile = Platform.isAndroid;
    switch (id) {
      case 'hesap':
        final u = p._account.user;
        return [
          (
            null,
            [
              _Item(tx('Hesap', 'Account'), u?.email ?? tx('giriş yap', 'sign in'), () {
                return _row(Icons.account_circle_outlined, u?.name ?? tx('Giriş yap veya üye ol', 'Sign in or sign up'),
                    sub: u != null ? u.email : tx('Şifre yok, e-postana kod gelir. Bilgisayar ve telefon eşitlenir.', 'No password: a code is sent to your email. Your computer and phone stay in sync.'),
                    trailing: Padding(padding: const EdgeInsets.only(right: 2), child: OAAvatar(name: u?.name, size: 36)),
                    onTap: p._openAccount);
              }),
            ]
          ),
          if (p._account.signedIn)
            (
              tx('Eşitlenenler', 'What syncs'),
              [
                _Item(tx('Yer imleri ve hızlı erişim', 'Bookmarks and quick access'), tx('her zaman eşitlenir', 'always synced'),
                    () => _row(Icons.sync, tx('Yer imleri ve hızlı erişim', 'Bookmarks and quick access'), sub: tx('Her zaman eşitlenir', 'Always synced'), trailing: Text(tx('Açık', 'On'), style: TextStyle(color: OAColors.green)))),
                _Item(tx('Açık sekmeler', 'Open tabs'), tx('öbür cihazlar görebilir sekme gönderme', 'other devices can see send tab'), () {
                  return _switch(Icons.tab_outlined, tx('Açık sekmeler', 'Open tabs'), p._syncTabs, (v) {
                    p.setState(() => p._syncTabs = v);
                    p._prefs?.setBool('sync_tabs', v);
                    p._syncNow();
                  }, sub: tx('Öbür cihazlar görebilir; sekme gönderilebilir', 'Other devices can see them; tabs can be sent'));
                }),
                _Item(tx('Geçmiş eşitleme', 'History sync'), tx('gizli sekmeler kaydedilmez', "private tabs aren't saved"), () {
                  return _switch(Icons.history, tx('Geçmiş', 'History'), p._syncHistory, (v) {
                    p.setState(() => p._syncHistory = v);
                    p._prefs?.setBool('sync_history', v);
                    p._syncNow();
                  }, sub: tx('Gizli sekmeler hiç kaydedilmez', 'Private tabs are never saved'));
                }),
                _Item(tx('Şifre eşitleme', 'Password sync'), tx('uçtan uca şifreli parola', 'end-to-end encrypted password'), () {
                  return _row(p._vault.enabled ? Icons.lock : Icons.lock_open_outlined, tx('Şifreler', 'Passwords'),
                      iconColor: p._vault.enabled ? OAColors.green : null,
                      sub: p._vault.enabled ? tx('Açık · uçtan uca şifreli', 'On · end-to-end encrypted') : tx('Kapalı · bir eşitleme parolası belirleyerek aç', 'Off · turn on by setting a sync password'),
                      trailing: TextButton(
                        onPressed: () async {
                          if (p._vault.enabled) {
                            await p._vault.disable();
                            p.setState(() {});
                          } else {
                            await p._enableVault();
                            p.setState(() {});
                          }
                        },
                        child: Text(p._vault.enabled ? tx('Kapat', 'Turn off') : tx('Aç', 'Turn on')),
                      ));
                }),
              ]
            ),
          if (p._account.signedIn)
            (
              tx('Cihazlar', 'Devices'),
              [
                _Item(tx('Öbür cihazlardaki sekmeler', 'Tabs on other devices'), 'cihazlar',
                    () => _row(Icons.devices_outlined, tx('Öbür cihazlardaki sekmeler', 'Tabs on other devices'),
                        sub: p._devices.isEmpty ? tx('Bu cihaz: ${p._deviceName}', 'This device: ${p._deviceName}') : tx('${p._devices.length} cihaz · bu cihaz: ${p._deviceName}', '${p._devices.length} devices · this device: ${p._deviceName}'),
                        onTap: p._showDevices)),
                _Item(tx('Şimdi eşitle', 'Sync now'), '', () {
                  return _row(Icons.sync, tx('Şimdi eşitle', 'Sync now'), onTap: () async {
                    await p._syncNow();
                    p._toast(tx('Eşitlendi', 'Synced'));
                  });
                }),
              ]
            ),
        ];
      case 'gorunum':
        return [
          (
            tx('Tema', 'Theme'),
            [
              _Item(tx('Uygulama teması', 'App theme'), tx('koyu açık sistem', 'dark light system'), () {
                final m = themeModeNotifier.value;
                return _row(Icons.contrast, tx('Uygulama teması', 'App theme'),
                    trailing: SegmentedButton<ThemeMode>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(value: ThemeMode.system, label: Text(tx('Sistem', 'System'))),
                        ButtonSegment(value: ThemeMode.dark, label: Text(tx('Koyu', 'Dark'))),
                        ButtonSegment(value: ThemeMode.light, label: Text(tx('Açık', 'Light'))),
                      ],
                      selected: {m},
                      onSelectionChanged: (s) {
                        themeModeNotifier.value = s.first;
                        p._prefs?.setString('theme', themeModeToString(s.first));
                        p.setState(() {});
                      },
                    ));
              }),
              _Item(tx('Dil', 'Language'), 'dil language türkçe english ingilizce', () {
                return _row(Icons.translate, tx('Dil', 'Language'),
                    sub: L.choice == 'auto'
                        ? tx('Cihazın diline göre', 'Same as device')
                        : null,
                    trailing: SegmentedButton<String>(
                      showSelectedIcon: false,
                      segments: [
                        ButtonSegment(value: 'auto', label: Text(tx('Otomatik', 'Auto'))),
                        const ButtonSegment(value: 'tr', label: Text('Türkçe')),
                        const ButtonSegment(value: 'en', label: Text('English')),
                      ],
                      selected: {L.choice},
                      onSelectionChanged: (s) async {
                        final v = s.first;
                        L.choice = v;
                        await p._prefs?.setString('dil', v);
                        p.setState(() {});
                        String next = v;
                        if (v == 'auto') {
                          final sys = WidgetsBinding.instance.platformDispatcher.locale.languageCode.toLowerCase();
                          next = sys == 'tr' ? 'tr' : 'en';
                        }
                        if (next != L.code) {
                          p._toast(next == 'en'
                              ? 'The language will change the next time you open Pusula.'
                              : 'Dil, Pusula bir sonraki açılışta değişecek.');
                        }
                      },
                    ));
              }),
              _Item(tx('Vurgu rengi', 'Accent color'), tx('renk tema turuncu mor mavi', 'color theme orange purple blue'), () {
                return _row(Icons.palette_outlined, tx('Vurgu rengi', 'Accent color'),
                    sub: accentById(accentNotifier.value).name,
                    trailing: Wrap(spacing: 6, children: [
                      for (final a in kAccents)
                        Tooltip(
                          message: a.name,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(20),
                            onTap: () => p._setAccent(a.id),
                            child: Container(
                              width: 24,
                              height: 24,
                              decoration: BoxDecoration(
                                color: a.fill,
                                shape: BoxShape.circle,
                                border: Border.all(
                                    color: accentNotifier.value == a.id ? OAColors.text : Colors.transparent, width: 2),
                              ),
                            ),
                          ),
                        ),
                    ]));
              }),
              _Item(tx('Hazır temalar', 'Preset themes'), tx('tema arka plan', 'theme background'), () {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(tx('Hazır temalar', 'Preset themes'), style: TextStyle(fontWeight: FontWeight.w600, color: OAColors.text, fontSize: 15)),
                    const SizedBox(height: 4),
                    Text(tx('Vurgu rengi ve başlangıç sayfası arka planı birlikte', 'Accent color and start page background together'), style: TextStyle(color: OAColors.muted, fontSize: 13)),
                    const SizedBox(height: 10),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      for (final (name, acc, wall) in kThemePresets)
                        ChoiceChip(
                          selected: accentNotifier.value == acc && p._wallpaperId == wall,
                          avatar: CircleAvatar(backgroundColor: accentById(acc).fill, radius: 7),
                          label: Text(name),
                          onSelected: (_) => p._applyPreset(acc, wall),
                        ),
                    ]),
                  ]),
                );
              }),
              _Item(tx('Bütün siteleri koyu göster', 'Show all sites dark'), tx('karanlık mod', 'dark mode'),
                  () => _switch(Icons.dark_mode_outlined, tx('Bütün siteleri koyu göster', 'Show all sites dark'), p._darkAll, p._setDarkAll,
                      sub: tx('Karanlık modu olmayan siteler de koyu görünür', 'Sites without a dark mode look dark too'))),
            ]
          ),
          if (!mobile)
            (
              tx('Fare ve klavye', 'Mouse and keyboard'),
              [
                _Item(tx('Fare hareketleri', 'Mouse gestures'), tx('gesture sağ tuş', 'gesture right button'), () => _switch(Icons.gesture, tx('Fare hareketleri', 'Mouse gestures'), p._gesturesOn, p._setGestures,
                    sub: tx('Sağ tuşa basılı tutup çek: ← geri, → ileri, ↑ yenile, ↓ sekmeyi kapat', 'Hold the right button and drag: ← back, → forward, ↑ reload, ↓ close tab'))),
                _Item(tx('Komut kutusu', 'Command box'), tx('ctrl+k kısayol', 'ctrl+k shortcut'), () => _row(Icons.bolt, tx('Komut kutusu', 'Command box'), sub: tx('Ctrl+K: komutlara, sekmelere ve ayarlara klavyeden ulaş', 'Ctrl+K: reach commands, tabs and settings from the keyboard'), onTap: () {
                      Navigator.pop(context);
                      p._showCommands();
                    })),
              ]
            ),
          if (!mobile)
            (
              tx('Sekmeler', 'Tabs'),
              [
                _Item(tx('Dikey sekmeler', 'Vertical tabs'), tx('sekmeler solda panelde', 'tabs in a left panel'),
                    () => _switch(Icons.view_sidebar_outlined, tx('Dikey sekmeler', 'Vertical tabs'), p._verticalTabs, (_) => p._toggleVerticalTabs(),
                        sub: tx('Sekmeler solda bir panelde dizilir', 'Tabs are listed in a panel on the left'))),
              ]
            ),
        ];
      case 'baslangic':
        return [
          (
            null,
            [
              _Item(tx('Arka plan', 'Background'), tx('duvar kağıdı fotoğraf', 'wallpaper photo'), () => _row(Icons.wallpaper_outlined, tx('Arka plan', 'Background'), onTap: p._showWallpaperPicker)),
              _Item(tx('Saat ve hava durumu', 'Clock and weather'), '', () => _switch(Icons.schedule, tx('Saat ve hava durumu', 'Clock and weather'), p._showClock, (_) => p._toggleClock())),
              _Item(tx('Hava durumu şehri', 'Weather city'), 'konum', () {
                return _row(Icons.location_city_outlined, tx('Hava durumu şehri', 'Weather city'),
                    trailing: _value(p._wx.city?.name ?? tx('Seçilmedi', 'Not set')), onTap: () => pickCity(context, p._wx).then((_) => p.setState(() {})));
              }),
              _Item(tx('Döviz ve altın', 'Currency and gold'), tx('dolar euro gram altın', 'dollar euro gold'),
                  () => _switch(Icons.currency_lira, tx('Döviz ve altın', 'Currency and gold'), p._showMarkets, (_) => p._toggleMarkets(), sub: tx('Dolar, euro, gram altın', 'Dollar, euro, gold (gram)'))),
              _Item(tx('Oyun köşesi', 'Game corner'), tx('epic steam ücretsiz oyun indirim', 'epic steam free games deals'),
                  () => _switch(Icons.sports_esports_outlined, tx('Oyun köşesi', 'Game corner'), p._showGames, (_) => p._toggleGames(), sub: tx('Epic\'te ücretsiz oyunlar, Steam indirimleri', 'Free games on Epic, Steam deals'))),
              _Item(tx('Haber akışı', 'News feed'), 'haberler', () => _switch(Icons.newspaper_outlined, tx('Haber akışı', 'News feed'), p._showNews, (_) => p._toggleNews())),
              _Item(tx('Haber kaynakları', 'News sources'), 'rss', () {
                final on = p._news.sources.where((s) => s.on).toList();
                return _row(Icons.rss_feed, tx('Haber kaynakları', 'News sources'),
                    sub: on.map((s) => s.name).take(4).join(', '),
                    trailing: _value('${on.length}'),
                    onTap: () => showNewsSources(context, p._news));
              }),
              _Item(tx('Hızlı erişime site ekle', 'Add a site to quick access'), 'tablo', () => _row(Icons.add_box_outlined, tx('Hızlı erişime site ekle', 'Add a site to quick access'), onTap: () => p._editQuick(null))),
              if (p._hiddenPromos.isNotEmpty)
                _Item(tx('Gizlenen OA kartlarını geri getir', 'Bring back hidden OA cards'), '', () {
                  return _row(Icons.view_carousel_outlined, tx('Gizlenen OA kartlarını geri getir', 'Bring back hidden OA cards'), onTap: () {
                    p.setState(() => p._hiddenPromos.clear());
                    p._prefs?.setStringList('promo_hidden', []);
                  });
                }),
            ]
          ),
        ];
      case 'kenar':
        return [
          (
            null,
            [
              _Item(tx('Kenar çubuğunu göster', 'Show sidebar'), 'dock', () => _switch(Icons.view_sidebar_outlined, tx('Kenar çubuğunu göster', 'Show sidebar'), p._sidebarOn, (_) => p._toggleSidebar(),
                  sub: tx('Soldaki simgeler; fareyle üzerine gelince büyür', 'Icons on the left; they grow when you hover'))),
            ]
          ),
          (
            tx('Uygulamalar', 'Apps'),
            [
              for (final a in p._sideApps)
                _Item(a.name, tx('kenar uygulama', 'sidebar app'), () {
                  final i = p._sideApps.indexOf(a);
                  return ListTile(
                    leading: a.id == kSideRadio
                        ? Icon(Icons.radio_rounded, color: OAColors.amber, size: 28)
                        : SiteIcon(url: a.url, letter: a.name[0], size: 28),
                    title: Text(a.name, style: TextStyle(fontWeight: FontWeight.w600, color: OAColors.text)),
                    subtitle: Text(a.id == kSideRadio ? tx('Uygulamanın kendi radyosu', "The app's own radio") : (Uri.tryParse(a.url)?.host ?? a.url),
                        style: TextStyle(color: OAColors.muted, fontSize: 13)),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(tooltip: tx('Yukarı', 'Up'), icon: const Icon(Icons.arrow_upward, size: 18), onPressed: i == 0 ? null : () => p._moveSideApp(a, -1)),
                      IconButton(
                          tooltip: tx('Aşağı', 'Down'),
                          icon: const Icon(Icons.arrow_downward, size: 18),
                          onPressed: i == p._sideApps.length - 1 ? null : () => p._moveSideApp(a, 1)),
                      IconButton(tooltip: tx('Kaldır', 'Remove'), icon: const Icon(Icons.close, size: 18), onPressed: () => p._removeSideApp(a)),
                    ]),
                  );
                }),
              _Item(tx('Uygulama ekle', 'Add app'), tx('telegram discord', 'telegram discord'), () => _row(Icons.add, tx('Uygulama ya da site ekle', 'Add an app or site'), sub: tx('Telegram, Discord, Google Takvim… ya da istediğin site', 'Telegram, Discord, Google Calendar… or any site you like'), onTap: p._addSideApp)),
            ]
          ),
        ];
      case 'performans':
        return [
          (
            tx('Sekme uyutma', 'Tab sleeping'),
            [
              _Item(tx('Sekmeleri uyut', 'Put tabs to sleep'), tx('bellek ram', 'memory ram'), () {
                return _row(Icons.bedtime_outlined, tx('Kullanılmayan sekmeleri uyut', 'Put unused tabs to sleep'),
                    sub: tx('Uyuyan sekme bellekten çıkar, dokununca yeniden açılır. Ses ya da video çalan sekme uyutulmaz.', "A sleeping tab is removed from memory and reopens when you tap it. Tabs playing audio or video aren't put to sleep."),
                    trailing: DropdownButton<int>(
                      value: p._sleepMinutes,
                      underline: const SizedBox.shrink(),
                      items: const [
                        DropdownMenuItem(value: 15, child: Text(tx('15 dk sonra', 'After 15 min'))),
                        DropdownMenuItem(value: 30, child: Text(tx('30 dk sonra', 'After 30 min'))),
                        DropdownMenuItem(value: 60, child: Text(tx('1 saat sonra', 'After 1 hour'))),
                        DropdownMenuItem(value: 120, child: Text(tx('2 saat sonra', 'After 2 hours'))),
                        DropdownMenuItem(value: 0, child: Text(tx('Hiçbir zaman', 'Never'))),
                      ],
                      onChanged: (v) {
                        if (v != null) p._setSleepMinutes(v);
                      },
                    ));
              }),
              _Item(tx('Uyuyan sekmeler', 'Sleeping tabs'), '', () {
                return _row(Icons.layers_outlined, tx('Uyuyan sekmeler', 'Sleeping tabs'),
                    sub: tx('${p._tabs.length} sekmeden ${p._sleepingCount} tanesi uykuda', '${p._sleepingCount} of ${p._tabs.length} tabs are asleep'),
                    trailing: TextButton(onPressed: p._sleepOthers, child: Text(tx('Diğerlerini şimdi uyut', 'Put others to sleep now'))));
              }),
            ]
          ),
        ];
      case 'arama':
        return [
          (
            null,
            [
              _Item(tx('Arama motoru', 'Search engine'), 'google duckduckgo', () => _row(Icons.travel_explore, tx('Arama motoru', 'Search engine'), trailing: _value(p._engine.name), onTap: p._showSearchSettings)),
              _Item(tx('Yazarken öneriler', 'Suggestions while typing'), '', () {
                return _switch(Icons.lightbulb_outline, tx('Yazarken öneriler', 'Suggestions while typing'), p._suggestOn, (v) {
                  p.setState(() => p._suggestOn = v);
                  p._prefs?.setBool('suggest', v);
                }, sub: tx('Önerileri seçtiğin arama motoru verir', 'Suggestions come from your chosen search engine'));
              }),
              if (mobile)
                _Item(tx('Sesli arama', 'Voice search'), 'mikrofon', () => _row(Icons.mic_none, tx('Sesli arama', 'Voice search'), sub: tx('Adres çubuğundaki mikrofona dokun', 'Tap the microphone in the address bar'), onTap: p._voiceSearch)),
            ]
          ),
        ];
      case 'gizlilik':
        return [
          (
            tx('Engelleme', 'Blocking'),
            [
              _Item(tx('Reklam ve izleyici engelleme', 'Ad and tracker blocking'), 'reklam', () {
                return _switch(Icons.shield_outlined, tx('Reklam ve izleyici engelleme', 'Ad and tracker blocking'), p._adblockOn, (v) {
                  p._adblockOn = v;
                  p._applyAdblock();
                }, sub: tx('${AdBlock.count} alan adı listede', '${AdBlock.count} domains on the list'));
              }),
              _Item(tx('Çerez pencerelerini reddet', 'Decline cookie pop-ups'), tx('çerez', 'cookie'), () {
                return _switch(Icons.cookie_outlined, tx('Çerez pencerelerini reddet', 'Decline cookie pop-ups'), p._cookieOn, p._setCookieBlock,
                    sub: tx('"Çerezleri kabul et"te reddet / yalnız gerekli', 'Picks "Reject" / "Only necessary" on "Accept cookies" pop-ups'));
              }),
              if (p._adblockAllow.isNotEmpty)
                _Item(tx('Engellemenin kapalı olduğu siteler', 'Sites with blocking turned off'), '', () {
                  return _row(Icons.playlist_remove, tx('Engellemenin kapalı olduğu siteler', 'Sites with blocking turned off'),
                      sub: p._adblockAllow.take(4).join(', '),
                      trailing: TextButton(
                          onPressed: () {
                            p._adblockAllow.clear();
                            p._applyAdblock();
                          },
                          child: Text(tx('Hepsini aç', 'Turn all on'))));
                }),
            ]
          ),
          (
            tx('Gizlilik', 'Privacy'),
            [
              _Item(tx('Gizli sekme kilidi', 'Private tab lock'), tx('parmak izi windows hello', 'fingerprint windows hello'), () {
                return _switch(Icons.lock_outline, tx('Gizli sekme kilidi', 'Private tab lock'), p._incognitoLock, (_) => p._toggleIncognitoLock(),
                    sub: Platform.isWindows ? tx('Windows Hello ile açılır', 'Unlocks with Windows Hello') : tx('Parmak izi, yüz ya da ekran kilidiyle açılır', 'Unlocks with fingerprint, face or screen lock'));
              }),
              _Item(tx('Geçmişi temizle', 'Clear history'), '', () {
                return _row(Icons.history, tx('Geçmişi temizle', 'Clear history'),
                    sub: tx('${p._history.length} kayıt', '${p._history.length} entries'),
                    trailing: TextButton(onPressed: p._history.isEmpty ? null : _confirmClearHistory, child: Text(tx('Temizle', 'Clear'))));
              }),
              _Item(tx('Çerezleri ve site verilerini sil', 'Delete cookies and site data'), 'oturumlar', () {
                return _row(Icons.delete_sweep_outlined, tx('Çerezleri ve site verilerini sil', 'Delete cookies and site data'),
                    sub: tx('Sitelerdeki oturumların kapanır', "You'll be signed out of sites"),
                    trailing: TextButton(onPressed: _confirmClearCookies, child: Text(tx('Sil', 'Delete'))));
              }),
            ]
          ),
        ];
      case 'sifreler':
        return [
          (
            null,
            [
              _Item(tx('Kayıtlı şifreler', 'Saved passwords'), 'liste', () {
                return _row(Icons.key_outlined, tx('Kayıtlı şifreler', 'Saved passwords'),
                    sub: tx('Görmek için kimlik doğrulanır', "You'll be asked to verify it's you"), trailing: _value('${p._passwords.items.length}'), onTap: p._showPasswords);
              }),
              if (p._passwords.never.isNotEmpty)
                _Item(tx('"Asla kaydetme" denen siteler', 'Sites marked "Never save"'), '', () {
                  return _row(Icons.block, tx('"Asla kaydetme" denen siteler', 'Sites marked "Never save"'),
                      sub: p._passwords.never.map((o) => Uri.tryParse(o)?.host ?? o).take(3).join(', '),
                      trailing: TextButton(
                          onPressed: () async {
                            await p._passwords.clearNever();
                            p.setState(() {});
                          },
                          child: Text(tx('Sıfırla', 'Reset'))));
                }),
              _Item(tx('Chrome / Edge / Firefox\'tan içe aktar', 'Import from Chrome / Edge / Firefox'), tx('yer imleri şifreler', 'bookmarks passwords'),
                  () => _row(Icons.file_download_outlined, tx('Chrome / Edge / Firefox\'tan içe aktar', 'Import from Chrome / Edge / Firefox'), sub: tx('Yer imleri (.html) ve şifreler (.csv)', 'Bookmarks (.html) and passwords (.csv)'), onTap: p._showImport)),
            ]
          ),
        ];
      case 'siteler':
        final perms = p._sitePerms();
        return [
          (
            tx('İzinler', 'Permissions'),
            [
              if (perms.isEmpty)
                _Item(tx('Site izinleri', 'Site permissions'), '', () => _row(Icons.public, tx('Henüz izin verilen ya da engellenen site yok', 'No sites allowed or blocked yet'), sub: tx('Siteler konum, kamera, bildirim isteyince sorulur', "You're asked when a site wants location, camera or notifications"))),
              for (final e in perms.entries)
                _Item(e.key, 'izin', () {
                  final parts = e.key.split('|');
                  return _row(e.value == true ? Icons.check_circle_outline : Icons.block, parts.first,
                      iconColor: e.value == true ? OAColors.green : OAColors.danger,
                      sub: tx('${e.value == true ? 'İzin verildi' : 'Engellendi'}: ${parts.length > 1 ? parts[1].toLowerCase().replaceAll('_', ' ') : ''}', "${e.value == true ? 'Allowed' : 'Blocked'}: ${parts.length > 1 ? parts[1].toLowerCase().replaceAll('_', ' ') : ''}"),
                      trailing: IconButton(
                        tooltip: tx('Kaldır (bir dahaki sefere sorulur)', "Remove (you'll be asked next time)"),
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          final m = p._sitePerms()..remove(e.key);
                          p._prefs?.setString('site_perms', jsonEncode(m));
                          p.setState(() {});
                        },
                      ));
                }),
            ]
          ),
          (
            tx('Yakınlaştırma', 'Zoom'),
            [
              if (p._siteZoom.isEmpty) _Item(tx('Yakınlaştırma', 'Zoom'), '', () => _row(Icons.zoom_in, tx('Bütün siteler %100', 'All sites at 100%'), sub: tx('Bir sitede yakınlaştırınca burada görünür', 'Shows up here when you zoom on a site'))),
              for (final e in p._siteZoom.entries)
                _Item(e.key, tx('yakınlaştırma', 'zoom'), () {
                  return _row(Icons.zoom_in, e.key,
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        Text('%${e.value}', style: TextStyle(color: OAColors.text2)),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () {
                            p.setState(() => p._siteZoom.remove(e.key));
                            p._prefs?.setString('site_zoom', jsonEncode(p._siteZoom));
                          },
                        ),
                      ]));
                }),
            ]
          ),
          (
            tx('Koyu gösterilen siteler', 'Sites shown dark'),
            [
              if (p._darkSites.isEmpty) _Item(tx('Koyu', 'Dark'), '', () => _row(Icons.dark_mode_outlined, tx('Yok', 'None'), sub: tx('Menüden "Bu siteyi koyu göster" ile eklenir', 'Added from the menu with "Show this site dark"'))),
              for (final h in p._darkSites.toList())
                _Item(h, 'koyu', () {
                  return _row(Icons.dark_mode_outlined, h,
                      trailing: IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          p.setState(() => p._darkSites.remove(h));
                          p._prefs?.setStringList('dark_sites', p._darkSites.toList());
                        },
                      ));
                }),
            ]
          ),
        ];
      case 'indirme':
        return [
          (
            null,
            [
              _Item(tx('İndirilenler', 'Downloads'), '', () {
                return _row(Icons.download_outlined, tx('İndirilenleri göster', 'Show downloads'),
                    sub: mobile ? tx('Telefonun İndirilenler klasörüne kaydedilir', "Saved to your phone's Downloads folder") : tx('Bilgisayarın İndirilenler klasörüne kaydedilir · Ctrl+J', "Saved to your computer's Downloads folder · Ctrl+J"),
                    onTap: p._showDownloads);
              }),
            ]
          ),
        ];
      case 'radyo':
        return [
          (
            null,
            [
              _Item('OA Radyo', 'istasyonlar', () => _row(Icons.radio_outlined, tx('Radyoyu aç', 'Open radio'), sub: tx('İstasyonlar, arama, favoriler', 'Stations, search, favorites'), onTap: p._showRadio)),
              _Item(tx('Favoriler', 'Favorites'), '', () => _row(Icons.favorite_border, tx('Favori istasyonlar', 'Favorite stations'), trailing: Text('${p._radio.favorites.length}', style: TextStyle(color: OAColors.text2)))),
              _Item(tx('Arka planda', 'In the background'), '', () {
                return _row(Icons.music_note_outlined, mobile ? tx('Arka planda çalar', 'Plays in the background') : tx('Medya tuşları', 'Media keys'),
                    sub: mobile ? tx('Uygulamadan çıkınca da çalar; bildirimde kontrol', 'Keeps playing after you leave the app; control it from the notification') : tx('Klavyedeki oynat/durdur tuşlarıyla kontrol', "Control with your keyboard's play/pause keys"));
              }),
            ]
          ),
        ];
      case 'hakkinda':
        return [
          (
            null,
            [
              _Item('Pusula Browser', tx('sürüm hakkında oa tarayıcı', 'version about oa browser'), () => _row(Icons.info_outline, 'Pusula Browser', sub: tx('Sürüm $appVersion · OA Labs', 'Version $appVersion · OA Labs'))),
              _Item(tx('Güncellemeleri denetle', 'Check for updates'), '', () => _row(Icons.system_update_outlined, tx('Güncellemeleri denetle', 'Check for updates'), onTap: () => p._checkUpdate(manual: true))),
              _Item('oalabs.dev/tarayici', 'site', () {
                return _row(Icons.public, 'oalabs.dev/tarayici', onTap: () {
                  Navigator.pop(context);
                  p._addTab(url: 'https://oalabs.dev/tarayici/');
                });
              }),
              _Item(tx('Gizlilik politikası', 'Privacy policy'), '', () {
                return _row(Icons.privacy_tip_outlined, tx('Gizlilik politikası', 'Privacy policy'), onTap: () {
                  Navigator.pop(context);
                  p._addTab(url: 'https://oalabs.dev/gizlilik/');
                });
              }),
            ]
          ),
        ];
    }
    return [];
  }

  Future<void> _confirmClearHistory() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tx('Geçmiş temizlensin mi?', 'Clear history?')),
        content: Text(p._syncHistory && p._account.signedIn ? tx('Geçmiş eşitleniyor: öbür cihazlarından da silinir.', 'History is syncing: it will also be deleted from your other devices.') : tx('Bu cihazdaki geçmiş silinir.', 'History on this device will be deleted.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tx('Vazgeç', 'Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(tx('Temizle', 'Clear'))),
        ],
      ),
    );
    if (ok == true) p._clearHistory();
  }

  Future<void> _confirmClearCookies() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tx('Çerezler ve site verileri silinsin mi?', 'Delete cookies and site data?')),
        content: Text(tx('Sitelerdeki oturumların kapanır, site tercihleri silinir. OA Labs hesabın uygulamada açık kalır.', "You'll be signed out of sites and site preferences will be deleted. Your OA Labs account stays signed in in the app.")),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tx('Vazgeç', 'Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(tx('Sil', 'Delete'))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await oaCookies().deleteAllCookies();
    } catch (_) {}
    await p._account.syncToWebView();
    p._toast(tx('Çerezler ve site verileri silindi', 'Cookies and site data deleted'));
  }

  // ------------------------------------------------------------- Ekran

  List<Widget> _sectionBody(String id) => [
        for (final (head, items) in _content(id))
          if (items.isNotEmpty) _card(head, [for (final it in items) it.build()]),
      ];

  List<Widget> _searchBody() {
    final q = _q.toLowerCase();
    final out = <Widget>[];
    for (final s in _visibleSections) {
      final hits = <_Item>[];
      for (final (_, items) in _content(s.id)) {
        hits.addAll(items.where((it) => '${it.title} ${it.sub} ${s.name}'.toLowerCase().contains(q)));
      }
      if (hits.isNotEmpty) out.add(_card(s.name, [for (final it in hits) it.build()]));
    }
    if (out.isEmpty) {
      out.add(Padding(
        padding: const EdgeInsets.all(24),
        child: Text(tx('"$_q" için ayar bulunamadı', 'No settings found for "$_q"'), textAlign: TextAlign.center, style: TextStyle(color: OAColors.muted)),
      ));
    }
    return out;
  }

  Widget _searchField({double? width}) => SizedBox(
        width: width,
        height: 40,
        child: TextField(
          controller: _qCtl,
          onChanged: (v) => setState(() => _q = v.trim()),
          style: TextStyle(color: OAColors.text, fontSize: 14),
          decoration: InputDecoration(
            hintText: tx('Ayarlarda ara', 'Search settings'),
            prefixIcon: Icon(Icons.search, size: 18, color: OAColors.muted),
            suffixIcon: _q.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.close, size: 16),
                    onPressed: () {
                      _qCtl.clear();
                      setState(() => _q = '');
                    }),
            contentPadding: EdgeInsets.zero,
            fillColor: OAColors.surface,
          ),
        ),
      );

  void _back() {
    if (_q.isNotEmpty) {
      _qCtl.clear();
      setState(() => _q = '');
    } else if (_sel != null && MediaQuery.sizeOf(context).width < 760) {
      setState(() => _sel = null);
    } else {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 760;
    final sel = _sel ?? (wide ? 'hesap' : null);
    final section = _visibleSections.where((s) => s.id == sel).firstOrNull;
    final canPopInside = _q.isNotEmpty || (!wide && _sel != null);
    return PopScope(
      canPop: !canPopInside,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: CallbackShortcuts(
        bindings: {const SingleActivator(LogicalKeyboardKey.escape): _back},
        child: Focus(
          autofocus: true,
          child: Scaffold(
            backgroundColor: OAColors.bg,
            body: SafeArea(
              child: Column(children: [
                // Üst çubuk
                Container(
                  height: 60,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(color: OAColors.bg2, border: Border(bottom: BorderSide(color: OAColors.line))),
                  child: Row(children: [
                    IconButton(tooltip: tx('Geri', 'Back'), icon: const Icon(Icons.arrow_back), onPressed: _back),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        !wide && section != null && _q.isEmpty ? section.name : tx('Ayarlar', 'Settings'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: oaDisplay(22),
                      ),
                    ),
                    if (wide) _searchField(width: 280),
                    if (wide) const SizedBox(width: 8),
                    IconButton(tooltip: tx('Kapat (Esc)', 'Close (Esc)'), icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                  ]),
                ),
                Expanded(child: wide ? _wideBody(section!) : _narrowBody(section)),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _wideBody(_Section section) {
    return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        width: 250,
        decoration: BoxDecoration(color: OAColors.bg2, border: Border(right: BorderSide(color: OAColors.line))),
        child: ListView(padding: const EdgeInsets.all(10), children: [
          for (final s in _visibleSections)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Material(
                color: s.id == section.id && _q.isEmpty ? OAColors.amber.withValues(alpha: 0.14) : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () {
                    _qCtl.clear();
                    setState(() {
                      _q = '';
                      _sel = s.id;
                    });
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    child: Row(children: [
                      Icon(s.icon, size: 19, color: s.id == section.id && _q.isEmpty ? OAColors.amberHi : OAColors.text2),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(s.name,
                            style: TextStyle(
                              color: s.id == section.id && _q.isEmpty ? OAColors.amberHi : OAColors.text2,
                              fontWeight: s.id == section.id && _q.isEmpty ? FontWeight.w600 : FontWeight.w400,
                              fontSize: 14.5,
                            )),
                      ),
                    ]),
                  ),
                ),
              ),
            ),
        ]),
      ),
      Expanded(
        child: Align(
          alignment: Alignment.topLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: ListView(padding: const EdgeInsets.fromLTRB(32, 24, 32, 40), children: [
              if (_q.isEmpty) ...[
                Text(section.name, style: oaDisplay(28)),
                const SizedBox(height: 4),
                Text(section.sub, style: TextStyle(color: OAColors.muted)),
                const SizedBox(height: 18),
                ..._sectionBody(section.id),
              ] else
                ..._searchBody(),
            ]),
          ),
        ),
      ),
    ]);
  }

  Widget _narrowBody(_Section? section) {
    if (_q.isNotEmpty || section == null) {
      return ListView(padding: const EdgeInsets.fromLTRB(14, 14, 14, 32), children: [
        _searchField(),
        const SizedBox(height: 14),
        if (_q.isNotEmpty)
          ..._searchBody()
        else
          _card(null, [
            for (final s in _visibleSections)
              _row(s.icon, s.name, sub: s.sub, onTap: () => setState(() => _sel = s.id)),
          ]),
      ]);
    }
    return ListView(padding: const EdgeInsets.fromLTRB(14, 14, 14, 32), children: [
      Text(section.sub, style: TextStyle(color: OAColors.muted)),
      const SizedBox(height: 12),
      ..._sectionBody(section.id),
    ]);
  }
}
