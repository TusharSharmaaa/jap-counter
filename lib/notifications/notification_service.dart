import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/services.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../data/activity_store.dart';
import '../data/dedication_store.dart';
import '../data/insight_store.dart';

class NotificationService {
  NotificationService._();
  static final NotificationService _i = NotificationService._();
  factory NotificationService() => _i;

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  FlutterLocalNotificationsPlugin get plugin => _plugin;

  static Future<void> initialize() async {
    await NotificationService().init();
  }

  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'bhakti_daily_channel',
    'Bhakti Daily Reminders',
    description: 'Daily devotional reminders at 7:00 / 12:00 / 18:00',
    importance: Importance.high,
    playSound: true,
  );

  Future<void> init() async {
    if (_initialized) return;

    // Timezone
    try {
      tzdata.initializeTimeZones();
      tz.setLocalLocation(tz.getLocation('Asia/Kolkata'));
    } catch (e) {
      if (kDebugMode) debugPrint('[Notifications] TZ init failed: $e');
    }

    const AndroidInitializationSettings androidInit =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const DarwinInitializationSettings iosInit = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const InitializationSettings settings = InitializationSettings(
      android: androidInit,
      iOS: iosInit,
    );

    await _plugin.initialize(settings);

    // Android channel
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(_channel);

    _initialized = true;
  }

  /// Android 13+ runtime permission; safe no-op on lower versions/iOS.
  Future<bool> requestPermission() async {
    try {
      final androidImpl = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      final granted =
          await androidImpl?.requestNotificationsPermission() ?? true;
      if (kDebugMode) debugPrint('[Notifications] permission: $granted');
      return granted;
    } catch (_) {
      // iOS handled by init; older Android doesn’t need runtime
      return true;
    }
  }

  Future<bool> areNotificationsAllowed() async {
    try {
      final androidImpl = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      final android = await androidImpl?.areNotificationsEnabled();
      if (android != null) return android;
    } catch (_) {
      // ignored
    }
    return true;
  }

  /// Clears all pending notifications (does not remove the channel).
  Future<void> cancelAll() async {
    await _plugin.cancelAll();
  }

  Future<void> scheduleDefaults() async {
    await cancelAll();

    final dstore = await DedicationStore.create();
    final note = dstore.note.isEmpty ? 'Radha Jap Counter' : dstore.note;
    final streakDays = await ActivityStore.currentStreak();
    final streakMsg = (streakDays >= 21)
        ? '🔥 21+ दिन की निरंतर साधना — अद्भुत है!'
        : (streakDays >= 7)
        ? '🌸 7 दिन का अनुशासन — स्थिरता बनाए रखें।'
        : '🙏 आज भी कुछ पल शांत बैठें।';

    final insights = await InsightStore.create();
    final malas = insights.getTodayMalas();
    final body = malas >= 1
        ? 'आज आपने $malas माला जपी हैं — $streakMsg'
        : 'आपकी साधना प्रतीक्षा कर रही है — $streakMsg';

    final notifications = [
      _dailyAt('सुप्रभात साधक', body, 7, 0, id: 700),
      _dailyAt('मध्याह्न ध्यान', 'क्षणिक शांति लें — $note', 12, 0, id: 1200),
      _dailyAt('संध्या साधना', 'दिवस की पूर्णता ध्यान में 🌙', 18, 0, id: 1800),
    ];

    for (final n in notifications) {
      try {
        await _plugin.zonedSchedule(
          n.id,
          n.title,
          n.body,
          n.scheduledDate,
          const NotificationDetails(
            android: AndroidNotificationDetails(
              'daily_sadhana',
              'Daily Reminders',
              importance: Importance.high,
              priority: Priority.high,
            ),
          ),
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          matchDateTimeComponents: DateTimeComponents.time,
        );
      } on PlatformException catch (e) {
        if (kDebugMode) {
          debugPrint('[Notifications] Daily reminder skipped (${n.id}): $e');
        }
      }
    }
  }

  Future<void> scheduleDynamicJapReminder(int todayJaps) async {
    final notificationDetails = const NotificationDetails(
      android: AndroidNotificationDetails(
        'daily_jap_count',
        'Daily Jap Count',
        importance: Importance.high,
        priority: Priority.high,
        styleInformation: BigTextStyleInformation(''),
      ),
      iOS: DarwinNotificationDetails(),
    );

    final now = DateTime.now();
    DateTime time = DateTime(now.year, now.month, now.day, 20, 0);
    if (time.isBefore(now)) {
      time = time.add(const Duration(days: 1));
    }

    try {
      await _plugin.zonedSchedule(
        4,
        'आज का जप संख्याः $todayJaps',
        '“राधे राधे” के संग साधना पूर्ण करें 🌸',
        tz.TZDateTime.from(time, tz.local),
        notificationDetails,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        androidAllowWhileIdle: true,
        matchDateTimeComponents: DateTimeComponents.time,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    } on PlatformException catch (e) {
      if (kDebugMode) {
        debugPrint('[Notifications] Dynamic reminder skipped: $e');
      }
    }

    if (kDebugMode) {
      debugPrint(
        '[Notifications] Dynamic reminder scheduled for $time with count $todayJaps',
      );
    }
  }

  Future<void> scheduleDailyMotivation() async {
    const android = AndroidNotificationDetails(
      'daily_motivation',
      'Daily Motivation',
      importance: Importance.high,
      priority: Priority.high,
    );
    const details = NotificationDetails(android: android);
    final tzNow = tz.TZDateTime.now(tz.local);
    final tomorrow7am = tz.TZDateTime(
      tz.local,
      tzNow.year,
      tzNow.month,
      tzNow.day,
      7,
    ).add(const Duration(days: 1));
    try {
      await _plugin.zonedSchedule(
        2001,
        '🌞 नई साधना का दिन',
        'कल की तरह आज भी अपने जाप पूरे करें 🙏',
        tomorrow7am,
        details,
        androidAllowWhileIdle: true,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.time,
      );
    } on PlatformException catch (e) {
      if (kDebugMode) {
        debugPrint('[Notifications] Daily motivation scheduling skipped: $e');
      }
    }
  }

  Future<void> _scheduleDailyAt({
    required int hour,
    required int minute,
    required int id,
    required String title,
    required String body,
  }) async {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );
    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }

    await _plugin.zonedSchedule(
      id,
      title,
      body,
      scheduled,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          priority: Priority.high,
          importance: Importance.high,
          playSound: true,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: const DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents:
          DateTimeComponents.time, // repeat daily at this time
    );

    if (kDebugMode) {
      debugPrint(
        '[Notifications] Scheduled $hour:${minute.toString().padLeft(2, '0')} with: $title',
      );
    }
  }
}

class _DailyNotification {
  final int id;
  final String title;
  final String body;
  final tz.TZDateTime scheduledDate;

  const _DailyNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.scheduledDate,
  });
}

_DailyNotification _dailyAt(
  String title,
  String body,
  int hour,
  int minute, {
  required int id,
}) {
  final now = tz.TZDateTime.now(tz.local);
  var scheduled = tz.TZDateTime(
    tz.local,
    now.year,
    now.month,
    now.day,
    hour,
    minute,
  );
  if (scheduled.isBefore(now)) {
    scheduled = scheduled.add(const Duration(days: 1));
  }
  return _DailyNotification(
    id: id,
    title: title,
    body: body,
    scheduledDate: scheduled,
  );
}
