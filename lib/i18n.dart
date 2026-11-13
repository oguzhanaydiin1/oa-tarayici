import 'dart:ui' as ui;

/// Uygulama dili. Açılışta bir kez belirlenir (Ayarlar → Görünüm → Dil);
/// değişiklik uygulama yeniden açılınca geçerli olur, açık sekmeler kaybolmasın diye.
class L {
  L._();

  /// 'auto' (cihazın dili), 'tr' ya da 'en'.
  static String choice = 'auto';

  /// Şu an kullanılan dil: 'tr' ya da 'en'.
  static String code = 'tr';

  static bool get en => code == 'en';

  static void init(String? saved) {
    choice = (saved == 'tr' || saved == 'en') ? saved! : 'auto';
    if (choice != 'auto') {
      code = choice;
      return;
    }
    String sys = 'tr';
    try {
      sys = ui.PlatformDispatcher.instance.locale.languageCode.toLowerCase();
    } catch (_) {}
    // Türkçe cihazda Türkçe, diğer her dilde İngilizce.
    code = sys == 'tr' ? 'tr' : 'en';
  }
}

/// Ekrandaki metin: Türkçesi ve İngilizcesi yan yana yazılır.
String tx(String tr, String en) => L.code == 'en' ? en : tr;
