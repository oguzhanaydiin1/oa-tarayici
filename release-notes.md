# OA Tarayıcı sürüm notları

Yeni bir sürüm çıkarırken `pubspec.yaml`'daki sürüm numarasıyla bir başlık ekle.
Derleme, o sürümün başlığını burada bulursa altındaki maddeleri GitHub Releases'taki
sürüm notuna kendisi yazar. Başlık yoksa sürüm notuna dokunulmaz.

Biçim (başlık tam olarak `## ` ve sürüm numarası olmalı):

    ## X.Y.Z
    • Türkçe madde
    • Bir madde daha

    • English item
    • Another item

En yeni sürüm en üstte olsun.

## 0.20.0
• OA Labs Center ile tek giriş: Windows'ta OA Labs Center'da giriş yaptıysan Pusula açılınca kendiliğinden girişli gelir; Pusula'da girdiysen OA Labs Center da girişli açılır.
• Telefonda giriş penceresinde "OA Labs Center ile giriş yap": kod beklemeden, tek onayla.
• Her uygulamanın kendi oturumu olur; oalabs.dev'deki cihaz listesinde ayrı görünür.

• Single sign-on with OA Labs Center: on Windows, if you're signed in to OA Labs Center, Pusula opens signed in, and the other way round.
• On the phone, the sign-in window has "Sign in with OA Labs Center": no code to wait for, one tap to approve.
• Each app gets its own session and shows up separately in your device list on oalabs.dev.

## 0.14.5
• OA Labs hesabına profil fotoğrafı eklediysen, uygulamada baş harflerin yerine artık fotoğrafın görünüyor. Fotoğrafı oalabs.dev’de Hesabım sayfasından ekleyip değiştirebilirsin; yalnızca sen görürsün.

• If you’ve added a profile photo to your OA Labs account, the app now shows it instead of your initials. Add or change it on the My account page at oalabs.dev; only you can see it.

## 0.14.6
• Profil fotoğrafını ya da adını oalabs.dev’de değiştirdiğinde uygulama artık bunu hemen öğreniyor: hesap menüsünü açınca, uygulamaya geri dönünce ya da oalabs.dev’de bir sayfa açınca yenileniyor. Önceden uygulamayı kapatıp açmak gerekiyordu.

• When you change your profile photo or name on oalabs.dev, the app now picks it up right away: when you open the account menu, come back to the app or open a page on oalabs.dev. Previously you had to restart the app.

## 0.14.7
• Yeni sekme artık açık olan sekmenin hemen yanında açılıyor, en sonda değil. Bir grubun içinden açarsan o gruba katılıyor.
• Yeni sekme açınca imleç doğrudan arama kutusunda; tıklamadan yazmaya başlayabilirsin.

• New tabs now open right next to the current tab instead of at the end. Opened inside a tab group, they join that group.
• When you open a new tab, the cursor is already in the search box, so you can start typing right away.

## 0.14.8
• Bilgisayarda yeni sekme (+) düğmesi artık sekme şeridinin en sağında değil, en son sekmenin hemen yanında.

• On desktop, the new tab (+) button now sits right next to the last tab instead of at the far right of the tab strip.

## 0.15.0
• Sabitlenmiş sekmeler: sekmeye sağ tıkla → "Sekmeyi sabitle". Şeridin başında küçük simge olarak durur, yanlışlıkla kapanmaz.
• Komut kutusu (Ctrl+K): komutlara, açık sekmelere, ayarlara ve yer imlerine klavyeden ulaş.
• Fare hareketleri (bilgisayar): sağ tuşa basılı tutup çek; sola geri, sağa ileri, yukarı yenile, aşağı sekmeyi kapat.
• QR kod ile telefona aktar: açık sayfanın QR kodunu telefonla okut.
• Vurgu rengi ve hazır temalar: Ayarlar → Görünüm.
• Sayfa açılamayınca OA hata sayfası; internet yoksa küçük bir oyun.

• Pinned tabs: right-click a tab → "Pin tab". It stays at the start of the strip as a small icon and can't be closed by accident.
• Command box (Ctrl+K): reach commands, open tabs, settings and bookmarks from the keyboard.
• Mouse gestures (desktop): hold the right button and drag; left for back, right for forward, up to reload, down to close the tab.
• Send to phone with a QR code: scan the current page's QR code with your phone.
• Accent colour and ready-made themes: Settings → Appearance.
• OA error page when a page can't be opened, with a small game when you're offline.

