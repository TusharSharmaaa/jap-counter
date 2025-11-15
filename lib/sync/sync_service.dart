import 'dart:async' show TimeoutException;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../data/insight_store.dart';

class SyncService {
  // Rate limiting: Only sync once per minute max
  static DateTime? _lastSyncTime;
  static const _minSyncInterval = Duration(minutes: 1);
  
  // Connection state cache
  static ConnectivityResult? _lastConnectivityResult;
  static DateTime? _lastConnectivityCheck;
  static const _connectivityCacheDuration = Duration(seconds: 30);

  /// Sync today's data to Firebase with comprehensive error handling and rate limiting.
  /// Designed to handle millions of users without blocking or causing glitches.
  static Future<void> syncToday() async {
    // Rate limiting: Prevent excessive sync calls
    final now = DateTime.now();
    if (_lastSyncTime != null && 
        now.difference(_lastSyncTime!) < _minSyncInterval) {
      if (kDebugMode) {
        debugPrint('[SyncService] Rate limited - skipping sync');
      }
      return;
    }

    try {
      // Check connectivity before attempting sync
      final hasConnection = await _checkConnectivity();
      if (!hasConnection) {
        if (kDebugMode) {
          debugPrint('[SyncService] No connectivity - skipping sync');
        }
        return;
      }

      // Check if Firebase is already initialized
      try {
        Firebase.app(); // This will throw if not initialized
      } catch (_) {
        // Firebase not initialized, initialize it
        try {
          await Firebase.initializeApp()
              .timeout(const Duration(seconds: 5));
        } catch (e) {
          if (kDebugMode) {
            debugPrint('[SyncService] Firebase init failed: $e');
          }
          return;
        }
      }

      final db = FirebaseFirestore.instance;
      final insights = await InsightStore.create();
      final today = DateTime.now().toIso8601String().substring(0, 10);

      // Use timeout to prevent hanging operations
      await db.collection('insights').doc(today).set(
        {
          'date': today,
          'japs': insights.getTodayJaps(),
          'malas': insights.getTodayMalas(),
          'updatedAt': DateTime.now(),
        },
        SetOptions(merge: true),
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          if (kDebugMode) {
            debugPrint('[SyncService] Sync timeout after 10s');
          }
          throw TimeoutException('Firestore sync timeout');
        },
      );

      _lastSyncTime = now;
      if (kDebugMode) {
        debugPrint('[SyncService] Successfully synced today\'s data');
      }
    } on TimeoutException {
      // Timeout is expected in poor network conditions - fail silently
      if (kDebugMode) {
        debugPrint('[SyncService] Sync timeout - will retry later');
      }
    } on FirebaseException catch (e) {
      // Handle Firebase-specific errors gracefully
      if (kDebugMode) {
        debugPrint('[SyncService] Firebase error: ${e.code} - ${e.message}');
      }
      // Don't throw - allow app to continue functioning offline
    } catch (e, stackTrace) {
      // Catch-all for any unexpected errors
      if (kDebugMode) {
        debugPrint('[SyncService] Unexpected error: $e\n$stackTrace');
      }
      // Fail silently to prevent app crashes
    }
  }

  /// Check connectivity with caching to reduce overhead.
  static Future<bool> _checkConnectivity() async {
    final now = DateTime.now();
    
    // Use cached result if recent
    if (_lastConnectivityResult != null && 
        _lastConnectivityCheck != null &&
        now.difference(_lastConnectivityCheck!) < _connectivityCacheDuration) {
      return _lastConnectivityResult != ConnectivityResult.none;
    }

    try {
      final connectivity = Connectivity();
      final result = await connectivity.checkConnectivity()
          .timeout(const Duration(seconds: 3));
      
      _lastConnectivityResult = result.firstOrNull ?? ConnectivityResult.none;
      _lastConnectivityCheck = now;
      
      return _lastConnectivityResult != ConnectivityResult.none;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[SyncService] Connectivity check failed: $e');
      }
      // Assume connected if check fails (optimistic approach)
      return true;
    }
  }
}

