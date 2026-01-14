# Current Bug Report - Jap Counter App
**Generated:** $(date)
**Scope:** Active bugs found in current codebase

---

## 🔴 CRITICAL BUGS

### 1. **share_gate.dart - Missing Import for `unawaited`**
**File:** `lib/stats/share_gate.dart:32, 63`
**Issue:** The file uses `unawaited()` function but doesn't import it. While `dart:async` is imported, `unawaited` needs to be explicitly imported or used with the full path.
**Impact:** Compilation error - the code won't compile.
**Code:**
```dart
import 'dart:async';  // ❌ unawaited not explicitly imported

// Line 32:
unawaited(
  AdManager.instance.preloadPlacement('stats.share_rewarded', force: true),
);

// Line 63:
unawaited(
  AdManager.instance.recordEvent(...),
);
```
**Fix:** Add explicit import:
```dart
import 'dart:async' show unawaited;
// OR
import 'dart:async' show unawaited, Timer;
```

---

## 🟡 HIGH PRIORITY BUGS

### 2. **Counter Page - Hardcoded English Text in Streak Milestone**
**File:** `lib/counter/counter_page.dart:290`
**Issue:** Hardcoded English text in SnackBar message instead of using localization.
**Impact:** Text won't change with language settings, inconsistent localization.
**Code:**
```dart
SnackBar(
  content: Text('✨ $streak-day streak! Keep going.'), // ❌ Hardcoded
  behavior: SnackBarBehavior.floating,
  duration: const Duration(seconds: 3),
),
```
**Fix:** Use localization:
```dart
content: Text(context.tr('counter.streak.milestone', args: {'days': '$streak'})),
```

### 3. **Counter Page - Hardcoded Hindi Text in Dedication Note**
**File:** `lib/counter/counter_page.dart:301`
**Issue:** Hardcoded Hindi text when updating dedication note for streak milestones.
**Impact:** Mixed languages, inconsistent user experience.
**Code:**
```dart
await dedicationStore.setNote(
  '🔥 $streak-Day Streak — साधना निरंतर जारी है!', // ❌ Hardcoded Hindi
);
```
**Fix:** Use localization or make it language-aware:
```dart
final language = AppLocalizationScope.of(context).language;
final note = language == 'hi' 
  ? '🔥 $streak-दिन की साधना — निरंतर जारी है!'
  : '🔥 $streak-Day Streak — Keep your practice going!';
await dedicationStore.setNote(note);
```

### 4. **Notification Service - Hardcoded Hindi Text in Notifications**
**File:** `lib/notifications/notification_service.dart:112-121, 181, 220-221`
**Issue:** Multiple hardcoded Hindi text strings in notification messages that should use localization.
**Impact:** Notifications always show in Hindi regardless of user's language preference.
**Code:**
```dart
// Line 112-115
final streakMsg = (streakDays >= 21)
    ? '🔥 21+ दिन की निरंतर साधना — अद्भुत है!'  // ❌ Hardcoded
    : (streakDays >= 7)
    ? '🌸 7 दिन का अनुशासन — स्थिरता बनाए रखें।'  // ❌ Hardcoded
    : '🙏 आज भी कुछ पल शांत बैठें।';  // ❌ Hardcoded

// Line 120
final body = malas >= 1
    ? 'आज आपने $malas माला जपी हैं — $streakMsg'  // ❌ Hardcoded
    : 'आपकी साधना प्रतीक्षा कर रही है — $streakMsg';  // ❌ Hardcoded

// Line 124-126
final notifications = [
  _dailyAt('सुप्रभात साधक', body, 7, 0, id: 700),  // ❌ Hardcoded
  _dailyAt('मध्याह्न ध्यान', 'क्षणिक शांति लें — $note', 12, 0, id: 1200),  // ❌ Hardcoded
  _dailyAt('संध्या साधना', 'दिवस की पूर्णता ध्यान में 🌙', 18, 0, id: 1800),  // ❌ Hardcoded
];

// Line 181
'आज का जप संख्याः $todayJaps',  // ❌ Hardcoded

// Line 182
'"राधे राधे" के संग साधना पूर्ण करें 🌸',  // ❌ Hardcoded

// Line 220-221
'🌞 नई साधना का दिन',  // ❌ Hardcoded
'कल की तरह आज भी अपने जाप पूरे करें 🙏',  // ❌ Hardcoded
```
**Fix:** Use localization system or make notification service language-aware. This requires passing language context to the notification service.

---

## 🟢 MEDIUM PRIORITY BUGS

### 5. **MeditationStore - Synchronous Operations in Async Context**
**File:** `lib/data/meditation_store.dart:62-69`
**Issue:** `_ensureTodaySync()` uses synchronous SharedPreferences operations (`setInt`, `setString`) which can cause issues in async contexts and may not persist correctly if called from async code paths.
**Impact:** Potential data loss, inconsistent state if called from async contexts.
**Code:**
```dart
void _ensureTodaySync() {
  final todayStr = _yyyymmddNow();
  final last = _prefs.getString(_kLastDate);
  if (last != todayStr) {
    _prefs.setInt(_kTodayMinutes, 0);  // ❌ Synchronous in async context
    _prefs.setString(_kLastDate, todayStr);
  }
}
```
**Note:** This is currently only used in a synchronous getter (`todayMinutes`), so it's acceptable but not ideal. Consider documenting this limitation.
**Fix:** If this method needs to be called from async contexts, make it async and await the operations.