## 0.16.0
• Yan yana görünüm (bilgisayar): sekmeye sağ tıkla → "Açık sekmeyle yan yana göster" ya da menü → "Yan yana yeni sekme". Ortadaki çizgiyi sürükleyerek genişliği ayarla; tıkladığın taraf etkin sekme olur.
• Sekme önizlemesi: bilgisayarda bir sekmenin üzerine gelince sayfanın küçük resmi çıkar; telefonda sekme listesindeki kartlarda da sayfa görünür.
• Sesli oku: menü → "Sesli oku". Sayfanın yazısı cihazın Türkçe sesiyle okunur; alttaki şeritten duraklat, ileri/geri atla, hızı seç. Radyo çalıyorsa susar.

• Split view (desktop): right-click a tab → "Show side by side with the current tab", or menu → "New tab side by side". Drag the divider to resize; the side you click becomes the active tab.
• Tab previews: hover a tab on desktop to see a thumbnail of the page; the cards in the phone's tab list show the page too.
• Read aloud: menu → "Read aloud". The page's text is read with the device's Turkish voice; pause, skip back/forward and pick the speed from the bar at the bottom. The radio pauses if it's playing.

## 0.17.0
• OA Akış: menü → "OA Akış". Aynı hesapla giriş yaptığın telefona ya da bilgisayara not, bağlantı, fotoğraf ve dosya (600 KB'a kadar) gönder. Gelen dosyalar İndirilenler klasörüne kaydedilir; akış geçmişi sohbet gibi görünür.
• Oyun köşesi: başlangıç sayfasında Epic Games'te şu an ve yakında ücretsiz olan oyunlar ile Steam'in öne çıkan indirimleri. Ayarlar → Başlangıç sayfasından kapatılabilir.
• Eşitleme aynı anda iki kez çalışmaz; öbür cihazdan gönderilenlerin kaybolma ihtimali azaldı.

• OA Flow: menu → "OA Flow". Send notes, links, photos and files (up to 600 KB) to your phone or computer signed in with the same account. Received files are saved to Downloads; the flow history looks like a chat.
• Game corner: the start page shows games that are free now or soon on the Epic Games Store and Steam's featured deals. You can turn it off in Settings → Start page.
• Sync no longer runs twice at the same time, so items sent from another device are less likely to get lost.

## 0.18.0
• Tarayıcının yeni adı Pusula Browser. Yeni simgesi koyu bir karede rüzgâr gülü; kuzeyi gösteren kolu amber.
• Windows'ta pencere başlığı, Başlat menüsü ve masaüstü kısayolu yeni adla görünür; eski kısayollar kaldırılır. Android'de simgenin altında "Pusula" yazar.
• Başlangıç sayfasında ve Hakkında penceresinde yeni logo.
• Yer imlerin, şifrelerin, sekmelerin ve ayarların olduğu gibi kalır; güncelleme eski kurulumun üstüne yapılır.

• The browser's new name is Pusula Browser. Its new icon is a compass rose on a dark square, with the north arm in amber.
• On Windows the window title, Start menu and desktop shortcut use the new name, and the old shortcuts are removed. On Android the icon is labelled "Pusula".
• The new logo is on the start page and in the About window.
• Your bookmarks, passwords, tabs and settings stay as they are; the update installs over the old version.

## 0.18.1
• Bütün sekmeleri tek seferde kapat: telefonda sekme listesinin üstündeki "Tümünü kapat", bilgisayarda sekmeye sağ tıklayıp "Bütün sekmeleri kapat" ya da Ctrl+Shift+W. Yanlışlıkla kapattıysan alttaki "Geri al" hepsini geri açar. Sabitlenmiş sekmeler kalır.
• Telefonda sekme listesinde bir kartı sola kaydırınca o sekme kapanır.

• Close all tabs at once: "Close all" at the top of the tab list on your phone, or right-click a tab → "Close all tabs" (Ctrl+Shift+W) on your PC. If you didn't mean it, "Undo" at the bottom brings them all back. Pinned tabs stay.
• On your phone, swipe a card to the left in the tab list to close that tab.

## 0.18.2
• Windows: TV+ gibi canlı yayın sitelerinde çıkan "geliştirici araçlarını kapatıp sayfayı yenileyin" uyarısı düzeltildi. Tarayıcı bu sitelere artık geliştirici araçları açıkmış gibi görünmüyor.

• Windows: fixed the "close developer tools and reload the page" warning on live TV sites such as TV+. The browser no longer looks to these sites as if developer tools were open.

## 0.18.3
• Windows: TV+, Netflix, Disney+, Prime Video, Exxen gibi kopya korumalı yayınlarda ses gelip görüntünün siyah kalması düzeltildi. Bu siteler video başlayınca ayrı bir Pusula penceresinde açılır; oturumun açık kalır.
• Listede olmayan bir site korumalı video oynatırsa üstte bir uyarı çıkar: "Ayrı pencerede aç" ya da "Hep ayrı aç". Menüde de "Ayrı pencerede aç (video görünmüyorsa)" var.

• Windows: fixed sound playing with a black picture on copy-protected streams such as TV+, Netflix, Disney+, Prime Video and Exxen. These sites open in a separate Pusula window when the video starts, and you stay signed in.
• If a site that isn't on the list plays protected video, a banner offers "Open in a separate window" or "Always open separately". The menu also has "Open in a separate window (if the video doesn't show)".

