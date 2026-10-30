# OA Tarayıcı

OA Labs'in Windows ve Android tarayıcısı. Flutter + `flutter_inappwebview`: sayfaları Windows'ta
WebView2 (Edge motoru), Android'de Android WebView çizer; arayüz OA Labs tasarım sistemiyle yazılır.

> Durum: deneme sürümü (0.1.0). Derlenen dosyalar imzasız.

## İndir ve dene

Her `main` gönderiminde GitHub Actions iki dosya derler: **Actions** sekmesi → son "Derle" çalışması → sayfanın altındaki *Artifacts*.

- **OA-Tarayici-Windows** (zip): aç, `oa_tarayici.exe`'yi çalıştır. Kurulum gerekmez. Klasördeki diğer dosyalar exe'nin yanında kalmalı.
  Windows imzasız olduğu için uyarı verirse: "Ek bilgi" → "Yine de çalıştır".
  Windows 10'da WebView2 Runtime yoksa Microsoft'tan ücretsiz kurulur (Windows 11'de hazırdır).
- **OA-Tarayici-Android** (apk): telefona at ve aç. "Bilinmeyen kaynaklardan yükleme" izni ister.

Aynı dosyalar **Releases** sayfasına da `pubspec.yaml`daki sürüm numarasıyla (ör. v0.1.0) deneme sürümü olarak eklenir. Yeni sürüm çıkarmak için `version` satırını artırmak yeterli.

## Özellikler
- Çoklu sekme, gizli sekme (gizli sekmede geçmiş tutulmaz, yazılanlar arama motoruna gönderilmez)
- Adres çubuğu: adres ya da arama; yazarken öneriler, ok tuşlarıyla gezinme
- Arama motoru seçimi: DuckDuckGo (varsayılan), Google, Bing, Yandex, Brave Search, Ecosia, Startpage
- Yer imleri ve geçmiş (cihazda saklanır)
- Geri / ileri / yenile-durdur / ana sayfa, yükleme çubuğu
- `target=_blank` bağlantıları yeni sekmede açılır; Android geri tuşu desteği
- Klavye: Ctrl+T yeni sekme, Ctrl+L adres çubuğu

## Dosyalar
- `lib/main.dart` — tarayıcı arayüzü ve sekmeler
- `lib/search.dart` — arama motorları ve öneri adresleri
- `lib/oa_theme.dart` — OA Labs renkleri, fontları (Bricolage Grotesque, DM Sans) ve bileşen stilleri
- `scripts/platform_hazirla.sh` — `windows/` ve `android/` klasörlerini üretir; internet izni, uygulama adı, pencere başlığı
- `docs/onizleme.html` — arayüzün tarayıcıda açılan önizlemesi
- `.github/workflows/derle.yml` — exe ve apk derlemesi

## Kendi bilgisayarında derlemek
Flutter SDK (stable), Windows için Visual Studio 2022 (C++ masaüstü iş yükü) ve NuGet, Android için Android Studio.

```
bash scripts/platform_hazirla.sh windows,android   # Windows'ta Git Bash ile
flutter pub get
flutter run -d windows
flutter build apk --release
```

## Sıradakiler
- OA başlangıç sayfası ("Nereye gidiyoruz?")
- İndirme yöneticisi
- Uygulama ikonu
- Kurulum programı ve OA Labs güncelleme sistemi (`latest.json`)
- Android için gerçek imza anahtarı
