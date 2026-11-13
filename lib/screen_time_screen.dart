import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'oa_theme.dart';
import 'screen_time.dart';
import 'start_page.dart' show SiteIcon;

import 'i18n.dart';
// Ekran süresi ekranı: bugün / bu hafta, siteler, site ayrıntısı, sınırlar ve ayarlar.

const _gunler = [tx('Pzt', 'Mon'), tx('Sal', 'Tue'), tx('Çar', 'Wed'), tx('Per', 'Thu'), tx('Cum', 'Fri'), tx('Cmt', 'Sat'), tx('Paz', 'Sun')];

/// Basit çubuk grafik. [highlight]: amber gösterilecek çubuk.
Widget barChart(List<int> values, List<String> labels, {int? highlight, double height = 120, int? goalSeconds}) {
  final mx = math.max(values.fold<int>(1, math.max), goalSeconds ?? 0).toDouble();
  return Semantics(
    label: [for (var i = 0; i < values.length; i++) '${labels[i]}: ${fmtDuration(values[i])}'].join(', '),
    child: SizedBox(
      height: height + 22,
      child: Stack(children: [
        if (goalSeconds != null && goalSeconds > 0)
          Positioned(
            left: 0,
            right: 0,
            top: height * (1 - goalSeconds / mx),
            child: Container(height: 1, color: OAColors.faint.withValues(alpha: 0.6)),
          ),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          for (var i = 0; i < values.length; i++)
            Expanded(
              child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                Container(
                  margin: EdgeInsets.symmetric(horizontal: values.length > 12 ? 1.5 : 6),
                  height: math.max(values[i] > 0 ? 3.0 : 1.5, height * values[i] / mx),
                  decoration: BoxDecoration(
                    color: i == highlight ? OAColors.amber : OAColors.text2.withValues(alpha: values[i] > 0 ? 0.55 : 0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 6),
                SizedBox(
                  height: 16,
                  child: Text(labels[i],
                      maxLines: 1,
                      overflow: TextOverflow.visible,
                      style: TextStyle(
                          color: i == highlight ? OAColors.text : OAColors.muted,
                          fontSize: 11.5,
                          fontWeight: i == highlight ? FontWeight.w700 : FontWeight.w500)),
                ),
              ]),
            ),
        ]),
      ]),
    ),
  );
}


class ScreenTimeScreen extends StatefulWidget {
  const ScreenTimeScreen({
    super.key,
    required this.st,
    required this.signedIn,
    required this.onSettingsChanged,
    required this.askNotify,
    this.names = const {},
  });

  final ScreenTime st;
  final bool signedIn;

  /// Haftalık özet ya da birleştirme açılıp kapanınca (bildirim yeniden kurulur, eşitlenir)
  final VoidCallback onSettingsChanged;
  final Future<bool> Function() askNotify;

  /// Kenar çubuğu uygulamaları gibi siteler için görünen ad: site → ad
  final Map<String, String> names;

  @override
  State<ScreenTimeScreen> createState() => _ScreenTimeScreenState();
}

class _ScreenTimeScreenState extends State<ScreenTimeScreen> {
  bool _week = false;
  bool _all = false;

  ScreenTime get st => widget.st;

  String _name(String site) => widget.names[site] ?? site;

  Widget _card({required Widget child, EdgeInsets padding = const EdgeInsets.all(20)}) => Container(
        width: double.infinity,
        padding: padding,
        decoration: BoxDecoration(
          color: OAColors.surface,
          borderRadius: BorderRadius.circular(OARadius.xl),
          border: Border.all(color: OAColors.border),
        ),
        child: child,
      );

  Widget _bars(List<int> values, List<String> labels, {int? highlight, double height = 120, int? goalSeconds}) =>
      barChart(values, labels, highlight: highlight, height: height, goalSeconds: goalSeconds);

  List<String> _weekLabels() {
    final now = DateTime.now();
    return [for (var i = 6; i >= 0; i--) _gunler[now.subtract(Duration(days: i)).weekday - 1]];
  }

  List<String> _hourLabels() => [for (var h = 0; h < 24; h++) h % 6 == 0 ? '$h' : ''];