## 0.18.4
• Windows: TV+ gibi sitelerde oynatıcı sayfanın içindeki ayrı bir çerçevede çalıştığı için ayrı pencere kendiliğinden açılmıyordu; düzeltildi.
• "Videoyu ayrı pencerede aç" artık ana menüde (önceden "Bu sayfa" alt menüsündeydi). Komut kutusunda da var.
• Video, sekmede de normal sayfa katmanında çizilir; bazı sitelerde görüntünün siyah kalması bununla da düzelebilir.

• Windows: on sites like TV+ the player runs in a separate frame inside the page, so the separate window didn't open by itself; fixed.
• "Open video in a separate window" is now in the main menu (it used to be under "This page"), and in the command box too.
• Video is now also drawn in the normal page layer inside the tab, which can fix a black picture on some sites.

## 0.18.5
• Windows: TV+, Netflix, Disney+ gibi kopya korumalı yayınlar artık ayrı pencere açmadan sekmenin içinde oynar. Video başlayınca sayfa, sekmenin yerinde web motorunun doğrudan çizdiği bir alana geçer; görüntü siyah kalmaz.
• Geri tuşu önce videonun içinde geri gider, en başta sekmenin kendi sayfasına döner. Menü → "Korumalı videodan çık" da aynısını yapar.
• Listede olmayan bir sitede görüntü gelmiyorsa menü → "Video görünmüyorsa düzelt".
• Menü ya da ayarlar açıkken video geçici olarak gizlenir, kapanınca geri gelir.

• Windows: copy-protected streams such as TV+, Netflix and Disney+ now play inside the tab, without a separate window. When the video starts, the page moves into an area of the tab that the web engine draws directly, so the picture is no longer black.
• Back first goes back inside the video page, and at the start returns to the tab's own page. Menu → "Exit protected video" does the same.
• If the picture doesn't show on a site that isn't on the list, use menu → "Fix video not showing".
• While a menu or settings is open the video is hidden for a moment and comes back when it closes.

## 0.18.6
• Windows: sekmenin içinde oynayan korumalı videonun uygulamanın altında kalmaması için eksik kalan düzeltme tamamlandı.

• Windows: completed a fix that was left out, so protected video playing inside the tab no longer ends up underneath the app.

## 0.18.7
• Geri tuşu düzeltildi: Trendyol gibi siteler bir ürünü yeni sekmede açınca, o sekmede geri basınca ana sayfa yerine ürünü açtığın sayfaya dönersin (yeni sekme kapanır).

• Fixed the Back button: when a site like Trendyol opens a product in a new tab, pressing Back in that tab takes you to the page you opened it from instead of the start page (the new tab closes).

## 0.18.8
• Windows: bir site bağlantıyı yeni sekmede açınca bulunduğun sekme de aynı sayfaya gidiyordu (Trendyol, Hürriyet gibi); artık yalnız yeni sekme açılır, geri basınca kaldığın sayfaya dönersin.
• Windows: uygulamayı kapatınca bir sonraki açılışta çıkan "Pusula geçen sefer beklenmedik şekilde kapandı" uyarısı düzeltildi (kapanışta olan bir çökmeydi).
• TV+ canlı yayın gibi kopya korumasız videolar artık sekmenin kendisinde oynar; ayrı alana yalnız gerçekten korumalı videolarda geçilir. Bu alanda geri basınca doğrudan önceki sayfaya dönülür.
• Sekme önizlemesi: sayfanın küçük resmi artık görünüyor.
• Başlangıç sayfasında saat, hava ve kurlar kutusu dar pencerede arama kutusunun üstüne binmiyor.
• Bağlantının üstüne gelince sol altta çıkan adres baloncuğu başka sekmelerde takılı kalıyordu; kaldırıldı.
• Ctrl+Shift+N ile gizli sekme açılır. Komut kutusunda adı aradığınla başlayan komutlar en üstte.
• Sekme şeridinin solunda yeni Pusula logosu.

