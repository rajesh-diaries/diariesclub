import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/current_wallet_provider.dart';
import '../../../core/providers/venue_config_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/currency.dart';
import '../../../core/utils/haptics.dart';
import '../../../core/utils/venues.dart';
import '../../../core/widgets/success_celebration.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../core/widgets/selection_card.dart';
import '../../sessions/widgets/insufficient_balance_sheet.dart';
import 'quantity_stepper.dart';
import '../providers/active_orders_provider.dart';
import '../providers/cart_provider.dart';
import 'order_confirm_sheet.dart';

const _venueId = Venues.kondapurId;

/// The bag bottom sheet. Brand-grouped line items, fulfillment + payment
/// pickers, GST-inclusive total, sticky place-order button. Place-order
/// calls `order_place` and routes to /club/order/:id on success. Sold-out
/// races + insufficient balance + invalid combo all surface as user-
/// friendly messages.
class CartSheet extends ConsumerStatefulWidget {
  const CartSheet({super.key});

  @override
  ConsumerState<CartSheet> createState() => _CartSheetState();
}

class _CartSheetState extends ConsumerState<CartSheet> {
  bool _busy = false;
  String? _errorText;
  bool _celebrate = false;
  bool _orderPlaced = false;

  // Idempotency key stabilized per cart contents. Re-opening the confirm
  // sheet (or a retried tap) reuses the same key so the server dedupes the
  // order; a genuinely different cart mints a fresh key.
  String? _idempotencyKey;
  String? _idempotencyCartSig;

  String _stableIdempotencyKey(List<Map<String, dynamic>> body) {
    final sig = jsonEncode(body);
    if (_idempotencyKey == null || _idempotencyCartSig != sig) {
      _idempotencyKey = const Uuid().v4();
      _idempotencyCartSig = sig;
    }
    return _idempotencyKey!;
  }

  /// Build the heterogeneous p_items payload used by both order_preview
  /// and order_place.
  List<Map<String, dynamic>> _buildOrderBody() {
    final body = <Map<String, dynamic>>[];
    final cart = ref.read(cartProvider);
    for (final l in cart.lines) {
      switch (l) {
        case MenuItemLine m:
          body.add({
            'type': 'menu_item',
            'menu_item_id': m.menuItemId,
            'quantity': m.quantity,
          });
        case ComboLine c:
          final entry = <String, dynamic>{
            'type': 'combo',
            'combo_id': c.comboId,
            'quantity': c.quantity,
          };
          if (c.hasLinkedFitMeal) {
            entry['fit_template_id'] = c.linkedFitTemplateId;
            entry['fit_selections'] = c.linkedFitSelections;
          }
          body.add(entry);
        case FitMealLine f:
          body.add({
            'type': 'fit_meal',
            'template_id': f.templateId,
            'quantity': f.quantity,
            'selections': f.selectionsJsonb,
          });
      }
    }
    return body;
  }