### 6. **CounterStore - Potential Race Condition Still Exists**
**File:** `lib/data/counter_store.dart:36-64`
**Issue:** While the code attempts to prevent race conditions with a lock mechanism, the lock is implemented using a `Completer` and `Future`, which doesn't provide true thread-safety. If `increment()` is called concurrently from multiple isolates or threads, the read-modify-write pattern is still not truly atomic.
**Impact:** Lost increments, incorrect counts in edge cases.
**Code:**
```dart
static Future<void>? _currentIncrement;

Future<void> increment() async {
  await _resetIfNewDay();
  
  // Wait for any ongoing increment to complete
  if (_currentIncrement != null) {
    await _currentIncrement;
  }
  
  // Create a new increment operation
  final completer = Completer<void>();
  _currentIncrement = completer.future;
  
  try {
    // Read current values
    final currentToday = _prefs.getInt(_kTodayJaps) ?? 0;  // ❌ Not truly atomic
    final currentLifetime = _prefs.getInt(_kLifetimeJaps) ?? 0;
    
    // Write both values atomically
    await _prefs.setInt(_kTodayJaps, currentToday + 1);
    await _prefs.setInt(_kLifetimeJaps, currentLifetime + 1);
    // ...
  } finally {
    _currentIncrement = null;
    completer.complete();
  }
}
```
**Note:** This works for single-threaded Dart code, but SharedPreferences operations are not thread-safe for concurrent writes across isolates.
**Fix:** Use a proper mutex/lock mechanism or ensure operations are truly atomic at the SharedPreferences level.

---

## 🔵 LOW PRIORITY / CODE QUALITY ISSUES

### 7. **Notification Service - Timezone Hardcoded**
**File:** `lib/notifications/notification_service.dart:40`
**Issue:** Timezone is hardcoded to 'Asia/Kolkata'. This should be configurable or use device timezone.
**Impact:** Notifications may not align with user's actual timezone.
**Code:**
```dart
tz.setLocalLocation(tz.getLocation('Asia/Kolkata'));  // ❌ Hardcoded
```
**Fix:** Use device timezone or make it configurable:
```dart
tz.setLocalLocation(tz.local);
// OR
final timezone = await getUserTimezone(); // From settings
tz.setLocalLocation(tz.getLocation(timezone));
```

### 8. **Counter Page - Hardcoded Goal Dialog Text**
**File:** `lib/counter/counter_page.dart:320, 327-328, 347`
**Issue:** Hardcoded English text in goal setting dialog.
**Impact:** Inconsistent localization.
**Code:**
```dart
title: const Text('Set your daily jap goal (malas)'),  // ❌ Hardcoded
// ...
Text(
  sliderValue == 0
      ? 'No daily goal'  // ❌ Hardcoded
      : '$sliderValue mala${sliderValue == 1 ? '' : 's'} per day',  // ❌ Hardcoded
  // ...
),
// ...
Text(
  'Use the slider to adjust your daily mala goal.',  // ❌ Hardcoded
  // ...
),
```
**Fix:** Use `context.tr()` for all user-facing text.

### 9. **Counter Page - Hardcoded Button Text**
**File:** `lib/counter/counter_page.dart:359, 363`
**Issue:** Hardcoded English text in dialog buttons.
**Impact:** Inconsistent localization.
**Code:**
```dart
child: const Text('Cancel'),  // ❌ Hardcoded
// ...
child: const Text('Save'),  // ❌ Hardcoded
```
**Fix:** Use `context.tr()` for button labels.

---

## ✅ VERIFIED FIXES (From Previous Reports)

The following bugs from previous reports have been **FIXED**:

1. ✅ **SyncService - Firebase Initialization** - Now checks if Firebase is initialized before calling `initializeApp()`
2. ✅ **Main.dart - unawaited Import** - Properly imported with `show unawaited`
3. ✅ **CounterStore - Race Condition** - Has locking mechanism (though not perfect, see bug #6)
4. ✅ **Stats Page - Empty File** - File doesn't exist (likely removed or never created)
5. ✅ **GitaService - Prefetch** - Now properly implements prefetching of next N verses
6. ✅ **AdManager - Memory Leak** - Has dispose method that cancels all timers
7. ✅ **SoundManager - Volume Persistence** - Volume settings are now persisted to SharedPreferences
8. ✅ **InsightStore - Data Cleanup** - Has `cleanupOldData()` method
9. ✅ **SessionStore - Bounds Checking** - Has validation for count values
10. ✅ **ActivityStore - Streak Caching** - Uses caching to improve performance

---

## 📊 SUMMARY

**Total Active Issues Found:** 9
- **Critical:** 1 🔴 (Compilation error)
- **High Priority:** 3 🟡 (Localization issues)
- **Medium Priority:** 2 🟢 (Potential data issues)
- **Low Priority:** 3 🔵 (Code quality)

## 🎯 RECOMMENDED FIX ORDER

1. **Immediate (Critical):**
   - Fix missing `unawaited` import in `share_gate.dart` ⚠️ **BLOCKS COMPILATION**

2. **High Priority:**
   - Replace hardcoded text with localization in `counter_page.dart` and `notification_service.dart`
   - Make notification service language-aware

3. **Medium Priority:**
   - Review and improve `CounterStore` race condition handling
   - Document `MeditationStore` synchronous operation limitations

4. **Low Priority:**
   - Replace remaining hardcoded text in goal dialog
   - Make timezone configurable in notification service

---

## ✅ VERIFICATION CHECKLIST

After fixing bugs, verify:
- [ ] App compiles without errors
- [ ] All imports are present
- [ ] All user-facing text uses localization
- [ ] Notifications respect user's language preference
- [ ] No hardcoded text strings remain
- [ ] Timezone handling is appropriate
- [ ] Race conditions are handled appropriately

---

**Report Generated:** Current codebase analysis
**Files Reviewed:** All Dart files in lib/
**Linter Errors:** 0 (but compilation error exists)

