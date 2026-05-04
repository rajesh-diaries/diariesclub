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
import 'widgets/order_status_timeline.dart';

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

    return Scaffold(
      appBar: AppBar(
        title: Text('Order #${orderId.substring(0, 6)}'),
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
          return _Body(
            order: order,
            items: itemsAsync.valueOrNull ?? const [],
          );
        },
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  final Map<String, dynamic> order;
  final List<Map<String, dynamic>> items;
  const _Body({required this.order, required this.items});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = (order['status'] as String?) ?? 'pending';
    final subtotal = (order['subtotal_paise'] as int?) ?? 0;
    final gst = (order['gst_paise'] as int?) ?? 0;
    final total = (order['total_paise'] as int?) ?? 0;
    final coins = (order['coins_earned'] as int?) ?? 0;
    final payment = (order['payment_method'] as String?) ?? '—';
    final fulfillment = (order['fulfillment_mode'] as String?) ?? '—';

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _StatusHero(status: status),
            const SizedBox(height: 24),
            OrderStatusTimeline(currentStatus: status),
            const SizedBox(height: 16),
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
                  _kv(context, 'Subtotal', Money.fromPaise(subtotal)),
                  _kv(context, 'GST', Money.fromPaise(gst)),
                  _kv(
                    context,
                    'Total',
                    Money.fromPaise(total),
                    bold: true,
                  ),
                  if (coins > 0) ...[
                    const SizedBox(height: 4),
                    Text(
                      '+$coins Diaries Coins earned',
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
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.lightBackground,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(
                    PhosphorIconsRegular.envelope,
                    color: AppColors.navy,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Invoice will be emailed.',
                      style: AppTextStyles.caption(
                        context,
                        color: AppColors.lightTextSecondary,
                      ),
                    ),
                  ),
                ],
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
        'wallet' => 'Diaries Wallet',
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
