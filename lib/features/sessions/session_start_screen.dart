import 'dart:developer' as dev;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../core/providers/active_sessions_provider.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/providers/current_wallet_provider.dart';
import '../../core/providers/play_passes_provider.dart';
import '../../core/providers/venue_config_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/currency.dart';
import '../../core/utils/haptics.dart';
import '../../core/utils/venues.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/error_screen.dart';
import '../../core/widgets/hero_avatar.dart';
import '../../core/widgets/skeleton_card.dart';
import '../../core/widgets/primary_button.dart';
import '../../core/widgets/selection_card.dart';
import 'widgets/insufficient_balance_sheet.dart';

const _venueId = Venues.kondapurId;

/// Step 1 of the session lifecycle: pick child (if multi), pick duration
/// (1hr / 2hr — prices from venue_config), pick payment method, then call
/// `session_create`. On success → /session/qr/:id.
class SessionStartScreen extends ConsumerStatefulWidget {
  const SessionStartScreen({super.key});

  @override
  ConsumerState<SessionStartScreen> createState() => _SessionStartScreenState();
}

class _SessionStartScreenState extends ConsumerState<SessionStartScreen> {
  // Multi-select: one pass per checked child, all same duration. The
  // running total = selected.length × pricePerKid.
  final Set<String> _selectedChildIds = <String>{};
  int? _selectedDurationMinutes;
  String _paymentMethod = 'wallet';
  bool _busy = false;
  String? _errorText;

  // Coupon state — applied at session_create time.
  final _couponCtrl = TextEditingController();
  bool _validatingCoupon = false;
  int? _couponDiscountPaise; // null = no coupon applied
  String? _appliedCouponCode; // display name (e.g. "Buddy Discount")
  String? _couponBackendCode; // actual code sent to RPC (e.g. "2KIDS")
  String? _couponError;

  // First-session welcome treatment (mutually exclusive):
  //   {'type':'discount','code':'WELCOME100', ...}  → auto-apply ₹100 off
  //   {'type':'referral','credit_paise':...}         → "friend gifted you ₹100"
  //   {'type':'none'} / null                         → nothing
  // Resolved server-side by welcome_offer_for_session.
  Map<String, dynamic>? _welcomeOffer;
  bool _welcomeAutoApplyDone = false;

  late Future<List<Map<String, dynamic>>> _childrenFuture;

  @override
  void initState() {
    super.initState();
    _childrenFuture = _loadChildren();
    _loadWelcomeOffer();
  }

  /// Ask the backend which first-session welcome treatment this family gets.
  Future<void> _loadWelcomeOffer() async {
    final familyId = ref.read(currentFamilyIdProvider);
    if (familyId == null) return;
    try {
      final res = await Supabase.instance.client.rpc<Map<String, dynamic>>(
        'welcome_offer_for_session',
        params: {'p_family_id': familyId, 'p_venue_id': _venueId},
      );
      if (!mounted) return;
      setState(() => _welcomeOffer = res);
      // If a duration is already chosen, apply straight away.
      _maybeAutoApplyWelcome();
    } catch (e) {
      debugPrint('[WELCOME_OFFER] error: $e');
    }
  }

  /// Auto-applies WELCOME100 once, for a non-referred first-timer, as soon as a
  /// duration is picked and no other coupon is in play. Runs at most once so a
  /// cleared or overridden (e.g. sibling) coupon is never silently re-added.
  Future<void> _maybeAutoApplyWelcome() async {
    if (_welcomeAutoApplyDone) return;
    if (_welcomeOffer?['type'] != 'discount') return;
    if (_couponBackendCode != null) return;
    if (_selectedDurationMinutes == null) return;

    _welcomeAutoApplyDone = true;
    final code = (_welcomeOffer?['code'] as String?) ?? 'WELCOME100';
    final cfg = ref.read(venueConfigProvider).valueOrNull;
    final amount = _priceFor(_selectedDurationMinutes, cfg);
    try {
      final res = await Supabase.instance.client.rpc<Map<String, dynamic>>(
        'coupon_validate',
        params: {
          'p_code': code,
          'p_amount_paise': amount,
          'p_kid_count': _selectedChildIds.length,
        },
      );
      if (!mounted) return;
      if (res['valid'] == true && _couponBackendCode == null) {
        final returnedCode = (res['code'] as String?) ?? code;
        setState(() {
          _couponDiscountPaise = res['discount_paise'] as int? ?? 0;
          _appliedCouponCode = returnedCode;
          _couponBackendCode = returnedCode;
          _couponError = null;
        });
      }
    } catch (e) {
      debugPrint('[WELCOME_OFFER] auto-apply error: $e');
    }
  }

  Future<List<Map<String, dynamic>>> _loadChildren() async {
    final familyId = ref.read(currentFamilyIdProvider);
    if (familyId == null) return const [];
    final rows = await Supabase.instance.client
        .from('children')
        .select()
        .eq('family_id', familyId)
        .order('created_at', ascending: true);
    return (rows as List)
        .map((r) => Map<String, dynamic>.from(r as Map))
        .toList();
  }

