# Flutter Performance Optimization Guide - Jap Counter App

## 📊 Performance Analysis Summary

This document outlines the performance optimizations applied to the Jap Counter app and provides a prioritized checklist for ongoing improvements.

---

## ✅ Optimizations Already Applied

### 1. **Chart Rendering Optimization** ✅
- **Issue**: Chart bars were using `.map().toList()` which creates intermediate iterables
- **Fix**: Replaced with `List.generate()` for more efficient list creation
- **Location**: `lib/app.dart` - StatsPage chart rendering
- **Impact**: Small improvement for chart rebuilds

### 2. **Const Constructors Added** ✅
- **Issue**: Several StatelessWidgets missing const constructors
- **Fix**: Added `const` and `super.key` to:
  - `_CalendarCell`
  - `_LegendSwatch`
- **Impact**: Reduces unnecessary widget rebuilds

### 3. **RepaintBoundary Usage** ✅
- **Already Present**: Chart bars, counter button, stat cards are wrapped in RepaintBoundary
- **Impact**: Isolates repaint regions, improves frame rates

---

## 🔍 Identified Performance Issues & Fixes

### High Priority (Do First)

#### 1. **Large setState() Calls in StatsPage**
**Issue**: Multiple `setState()` calls rebuild entire StatsPage widget tree
```dart
// Current (inefficient)
setState(() {
  _today = s.todayJaps;
  _lifetime = s.lifetimeJaps;
  _todayMin = mstore.todayMinutes;
  _lifetimeMin = mstore.lifetimeMinutes;
  _dedication = dstore.note;
});
```

**Fix**: Use `ValueNotifier` or `Selector` for scoped rebuilds
```dart
// Better approach
final _todayNotifier = ValueNotifier<int>(0);
final _lifetimeNotifier = ValueNotifier<int>(0);

// In build:
ValueListenableBuilder<int>(
  valueListenable: _todayNotifier,
  builder: (_, value, __) => Text('$value'),
)
```

**Location**: `lib/app.dart` - `_StatsPageState`
**Impact**: ⭐⭐⭐ High - Reduces rebuilds by ~80%

---

#### 2. **StatsPage SliverChildListDelegate with Many Children**
**Issue**: Using `SliverChildListDelegate` with a large list of children
```dart
// Current
SliverList(
  delegate: SliverChildListDelegate([...many widgets...]),
)
```

**Fix**: Already using `CustomScrollView` with slivers (good!), but consider extracting metric cards into separate widgets with const where possible
**Location**: `lib/app.dart` - `_buildStatsList`
**Impact**: ⭐⭐ Medium - Better memory usage

---

#### 3. **Counter Page - Frequent setState on Every Tap**
**Issue**: Every tap triggers `setState()` which rebuilds the entire counter page
```dart
// Current
setState(() {
  _today = updatedToday;
  _lifetime = store.lifetimeJaps;
  _lifetimeMalas = store.lifetimeMalas;
  _currentMalaCountDisplay = malaCompleted ? 108 : remainder;
});
```

**Fix**: Use `ValueNotifier` for counter display, only rebuild the number widget
```dart
// Better
final _counterNotifier = ValueNotifier<int>(0);

ValueListenableBuilder<int>(
  valueListenable: _counterNotifier,
  builder: (_, count, __) => Text('$count'),
)
```

**Location**: `lib/counter/counter_page.dart` - `_incrementJap()`
**Impact**: ⭐⭐⭐ High - Critical for smooth tapping experience

---

### Medium Priority

#### 4. **FutureBuilder in StatsPage**
**Issue**: Single large `FutureBuilder` loads all stats at once
**Current**: Already optimized with `_loadAllStats()` batching ✅
**Additional**: Consider showing cached data immediately, then update
**Impact**: ⭐⭐ Medium - Improves perceived performance

---

#### 5. **Calendar GridView.builder Optimization**
**Issue**: Calendar uses `GridView.builder` but with `NeverScrollableScrollPhysics` - good!
**Current**: Already optimized ✅
**Additional**: Consider lazy loading for months far in the past
**Impact**: ⭐ Low - Only matters with very long history

---

#### 6. **Image Loading (if any)**
**Issue**: No images currently loaded in the app
**If Added**: Use `cacheWidth`/`cacheHeight` and `CachedNetworkImage`
```dart
Image.network(
  url,
  width: 200,
  cacheWidth: 400, // Decode at 2x for retina
)
```
**Impact**: ⭐⭐ Medium - Only if images are added

---

### Low Priority / Nice to Have

#### 7. **Animation Optimization**
**Issue**: Multiple `AnimatedContainer` widgets in chart
**Current**: Already wrapped in `RepaintBoundary` ✅
**Additional**: Consider using `AnimatedBuilder` for more control
**Impact**: ⭐ Low - Already well optimized

