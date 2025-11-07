import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    // Initialize timezone (for proper scheduling)
    tz.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Kolkata'));

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: androidInit);
    await _plugin.initialize(settings);
  }
  /// Android 13+ runtime permission. Returns true if notifications are allowed.
  Future<bool> requestPermission() async {
    final androidImpl = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    // On Android <13 this returns null; treat as granted.
    final granted = await androidImpl?.requestNotificationsPermission();
    return granted ?? true;
  }

  /// Schedule the app's default three daily reminders.
  Future<void> scheduleDefaults() async {
    await scheduleDaily(
      hour: 7,
      minute: 0,
      title: '🕉️ Jap Reminder',
      body: 'सुबह की साधना शुरू करें — 108 जाप लक्ष्य रखें।',
    );
    await scheduleDaily(
      hour: 12,
      minute: 0,
      title: '🕉️ Mid-day Check-in',
      body: 'कुछ मिनट निकालें — मन को शान्त करें, कुछ जाप जोड़ें।',
    );
    await scheduleDaily(
      hour: 18,
      minute: 0,
      title: '🕉️ Evening Jap',
      body: 'दिन पूरा करें — आज की माला पूर्ण करने का संकल्प।',
    );
  }
  Future<void> showInstant(String title, String body) async {
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'default_channel',
        'General Notifications',
        importance: Importance.high,
        priority: Priority.high,
      ),
    );

    await _plugin.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      details,
    );
  }

  Future<void> scheduleDaily({
    required int hour,
    required int minute,
    required String title,
    required String body,
  }) async {
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'daily_channel',
        'Daily Reminders',
        importance: Importance.high,
        priority: Priority.high,
      ),
    );

    await _plugin.zonedSchedule(
      hour * 60 + minute, // unique ID per time
      title,
      body,
      _nextInstanceOfTime(hour, minute),
      details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
      UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  tz.TZDateTime _nextInstanceOfTime(int hour, int minute) {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }
}