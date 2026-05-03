import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Single source of truth for admin-tunable values (prices, time windows,
/// XP rules, etc.). Read once at app start via the `get_venue_config` RPC,
/// cached for the session, refresh on pull-to-refresh or manual invalidate.
///
/// Returns the raw JSONB map so callers can pluck whatever field they need
/// without re-fetching. Strongly-typed accessors live alongside features
/// (e.g. SessionPrice.fromConfig(cfg)).
final venueConfigProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  // Hyderabad single-venue v1; replace with real venue_id resolution when
  // multi-venue arrives.
  const venueId = '00000000-0000-0000-0000-000000000001';
  final raw = await Supabase.instance.client.rpc<Map<String, dynamic>>(
    'get_venue_config',
    params: {'p_venue_id': venueId},
  );
  return Map<String, dynamic>.from(raw);
});
