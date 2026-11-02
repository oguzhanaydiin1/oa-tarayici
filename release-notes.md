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
