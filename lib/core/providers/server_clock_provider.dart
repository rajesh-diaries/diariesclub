import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Server-clock offset. Pulled via the `server_now` RPC at app start
/// and at most every 5 minutes thereafter. The session timer reads
/// `serverNow` instead of `DateTime.now()` so a tampered device clock
/// can't extend a session.
class ServerClockNotifier extends StateNotifier<Duration> {
  ServerClockNotifier() : super(Duration.zero);

  DateTime _lastSync = DateTime.fromMillisecondsSinceEpoch(0);

  Future<void> sync({bool force = false}) async {
    if (!force &&
        DateTime.now().difference(_lastSync) < const Duration(minutes: 5)) {
      return;
    }
    try {
      final t0 = DateTime.now().toUtc();
      final response = await Supabase.instance.client
          .rpc<Map<String, dynamic>>('server_now');
      final t1 = DateTime.now().toUtc();
      final serverTime = DateTime.parse(response['now']! as String).toUtc();
      final rtt = t1.difference(t0);
      final approximatedDispatch = t0.add(rtt ~/ 2);
      state = serverTime.difference(approximatedDispatch);
      _lastSync = DateTime.now();
    } catch (e) {
      debugPrint('server_now sync failed (will retry): $e');
    }
  }

  /// Best-known UTC server time. Pre-sync, falls back to device UTC.
  DateTime get serverNow => DateTime.now().toUtc().add(state);
}

final serverClockProvider =
    StateNotifierProvider<ServerClockNotifier, Duration>((ref) {
  return ServerClockNotifier();
});
