import 'package:flutter/widgets.dart';

class AppLocalizationScope extends InheritedWidget {
  final String language;

  const AppLocalizationScope({
    super.key,
    required this.language,
    required super.child,
  });

  static AppLocalizationScope of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<AppLocalizationScope>();
    assert(scope != null, 'AppLocalizationScope not found in widget tree');
    return scope!;
  }

  static AppLocalizationScope? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<AppLocalizationScope>();
  }

  @override
  bool updateShouldNotify(covariant AppLocalizationScope oldWidget) =>
      language != oldWidget.language;
}

class AppStrings {
  static const _values = <String, Map<String, String>>{
    'en': {
      // Navigation
      'nav.counter': 'Counter',
      'nav.stats': 'Stats',
      'nav.gita': 'Gita',
      'nav.timer': 'Timer',
      'nav.settings': 'Settings',

      // Generic
      'common.save': 'Save',
      'common.cancel': 'Cancel',
      'common.edit': 'Edit',
      'common.share': 'Share',
      'common.shareApp': 'Share App',
      'common.light': 'Light',
      'common.dark': 'Dark',
      'common.language': 'Language',
      'common.english': 'English',
      'common.hindi': 'Hindi',
      'common.reset': 'Reset',
      'common.on': 'On',
      'common.off': 'Off',
      'common.ok': 'OK',

      // Home snackbars
      'home.snackbar.progress':
          "Today's progress: {count} mala completed. Keep practicing 🙏",
      'home.snackbar.start': 'Begin a fresh practice tomorrow 🌸',

      // Stats page
      'stats.title': 'Stats',
      'stats.currentStreak': 'Current Streak',
      'stats.noActiveStreak': 'No active streak yet',
      'stats.streakMessage.7': '🌸 7-Day Streak — Discipline!',
      'stats.streakMessage.21': '🔥 21-Day Streak — Devotion!',
      'stats.streakMessage.40': '🌼 40-Day Tapasya — Rare!',
      'stats.streakMessage.generic': '✨ Current Streak: {days} days',
      'stats.metric.todayJaps': "Today's Japs",
      'stats.metric.todayMalas': "Today's Malas",
      'stats.metric.lifetimeMalas': 'Lifetime Malas',
      'stats.metric.todayMeditation': "Today's Meditation (min)",
      'stats.metric.lifetimeMeditation': 'Lifetime Meditation (min)',
      'stats.summary.malas': 'Malas',
      'stats.summary.meditation': 'Meditation (min)',
      'stats.summary.streak': 'Streak',
      'stats.dailyGoal.met': 'Daily Goal met — {todayMalas} / {goal} malas',
      'stats.dailyGoal.pending':
          'Daily Goal: {goal} malas • Today: {todayMalas}',
      'stats.progressTitle': '7-Day Progress',
      'stats.dedication.empty': 'Dedication: (tap edit to add)',
      'stats.dedication.title': 'Dedication: {note}',
      'stats.daysActive': 'Days Active: {count}',
      'stats.calendar': 'Calendar',
      'stats.shareButton': 'Share My Streak',
      'stats.sharePreparing': 'Preparing…',
      'stats.shareWait': 'Wait {time}',
      'stats.ambience.on': 'Ambience On',
      'stats.ambience.off': 'Ambience Off',
      'stats.legend.zero': '0 mala',
      'stats.legend.few': '1-4 malas',
      'stats.legend.some': '5-7 malas',
      'stats.legend.plenty': '8-14 malas',
      'stats.legend.intense': '15+ malas',
      'stats.calendar.today': 'Today',
      'stats.calendar.selected': '{date}\n{malas} malas • {japs} japs',
      'stats.calendar.summary': '{malas} malas • {japs} japs',
      'stats.dedication.editTitle': 'Edit Dedication',
      'stats.dedication.hint': 'e.g., Parents names',
      'stats.badge.streak7': '🔥 7-day Streak',
      'stats.badge.streak21': '🔥 21-day Streak',
      'stats.badge.streak40': '🔥 40-day Streak',

      // Settings page
      'settings.title': 'Settings',
      'settings.subtitle': 'Customize your experience',
      'settings.notifications': 'Notifications',
      'settings.notifications.daily': 'Daily Reminders',
      'settings.notifications.desc': 'Get reminded to maintain your streak',
      'settings.notifications.locked':
          'Notifications already enabled in system settings',
      'settings.notifications.denied':
          'Permission denied. Enable notifications from system settings.',
      'settings.notifications.systemOn': 'On (system)',
      'settings.goal': 'Daily Goal',
      'settings.goal.title': 'Target Malas per Day',
      'settings.goal.subtitle':
          'Set a simple, consistent daily target (0 to disable)',
      'settings.goal.updated': 'Daily goal updated',
      'settings.sound': 'Sound',
      'settings.sound.action': 'Play sound feedback on actions',
      'settings.sound.malaBell': 'Play bell sound on mala completion',
      'settings.about': 'About',
      'settings.privacy': 'Privacy Policy',
      'settings.terms': 'Terms & Conditions',
      'settings.aboutApp': 'About App',
      'settings.rate': 'Rate on Play Store',
      'settings.rate.subtitle': 'Share love & feedback with the community',
      'settings.data': 'Data Management',
      'settings.data.export': 'Export Backup',
      'settings.data.reset': 'Reset All Data',
      'settings.data.resetConfirm': 'Confirm Reset',
      'settings.data.resetMessage':
          'This will erase all jap, meditation, and streak data permanently. Continue?',
      'settings.data.resetSuccess': 'All data reset successfully.',
      'settings.language': 'Language',
      'settings.language.subtitle': 'Switch the app interface language',
      'settings.theme': 'Theme',
      'settings.theme.light': 'Light',
      'settings.theme.dark': 'Dark',
      'badge.platinum': 'Platinum',
      'badge.gold': 'Gold',
      'badge.silver': 'Silver',
      'badge.bronze': 'Bronze',
      'badge.new': 'New',

      // Counter page
      'counter.goal.cta': 'Set daily mala goal',
      'counter.goal.label': 'Goal: {count} mala{suffix}',
      'counter.goal.status.none': 'Tap to add a daily mala target',
      'counter.goal.status.met': '✅ Goal met for today',
      'counter.goal.status.progress': 'Progress: {malas} / {goal} mala{suffix}',
      'counter.mala.new': 'Start a new mala',
      'counter.mala.remaining': '{count} more japs will complete this mala',
      'counter.malaCompleted': '🎯 Mala completed! Keep your practice going.',
      'counter.streak.milestone': '✨ {days}-day streak! Keep going.',
      'counter.streak.dedication': '🔥 {days}-Day Streak — Keep your practice going!',
      'counter.goal.dialog.title': 'Set your daily jap goal (malas)',
      'counter.goal.dialog.noGoal': 'No daily goal',
      'counter.goal.dialog.goalText': '{count} mala{suffix} per day',
      'counter.goal.dialog.hint': 'Use the slider to adjust your daily mala goal.',

      // Timer
      'timer.complete.title': 'Meditation Completed',
      'timer.complete.message':
          'You meditated for {minutes} minute(s). Take a deep breath before you continue.',
      'timer.ambience.label': 'Select sound',
      'timer.ambience.mute': 'Mute',
      'timer.ambience.om': 'Om',
      'timer.ambience.flute': 'Flute',
      'timer.ambience.birds': 'Birds',
      'timer.ambience.water': 'Water',
      'timer.share.cardTitle': 'Meditation Snapshot',
      'timer.share.subtitle': 'Keep showing up. Every breath counts.',
      'timer.share.today': 'Today',
      'timer.share.lifetime': 'Lifetime',
      'timer.share.cta': 'Share meditation',
      'timer.share.caption':
          'Today: {today} · Lifetime: {lifetime} — Naam Jap Counter : Sadhna',
      'timer.share.error': 'Unable to share right now. Please try again.',

      // Share card
      'share.appBar': 'Share My Streak',
      'share.title': '🌸 My Sadhana Journey 🌸',
      'share.streakLabel': '🔥 {days} day streak',
      'share.date': '{date}',
      'share.todayJaps': 'Today\'s Japs · {value}',
      'share.lifetimeMalas': 'Lifetime Malas · {value}',
      'share.streakDays': 'Practice Days · {value}',
      'share.dedication': '💠 Dedication: {note}',
      'share.motto': '“Every chant counts in silence.” 🌼',
      'share.footer': 'Naam Jap Counter : Sadhna',
      'share.footerSub': 'Download from Play Store today',
      'share.saveTooltip': 'Save Image',
      'share.whatsappTooltip': 'WhatsApp',
      'share.shareText': '🌸 Glimpse of my practice — with Naam Jap Counter : Sadhna.',
      'share.shareTextLink':
          '🌸 Download Naam Jap Counter : Sadhna today: https://play.google.com/store/apps/details?id=com.example.jap_counter',
      'share.saved': 'Saved image to: {path}',
      'share.donate': 'Tap to support',

      // Notifications
      'notification.streak.21plus': '🔥 21+ days of continuous practice — Amazing!',
      'notification.streak.7plus': '🌸 7 days of discipline — Keep the momentum!',
      'notification.streak.default': '🙏 Take a few quiet moments today.',
      'notification.body.withMalas': 'Today you completed {malas} malas — {streakMsg}',
      'notification.body.noMalas': 'Your practice awaits — {streakMsg}',
      'notification.title.morning': 'Good Morning Sadhak',
      'notification.title.noon': 'Midday Meditation',
      'notification.title.evening': 'Evening Practice',
      'notification.body.noon': 'Take a moment of peace — {note}',
      'notification.body.evening': 'Complete the day in meditation 🌙',
      'notification.dynamic.title': "Today's Jap Count: {count}",
      'notification.dynamic.body': 'Complete your practice with "Radhe Radhe" 🌸',
      'notification.motivation.title': '🌞 A New Day of Practice',
      'notification.motivation.body': 'Complete your japs today, just like yesterday 🙏',
    },
    'hi': {
      // Navigation
      'nav.counter': 'जप',
      'nav.stats': 'आँकड़े',
      'nav.gita': 'गीता',
      'nav.timer': 'घड़ी',
      'nav.settings': 'सेटिंग्स',

      // Generic
      'common.save': 'सहेजें',
      'common.cancel': 'रद्द करें',
      'common.edit': 'संपादित करें',
      'common.share': 'साझा करें',
      'common.shareApp': 'ऐप साझा करें',
      'common.light': 'लाइट',
      'common.dark': 'डार्क',
      'common.language': 'भाषा',
      'common.english': 'English',
      'common.hindi': 'हिन्दी',
      'common.reset': 'रीसेट',
      'common.on': 'चालू',
      'common.off': 'बंद',
      'common.ok': 'ठीक है',

      // Home snackbars
      'home.snackbar.progress':
          'आज की प्रगति: {count} माला पूर्ण हुई। साधना जारी रखें 🙏',
      'home.snackbar.start': 'कल से नई साधना यात्रा प्रारंभ करें 🌸',

      // Stats page
      'stats.title': 'आँकड़े',
      'stats.currentStreak': 'वर्तमान श्रंखला',
      'stats.noActiveStreak': 'अभी कोई श्रंखला सक्रिय नहीं',
      'stats.streakMessage.7': '🌸 7-दिन की श्रंखला — अनुशासन!',
      'stats.streakMessage.21': '🔥 21-दिन की श्रंखला — भक्ति!',
      'stats.streakMessage.40': '🌼 40-दिन तपस्या — अद्भुत!',
      'stats.streakMessage.generic': '✨ श्रंखला: {days} दिन',
      'stats.metric.todayJaps': 'आज के जप',
      'stats.metric.todayMalas': 'आज की मालाएँ',
      'stats.metric.lifetimeMalas': 'कुल मालाएँ',
      'stats.metric.todayMeditation': 'आज का ध्यान (मि)',
      'stats.metric.lifetimeMeditation': 'कुल ध्यान (मि)',
      'stats.summary.malas': 'मालाएँ',
      'stats.summary.meditation': 'ध्यान (मि)',
      'stats.summary.streak': 'श्रंखला',
      'stats.dailyGoal.met': 'दैनिक लक्ष्य पूर्ण — {todayMalas} / {goal} माला',
      'stats.dailyGoal.pending': 'दैनिक लक्ष्य: {goal} माला • आज: {todayMalas}',
      'stats.progressTitle': '7-दिन प्रगति',
      'stats.dedication.empty': 'समर्पण: (जोड़ने हेतु टैप करें)',
      'stats.dedication.title': 'समर्पण: {note}',
      'stats.daysActive': 'सक्रिय दिन: {count}',
      'stats.calendar': 'कैलेंडर',
      'stats.shareButton': 'श्रंखला साझा करें',
      'stats.sharePreparing': 'तैयार कर रहे हैं…',
      'stats.shareWait': '{time} प्रतीक्षा करें',
      'stats.ambience.on': 'ध्वनि चालू',
      'stats.ambience.off': 'ध्वनि बंद',
      'stats.legend.zero': '0 माला',
      'stats.legend.few': '1-4 माला',
      'stats.legend.some': '5-7 माला',
      'stats.legend.plenty': '8-14 माला',
      'stats.legend.intense': '15+ माला',
      'stats.calendar.today': 'आज',
      'stats.calendar.selected': '{date}\n{malas} माला • {japs} जप',
      'stats.calendar.summary': '{malas} माला • {japs} जप',
      'stats.dedication.editTitle': 'समर्पण संपादित करें',
      'stats.dedication.hint': 'जैसे, माता-पिता का नाम',
      'stats.badge.streak7': '🔥 7-दिन की श्रंखला',
      'stats.badge.streak21': '🔥 21-दिन की श्रंखला',
      'stats.badge.streak40': '🔥 40-दिन की श्रंखला',

      // Settings page
      'settings.title': 'सेटिंग्स',
      'settings.subtitle': 'अनुभव को अनुकूलित करें',
      'settings.notifications': 'सूचनाएँ',
      'settings.notifications.daily': 'दैनिक अनुस्मारक',
      'settings.notifications.desc': 'श्रंखला बनाए रखने की याद दिलाएँ',
      'settings.notifications.locked': 'सूचनाएँ सिस्टम सेटिंग्स से चालू हैं',
      'settings.notifications.denied':
          'अनुमति अस्वीकृत। सिस्टम सेटिंग्स में सूचनाएँ चालू करें।',
      'settings.notifications.systemOn': 'सिस्टम द्वारा चालू',
      'settings.goal': 'दैनिक लक्ष्य',
      'settings.goal.title': 'प्रति दिन लक्षित माला',
      'settings.goal.subtitle':
          'सरल एवं निरंतर लक्ष्य चुनें (0 से निष्क्रिय करें)',
      'settings.goal.updated': 'दैनिक लक्ष्य अपडेट हुआ',
      'settings.sound': 'ध्वनि',
      'settings.sound.action': 'क्रियाओं पर ध्वनि चलाएँ',
      'settings.sound.malaBell': 'माला पूर्ण होने पर घंटी बजाएँ',
      'settings.about': 'परिचय',
      'settings.privacy': 'गोपनीयता नीति',
      'settings.terms': 'नियम व शर्तें',
      'settings.aboutApp': 'ऐप के बारे में',
      'settings.rate': 'प्ले स्टोर पर रेट करें',
      'settings.rate.subtitle': 'समुदाय के साथ अपना अनुभव साझा करें',
      'settings.data': 'डेटा प्रबंधन',
      'settings.data.export': 'बैकअप निर्यात करें',
      'settings.data.reset': 'सभी डेटा रीसेट करें',
      'settings.data.resetConfirm': 'रीसेट पुष्टि',
      'settings.data.resetMessage':
          'यह सभी जप, ध्यान और श्रंखला डेटा स्थायी रूप से मिटा देगा। जारी रखें?',
      'settings.data.resetSuccess': 'सभी डेटा सफलतापूर्वक रीसेट हुआ।',
      'settings.language': 'भाषा',
      'settings.language.subtitle': 'ऐप का इंटरफ़ेस भाषा चुनें',
      'settings.theme': 'विषय',
      'settings.theme.light': 'लाइट',
      'settings.theme.dark': 'डार्क',
      'badge.platinum': 'प्लैटिनम',
      'badge.gold': 'स्वर्ण',
      'badge.silver': 'रजत',
      'badge.bronze': 'कांस्य',
      'badge.new': 'नया',

      // Counter page
      'counter.goal.cta': 'दैनिक माला लक्ष्य चुनें',
      'counter.goal.label': 'लक्ष्य: {count} माला{suffix}',
      'counter.goal.status.none': 'दैनिक माला लक्ष्य जोड़ने हेतु टैप करें',
      'counter.goal.status.met': '✅ लक्ष्य प्राप्त हो चुका है',
      'counter.goal.status.progress': 'प्रगति: {malas} / {goal} माला{suffix}',
      'counter.mala.new': 'नई माला प्रारंभ करें',
      'counter.mala.remaining': '{count} और जप इस माला को पूर्ण करेंगे',
      'counter.malaCompleted': '🎯 माला पूर्ण! साधना जारी रखें।',
      'counter.streak.milestone': '✨ {days}-दिन की श्रंखला! जारी रखें।',
      'counter.streak.dedication': '🔥 {days}-दिन की साधना — निरंतर जारी है!',
      'counter.goal.dialog.title': 'दैनिक जप लक्ष्य चुनें (माला)',
      'counter.goal.dialog.noGoal': 'कोई दैनिक लक्ष्य नहीं',
      'counter.goal.dialog.goalText': 'प्रति दिन {count} माला{suffix}',
      'counter.goal.dialog.hint': 'दैनिक माला लक्ष्य समायोजित करने हेतु स्लाइडर का उपयोग करें।',

      // Timer
      'timer.complete.title': 'साधना पूर्ण हुई',
      'timer.complete.message':
          'आपने {minutes} मिनट ध्यान किया। एक गहरी साँस लें और आगे बढ़ें।',
      'timer.ambience.label': 'ध्वनि चुनें',
      'timer.ambience.mute': 'मूक',
      'timer.ambience.om': 'ॐ',
      'timer.ambience.flute': 'बांसुरी',
      'timer.ambience.birds': 'पक्षियों की ध्वनि',
      'timer.ambience.water': 'जलधारा',
      'timer.share.cardTitle': 'ध्यान सारांश',
      'timer.share.subtitle': 'नित्य अभ्यास से ही मन स्थिर होता है।',
      'timer.share.today': 'आज',
      'timer.share.lifetime': 'कुल योग',
      'timer.share.cta': 'ध्यान साझा करें',
      'timer.share.caption':
          'आज: {today} · कुल: {lifetime} — Naam Jap Counter : Sadhna',
      'timer.share.error': 'अभी साझा नहीं कर सके। कृपया पुनः प्रयास करें।',

      // Share card
      'share.appBar': 'श्रंखला साझा करें',
      'share.title': '🌸 मेरा साधना सफर 🌸',
      'share.streakLabel': '🔥 {days} दिन की साधना',
      'share.date': '{date}',
      'share.todayJaps': 'आज के जप · {value}',
      'share.lifetimeMalas': 'जीवनभर की मालाएँ · {value}',
      'share.streakDays': 'अभ्यास के दिन · {value}',
      'share.dedication': '💠 समर्पण: {note}',
      'share.motto': '“हर जप मौन में मायने रखता है।” 🌼',
      'share.footer': 'Naam Jap Counter : Sadhna',
      'share.footerSub': 'आज ही Play Store से डाउनलोड करें',
      'share.saveTooltip': 'चित्र सहेजें',
      'share.whatsappTooltip': 'व्हाट्सऐप',
      'share.shareText': '🌸 मेरी साधना की झलक — Naam Jap Counter : Sadhna के साथ।',
      'share.shareTextLink':
          '🌸 आज ही Naam Jap Counter : Sadhna डाउनलोड करें: https://play.google.com/store/apps/details?id=com.example.jap_counter',
      'share.saved': 'चित्र सहेजा गया: {path}',
      'share.donate': 'सहयोग हेतु टैप करें',

      // Notifications
      'notification.streak.21plus': '🔥 21+ दिन की निरंतर साधना — अद्भुत है!',
      'notification.streak.7plus': '🌸 7 दिन का अनुशासन — स्थिरता बनाए रखें।',
      'notification.streak.default': '🙏 आज भी कुछ पल शांत बैठें।',
      'notification.body.withMalas': 'आज आपने {malas} माला जपी हैं — {streakMsg}',
      'notification.body.noMalas': 'आपकी साधना प्रतीक्षा कर रही है — {streakMsg}',
      'notification.title.morning': 'सुप्रभात साधक',
      'notification.title.noon': 'मध्याह्न ध्यान',
      'notification.title.evening': 'संध्या साधना',
      'notification.body.noon': 'क्षणिक शांति लें — {note}',
      'notification.body.evening': 'दिवस की पूर्णता ध्यान में 🌙',
      'notification.dynamic.title': 'आज का जप संख्याः {count}',
      'notification.dynamic.body': '"राधे राधे" के संग साधना पूर्ण करें 🌸',
      'notification.motivation.title': '🌞 नई साधना का दिन',
      'notification.motivation.body': 'कल की तरह आज भी अपने जाप पूरे करें 🙏',
    },
  };

  static String resolve(String language, String key) {
    final langMap = _values[language] ?? _values['en']!;
    final value = langMap[key] ?? _values['en']![key];
    if (value == null) {
      return key;
    }
    return value;
  }
}

extension LocalizationExt on BuildContext {
  String tr(String key, {Map<String, String>? args}) {
    final lang = AppLocalizationScope.of(this).language;
    var value = AppStrings.resolve(lang, key);
    if (args != null) {
      args.forEach((k, v) {
        value = value.replaceAll('{$k}', v);
      });
    }
    return value;
  }
}
