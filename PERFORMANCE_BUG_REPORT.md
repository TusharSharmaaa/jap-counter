# Performance Bug Report - Jap Counter App
**Generated:** Final comprehensive analysis
**Focus:** All bugs causing app slowness, hangs, and poor performance

---

## 🔴 CRITICAL PERFORMANCE BUGS

### 1. **Stats Page - Multiple FutureBuilders Rebuilding on Every setState**
**File:** `lib/app.dart:557, 629, 707, 747, 869, 992`
**Issue:** The Stats page has 6+ FutureBuilders that rebuild every time the parent widget calls setState(). Each FutureBuilder creates a new Future, causing unnecessary async operations and rebuilds.
**Impact:** Stats page rebuilds trigger 6+ async operations simultaneously, causing UI lag and hangs.
**Code:**
```dart
// Line 557 - Rebuilds on every parent setState
FutureBuilder<int>(
  future: ActivityStore.currentStreak(), // ❌ New Future every build
  builder: (context, snap) { ... }
)

// Line 629 - Rebuilds on every parent setState
FutureBuilder<Set<String>>(
  future: GamifyStore.badges(), // ❌ New Future every build
  builder: (context, snapshot) { ... }
)

// Line 707 - Rebuilds on every parent setState
FutureBuilder<int>(
  future: (() async { // ❌ New Future every build
    final gs = await GoalStore.create();
    return gs.dailyMalasGoal;
  })(),
  builder: (context, snap) { ... }
)

// Line 747 - Rebuilds on every parent setState
FutureBuilder<List<Map<String, dynamic>>>(
  future: WeeklyChartData.build(), // ❌ New Future every build
  builder: (context, snap) { ... }
)

// Line 869 - Rebuilds on every parent setState
FutureBuilder<String>(
  future: DedicationStore.create().then((s) => s.note), // ❌ New Future every build
  builder: (context, snap) { ... }
)

// Line 992 - Rebuilds on every parent setState
FutureBuilder<int>(
  future: ActivityStore.totalActiveDays(), // ❌ New Future every build
  builder: (context, snap) { ... }
)
```
**Fix:** Cache Futures in State or use FutureProvider/StreamProvider:
```dart
// In _StatsPageState:
Future<int>? _streakFuture;
Future<Set<String>>? _badgesFuture;
Future<int>? _goalFuture;
Future<List<Map<String, dynamic>>>? _chartFuture;
Future<String>? _dedicationFuture;
Future<int>? _activeDaysFuture;

@override
void initState() {
  super.initState();
  _streakFuture = ActivityStore.currentStreak();
  _badgesFuture = GamifyStore.badges();
  _goalFuture = GoalStore.create().then((gs) => gs.dailyMalasGoal);
  _chartFuture = WeeklyChartData.build();
  _dedicationFuture = DedicationStore.create().then((s) => s.note);
  _activeDaysFuture = ActivityStore.totalActiveDays();
}

// Then use cached futures:
FutureBuilder<int>(
  future: _streakFuture,
  builder: (context, snap) { ... }
)
```

---

### 2. **Timer Service - notifyListeners() Called Every Second**
**File:** `lib/timer/timer_service.dart:203-212`
**Issue:** Timer.periodic calls notifyListeners() every second when timer is running, causing all listeners (including TimerPage) to rebuild 60 times per minute.
**Impact:** Constant rebuilds cause UI lag, battery drain, and poor performance.
**Code:**
```dart
void _startTicker() {
  _stopTicker();
  _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
    if (!_running) return;
    if (remaining == Duration.zero) {
      unawaited(_complete());
      return;
    }
    notifyListeners(); // ❌ Called every second - too frequent!
  });
  notifyListeners();
}
```
**Fix:** Debounce or throttle notifyListeners, or only notify when display value changes:
```dart
int? _lastDisplayedSeconds;

void _startTicker() {
  _stopTicker();
  _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
    if (!_running) return;
    if (remaining == Duration.zero) {
      unawaited(_complete());
      return;
    }
    // Only notify if displayed seconds changed
    final currentSeconds = remaining.inSeconds;
    if (_lastDisplayedSeconds != currentSeconds) {
      _lastDisplayedSeconds = currentSeconds;
      notifyListeners();
    }
  });
  notifyListeners();
}
```

