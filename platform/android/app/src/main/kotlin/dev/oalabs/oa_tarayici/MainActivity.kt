package dev.oalabs.oa_tarayici

import android.app.PictureInPictureParams
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.os.Build
import android.util.Rational
import com.ryanheise.audioservice.AudioServiceFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// AudioServiceFragmentActivity: arka planda radyo (audio_service) ve parmak izi (local_auth,
// FragmentActivity ister) birlikte çalışsın diye.
class MainActivity : AudioServiceFragmentActivity() {
    private var pip: MethodChannel? = null

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

    override fun onPictureInPictureModeChanged(isInPictureInPictureMode: Boolean, newConfig: Configuration) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        pip?.invokeMethod("degisti", isInPictureInPictureMode)
    }
}