  Widget _summary() {
    final now = DateTime.now();
    final today = st.totalOn(now, all: _all);
    final yesterday = st.totalOn(now.subtract(const Duration(days: 1)), all: _all);
    final w = st.week(all: _all);
    final weekSum = w.fold<int>(0, (a, b) => a + b);
    final daysUsed = w.where((x) => x > 0).length;
    final avg = daysUsed == 0 ? 0 : weekSum ~/ daysUsed;
    String compare;
    if (_week) {
      compare = tx('Günlük ortalama ${fmtDuration(avg)}', 'Daily average ${fmtDuration(avg)}');
    } else if (yesterday == 0) {
      compare = tx('Dün için kayıt yok', 'No data for yesterday');
    } else {
      final d = today - yesterday;
      compare = d.abs() < 60 ? tx('Dünle aynı', 'Same as yesterday') : tx('Dünden ${fmtDuration(d.abs())} ${d < 0 ? 'az' : 'fazla'}', "${fmtDuration(d.abs())} ${d < 0 ? 'less' : 'more'} than yesterday");
    }
    final goal = st.dailyGoal * 60;
    return _card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(_week ? tx('Son 7 gün', 'Last 7 days') : tx('Bugün', 'Today'), style: TextStyle(color: OAColors.muted, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(fmtDuration(_week ? weekSum : today), style: oaDisplay(44)),
        Text(compare, style: TextStyle(color: OAColors.text2)),
        if (!_week && goal > 0) ...[
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: (today / goal).clamp(0, 1).toDouble(),
              minHeight: 8,
              backgroundColor: OAColors.surface2,
              color: today >= goal ? OAColors.danger : OAColors.amber,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            today >= goal
                ? tx('Günlük hedefin (${fmtDuration(goal)}) doldu', 'Daily goal (${fmtDuration(goal)}) reached')
                : tx('Günlük hedef ${fmtDuration(goal)} · ${fmtDuration(goal - today)} kaldı', 'Daily goal ${fmtDuration(goal)} · ${fmtDuration(goal - today)} left'),
            style: TextStyle(color: today >= goal ? OAColors.danger : OAColors.muted, fontSize: 13),
          ),
        ],
        const SizedBox(height: 22),
        _week
            ? _bars(w, _weekLabels(), highlight: 6, goalSeconds: goal > 0 ? goal : null)
            : _bars(st.hoursOn(now), _hourLabels(), highlight: now.hour, height: 90),
      ]),
    );
  }

  Widget _sites() {
    final now = DateTime.now();
    final list = _week
        ? st.topSites(all: _all)
        : (st.sitesOn(now, all: _all).entries.toList()..sort((a, b) => b.value.compareTo(a.value)));
    if (list.isEmpty) {
      return _card(
        child: Text(
          st.enabled ? tx('Henüz kayıt yok. Siteleri gezdikçe burada görünür.', 'No data yet. Sites appear here as you browse.') : tx('Ölçüm kapalı. Aşağıdan açabilirsin.', 'Tracking is off. You can turn it on below.'),
          style: TextStyle(color: OAColors.muted),
        ),
      );
    }
    final mx = list.first.value.toDouble();
    return _card(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(children: [
        for (final e in list.take(30))
          InkWell(
            onTap: () => _openSite(e.key),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              child: Row(children: [
                SizedBox(
                  width: 34,
                  height: 34,
                  child: SiteIcon(url: 'https://${e.key}', letter: _name(e.key).characters.first.toUpperCase(), size: 34),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(
                        child: Text(_name(e.key),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: OAColors.text, fontWeight: FontWeight.w600)),
                      ),
                      if (st.limits[e.key] != null)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Icon(st.limits[e.key]!.lock ? Icons.lock_clock_outlined : Icons.timer_outlined,
                              size: 16, color: st.overLimit(e.key) ? OAColors.danger : OAColors.muted),
                        ),
                      Text(fmtDuration(e.value), style: TextStyle(color: OAColors.text2, fontWeight: FontWeight.w600)),
                    ]),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: LinearProgressIndicator(
                        value: e.value / mx,
                        minHeight: 5,
                        backgroundColor: OAColors.surface2,
                        color: OAColors.amber.withValues(alpha: 0.85),
                      ),
                    ),
                  ]),
                ),
                const SizedBox(width: 6),
                Icon(Icons.chevron_right, color: OAColors.faint),
              ]),
            ),
          ),
      ]),
    );
  }

  Future<void> _openSite(String site) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: OAColors.bg,
      constraints: const BoxConstraints(maxWidth: 640),
      builder: (_) => _SiteSheet(st: st, site: site, name: _name(site), all: _all),
    );
    if (mounted) setState(() {});
  }

  Future<void> _pickGoal() async {
    final v = await showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(tx('Günlük hedef', 'Daily goal')),
        children: [
          for (final m in const [0, 60, 120, 180, 240, 300, 360])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, m),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(m == 0 ? tx('Hedef yok', 'No goal') : tx('Günde en çok ${m ~/ 60} saat', 'At most ${m ~/ 60} h a day'),
                    style: TextStyle(fontWeight: st.dailyGoal == m ? FontWeight.w700 : FontWeight.w400)),
              ),
            ),
        ],
      ),
    );
    if (v == null) return;
    st.dailyGoal = v;
    st.changed();
    setState(() {});
  }

  Widget _settings() {
    Widget row(IconData icon, String title, String sub, Widget trailing, {VoidCallback? onTap}) => ListTile(
          onTap: onTap,
          leading: Icon(icon, color: OAColors.text2),
          title: Text(title, style: TextStyle(color: OAColors.text, fontWeight: FontWeight.w600)),
          subtitle: Text(sub, style: TextStyle(color: OAColors.muted, fontSize: 13)),
          trailing: trailing,
        );
    return _card(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(children: [
        row(Icons.timer_outlined, tx('Ekran süresini ölç', 'Track screen time'), tx('Yalnız bu cihazda tutulur; gizli sekmeler sayılmaz', "Kept only on this device; private tabs aren't counted"),
            Switch(value: st.enabled, onChanged: (v) => setState(() {
                  st.enabled = v;
                  st.changed();
                }))),
        row(Icons.flag_outlined, tx('Günlük hedef', 'Daily goal'), st.dailyGoal == 0 ? tx('Yok', 'None') : tx('Günde en çok ${st.dailyGoal ~/ 60} saat', 'At most ${st.dailyGoal ~/ 60} h a day'),
            Icon(Icons.chevron_right, color: OAColors.faint),
            onTap: _pickGoal),
        if (Platform.isAndroid)
          row(Icons.notifications_outlined, tx('Haftalık özet', 'Weekly summary'), tx('Pazar akşamı 20:00\'de bir bildirim', 'A notification on Sunday at 8 pm'),
              Switch(
                  value: st.weeklySummary,
                  onChanged: (v) async {
                    if (v) await widget.askNotify();
                    setState(() {
                      st.weeklySummary = v;
                      st.changed();
                    });
                    widget.onSettingsChanged();
                  })),
        row(
          Icons.devices_outlined,
          tx('Cihazları birleştir', 'Combine devices'),
          widget.signedIn
              ? tx('Öbür cihazlarının süreleri de görünür (site başına özet hesabına eşitlenir)', "Your other devices' time is shown too (a per-site summary syncs to your account)")
              : tx('Hesapla giriş yapınca açılabilir', 'Available after you sign in'),
          Switch(
              value: st.mergeDevices && widget.signedIn,
              onChanged: widget.signedIn
                  ? (v) {
                      setState(() {
                        st.mergeDevices = v;
                        if (!v) {
                          st.remote.clear();
                          _all = false;
                        }
                        st.changed();
                      });
                      widget.onSettingsChanged();
                    }
                  : null),
        ),
        row(Icons.delete_outline, tx('Ekran süresi kayıtlarını sil', 'Delete screen time data'), tx('Sınırlar ve hedef kalır', 'Limits and goal are kept'), const SizedBox.shrink(),
            onTap: () async {
          final ok = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: Text(tx('Kayıtlar silinsin mi?', 'Delete data?')),
              content: Text(tx('Bu cihazdaki bütün ekran süresi kayıtları silinir.', 'All screen time data on this device will be deleted.')),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tx('Vazgeç', 'Cancel'))),
                FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tx('Sil', 'Delete'))),
              ],
            ),
          );
          if (ok == true) {
            st.clearAll();
            if (mounted) setState(() {});
          }
        }),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasRemote = st.mergeDevices && st.remote.isNotEmpty;
    return Scaffold(
      backgroundColor: OAColors.bg,
      appBar: AppBar(
        backgroundColor: OAColors.bg,
        title: Text(tx('Ekran süresi', 'Screen time'), style: oaDisplay(22)),
      ),
      body: ListenableBuilder(
        listenable: st,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(value: false, label: Text(tx('Bugün', 'Today'))),
                        ButtonSegment(value: true, label: Text(tx('Bu hafta', 'This week'))),
                      ],
                      selected: {_week},
                      onSelectionChanged: (s) => setState(() => _week = s.first),
                    ),
                    if (hasRemote)
                      SegmentedButton<bool>(
                        segments: const [
                          ButtonSegment(value: false, label: Text(tx('Bu cihaz', 'This device'))),
                          ButtonSegment(value: true, label: Text(tx('Tüm cihazlar', 'All devices'))),
                        ],
                        selected: {_all},
                        onSelectionChanged: (s) => setState(() => _all = s.first),
                      ),
                  ]),
                  const SizedBox(height: 14),
                  _summary(),
                  const SizedBox(height: 22),
                  Text(_week ? tx('Bu hafta en çok', 'Top this week') : tx('Bugün en çok', 'Top today'), style: oaDisplay(18)),
                  const SizedBox(height: 4),
                  Text(tx('Sınır koymak için bir siteye dokun', 'Tap a site to set a limit'), style: TextStyle(color: OAColors.muted, fontSize: 13)),
                  const SizedBox(height: 10),
                  _sites(),
                  const SizedBox(height: 22),
                  Text(tx('Ayarlar', 'Settings'), style: oaDisplay(18)),
                  const SizedBox(height: 10),
                  _settings(),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SiteSheet extends StatefulWidget {
  const _SiteSheet({required this.st, required this.site, required this.name, required this.all});
  final ScreenTime st;
  final String site;
  final String name;
  final bool all;

  @override
  State<_SiteSheet> createState() => _SiteSheetState();
}

