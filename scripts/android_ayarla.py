#!/usr/bin/env python3
"""flutter create'in ürettiği Android klasörüne OA Tarayıcı ayarlarını uygular.

- Uygulamayı Android'e tarayıcı olarak tanıtır: http/https bağlantıları ve "varsayılan tarayıcı"
  seçimi (Ayarlar → Varsayılan uygulamalar → Tarayıcı) için intent filtreleri.
- Güncellemeleri kurabilmek için REQUEST_INSTALL_PACKAGES izni.
- OA_KEYSTORE_PATH ve OA_KEYSTORE_PASSWORD ortam değişkenleri varsa yayın sürümünü bu sabit
  anahtarla imzalar. Sabit anahtar olmadan her derleme farklı imzalanır ve Android yeni sürümü
  eskisinin üzerine kurmaz.

Kullanım (proje kökünde): python3 scripts/android_ayarla.py
"""
import os
import re
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
    open(MANIFEST, 'w', encoding='utf-8').write(s)
    print('Manifest: tarayıcı intent filtreleri ve kurulum izni eklendi')


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
    signing()
