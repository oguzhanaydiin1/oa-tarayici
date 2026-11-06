#!/usr/bin/env python3
"""flutter create'in ürettiği Android klasörüne OA Tarayıcı ayarlarını uygular.

- Uygulamayı Android'e tarayıcı olarak tanıtır: http/https bağlantıları ve "varsayılan tarayıcı"
  seçimi (Ayarlar → Varsayılan uygulamalar → Tarayıcı) için intent filtreleri.
- Güncellemeleri kurabilmek için REQUEST_INSTALL_PACKAGES izni.
- Arka planda radyo (just_audio_background / audio_service): ön plan hizmeti, medya düğmesi alıcısı.
- Parmak izi / ekran kilidi (local_auth): MainActivity FragmentActivity olur, tema AppCompat olur.
- Videoyu küçük pencerede izleme (resim içinde resim): MainActivity'de "oa/pip" kanalı.
- Ana ekran widget'ları (arama, saat ve hava) ve uygulama simgesi kısayolları.
  Kotlin ve kaynak dosyaları platform/android/ klasöründen kopyalanır.
- OA_KEYSTORE_PATH ve OA_KEYSTORE_PASSWORD ortam değişkenleri varsa yayın sürümünü bu sabit
  anahtarla imzalar. Sabit anahtar olmadan her derleme farklı imzalanır ve Android yeni sürümü
  eskisinin üzerine kurmaz.

Kullanım (proje kökünde): python3 scripts/android_ayarla.py
"""
import os
import re
import shutil
import sys

MANIFEST = 'android/app/src/main/AndroidManifest.xml'

BROWSER_FILTERS = '''
            <!-- OA Tarayıcı: web bağlantılarını açabilir ve varsayılan tarayıcı seçilebilir -->
            <intent-filter>
                <action android:name="android.intent.action.VIEW"/>
                <category android:name="android.intent.category.DEFAULT"/>
                <category android:name="android.intent.category.BROWSABLE"/>
                <data android:scheme="http"/>
                <data android:scheme="https"/>
            </intent-filter>
            <intent-filter>
                <action android:name="android.intent.action.MAIN"/>
                <category android:name="android.intent.category.DEFAULT"/>
                <category android:name="android.intent.category.APP_BROWSER"/>
            </intent-filter>
            <intent-filter>
                <action android:name="android.intent.action.WEB_SEARCH"/>
                <category android:name="android.intent.category.DEFAULT"/>
            </intent-filter>
'''


def manifest():
    if not os.path.exists(MANIFEST):
        return
    s = open(MANIFEST, encoding='utf-8').read()
    if 'android.intent.category.APP_BROWSER' not in s:
        i = s.find('</activity>')
        if i < 0:
            sys.exit('AndroidManifest.xml içinde </activity> bulunamadı')
        s = s[:i] + BROWSER_FILTERS.strip('\n') + '\n        ' + s[i:]
    if 'REQUEST_INSTALL_PACKAGES' not in s:
        s = s.replace('<application', '<uses-permission android:name="android.permission.REQUEST_INSTALL_PACKAGES"/>\n    <application', 1)
    # Sesli okuma: Android 11+ cihazdaki konuşma motorunu görebilmek için
    if 'TTS_SERVICE' not in s:
        tts = '<intent>\n            <action android:name="android.intent.action.TTS_SERVICE" />\n        </intent>\n    '
        if '</queries>' in s:
            s = s.replace('</queries>', '    ' + tts + '</queries>', 1)
        else:
            s = s.replace('<application', '<queries>\n        ' + tts + '</queries>\n    <application', 1)
    # Bildirimler (ekran süresi haftalık özeti): izin ve zamanlanmış bildirimin alıcıları
    if 'POST_NOTIFICATIONS' not in s:
        s = s.replace('<application', '<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>\n    <application', 1)
    if 'RECEIVE_BOOT_COMPLETED' not in s:
        s = s.replace('<application', '<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>\n    <application', 1)
    if 'ScheduledNotificationReceiver' not in s:
        i = s.rfind('</application>')
        s = s[:i] + NOTIFY_RECEIVERS.strip('\n') + '\n    ' + s[i:]
    open(MANIFEST, 'w', encoding='utf-8').write(s)
    print('Manifest: tarayıcı intent filtreleri, kurulum ve bildirim izinleri eklendi')