• Windows: when a site opened a link in a new tab, the tab you were on also went to the same page (Trendyol, Hürriyet and others); now only the new tab opens, and Back returns you to where you were.
• Windows: fixed the "Pusula closed unexpectedly last time" warning that appeared after closing the app (it was a crash on shutdown).
• Videos without copy protection, such as TV+ live streams, now play in the tab itself; the separate area is used only for truly protected video. Back in that area goes straight to the previous page.
• Tab previews: the page thumbnail now shows.
• On the start page, the clock, weather and currency box no longer covers the search box in a narrow window.
• The link address bubble at the bottom left (when hovering a link) got stuck on other tabs; it has been removed.
• Ctrl+Shift+N opens a private tab. In the command box, commands whose name starts with what you typed come first.
• The new Pusula logo at the left of the tab strip.

## 0.18.9
• Windows: videolarda tam ekran düzeltildi (TV+, YouTube ve diğerleri). Oynatıcının tam ekran düğmesine basınca pencere tam ekran olur, sekme şeridi, adres çubuğu ve kenar çubuğu gizlenir. Esc ya da oynatıcının düğmesi geri getirir; başka sekmeye geçince de tam ekrandan çıkılır.

• Windows: fixed fullscreen for videos (TV+, YouTube and others). Pressing the player's fullscreen button now makes the window fullscreen and hides the tab strip, address bar and sidebar. Esc or the player's button brings them back, and switching to another tab also exits fullscreen.

## 0.19.0
• Ekran süresi: menü → "Ekran süresi". Bugün ve bu hafta tarayıcıda ne kadar kaldığın, günlere ve saatlere göre grafik, en çok vakit geçirdiğin siteler. Veriler yalnız bu cihazda tutulur; gizli sekmeler sayılmaz. 2 dakika dokunulmazsa sayaç durur, video ya da radyo çalıyorsa devam eder.
• Site süre sınırı: bir siteye dokunup günlük sınır koy. Süre dolunca uyarı çıkar; istersen site o gün kilitlenir ("15 dakika daha" ile uzatılabilir).
• Günlük hedef: hedefe yaklaşınca ve dolunca haber verir.
• Haftalık özet (Android): pazar akşamı 20:00'de "Bu hafta … geçirdin" bildirimi.
• Cihazları birleştir (isteğe bağlı): hesapla giriş yaptıysan telefon ve bilgisayarın süreleri birlikte görünür.

• Screen time: menu → "Screen time". How long you spent in the browser today and this week, charts by day and hour, and the sites you spent the most time on. The data stays on this device, and private tabs are not counted. The timer pauses after 2 minutes without touching anything, but keeps going while video or the radio plays.
• Site time limit: tap a site to set a daily limit. When the time is up you get a warning, or if you choose, the site is locked for the day (you can extend it with "15 more minutes").
• Daily goal: lets you know when you're close to your goal and when you reach it.
• Weekly summary (Android): a "This week you spent …" notification on Sunday at 8 pm.
• Merge devices (optional): if you're signed in, your phone's and computer's times show together.

## 0.19.1
• Windows: dizüstü bilgisayarlarda touchpad'de iki parmakla kaydırınca sayfalar kaymıyordu; düzeltildi. Yavaş kaydırmalar da işlenir, hız parmağın hareketine yakındır.

• Windows: on laptops, pages didn't scroll with a two-finger swipe on the touchpad; fixed. Slow swipes work too, and the speed follows your fingers closely.

## 0.19.2
• Windows: touchpad ile kaydırma yeniden yazıldı. Sayfa parmağının hareketini birebir izler, kesik kesik ya da yavaş kaymaz; parmağını kaldırınca hızına göre yavaşlayarak bir süre daha kayar. Sayfanın içindeki kaydırmalı alanlar (sohbet listesi, menü) ve haritalar da touchpad ile kayar.

• Windows: touchpad scrolling has been rewritten. The page follows your fingers exactly, without stutter or slowness, and when you lift your fingers it keeps gliding for a moment, slowing down based on your speed. Scrollable areas inside a page (chat lists, menus) and maps also scroll with the touchpad.

