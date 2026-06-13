import 'package:flutter/foundation.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tracks happy moments and throttles in-app review prompts.
///
/// A review request is considered when:
///   * the user has had at least [happySessionThreshold] successful sessions
///     within the last [sessionWindow], and
///   * at least [minPromptInterval] has passed since the last prompt.
class AppReviewHelper {
  AppReviewHelper._();

  static final InAppReview _inAppReview = InAppReview.instance;

  static const String _lastRequestedKey = 'app_review_last_requested_at';
  static const String _windowStartKey = 'app_review_session_window_start';
  static const String _sessionCountKey = 'app_review_session_count';

  /// How often the system review prompt may be shown.
  static const Duration minPromptInterval = Duration(days: 7);

  /// How long we look back when counting successful sessions.
  static const Duration sessionWindow = Duration(days: 7);

  /// How many successful sessions within [sessionWindow] count as a
  /// "happy moment" worthy of asking for a review.
  static const int happySessionThreshold = 2;

  /// Records a successful session and returns whether the user is in a
  /// happy-moment window right now.
  static Future<bool> recordSuccessfulSession() async {
    if (kIsWeb) return false;
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final nowMs = now.millisecondsSinceEpoch;

    final windowStartMs = prefs.getInt(_windowStartKey);
    final int count;
    if (windowStartMs == null ||
        nowMs - windowStartMs > sessionWindow.inMilliseconds) {
      await prefs.setInt(_windowStartKey, nowMs);
      count = 1;
    } else {
      count = (prefs.getInt(_sessionCountKey) ?? 0) + 1;
    }
    await prefs.setInt(_sessionCountKey, count);
    return count >= happySessionThreshold;
  }

  /// Requests a review if the platform supports it and enough time has
  /// passed since the last prompt. Callers should only invoke this when
  /// [recordSuccessfulSession] (or another happy-moment check) returns true.
  static Future<bool> maybeRequestAfterHappyMoment() async {
    if (kIsWeb) return false;

    final prefs = await SharedPreferences.getInstance();
    final lastRequestedMs = prefs.getInt(_lastRequestedKey);
    final now = DateTime.now();

    if (lastRequestedMs != null) {
      final lastRequested = DateTime.fromMillisecondsSinceEpoch(lastRequestedMs);
      if (now.difference(lastRequested) < minPromptInterval) {
        return false;
      }
    }

    try {
      final available = await _inAppReview.isAvailable();
      if (!available) return false;
      await _inAppReview.requestReview();
      await prefs.setInt(_lastRequestedKey, now.millisecondsSinceEpoch);
      return true;
    } catch (e) {
      // Silently fail — prompting for reviews should never break the flow.
      return false;
    }
  }

  /// Opens the store listing directly. Useful for a manual "Rate us" row.
  static Future<void> openStoreListing() async {
    if (kIsWeb) return;
    try {
      await _inAppReview.openStoreListing();
    } catch (_) {
      // Ignore.
    }
  }
}
