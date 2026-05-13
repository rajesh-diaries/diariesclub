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
  Map<String, dynamic>? _family;

  @override
  void initState() {
    super.initState();
    _loadItems();
    _loadFamily();
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

  Future<void> _loadFamily() async {
    final familyId = widget.order['family_id'] as String?;
    if (familyId == null) return;
    try {
      final row = await Supabase.instance.client
          .from('families')
          .select('id, name, phone')
          .eq('id', familyId)
          .maybeSingle();
      if (!mounted) return;
      setState(() => _family = row);
    } catch (_) {
      // Walk-in / synthetic family — leave _family null; card shows
      // "Walk-in" as a fallback.
    }
  }

  Future<void> _advance() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await Supabase.instance.client.rpc<dynamic>(
        'staff_order_advance_status',
        params: {
          'p_order_id': widget.order['id'] as String,
          'p_new_status': widget.nextStatus,
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.activeGreen,
          content: Text('Moved to ${widget.nextStatus}.'),
        ),
      );
    } on PostgrestException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Couldn't advance: ${e.message}")),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Couldn't advance: $e")),
      );
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

  /// "3m" / "12m" / "1h 5m" / "2d ago" — better than raw minutes once
  /// orders age past an hour.
  String _ageLabel(int minutes) {
    if (minutes < 60) return '${minutes}m';
    if (minutes < 60 * 24) {
      final h = minutes ~/ 60;
      final m = minutes % 60;
      return m == 0 ? '${h}h' : '${h}h ${m}m';
    }
    return '${minutes ~/ (60 * 24)}d ago';
  }

  String _modeLabel(String mode) => switch (mode) {
        'table_service' => 'Table',
        'pickup' => 'Pickup',
        'dine_in' => 'Dine-in',
        _ => mode.replaceAll('_', ' '),
      };

  @override
  Widget build(BuildContext context) {
    final o = widget.order;
    final created = DateTime.tryParse(o['created_at'] as String? ?? '');
    final ageMin =
        created == null ? 0 : DateTime.now().difference(created).inMinutes;
    final isOld = ageMin >= 15;
    final customerName = (_family?['name'] as String?) ?? 'Walk-in';
    final shortId = (o['id'] as String).substring(0, 4).toUpperCase();
    final mode = (o['fulfillment_mode'] as String?) ?? '';

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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ID first + customer — two orders from the same
                    // family stay visually distinct ("#08CE Rajesh"
                    // vs "#7D67 Rajesh").
                    RichText(
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      text: TextSpan(
                        style: AppTextStyles.bodyLarge(context),
                        children: [
                          TextSpan(
                            text: '#$shortId  ',
                            style: const TextStyle(
                              color: AppColors.navy,
                              fontWeight: FontWeight.w900,
                              fontFamily: 'monospace',
                            ),
                          ),
                          TextSpan(
                            text: customerName,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      _modeLabel(mode),
                      style: AppTextStyles.caption(
                        context,
                        color: AppColors.lightTextSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _ageColor(ageMin).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Text(
                  _ageLabel(ageMin),
                  style: AppTextStyles.caption(
                    context,
                    color: _ageColor(ageMin),
                  ).copyWith(fontWeight: FontWeight.w800),
                ),
              ),
            ],
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