## 0.19.3
• Windows: pencere daraltılınca ya da video küçük pencereye alınınca uygulama telefon düzenine geçip bütün sekmeleri baştan yüklüyordu (açık sayfalar kayboluyordu); düzeltildi. Küçük pencerede artık izlediğin video kalır.
• Windows: sayfanın içine tıkladıktan sonra Ctrl+T, Ctrl+W, Ctrl+L, Ctrl+K, Ctrl+Tab gibi kısayollar çalışmıyordu; artık çalışır. Ctrl+1…9 ile sekmeler arası geçiş de eklendi.
• Windows: video tam ekranında başlık çubuğu görünmeye devam ediyordu; artık video bütün ekranı kaplar.
• YouTube: video reklamları sessize alınıp hemen geçilir, "Atla" düğmesine kendiliğinden basılır; ana sayfadaki ve yan sütundaki reklam kutuları gizlenir.
• Menüdeki uzun öğeler artık iki satıra bölünmüyor.

• Windows: when you made the window narrow or put a video in the mini window, the app switched to the phone layout and reloaded every tab (open pages were lost); fixed. The mini window now keeps the video you were watching.
• Windows: after clicking inside a page, shortcuts like Ctrl+T, Ctrl+W, Ctrl+L, Ctrl+K and Ctrl+Tab didn't work; now they do. Ctrl+1…9 now also switch between tabs.
• Windows: the title bar stayed visible in video fullscreen; now the video fills the whole screen.
• YouTube: video ads are muted and skipped right away, and the "Skip" button is pressed for you; ad boxes on the home page and in the side column are hidden.
• Long menu items no longer wrap onto two lines.

## 0.19.4
• Windows: güncelleme, Pusula'yı zip'ten çıkarıp kendi klasöründen kullananlarda başka bir klasöre kuruluyor, açtığın sürüm eskide kalıyordu; artık Pusula hangi klasörden çalışıyorsa o güncellenir. Güncelleme indirilirken ilerleme görünür, kurulum sessizce yapılır ve Pusula kendiliğinden yeniden açılır. Güncelleme dosyaları artık İndirilenler listesini doldurmuyor.
• Windows: pencerenin boyutu, yeri ve tam boyutta olup olmadığı hatırlanır; Pusula kapattığın gibi açılır.
• Bağlantıya orta tıkla ya da Ctrl+tıkla açılan sekme artık arkada açılır, bulunduğun sayfada kalırsın.
• Ekran süresi, ayarlar ve benzeri ekranlar Esc ile kapanır. Bu ekranlar açıkken geçen süre, arkadaki siteye yazılmaz.
• Adres çubuğunda Türkçe harfler artık %C4%B1 gibi kodlarla değil, okunur biçimde görünür.
• Geçmiş ve yer imlerinde arama kutusu, gün başlıkları (Bugün, Dün…) ve tek tek silme var; "Temizle" önce sorar. Yeni kısayollar: Ctrl+H geçmiş, Ctrl+D yer imi, Ctrl+Shift+O yer imleri, Ctrl+R / F5 yenile.
• Reklam engelleyici, reklamı kaldırılan kutuların bıraktığı boş beyaz alanları da kapatır (haber sitelerinin üstündeki büyük boşluk gibi).
• Sekmeye sağ tıklayınca yeni seçenekler: Yeniden yükle, Sekmeyi çoğalt, Diğer sekmeleri kapat, Sağdaki sekmeleri kapat.
• Site izin penceresi daha anlaşılır ("Şunları kullanmak istiyor: konum"); seçili düğmeler artık turuncu.

• Windows: for people who unzipped Pusula and run it from their own folder, updates were installed to a different folder and the copy they opened stayed old; now the folder Pusula runs from is the one updated. Download progress is shown, the install runs quietly and Pusula reopens by itself. Update files no longer fill up the Downloads list.
• Windows: the window's size, position and maximized state are remembered; Pusula opens the way you closed it.
• Links opened with a middle click or Ctrl+click now open in a background tab, so you stay on the current page.
• Screen time, settings and similar screens close with Esc. Time spent while these screens are open is no longer counted toward the site behind them.
• Turkish and other non-English letters in the address bar now show as readable text, not codes like %C4%B1.
• History and bookmarks now have a search box, day headings (Today, Yesterday…) and per-item delete; "Clear" asks first. New shortcuts: Ctrl+H history, Ctrl+D bookmark, Ctrl+Shift+O bookmarks, Ctrl+R / F5 reload.
• The ad blocker now also collapses the empty white space left by removed ads (like the big gap at the top of news sites).
• New options when you right-click a tab: Reload, Duplicate tab, Close other tabs, Close tabs to the right.
• The site permission dialog is clearer ("Wants to use: location"), and selected buttons are now orange.

