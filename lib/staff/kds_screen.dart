import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_text_styles.dart';
import 'providers/venue_streams_provider.dart';

/// Kitchen Display System. Three tabs (Pending / Preparing / Ready). Each
/// card shows the order's items + age; the primary action advances status
/// (pending → preparing → ready → served). Realtime: customer's order
/// tracker reflects the same status flips within a couple of seconds.
class KdsScreen extends ConsumerStatefulWidget {
  const KdsScreen({super.key});

  @override
  ConsumerState<KdsScreen> createState() => _KdsScreenState();
}

class _KdsScreenState extends ConsumerState<KdsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(length: 3, vsync: this);

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final orders = ref.watch(venueOrdersProvider).valueOrNull ?? const [];
    final pending = orders.where((o) => o['status'] == 'pending').toList();
    final preparing =
        orders.where((o) => o['status'] == 'preparing').toList();
    final ready = orders.where((o) => o['status'] == 'ready').toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Kitchen'),
        bottom: TabBar(
          controller: _tab,
          tabs: [
            Tab(text: 'Pending (${pending.length})'),
            Tab(text: 'Preparing (${preparing.length})'),
            Tab(text: 'Ready (${ready.length})'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          _OrdersList(orders: pending, nextStatus: 'preparing'),
          _OrdersList(orders: preparing, nextStatus: 'ready'),
          _OrdersList(orders: ready, nextStatus: 'served'),
        ],
      ),
    );
  }
}

class _OrdersList extends StatelessWidget {
  final List<Map<String, dynamic>> orders;
  final String nextStatus;
  const _OrdersList({required this.orders, required this.nextStatus});

  @override
  Widget build(BuildContext context) {
    if (orders.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text('No orders here'),
        ),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 360,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: 0.95,
      ),
      itemCount: orders.length,
      itemBuilder: (_, i) =>
          _OrderCard(order: orders[i], nextStatus: nextStatus),
    );
  }
}

class _OrderCard extends ConsumerStatefulWidget {
  final Map<String, dynamic> order;
  final String nextStatus;
  const _OrderCard({required this.order, required this.nextStatus});

  @override
  ConsumerState<_OrderCard> createState() => _OrderCardState();
}

class _OrderCardState extends ConsumerState<_OrderCard> {
  bool _busy = false;
  List<Map<String, dynamic>>? _items;

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  Future<void> _loadItems() async {
    final rows = await Supabase.instance.client
        .from('order_items')
        .select()
        .eq('order_id', widget.order['id'] as String)
        .order('created_at', ascending: true);
    if (!mounted) return;
    setState(() {
      _items = (rows as List)
          .map((r) => Map<String, dynamic>.from(r as Map))
          .toList();
    });
  }

  Future<void> _advance() async {
    setState(() => _busy = true);
    try {
      await Supabase.instance.client
          .from('orders')
          .update({'status': widget.nextStatus})
          .eq('id', widget.order['id'] as String);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _ctaLabel() => switch (widget.nextStatus) {
        'preparing' => 'Mark preparing →',
        'ready' => 'Mark ready →',
        'served' => 'Mark served ✓',
        _ => '',
      };

  Color _ageColor(int minutes) {
    if (minutes >= 15) return AppColors.adminRed;
    if (minutes >= 10) return AppColors.warningYellow;
    return AppColors.activeGreen;
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.order;
    final created = DateTime.tryParse(o['created_at'] as String? ?? '');
    final ageMin =
        created == null ? 0 : DateTime.now().difference(created).inMinutes;
    final isOld = ageMin >= 15;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.lightSurface,
        border: Border.all(
          color: isOld ? AppColors.adminRed : AppColors.lightBorder,
          width: isOld ? 2 : 1,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '#${(o['id'] as String).substring(0, 4).toUpperCase()}',
                  style: AppTextStyles.h3(context),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _ageColor(ageMin).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Text(
                  '${ageMin}m',
                  style: AppTextStyles.caption(
                    context,
                    color: _ageColor(ageMin),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            o['fulfillment_mode'] as String? ?? '',
            style: AppTextStyles.caption(
              context,
              color: AppColors.lightTextSecondary,
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _items == null
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    children: _renderItems(_items!, context),
                  ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _busy ? null : _advance,
              style: FilledButton.styleFrom(backgroundColor: AppColors.navy),
              icon: const Icon(PhosphorIconsRegular.arrowRight, size: 16),
              label: Text(_ctaLabel()),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _renderItems(
    List<Map<String, dynamic>> items,
    BuildContext context,
  ) {
    final byBrand = <String, List<Map<String, dynamic>>>{};
    for (final i in items) {
      final brand = (i['brand'] as String?) ?? 'misc';
      byBrand.putIfAbsent(brand, () => []).add(i);
    }
    final out = <Widget>[];
    byBrand.forEach((brand, list) {
      out.add(Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          brand.toUpperCase(),
          style: AppTextStyles.caption(
            context,
            color: AppColors.lightTextSecondary,
          ).copyWith(letterSpacing: 1.5, fontWeight: FontWeight.w800),
        ),
      ));
      for (final i in list) {
        final qty = (i['quantity'] as int?) ?? 1;
        final name = (i['name_snapshot'] as String?) ?? '';
        out.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Text(
            '• $name${qty > 1 ? ' ×$qty' : ''}',
            style: AppTextStyles.body(context),
          ),
        ));
      }
    });
    return out;
  }
}
