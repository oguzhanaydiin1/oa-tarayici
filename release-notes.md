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
