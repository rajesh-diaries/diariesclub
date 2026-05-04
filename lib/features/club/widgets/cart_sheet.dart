// ignore_for_file: deprecated_member_use
// ^ RadioListTile.groupValue/onChanged — see extend_session_sheet.dart.

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
import '../../../core/widgets/primary_button.dart';
import '../../sessions/widgets/insufficient_balance_sheet.dart';
import '../providers/cart_provider.dart';

const _venueId = '00000000-0000-0000-0000-000000000001';

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

  Future<void> _placeOrder() async {
    final cart = ref.read(cartProvider);
    if (cart.isEmpty) return;
    final familyId = ref.read(currentFamilyIdProvider);
    if (familyId == null) return;
    final fulfillment = ref.read(cartFulfillmentProvider);
    final payment = ref.read(cartPaymentMethodProvider);

    setState(() {
      _busy = true;
      _errorText = null;
    });

    final items = cart.isCombo ? cart.comboItems : cart.items;
    final body = items
        .map((i) => {
              'menu_item_id': i.menuItemId,
              'quantity': i.quantity,
            })
        .toList();
    final idem = const Uuid().v4();

    try {
      final result = await Supabase.instance.client
          .rpc<Map<String, dynamic>>('order_place', params: {
        'p_venue_id': _venueId,
        'p_family_id': familyId,
        'p_items': body,
        'p_fulfillment_mode': fulfillment.rpcValue,
        'p_payment_method': payment.rpcValue,
        'p_combo_id': cart.comboId,
        'p_idempotency_key': idem,
      });
      final orderId = result['order_id'] as String?;
      if (orderId == null) throw StateError('order_place returned no id');

      ref.read(cartProvider.notifier).clear();
      if (!mounted) return;
      Navigator.of(context).pop();
      context.push('/club/order/$orderId');
    } on PostgrestException catch (e) {
      if (!mounted) return;
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
        setState(() => _errorText =
            'An item just sold out. Please remove it from your bag.');
      } else if (e.message.contains('invalid_combo')) {
        setState(() =>
            _errorText = "That combo isn't available right now.");
      } else {
        setState(() => _errorText = "Couldn't place order. Please try again.");
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _errorText = "Couldn't place order. Please try again.";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);
    final balance = ref.watch(walletBalancePaiseProvider) ?? 0;
    final cfg = ref.watch(venueConfigProvider).valueOrNull ?? const {};
    final cashbackPct = (cfg['cashback_percent'] as num?)?.toDouble() ?? 7.0;
    final gstPct = (cfg['gst_percent'] as num?)?.toDouble() ?? 18.0;

    if (cart.isEmpty) return const _EmptyBag();

    final total = cart.totalPaise;
    final subtotal = (total * 100 / (100 + gstPct)).floor();
    final coins = (subtotal * cashbackPct / 100).floor();
    final payment = ref.watch(cartPaymentMethodProvider);

    return Container(
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
            padding:
                const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: Row(
              children: [
                Text('Your bag', style: AppTextStyles.h2(context)),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
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
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                children: [
                  if (cart.isCombo)
                    _ComboSection(
                      comboName: cart.comboName ?? 'Combo',
                      items: cart.comboItems,
                      onRemove: () =>
                          ref.read(cartProvider.notifier).removeCombo(),
                    )
                  else
                    _BrandSections(items: cart.items),
                  const SizedBox(height: 16),
                  _Summary(
                    subtotalPaise: subtotal,
                    gstPaise: total - subtotal,
                    totalPaise: total,
                    coinsEarned: payment == CartPaymentMethod.wallet ? coins : 0,
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
                  onPressed: _busy ? null : _placeOrder,
                  loading: _busy,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
//  Brand grouping
// ---------------------------------------------------------------------------
class _BrandSections extends ConsumerWidget {
  final List<CartItem> items;
  const _BrandSections({required this.items});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final byBrand = <String, List<CartItem>>{};
    for (final i in items) {
      byBrand.putIfAbsent(i.brand, () => []).add(i);
    }
    return Column(
      children: [
        if (byBrand['coffee'] != null) ...[
          _BrandSection(brand: 'coffee', items: byBrand['coffee']!),
          if (byBrand['fit'] != null) const SizedBox(height: 12),
        ],
        if (byBrand['fit'] != null)
          _BrandSection(brand: 'fit', items: byBrand['fit']!),
      ],
    );
  }
}

class _BrandSection extends ConsumerWidget {
  final String brand;
  final List<CartItem> items;
  const _BrandSection({required this.brand, required this.items});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = brand == 'coffee' ? AppColors.coffeeBrown : AppColors.fitGreen;
    final bg = color.withValues(alpha: 0.08);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                brand == 'coffee'
                    ? PhosphorIconsRegular.coffee
                    : PhosphorIconsRegular.carrot,
                color: color,
                size: 16,
              ),
              const SizedBox(width: 6),
              Text(
                brand.toUpperCase(),
                style: AppTextStyles.caption(context, color: color).copyWith(
                  letterSpacing: 1.4,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final i in items) _CartLine(item: i),
        ],
      ),
    );
  }
}

class _CartLine extends ConsumerWidget {
  final CartItem item;
  const _CartLine({required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${item.name} × ${item.quantity}',
                    style: AppTextStyles.body(context)),
                Text(
                  Money.fromPaise(item.linePaise),
                  style: AppTextStyles.caption(
                    context,
                    color: AppColors.lightTextSecondary,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () =>
                ref.read(cartProvider.notifier).changeQuantity(item.menuItemId, -1),
            icon: const Icon(Icons.remove_circle_outline),
            visualDensity: VisualDensity.compact,
          ),
          Text('${item.quantity}', style: AppTextStyles.bodyLarge(context)),
          IconButton(
            onPressed: () =>
                ref.read(cartProvider.notifier).changeQuantity(item.menuItemId, 1),
            icon: const Icon(Icons.add_circle_outline),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

class _ComboSection extends StatelessWidget {
  final String comboName;
  final List<CartItem> items;
  final VoidCallback onRemove;
  const _ComboSection({
    required this.comboName,
    required this.items,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.gold.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.40)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                PhosphorIconsFill.gift,
                color: AppColors.gold,
                size: 18,
              ),
              const SizedBox(width: 6),
              Text(
                'COMBO · $comboName'.toUpperCase(),
                style: AppTextStyles.caption(context, color: AppColors.gold)
                    .copyWith(
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: onRemove,
                child: const Text('Remove'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final i in items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  const Icon(Icons.check, size: 16, color: AppColors.activeGreen),
                  const SizedBox(width: 6),
                  Expanded(child: Text(i.name)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  final int subtotalPaise;
  final int gstPaise;
  final int totalPaise;
  final int coinsEarned;
  const _Summary({
    required this.subtotalPaise,
    required this.gstPaise,
    required this.totalPaise,
    required this.coinsEarned,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Total (incl. GST)',
                style: AppTextStyles.bodyLarge(context),
              ),
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
                    '+$coinsEarned Diaries Coins back',
                    style: AppTextStyles.caption(context, color: AppColors.gold),
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
        for (final m in FulfillmentMode.values)
          RadioListTile<FulfillmentMode>(
            value: m,
            groupValue: selected,
            title: Text(m.label),
            subtitle: m == FulfillmentMode.tableService
                ? const Text("We'll bring it to your table")
                : null,
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
        RadioListTile<CartPaymentMethod>(
          value: CartPaymentMethod.wallet,
          groupValue: selected,
          title: Text('Wallet (${Money.fromPaise(walletBalance)})'),
          subtitle: walletShort
              ? const Text(
                  'Not enough balance',
                  style: TextStyle(color: AppColors.adminRed),
                )
              : null,
          onChanged: (v) => ref.read(cartPaymentMethodProvider.notifier).state =
              v ?? CartPaymentMethod.wallet,
        ),
        RadioListTile<CartPaymentMethod>(
          value: CartPaymentMethod.cash,
          groupValue: selected,
          title: const Text('Pay at counter'),
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
            'Browse Coffee, FIT, or Combos to add something.',
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
