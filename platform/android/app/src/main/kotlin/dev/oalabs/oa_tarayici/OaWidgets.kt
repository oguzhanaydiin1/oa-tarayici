package dev.oalabs.oa_tarayici

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale
import kotlin.math.roundToInt

// OA Tarayıcı ana ekran widget'ları.
//  - AramaWidget: arama kutusu, QR ve gizli sekme düğmeleri
//  - HavaWidget: saat, tarih, hava durumu ve kısa tahmin (Open-Meteo)
// Dokunuşlar uygulamayı oatarayici://<eylem> adresiyle açar; Flutter tarafı (app_links) karşılar.

object WidgetVeri {
    private const val AD = "oa_widget"

    fun prefs(c: Context) = c.getSharedPreferences(AD, Context.MODE_PRIVATE)

    /** Uygulamadan gelen hava durumu (Flutter, "oa/widget" kanalı). */
    fun havaKaydet(c: Context, m: Map<String, Any?>) {
        val e = prefs(c).edit()
        for ((k, v) in m) {
            when (v) {
                null -> e.remove(k)
                is Boolean -> e.putBoolean(k, v)
                is Int -> e.putInt(k, v)
                is Long -> e.putInt(k, v.toInt())
                is Double -> e.putString(k, v.toString())
                else -> e.putString(k, v.toString())
            }
        }
        e.putLong("upd", System.currentTimeMillis())
        e.apply()
    }

