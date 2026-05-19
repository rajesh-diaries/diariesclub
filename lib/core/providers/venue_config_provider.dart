import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/venues.dart';

/// Single source of truth for admin-tunable values (prices, time windows,
/// XP rules, etc.). Read once at app start via the `get_venue_config` RPC,
/// cached for the session, refresh on pull-to-refresh or manual invalidate.
///
/// Returns the raw JSONB map so callers can pluck whatever field they need
/// without re-fetching. Strongly-typed accessors live alongside features
/// (e.g. SessionPrice.fromConfig(cfg)).
final venueConfigProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  // Single-venue v1; centralised in core/utils/venues.dart so the
  // multi-venue swap is one find-and-replace.
  const venueId = Venues.kondapurId;
  // 10s timeout: venue_config is read at splash and on most home views.
  // If it hangs the whole UI hangs. AsyncError surfaces to the caller's
  // .when(error: ...) so user gets a retry-able state, not infinite spin.
  final raw = await Supabase.instance.client.rpc<Map<String, dynamic>>(
    'get_venue_config',
    params: {'p_venue_id': venueId},
  ).timeout(const Duration(seconds: 10));
  return Map<String, dynamic>.from(raw);
});
