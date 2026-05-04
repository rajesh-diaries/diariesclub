import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../core/providers/venue_config_provider.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_text_styles.dart';
import '../core/utils/currency.dart';
import '../core/widgets/primary_button.dart';
import 'providers/staff_auth_provider.dart';

/// Walk-in cash checkout. Mode toggle Play / Food / Mixed:
///   - PLAY: 18% inclusive (uses venue_config.gst_percent)
///   - FOOD: 5% exclusive (uses venue_config.walkin_food_gst_percent)
///   - MIXED: both legs, billed independently per the rules above.
///
/// Submit calls walkin_checkout RPC, which creates a session and/or order
/// pointed at the venue's walk-in family with payment_method='cash_walkin'.
class WalkinPosScreen extends ConsumerStatefulWidget {
  final String staffId;
  const WalkinPosScreen({super.key, required this.staffId});

  @override
  ConsumerState<WalkinPosScreen> createState() => _WalkinPosScreenState();
}

class _WalkinPosScreenState extends ConsumerState<WalkinPosScreen> {
  String _mode = 'play';
  int _playMinutes = 60;
  final Map<String, int> _foodCart = {}; // menu_item_id → qty
  bool _busy = false;
  String? _errorText;

  List<Map<String, dynamic>> _menuItems = const [];

  @override
  void initState() {
    super.initState();
    _loadMenu();
  }

  Future<void> _loadMenu() async {
    final venueId = ref.read(currentTabletVenueIdProvider);
    if (venueId == null) return;
    final menus = await Supabase.instance.client
        .from('menus')
        .select('id, brand')
        .eq('venue_id', venueId)
        .eq('is_active', true);
    final menuIds = (menus as List).map((m) => m['id']).toList();
    final brandByMenu = {
      for (final m in menus) m['id']: m['brand'] as String,
    };
    final items = await Supabase.instance.client
        .from('menu_items')
        .select()
        .inFilter('menu_id', menuIds)
        .eq('is_available', true)
        .order('sort_order');
    if (!mounted) return;
    setState(() {
      _menuItems = (items as List)
          .map((r) => {
                ...Map<String, dynamic>.from(r as Map),
                'brand': brandByMenu[r['menu_id']],
              })
          .toList();
    });
  }

  int get _playSubtotal {
    final cfg = ref.read(venueConfigProvider).valueOrNull;
    if (cfg == null) return 0;
    return _playMinutes == 60
        ? (cfg['session_1hr_price_paise'] as int? ?? 80000)
        : (cfg['session_2hr_price_paise'] as int? ?? 110000);
  }

  int get _foodSubtotal {
    var total = 0;
    for (final entry in _foodCart.entries) {
      final item = _menuItems.firstWhere(
        (m) => m['id'] == entry.key,
        orElse: () => const <String, dynamic>{},
      );
      final price = (item['price_paise'] as int?) ?? 0;
      total += price * entry.value;
    }
    return total;
  }

  int get _foodGst {
    final cfg = ref.read(venueConfigProvider).valueOrNull;
    final pct = (cfg?['walkin_food_gst_percent'] as num?)?.toDouble() ?? 5.0;
    return (_foodSubtotal * pct / 100).ceil();
  }

  int get _grandTotal {
    var total = 0;
    if (_mode == 'play' || _mode == 'mixed') total += _playSubtotal;
    if (_mode == 'food' || _mode == 'mixed') total += _foodSubtotal + _foodGst;
    return total;
  }