---

### 3. **Counter Page - Sequential Async Operations Blocking UI**
**File:** `lib/counter/counter_page.dart:112-186`
**Issue:** `_incrementJap()` performs multiple sequential async operations (SharedPreferences, InsightStore, ActivityStore, NotificationService) that block the UI thread.
**Impact:** Rapid taps cause lag, UI freezes, and poor responsiveness.
**Code:**
```dart
Future<void> _incrementJap() async {
  // ... 
  await store.increment(); // ❌ Blocks UI
  
  try {
    final insights = await InsightStore.create(); // ❌ Blocks UI
    await insights.recordJap(count: 1, malas: willBe % 108 == 0 ? 1 : 0);
  } catch (e) { ... }
  
  if (wasZero) {
    await ActivityStore.markTodayActive(); // ❌ Blocks UI
    await _handleStreakMilestones(context, showSnackBar: true); // ❌ Blocks UI
  }
  
  // ... more blocking operations
  
  try {
    final ns = NotificationService();
    final language = AppLocalizationScope.of(context).language;
    await ns.scheduleDynamicJapReminder(_today, language: language); // ❌ Blocks UI
  } catch (e) { ... }
}
```
**Fix:** Use unawaited for non-critical operations, batch operations, or use isolates:
```dart
Future<void> _incrementJap() async {
  // Critical: Update counter immediately
  await store.increment();
  
  // Non-critical: Fire and forget
  unawaited(_recordInsight(willBe));
  unawaited(_handleStreakIfNeeded(wasZero));
  unawaited(_scheduleNotification());
  
  // Update UI immediately
  setState(() {
    _today = store.todayJaps;
    _lifetime = store.lifetimeJaps;
  });
}

Future<void> _recordInsight(int willBe) async {
  try {
    final insights = await InsightStore.create();
    await insights.recordJap(count: 1, malas: willBe % 108 == 0 ? 1 : 0);
  } catch (e) {
    debugPrint('[Insights] Record failed: $e');
  }
}
```

---

### 4. **App.dart - PostFrameCallback with Async Operations**
**File:** `lib/app.dart:56-75`
**Issue:** PostFrameCallback performs async operations (CounterStore.create(), initializeDateFormatting) that delay the initial render and can cause hangs.
**Impact:** App startup is slower, initial render delayed, potential hangs.
**Code:**
```dart
WidgetsBinding.instance.addPostFrameCallback((_) async {
  final counter = await CounterStore.create(); // ❌ Blocks initial render
  final today = counter.todayJaps ~/ 108;
  await initializeDateFormatting(_language == 'hi' ? 'hi' : 'en'); // ❌ Blocks
  final msg = today > 0
      ? _translate('home.snackbar.progress', args: {'count': '$today'})
      : _translate('home.snackbar.start');
  if (mounted) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(...));
  }
});
```
**Fix:** Move to initState or use unawaited:
```dart
@override
void initState() {
  super.initState();
  // ... existing code ...
  unawaited(_showWelcomeSnackbar());
}

Future<void> _showWelcomeSnackbar() async {
  await Future.delayed(const Duration(milliseconds: 500)); // Small delay
  if (!mounted) return;
  final counter = await CounterStore.create();
  final today = counter.todayJaps ~/ 108;
  await initializeDateFormatting(_language == 'hi' ? 'hi' : 'en');
  if (!mounted) return;
  final msg = today > 0
      ? _translate('home.snackbar.progress', args: {'count': '$today'})
      : _translate('home.snackbar.start');
  final messenger = ScaffoldMessenger.maybeOf(context);
  messenger
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(...));
}
```

---