  /// Show the tax-aware confirmation sheet. The actual order_place call
  /// only happens after the user taps "Place order" inside the sheet.
  void _showConfirmSheet() {
    final cart = ref.read(cartProvider);
    if (cart.isEmpty) return;
    final familyId = ref.read(currentFamilyIdProvider);
    if (familyId == null) return;
    final body = _buildOrderBody();
    final idem = _stableIdempotencyKey(body);
    // NOTE: do not reset _busy in whenComplete — the confirm sheet pops
    // immediately while _executePlaceOrder's order_place RPC is still
    // in-flight. _executePlaceOrder owns _busy and clears it only when the
    // async work actually resolves (or on navigation away on success).
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => OrderConfirmSheet(
        title:
            '${cart.totalItemCount} item${cart.totalItemCount == 1 ? '' : 's'}',
        subtitle: 'Review before placing',
        items: body,
        onConfirm: () => _executePlaceOrder(body, idem),
      ),
    );
  }

  Future<void> _executePlaceOrder(
    List<Map<String, dynamic>> body,
    String idempotencyKey,
  ) async {
    final cart = ref.read(cartProvider);
    final familyId = ref.read(currentFamilyIdProvider);
    if (familyId == null) return;
    final fulfillment = ref.read(cartFulfillmentProvider);
    final payment = ref.read(cartPaymentMethodProvider);

    setState(() {
      _busy = true;
      _errorText = null;
    });

    try {
      final result = await Supabase.instance.client.rpc<Map<String, dynamic>>(
        'order_place',
        params: {
          'p_venue_id': _venueId,
          'p_family_id': familyId,
          'p_items': body,
          'p_fulfillment_mode': fulfillment.rpcValue,
          'p_payment_method': payment.rpcValue,
          'p_combo_id': null,
          'p_idempotency_key': idempotencyKey,
        },
      );
      final orderId = result['order_id'] as String?;
      if (orderId == null) throw StateError('order_place returned no id');

      AppHaptics.success();
      setState(() {
        _celebrate = true;
        _orderPlaced = true;
      });
      ref.read(cartProvider.notifier).clear();
      ref.invalidate(currentWalletProvider);
      ref.invalidate(activeOrdersProvider);
      if (!mounted) return;
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      if (!mounted) return;
      Navigator.of(context).pop();
      context.go('/club/order/$orderId');
    } on PostgrestException catch (e) {
      debugPrint(
        '[ORDER_PLACE] PostgrestException: code=${e.code} '
        'message=${e.message} details=${e.details} hint=${e.hint}',
      );
      if (!mounted) return;
      AppHaptics.error();
      setState(() => _busy = false);
      if (e.message.contains('insufficient_balance')) {
        showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => InsufficientBalanceSheet(
            requiredPaise: cart.totalPaise,
            onSwitchToCash: () {
              if (!mounted) return;
              ref.read(cartPaymentMethodProvider.notifier).state =
                  CartPaymentMethod.cash;
            },
          ),
        );
      } else if (e.message.contains('menu_item_unavailable')) {
        setState(
          () => _errorText =
              'An item just sold out. Please remove it from your bag.',
        );
      } else if (e.message.contains('invalid_combo')) {
        setState(() => _errorText = "That combo isn't available right now.");
      } else {
        setState(() => _errorText = "Couldn't place order: ${e.message}");
      }
    } catch (e) {
      debugPrint('[ORDER_PLACE] generic error: $e');
      if (!mounted) return;
      AppHaptics.error();
      setState(() {
        _busy = false;
        _errorText = "Couldn't place order: $e";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);
    final balance = ref.watch(walletBalancePaiseProvider) ?? 0;
    final cfg = ref.watch(venueConfigProvider).valueOrNull ?? const {};
    final cashbackPct = (cfg['cashback_percent'] as num?)?.toDouble() ?? 7.0;
    final foodGstPct = (cfg['food_gst_percent'] as num?)?.toDouble() ?? 5.0;

    if (_orderPlaced) {
      return SuccessCelebration(
        shouldPlay: _celebrate,
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.all(24),
          child: const SafeArea(
            top: false,
            child: Center(child: _OrderPlacedView()),
          ),
        ),
      );
    }

    if (cart.isEmpty) return const _EmptyBag();

    // Mixed-GST preview math (policy 2026-05-11):
    //   food prices (menu + fit_meal) are PRE-GST → add 5% on top
    //   combo prices are all-in (any session portion stays 18% inclusive)
    //   final total rounded to nearest rupee (server is authoritative).
    var foodPaise = 0;
    var comboPaise = 0;
    for (final l in cart.lines) {
      if (l is ComboLine) {
        comboPaise += l.linePaise;
      } else {
        foodPaise += l.linePaise;
      }
    }
    final foodGstPaise = (foodPaise * foodGstPct / 100).round();
    final preRound = foodPaise + foodGstPaise + comboPaise;
    final total = ((preRound + 50) ~/ 100) * 100;
    final roundingPaise = total - preRound;

    // Coins are whole-rupee-equivalent integers. Cashback applies on the
    // taxable (pre-GST) value; combos: server strips the play portion, the
    // cart can only show a rough preview. Receipt shows the authoritative
    // number.
    final coinsBasePaise = foodPaise + comboPaise;
    final coins = (coinsBasePaise / 100 * cashbackPct / 100).floor();

    return SuccessCelebration(
      shouldPlay: _celebrate,
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.lightBorder,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: Row(
                children: [
                  Text('Your bag', style: AppTextStyles.h2(context)),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(PhosphorIconsRegular.x),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                cart.totalItemCount == 1
                    ? '1 item'
                    : '${cart.totalItemCount} items',
                style: AppTextStyles.caption(
                  context,
                  color: AppColors.lightTextSecondary,
                ),
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Column(
                  children: [
                    _LineList(lines: cart.lines),
                    const SizedBox(height: 16),
                    _Summary(
                      foodPaise: foodPaise,
                      foodGstPaise: foodGstPaise,
                      foodGstPct: foodGstPct,
                      comboPaise: comboPaise,
                      roundingPaise: roundingPaise,
                      totalPaise: total,
                      coinsEarned: coins,
                    ),
                    const SizedBox(height: 16),
                    const _FulfillmentSelector(),
                    const SizedBox(height: 12),
                    _PaymentSelector(
                      walletBalance: balance,
                      requiredPaise: total,
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
            SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
                decoration: BoxDecoration(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  border: const Border(
                    top: BorderSide(color: AppColors.lightBorder),
                  ),
                ),
                child: SizedBox(
                  width: double.infinity,
                  child: PrimaryButton(
                    label: 'Place order · ${Money.fromPaise(total)}',
                    onPressed: _busy ? null : _showConfirmSheet,
                    loading: _busy,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
//  Heterogeneous line list — switches on CartLine type.
// ---------------------------------------------------------------------------
class _LineList extends ConsumerWidget {
  final List<CartLine> lines;
  const _LineList({required this.lines});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        for (final l in lines) ...[
          _LineCard(line: l),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _LineCard extends ConsumerWidget {
  final CartLine line;
  const _LineCard({required this.line});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(cartProvider.notifier);
    final (
      Color accent,
      IconData fallbackIcon,
      String typeLabel,
      String? imageUrl,
    ) = switch (line) {
      MenuItemLine m when m.brand == 'coffee' => (
        AppColors.coffeeBrown,
        PhosphorIconsRegular.coffee,
        'COFFEE',
        m.imageUrl,
      ),
      MenuItemLine m => (
        AppColors.fitGreen,
        PhosphorIconsRegular.carrot,
        'FIT',
        m.imageUrl,
      ),
      ComboLine c => (
        AppColors.gold,
        PhosphorIconsFill.gift,
        'COMBO',
        c.imageUrl,
      ),
      FitMealLine f => (
        AppColors.fitGreen,
        PhosphorIconsRegular.bowlFood,
        'FIT MEAL',
        f.imageUrl,
      ),
    };

    final card = Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.20)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Container(
              width: 56,
              height: 56,
              color: accent.withValues(alpha: 0.12),
              child: imageUrl != null && imageUrl.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: imageUrl,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Center(
                        child: Icon(fallbackIcon, color: accent, size: 22),
                      ),
                      errorWidget: (_, __, ___) => Center(
                        child: Icon(fallbackIcon, color: accent, size: 22),
                      ),
                    )
                  : Center(child: Icon(fallbackIcon, color: accent, size: 22)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  typeLabel,
                  style: AppTextStyles.caption(
                    context,
                    color: accent,
                  ).copyWith(letterSpacing: 1.2, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 2),
                Text(line.displayName, style: AppTextStyles.body(context)),
                if (line case ComboLine(
                  linkedFitSelectionsSummary: final fitSummary,
                  linkedFitTemplateName: final fitName,
                ) when fitSummary.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      fitName != null
                          ? '$fitName · ${fitSummary.join(' · ')}'
                          : fitSummary.join(' · '),
                      style: AppTextStyles.caption(
                        context,
                        color: AppColors.lightTextSecondary,
                      ),
                    ),
                  )
                else if (line case ComboLine(
                  includedItemNames: final names,
                ) when names.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      names.join(' · '),
                      style: AppTextStyles.caption(
                        context,
                        color: AppColors.lightTextSecondary,
                      ),
                    ),
                  ),
                if (line case FitMealLine(
                  selectionsSummary: final summary,
                ) when summary.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      summary.join(' · '),
                      style: AppTextStyles.caption(
                        context,
                        color: AppColors.lightTextSecondary,
                      ),
                    ),
                  ),
                const SizedBox(height: 4),
                Text(
                  Money.fromPaise(line.linePaise),
                  style: AppTextStyles.caption(
                    context,
                    color: AppColors.lightTextSecondary,
                  ),
                ),
              ],
            ),
          ),
          QuantityStepper(lineId: line.id, currentQty: line.quantity),
        ],
      ),
    );

    return Dismissible(
      key: ValueKey(line.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        decoration: BoxDecoration(
          color: AppColors.adminRed.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(
          PhosphorIconsRegular.trash,
          color: AppColors.adminRed,
        ),
      ),
      onDismissed: (_) => notifier.removeLineById(line.id),
      child: card,
    );
  }
}

class _Summary extends StatelessWidget {
  final int foodPaise;
  final int foodGstPaise;
  final double foodGstPct;
  final int comboPaise;
  final int roundingPaise;
  final int totalPaise;
  final int coinsEarned;
  const _Summary({
    required this.foodPaise,
    required this.foodGstPaise,
    required this.foodGstPct,
    required this.comboPaise,
    required this.roundingPaise,
    required this.totalPaise,
    required this.coinsEarned,
  });

  @override
  Widget build(BuildContext context) {
    final pct = foodGstPct == foodGstPct.roundToDouble()
        ? foodGstPct.toInt().toString()
        : foodGstPct.toString();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        children: [
          if (foodPaise > 0) ...[
            _SummaryRow(label: 'Subtotal', value: Money.fromPaise(foodPaise)),
            _SummaryRow(
              label: 'GST $pct%',
              value: Money.fromPaise(foodGstPaise),
            ),
          ],
          if (comboPaise > 0)
            _SummaryRow(
              label: 'Combos (incl. play & GST)',
              value: Money.fromPaise(comboPaise),
            ),
          if (roundingPaise != 0)
            _SummaryRow(
              label: 'Rounding',
              value:
                  (roundingPaise > 0 ? '+' : '') +
                  Money.fromPaise(roundingPaise),
              muted: true,
            ),
          const Divider(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Total', style: AppTextStyles.bodyLarge(context)),
              Text(
                Money.fromPaise(totalPaise),
                style: AppTextStyles.h3(context, color: AppColors.navy),
              ),
            ],
          ),
          if (coinsEarned > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '+$coinsEarned Coins back',
                    style: AppTextStyles.caption(
                      context,
                      color: AppColors.gold,
                    ),
                  ),
                  const Icon(
                    PhosphorIconsFill.star,
                    color: AppColors.gold,
                    size: 14,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final bool muted;
  const _SummaryRow({
    required this.label,
    required this.value,
    this.muted = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = muted ? AppColors.lightTextSecondary : null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: AppTextStyles.body(context, color: color)),
          Text(value, style: AppTextStyles.body(context, color: color)),
        ],
      ),
    );
  }
}

class _FulfillmentSelector extends ConsumerWidget {
  const _FulfillmentSelector();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(cartFulfillmentProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            'Fulfillment',
            style: AppTextStyles.caption(context).copyWith(
              letterSpacing: 1.0,
              color: AppColors.lightTextSecondary,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(height: 4),
        // Customers see only Dine in / Takeaway. The tableService enum
        // value still exists for staff/admin flows and legacy orders, but
        // we don't surface it as a customer-facing pick.
        for (final m in const [
          FulfillmentMode.dineIn,
          FulfillmentMode.takeaway,
        ])
          SelectableCard<FulfillmentMode>(
            value: m,
            groupValue: selected,
            title: m.label,
            leading: Icon(
              m == FulfillmentMode.dineIn
                  ? PhosphorIconsRegular.bowlFood
                  : PhosphorIconsRegular.bag,
              color: AppColors.navy,
              size: 24,
            ),
            onChanged: (v) =>
                ref.read(cartFulfillmentProvider.notifier).state = v ?? m,
          ),
      ],
    );
  }
}