  Future<void> _submit() async {
    final venueId = ref.read(currentTabletVenueIdProvider);
    if (venueId == null) return;

    if ((_mode == 'food' || _mode == 'mixed') && _foodCart.isEmpty) {
      setState(() => _errorText = 'Add at least one item.');
      return;
    }

    setState(() {
      _busy = true;
      _errorText = null;
    });

    final foodItems = _foodCart.entries
        .map((e) => {'menu_item_id': e.key, 'quantity': e.value})
        .toList();

    try {
      final res = await Supabase.instance.client
          .rpc<dynamic>('walkin_checkout', params: {
        'p_venue_id': venueId,
        'p_staff_pin_id': widget.staffId,
        'p_mode': _mode,
        'p_play_minutes':
            (_mode == 'play' || _mode == 'mixed') ? _playMinutes : null,
        'p_food_items': (_mode == 'food' || _mode == 'mixed')
            ? foodItems
            : null,
        'p_idempotency_key': const Uuid().v4(),
      });
      final r = Map<String, dynamic>.from(res as Map);
      if (!mounted) return;
      _showConfirmation(r);
    } on PostgrestException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _errorText = "Couldn't check out: ${e.message}";
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _errorText = "Couldn't check out.";
      });
    }
  }

  void _showConfirmation(Map<String, dynamic> r) {
    showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Walk-in checkout complete'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Total: ${Money.fromPaise((r['grand_total_paise'] as int?) ?? 0)}'),
            const SizedBox(height: 4),
            if (r['session_id'] != null)
              Text(
                'Play: ${Money.fromPaise((r['play_total_paise'] as int?) ?? 0)} (incl. GST)',
              ),
            if (r['order_id'] != null) ...[
              Text(
                'Food: ${Money.fromPaise((r['food_total_paise'] as int?) ?? 0)} (incl. ${Money.fromPaise((r['food_gst_paise'] as int?) ?? 0)} GST)',
              ),
            ],
            const SizedBox(height: 8),
            const Text(
              'Order has been added to KDS. Hand the customer their physical receipt.',
              style: TextStyle(fontStyle: FontStyle.italic),
            ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () {
              Navigator.of(c).pop();
              context.go('/staff/home');
            },
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Walk-in cash POS')),
      body: SafeArea(
        child: Column(
          children: [
            _ModeToggle(
              mode: _mode,
              onChanged: (m) => setState(() => _mode = m),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_mode == 'play' || _mode == 'mixed') ...[
                      _PlaySection(
                        minutes: _playMinutes,
                        subtotal: _playSubtotal,
                        onChanged: (v) => setState(() => _playMinutes = v),
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (_mode == 'food' || _mode == 'mixed') ...[
                      _FoodSection(
                        items: _menuItems,
                        cart: _foodCart,
                        onChanged: () => setState(() {}),
                      ),
                      const SizedBox(height: 16),
                      _FoodTotalsCard(
                        subtotal: _foodSubtotal,
                        gst: _foodGst,
                      ),
                    ],
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
            _StickyFooter(
              total: _grandTotal,
              busy: _busy,
              onSubmit: _grandTotal == 0 ? null : _submit,
            ),
          ],
        ),
      ),
    );
  }
}

class _ModeToggle extends StatelessWidget {
  final String mode;
  final ValueChanged<String> onChanged;
  const _ModeToggle({required this.mode, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      color: AppColors.lightBackground,
      child: SegmentedButton<String>(
        segments: const [
          ButtonSegment(
            value: 'play',
            label: Text('Play'),
            icon: Icon(PhosphorIconsRegular.gameController),
          ),
          ButtonSegment(
            value: 'food',
            label: Text('Food'),
            icon: Icon(PhosphorIconsRegular.cookingPot),
          ),
          ButtonSegment(
            value: 'mixed',
            label: Text('Mixed'),
            icon: Icon(PhosphorIconsRegular.stack),
          ),
        ],
        selected: {mode},
        onSelectionChanged: (s) => onChanged(s.first),
      ),
    );
  }
}

