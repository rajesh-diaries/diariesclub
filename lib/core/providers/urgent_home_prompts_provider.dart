import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'current_wallet_provider.dart';
import 'upcoming_birthdays_provider.dart';
import 'venue_config_provider.dart';

/// True if Home should show a *compact* timer (and let other prompts breathe)
/// during an active session. Decision tree:
///   - Birthday within 7 days → urgent
///   - Wallet balance below `low_balance_threshold_paise` → urgent
///   - (Healthy bite pending — wired in Session 6 once distribution flow lands)
///
/// When false, the active-session view gets the full dominant timer.
final hasUrgentHomePromptsProvider = Provider<bool>((ref) {
  if (ref.watch(birthdayWithinWeekProvider)) return true;
  if (ref.watch(lowWalletBalanceProvider)) return true;
  return false;
});

/// True iff the wallet balance has loaded and is below the venue's low-
/// balance threshold. Falsy while loading — we don't want to show "Top up"
/// before we've confirmed the balance is actually low.
final lowWalletBalanceProvider = Provider<bool>((ref) {
  final balance = ref.watch(walletBalancePaiseProvider);
  if (balance == null) return false;
  final cfg = ref.watch(venueConfigProvider).valueOrNull;
  final threshold = cfg?['low_balance_threshold_paise'] as int?;
  if (threshold == null) return false;
  return balance < threshold;
});
