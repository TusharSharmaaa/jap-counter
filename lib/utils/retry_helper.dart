import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

/// Helper class for retrying failed operations with exponential backoff
class RetryHelper {
  /// Retry an operation with exponential backoff
  /// 
  /// [operation] - The async operation to retry
  /// [maxRetries] - Maximum number of retry attempts (default: 3)
  /// [initialDelay] - Initial delay before first retry (default: 100ms)
  /// [maxDelay] - Maximum delay between retries (default: 2 seconds)
  /// [onRetry] - Optional callback called before each retry
  static Future<T> retry<T>({
    required Future<T> Function() operation,
    int maxRetries = 3,
    Duration initialDelay = const Duration(milliseconds: 100),
    Duration maxDelay = const Duration(seconds: 2),
    void Function(int attempt, Object error)? onRetry,
  }) async {
    int attempt = 0;
    
    while (true) {
      try {
        return await operation();
      } catch (error, stackTrace) {
        attempt++;
        
        if (attempt > maxRetries) {
          if (kDebugMode) {
            debugPrint('[RetryHelper] Max retries ($maxRetries) exceeded. Error: $error');
          }
          rethrow;
        }
        
        // Call onRetry callback if provided
        onRetry?.call(attempt, error);
        
        // Calculate exponential backoff delay
        final delayMs = min(
          initialDelay.inMilliseconds * pow(2, attempt - 1).toInt(),
          maxDelay.inMilliseconds,
        );
        
        if (kDebugMode) {
          debugPrint('[RetryHelper] Retry attempt $attempt/$maxRetries after ${delayMs}ms. Error: $error');
        }
        
        // Wait before retrying
        await Future.delayed(Duration(milliseconds: delayMs));
      }
    }
  }
  
  /// Retry an operation that returns void
  static Future<void> retryVoid({
    required Future<void> Function() operation,
    int maxRetries = 3,
    Duration initialDelay = const Duration(milliseconds: 100),
    Duration maxDelay = const Duration(seconds: 2),
    void Function(int attempt, Object error)? onRetry,
  }) async {
    await retry<void>(
      operation: operation,
      maxRetries: maxRetries,
      initialDelay: initialDelay,
      maxDelay: maxDelay,
      onRetry: onRetry,
    );
  }
}