NOTIFY_RECEIVERS = '''
        <!-- Zamanlanmış bildirimler (flutter_local_notifications) -->
        <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver" />
        <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver">
            <intent-filter>
                <action android:name="android.intent.action.BOOT_COMPLETED"/>
                <action android:name="android.intent.action.MY_PACKAGE_REPLACED"/>
                <action android:name="android.intent.action.QUICKBOOT_POWERON" />
            </intent-filter>
        </receiver>
'''


WIDGETS = '''
        <!-- Ana ekran widget'ları -->
        <receiver android:name=".AramaWidget" android:exported="false" android:label="@string/oa_w_arama_ad">
            <intent-filter>
                <action android:name="android.appwidget.action.APPWIDGET_UPDATE" />
            </intent-filter>
            <meta-data android:name="android.appwidget.provider" android:resource="@xml/oa_widget_arama_info" />
        </receiver>
        <receiver android:name=".HavaWidget" android:exported="false" android:label="@string/oa_w_hava_ad">
            <intent-filter>
                <action android:name="android.appwidget.action.APPWIDGET_UPDATE" />
            </intent-filter>
            <meta-data android:name="android.appwidget.provider" android:resource="@xml/oa_widget_hava_info" />
        </receiver>
'''

AUDIO_SERVICE = '''
        <!-- OA Radyo: arka planda çalma (audio_service) -->
        <service android:name="com.ryanheise.audioservice.AudioService"
            android:foregroundServiceType="mediaPlayback"
            android:exported="true" tools:ignore="Instantiatable">
            <intent-filter>
                <action android:name="android.media.browse.MediaBrowserService" />
            </intent-filter>
        </service>
        <receiver android:name="com.ryanheise.audioservice.MediaButtonReceiver"
            android:exported="true" tools:ignore="Instantiatable">
            <intent-filter>
                <action android:name="android.intent.action.MEDIA_BUTTON" />
            </intent-filter>
        </receiver>
'''


def native():
    """Radyo hizmeti, resim içinde resim, parmak izi için Android ayarları."""
    if not os.path.exists(MANIFEST):
        return
    s = open(MANIFEST, encoding='utf-8').read()
    if 'xmlns:tools' not in s:
        s = s.replace('<manifest xmlns:android="http://schemas.android.com/apk/res/android"',
                      '<manifest xmlns:android="http://schemas.android.com/apk/res/android"\n    xmlns:tools="http://schemas.android.com/tools"', 1)
    for perm in ['WAKE_LOCK', 'FOREGROUND_SERVICE', 'FOREGROUND_SERVICE_MEDIA_PLAYBACK']:
        if 'android.permission.' + perm + '"' not in s:
            s = s.replace('<application', '<uses-permission android:name="android.permission.' + perm + '"/>\n    <application', 1)
    if 'com.ryanheise.audioservice.AudioService' not in s:
        i = s.rfind('</application>')
        s = s[:i] + AUDIO_SERVICE.strip('\n') + '\n    ' + s[i:]
    if 'supportsPictureInPicture' not in s:
        s = s.replace('android:name=".MainActivity"',
                      'android:name=".MainActivity"\n            android:supportsPictureInPicture="true"\n            android:resizeableActivity="true"', 1)
    open(MANIFEST, 'w', encoding='utf-8').write(s)

    if '.AramaWidget' not in s:
        i = s.rfind('</application>')
        s = s[:i] + WIDGETS.strip('\n') + '\n    ' + s[i:]
    if 'android.app.shortcuts' not in s:
        i = s.find('</activity>')
        s = s[:i] + '    <meta-data android:name="android.app.shortcuts" android:resource="@xml/oa_shortcuts" />\n        ' + s[i:]
    open(MANIFEST, 'w', encoding='utf-8').write(s)

    # Flutter'ın ürettiği MainActivity yerine bizimki (platform/android/...)
    found = False
    for root, _, files in os.walk('android/app/src/main'):
        for f in files:
            if f in ('MainActivity.kt', 'MainActivity.java'):
                os.remove(os.path.join(root, f))
                found = True
    shutil.copytree('platform/android/app/src/main', 'android/app/src/main', dirs_exist_ok=True)

    # local_auth: tema AppCompat olmalı (eski Android sürümlerinde çökmesin)
    for f in ['android/app/src/main/res/values/styles.xml', 'android/app/src/main/res/values-night/styles.xml']:
        if os.path.exists(f):
            t = open(f, encoding='utf-8').read()
            t = t.replace('@android:style/Theme.Light.NoTitleBar', 'Theme.AppCompat.Light.NoActionBar')
            t = t.replace('@android:style/Theme.Black.NoTitleBar', 'Theme.AppCompat.NoActionBar')
            open(f, 'w', encoding='utf-8').write(t)
    kts = 'android/app/build.gradle.kts'
    groovy = 'android/app/build.gradle'
    if os.path.exists(kts):
        t = open(kts, encoding='utf-8').read()
        if 'androidx.appcompat:appcompat' not in t:
            t += '\ndependencies {\n    implementation("androidx.appcompat:appcompat:1.7.0")\n}\n'
        # flutter_local_notifications Java 8+ tarih kitaplığını ister (desugaring)
        if 'isCoreLibraryDesugaringEnabled' not in t:
            t, n = re.subn(r'compileOptions\s*\{', 'compileOptions {\n        isCoreLibraryDesugaringEnabled = true', t, count=1)
            if n == 0:
                sys.exit('build.gradle.kts içinde compileOptions bulunamadı')
            t += '\ndependencies {\n    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")\n}\n'
        open(kts, 'w', encoding='utf-8').write(t)
    elif os.path.exists(groovy):
        t = open(groovy, encoding='utf-8').read()
        if 'androidx.appcompat:appcompat' not in t:
            t += "\ndependencies {\n    implementation 'androidx.appcompat:appcompat:1.7.0'\n}\n"
        if 'coreLibraryDesugaringEnabled' not in t:
            t = re.sub(r'compileOptions\s*\{', 'compileOptions {\n        coreLibraryDesugaringEnabled true', t, count=1)
            t += "\ndependencies {\n    coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.1.4'\n}\n"
        open(groovy, 'w', encoding='utf-8').write(t)
    print('Android: radyo hizmeti, resim içinde resim, parmak izi, widget ve kısayollar ayarlandı' + ('' if found else ' (MainActivity bulunamadı, yenisi yazıldı)'))