class _PaymentSelector extends ConsumerWidget {
  final int walletBalance;
  final int requiredPaise;
  const _PaymentSelector({
    required this.walletBalance,
    required this.requiredPaise,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(cartPaymentMethodProvider);
    final walletShort = walletBalance < requiredPaise;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            'Payment',
            style: AppTextStyles.caption(context).copyWith(
              letterSpacing: 1.0,
              color: AppColors.lightTextSecondary,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(height: 4),
        SelectableCard<CartPaymentMethod>(
          value: CartPaymentMethod.wallet,
          groupValue: selected,
          title: 'Wallet (${Money.fromPaise(walletBalance)})',
          subtitle: walletShort
              ? 'Not enough balance'
              : 'Pay instantly from wallet',
          leading: const Icon(
            PhosphorIconsFill.wallet,
            color: AppColors.navy,
            size: 24,
          ),
          onChanged: (v) => ref.read(cartPaymentMethodProvider.notifier).state =
              v ?? CartPaymentMethod.wallet,
        ),
        SelectableCard<CartPaymentMethod>(
          value: CartPaymentMethod.cash,
          groupValue: selected,
          title: 'Pay at counter',
          subtitle: 'Pay when you pick up',
          leading: const Icon(
            PhosphorIconsRegular.money,
            color: AppColors.navy,
            size: 24,
          ),
          onChanged: (v) => ref.read(cartPaymentMethodProvider.notifier).state =
              v ?? CartPaymentMethod.cash,
        ),
      ],
    );
  }
}

class _EmptyBag extends StatelessWidget {
  const _EmptyBag();
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(32, 24, 32, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.lightBorder,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 24),
          const Icon(
            PhosphorIconsRegular.shoppingBag,
            size: 56,
            color: AppColors.lightTextSecondary,
          ),
          const SizedBox(height: 12),
          Text('Your bag is empty', style: AppTextStyles.h3(context)),
          const SizedBox(height: 4),
          Text(
            'Browse Cafe, FIT, or Combos to add something.',
            style: AppTextStyles.body(
              context,
              color: AppColors.lightTextSecondary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Browse menu'),
          ),
        ],
      ),
    );
  }
}

class _OrderPlacedView extends StatelessWidget {
  const _OrderPlacedView();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          PhosphorIconsFill.checkCircle,
          size: 64,
          color: AppColors.fitGreen,
        ),
        const SizedBox(height: 16),
        Text('Order placed!', style: AppTextStyles.h2(context)),
        const SizedBox(height: 8),
        Text(
          'Taking you to your order...',
          style: AppTextStyles.body(
            context,
            color: AppColors.lightTextSecondary,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