  @override
  void dispose() {
    _couponCtrl.dispose();
    super.dispose();
  }

  int _priceFor(int? duration, Map<String, dynamic>? cfg) {
    if (duration == null) return 0;
    // Prices from venue_config; standard 1hr ₹800 / 2hr ₹1100 as fallback
    // when the key is missing or unparseable.
    final price1hr =
        (cfg?['session_1hr_price_paise'] as num?)?.toInt() ?? 80000;
    final price2hr =
        (cfg?['session_2hr_price_paise'] as num?)?.toInt() ?? 110000;
    return duration <= 60 ? price1hr : price2hr;
  }

  // Fallback map used when the admin has not configured sibling_coupon_codes
  // in venue_config (or while the config row is still loading).
  static const _fallbackSiblingCodes = {
    '2': 'ZENA',
    '3': 'RAFI',
    '4': 'GERRY',
    '5': 'WILDPACK',
  };

  static const _fallbackSiblingDiscounts = {
    'ZENA': 15000,
    'RAFI': 25000,
    'GERRY': 40000,
    'WILDPACK': 50000,
  };

  /// Sibling coupon metadata for the selected kid count.
  /// Reads the admin-configured `sibling_coupon_codes` map from venue_config,
  /// falling back to the standard 2KIDS/3KIDS/4KIDS/5KIDS codes.
  /// Returns null for single kid or when no mapping exists.
  Map<String, dynamic>? _siblingCouponFor(
    int kidCount,
    Map<String, dynamic>? cfg,
  ) {
    final configMap =
        (cfg?['sibling_coupon_codes'] as Map<String, dynamic>?) ?? {};
    final code =
        (configMap[kidCount.toString()] ??
                _fallbackSiblingCodes[kidCount.toString()])
            as String?;
    if (code == null) return null;
    return {
      'code': code,
      'discount_paise': _fallbackSiblingDiscounts[code] ?? 0,
    };
  }

  Future<void> _applySiblingCoupon() async {
    final cfg = ref.read(venueConfigProvider).valueOrNull;
    final coupon = _siblingCouponFor(_selectedChildIds.length, cfg);
    if (coupon == null) return;
    if (_selectedDurationMinutes == null) {
      setState(() => _couponError = 'Pick a duration first.');
      return;
    }
    final code = coupon['code'] as String;
    // Validate server-side the same way manual codes are (coupon_validate),
    // so the displayed discount matches what the backend actually deducts.
    // Fall back to the configured/hardcoded amount only if validation is
    // unavailable — session_create re-checks server-side regardless.
    final amount = _priceFor(_selectedDurationMinutes, cfg);
    setState(() {
      _validatingCoupon = true;
      _couponError = null;
    });
    try {
      final res = await Supabase.instance.client.rpc<Map<String, dynamic>>(
        'coupon_validate',
        params: {
          'p_code': code,
          'p_amount_paise': amount,
          'p_kid_count': _selectedChildIds.length,
        },
      );
      if (!mounted) return;
      if (res['valid'] == true) {
        final returnedCode = (res['code'] as String?) ?? code;
        AppHaptics.success();
        setState(() {
          _validatingCoupon = false;
          _couponDiscountPaise = res['discount_paise'] as int? ?? 0;
          _appliedCouponCode = returnedCode;
          _couponBackendCode = returnedCode;
          _couponError = null;
        });
      } else {
        AppHaptics.error();
        setState(() {
          _validatingCoupon = false;
          _couponDiscountPaise = null;
          _appliedCouponCode = null;
          _couponBackendCode = null;
          _couponError = (res['message'] as String?) ?? 'Invalid coupon.';
        });
      }
    } catch (e) {
      // Validation unavailable — fall back to the configured/hardcoded
      // amount so the chip still works offline.
      if (!mounted) return;
      AppHaptics.success();
      setState(() {
        _validatingCoupon = false;
        _couponDiscountPaise = coupon['discount_paise'] as int;
        _appliedCouponCode = code;
        _couponBackendCode = code;
        _couponError = null;
      });
      debugPrint('[SIBLING_COUPON_VALIDATE] error: $e');
    }
  }