    fun ac(c: Context, eylem: String): PendingIntent {
        val i = Intent(Intent.ACTION_VIEW, Uri.parse("oatarayici://$eylem"))
            .setClass(c, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        return PendingIntent.getActivity(
            c, eylem.hashCode(), i,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    fun ikon(kod: Int, gunduz: Boolean): Int = when (kod) {
        0, 1 -> if (gunduz) R.drawable.oa_w_gunes else R.drawable.oa_w_ay
        2 -> if (gunduz) R.drawable.oa_w_parcali else R.drawable.oa_w_ay
        3 -> R.drawable.oa_w_bulut
        45, 48 -> R.drawable.oa_w_sis
        in 51..67, in 80..82 -> R.drawable.oa_w_yagmur
        in 71..77, 85, 86 -> R.drawable.oa_w_kar
        in 95..99 -> R.drawable.oa_w_firtina
        else -> R.drawable.oa_w_bulut
    }

    fun metin(kod: Int): String = when (kod) {
        0 -> "Açık"
        1 -> "Çoğunlukla açık"
        2 -> "Parçalı bulutlu"
        3 -> "Bulutlu"
        45, 48 -> "Sisli"
        51, 53, 55 -> "Çiseleme"
        56, 57 -> "Dondurucu çiseleme"
        61 -> "Hafif yağmurlu"
        63 -> "Yağmurlu"
        65 -> "Şiddetli yağmur"
        66, 67 -> "Dondurucu yağmur"
        71 -> "Hafif kar"
        73 -> "Karlı"
        75 -> "Yoğun kar"
        77 -> "Kar taneleri"
        80, 81 -> "Sağanak"
        82 -> "Şiddetli sağanak"
        85, 86 -> "Kar sağanağı"
        95 -> "Gök gürültülü"
        96, 99 -> "Dolu ve fırtına"
        else -> ""
    }

    /** Widget kendi başına da yeniler (uygulama kapalıyken): Open-Meteo'dan çeker. */
    fun havaCek(c: Context): Boolean {
        val p = prefs(c)
        val lat = p.getString("lat", null) ?: return false
        val lon = p.getString("lon", null) ?: return false
        return try {
            val u = URL(
                "https://api.open-meteo.com/v1/forecast?latitude=$lat&longitude=$lon" +
                    "&current=temperature_2m,weather_code,is_day&hourly=temperature_2m,weather_code,is_day" +
                    "&daily=weather_code,temperature_2m_max,temperature_2m_min&timezone=auto&forecast_days=3"
            )
            val con = (u.openConnection() as HttpURLConnection).apply {
                connectTimeout = 8000
                readTimeout = 8000
            }
            val body = con.inputStream.bufferedReader().use { it.readText() }
            con.disconnect()
            val j = JSONObject(body)
            val cur = j.getJSONObject("current")
            val m = HashMap<String, Any?>()
            val kod = cur.optInt("weather_code", 0)
            m["temp"] = "${cur.optDouble("temperature_2m").roundToInt()}°"
            m["code"] = kod
            m["day"] = cur.optInt("is_day", 1) == 1
            m["desc"] = metin(kod)
            val fmt = SimpleDateFormat("yyyy-MM-dd'T'HH:mm", Locale.US)
            val now = System.currentTimeMillis()
            val h = j.getJSONObject("hourly")
            val ht = h.getJSONArray("time")
            val htemp = h.getJSONArray("temperature_2m")
            val hcode = h.getJSONArray("weather_code")
            val hday = h.getJSONArray("is_day")
            var n = 0
            val cal = Calendar.getInstance()
            for (i in 0 until ht.length()) {
                if (n >= 2) break
                val t = fmt.parse(ht.getString(i)) ?: continue
                if (t.time <= now + 30 * 60 * 1000) continue
                cal.time = t
                if (cal.get(Calendar.HOUR_OF_DAY) % 3 != 0) continue
                m["f${n}_l"] = String.format(Locale.US, "%02d:00", cal.get(Calendar.HOUR_OF_DAY))
                m["f${n}_c"] = hcode.optInt(i)
                m["f${n}_d"] = hday.optInt(i, 1) == 1
                m["f${n}_t"] = "${htemp.optDouble(i).roundToInt()}°"
                n++
            }
            val d = j.getJSONObject("daily")
            val dt = d.getJSONArray("time")
            val gun = SimpleDateFormat("EEE", Locale("tr"))
            val dfmt = SimpleDateFormat("yyyy-MM-dd", Locale.US)
            for (i in 1 until minOf(3, dt.length())) {
                val t = dfmt.parse(dt.getString(i)) ?: continue
                m["f${n}_l"] = gun.format(t).replace(".", "")
                m["f${n}_c"] = d.getJSONArray("weather_code").optInt(i)
                m["f${n}_d"] = true
                m["f${n}_t"] = "${d.getJSONArray("temperature_2m_max").optDouble(i).roundToInt()}°/" +
                    "${d.getJSONArray("temperature_2m_min").optDouble(i).roundToInt()}"
                n++
            }
            havaKaydet(c, m)
            true
        } catch (e: Exception) {
            false
        }
    }
}

class AramaWidget : AppWidgetProvider() {
    override fun onUpdate(c: Context, m: AppWidgetManager, ids: IntArray) {
        for (id in ids) {
            val v = RemoteViews(c.packageName, R.layout.oa_widget_arama)
            v.setOnClickPendingIntent(R.id.w_kutu, WidgetVeri.ac(c, "ara"))
            v.setOnClickPendingIntent(R.id.w_logo, WidgetVeri.ac(c, "yeni"))
            v.setOnClickPendingIntent(R.id.w_qr, WidgetVeri.ac(c, "qr"))
            v.setOnClickPendingIntent(R.id.w_gizli, WidgetVeri.ac(c, "gizli"))
            m.updateAppWidget(id, v)
        }
    }
}

class HavaWidget : AppWidgetProvider() {
    companion object {
        private val GUN = intArrayOf(R.id.f0, R.id.f1, R.id.f2, R.id.f3)
        private val ETIKET = intArrayOf(R.id.f0_l, R.id.f1_l, R.id.f2_l, R.id.f3_l)
        private val SIMGE = intArrayOf(R.id.f0_i, R.id.f1_i, R.id.f2_i, R.id.f3_i)
        private val DERECE = intArrayOf(R.id.f0_t, R.id.f1_t, R.id.f2_t, R.id.f3_t)

        fun guncelle(c: Context) {
            val m = AppWidgetManager.getInstance(c)
            val ids = m.getAppWidgetIds(ComponentName(c, HavaWidget::class.java))
            if (ids.isNotEmpty()) ciz(c, m, ids)
        }

        fun ciz(c: Context, m: AppWidgetManager, ids: IntArray) {
            val p = WidgetVeri.prefs(c)
            for (id in ids) {
                val v = RemoteViews(c.packageName, R.layout.oa_widget_hava)
                val sehir = p.getString("city", null)
                val temp = p.getString("temp", null)
                if (sehir == null) {
                    v.setTextViewText(R.id.w_derece, "")
                    v.setTextViewText(R.id.w_sehir, "Hava için uygulamada şehir seç")
                    v.setViewVisibility(R.id.w_simge, View.GONE)
                    v.setViewVisibility(R.id.w_tahmin, View.GONE)
                    v.setViewVisibility(R.id.w_cizgi, View.GONE)
                } else {
                    val kod = p.getInt("code", 3)
                    v.setTextViewText(R.id.w_derece, temp ?: "–")
                    val acik = p.getString("desc", "") ?: ""
                    v.setTextViewText(R.id.w_sehir, if (acik.isEmpty()) sehir else "$sehir · $acik")
                    v.setViewVisibility(R.id.w_simge, if (temp == null) View.GONE else View.VISIBLE)
                    v.setImageViewResource(R.id.w_simge, WidgetVeri.ikon(kod, p.getBoolean("day", true)))
                    var tahminVar = false
                    for (i in 0 until 4) {
                        val l = p.getString("f${i}_l", null)
                        if (l == null) {
                            v.setViewVisibility(GUN[i], View.INVISIBLE)
                            continue
                        }
                        tahminVar = true
                        v.setViewVisibility(GUN[i], View.VISIBLE)
                        v.setTextViewText(ETIKET[i], l)
                        v.setTextViewText(DERECE[i], p.getString("f${i}_t", ""))
                        v.setImageViewResource(SIMGE[i], WidgetVeri.ikon(p.getInt("f${i}_c", 3), p.getBoolean("f${i}_d", true)))
                    }
                    v.setViewVisibility(R.id.w_tahmin, if (tahminVar) View.VISIBLE else View.GONE)
                    v.setViewVisibility(R.id.w_cizgi, if (tahminVar) View.VISIBLE else View.GONE)
                }
                v.setOnClickPendingIntent(R.id.w_kok, WidgetVeri.ac(c, "hava"))
                m.updateAppWidget(id, v)
            }
        }
    }

    override fun onUpdate(c: Context, m: AppWidgetManager, ids: IntArray) {
        ciz(c, m, ids)
        // Son veri 25 dakikadan eskiyse widget kendisi yeniler (uygulama kapalı olabilir).
        val upd = WidgetVeri.prefs(c).getLong("upd", 0)
        if (System.currentTimeMillis() - upd < 25 * 60 * 1000) return
        val bekle = goAsync()
        Thread {
            try {
                if (WidgetVeri.havaCek(c)) ciz(c, m, ids)
            } finally {
                bekle.finish()
            }
        }.start()
    }
}
