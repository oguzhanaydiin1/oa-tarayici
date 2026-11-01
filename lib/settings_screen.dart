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

const _sections = <_Section>[
  _Section('hesap', 'Hesap ve eşitleme', Icons.person_outline, 'OA Labs hesabın ve cihazlar arasında eşitlenenler'),
  _Section('gorunum', 'Görünüm', Icons.light_mode_outlined, 'Tema ve sayfaların görünüşü'),
  _Section('baslangic', 'Başlangıç sayfası', Icons.home_outlined, 'Yeni sekmede ne görünsün?'),
  _Section('kenar', 'Kenar çubuğu', Icons.view_sidebar_outlined, 'WhatsApp, Gmail, Spotify… soldaki panelde'),
  _Section('performans', 'Performans', Icons.speed, 'Sekme uyutma ve bellek'),
  _Section('arama', 'Arama', Icons.search, 'Adres çubuğu ve arama motoru'),
  _Section('gizlilik', 'Gizlilik ve güvenlik', Icons.shield_outlined, 'Reklamlar, izleyiciler, çerezler ve kilit'),
  _Section('sifreler', 'Şifreler', Icons.key_outlined, 'Kayıtlı girişler ve içe aktarma'),
  _Section('siteler', 'Site ayarları', Icons.public, 'Siteye özel izinler ve tercihler'),
  _Section('indirme', 'İndirilenler', Icons.download_outlined, 'İndirilen dosyalar'),
  _Section('radyo', 'OA Radyo', Icons.radio_outlined, 'Yerleşik radyo'),
  _Section('hakkinda', 'Hakkında', Icons.info_outline, 'Sürüm ve güncellemeler'),
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
              _Item('Hesap', u?.email ?? 'giriş yap', () {
                return _row(Icons.account_circle_outlined, u?.name ?? 'Giriş yap veya üye ol',
                    sub: u != null ? u.email : 'Şifre yok, e-postana kod gelir. Bilgisayar ve telefon eşitlenir.',
                    trailing: Padding(padding: const EdgeInsets.only(right: 2), child: OAAvatar(name: u?.name, size: 36)),
                    onTap: p._openAccount);
              }),
            ]
          ),
          if (p._account.signedIn)
            (
              'Eşitlenenler',
              [
                _Item('Yer imleri ve hızlı erişim', 'her zaman eşitlenir',
                    () => _row(Icons.sync, 'Yer imleri ve hızlı erişim', sub: 'Her zaman eşitlenir', trailing: Text('Açık', style: TextStyle(color: OAColors.green)))),
                _Item('Açık sekmeler', 'öbür cihazlar görebilir sekme gönderme', () {
                  return _switch(Icons.tab_outlined, 'Açık sekmeler', p._syncTabs, (v) {
                    p.setState(() => p._syncTabs = v);
                    p._prefs?.setBool('sync_tabs', v);
                    p._syncNow();
                  }, sub: 'Öbür cihazlar görebilir; sekme gönderilebilir');
                }),
                _Item('Geçmiş eşitleme', 'gizli sekmeler kaydedilmez', () {
                  return _switch(Icons.history, 'Geçmiş', p._syncHistory, (v) {
                    p.setState(() => p._syncHistory = v);
                    p._prefs?.setBool('sync_history', v);
                    p._syncNow();
                  }, sub: 'Gizli sekmeler hiç kaydedilmez');
                }),
                _Item('Şifre eşitleme', 'uçtan uca şifreli parola', () {
                  return _row(p._vault.enabled ? Icons.lock : Icons.lock_open_outlined, 'Şifreler',
                      iconColor: p._vault.enabled ? OAColors.green : null,
                      sub: p._vault.enabled ? 'Açık · uçtan uca şifreli' : 'Kapalı · bir eşitleme parolası belirleyerek aç',
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
                        child: Text(p._vault.enabled ? 'Kapat' : 'Aç'),
                      ));
                }),
              ]
            ),
          if (p._account.signedIn)
            (
              'Cihazlar',
              [
                _Item('Öbür cihazlardaki sekmeler', 'cihazlar',
                    () => _row(Icons.devices_outlined, 'Öbür cihazlardaki sekmeler',
                        sub: p._devices.isEmpty ? 'Bu cihaz: ${p._deviceName}' : '${p._devices.length} cihaz · bu cihaz: ${p._deviceName}',
                        onTap: p._showDevices)),
                _Item('Şimdi eşitle', '', () {
                  return _row(Icons.sync, 'Şimdi eşitle', onTap: () async {
                    await p._syncNow();
                    p._toast('Eşitlendi');
                  });
                }),
              ]
            ),
        ];
      case 'gorunum':
        return [
          (
            'Tema',
            [
              _Item('Uygulama teması', 'koyu açık sistem', () {
                final m = themeModeNotifier.value;
                return _row(Icons.contrast, 'Uygulama teması',
                    trailing: SegmentedButton<ThemeMode>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(value: ThemeMode.system, label: Text('Sistem')),
                        ButtonSegment(value: ThemeMode.dark, label: Text('Koyu')),
                        ButtonSegment(value: ThemeMode.light, label: Text('Açık')),
                      ],
                      selected: {m},
                      onSelectionChanged: (s) {
                        themeModeNotifier.value = s.first;
                        p._prefs?.setString('theme', themeModeToString(s.first));
                        p.setState(() {});
                      },
                    ));
              }),
              _Item('Bütün siteleri koyu göster', 'karanlık mod',
                  () => _switch(Icons.dark_mode_outlined, 'Bütün siteleri koyu göster', p._darkAll, p._setDarkAll,
                      sub: 'Karanlık modu olmayan siteler de koyu görünür')),
            ]
          ),
          if (!mobile)
            (
              'Sekmeler',
              [
                _Item('Dikey sekmeler', 'sekmeler solda panelde',
                    () => _switch(Icons.view_sidebar_outlined, 'Dikey sekmeler', p._verticalTabs, (_) => p._toggleVerticalTabs(),
                        sub: 'Sekmeler solda bir panelde dizilir')),
              ]
            ),
        ];
      case 'baslangic':
        return [
          (
            null,
            [
              _Item('Arka plan', 'duvar kağıdı fotoğraf', () => _row(Icons.wallpaper_outlined, 'Arka plan', onTap: p._showWallpaperPicker)),
              _Item('Saat ve hava durumu', '', () => _switch(Icons.schedule, 'Saat ve hava durumu', p._showClock, (_) => p._toggleClock())),
              _Item('Hava durumu şehri', 'konum', () {
                return _row(Icons.location_city_outlined, 'Hava durumu şehri',
                    trailing: _value(p._wx.city?.name ?? 'Seçilmedi'), onTap: () => pickCity(context, p._wx).then((_) => p.setState(() {})));
              }),
              _Item('Döviz ve altın', 'dolar euro gram altın',
                  () => _switch(Icons.currency_lira, 'Döviz ve altın', p._showMarkets, (_) => p._toggleMarkets(), sub: 'Dolar, euro, gram altın')),
              _Item('Haber akışı', 'haberler', () => _switch(Icons.newspaper_outlined, 'Haber akışı', p._showNews, (_) => p._toggleNews())),
              _Item('Haber kaynakları', 'rss', () {
                final on = p._news.sources.where((s) => s.on).toList();
                return _row(Icons.rss_feed, 'Haber kaynakları',
                    sub: on.map((s) => s.name).take(4).join(', '),
                    trailing: _value('${on.length}'),
                    onTap: () => showNewsSources(context, p._news));
              }),
              _Item('Hızlı erişime site ekle', 'tablo', () => _row(Icons.add_box_outlined, 'Hızlı erişime site ekle', onTap: () => p._editQuick(null))),
              if (p._hiddenPromos.isNotEmpty)
                _Item('Gizlenen OA kartlarını geri getir', '', () {
                  return _row(Icons.view_carousel_outlined, 'Gizlenen OA kartlarını geri getir', onTap: () {
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
              _Item('Kenar çubuğunu göster', 'dock', () => _switch(Icons.view_sidebar_outlined, 'Kenar çubuğunu göster', p._sidebarOn, (_) => p._toggleSidebar(),
                  sub: 'Soldaki simgeler; fareyle üzerine gelince büyür')),
            ]
          ),
          (
            'Uygulamalar',
            [
              for (final a in p._sideApps)
                _Item(a.name, 'kenar uygulama', () {
                  final i = p._sideApps.indexOf(a);
                  return ListTile(
                    leading: a.id == kSideRadio
                        ? Icon(Icons.radio_rounded, color: OAColors.amber, size: 28)
                        : SiteIcon(url: a.url, letter: a.name[0], size: 28),
                    title: Text(a.name, style: TextStyle(fontWeight: FontWeight.w600, color: OAColors.text)),
                    subtitle: Text(a.id == kSideRadio ? 'Uygulamanın kendi radyosu' : (Uri.tryParse(a.url)?.host ?? a.url),
                        style: TextStyle(color: OAColors.muted, fontSize: 13)),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(tooltip: 'Yukarı', icon: const Icon(Icons.arrow_upward, size: 18), onPressed: i == 0 ? null : () => p._moveSideApp(a, -1)),
                      IconButton(
                          tooltip: 'Aşağı',
                          icon: const Icon(Icons.arrow_downward, size: 18),
                          onPressed: i == p._sideApps.length - 1 ? null : () => p._moveSideApp(a, 1)),
                      IconButton(tooltip: 'Kaldır', icon: const Icon(Icons.close, size: 18), onPressed: () => p._removeSideApp(a)),
                    ]),
                  );
                }),
              _Item('Uygulama ekle', 'telegram discord', () => _row(Icons.add, 'Uygulama ya da site ekle', sub: 'Telegram, Discord, Google Takvim… ya da istediğin site', onTap: p._addSideApp)),
            ]
          ),
        ];
      case 'performans':
        return [
          (
            'Sekme uyutma',
            [
              _Item('Sekmeleri uyut', 'bellek ram', () {
                return _row(Icons.bedtime_outlined, 'Kullanılmayan sekmeleri uyut',
                    sub: 'Uyuyan sekme bellekten çıkar, dokununca yeniden açılır. Ses ya da video çalan sekme uyutulmaz.',
                    trailing: DropdownButton<int>(
                      value: p._sleepMinutes,
                      underline: const SizedBox.shrink(),
                      items: const [
                        DropdownMenuItem(value: 15, child: Text('15 dk sonra')),
                        DropdownMenuItem(value: 30, child: Text('30 dk sonra')),
                        DropdownMenuItem(value: 60, child: Text('1 saat sonra')),
                        DropdownMenuItem(value: 120, child: Text('2 saat sonra')),
                        DropdownMenuItem(value: 0, child: Text('Hiçbir zaman')),
                      ],
                      onChanged: (v) {
                        if (v != null) p._setSleepMinutes(v);
                      },
                    ));
              }),
              _Item('Uyuyan sekmeler', '', () {
                return _row(Icons.layers_outlined, 'Uyuyan sekmeler',
                    sub: '${p._tabs.length} sekmeden ${p._sleepingCount} tanesi uykuda',
                    trailing: TextButton(onPressed: p._sleepOthers, child: const Text('Diğerlerini şimdi uyut')));
              }),
            ]
          ),
        ];
      case 'arama':
        return [
          (
            null,
            [
              _Item('Arama motoru', 'google duckduckgo', () => _row(Icons.travel_explore, 'Arama motoru', trailing: _value(p._engine.name), onTap: p._showSearchSettings)),
              _Item('Yazarken öneriler', '', () {
                return _switch(Icons.lightbulb_outline, 'Yazarken öneriler', p._suggestOn, (v) {
                  p.setState(() => p._suggestOn = v);
                  p._prefs?.setBool('suggest', v);
                }, sub: 'Önerileri seçtiğin arama motoru verir');
              }),
              if (mobile)
                _Item('Sesli arama', 'mikrofon', () => _row(Icons.mic_none, 'Sesli arama', sub: 'Adres çubuğundaki mikrofona dokun', onTap: p._voiceSearch)),
            ]
          ),
        ];
      case 'gizlilik':
        return [
          (
            'Engelleme',
            [
              _Item('Reklam ve izleyici engelleme', 'reklam', () {
                return _switch(Icons.shield_outlined, 'Reklam ve izleyici engelleme', p._adblockOn, (v) {
                  p._adblockOn = v;
                  p._applyAdblock();
                }, sub: '${AdBlock.domains.length} alan adı listede');
              }),
              _Item('Çerez pencerelerini reddet', 'çerez', () {
                return _switch(Icons.cookie_outlined, 'Çerez pencerelerini reddet', p._cookieOn, p._setCookieBlock,
                    sub: '"Çerezleri kabul et"te reddet / yalnız gerekli');
              }),
              if (p._adblockAllow.isNotEmpty)
                _Item('Engellemenin kapalı olduğu siteler', '', () {
                  return _row(Icons.playlist_remove, 'Engellemenin kapalı olduğu siteler',
                      sub: p._adblockAllow.take(4).join(', '),
                      trailing: TextButton(
                          onPressed: () {
                            p._adblockAllow.clear();
                            p._applyAdblock();
                          },
                          child: const Text('Hepsini aç')));
                }),
            ]
          ),
          (
            'Gizlilik',
            [
              _Item('Gizli sekme kilidi', 'parmak izi windows hello', () {
                return _switch(Icons.lock_outline, 'Gizli sekme kilidi', p._incognitoLock, (_) => p._toggleIncognitoLock(),
                    sub: Platform.isWindows ? 'Windows Hello ile açılır' : 'Parmak izi, yüz ya da ekran kilidiyle açılır');
              }),
              _Item('Geçmişi temizle', '', () {
                return _row(Icons.history, 'Geçmişi temizle',
                    sub: '${p._history.length} kayıt',
                    trailing: TextButton(onPressed: p._history.isEmpty ? null : _confirmClearHistory, child: const Text('Temizle')));
              }),
              _Item('Çerezleri ve site verilerini sil', 'oturumlar', () {
                return _row(Icons.delete_sweep_outlined, 'Çerezleri ve site verilerini sil',
                    sub: 'Sitelerdeki oturumların kapanır',
                    trailing: TextButton(onPressed: _confirmClearCookies, child: const Text('Sil')));
              }),
            ]
          ),
        ];
      case 'sifreler':
        return [
          (
            null,
            [
              _Item('Kayıtlı şifreler', 'liste', () {
                return _row(Icons.key_outlined, 'Kayıtlı şifreler',
                    sub: 'Görmek için kimlik doğrulanır', trailing: _value('${p._passwords.items.length}'), onTap: p._showPasswords);
              }),
              if (p._passwords.never.isNotEmpty)
                _Item('"Asla kaydetme" denen siteler', '', () {
                  return _row(Icons.block, '"Asla kaydetme" denen siteler',
                      sub: p._passwords.never.map((o) => Uri.tryParse(o)?.host ?? o).take(3).join(', '),
                      trailing: TextButton(
                          onPressed: () async {
                            await p._passwords.clearNever();
                            p.setState(() {});
                          },
                          child: const Text('Sıfırla')));
                }),
              _Item('Chrome / Edge / Firefox\'tan içe aktar', 'yer imleri şifreler',
                  () => _row(Icons.file_download_outlined, 'Chrome / Edge / Firefox\'tan içe aktar', sub: 'Yer imleri (.html) ve şifreler (.csv)', onTap: p._showImport)),
            ]
          ),
        ];
      case 'siteler':
        final perms = p._sitePerms();
        return [
          (
            'İzinler',
            [
              if (perms.isEmpty)
                _Item('Site izinleri', '', () => _row(Icons.public, 'Henüz izin verilen ya da engellenen site yok', sub: 'Siteler konum, kamera, bildirim isteyince sorulur')),
              for (final e in perms.entries)
                _Item(e.key, 'izin', () {
                  final parts = e.key.split('|');
                  return _row(e.value == true ? Icons.check_circle_outline : Icons.block, parts.first,
                      iconColor: e.value == true ? OAColors.green : OAColors.danger,
                      sub: '${e.value == true ? 'İzin verildi' : 'Engellendi'}: ${parts.length > 1 ? parts[1].toLowerCase().replaceAll('_', ' ') : ''}',
                      trailing: IconButton(
                        tooltip: 'Kaldır (bir dahaki sefere sorulur)',
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
            'Yakınlaştırma',
            [
              if (p._siteZoom.isEmpty) _Item('Yakınlaştırma', '', () => _row(Icons.zoom_in, 'Bütün siteler %100', sub: 'Bir sitede yakınlaştırınca burada görünür')),
              for (final e in p._siteZoom.entries)
                _Item(e.key, 'yakınlaştırma', () {
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
            'Koyu gösterilen siteler',
            [
              if (p._darkSites.isEmpty) _Item('Koyu', '', () => _row(Icons.dark_mode_outlined, 'Yok', sub: 'Menüden "Bu siteyi koyu göster" ile eklenir')),
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
              _Item('İndirilenler', '', () {
                return _row(Icons.download_outlined, 'İndirilenleri göster',
                    sub: mobile ? 'Telefonun İndirilenler klasörüne kaydedilir' : 'Bilgisayarın İndirilenler klasörüne kaydedilir · Ctrl+J',
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
              _Item('OA Radyo', 'istasyonlar', () => _row(Icons.radio_outlined, 'Radyoyu aç', sub: 'İstasyonlar, arama, favoriler', onTap: p._showRadio)),
              _Item('Favoriler', '', () => _row(Icons.favorite_border, 'Favori istasyonlar', trailing: Text('${p._radio.favorites.length}', style: TextStyle(color: OAColors.text2)))),
              _Item('Arka planda', '', () {
                return _row(Icons.music_note_outlined, mobile ? 'Arka planda çalar' : 'Medya tuşları',
                    sub: mobile ? 'Uygulamadan çıkınca da çalar; bildirimde kontrol' : 'Klavyedeki oynat/durdur tuşlarıyla kontrol');
              }),
            ]
          ),
        ];
      case 'hakkinda':
        return [
          (
            null,
            [
              _Item('OA Tarayıcı', 'sürüm', () => _row(Icons.info_outline, 'OA Tarayıcı', sub: 'Sürüm $appVersion')),
              _Item('Güncellemeleri denetle', '', () => _row(Icons.system_update_outlined, 'Güncellemeleri denetle', onTap: () => p._checkUpdate(manual: true))),
              _Item('oalabs.dev/tarayici', 'site', () {
                return _row(Icons.public, 'oalabs.dev/tarayici', onTap: () {
                  Navigator.pop(context);
                  p._addTab(url: 'https://oalabs.dev/tarayici/');
                });
              }),
              _Item('Gizlilik politikası', '', () {
                return _row(Icons.privacy_tip_outlined, 'Gizlilik politikası', onTap: () {
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
        title: const Text('Geçmiş temizlensin mi?'),
        content: Text(p._syncHistory && p._account.signedIn ? 'Geçmiş eşitleniyor: öbür cihazlarından da silinir.' : 'Bu cihazdaki geçmiş silinir.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Temizle')),
        ],
      ),
    );
    if (ok == true) p._clearHistory();
  }

  Future<void> _confirmClearCookies() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Çerezler ve site verileri silinsin mi?'),
        content: const Text('Sitelerdeki oturumların kapanır, site tercihleri silinir. OA Labs hesabın uygulamada açık kalır.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Sil')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await oaCookies().deleteAllCookies();
    } catch (_) {}
    await p._account.syncToWebView();
    p._toast('Çerezler ve site verileri silindi');
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
        child: Text('"$_q" için ayar bulunamadı', textAlign: TextAlign.center, style: TextStyle(color: OAColors.muted)),
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
            hintText: 'Ayarlarda ara',
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
                    IconButton(tooltip: 'Geri', icon: const Icon(Icons.arrow_back), onPressed: _back),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        !wide && section != null && _q.isEmpty ? section.name : 'Ayarlar',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: oaDisplay(22),
                      ),
                    ),
                    if (wide) _searchField(width: 280),
                    if (wide) const SizedBox(width: 8),
                    IconButton(tooltip: 'Kapat (Esc)', icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
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