class _SiteSheetState extends State<_SiteSheet> {
  ScreenTime get st => widget.st;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final w = st.week(site: widget.site, all: widget.all);
    final hours = st.hoursOn(now, site: widget.site);
    final limit = st.limits[widget.site];
    final today = st.siteOn(widget.site, now, all: widget.all);
    Widget bars(List<int> v, List<String> l, int hi, double h, {int? goal}) =>
        barChart(v, l, highlight: hi, height: h, goalSeconds: goal);
    final weekLabels = [for (var i = 6; i >= 0; i--) _gunler[now.subtract(Duration(days: i)).weekday - 1]];
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(22, 18, 22, 22 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          SizedBox(
            width: 40,
            height: 40,
            child: SiteIcon(url: 'https://${widget.site}', letter: widget.name.characters.first.toUpperCase(), size: 40),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(widget.name, style: oaDisplay(22), maxLines: 1, overflow: TextOverflow.ellipsis)),
          IconButton(tooltip: tx('Kapat', 'Close'), icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
        ]),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(child: _stat(tx('Bugün', 'Today'), fmtDuration(today))),
          const SizedBox(width: 10),
          Expanded(child: _stat(tx('Son 7 gün', 'Last 7 days'), fmtDuration(w.fold<int>(0, (a, b) => a + b)))),
        ]),
        const SizedBox(height: 20),
        Text(tx('Son 7 gün', 'Last 7 days'), style: TextStyle(color: OAColors.muted, fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),
        bars(w, weekLabels, 6, 90, goal: limit != null ? limit.minutes * 60 : null),
        const SizedBox(height: 18),
        Text(tx('Bugün hangi saatlerde', 'Hours used today'), style: TextStyle(color: OAColors.muted, fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),
        bars(hours, [for (var h = 0; h < 24; h++) h % 6 == 0 ? '$h' : ''], now.hour, 60),
        const SizedBox(height: 22),
        Text(tx('Günlük sınır', 'Daily limit'), style: oaDisplay(18)),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final m in const [0, 15, 30, 45, 60, 90, 120, 180])
            ChoiceChip(
              label: Text(m == 0 ? tx('Yok', 'None') : (m < 60 ? tx('$m dk', '$m min') : (m % 60 == 0 ? tx('${m ~/ 60} sa', '${m ~/ 60} h') : tx('${m ~/ 60} sa ${m % 60} dk', '${m ~/ 60} h ${m % 60} min')))),
              selected: (limit?.minutes ?? 0) == m,
              onSelected: (_) => setState(() {
                if (m == 0) {
                  st.limits.remove(widget.site);
                } else {
                  st.limits[widget.site] = SiteLimit(m, lock: limit?.lock ?? false);
                }
                st.changed();
              }),
            ),
        ]),
        if (limit != null) ...[
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: limit.lock,
            onChanged: (v) => setState(() {
              limit.lock = v;
              st.changed();
            }),
            title: Text(tx('Süre dolunca siteyi kilitle', 'Lock the site when time is up'), style: TextStyle(color: OAColors.text, fontWeight: FontWeight.w600)),
            subtitle: Text(
                limit.lock
                    ? tx('Süre dolunca site o gün açılmaz ("15 dakika daha" ile uzatılabilir)', 'When time is up the site won\'t open that day ("15 more minutes" extends it)')
                    : tx('Süre dolunca yalnız uyarı çıkar', 'When time is up you only get a warning'),
                style: TextStyle(color: OAColors.muted, fontSize: 13)),
          ),
        ],
      ]),
    );
  }

  Widget _stat(String label, String value) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: OAColors.surface,
          borderRadius: BorderRadius.circular(OARadius.lg),
          border: Border.all(color: OAColors.border),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(color: OAColors.muted, fontSize: 13)),
          const SizedBox(height: 2),
          Text(value, style: oaDisplay(22)),
        ]),
      );
}
