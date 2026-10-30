import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'oa_theme.dart';
import 'search.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const BrowserApp());
}

class BrowserApp extends StatelessWidget {
  const BrowserApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OA Tarayıcı',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      theme: buildOATheme(),
      darkTheme: buildOATheme(),
      home: const BrowserPage(),
    );
  }
}

/// Tek bir sekmenin durumu.
class TabData {
  TabData(this.url, {this.incognito = false}) : id = UniqueKey().toString();

  final String id;
  final bool incognito;
  String url;
  String title = 'Yeni sekme';
  double progress = 0;
  bool canGoBack = false;
  InAppWebViewController? controller;
}

class BrowserPage extends StatefulWidget {
  const BrowserPage({super.key});

  @override
  State<BrowserPage> createState() => _BrowserPageState();
}

class _BrowserPageState extends State<BrowserPage> {
  final List<TabData> _tabs = [];
  int _current = 0;

  final TextEditingController _urlCtl = TextEditingController();
  final FocusNode _urlFocus = FocusNode();

  SharedPreferences? _prefs;
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

  @override
  void initState() {
    super.initState();
    _addTab();
    _loadStorage();
    // Ok tuşları öneri listesinde gezsin; odaktaki düğümde yakalanır, metin kutusundan önce.
    _urlFocus.onKeyEvent = _onAddressKey;
    _urlFocus.addListener(() {
      if (!_urlFocus.hasFocus) {
        // Öneriye dokunma, odak kaybından sonra gelir; kısa bir gecikmeyle kapat.
        Future.delayed(const Duration(milliseconds: 150), () {
          if (mounted && !_urlFocus.hasFocus) {
            setState(() => _showSuggestions = false);
          }
        });
      } else {
        _urlCtl.selection =
            TextSelection(baseOffset: 0, extentOffset: _urlCtl.text.length);
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _urlCtl.dispose();
    _urlFocus.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------- Depolama

  Future<void> _loadStorage() async {
    _prefs = await SharedPreferences.getInstance();
    setState(() {
      _bookmarks = _decode(_prefs!.getStringList('bookmarks'));
      _history = _decode(_prefs!.getStringList('history'));
      _engine = engineById(_prefs!.getString('engine'));
      _suggestOn = _prefs!.getBool('suggest') ?? true;
    });
  }

  List<Map<String, String>> _decode(List<String>? raw) => (raw ?? [])
      .map((e) => Map<String, String>.from(jsonDecode(e) as Map))
      .toList();

  void _save(String key, List<Map<String, String>> list) {
    _prefs?.setStringList(key, list.map(jsonEncode).toList());
  }

  bool get _isBookmarked => _bookmarks.any((b) => b['url'] == _tab.url);

  void _toggleBookmark() {
    setState(() {
      if (_isBookmarked) {
        _bookmarks.removeWhere((b) => b['url'] == _tab.url);
      } else {
        _bookmarks.insert(0, {'title': _tab.title, 'url': _tab.url});
      }
    });
    _save('bookmarks', _bookmarks);
  }

  void _pushHistory(Map<String, String> entry) {
    if (_history.isNotEmpty && _history.first['url'] == entry['url']) return;
    _history.insert(0, entry);
    if (_history.length > 300) _history.removeRange(300, _history.length);
    _save('history', _history);
  }

  void _addHistory(TabData t) {
    if (t.incognito || t.url.isEmpty || t.url == 'about:blank') return;
    _pushHistory({'title': t.title, 'url': t.url});
  }

  // ----------------------------------------------------------------- Sekmeler

  void _addTab({String? url, bool incognito = false}) {
    setState(() {
      _tabs.add(TabData(url ?? _engine.homeUrl, incognito: incognito));
      _current = _tabs.length - 1;
      _urlCtl.text = '';
    });
  }

  void _closeTab(int i) {
    setState(() {
      if (_tabs.length == 1) {
        _tabs.clear();
        _tabs.add(TabData(_engine.homeUrl));
        _current = 0;
      } else {
        _tabs.removeAt(i);
        if (_current >= _tabs.length) _current = _tabs.length - 1;
      }
      _urlCtl.text = _tab.url;
    });
  }

  void _selectTab(int i) {
    setState(() {
      _current = i;
      _urlCtl.text = _tab.url;
    });
  }

  // ---------------------------------------------------------------- Gezinme

  /// Adres çubuğuna yazılanı URL'ye ya da seçili motorda aramaya çevirir.
  String _normalize(String input, {bool forceSearch = false}) {
    final text = input.trim();
    if (text.isEmpty) return _engine.homeUrl;
    if (!forceSearch && looksLikeUrl(text)) {
      final hasScheme = RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*://').hasMatch(text);
      return hasScheme ? text : 'https://$text';
    }
    if (!_tab.incognito) {
      _pushHistory({'title': text, 'url': _engine.searchUrl(text), 'q': text});
    }
    return _engine.searchUrl(text);
  }

  void _go(String input, {bool forceSearch = false}) {
    final url = _normalize(input, forceSearch: forceSearch);
    _tab.controller?.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
    setState(() => _showSuggestions = false);
    _urlFocus.unfocus();
  }

  Future<void> _refreshNavState(TabData t) async {
    final back = await t.controller?.canGoBack() ?? false;
    if (!mounted) return;
    setState(() => t.canGoBack = back);
  }

  Future<bool> _handleBack() async {
    if (_showSuggestions) {
      setState(() => _showSuggestions = false);
      return true;
    }
    if (await _tab.controller?.canGoBack() ?? false) {
      await _tab.controller!.goBack();
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
      _selected = -1;
      _showSuggestions = local.isNotEmpty;
    });

    _debounce?.cancel();
    // Gizli sekmede yazılanlar arama motoruna gönderilmez.
    if (!_suggestOn || _tab.incognito || text.trim().isEmpty || looksLikeUrl(text)) {
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 150), () async {
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
    if (q.isEmpty) return const [];
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

  // ---------------------------------------------------------------- Arayüz

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final handled = await _handleBack();
        if (!handled) SystemNavigator.pop();
      },
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyT, control: true): () => _addTab(),
          const SingleActivator(LogicalKeyboardKey.keyL, control: true): () =>
              _urlFocus.requestFocus(),
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            body: SafeArea(
              child: Column(
                children: [
                  _buildTabBar(),
                  _buildToolbar(),
                  _buildProgress(),
                  Expanded(
                    child: Stack(
                      children: [
                        IndexedStack(
                          index: _current,
                          children: [for (final t in _tabs) _buildWebView(t)],
                        ),
                        if (_showSuggestions) _buildSuggestions(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      height: 46,
      decoration: const BoxDecoration(
        color: OAColors.bg2,
        border: Border(bottom: BorderSide(color: OAColors.line)),
      ),
      child: Row(
        children: [
          const Padding(
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
                    margin: const EdgeInsets.fromLTRB(2, 8, 0, 0),
                    padding: const EdgeInsets.only(left: 14),
                    decoration: BoxDecoration(
                      color: selected ? OAColors.surface : Colors.transparent,
                      border: selected
                          ? const Border(
                              top: BorderSide(color: OAColors.border),
                              left: BorderSide(color: OAColors.border),
                              right: BorderSide(color: OAColors.border),
                            )
                          : null,
                      borderRadius:
                          const BorderRadius.vertical(top: Radius.circular(12)),
                    ),
                    child: Row(
                      children: [
                        if (t.incognito)
                          const Padding(
                            padding: EdgeInsets.only(right: 6),
                            child: Icon(Icons.visibility_off,
                                size: 14, color: OAColors.blue),
                          ),
                        Expanded(
                          child: Text(
                            t.title,
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
                              const BoxConstraints(minWidth: 28, minHeight: 28),
                          icon: const Icon(Icons.close),
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
            icon: const Icon(Icons.add),
            onPressed: () => _addTab(),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar() {
    final loading = _tab.progress < 1;
    final secure = _tab.url.startsWith('https');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      decoration: const BoxDecoration(
        color: OAColors.surface,
        border: Border(bottom: BorderSide(color: OAColors.border)),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Geri',
            icon: const Icon(Icons.arrow_back),
            onPressed: _tab.canGoBack ? () => _tab.controller?.goBack() : null,
          ),
          IconButton(
            tooltip: 'İleri',
            icon: const Icon(Icons.arrow_forward),
            onPressed: () => _tab.controller?.goForward(),
          ),
          IconButton(
            tooltip: loading ? 'Durdur' : 'Yenile',
            icon: Icon(loading ? Icons.close : Icons.refresh),
            onPressed: () => loading
                ? _tab.controller?.stopLoading()
                : _tab.controller?.reload(),
          ),
          IconButton(
            tooltip: 'Ana sayfa',
            icon: const Icon(Icons.home_outlined),
            onPressed: () => _go(''),
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
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: '${_engine.name} ile ara veya adres yaz',
                  prefixIcon: Icon(
                    secure ? Icons.lock_outline : Icons.search,
                    size: 18,
                    color: secure ? OAColors.green : OAColors.muted,
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
            ),
          ),
          IconButton(
            tooltip: 'Yer imi',
            icon: Icon(
              _isBookmarked ? Icons.star : Icons.star_border,
              color: _isBookmarked ? OAColors.amber : null,
            ),
            onPressed: _toggleBookmark,
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              switch (v) {
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
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'incognito', child: Text('Yeni gizli sekme')),
              PopupMenuItem(value: 'bookmarks', child: Text('Yer imleri')),
              PopupMenuItem(value: 'history', child: Text('Geçmiş')),
              PopupMenuDivider(),
              PopupMenuItem(value: 'engine', child: Text('Arama motoru')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildProgress() {
    if (_tab.progress >= 1) return const SizedBox(height: 2);
    return SizedBox(
      height: 2,
      child: LinearProgressIndicator(value: _tab.progress),
    );
  }

  Widget _buildSuggestions() {
    final q = _urlCtl.text.trim();
    return Positioned(
      top: 6,
      left: 12,
      right: 12,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Material(
            color: OAColors.surface,
            elevation: 12,
            shadowColor: Colors.black,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(OARadius.lg),
              side: const BorderSide(color: OAColors.border2),
            ),
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < _suggestions.length; i++)
                    _suggestionRow(_suggestions[i], q, i == _selected),
                ],
              ),
            ),
          ),
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
        height: 42,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: selected ? OAColors.surface2 : null,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(icon,
                size: 18,
                color: s.kind == SuggestionKind.go ? OAColors.amber : OAColors.muted),
            const SizedBox(width: 12),
            Expanded(child: _highlight(s.label, q)),
            if (right.isNotEmpty) ...[
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  right,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, color: OAColors.faint),
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
    const base = TextStyle(fontSize: 15, color: OAColors.text);
    if (i < 0) {
      return Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: base);
    }
    return Text.rich(
      TextSpan(style: base, children: [
        TextSpan(text: label.substring(0, i)),
        TextSpan(
            text: label.substring(i, i + q.length),
            style: const TextStyle(fontWeight: FontWeight.w600)),
        TextSpan(text: label.substring(i + q.length)),
      ]),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  String _shortUrl(String? url) =>
      (url ?? '').replaceFirst(RegExp(r'^https?://(www\.)?'), '');

  Widget _buildWebView(TabData t) {
    return InAppWebView(
      key: ValueKey(t.id),
      initialUrlRequest: URLRequest(url: WebUri(t.url)),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        incognito: t.incognito,
        isInspectable: true,
        supportZoom: true,
        mediaPlaybackRequiresUserGesture: false,
      ),
      onWebViewCreated: (c) => t.controller = c,
      onLoadStart: (c, url) {
        if (url == null) return;
        setState(() => t.url = url.toString());
        if (t == _tab && !_urlFocus.hasFocus) _urlCtl.text = t.url;
      },
      onLoadStop: (c, url) async {
        _refreshNavState(t);
        _addHistory(t);
      },
      onProgressChanged: (c, p) => setState(() => t.progress = p / 100),
      onTitleChanged: (c, title) {
        if (title == null || title.isEmpty) return;
        setState(() => t.title = title);
      },
      onUpdateVisitedHistory: (c, url, isReload) {
        if (url == null) return;
        t.url = url.toString();
        if (t == _tab && !_urlFocus.hasFocus) _urlCtl.text = t.url;
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('İndirme: ${req.url}')),
        );
      },
    );
  }

  // ---------------------------------------------------------------- Paneller

  void _showSearchSettings() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
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
              padding: const EdgeInsets.fromLTRB(8, 16, 8, 24),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                  child: Text('Arama motoru', style: oaDisplay(22)),
                ),
                const Padding(
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
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(e.note),
                    trailing: Icon(
                      e.id == _engine.id
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      color: e.id == _engine.id ? OAColors.amber : OAColors.border2,
                    ),
                  ),
                const Divider(height: 24),
                SwitchListTile(
                  value: _suggestOn,
                  activeColor: OAColors.amberInk,
                  activeTrackColor: OAColors.amber,
                  title: const Text('Yazarken öneri göster',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text('Adres çubuğunda arama önerileri'),
                  onChanged: (v) {
                    setState(() => _suggestOn = v);
                    setSheet(() {});
                    _prefs?.setBool('suggest', v);
                  },
                ),
                const Padding(
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
                      child: const Text('Temizle'),
                    ),
            ),
            const Divider(height: 1),
            Expanded(
              child: items.isEmpty
                  ? const Center(
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