  Future<void> _applyCoupon() async {
    final code = _couponCtrl.text.trim();
    if (code.isEmpty) {
      setState(() => _couponError = 'Enter a code.');
      return;
    }
    if (_selectedDurationMinutes == null) {
      setState(() => _couponError = 'Pick a duration first.');
      return;
    }
    final cfg = ref.read(venueConfigProvider).valueOrNull;
    final amount = _priceFor(_selectedDurationMinutes, cfg);
    setState(() {
      _validatingCoupon = true;
      _couponError = null;
    });
    try {
      final res = await Supabase.instance.client.rpc<Map<String, dynamic>>(
        'coupon_validate',
        params: {
          'p_code': code,
          'p_amount_paise': amount,
          'p_kid_count': _selectedChildIds.length,
        },
      );
      if (!mounted) return;
      if (res['valid'] == true) {
        final returnedCode = (res['code'] as String?) ?? code.toUpperCase();
        AppHaptics.success();
        setState(() {
          _validatingCoupon = false;
          _couponDiscountPaise = res['discount_paise'] as int? ?? 0;
          _appliedCouponCode = returnedCode;
          _couponBackendCode = returnedCode;
        });
      } else {
        AppHaptics.error();
        setState(() {
          _validatingCoupon = false;
          _couponDiscountPaise = null;
          _appliedCouponCode = null;
          _couponError = (res['message'] as String?) ?? 'Invalid coupon.';
        });
      }
    } catch (e) {
      if (!mounted) return;
      AppHaptics.error();
      setState(() {
        _validatingCoupon = false;
        _couponDiscountPaise = null;
        _appliedCouponCode = null;
        _couponError = 'Could not check coupon. Try again.';
      });
      debugPrint('[COUPON_VALIDATE] error: $e');
    }
  }

  void _clearCoupon() {
    setState(() {
      _couponDiscountPaise = null;
      _appliedCouponCode = null;
      _couponBackendCode = null;
      _couponError = null;
      _couponCtrl.clear();
    });
  }

  Future<void> _start() async {
    if (_busy) return;
    if (_selectedDurationMinutes == null || _selectedChildIds.isEmpty) return;
    final cfg = ref.read(venueConfigProvider).valueOrNull;
    final perKidPrice = _priceFor(_selectedDurationMinutes, cfg);
    final coupon = _couponDiscountPaise ?? 0;
    // Coupon applies to the first session only (per-family redemption).
    // The remaining N-1 sessions pay full price.
    final totalAmount = (perKidPrice * _selectedChildIds.length) - coupon;

    setState(() {
      _busy = true;
      _errorText = null;
    });
    final familyId = ref.read(currentFamilyIdProvider);
    if (familyId == null) {
      setState(() => _busy = false);
      return;
    }

    // Pre-check wallet balance (or passes) so we don't half-create the
    // batch and leave orphaned holds / consumed passes.
    if (_paymentMethod == 'wallet') {
      final balance = ref.read(walletBalancePaiseProvider) ?? 0;
      if (balance < totalAmount) {
        if (!mounted) return;
        setState(() => _busy = false);
        showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          useRootNavigator: true,
          builder: (_) => InsufficientBalanceSheet(
            requiredPaise: totalAmount,
            onSwitchToCash: () {
              if (!mounted) return;
              setState(() => _paymentMethod = 'cash');
            },
          ),
        );
        return;
      }
    } else if (_paymentMethod == 'play_pass') {
      final passes = ref.read(remainingPassesCountProvider);
      if (passes < _selectedChildIds.length) {
        if (!mounted) return;
        AppHaptics.error();
        setState(() {
          _busy = false;
          _errorText = 'Not enough Play Passes for all selected kids.';
        });
        return;
      }
    }

