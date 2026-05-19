import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/providers/venue_config_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/currency.dart';
import '../../core/widgets/error_screen.dart';
import 'providers/order_stream_provider.dart';

/// Realtime order tracking. Subscribes to a single `orders` row + a
/// one-shot `order_items` fetch (line items don't mutate after insert).
/// On status flips to "ready" we'd fire a local notification (Session 12
/// wires firebase_messaging + flutter_local_notifications properly; for
/// now the screen-state animation alone is enough).
class OrderTrackingScreen extends ConsumerWidget {
  final String orderId;
  const OrderTrackingScreen({super.key, required this.orderId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orderAsync = ref.watch(orderStreamProvider(orderId));
    final itemsAsync = ref.watch(orderItemsProvider(orderId));

    final invoice = orderAsync.valueOrNull?['invoice_number'] as String?;
    return Scaffold(
      appBar: AppBar(
        title: Text(invoice ?? 'Order #${orderId.substring(0, 6)}'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/club'),
        ),
      ),
      body: orderAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => FriendlyErrorScreen(
          code: 'E-ORD',
          userMessage: "Couldn't load order",
          technicalDetails: e.toString(),
        ),
        data: (order) {
          if (order == null) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text("This order doesn't exist."),
              ),
            );
          }
          final cfg = ref.watch(venueConfigProvider).valueOrNull ?? const {};
          return _Body(
            order: order,
            items: itemsAsync.valueOrNull ?? const [],
            cfg: cfg,
          );
        },
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  final Map<String, dynamic> order;
  final List<Map<String, dynamic>> items;
  final Map<String, dynamic> cfg;
  const _Body({
    required this.order,
    required this.items,
    required this.cfg,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = (order['status'] as String?) ?? 'pending';
    final gst = (order['gst_paise'] as int?) ?? 0;
    final total = (order['total_paise'] as int?) ?? 0;
    final coins = (order['coins_earned'] as int?) ?? 0;
    final payment = (order['payment_method'] as String?) ?? '—';
    final fulfillment = (order['fulfillment_mode'] as String?) ?? '—';
    final invoice = order['invoice_number'] as String?;
    final customerGstin = order['customer_gstin'] as String?;
    final foodTaxable = (order['food_taxable_paise'] as int?) ?? 0;
    final foodGst = (order['food_gst_paise'] as int?) ?? 0;
    final sessionValue = (order['session_value_paise'] as int?) ?? 0;
    final sessionTaxable = (order['session_taxable_paise'] as int?) ?? 0;
    final sessionGst = (order['session_gst_paise'] as int?) ?? 0;
    final rounding = (order['rounding_paise'] as int?) ?? 0;
    // New orders carry the split fields; pre-0100 orders fall back to
    // the legacy single-rate display.
    final hasSplit = foodTaxable > 0 || sessionValue > 0;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _StatusHero(status: status),
            const SizedBox(height: 24),
            if (invoice != null) ...[
              _TaxInvoiceHeader(
                cfg: cfg,
                invoiceNumber: invoice,
                customerGstin: customerGstin,
                createdAt: order['created_at'] as String?,
              ),
              const SizedBox(height: 16),
            ],
            _Section(
              title: 'Order details',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final i in items)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${i['name_snapshot']} × ${i['quantity']}',
                              style: AppTextStyles.body(context),
                            ),
                          ),
                          Text(
                            Money.fromPaise(
                              ((i['unit_price_paise'] as int?) ?? 0) *
                                  ((i['quantity'] as int?) ?? 0),
                            ),
                            style: AppTextStyles.body(context),
                          ),
                        ],
                      ),
                    ),
                  const Divider(),
                  if (hasSplit) ...[
                    if (foodTaxable > 0) ...[
                      _kv(context, 'Food (taxable)',
                          Money.fromPaise(foodTaxable)),
                      _kv(context, 'GST 5% (food)',
                          Money.fromPaise(foodGst)),
                    ],
                    if (sessionValue > 0) ...[
                      _kv(context, 'Play session (incl. GST)',
                          Money.fromPaise(sessionValue)),
                      Padding(
                        padding: const EdgeInsets.only(left: 12, bottom: 2),
                        child: Text(
                          'incl. ${Money.fromPaise(sessionGst)} GST '
                          '@ 18% on ${Money.fromPaise(sessionTaxable)}',
                          style: AppTextStyles.caption(
                            context,
                            color: AppColors.lightTextSecondary,
                          ),
                        ),
                      ),
                    ],
                    if (rounding != 0)
                      _kv(
                        context,
                        'Rounding',
                        (rounding > 0 ? '+' : '') + Money.fromPaise(rounding),
                      ),
                    const Divider(),
                  ],
                  _kv(
                    context,
                    'Total',
                    Money.fromPaise(total),
                    bold: true,
                  ),
                  if (!hasSplit && gst > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        'Includes ${Money.fromPaise(gst)} GST',
                        style: AppTextStyles.caption(
                          context,
                          color: AppColors.lightTextSecondary,
                        ),
                      ),
                    ),
                  // Invoice number + buyer GSTIN render in the
                  // _TaxInvoiceHeader above; no duplicates here.
                  if (coins > 0) ...[
                    const SizedBox(height: 4),
                    Text(
                      '+$coins Coins earned',
                      style: AppTextStyles.caption(
                        context,
                        color: AppColors.gold,
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Text(
                    'Paid via ${_paymentLabel(payment)}',
                    style: AppTextStyles.caption(
                      context,
                      color: AppColors.lightTextSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _Section(
              title: 'Fulfillment',
              child: Text(
                _fulfillmentLabel(fulfillment),
                style: AppTextStyles.body(context),
              ),
            ),
            const SizedBox(height: 16),
            const _Help(),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _kv(BuildContext c, String k, String v, {bool bold = false}) {
    final style =
        bold ? AppTextStyles.bodyLarge(c) : AppTextStyles.body(c);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(k, style: style),
          Text(v, style: style),
        ],
      ),
    );
  }

  String _paymentLabel(String p) => switch (p) {
        'wallet' => 'Wallet',
        'cash' => 'cash at counter',
        'razorpay' => 'Razorpay',
        _ => p,
      };

  String _fulfillmentLabel(String f) => switch (f) {
        'dine_in' => 'Dine in',
        'takeaway' => 'Takeaway',
        'table_service' => 'Table service — bringing it over',
        _ => f,
      };
}

class _StatusHero extends StatelessWidget {
  final String status;
  const _StatusHero({required this.status});

  @override
  Widget build(BuildContext context) {
    final (title, subtitle, color, icon) = switch (status) {
      'pending' => (
          'Order received',
          'We just got it.',
          AppColors.gold,
          PhosphorIconsFill.checkCircle,
        ),
      'preparing' => (
          'Preparing your order',
          'Estimated time: 8 min',
          AppColors.gold,
          PhosphorIconsFill.fire,
        ),
      'ready' => (
          'Ready for pickup',
          'Come collect at the counter.',
          AppColors.activeGreen,
          PhosphorIconsFill.bell,
        ),
      'served' => (
          'Enjoy!',
          'Hope it hit the spot.',
          AppColors.activeGreen,
          PhosphorIconsFill.coffee,
        ),
      'cancelled' => (
          'Cancelled',
          'Refunded to your wallet.',
          AppColors.adminRed,
          PhosphorIconsFill.xCircle,
        ),
      _ => (
          status,
          '',
          AppColors.lightTextSecondary,
          PhosphorIconsFill.circle,
        ),
    };

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 36),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTextStyles.h3(context)),
                const SizedBox(height: 2),
                if (subtitle.isNotEmpty)
                  Text(
                    subtitle,
                    style: AppTextStyles.body(
                      context,
                      color: AppColors.lightTextSecondary,
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

class _Section extends StatelessWidget {
  final String title;
  final Widget child;
  const _Section({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.lightSurface,
        border: Border.all(color: AppColors.lightBorder),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: AppTextStyles.caption(
              context,
              color: AppColors.lightTextSecondary,
            ).copyWith(letterSpacing: 1.2, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

class _TaxInvoiceHeader extends StatelessWidget {
  final Map<String, dynamic> cfg;
  final String invoiceNumber;
  final String? customerGstin;
  final String? createdAt;
  const _TaxInvoiceHeader({
    required this.cfg,
    required this.invoiceNumber,
    required this.customerGstin,
    required this.createdAt,
  });

  @override
  Widget build(BuildContext context) {
    final bizName = (cfg['business_name'] as String?) ?? 'Play Diaries';
    final gstin = (cfg['gstin'] as String?) ?? '';
    final address = (cfg['venue_address'] as String?) ?? '';
    final phone = (cfg['venue_phone'] as String?) ?? '';
    final email = (cfg['venue_email'] as String?) ?? '';
    final dateStr =
        createdAt != null ? _formatDate(DateTime.tryParse(createdAt!)) : '';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.lightSurface,
        border: Border.all(color: AppColors.navy.withValues(alpha: 0.30)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'TAX INVOICE',
                style: AppTextStyles.caption(context, color: AppColors.navy)
                    .copyWith(letterSpacing: 1.6, fontWeight: FontWeight.w800),
              ),
              Text(
                invoiceNumber,
                style: AppTextStyles.bodyLarge(context, color: AppColors.navy),
              ),
            ],
          ),
          if (dateStr.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                dateStr,
                style: AppTextStyles.caption(
                  context,
                  color: AppColors.lightTextSecondary,
                ),
              ),
            ),
          const Divider(height: 16),
          Text(bizName, style: AppTextStyles.bodyLarge(context)),
          if (address.isNotEmpty)
            Text(
              address,
              style: AppTextStyles.caption(
                context,
                color: AppColors.lightTextSecondary,
              ),
            ),
          if (phone.isNotEmpty || email.isNotEmpty)
            Text(
              [phone, email].where((s) => s.isNotEmpty).join(' · '),
              style: AppTextStyles.caption(
                context,
                color: AppColors.lightTextSecondary,
              ),
            ),
          if (gstin.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'GSTIN $gstin',
                style: AppTextStyles.body(context, color: AppColors.navy)
                    .copyWith(fontWeight: FontWeight.w700),
              ),
            ),
          // Buyer GSTIN intentionally not shown — food at 5% GST has no
          // ITC under Indian GST regime, so capturing/displaying it adds
          // no value to the customer. Birthday-party invoices (18% on
          // services) live on a separate admin surface where ITC matters.
        ],
      ),
    );
  }

  String _formatDate(DateTime? dt) {
    if (dt == null) return '';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final local = dt.toLocal();
    return '${local.day} ${months[local.month - 1]} ${local.year}';
  }
}

class _Help extends ConsumerWidget {
  const _Help();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cfg = ref.watch(venueConfigProvider).valueOrNull ?? const {};
    final phone = (cfg['whatsapp_support_phone'] as String?) ?? '';
    final num = phone.replaceAll(RegExp(r'[^\d]'), '');
    return OutlinedButton.icon(
      onPressed: () async {
        if (num.isEmpty) return;
        final uri = Uri.parse(
          'https://wa.me/$num?text=${Uri.encodeComponent("I need help with my order.")}',
        );
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      },
      icon: const Icon(PhosphorIconsRegular.whatsappLogo),
      label: const Text('Talk to staff via WhatsApp'),
    );
  }
}
