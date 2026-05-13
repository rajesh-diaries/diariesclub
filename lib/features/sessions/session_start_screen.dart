// ignore_for_file: deprecated_member_use
// ^ RadioListTile.groupValue/onChanged — see extend_session_sheet.dart.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../core/providers/active_sessions_provider.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/providers/current_wallet_provider.dart';
import '../../core/providers/venue_config_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/currency.dart';
import '../../core/utils/venues.dart';
import '../../core/widgets/error_screen.dart';
import '../../core/widgets/primary_button.dart';
import 'widgets/insufficient_balance_sheet.dart';

const _venueId = Venues.kondapurId;

/// Step 1 of the session lifecycle: pick child (if multi), pick duration
/// (1hr / 2hr — prices from venue_config), pick payment method, then call
/// `session_create`. On success → /session/qr/:id.
class SessionStartScreen extends ConsumerStatefulWidget {
  const SessionStartScreen({super.key});

  @override
  ConsumerState<SessionStartScreen> createState() =>
      _SessionStartScreenState();
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
  String? _appliedCouponCode;
  String? _couponError;

  late Future<List<Map<String, dynamic>>> _childrenFuture;

  @override
  void initState() {
    super.initState();
    _childrenFuture = _loadChildren();
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
    if (duration == null || cfg == null) return 0;
    return duration == 60
        ? (cfg['session_1hr_price_paise'] as int?) ?? 80000
        : (cfg['session_2hr_price_paise'] as int?) ?? 110000;
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
        params: {'p_code': code, 'p_amount_paise': amount},
      );
      if (!mounted) return;
      if (res['valid'] == true) {
        setState(() {
          _validatingCoupon = false;
          _couponDiscountPaise = res['discount_paise'] as int? ?? 0;
          _appliedCouponCode = (res['code'] as String?) ?? code.toUpperCase();
        });
      } else {
        setState(() {
          _validatingCoupon = false;
          _couponDiscountPaise = null;
          _appliedCouponCode = null;
          _couponError = (res['message'] as String?) ?? 'Invalid coupon.';
        });
      }
    } catch (e) {
      if (!mounted) return;
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
      _couponError = null;
      _couponCtrl.clear();
    });
  }

  Future<void> _start() async {
    if (_selectedDurationMinutes == null || _selectedChildIds.isEmpty) return;
    final cfg = ref.read(venueConfigProvider).valueOrNull;
    final perKidPrice = _priceFor(_selectedDurationMinutes, cfg);
    final coupon = _couponDiscountPaise ?? 0;
    // Coupon applies to the first session only (per-family redemption).
    // The remaining N-1 sessions pay full price.
    final totalAmount =
        (perKidPrice * _selectedChildIds.length) - coupon;

    setState(() {
      _busy = true;
      _errorText = null;
    });
    final familyId = ref.read(currentFamilyIdProvider);
    if (familyId == null) {
      setState(() => _busy = false);
      return;
    }

    // Pre-check wallet balance so we don't half-create the batch and
    // leave orphaned holds.
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
    }

    final children = _selectedChildIds.toList();
    String? firstSessionId;
    // Track successes so a mid-batch failure can surface a "N of M
    // started" message instead of silently leaving the user wondering
    // which kids made it through.
    final createdCount = <int>[0];
    try {
      for (var i = 0; i < children.length; i++) {
        final childId = children[i];
        final idem = const Uuid().v4();
        // Coupon attaches to first session only; remaining run full price.
        final couponForCall = (i == 0) ? _appliedCouponCode : null;
        final result = await Supabase.instance.client
            .rpc<Map<String, dynamic>>('session_create', params: {
          'p_venue_id': _venueId,
          'p_family_id': familyId,
          'p_child_id': childId,
          'p_duration_minutes': _selectedDurationMinutes,
          'p_payment_method': _paymentMethod,
          'p_idempotency_key': idem,
          if (couponForCall != null) 'p_coupon_code': couponForCall,
        });
        firstSessionId ??= result['session_id'] as String?;
        createdCount[0]++;
      }

      if (!mounted) return;
      // Refresh active sessions so Home reflects the new batch on the
      // next frame — without this the multi-session stack appears empty
      // until the stream's next 15s tick.
      ref.invalidate(activeSessionsProvider);
      // Multi-session → land on home with the new session stack.
      // Single-kid → straight to QR like before.
      if (children.length == 1 && firstSessionId != null) {
        context.go('/session/qr/$firstSessionId');
      } else {
        context.go('/home');
      }
    } on PostgrestException catch (e) {
      final couponErrors = {
        'coupon_invalid_code': 'That coupon code doesn\'t exist.',
        'coupon_inactive': 'That coupon is no longer active.',
        'coupon_not_yet_active': 'That coupon isn\'t active yet.',
        'coupon_expired': 'That coupon has expired.',
        'coupon_exhausted': 'That coupon has been fully redeemed.',
        'coupon_already_used_by_family': 'You\'ve already used that coupon.',
        'coupon_min_order_not_met': 'Coupon needs a higher order amount.',
      };
      for (final entry in couponErrors.entries) {
        if (e.message.contains(entry.key)) {
          if (!mounted) return;
          setState(() {
            _busy = false;
            _couponError = entry.value;
            _couponDiscountPaise = null;
            _appliedCouponCode = null;
          });
          return;
        }
      }
      if (e.message.contains('insufficient_balance')) {
        if (!mounted) return;
        // If some sessions already started before the wallet drained,
        // bail to home with the partial-success message — opening the
        // top-up sheet on a half-charged batch is more confusing than
        // helpful.
        if (createdCount[0] > 0) {
          _handlePartialOrFullFailure(createdCount[0], children.length);
          return;
        }
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
      if (!mounted) return;
      _handlePartialOrFullFailure(createdCount[0], children.length);
    } catch (_) {
      if (!mounted) return;
      _handlePartialOrFullFailure(createdCount[0], children.length);
    }
  }

  /// Route after a session_create batch error. If some sessions started
  /// before the failure, refresh active sessions and route home with a
  /// snackbar — the user has been charged and needs to see what's live.
  /// Full failures stay on the screen with the error text so the parent
  /// can retry without losing their picks.
  void _handlePartialOrFullFailure(int created, int total) {
    if (created > 0) {
      ref.invalidate(activeSessionsProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.warningYellow,
          content: Text(
            '$created of $total sessions started. The rest didn\'t go '
            'through — please ask staff.',
          ),
        ),
      );
      context.go('/home');
      return;
    }
    setState(() {
      _busy = false;
      _errorText = "Couldn't start session. Please try again.";
    });
  }

  @override
  Widget build(BuildContext context) {
    final cfg = ref.watch(venueConfigProvider).valueOrNull;
    final balance = ref.watch(walletBalancePaiseProvider) ?? 0;

    final price1hr = (cfg?['session_1hr_price_paise'] as int?) ?? 80000;
    final price2hr = (cfg?['session_2hr_price_paise'] as int?) ?? 110000;
    final perKidPrice = _priceFor(_selectedDurationMinutes, cfg);
    final discount = _couponDiscountPaise ?? 0;
    // Sum across selected kids, then subtract the (single-redemption) coupon.
    final subtotal = perKidPrice * _selectedChildIds.length;
    final finalAmount = (subtotal - discount).clamp(0, 1 << 30);
    final walletEnough = balance >= finalAmount;

    final canSubmit = !_busy &&
        _selectedDurationMinutes != null &&
        _selectedChildIds.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Start a session'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
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
            return const Center(child: CircularProgressIndicator());
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
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  'All your kids are already playing! Add another child '
                  'in Profile to start a new session.',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.body(
                    context,
                    color: AppColors.lightTextSecondary,
                  ),
                ),
              ),
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
                        if (children.length > 1) ...[
                          Text('Who\'s playing?',
                              style: AppTextStyles.bodyLarge(context)),
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
                                final selected =
                                    _selectedChildIds.contains(id);
                                return _ChildAvatar(
                                  name: c['name'] as String? ?? '—',
                                  photoUrl: c['photo_url'] as String?,
                                  selected: selected,
                                  onTap: () => setState(() {
                                    if (selected) {
                                      _selectedChildIds.remove(id);
                                    } else {
                                      _selectedChildIds.add(id);
                                    }
                                  }),
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
                                photoUrl:
                                    children.first['photo_url'] as String?,
                                selected: true,
                                onTap: () {},
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text('Playing as',
                                        style: AppTextStyles.caption(
                                          context,
                                          color:
                                              AppColors.lightTextSecondary,
                                        )),
                                    const SizedBox(height: 2),
                                    Text(
                                      children.first['name'] as String? ??
                                          '—',
                                      style: AppTextStyles.bodyLarge(
                                              context)
                                          .copyWith(
                                              fontWeight: FontWeight.w800),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),
                        ],
                        Text('How long?',
                            style: AppTextStyles.bodyLarge(context)),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _DurationCard(
                                title: '1 hour',
                                tagline: 'Quick play',
                                pricePaise: price1hr,
                                selected: _selectedDurationMinutes == 60,
                                onTap: () => setState(
                                    () => _selectedDurationMinutes = 60),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _DurationCard(
                                title: '2 hours',
                                tagline: 'Best value',
                                pricePaise: price2hr,
                                selected: _selectedDurationMinutes == 120,
                                onTap: () => setState(
                                    () => _selectedDurationMinutes = 120),
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
                        const SizedBox(height: 24),
                        Text('Pay with',
                            style: AppTextStyles.bodyLarge(context)),
                        const SizedBox(height: 4),
                        RadioListTile<String>(
                          value: 'wallet',
                          groupValue: _paymentMethod,
                          title: Text(
                              'Diaries Wallet (${Money.fromPaise(balance)})'),
                          subtitle: !walletEnough &&
                                  _selectedDurationMinutes != null
                              ? const Text(
                                  'Not enough balance',
                                  style: TextStyle(color: AppColors.adminRed),
                                )
                              : null,
                          onChanged: (v) =>
                              setState(() => _paymentMethod = v ?? 'wallet'),
                        ),
                        RadioListTile<String>(
                          value: 'cash',
                          groupValue: _paymentMethod,
                          title: const Text('Cash at venue'),
                          subtitle: const Text(
                            'Pay our team when you check in',
                          ),
                          onChanged: (v) =>
                              setState(() => _paymentMethod = v ?? 'cash'),
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
                          : _paymentMethod == 'wallet'
                              ? 'Pay ${Money.fromPaise(finalAmount)} '
                                  'from wallet'
                              : 'Continue with cash',
                  onPressed: canSubmit ? _start : null,
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
  final String? photoUrl;
  final bool selected;
  final VoidCallback onTap;
  const _ChildAvatar({
    required this.name,
    required this.photoUrl,
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
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: selected ? AppColors.gold : AppColors.lightBorder,
                width: selected ? 3 : 1,
              ),
              image: photoUrl != null && photoUrl!.isNotEmpty
                  ? DecorationImage(
                      image: NetworkImage(photoUrl!),
                      fit: BoxFit.cover,
                    )
                  : null,
              color: AppColors.gold.withValues(alpha: 0.18),
            ),
            child: photoUrl == null || photoUrl!.isEmpty
                ? const Icon(
                    PhosphorIconsFill.smiley,
                    color: AppColors.navy,
                    size: 30,
                  )
                : null,
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
      borderRadius: BorderRadius.circular(16),
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
          borderRadius: BorderRadius.circular(16),
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
          border: const Border(
            top: BorderSide(color: AppColors.lightBorder),
          ),
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
          _TallyRow(
            label: 'Total',
            value: Money.fromPaise(total),
            bold: true,
          ),
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
    final style = AppTextStyles.body(context).copyWith(
      fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
    );
    return Row(
      children: [
        Expanded(child: Text(label, style: style)),
        Text(
          value,
          style: style.copyWith(color: valueColor ?? AppColors.navy),
        ),
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
          border: Border.all(color: AppColors.activeGreen.withValues(alpha: 0.40)),
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

    // Vertical stack — no Row/Expanded shenanigans. The TextField gets
    // full width from the parent stretch, the Apply button right-aligns
    // with intrinsic width. Bulletproof against Flutter web's flex
    // layout pitfalls.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Have a coupon code?', style: AppTextStyles.bodyLarge(context)),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          enabled: enabled && !validating,
          textCapitalization: TextCapitalization.characters,
          decoration: InputDecoration(
            hintText: enabled ? 'e.g. WELCOME50' : 'Pick a duration first',
            border: const OutlineInputBorder(),
            isDense: true,
            errorText: error,
          ),
          onSubmitted: (_) => enabled ? onApply() : null,
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton(
            onPressed: enabled && !validating ? onApply : null,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.navy,
              foregroundColor: Colors.white,
            ),
            child: validating
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(Colors.white),
                    ),
                  )
                : const Text('Apply coupon'),
          ),
        ),
      ],
    );
  }
}
