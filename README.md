# OA Tarayıcı

OA Labs'in Windows ve Android tarayıcısı. Flutter + `flutter_inappwebview`: sayfaları Windows'ta
WebView2 (Edge motoru), Android'de Android WebView çizer; arayüz OA Labs tasarım sistemiyle yazılır.

> Durum: deneme sürümü (0.5.2). Derlenen dosyalar imzasız.

## İndir ve dene

Her `main` gönderiminde GitHub Actions iki dosya derler: **Actions** sekmesi → son "Derle" çalışması → sayfanın altındaki *Artifacts*.

- **OA-Tarayici-Windows** (zip): aç, `oa_tarayici.exe`'yi çalıştır. Kurulum gerekmez. Klasördeki diğer dosyalar exe'nin yanında kalmalı.
  Windows imzasız olduğu için uyarı verirse: "Ek bilgi" → "Yine de çalıştır".
  Windows 10'da WebView2 Runtime yoksa Microsoft'tan ücretsiz kurulur (Windows 11'de hazırdır).
- **OA-Tarayici-Android** (apk): telefona at ve aç. "Bilinmeyen kaynaklardan yükleme" izni ister.

Aynı dosyalar **Releases** sayfasına da `pubspec.yaml`daki sürüm numarasıyla (ör. v0.1.0) deneme sürümü olarak eklenir. Yeni sürüm çıkarmak için `version` satırını artırmak yeterli.

## Özellikler
- Reklam ve izleyici engelleme: reklam ağlarına ve izleyicilere giden istekler engellenir (Android'de web motorunun içerik engelleyicisi, Windows'ta istek kontrolü), sayfadaki reklam kutuları gizlenir; site bazında kapatılabilir
- Tablo: hızlı erişimde sitelerin ikonları, "Düzenle" ile sürükleyip sıralama, başlangıç sayfası arka planları (OA desenleri ya da kendi fotoğrafın)
- Akıllı adres çubuğu: hesap makinesi (`125*18`), birim (`10 km`, `30 c kaç f`), döviz (`100 dolar`, `50 euro kaç tl`; Avrupa Merkez Bankası kurları, frankfurter.dev)
- Okuma modu (Mozilla Readability) ve "Türkçeye çevir" (Google Çeviri)
- Telefonda: aşağı çekip yenile, adres çubuğunda sağa-sola kaydırıp sekme değiştir, QR kod / barkod okut
- OA hesabıyla eşitleme: yer imleri ve hızlı erişim cihazlar arasında taşınır (sunucu: radyo-app `/v1/me/sync`)
- OA Labs hesabıyla giriş: sitedeki üyelikle aynı (e-postaya gelen kodla, şifresiz). Oturum cihazın güvenli deposunda saklanır ve tarayıcının içindeki oalabs.dev'e de aktarılır; sitede giriş yapılırsa uygulama da öğrenir
- Koyu / açık tema (ya da sistemi izle). DuckDuckGo sonuçları da seçilen temada açılır
- Hızlı erişim düzenlenebilir: telefonda basılı tut, bilgisayarda sağ tıkla → Düzenle / Kaldır / Yeni sekmede aç; "Ekle" kutusu, menüde "Bu sayfayı hızlı erişime ekle"
- Telefon başlangıç sayfası: arka plan ekranın en üstüne kadar, ortada OA logosu ve arama kutusu (reklam engelleme kalkanıyla), OA uygulama kartları, uygulama simgesi gibi hızlı erişim (5 sütun); sağ üstte QR ve Özelleştir
- OA başlangıç sayfası: "Nereye gidiyoruz?", arama, hızlı erişim, yer imleri (yeni sekmede ve ana sayfa düğmesinde)
- Telefonda saatin olduğu üst şerit açık sitenin rengini alır (theme-color ya da sayfa zemini); aşağı kaydırınca alt çubuk incelir, yukarı kaydırınca açılır
- Telefon düzeni (Android): adres çubuğu ve düğmeler altta; adres çubuğu alan adını gösterir, dokununca düzenlenir; sekmeler kart görünümünde
- Çoklu sekme, gizli sekme (gizli sekmede geçmiş tutulmaz, yazılanlar arama motoruna gönderilmez)
- Adres çubuğu: adres ya da arama; yazarken öneriler, ok tuşlarıyla gezinme
- Arama motoru seçimi: DuckDuckGo (varsayılan), Google, Bing, Yandex, Brave Search, Ecosia, Startpage
- Yer imleri ve geçmiş (cihazda saklanır)
- Geri / ileri / yenile-durdur / ana sayfa, yükleme çubuğu
- `target=_blank` bağlantıları yeni sekmede açılır; Android geri tuşu desteği
- Klavye: Ctrl+T yeni sekme, Ctrl+L adres çubuğu

## Dosyalar
- `lib/main.dart` — tarayıcı arayüzü (bilgisayar ve telefon düzeni) ve sekmeler
- `lib/start_page.dart` — OA başlangıç sayfası ve hızlı erişim
- `lib/account.dart`, `lib/account_sheet.dart` — OA Labs üyeliği (api.oalabs.dev) ve giriş ekranı
- `lib/search.dart` — arama motorları ve öneri adresleri
- `lib/adblock.dart` — engelleme listesi ve kuralları
- `lib/smart.dart` — hesap makinesi, birim ve döviz cevapları
- `lib/reader.dart`, `assets/readability.js`, `assets/reader.js` — okuma modu (Readability: Apache 2.0, Mozilla)
- `lib/wallpaper.dart` — başlangıç sayfası arka planları
- `lib/qr_page.dart` — QR / barkod okuyucu (Android)
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
- İndirme yöneticisi
- Uygulama ikonu
- Kurulum programı ve OA Labs güncelleme sistemi (`latest.json`)
- Android için gerçek imza anahtarı