### 5. **Counter Store - Multiple SharedPreferences Calls in Increment**
**File:** `lib/data/counter_store.dart:38-66`
**Issue:** Each increment() call performs 3-4 separate SharedPreferences operations (read today, read lifetime, write today, write lifetime, XP store).
**Impact:** Multiple disk I/O operations per tap cause lag and poor performance.
**Code:**
```dart
Future<void> increment() async {
  await _resetIfNewDay(); // ❌ SharedPreferences read
  
  // ... lock logic ...
  
  // Read current values
  final currentToday = _prefs.getInt(_kTodayJaps) ?? 0; // ❌ Read 1
  final currentLifetime = _prefs.getInt(_kLifetimeJaps) ?? 0; // ❌ Read 2
  
  // Write both values atomically
  await _prefs.setInt(_kTodayJaps, currentToday + 1); // ❌ Write 1
  await _prefs.setInt(_kLifetimeJaps, currentLifetime + 1); // ❌ Write 2
  
  final xp = await XPStore.create(); // ❌ More SharedPreferences
  await xp.addXP(1); // ❌ More SharedPreferences
}
```
**Fix:** Batch operations or use in-memory cache with periodic sync:
```dart
// Add in-memory cache
int _cachedToday = 0;
int _cachedLifetime = 0;
bool _cacheDirty = false;
Timer? _syncTimer;

Future<void> increment() async {
  await _resetIfNewDay();
  
  // ... lock logic ...
  
  // Update in-memory cache immediately
  _cachedToday++;
  _cachedLifetime++;
  _cacheDirty = true;
  
  // Sync to disk asynchronously (debounced)
  _scheduleSync();
  
  // Update XP asynchronously
  unawaited(_updateXP());
}

void _scheduleSync() {
  _syncTimer?.cancel();
  _syncTimer = Timer(const Duration(milliseconds: 500), () async {
    if (_cacheDirty) {
      await _prefs.setInt(_kTodayJaps, _cachedToday);
      await _prefs.setInt(_kLifetimeJaps, _cachedLifetime);
      _cacheDirty = false;
    }
  });
}
```

---

## 🟡 HIGH PRIORITY PERFORMANCE BUGS

### 6. **Stats Page - ActivityStore.currentStreak() Called Multiple Times**
**File:** `lib/app.dart:434, 459, 558, 950`
**Issue:** `currentStreak()` is called in multiple places (init, refresh, FutureBuilder, share) even though it's cached. Each call still does some work.
**Impact:** Unnecessary async operations, potential race conditions.
**Fix:** Cache the result in State:
```dart
int? _cachedStreak;

Future<void> _refresh() async {
  // ... existing code ...
  final streak = await ActivityStore.currentStreak();
  _cachedStreak = streak; // Cache it
  if ([7, 21, 40].contains(streak)) {
    _confetti.play();
  }
}

// Use cached value in FutureBuilder
FutureBuilder<int>(
  future: _cachedStreak != null 
      ? Future.value(_cachedStreak!)
      : ActivityStore.currentStreak().then((s) {
          _cachedStreak = s;
          return s;
        }),
  builder: (context, snap) { ... }
)
```

---

### 7. **Missing const Constructors Throughout Codebase**
**File:** Multiple files
**Issue:** Many widgets don't use `const` constructors, causing unnecessary rebuilds when parent rebuilds.
**Impact:** Excessive widget rebuilds, poor performance.
**Examples:**
- `lib/app.dart:239-243` - Navigation icons not const
- `lib/counter/counter_page.dart:610-634` - _StatTile not const
- `lib/app.dart:1030-1079` - _NeoTile not const
**Fix:** Add const where possible:
```dart
// Before:
child: _navIcon(Icons.touch_app, 0, 'nav.counter'),

// After:
child: _navIcon(Icons.touch_app, 0, 'nav.counter'), // Make _navIcon return const widgets
```

---