    final children = _selectedChildIds.toList();
    // One batch id shared by every session in this group. The backend uses it
    // to revoke a group coupon (e.g. 2KIDS) if any sibling session is later
    // cancelled, so the discount can't be kept on a single leftover session.
    final batchId = const Uuid().v4();
    final sessionIds = <String>[];
    // Track successes so a mid-batch failure can surface a "N of M
    // started" message instead of silently leaving the user wondering
    // which kids made it through.
    final createdCount = <int>[0];
    try {
      for (var i = 0; i < children.length; i++) {
        final childId = children[i];
        final idem = const Uuid().v4();
        // Coupon attaches to first session only; remaining run full price.
        final couponForCall = (i == 0) ? _couponBackendCode : null;
        final result = await Supabase.instance.client.rpc<Map<String, dynamic>>(
          'session_create',
          params: {
            'p_venue_id': _venueId,
            'p_family_id': familyId,
            'p_child_id': childId,
            'p_duration_minutes': _selectedDurationMinutes,
            'p_payment_method': _paymentMethod,
            'p_idempotency_key': idem,
            'p_batch_id': batchId,
            'p_kid_count': children.length,
            if (couponForCall != null) 'p_coupon_code': couponForCall,
          },
        );
        final sid = result['session_id'] as String?;
        if (sid != null) sessionIds.add(sid);
        createdCount[0]++;
      }

      if (!mounted) return;
      AppHaptics.success();
      // Refresh active sessions so Home reflects the new batch on the
      // next frame — without this the multi-session stack appears empty
      // until the stream's next 15s tick.
      ref.invalidate(activeSessionsProvider);
      // Refresh wallet / pass balances so the Home header and pass card
      // update immediately (the backend may place a hold or consume passes
      // at creation time; the QR screen refreshes again on scan).
      ref.invalidate(walletTransactionsBalanceProvider);
      ref.invalidate(currentWalletProvider);
      ref.invalidate(playPassesProvider);
      // Always route to QR scanner after session creation — parents need
      // to scan at the venue for every session, including additional kids.
      if (sessionIds.isNotEmpty) {
        context.go(
          '/session/qr/${sessionIds.first}',
          extra: {'batchSessionIds': sessionIds},
        );
      } else {
        context.go('/home');
      }
    } on PostgrestException catch (e) {
      // Money-safety: if any sessions were created before this failure,
      // cancel them so the parent doesn't end up with a half-started batch
      // and a confusing mix of holds/consumed passes.
      if (createdCount[0] > 0) {
        await _cancelPendingSessions(sessionIds);
      }
      if (!mounted) return;

      final couponErrors = {
        'coupon_invalid_code': 'That coupon code doesn\'t exist.',
        'coupon_inactive': 'That coupon is no longer active.',
        'coupon_not_yet_active': 'That coupon isn\'t active yet.',
        'coupon_expired': 'That coupon has expired.',
        'coupon_exhausted': 'That coupon has been fully redeemed.',
        'coupon_already_used_by_family': 'You\'ve already used that coupon.',
        'coupon_min_order_not_met': 'Coupon needs a higher order amount.',
        'coupon_requires_more_kids':
            'That code needs more kids in the booking.',
      };
      for (final entry in couponErrors.entries) {
        if (e.message.contains(entry.key)) {
          setState(() {
            _busy = false;
            _couponError = entry.value;
            _couponDiscountPaise = null;
            _appliedCouponCode = null;
          });
          return;
        }
      }
      if (e.message.contains('child_already_in_session')) {
        // The kid picker filters out already-playing kids, so we only
        // get here if a sibling session was started from another device
        // between picker render and submit. Refresh the picker so it
        // catches up.
        ref.invalidate(activeSessionsProvider);
        AppHaptics.error();
        setState(() {
          _busy = false;
          _errorText = 'One of those kids is already playing. Try again.';
        });
        return;
      }
      if (e.message.contains('play_pass_1hr_only')) {
        AppHaptics.error();
        setState(() {
          _busy = false;
          _errorText =
              'Play Passes are for 1-hour visits only. Pick 1 hour or switch payment.';
        });
        return;
      }
      if (e.message.contains('no_active_play_pass')) {
        AppHaptics.error();
        setState(() {
          _busy = false;
          _errorText = 'Not enough Play Passes. Buy more in Profile.';
        });
        return;
      }
      if (e.message.contains('insufficient_balance')) {
        setState(() => _busy = false);
        showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          useRootNavigator: true,
          builder: (_) => InsufficientBalanceSheet(
            requiredPaise: totalAmount,
            onSwitchToCash: () {
              if (!mounted) return;
              setState(() => _paymentMethod = 'cash');
            },
          ),
        );
        return;
      }
      AppHaptics.error();
      setState(() {
        _busy = false;
        _errorText = "Couldn't start session: ${e.message}";
      });
    } catch (e, st) {
      // Same money-safety rollback for non-PostgREST failures.
      dev.log('[session_start] unexpected error', error: e, stackTrace: st);
      if (createdCount[0] > 0) {
        await _cancelPendingSessions(sessionIds);
      }
      if (!mounted) return;
      AppHaptics.error();
      setState(() {
        _busy = false;
        _errorText = "Couldn't start session. Please try again.";
      });
    }
  }

  /// Cancel any pending sessions created so far in a batch. Used for
  /// all-or-nothing rollback when a later session_create call fails.
  Future<void> _cancelPendingSessions(List<String> ids) async {
    for (final id in ids) {
      try {
        await Supabase.instance.client.rpc<dynamic>(
          'session_cancel_pending',
          params: {'p_session_id': id},
        );
      } catch (_) {
        // Best-effort; server-side cron is the safety net.
      }
    }
    // Refresh balances so any released holds / passes show immediately.
    ref.invalidate(activeSessionsProvider);
    ref.invalidate(walletTransactionsBalanceProvider);
    ref.invalidate(currentWalletProvider);
    ref.invalidate(playPassesProvider);
  }

  @override
  Widget build(BuildContext context) {
    final cfg = ref.watch(venueConfigProvider).valueOrNull;
    final balance = ref.watch(walletBalancePaiseProvider) ?? 0;
    final remainingPasses = ref.watch(remainingPassesCountProvider);

    // Prices from venue_config; standard 1hr ₹800 / 2hr ₹1100 as fallback
    // when the key is missing or unparseable.
    final price1hr =
        (cfg?['session_1hr_price_paise'] as num?)?.toInt() ?? 80000;
    final price2hr =
        (cfg?['session_2hr_price_paise'] as num?)?.toInt() ?? 110000;
    final perKidPrice = _priceFor(_selectedDurationMinutes, cfg);
    final discount = _couponDiscountPaise ?? 0;
    // Sum across selected kids, then subtract the (single-redemption) coupon.
    final subtotal = perKidPrice * _selectedChildIds.length;
    final finalAmount = (subtotal - discount).clamp(0, 1 << 30);
    final walletEnough = balance >= finalAmount;
    final passesEnough = remainingPasses >= _selectedChildIds.length;

    final canSubmit =
        !_busy &&
        _selectedDurationMinutes != null &&
        _selectedChildIds.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Start a session'),
        leading: IconButton(
          icon: const Icon(PhosphorIconsRegular.arrowLeft),
          onPressed: () => context.pop(),
        ),
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _childrenFuture,
        builder: (context, snap) {
          if (snap.hasError) {
            return FriendlyErrorScreen(
              code: 'E-SES-1',
              userMessage: "Couldn't load your kids",
              technicalDetails: snap.error.toString(),
              onRetry: () {
                setState(() {
                  _childrenFuture = _loadChildren();
                });
              },
            );
          }
          if (!snap.hasData) {
            return const Padding(
              padding: EdgeInsets.all(20),
              child: SkeletonList(itemCount: 4),
            );
          }
          final allChildren = snap.data!;
          // Filter out children who already have an open session — they
          // can't be picked for a parallel one.
          final inSession = ref.watch(childrenWithActiveSessionProvider);
          final children = allChildren
              .where((c) => !inSession.contains(c['id'] as String))
              .toList();

          // Drop any selections that have since gone into session.
          _selectedChildIds.removeWhere(inSession.contains);
          // No default selection for multi-kid families — parent taps to
          // opt each kid in. Copy 'Tap to include each kid. Tally adds up
          // below.' implies an empty start; pre-selecting contradicted it
          // and risked accidental over-charges in multi-kid families.
          //
          // BUT for single-kid families the picker UI is hidden entirely
          // (no scroll list rendered below), so without an auto-select the
          // CTA gets stuck on "Pick at least one kid" with nothing to tap.
          if (children.length == 1) {
            _selectedChildIds.add(children.first['id'] as String);
          }

          if (children.isEmpty) {
            return const BrandedEmptyState(
              icon: PhosphorIconsFill.users,
              title: 'All your kids are already playing!',
              subtitle: 'Add another child in Profile to start a new session.',
            );
          }

          return SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_welcomeOffer != null &&
                            _welcomeOffer!['type'] != 'none') ...[
                          _WelcomeOfferBanner(offer: _welcomeOffer!),
                          const SizedBox(height: 20),
                        ],
                        if (children.length > 1) ...[
                          Text(
                            'Who\'s playing?',
                            style: AppTextStyles.bodyLarge(context),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Tap to include each kid. Tally adds up below.',
                            style: AppTextStyles.caption(
                              context,
                              color: AppColors.lightTextSecondary,
                            ),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            height: 110,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: children.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(width: 12),
                              itemBuilder: (_, i) {
                                final c = children[i];
                                final id = c['id'] as String;
                                final selected = _selectedChildIds.contains(id);
                                return _ChildAvatar(
                                  name: c['name'] as String? ?? '—',
                                  favouriteHero: c['favourite_hero'] as String?,
                                  selected: selected,
                                  onTap: () {
                                    AppHaptics.light();
                                    setState(() {
                                      if (selected) {
                                        _selectedChildIds.remove(id);
                                      } else {
                                        _selectedChildIds.add(id);
                                      }
                                      _errorText = null;
                                      // If Play Pass can no longer cover the
                                      // selection, fall back to wallet so the
                                      // user never sees a disabled pass CTA.
                                      if (_paymentMethod == 'play_pass' &&
                                          remainingPasses <
                                              _selectedChildIds.length) {
                                        _paymentMethod = 'wallet';
                                      }
                                      // Clearing a sibling coupon if kid
                                      // count changes so it no longer matches
                                      // keeps the tally honest.
                                      if (_couponBackendCode != null) {
                                        final cfg = ref
                                            .read(venueConfigProvider)
                                            .valueOrNull;
                                        final stillValid =
                                            _siblingCouponFor(
                                              _selectedChildIds.length,
                                              cfg,
                                            )?['code'] ==
                                            _couponBackendCode;
                                        if (!stillValid) _clearCoupon();
                                      }
                                    });
                                  },
                                );
                              },
                            ),
                          ),
                          const SizedBox(height: 24),
                        ] else ...[
                          // Single-kid family: no picker, just confirm who.
                          Row(
                            children: [
                              _ChildAvatar(
                                name: children.first['name'] as String? ?? '—',
                                favouriteHero:
                                    children.first['favourite_hero'] as String?,
                                selected: true,
                                onTap: () {},
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Playing as',
                                      style: AppTextStyles.caption(
                                        context,
                                        color: AppColors.lightTextSecondary,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      children.first['name'] as String? ?? '—',
                                      style: AppTextStyles.bodyLarge(
                                        context,
                                      ).copyWith(fontWeight: FontWeight.w800),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),
                        ],
                        Text(
                          'How long?',
                          style: AppTextStyles.bodyLarge(context),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _DurationCard(
                                title: '1 hour',
                                tagline: 'Quick play',
                                pricePaise: price1hr,
                                selected: _selectedDurationMinutes == 60,
                                onTap: () {
                                  AppHaptics.light();
                                  setState(() {
                                    _selectedDurationMinutes = 60;
                                    _errorText = null;
                                    if (_paymentMethod == 'play_pass' &&
                                        remainingPasses <
                                            _selectedChildIds.length) {
                                      _paymentMethod = 'wallet';
                                    }
                                  });
                                  _maybeAutoApplyWelcome();
                                },
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _DurationCard(
                                title: '2 hours',
                                tagline: 'Best value',
                                pricePaise: price2hr,
                                selected: _selectedDurationMinutes == 120,
                                onTap: () {
                                  AppHaptics.light();
                                  setState(() {
                                    _selectedDurationMinutes = 120;
                                    _errorText = null;
                                    // Play Passes are 1-hour only.
                                    if (_paymentMethod == 'play_pass') {
                                      _paymentMethod = 'wallet';
                                    }
                                  });
                                  _maybeAutoApplyWelcome();
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        if (_selectedDurationMinutes != null &&
                            _selectedChildIds.isNotEmpty) ...[
                          _TallyBox(
                            kidCount: _selectedChildIds.length,
                            perKidPaise: perKidPrice,
                            subtotal: subtotal,
                            discountPaise: discount,
                            total: finalAmount,
                          ),
                          const SizedBox(height: 24),
                        ],
                        if (_paymentMethod != 'play_pass') ...[
                          _CouponSection(
                            controller: _couponCtrl,
                            appliedCode: _appliedCouponCode,
                            discountPaise: _couponDiscountPaise,
                            baseAmountPaise: subtotal,
                            validating: _validatingCoupon,
                            error: _couponError,
                            enabled: _selectedDurationMinutes != null,
                            onApply: _applyCoupon,
                            onClear: _clearCoupon,
                          ),
                          const SizedBox(height: 12),
                          _SiblingCouponChips(
                            kidCount: _selectedChildIds.length,
                            appliedCode: _couponBackendCode,
                            venueConfig: cfg,
                            onApply: _applySiblingCoupon,
                          ),
                          const SizedBox(height: 24),
                        ],
                        Text(
                          'Pay with',
                          style: AppTextStyles.bodyLarge(context),
                        ),
                        const SizedBox(height: 4),
                        if (passesEnough && _selectedDurationMinutes != 120)
                          SelectableCard<String>(
                            value: 'play_pass',
                            groupValue: _paymentMethod,
                            title: 'Play Pass ($remainingPasses left)',
                            subtitle: '1 pass = 1 hour for any kid',
                            leading: const Icon(
                              PhosphorIconsFill.ticket,
                              color: AppColors.gold,
                              size: 24,
                            ),
                            onChanged: (_) => setState(() {
                              _paymentMethod = 'play_pass';
                              _errorText = null;
                              _clearCoupon();
                            }),
                          ),
                        SelectableCard<String>(
                          value: 'wallet',
                          groupValue: _paymentMethod,
                          title: 'Wallet (${Money.fromPaise(balance)})',
                          subtitle:
                              !walletEnough && _selectedDurationMinutes != null
                              ? 'Not enough balance'
                              : 'Pay instantly from wallet',
                          leading: const Icon(
                            PhosphorIconsFill.wallet,
                            color: AppColors.navy,
                            size: 24,
                          ),
                          onChanged: (_) => setState(() {
                            _paymentMethod = 'wallet';
                            _errorText = null;
                          }),
                        ),
                        SelectableCard<String>(
                          value: 'cash',
                          groupValue: _paymentMethod,
                          title: 'Cash at venue',
                          subtitle: 'Pay our team when you check in',
                          leading: const Icon(
                            PhosphorIconsRegular.money,
                            color: AppColors.navy,
                            size: 24,
                          ),
                          onChanged: (_) => setState(() {
                            _paymentMethod = 'cash';
                            _errorText = null;
                          }),
                        ),
                        if (_errorText != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            _errorText!,
                            style: AppTextStyles.caption(
                              context,
                              color: AppColors.adminRed,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                _StickyCta(
                  label: _selectedDurationMinutes == null
                      ? 'Pick a duration'
                      : _selectedChildIds.isEmpty
                      ? 'Pick at least one kid'
                      : _paymentMethod == 'play_pass'
                      ? passesEnough
                            ? 'Use ${_selectedChildIds.length} '
                                  'Play Pass${_selectedChildIds.length == 1 ? '' : 'es'}'
                            : 'Not enough passes'
                      : _paymentMethod == 'wallet'
                      ? 'Pay ${Money.fromPaise(finalAmount)} '
                            'from wallet'
                      : 'Continue with cash',
                  onPressed:
                      canSubmit &&
                          (_paymentMethod != 'play_pass' || passesEnough)
                      ? _start
                      : null,
                  loading: _busy,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ChildAvatar extends StatelessWidget {
  final String name;
  final String? favouriteHero;
  final bool selected;
  final VoidCallback onTap;
  const _ChildAvatar({
    required this.name,
    this.favouriteHero,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          HeroAvatar(
            heroId: favouriteHero,
            fallbackName: name,
            size: 72,
            selected: selected,
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: 78,
            child: Text(
              name,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.caption(context),
            ),
          ),
        ],
      ),
    );
  }
}

class _DurationCard extends StatelessWidget {
  final String title;
  final String tagline;
  final int pricePaise;
  final bool selected;
  final VoidCallback onTap;
  const _DurationCard({
    required this.title,
    required this.tagline,
    required this.pricePaise,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(kHomeCardRadius),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.gold.withValues(alpha: 0.18)
              : AppColors.lightSurface,
          border: Border.all(
            color: selected ? AppColors.gold : AppColors.lightBorder,
            width: selected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(kHomeCardRadius),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: AppTextStyles.h3(context)),
            const SizedBox(height: 4),
            Text(
              Money.fromPaise(pricePaise),
              style: AppTextStyles.h2(context, color: AppColors.navy),
            ),
            const SizedBox(height: 4),
            Text(
              tagline,
              style: AppTextStyles.caption(
                context,
                color: AppColors.lightTextSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StickyCta extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  const _StickyCta({
    required this.label,
    required this.onPressed,
    required this.loading,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          border: const Border(top: BorderSide(color: AppColors.lightBorder)),
        ),
        child: SizedBox(
          width: double.infinity,
          child: PrimaryButton(
            label: label,
            onPressed: onPressed,
            loading: loading,
          ),
        ),
      ),
    );
  }
}

/// Coupon entry + applied state for the Start a session screen. Renders
/// the input + apply button until validated, then shows a green
/// Running tally — visible once at least one kid is selected and a
/// duration is picked. Shows per-kid line, subtotal across selected
/// kids, optional coupon discount, and total.
class _TallyBox extends StatelessWidget {
  final int kidCount;
  final int perKidPaise;
  final int subtotal;
  final int discountPaise;
  final int total;

  const _TallyBox({
    required this.kidCount,
    required this.perKidPaise,
    required this.subtotal,
    required this.discountPaise,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.lightSurface,
        border: Border.all(color: AppColors.lightBorder),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _TallyRow(
            label: '$kidCount × ${Money.fromPaise(perKidPaise)}',
            value: Money.fromPaise(subtotal),
          ),
          if (discountPaise > 0) ...[
            const SizedBox(height: 6),
            _TallyRow(
              label: 'Coupon',
              value: '-${Money.fromPaise(discountPaise)}',
              valueColor: AppColors.activeGreen,
            ),
          ],
          const SizedBox(height: 8),
          const Divider(height: 1),
          const SizedBox(height: 8),
          _TallyRow(label: 'Total', value: Money.fromPaise(total), bold: true),
        ],
      ),
    );
  }
}

class _TallyRow extends StatelessWidget {
  final String label;
  final String value;
  final bool bold;
  final Color? valueColor;
  const _TallyRow({
    required this.label,
    required this.value,
    this.bold = false,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    final style = AppTextStyles.body(
      context,
    ).copyWith(fontWeight: bold ? FontWeight.w800 : FontWeight.w500);
    return Row(
      children: [
        Expanded(child: Text(label, style: style)),
        Text(value, style: style.copyWith(color: valueColor ?? AppColors.navy)),
      ],
    );
  }
}

/// "applied" pill with the discount and a clear (×) action.
class _CouponSection extends StatelessWidget {
  final TextEditingController controller;
  final String? appliedCode;
  final int? discountPaise;
  final int baseAmountPaise;
  final bool validating;
  final String? error;
  final bool enabled;
  final VoidCallback onApply;
  final VoidCallback onClear;

  const _CouponSection({
    required this.controller,
    required this.appliedCode,
    required this.discountPaise,
    required this.baseAmountPaise,
    required this.validating,
    required this.error,
    required this.enabled,
    required this.onApply,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    if (appliedCode != null && discountPaise != null && discountPaise! > 0) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.activeGreen.withValues(alpha: 0.10),
          border: Border.all(
            color: AppColors.activeGreen.withValues(alpha: 0.40),
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$appliedCode applied — you save ${Money.fromPaise(discountPaise!)}',
              style: AppTextStyles.body(context).copyWith(
                fontWeight: FontWeight.w700,
                color: AppColors.activeGreen,
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: onClear,
                child: const Text('Remove'),
              ),
            ),
          ],
        ),
      );
    }

    // Apply lives INSIDE the TextField as a suffix button so it stays
    // glued to the input. A separate Apply button below the field gets
    // hidden by the on-screen keyboard, and parents — seeing only the
    // sticky "Pay" CTA — were tapping Pay before realising they hadn't
    // applied their coupon. With the suffix pattern, "APPLY" is always
    // next to where they're typing, and pressing Return on the keyboard
    // also applies (onSubmitted handler).
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Have a coupon code?', style: AppTextStyles.bodyLarge(context)),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          enabled: enabled && !validating,
          textCapitalization: TextCapitalization.characters,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
            hintText: enabled ? 'Enter coupon code' : 'Pick a duration first',
            border: const OutlineInputBorder(),
            isDense: true,
            errorText: error,
            suffixIcon: validating
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation(AppColors.navy),
                      ),
                    ),
                  )
                : TextButton(
                    onPressed: enabled ? onApply : null,
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.navy,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      minimumSize: const Size(60, 36),
                    ),
                    child: Text(
                      'APPLY',
                      style: AppTextStyles.button(
                        context,
                        color: AppColors.navy,
                      ),
                    ),
                  ),
          ),
          onSubmitted: (_) => enabled ? onApply() : null,
        ),
      ],
    );
  }
}