## 0.19.5
• Sesli video ya da müzik çalan sekmede hoparlör simgesi görünür; simgeye tıklayınca o sekmenin sesi kapanır (sekmeye sağ tıklayarak da yapılır).
• Okuma modu, yazıya karışan küçük simgeleri ve "Google'da takip edin" gibi kutuları ayıklar.

• Tabs playing audible video or music show a speaker icon; click it to mute that tab (also available when you right-click the tab).
• Reader mode filters out small icons and boxes like "Follow us on Google" mixed into the article.

## 0.19.6
• Çok sekme açıkken sekmeler sığmak için daralır (Chrome gibi); fare tekerleği sekme şeridini kaydırır, açtığın sekme şeritte hep görünür.
• Küçük pencerede video artık pencereyi tamamen kaplar (YouTube'un üst çubuğu görünmez) ve ekranın sağ alt köşesine yerleşir.
• Orta tık ve Ctrl+tık, yeni pencere açmayan sitelerde de (YouTube gibi) bağlantıyı arka sekmede açar.
• Kurulum, var olan klasöre güncellerken artık "klasör zaten var" diye sormuyor.

• With many tabs open, tabs shrink to fit (like Chrome); the mouse wheel scrolls the tab strip, and the tab you open always stays in view.
• In the mini window the video now fills the whole window (YouTube's top bar is hidden) and sits in the bottom-right corner of the screen.
• Middle click and Ctrl+click now open links in a background tab on sites that don't request a new window themselves (like YouTube).
• The installer no longer asks "folder already exists" when updating an existing folder.

## 0.19.7
• Sekmeler sürüklenerek yer değiştirir; başka bir gruptaki sekmenin üstüne bırakılan sekme o gruba katılır.
• Açık sekmeyi kapatınca, onu açan sekmeye dönülür (Chrome gibi).
• YouTube: izleme sayfasının yan sütunundaki "Sponsorlu" alışveriş kutuları da gizlenir.

• Tabs can be dragged to reorder; a tab dropped onto a tab in another group joins that group.
• Closing the current tab returns you to the tab that opened it (like Chrome).
• YouTube: "Sponsored" shopping boxes in the side column of the watch page are now hidden too.

## 0.19.9
• Açılışta yalnız kaldığın sekme yüklenir, öbür sekmeler tıklayınca açılır (Chrome gibi). Pusula daha hızlı açılır ve arka sekmelerdeki video ya da canlı yayınlar açılır açılmaz kendiliğinden ses çıkarmaz.
• Reklam engelleyicinin listesi 117 alan adından 3.600'ü aşkın alan adına çıktı (yaygın reklam engelleyicilerin varsayılan listelerinden Peter Lowe listesi eklendi). Daha az reklam, daha az izleyici, daha hızlı sayfalar.
• Adres çubuğundaki kilide tıklayınca site bilgileri açılır: bağlantının güvenli olup olmadığı, sitenin izinleri (tek tek sıfırlanabilir) ve "Bu sitenin çerezlerini sil".
• Sekmedeki hoparlör simgesi başlığın soluna taşındı; ses durunca kapatma düğmesi artık yer değiştirmiyor (yanlışlıkla sekme kapatılmıyor).

• On startup only the tab you were on loads; the other tabs open when you click them (like Chrome). Pusula opens faster, and videos or live streams in background tabs no longer start playing sound on their own.
• The ad blocker list grew from 117 to more than 3,600 domains (added Peter Lowe's list, one of the default lists in popular ad blockers). Fewer ads, fewer trackers, faster pages.
• Clicking the lock in the address bar opens site info: whether the connection is secure, the site's permissions (each can be reset) and "Delete this site's cookies".
• The tab's speaker icon moved to the left of the title, so the close button no longer shifts when audio stops (no more closing a tab by accident).

## 0.19.11
• "Telefona gönder (Pusula Köprü)": açık sekme, Pusula Köprü ile eşleşmiş telefonda hemen açılır. Telefonda "Bilgisayara gönder" aynısını tersine yapar. Hesap gerekmez, aynı Wi-Fi yeter.

## 0.19.10
• Ctrl+T ile açtığın sekmeyi başka sekmeye geçmeden kapatırsan, önceki sekmene dönersin (Chrome gibi).

• If you close a tab opened with Ctrl+T without switching to another tab, you return to the tab you were on (like Chrome).