### 8. **Stats Page - WeeklyChartData.build() Rebuilds on Every setState**
**File:** `lib/app.dart:747`
**Issue:** FutureBuilder for WeeklyChartData creates a new Future on every parent rebuild, causing expensive chart data recalculation.
**Impact:** Chart data recalculated unnecessarily, causing lag.
**Fix:** Cache the Future in State (see bug #1).

---

### 9. **Timer Page - Multiple setState Calls**
**File:** `lib/timer/timer_page.dart:83, 149, 157, 173, 185`
**Issue:** Multiple setState calls in quick succession cause multiple rebuilds.
**Impact:** Excessive rebuilds, UI lag.
**Fix:** Batch setState calls:
```dart
// Before:
setState(() => _visible = true);
setState(() => _todayMinutes = store.todayMinutes);
setState(() => _lifetimeMinutes = store.lifetimeMinutes);

// After:
setState(() {
  _visible = true;
  _todayMinutes = store.todayMinutes;
  _lifetimeMinutes = store.lifetimeMinutes;
});
```

---

### 10. **ActivityStore - Streak Calculation Loops 365 Days**
**File:** `lib/data/activity_store.dart:99-108`
**Issue:** Even with caching, the streak calculation loops up to 365 days on cache miss.
**Impact:** Expensive computation on first call or cache invalidation.
**Fix:** Optimize with early exit or binary search:
```dart
// Current: O(n) where n can be up to 365
for (int i = 0; i < 365; i++) {
  final d = DateTime(today.year, today.month, today.day).subtract(Duration(days: i));
  final key = _isoDate(d);
  if (active.contains(key)) {
    streak++;
  } else {
    break;
  }
}

// Optimized: Use Set lookup (already O(1)), but limit iterations
// Add early exit if we know max possible streak
int streak = 0;
final todayKey = _isoDate(today);
if (!active.contains(todayKey)) {
  return 0; // Early exit
}
for (int i = 0; i < 365; i++) {
  final d = DateTime(today.year, today.month, today.day).subtract(Duration(days: i));
  final key = _isoDate(d);
  if (active.contains(key)) {
    streak++;
  } else {
    break; // Already optimized
  }
}
```

---

## 🟢 MEDIUM PRIORITY PERFORMANCE BUGS

### 11. **Counter Page - AudioPlayer Created on Every Mala**
**File:** `lib/counter/counter_page.dart:94-98, 283-285`
**Issue:** New AudioPlayer instances are created for bell sounds instead of reusing a single instance.
**Impact:** Memory leaks, audio resource waste.
**Fix:** Reuse AudioPlayer instance (already has _bellPlayer, but creates new one in streak handler).

---

### 12. **Gita Service - No Cache Size Limit**
**File:** `lib/content/gita_service.dart:34`
**Issue:** In-memory cache grows unbounded, causing memory issues over time.
**Impact:** Memory leaks, app slowdown over time.
**Fix:** Add LRU cache with size limit:
```dart
static const int _maxCacheSize = 100;
static final Map<String, GitaVerse> _cache = {};
static final List<String> _cacheOrder = [];

static Future<GitaVerse?> fetchVerse(int chapter, int verse) async {
  final k = _key(chapter, verse);
  if (_cache.containsKey(k)) {
    // Move to end (LRU)
    _cacheOrder.remove(k);
    _cacheOrder.add(k);
    return _cache[k];
  }
  
  // ... fetch logic ...
  
  // Add to cache with size limit
  if (_cache.length >= _maxCacheSize) {
    final oldest = _cacheOrder.removeAt(0);
    _cache.remove(oldest);
  }
  _cache[k] = v;
  _cacheOrder.add(k);
  return v;
}
```

---

### 13. **Stats Page - DedicationStore.create() Called in FutureBuilder**
**File:** `lib/app.dart:869`
**Issue:** `DedicationStore.create()` is called in FutureBuilder, creating new instance on every rebuild.
**Impact:** Unnecessary SharedPreferences operations.
**Fix:** Cache the Future (see bug #1).

---

### 14. **Timer Service - DateTime.now() Called Multiple Times**
**File:** `lib/timer/timer_service.dart:39-44, 174-181`
**Issue:** `DateTime.now()` is called multiple times in getters and methods, causing unnecessary system calls.
**Impact:** Minor performance impact, but adds up with frequent calls.
**Fix:** Cache current time in ticker:
```dart
DateTime? _cachedNow;

Duration get elapsed {
  if (!_running || _startedAt == null) {
    return _accumulated;
  }
  final now = _cachedNow ?? DateTime.now();
  return _accumulated + now.difference(_startedAt!);
}

// In ticker:
_ticker = Timer.periodic(const Duration(seconds: 1), (_) {
  _cachedNow = DateTime.now(); // Cache once per tick
  if (!_running) return;
  // ... rest of logic
});
```

---

### 15. **App.dart - AnimatedSwitcher Rebuilds All Pages**
**File:** `lib/app.dart:186-214`
**Issue:** AnimatedSwitcher rebuilds all pages when index changes, even though only one is visible.
**Impact:** Unnecessary widget tree builds.
**Fix:** Use IndexedStack or keepAlive:
```dart
// Use IndexedStack instead of AnimatedSwitcher for better performance
child: IndexedStack(
  index: _index == 4 ? null : _index,
  children: [
    ..._pages,
    if (_index == 4)
      SettingsPage(...)
    else
      const SizedBox.shrink(),
  ],
)
```

---

## 🔵 LOW PRIORITY / OPTIMIZATION OPPORTUNITIES

### 16. **Missing RepaintBoundary Widgets**
**File:** Multiple files
**Issue:** Complex widgets (charts, calendars) don't use RepaintBoundary to isolate repaints.
**Impact:** Unnecessary repaints of parent widgets.
**Fix:** Wrap expensive widgets in RepaintBoundary:
```dart
RepaintBoundary(
  child: WeeklyChart(...),
)
```

---

### 17. **Stats Page - ListView Instead of CustomScrollView**
**File:** `lib/app.dart:545`
**Issue:** Using ListView with multiple FutureBuilders instead of optimized CustomScrollView.
**Impact:** Less efficient scrolling performance.
**Fix:** Use CustomScrollView with SliverList for better performance.

---

### 18. **Counter Page - Hardcoded Text Not Using const**
**File:** `lib/counter/counter_page.dart:501, 508, 515`
**Issue:** StatTile widgets have hardcoded English text, not using localization or const.
**Impact:** Minor, but causes unnecessary rebuilds.
**Fix:** Use localization and const.

---

### 19. **Activity Calendar - GridView Rebuilds All Cells**
**File:** `lib/app.dart:1212-1271`
**Issue:** GridView.builder rebuilds all cells when parent rebuilds, even with NeverScrollableScrollPhysics.
**Impact:** Unnecessary widget builds.
**Fix:** Use const constructors for cell widgets where possible.

---

### 20. **AdManager - Retry Timers Not Debounced**
**File:** `lib/core/ad_manager.dart:1107-1135`
**Issue:** Retry timers can accumulate if multiple failures occur quickly.
**Impact:** Multiple retry attempts, wasted resources.
**Fix:** Already has attempt counting, but could add exponential backoff.

---

## 📊 SUMMARY

**Total Performance Issues Found:** 20
- **Critical:** 5 🔴 (Causing hangs and major lag)
- **High Priority:** 5 🟡 (Causing noticeable lag)
- **Medium Priority:** 5 🟢 (Causing minor lag)
- **Low Priority:** 5 🔵 (Optimization opportunities)

## 🎯 RECOMMENDED FIX ORDER

1. **Immediate (Critical):**
   - Fix Stats Page FutureBuilders caching (#1)
   - Fix Timer Service notifyListeners frequency (#2)
   - Fix Counter Page async operations (#3)
   - Fix App.dart PostFrameCallback (#4)
   - Fix Counter Store SharedPreferences batching (#5)

2. **High Priority:**
   - Cache ActivityStore.currentStreak() (#6)
   - Add const constructors (#7)
   - Cache WeeklyChartData Future (#8)
   - Batch Timer Page setState calls (#9)
   - Optimize streak calculation (#10)

3. **Medium Priority:**
   - Fix AudioPlayer reuse (#11)
   - Add Gita cache limit (#12)
   - Cache DedicationStore Future (#13)
   - Cache DateTime.now() (#14)
   - Optimize AnimatedSwitcher (#15)

4. **Low Priority:**
   - Add RepaintBoundary widgets (#16)
   - Optimize ListView (#17)
   - Fix hardcoded text (#18)
   - Optimize GridView (#19)
   - Improve retry logic (#20)

---

## ✅ VERIFICATION CHECKLIST

After fixing bugs, verify:
- [ ] Stats page loads instantly without lag
- [ ] Timer updates smoothly without jank
- [ ] Counter taps are instant and responsive
- [ ] App startup is fast
- [ ] No memory leaks over time
- [ ] Smooth scrolling in all lists
- [ ] No excessive rebuilds (use Flutter DevTools)
- [ ] Battery usage is reasonable
- [ ] No UI freezes or hangs

---

**Report Generated:** Comprehensive performance analysis
**Files Reviewed:** All Dart files in lib/
**Focus:** Performance, responsiveness, and smoothness