class _PlaySection extends StatelessWidget {
  final int minutes;
  final int subtotal;
  final ValueChanged<int> onChanged;
  const _PlaySection({
    required this.minutes,
    required this.subtotal,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.lightSurface,
        border: Border.all(color: AppColors.lightBorder),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Play (18% inclusive)',
              style: AppTextStyles.bodyLarge(context)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: ChoiceChip(
                  label: const Text('1 hour'),
                  selected: minutes == 60,
                  onSelected: (_) => onChanged(60),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ChoiceChip(
                  label: const Text('2 hours'),
                  selected: minutes == 120,
                  onSelected: (_) => onChanged(120),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Total (incl. 18% GST)',
                  style: AppTextStyles.body(context),
                ),
              ),
              Text(
                Money.fromPaise(subtotal),
                style: AppTextStyles.bodyLarge(context),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FoodSection extends StatelessWidget {
  final List<Map<String, dynamic>> items;
  final Map<String, int> cart;
  final VoidCallback onChanged;
  const _FoodSection({
    required this.items,
    required this.cart,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.lightSurface,
        border: Border.all(color: AppColors.lightBorder),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Food (5% exclusive — added on top)',
            style: AppTextStyles.bodyLarge(context),
          ),
          const SizedBox(height: 8),
          for (final item in items)
            _ItemRow(
              item: item,
              quantity: cart[item['id']] ?? 0,
              onAdd: () {
                cart[item['id'] as String] =
                    (cart[item['id']] ?? 0) + 1;
                onChanged();
              },
              onRemove: () {
                final id = item['id'] as String;
                final q = cart[id] ?? 0;
                if (q <= 1) {
                  cart.remove(id);
                } else {
                  cart[id] = q - 1;
                }
                onChanged();
              },
            ),
        ],
      ),
    );
  }
}

class _ItemRow extends StatelessWidget {
  final Map<String, dynamic> item;
  final int quantity;
  final VoidCallback onAdd;
  final VoidCallback onRemove;
  const _ItemRow({
    required this.item,
    required this.quantity,
    required this.onAdd,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item['name'] as String? ?? '—',
                  style: AppTextStyles.body(context),
                ),
                Text(
                  '${(item['brand'] as String?)?.toUpperCase() ?? ''} · ${Money.fromPaise((item['price_paise'] as int?) ?? 0)}',
                  style: AppTextStyles.caption(
                    context,
                    color: AppColors.lightTextSecondary,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(PhosphorIconsRegular.minusCircle),
            onPressed: quantity == 0 ? null : onRemove,
          ),
          SizedBox(
            width: 24,
            child: Center(
              child: Text(
                '$quantity',
                style: AppTextStyles.bodyLarge(context),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(PhosphorIconsRegular.plusCircle),
            onPressed: onAdd,
          ),
        ],
      ),
    );
  }
}

class _FoodTotalsCard extends StatelessWidget {
  final int subtotal;
  final int gst;
  const _FoodTotalsCard({required this.subtotal, required this.gst});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.lightBackground,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          _row(context, 'Subtotal', Money.fromPaise(subtotal)),
          _row(context, 'GST (5%)', Money.fromPaise(gst)),
          const Divider(),
          _row(context, 'Food total', Money.fromPaise(subtotal + gst),
              bold: true),
        ],
      ),
    );
  }

  Widget _row(BuildContext c, String label, String value,
          {bool bold = false}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Expanded(child: Text(label, style: AppTextStyles.body(c))),
            Text(
              value,
              style: bold
                  ? AppTextStyles.bodyLarge(c)
                  : AppTextStyles.body(c),
            ),
          ],
        ),
      );
}

class _StickyFooter extends StatelessWidget {
  final int total;
  final bool busy;
  final VoidCallback? onSubmit;
  const _StickyFooter({
    required this.total,
    required this.busy,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      decoration: const BoxDecoration(
        color: AppColors.lightSurface,
        border: Border(top: BorderSide(color: AppColors.lightBorder)),
      ),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Grand total',
                  style: AppTextStyles.caption(context)),
              Text(
                Money.fromPaise(total),
                style: AppTextStyles.h2(context, color: AppColors.gold),
              ),
            ],
          ),
          const Spacer(),
          SizedBox(
            width: 220,
            child: PrimaryButton(
              label: 'Take cash & checkout',
              loading: busy,
              onPressed: onSubmit,
            ),
          ),
        ],
      ),
    );
  }
}
