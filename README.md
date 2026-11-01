# OA Tarayıcı

OA Labs'in Windows ve Android tarayıcısı. Flutter + `flutter_inappwebview`: sayfaları Windows'ta
WebView2 (Edge motoru), Android'de Android WebView çizer; arayüz OA Labs tasarım sistemiyle yazılır.

> Durum: deneme sürümü (0.13.0). Android sürümü sabit OA anahtarıyla imzalı; Windows dosyaları imzasız.

## İndir ve dene

Her `main` gönderiminde GitHub Actions iki dosya derler: **Actions** sekmesi → son "Derle" çalışması → sayfanın altındaki *Artifacts*.

- **OA-Tarayici-Kurulum.exe**: Windows kurulum programı (yönetici izni istemez). Kurunca OA Tarayıcı, Ayarlar → Varsayılan uygulamalar'da tarayıcı olarak seçilebilir.
- **OA-Tarayici-Windows** (zip): kurmadan denemek için; aç, `oa_tarayici.exe`'yi çalıştır. Klasördeki diğer dosyalar exe'nin yanında kalmalı.
  Windows imzasız olduğu için uyarı verirse: "Ek bilgi" → "Yine de çalıştır".
  Windows 10'da WebView2 Runtime yoksa Microsoft'tan ücretsiz kurulur (Windows 11'de hazırdır).
- **OA-Tarayici-Android** (apk): telefona at ve aç. "Bilinmeyen kaynaklardan yükleme" izni ister.

Aynı dosyalar **Releases** sayfasına da `pubspec.yaml`daki sürüm numarasıyla (ör. v0.1.0) deneme sürümü olarak eklenir. Yeni sürüm çıkarmak için `version` satırını artırmak yeterli.

## Özellikler
- Ayarlar ayrı bir ekranda (menü → Ayarlar, Ctrl+,): uygulamanın üzerine kayarak açılır; başlıklar, ayarlarda arama; menü kısaldı, sayfa araçları "Bu sayfa" altında
- Eşitleme (OA hesabı): öbür cihazlardaki açık sekmeler, sekmeyi öbür cihaza gönderme, geçmiş, ve şifreler (eşitleme parolasıyla uçtan uca şifreli; sunucu içini göremez)
- Haber akışı: başlangıç sayfasında seçilen sitelerin son haberleri (RSS; BBC Türkçe, NTV, DW Türkçe, Webtekno… ve kendi eklediğin kaynaklar)
- Döviz ve altın: dolar, euro, gram altın ve günlük değişim
- Sonra oku: yazılar resimleriyle cihaza kaydedilir, internetsiz okunur
- Sekme grupları (sağ tık → gruba ekle; adlı, renkli, daraltılabilir) ve dikey sekmeler (Windows)
- Chrome / Edge / Firefox'tan içe aktarma: yer imleri (.html) ve şifreler (.csv)
- Çerez pencerelerini kendiliğinden reddetme ("Çerezleri kabul et" pencerelerinde reddet / yalnız gerekli)
- Sesli arama (Android, adres çubuğundaki mikrofon)
- Sitelere karanlık mod: site başına ya da bütün sitelerde; sayfa zaten koyuysa dokunmaz
- Site başına yakınlaştırma (Ctrl + / Ctrl − / Ctrl 0), her site için hatırlanır
- Tam sayfa ekran görüntüsü (Windows)
- Android ana ekran widget'ları: OA arama (arama kutusu, QR, gizli sekme) ve OA saat ve hava (uygulama kapalıyken de yenilenir); simgeye basılı tutunca kısayollar: yeni sekme, gizli sekme, QR, OA Radyo
- Başlangıç sayfasında saat, tarih ve hava durumu (Open-Meteo): bilgisayarda sağ üst köşede, telefonda arama kutusunun altında tahminli kart; dokununca saatlik ve 7 günlük tahmin, şehir seçimi
- Telefonda radyo arka planda çalar: uygulamadan çıkınca ya da ekran kilitlenince susmaz; bildirimde ve kilit ekranında oynat/durdur
- Windows'ta radyo, klavyedeki medya tuşlarıyla ve Windows'un ses panelindeki çalarla kontrol edilir
- Windows'ta tek pencere: OA Tarayıcı açıkken bir bağlantıya tıklanınca açık pencerede yeni sekme olarak açılır
- Gizli sekme kilidi: uygulamadan çıkınca gizli sekmeler kilitlenir; parmak izi, yüz, ekran kilidi ya da Windows Hello ile açılır
- Sayfada bul (Ctrl+F) ve PDF olarak kaydet (Ctrl+P; telefonda yazdırma ekranından "PDF olarak kaydet")
- Videoyu küçük pencerede izle: telefonda resim içinde resim; Windows'ta pencere küçülüp her zaman üstte kalır
- Şifreler: girişte kaydetmeyi sorar, bir dahaki sefere kendiliğinden doldurur; yalnız cihazın güvenli deposunda saklanır, listeyi görmek için kimlik doğrulanır
- İndirme yöneticisi: ilerleme, İndirilenler listesi (Ctrl+J), bitince aç; Android'de telefonun İndirilenler klasörüne
- Sekmeler uygulama kapanıp açılınca geri gelir; kapatılan sekmeyi geri aç (Ctrl+Shift+T)
- Varsayılan tarayıcı olabilir: Android'de bağlantılar OA Tarayıcı'da açılabilir; Windows kurulumu tarayıcı olarak kaydeder
- Uygulama ikonu (OA işareti) ve kendini güncelleme: yeni sürüm çıkınca haber verir, tek dokunuşla indirip kurar
- OA Radyo: gezinirken radyo dinle; popüler Türk istasyonları, arama, favoriler, alt çubuğun üstünde mini çalar
- Reklam ve izleyici engelleme: reklam ağlarına ve izleyicilere giden istekler engellenir (Android'de web motorunun içerik engelleyicisi, Windows'ta istek kontrolü), sayfadaki reklam kutuları gizlenir; site bazında kapatılabilir
- Tablo: hızlı erişimde sitelerin ikonları, "Düzenle" ile sürükleyip sıralama, başlangıç sayfası arka planları (OA desenleri ya da kendi fotoğrafın)
- Akıllı adres çubuğu: hesap makinesi (`125*18`), birim (`10 km`, `30 c kaç f`), döviz (`100 dolar`, `50 euro kaç tl`; Avrupa Merkez Bankası kurları, frankfurter.dev)
- Okuma modu (Mozilla Readability) ve "Türkçeye çevir" (Google Çeviri)
- Telefonda: aşağı çekip yenile, adres çubuğunda sağa-sola kaydırıp sekme değiştir, QR kod / barkod okut
- OA hesabıyla eşitleme: yer imleri, hızlı erişim, açık sekmeler, geçmiş ve şifreler (sunucu: radyo-app `/v1/me/sync`)
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
- Klavye: Ctrl+T yeni sekme, Ctrl+W sekmeyi kapat, Ctrl+L adres çubuğu, Ctrl+F sayfada bul, Ctrl+P PDF, Ctrl+J indirilenler

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
- `lib/downloads.dart` — indirme yöneticisi (background_downloader)
- `lib/radio.dart`, `assets/hls.min.js` — OA Radyo çalar (Radio Browser, OA Radyo'nun ek istasyonları)
- `lib/updater.dart` — GitHub sürümlerinden güncelleme denetimi
- `lib/weather.dart` — saat, tarih, hava durumu (Open-Meteo) ve şehir seçimi
- `lib/settings_screen.dart` — Ayarlar ekranı
- `lib/vault.dart` — şifre kasası (PBKDF2 + AES-256-GCM)
- `lib/passwords.dart` — şifre deposu, cihaz kilidiyle doğrulama, Şifreler listesi
- `lib/news.dart`, `lib/markets.dart`, `lib/read_later.dart`, `lib/tab_groups.dart` — haber akışı, döviz/altın, okuma listesi, sekme grupları
- `lib/extras.dart` — çerez pencereleri, karanlık mod, yakınlaştırma, içe aktarma
- `lib/page_tools.dart` — sayfada bul, videoyu küçük pencerede izleme, şifre yakalama/doldurma betikleri
- `platform/android/` — Android'e kopyalanan Kotlin ve kaynaklar (MainActivity, widget'lar, kısayollar)
- `platform/windows/runner/` — Windows giriş noktası (tek pencere)
- `scripts/android_ayarla.py` — Android tarayıcı kaydı, kurulum izni, sabit imza
- `installer/oa_tarayici.iss` — Windows kurulum programı (Inno Setup)
- `assets/icon/` — uygulama ikonu
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
- Şifreleri ve açık sekmeleri OA hesabıyla cihazlar arasında (uçtan uca şifreli) eşitleme
