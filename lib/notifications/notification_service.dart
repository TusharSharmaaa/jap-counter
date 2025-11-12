import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/services.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../data/activity_store.dart';
import '../data/dedication_store.dart';
import '../data/insight_store.dart';
import '../l10n/app_localizations.dart';

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

    // Timezone - use device local timezone
    try {
      tzdata.initializeTimeZones();
      tz.setLocalLocation(tz.local);
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

  Future<void> scheduleDefaults({String language = 'hi'}) async {
    await cancelAll();

    final dstore = await DedicationStore.create();
    final note = dstore.note.isEmpty ? 'Radha Jap Counter' : dstore.note;
    final streakDays = await ActivityStore.currentStreak();
    
    // Get localized streak message
    final streakMsgKey = streakDays >= 21
        ? 'notification.streak.21plus'
        : streakDays >= 7
        ? 'notification.streak.7plus'
        : 'notification.streak.default';
    final streakMsg = AppStrings.resolve(language, streakMsgKey);

    final insights = await InsightStore.create();
    final malas = insights.getTodayMalas();
    
    // Get localized body message
    final bodyKey = malas >= 1 ? 'notification.body.withMalas' : 'notification.body.noMalas';
    var body = AppStrings.resolve(language, bodyKey);
    body = body.replaceAll('{malas}', '$malas').replaceAll('{streakMsg}', streakMsg);

    // Get localized titles and bodies
    final morningTitle = AppStrings.resolve(language, 'notification.title.morning');
    final noonTitle = AppStrings.resolve(language, 'notification.title.noon');
    final eveningTitle = AppStrings.resolve(language, 'notification.title.evening');
    var noonBody = AppStrings.resolve(language, 'notification.body.noon');
    noonBody = noonBody.replaceAll('{note}', note);
    final eveningBody = AppStrings.resolve(language, 'notification.body.evening');

    final notifications = [
      _dailyAt(morningTitle, body, 7, 0, id: 700),
      _dailyAt(noonTitle, noonBody, 12, 0, id: 1200),
      _dailyAt(eveningTitle, eveningBody, 18, 0, id: 1800),
    ];

    for (final n in notifications) {
      try {
        await _plugin.zonedSchedule(
          n.id,
          n.title,
          n.body,
          n.scheduledDate,
          NotificationDetails(
            android: AndroidNotificationDetails(
              _channel.id,
              _channel.name,
              channelDescription: _channel.description,
              importance: Importance.high,
              priority: Priority.high,
              playSound: true,
              icon: '@mipmap/ic_launcher',
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

  Future<void> scheduleDynamicJapReminder(int todayJaps, {String language = 'hi'}) async {
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

    // Get localized notification text
    var title = AppStrings.resolve(language, 'notification.dynamic.title');
    title = title.replaceAll('{count}', '$todayJaps');
    final body = AppStrings.resolve(language, 'notification.dynamic.body');

    try {
      await _plugin.zonedSchedule(
        4,
        title,
        body,
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

  Future<void> scheduleDailyMotivation({String language = 'hi'}) async {
    final tzNow = tz.TZDateTime.now(tz.local);
    var scheduled7am = tz.TZDateTime(
      tz.local,
      tzNow.year,
      tzNow.month,
      tzNow.day,
      7,
    );
    // If it's already past 7am today, schedule for tomorrow
    if (scheduled7am.isBefore(tzNow)) {
      scheduled7am = scheduled7am.add(const Duration(days: 1));
    }
    
    // Get localized notification text
    final title = AppStrings.resolve(language, 'notification.motivation.title');
    final body = AppStrings.resolve(language, 'notification.motivation.body');
    
    try {
      await _plugin.zonedSchedule(
        2001,
        title,
        body,
        scheduled7am,
        NotificationDetails(
          android: AndroidNotificationDetails(
            _channel.id,
            _channel.name,
            channelDescription: _channel.description,
            importance: Importance.high,
            priority: Priority.high,
            playSound: true,
            icon: '@mipmap/ic_launcher',
          ),
        ),
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
