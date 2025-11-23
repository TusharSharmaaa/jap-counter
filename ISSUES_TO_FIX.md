# Issues Found in Jap Counter App

This document lists all issues found during code review that can be fixed.

## 🔴 Critical Issues

### 1. Memory Leak: StatsAmbience AudioPlayer Not Disposed
**Location:** `lib/stats/stats_ambience.dart`
**Issue:** The `AudioPlayer` instance is never disposed, causing memory leaks.
**Fix:** Add a `dispose()` method and call it when the app is disposed.

### 2. Missing Error Handling in Async Operations
**Location:** Multiple files
**Issue:** Many `unawaited()` calls don't have error handling, which can cause silent failures.
**Examples:**
- `lib/app.dart:62` - `unawaited(_showWelcomeSnackbar())`
- `lib/app.dart:68` - `unawaited(SyncService.syncToday())`
- `lib/counter/counter_page.dart:251` - `unawaited(_recordInsight(willBe))`

**Fix:** Wrap unawaited futures in try-catch or use `.catchError()`.

### 3. Timer Not Cancelled in ActivityStore
**Location:** `lib/data/activity_store.dart:179`
**Issue:** `_batchWriteTimer` is created but may not be cancelled if the app closes, causing potential memory leaks.
**Fix:** Add cleanup method to cancel timer and call it on app lifecycle events.

### 4. Missing Null Check in TimerService
**Location:** `lib/timer/timer_service.dart:214-220`
**Issue:** Timer callback doesn't check if service is still valid before accessing properties.
**Fix:** Add null checks and mounted checks.

