import 'package:flutter/material.dart';

import 'oa_theme.dart';

// Sekme grupları (bilgisayar): sekmeler adlı ve renkli gruplara ayrılır, grup daraltılabilir.

const kGroupColors = <Color>[
  Color(0xFFF2A541), // amber
  Color(0xFF6EA8FE), // mavi
  Color(0xFF5BC48C), // yeşil
  Color(0xFFF0729A), // pembe
  Color(0xFFA78BFA), // mor
  Color(0xFF5CC8D7), // camgöbeği
  Color(0xFFF08A7E), // kırmızı
  Color(0xFF9EA2B3), // gri
];

class TabGroup {
  TabGroup({required this.id, required this.name, this.color = 0, this.collapsed = false});
  final String id;
  String name;
  int color;
  bool collapsed;

  Color get c => kGroupColors[color % kGroupColors.length];

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'color': color, 'collapsed': collapsed};
  static TabGroup? fromJson(Map j) {
    final id = j['id']?.toString();
    if (id == null) return null;
    return TabGroup(
      id: id,
      name: j['name']?.toString() ?? '',
      color: (j['color'] as num?)?.toInt() ?? 0,
      collapsed: j['collapsed'] == true,
    );
  }
}

/// Grup adı ve rengi. Vazgeçilirse null.
Future<(String, int)?> editGroupDialog(BuildContext context, {String name = '', int color = 0, bool isNew = true}) {
  final ctl = TextEditingController(text: name);
  var sel = color;
  return showDialog<(String, int)>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setD) => AlertDialog(
        title: Text(isNew ? 'Yeni sekme grubu' : 'Grubu düzenle'),
        content: SizedBox(
          width: 360,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            TextField(
              controller: ctl,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Grup adı', hintText: 'Örn. İş, Alışveriş, Okunacaklar'),
              onSubmitted: (_) => Navigator.pop(ctx, (ctl.text.trim(), sel)),
            ),
            const SizedBox(height: 16),
            Text('Renk', style: TextStyle(color: OAColors.muted, fontSize: 13)),
            const SizedBox(height: 8),
            Wrap(spacing: 10, runSpacing: 10, children: [
              for (var i = 0; i < kGroupColors.length; i++)
                InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () => setD(() => sel = i),
                  child: Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: kGroupColors[i],
                      shape: BoxShape.circle,
                      border: Border.all(color: sel == i ? OAColors.text : Colors.transparent, width: 2.5),
                    ),
                    child: sel == i ? const Icon(Icons.check, size: 16, color: Color(0xFF14110A)) : null,
                  ),
                ),
            ]),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(ctx, (ctl.text.trim(), sel)), child: Text(isNew ? 'Oluştur' : 'Kaydet')),
        ],
      ),
    ),
  );
}
