import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'i18n.dart';
// Telefonun kendi bildirimleri (Android). Şimdilik ekran süresinin haftalık özeti için.

class OaNotify {
  static final _p = FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  /// Bildirime dokunulunca (uygulama açıkken ya da bildirimle açıldıysa)
  static void Function(String payload)? onTap;
  static String? launchPayload;

  static const weeklyId = 1001;

  static Future<void> init() async {
    if (!Platform.isAndroid || _ready) return;
    try {
      tzdata.initializeTimeZones();
      await _p.initialize(
        const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')),
        onDidReceiveNotificationResponse: (r) {
          final p = r.payload;
          if (p != null) onTap?.call(p);
        },
      );
      final l = await _p.getNotificationAppLaunchDetails();
      if (l?.didNotificationLaunchApp == true) launchPayload = l!.notificationResponse?.payload;
      _ready = true;
    } catch (_) {}
  }

  /// Android 13+: bildirim izni ister. Önceden verildiyse hemen true döner.
  static Future<bool> ask() async {
    if (!_ready) return false;
    try {
      final a = _p.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      return await a?.requestNotificationsPermission() ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> allowed() async {
    if (!_ready) return false;
    try {
      final a = _p.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      return await a?.areNotificationsEnabled() ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> schedule(int id, String title, String body, DateTime when, {String? payload}) async {
    if (!_ready) return;
    try {
      await _p.zonedSchedule(
        id,
        title,
        body,
        tz.TZDateTime.from(when.toUtc(), tz.UTC),
        NotificationDetails(
          android: AndroidNotificationDetails(
            'ekran_suresi',
            tx('Ekran süresi', 'Screen time'),
            channelDescription: tx('Haftalık ekran süresi özeti', 'Weekly screen time summary'),
            importance: Importance.defaultImportance,
            styleInformation: BigTextStyleInformation(body),
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
        payload: payload,
      );
    } catch (_) {}
  }

  static Future<void> cancel(int id) async {
    if (!_ready) return;
    try {
      await _p.cancel(id);
    } catch (_) {}
  }
}
