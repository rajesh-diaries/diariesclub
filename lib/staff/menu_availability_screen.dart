import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_text_styles.dart';
import 'providers/staff_auth_provider.dart';
import 'widgets/staff_pin_sheet.dart';

/// Two-tab (Coffee / FIT) toggle for menu items at this venue. Tapping
/// the switch opens the PIN sheet; on success, updates menu_items.
/// is_available + drops an audit_log row.
class MenuAvailabilityScreen extends ConsumerStatefulWidget {
  const MenuAvailabilityScreen({super.key});

  @override
  ConsumerState<MenuAvailabilityScreen> createState() =>
      _MenuAvailabilityScreenState();
}

class _MenuAvailabilityScreenState
    extends ConsumerState<MenuAvailabilityScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(length: 2, vsync: this);

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Menu availability'),
        bottom: TabBar(
          controller: _tab,
          tabs: const [Tab(text: 'Coffee'), Tab(text: 'FIT')],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: const [
          _ItemsList(brand: 'coffee'),
          _ItemsList(brand: 'fit'),
        ],
      ),
    );
  }
}

class _ItemsList extends ConsumerStatefulWidget {
  final String brand;
  const _ItemsList({required this.brand});

  @override
  ConsumerState<_ItemsList> createState() => _ItemsListState();
}

class _ItemsListState extends ConsumerState<_ItemsList> {
  late final Stream<List<Map<String, dynamic>>> _stream = _build();

  Stream<List<Map<String, dynamic>>> _build() async* {
    final venueId = ref.read(currentTabletVenueIdProvider);
    if (venueId == null) {
      yield const [];
      return;
    }
    // The menu items stream is filtered to this venue's brand via a join,
    // and Realtime fires on every menu_items update.
    final s = Supabase.instance.client
        .from('menu_items')
        .stream(primaryKey: ['id'])
        .order('sort_order');
    await for (final rows in s) {
      final menus = await Supabase.instance.client
          .from('menus')
          .select('id')
          .eq('venue_id', venueId)
          .eq('brand', widget.brand);
      final allowedMenuIds = (menus as List).map((m) => m['id']).toSet();
      yield rows.where((r) => allowedMenuIds.contains(r['menu_id'])).toList();
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _stream,
      builder: (c, snap) {
        final items = snap.data ?? const [];
        if (snap.connectionState == ConnectionState.waiting && items.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }
        if (items.isEmpty) {
          return const Center(child: Text('No items.'));
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: items.length,
          separatorBuilder: (_, __) =>
              const Divider(height: 1, color: AppColors.lightBorder),
          itemBuilder: (_, i) => _ItemRow(item: items[i]),
        );
      },
    );
  }
}

class _ItemRow extends ConsumerStatefulWidget {
  final Map<String, dynamic> item;
  const _ItemRow({required this.item});

  @override
  ConsumerState<_ItemRow> createState() => _ItemRowState();
}

class _ItemRowState extends ConsumerState<_ItemRow> {
  bool? _localValue; // optimistic toggle while waiting for stream echo

  Future<void> _toggle(bool newValue) async {
    final staff = await StaffPinSheet.show(
      context,
      actionLabel:
          '${newValue ? 'Enable' : 'Disable'} ${widget.item['name'] ?? 'item'}',
    );
    if (staff == null) return;
    setState(() => _localValue = newValue);
    final venueId = ref.read(currentTabletVenueIdProvider);
    try {
      await Supabase.instance.client
          .from('menu_items')
          .update({
            'is_available': newValue,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', widget.item['id'] as String);

      await Supabase.instance.client.from('audit_log').insert({
        'actor_id': staff.staffId,
        'actor_type': 'staff',
        'action': newValue ? 'menu.enable' : 'menu.disable',
        'entity_type': 'menu_item',
        'entity_id': widget.item['id'],
        'venue_id': venueId,
        'new_value': {'is_available': newValue},
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _localValue = !newValue);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't update.")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final value = _localValue ?? (widget.item['is_available'] == true);
    return SwitchListTile(
      title: Text(
        widget.item['name'] as String? ?? '—',
        style: AppTextStyles.body(context),
      ),
      subtitle: widget.item['description'] != null
          ? Text(
              widget.item['description'] as String,
              style: AppTextStyles.caption(
                context,
                color: AppColors.lightTextSecondary,
              ),
            )
          : null,
      value: value,
      onChanged: _toggle,
    );
  }
}
