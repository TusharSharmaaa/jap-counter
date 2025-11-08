import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../data/dedication_store.dart';

class NotificationService {
  NotificationService._();
  static final NotificationService _i = NotificationService._();
  factory NotificationService() => _i;

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

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

    const AndroidInitializationSettings androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const DarwinInitializationSettings iosInit = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const InitializationSettings settings = InitializationSettings(android: androidInit, iOS: iosInit);

    await _plugin.initialize(settings);

    // Android channel
    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_channel);

    _initialized = true;
  }

  /// Android 13+ runtime permission; safe no-op on lower versions/iOS.
  Future<bool> requestPermission() async {
    try {
      final androidImpl = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      final granted = await androidImpl?.requestNotificationsPermission() ?? true;
      if (kDebugMode) debugPrint('[Notifications] permission: $granted');
      return granted;
    } catch (_) {
      // iOS handled by init; older Android doesn’t need runtime
      return true;
    }
  }

  /// Clears all pending notifications (does not remove the channel).
  Future<void> cancelAll() async {
    await _plugin.cancelAll();
  }

  /// Schedule 3 daily reminders (07:00, 12:00, 18:00 IST) with randomized devotional lines.
  /// Keeps your previous Settings toggle flow unchanged.
  Future<void> scheduleDefaults() async {
    await cancelAll(); // idempotent: clear then schedule

    final dstore = await DedicationStore.create();
    final userNote = dstore.note.isEmpty ? 'आपकी साधना जारी रहे 🌼' : dstore.note;

    final notifications = [
      {'id': 700, 'hour': 7, 'minute': 0, 'title': 'सुप्रभात', 'body': 'दिन की शुरुआत करें — $userNote'},
      {'id': 1200, 'hour': 12, 'minute': 0, 'title': 'मध्याह्न साधना', 'body': 'थोड़ा विराम लें, ध्यान करें 🌸'},
      {'id': 1800, 'hour': 18, 'minute': 0, 'title': 'संध्या साधना', 'body': 'रात से पहले कुछ पल शांति के 🌙'},
    ];

    for (final n in notifications) {
      await _scheduleDailyAt(
        id: n['id'] as int,
        hour: n['hour'] as int,
        minute: n['minute'] as int,
        title: n['title'] as String,
        body: n['body'] as String,
      );
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

    await _plugin.zonedSchedule(
      4,
      'आज का जप संख्याः $todayJaps',
      '“राधे राधे” के संग साधना पूर्ण करें 🌸',
      tz.TZDateTime.from(time, tz.local),
      notificationDetails,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      androidAllowWhileIdle: true,
      matchDateTimeComponents: DateTimeComponents.time,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
    );

    if (kDebugMode) {
      debugPrint('[Notifications] Dynamic reminder scheduled for $time with count $todayJaps');
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
    var scheduled = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
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
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time, // repeat daily at this time
    );

    if (kDebugMode) {
      debugPrint('[Notifications] Scheduled $hour:${minute.toString().padLeft(2, '0')} with: $title');
    }
  }
}