/// Direct-code sibling-coupon chip. Shown below the coupon input when 2+ kids
/// are selected. The coupon code itself is surfaced (e.g. `2KIDS`) and is
/// read from the admin-configured `sibling_coupon_codes` map in venue_config.
class _SiblingCouponChips extends StatelessWidget {
  final int kidCount;
  final String? appliedCode;
  final Map<String, dynamic>? venueConfig;
  final VoidCallback onApply;

  const _SiblingCouponChips({
    required this.kidCount,
    required this.appliedCode,
    required this.venueConfig,
    required this.onApply,
  });

  static const _fallbackCodes = {
    '2': 'ZENA',
    '3': 'RAFI',
    '4': 'GERRY',
    '5': 'WILDPACK',
  };

  String? _codeFor(int count, Map<String, dynamic>? cfg) {
    final map = (cfg?['sibling_coupon_codes'] as Map<String, dynamic>?) ?? {};
    return (map[count.toString()] ?? _fallbackCodes[count.toString()])
        as String?;
  }

  @override
  Widget build(BuildContext context) {
    final code = _codeFor(kidCount, venueConfig);
    if (code == null) return const SizedBox.shrink();

    final isApplied = appliedCode == code;

    return Row(
      children: [
        Expanded(
          child: InkWell(
            onTap: isApplied ? null : onApply,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: isApplied
                    ? AppColors.activeGreen.withValues(alpha: 0.12)
                    : AppColors.lightSurface,
                border: Border.all(
                  color: isApplied
                      ? AppColors.activeGreen
                      : AppColors.lightBorder,
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isApplied
                        ? PhosphorIconsRegular.checkCircle
                        : PhosphorIconsRegular.tag,
                    color: isApplied
                        ? AppColors.fitGreen
                        : AppColors.lightTextSecondary,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      isApplied ? '$code applied' : 'Apply $code',
                      style: AppTextStyles.caption(context).copyWith(
                        color: isApplied
                            ? AppColors.fitGreen
                            : AppColors.lightTextSecondary,
                        fontWeight: isApplied
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Prominent first-session welcome banner. Two flavours:
///   * discount  → "₹100 OFF your first play — applied!"
///   * referral  → "A friend gifted you ₹100 — lands in your wallet after play"
class _WelcomeOfferBanner extends StatelessWidget {
  final Map<String, dynamic> offer;
  const _WelcomeOfferBanner({required this.offer});

  @override
  Widget build(BuildContext context) {
    final type = offer['type'] as String?;
    final bool isDiscount = type == 'discount';

    final int paise = isDiscount
        ? ((offer['value_paise'] as num?)?.toInt() ?? 0)
        : ((offer['credit_paise'] as num?)?.toInt() ?? 0);
    if (paise <= 0) return const SizedBox.shrink();
    final String rupees = '₹${paise ~/ 100}';

    final String title = isDiscount
        ? '$rupees OFF your first play!'
        : 'A friend gifted you $rupees!';
    final String subtitle = isDiscount
        ? 'Welcome offer applied automatically at checkout.'
        : 'It lands in your wallet right after your first play.';
    final IconData icon =
        isDiscount ? PhosphorIconsFill.confetti : PhosphorIconsFill.gift;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.gold,
            AppColors.gold.withValues(alpha: 0.85),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.gold.withValues(alpha: 0.30),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.navy, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTextStyles.bodyLarge(context).copyWith(
                    color: AppColors.navy,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: AppTextStyles.caption(
                    context,
                    color: AppColors.navy.withValues(alpha: 0.85),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
