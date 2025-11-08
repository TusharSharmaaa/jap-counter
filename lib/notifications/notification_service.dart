import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  NotificationService._();
  static final NotificationService _i = NotificationService._();
  factory NotificationService() => _i;

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  // Devotional lines (Hindi) — short, respectful, non-intrusive
  static final List<String> _messages = [
    'हर मंत्र एक कदम है — साधना जारी रखें।',
    'ख़ामोशी में शक्ति है — आज का ध्यान पूरा करें।',
    '108 नहीं भी हो तो क्या — आज की शुरुआत यहीं से।',
    'माला गिनती नहीं, मन गवाही देता है — जुड़िए।',
    'थोड़ा-थोड़ा, रोज़-रोज़ — यही है तप।',
    'नियत पक्की हो, तो समय खुद जगह देता है।',
    'श्वासों की गिनती छोड़िए, जाप पकड़िए।',
    'जहां ध्यान, वहीं धाम — 5 मिनट अभी।',
    'धीरे-धीरे, पर ठहरे रहें — साधना वहीं खिलती है।',
    'आज की शांति, कल की शक्ति बनती है।',
  ];

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

    await _scheduleDailyAt(hour: 7, minute: 0, id: 700);
    await _scheduleDailyAt(hour: 12, minute: 0, id: 1200);
    await _scheduleDailyAt(hour: 18, minute: 0, id: 1800);
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

  Future<void> _scheduleDailyAt({required int hour, required int minute, required int id}) async {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }

    final msg = _pickMessage();

    await _plugin.zonedSchedule(
      id,
      'भक्ति स्मरण',
      msg,
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
      debugPrint('[Notifications] Scheduled $hour:${minute.toString().padLeft(2, '0')} with: $msg');
    }
  }

  String _pickMessage() {
    // Random devotional line; could be enhanced with streak/context later
    final rnd = Random();
    return _messages[rnd.nextInt(_messages.length)];
    // Optional: attach a soft CTA like "आज 5 मिनट ध्यान करें"
  }
}