### 5. AdManager Timers Not Cleaned Up on App Dispose
**Location:** `lib/core/ad_manager.dart`
**Issue:** Retry timers (`_rewardedRetryTimers`, `_interstitialRetryTimers`) and `_preloadTimer` may not be cancelled when app closes.
**Fix:** Ensure `dispose()` is called on app disposal (already exists but verify it's called).

## 🟡 High Priority Issues

### 6. Potential Race Condition in CounterStore
**Location:** `lib/data/counter_store.dart:15`
**Issue:** `_currentIncrement` static variable could cause race conditions if multiple instances try to increment simultaneously.
**Fix:** Use proper locking mechanism or ensure single instance pattern is enforced.

### 7. Missing Context Check Before Navigation
**Location:** `lib/app.dart:163`
**Issue:** `Navigator.of(context).pushReplacement` called without checking if context is mounted.
**Fix:** Add `if (!mounted) return;` check before navigation.

### 8. Incomplete Error Handling in SoundManager
**Location:** `lib/core/sound_manager.dart:110-134`
**Issue:** `_syncAmbience` method has incomplete try-catch (missing opening brace in some code paths).
**Fix:** Ensure all async operations have proper error handling.

### 9. StatsAmbience dispose() Not Called
**Location:** `lib/stats/stats_ambience.dart`
**Issue:** The `dispose()` method exists but is never called from app lifecycle.
**Fix:** Call `StatsAmbience.instance.dispose()` in app dispose (already done in app.dart:321, but verify).

### 10. Potential Memory Leak: ConfettiController
**Location:** `lib/counter/counter_page.dart:58`
**Issue:** ConfettiController is disposed, but ensure it's always disposed even if errors occur.
**Fix:** Use try-finally in dispose method.

### 11. Missing Validation in Goal Store
**Location:** `lib/counter/counter_page.dart:621`
**Issue:** Goal value is clamped but not validated for negative values before clamping.
**Fix:** Add validation before clamping.

### 12. Timer Service Display Notifier Not Checked
**Location:** `lib/timer/timer_service.dart:244`
**Issue:** `displayNotifier.value` is set without checking if notifier is disposed.
**Fix:** Add check before setting value.

## 🟢 Medium Priority Issues

### 13. Duplicate Code in Translation Helpers
**Location:** Multiple files
**Issue:** `safeTr()` helper function is duplicated in multiple places (app.dart, counter_page.dart).
**Fix:** Extract to a utility class or extension.

### 14. Hardcoded Strings
**Location:** Multiple files
**Issue:** Some strings are hardcoded instead of using localization.
**Examples:**
- `lib/app.dart:183` - 'Starting...'
- Various error messages

**Fix:** Move all strings to localization files.

### 15. Missing Input Validation
**Location:** `lib/counter/counter_page.dart:621`
**Issue:** Goal dialog doesn't validate input before saving.
**Fix:** Add validation for edge cases (e.g., very large numbers).

### 16. Inefficient Chart Cache Invalidation
**Location:** `lib/counter/counter_page.dart:299`
**Issue:** Chart cache is invalidated on every tap, which may be excessive.
**Fix:** Debounce cache invalidation or only invalidate when necessary.

### 17. Missing Error Recovery in Notification Service
**Location:** `lib/notifications/notification_service.dart`
**Issue:** If notification initialization fails, there's no retry mechanism.
**Fix:** Add retry logic with exponential backoff.

### 18. Unused Import
**Location:** `lib/debug/ad_health.dart:1`
**Issue:** `import 'package:flutter/foundation.dart';` may not be needed if only using `debugPrint`.
**Fix:** Remove if unused (verify with analyzer).

### 19. Missing Documentation
**Location:** Multiple files
**Issue:** Some complex methods lack documentation.
**Fix:** Add dartdoc comments for public APIs and complex logic.

### 20. Inconsistent Error Logging
**Location:** Multiple files
**Issue:** Some errors are logged with `debugPrint`, others are silently caught.
**Fix:** Use consistent error logging strategy (consider using a logging package).

## 🔵 Low Priority / Code Quality

### 21. Magic Numbers
**Location:** Multiple files
**Issue:** Magic numbers used without constants (e.g., 108, 365, 2 seconds).
**Examples:**
- `lib/counter/counter_page.dart:108` - Mala count
- `lib/data/activity_store.dart:112` - Streak limit
- `lib/data/activity_store.dart:179` - Batch timer duration

**Fix:** Extract to named constants.

### 22. Long Methods
**Location:** Multiple files
**Issue:** Some methods are too long and do multiple things.
**Examples:**
- `lib/app.dart:_buildStatsList()` - Very long method
- `lib/counter/counter_page.dart:build()` - Long build method

**Fix:** Break down into smaller, focused methods.

### 23. Inconsistent Naming
**Location:** Multiple files
**Issue:** Some variables use different naming conventions.
**Fix:** Follow consistent Dart naming conventions.

### 24. Missing Type Annotations
**Location:** Some files
**Issue:** Some variables could benefit from explicit type annotations for clarity.
**Fix:** Add type annotations where it improves readability.

### 25. Duplicate Date Formatting Logic
**Location:** Multiple files
**Issue:** Date formatting logic (`_yyyymmdd`, `_isoDate`) is duplicated.
**Fix:** Extract to a shared utility class.

### 26. Missing Tests
**Location:** Entire codebase
**Issue:** No unit tests found for critical business logic.
**Fix:** Add unit tests for stores, services, and critical calculations.

### 27. Potential Performance Issue: Future.wait Without Error Handling
**Location:** `lib/app.dart:592`
**Issue:** `Future.wait()` doesn't handle individual failures gracefully.
**Fix:** Use `Future.wait()` with `eagerError: false` or handle errors individually.

### 28. Missing Accessibility Labels
**Location:** UI widgets
**Issue:** Some interactive elements lack semantic labels for accessibility.
**Fix:** Add `Semantics` widgets or `tooltip` properties.

### 29. Inconsistent State Management
**Location:** Multiple files
**Issue:** Mix of `setState`, `ValueNotifier`, and `ChangeNotifier` without clear pattern.
**Fix:** Document and standardize state management approach.

### 30. Missing Input Sanitization
**Location:** `lib/stats/stats_ambience.dart` and other user input areas
**Issue:** User inputs (like dedication notes) may not be sanitized.
**Fix:** Add input sanitization for user-generated content.

## 🐛 Potential Bugs

### 31. Goal Completion Logic Edge Case
**Location:** `lib/counter/counter_page.dart:333-352`
**Issue:** Goal completion check may fire multiple times if called rapidly.
**Fix:** Add debouncing or flag to prevent duplicate dialogs.

### 32. Streak Calculation May Be Incorrect
**Location:** `lib/data/activity_store.dart:112`
**Issue:** Streak calculation limits to 365 days, but doesn't account for leap years properly.
**Fix:** Use proper date arithmetic.

### 33. Timer State May Be Lost
**Location:** `lib/timer/timer_service.dart:101-139`
**Issue:** Complex timer restoration logic may fail in edge cases (timezone changes, etc.).
**Fix:** Add more robust state validation and recovery.

### 34. Chart Data May Show Stale Data
**Location:** `lib/utils/weekly_chart_data.dart`
**Issue:** Cache invalidation may not always work correctly.
**Fix:** Verify cache invalidation logic and add tests.

### 35. Ad Preloading May Continue After App Close
**Location:** `lib/core/ad_manager.dart:475`
**Issue:** Preload timer may continue running after app is disposed.
**Fix:** Ensure all timers are cancelled in dispose() (verify implementation).

## 📝 Code Organization

### 36. Large File Sizes
**Location:** `lib/app.dart` (2055 lines), `lib/counter/counter_page.dart` (1353 lines)
**Issue:** Files are too large and hard to maintain.
**Fix:** Split into smaller, focused files.

### 37. Missing Separation of Concerns
**Location:** Multiple files
**Issue:** Business logic mixed with UI code in some places.
**Fix:** Extract business logic to separate service classes.

### 38. Inconsistent File Structure
**Location:** Project structure
**Issue:** Some related functionality is scattered across different directories.
**Fix:** Reorganize to follow feature-based structure.

## 🔒 Security & Privacy

### 39. No Input Validation on User Data
**Location:** Dedication store, goal store
**Issue:** User inputs may not be validated for length, content, etc.
**Fix:** Add input validation and sanitization.

### 40. Potential Data Loss on App Crash
**Location:** Batching mechanisms
**Issue:** Batched writes may be lost if app crashes before flush.
**Fix:** Consider more frequent persistence or use transactions.

## Summary

**Total Issues Found:** 40
- **Critical:** 5
- **High Priority:** 7
- **Medium Priority:** 10
- **Low Priority:** 10
- **Potential Bugs:** 5
- **Code Organization:** 3

**Recommended Fix Order:**
1. Fix all Critical issues first
2. Address High Priority issues
3. Fix Potential Bugs
4. Work through Medium and Low Priority issues
5. Refactor for Code Organization

---

*Generated by code review on $(date)*

