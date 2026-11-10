package dev.oalabs.oa_tarayici

import android.app.Activity
import android.app.PictureInPictureParams
import android.content.Intent
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.os.Build
import android.speech.RecognizerIntent
import android.util.Rational
import com.ryanheise.audioservice.AudioServiceFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// AudioServiceFragmentActivity: arka planda radyo (audio_service) ve parmak izi (local_auth,
// FragmentActivity ister) birlikte çalışsın diye.
class MainActivity : AudioServiceFragmentActivity() {
    private var pip: MethodChannel? = null
    private var sesSonuc: MethodChannel.Result? = null
    private var centerSonuc: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val ch = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "oa/pip")
        ch.setMethodCallHandler { call, result ->
            when (call.method) {
                "destek" -> result.success(
                    Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                        packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)
                )
                "gir" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        val w = maxOf(call.argument<Int>("w") ?: 16, 1)
                        val h = maxOf(call.argument<Int>("h") ?: 9, 1)
                        // Android en fazla 2.39:1 ile 1:2.39 arası oran kabul eder
                        var r = Rational(w, h)
                        if (r.toDouble() > 2.39) r = Rational(239, 100)
                        if (r.toDouble() < 1 / 2.39) r = Rational(100, 239)
                        val ok = try {
                            enterPictureInPictureMode(PictureInPictureParams.Builder().setAspectRatio(r).build())
                        } catch (e: Exception) {
                            false
                        }
                        result.success(ok)
                    } else {
                        result.success(false)
                    }
                }
                else -> result.notImplemented()
            }
        }
        pip = ch

        // OA Labs Center ile giriş (tek giriş): Center'ın onay ekranı açılır, onaylanırsa tek
        // kullanımlık kod döner; Dart tarafı kodu sunucuda Pusula'nın kendi oturumuna çevirir.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "oa/center").setMethodCallHandler { call, result ->
            when (call.method) {
                "var" -> result.success(
                    try {
                        packageManager.getPackageInfo(CENTER_PAKET, 0)
                        true
                    } catch (e: PackageManager.NameNotFoundException) {
                        false
                    }
                )
                "giris" -> {
                    val i = Intent(CENTER_GIRIS).setClassName(CENTER_PAKET, "$CENTER_PAKET.MainActivity")
                    centerSonuc?.success(null)
                    centerSonuc = result
                    try {
                        @Suppress("DEPRECATION")
                        startActivityForResult(i, CENTER_ISTEK)
                    } catch (e: Exception) {
                        centerSonuc = null
                        result.success(null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        // Pusula Köprü: açık sekmeyi eşleşmiş bilgisayara gönder (Köprü ekranı açılmadan işler)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "oa/kopru").setMethodCallHandler { call, result ->
            if (call.method != "gonder") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val i = Intent(Intent.ACTION_SEND).apply {
                type = "text/plain"
                setPackage("dev.oalabs.pusula_kopru")
                putExtra(Intent.EXTRA_TEXT, call.argument<String>("url") ?: "")
                putExtra("dev.oalabs.kopru.OPEN", true)
            }
            result.success(
                try {
                    startActivity(i)
                    true
                } catch (e: Exception) {
                    false
                }
            )
        }

        // Sesli arama: telefonun konuşma tanıma ekranı (izin gerekmez; mikrofonu sistem kullanır).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "oa/ses").setMethodCallHandler { call, result ->
            if (call.method != "dinle") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val i = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_WEB_SEARCH)
                putExtra(RecognizerIntent.EXTRA_LANGUAGE, "tr-TR")
                putExtra(RecognizerIntent.EXTRA_PROMPT, "Ne aramak istersin?")
                putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
            }
            try {
                sesSonuc?.success(null)
                sesSonuc = result
                startActivityForResult(i, SES_ISTEK)
            } catch (e: Exception) {
                sesSonuc = null
                result.error("yok", "Bu telefonda sesli arama yok", null)
            }
        }

        // Ana ekran widget'ları: uygulama hava durumunu buraya yazar, widget'lar yenilenir.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "oa/widget").setMethodCallHandler { call, result ->
            when (call.method) {
                "hava" -> {
                    @Suppress("UNCHECKED_CAST")
                    val m = call.arguments as? Map<String, Any?>
                    if (m != null) WidgetVeri.havaKaydet(applicationContext, m)
                    HavaWidget.guncelle(applicationContext)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    @Deprecated("FlutterFragmentActivity hâlâ bunu kullanıyor")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == SES_ISTEK) {
            val r = sesSonuc
            sesSonuc = null
            val t = data?.getStringArrayListExtra(RecognizerIntent.EXTRA_RESULTS)?.firstOrNull()
            r?.success(if (resultCode == Activity.RESULT_OK) t else null)
        }
        if (requestCode == CENTER_ISTEK) {
            val r = centerSonuc
            centerSonuc = null
            r?.success(if (resultCode == Activity.RESULT_OK) data?.getStringExtra("kod") else null)
        }
    }

    companion object {
        private const val SES_ISTEK = 7301
        private const val CENTER_ISTEK = 7302
        private const val CENTER_PAKET = "dev.oalabs.oa_center"
        private const val CENTER_GIRIS = "dev.oalabs.center.GIRIS"
    }

    override fun onPictureInPictureModeChanged(isInPictureInPictureMode: Boolean, newConfig: Configuration) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        pip?.invokeMethod("degisti", isInPictureInPictureMode)
    }
}