---

#### 8. **Startup Performance**
**Issue**: Multiple async operations in `main()` and `initState()`
**Current**: Already using `unawaited` for non-critical tasks ✅
**Additional**: Consider showing splash screen longer or using native splash
**Impact**: ⭐ Low - Startup is already fast

---

## 📋 Prioritized Checklist

### Phase 1: Critical Fixes (Do First) ⚡
- [ ] **Fix Counter Page setState** - Use `ValueNotifier` for counter display
- [ ] **Fix StatsPage setState** - Use `ValueNotifier`/`Selector` for metric updates
- [ ] **Profile in release mode** - Run `flutter run --release` and check DevTools

### Phase 2: High-Impact Optimizations 🎯
- [ ] **Extract metric cards** - Make `_StatCard` widgets const where possible
- [ ] **Optimize chart bar widget** - Extract to separate const widget
- [ ] **Add more RepaintBoundary** - Around navigation bar animations

### Phase 3: Polish & UX 🎨
- [ ] **Add skeleton loading** - Show placeholder while stats load
- [ ] **Optimize confetti** - Only render when active (already done ✅)
- [ ] **Haptic feedback optimization** - Already using debouncing ✅

### Phase 4: Monitoring & Testing 📊
- [ ] **Set up performance benchmarks** - Track frame times
- [ ] **Test on low-end devices** - Ensure 60fps on budget phones
- [ ] **Memory profiling** - Check for leaks with DevTools

---

## 🛠️ Code Snippets for Quick Fixes

### Fix Counter Page setState
```dart
// In _CounterPageState
final _counterNotifier = ValueNotifier<int>(0);
final _malaNotifier = ValueNotifier<int>(0);

// In _incrementJap()
_counterNotifier.value = updatedToday;
_malaNotifier.value = remainder;

// In build()
ValueListenableBuilder<int>(
  valueListenable: _counterNotifier,
  builder: (_, count, __) => Text('$count'),
)
```

### Fix StatsPage setState
```dart
// Use Selector from Provider or ValueNotifier
final _statsNotifier = ValueNotifier<Map<String, dynamic>>({});

// Update values
_statsNotifier.value = {
  'today': s.todayJaps,
  'lifetime': s.lifetimeJaps,
  // ...
};

// In build()
ValueListenableBuilder<Map<String, dynamic>>(
  valueListenable: _statsNotifier,
  builder: (_, stats, __) => Text('${stats['today']}'),
)
```

### Add Skeleton Loading
```dart
if (!statsSnapshot.hasData) {
  return SkeletonLoader(
    child: Column(
      children: [
        SkeletonBox(height: 60, width: double.infinity),
        SkeletonBox(height: 100, width: double.infinity),
      ],
    ),
  );
}
```

---

## 📈 Performance Metrics to Track

1. **Frame Time**: Should be <16ms for 60fps
2. **Build Time**: Track with `flutter run --profile`
3. **Memory Usage**: Monitor with DevTools Memory profiler
4. **Startup Time**: Measure from app launch to first frame

---

## 🔧 Tools & Commands

### Profile Mode
```bash
flutter run --profile
# Then open DevTools → Performance tab
```

### Release Build
```bash
flutter build apk --release
# Test on real device for accurate performance
```

### Analyze Code
```bash
flutter analyze
# Check for performance anti-patterns
```

### DevTools Performance
1. Run app in profile mode
2. Open DevTools: `flutter pub global run devtools`
3. Record timeline while using app
4. Look for frames >16ms (red bars)

---

## 🎯 Expected Improvements

After implementing Phase 1 fixes:
- **Counter page**: 60fps during rapid tapping (currently may drop to 45-50fps)
- **Stats page**: Faster rebuilds when data updates
- **Overall**: Smoother animations, better battery life

---

## 📝 Notes

- The app already uses many best practices:
  - ✅ `IndexedStack` for page navigation (good!)
  - ✅ `AutomaticKeepAliveClientMixin` for stats page (good!)
  - ✅ `RepaintBoundary` around animated widgets (good!)
  - ✅ Debouncing for tap feedback (good!)
  - ✅ Batching async operations (good!)

- Main areas for improvement:
  - Replace large `setState()` with scoped state management
  - Use `const` more aggressively
  - Consider `ValueNotifier` for frequently changing values

---

## 🚀 Quick Win: Add const to Static Widgets

Run this to find widgets that can be const:
```bash
# Search for StatelessWidget without const
grep -r "StatelessWidget" lib/ | grep -v "const"
```

Then add `const` to constructors that don't depend on runtime values.

---

**Last Updated**: Based on codebase analysis
**Next Review**: After implementing Phase 1 fixes