def signing():
    path = os.environ.get('OA_KEYSTORE_PATH')
    if not path or not os.environ.get('OA_KEYSTORE_PASSWORD'):
        print('::warning title=imza::Sabit imza anahtarı yok (ANDROID_KEYSTORE_BASE64 secret). '
              'APK test anahtarıyla imzalanıyor; Android güncellemeyi eski sürümün üzerine kurmaz.')
        return
    kts = 'android/app/build.gradle.kts'
    groovy = 'android/app/build.gradle'
    if os.path.exists(kts):
        s = open(kts, encoding='utf-8').read()
        block = '''    signingConfigs {
        create("oa") {
            storeFile = file(System.getenv("OA_KEYSTORE_PATH"))
            storePassword = System.getenv("OA_KEYSTORE_PASSWORD")
            keyAlias = "oa"
            keyPassword = System.getenv("OA_KEYSTORE_PASSWORD")
        }
    }
'''
        if 'create("oa")' not in s:
            s = re.sub(r'(^android\s*\{\s*\n)', lambda m: m.group(1) + block, s, count=1, flags=re.M)
        s = s.replace('signingConfig = signingConfigs.getByName("debug")',
                      'signingConfig = signingConfigs.getByName("oa")')
        open(kts, 'w', encoding='utf-8').write(s)
    elif os.path.exists(groovy):
        s = open(groovy, encoding='utf-8').read()
        block = '''    signingConfigs {
        oa {
            storeFile file(System.getenv("OA_KEYSTORE_PATH"))
            storePassword System.getenv("OA_KEYSTORE_PASSWORD")
            keyAlias "oa"
            keyPassword System.getenv("OA_KEYSTORE_PASSWORD")
        }
    }
'''
        if 'signingConfigs {' not in s:
            s = re.sub(r'(^android\s*\{\s*\n)', lambda m: m.group(1) + block, s, count=1, flags=re.M)
        s = s.replace('signingConfig signingConfigs.debug', 'signingConfig signingConfigs.oa')
        open(groovy, 'w', encoding='utf-8').write(s)
    else:
        sys.exit('android/app/build.gradle(.kts) bulunamadı')
    print('İmza: yayın sürümü sabit OA anahtarıyla imzalanacak')


if __name__ == '__main__':
    manifest()
    native()
    signing()
