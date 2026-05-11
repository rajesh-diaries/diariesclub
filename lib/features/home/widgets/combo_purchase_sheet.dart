import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../core/providers/active_sessions_provider.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/family_children_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/currency.dart';
import '../../club/providers/cart_provider.dart';

const _venueId = '00000000-0000-0000-0000-000000000001';

/// Modal sheet that handles a combo purchase straight from the home tab.
///
/// Two flows depending on the combo's inclusions:
///
/// 1. Combo with `session_minutes` set: includes a play session for one
///    kid. Shows kid picker (idle kids only). Pay button creates a
///    session via session_create AND adds the combo line to the cart so
///    staff sees the food order. Routes home; the new pending session
///    appears in the active stack.
///
/// 2. Combo without session_minutes: food-only. No kid picker. "Add to
///    bag" → combo line into cart, routes to /club for review/checkout.
class ComboPurchaseSheet extends ConsumerStatefulWidget {
  final Map<String, dynamic> combo;
  const ComboPurchaseSheet({super.key, required this.combo});

  @override
  ConsumerState<ComboPurchaseSheet> createState() =>
      _ComboPurchaseSheetState();
}

class _ComboPurchaseSheetState extends ConsumerState<ComboPurchaseSheet> {
  String? _selectedChildId;
  bool _busy = false;
  String? _errorText;
  List<Map<String, dynamic>> _itemRows = const [];

  @override
  void initState() {
    super.initState();
    _loadItemNames();
  }

  Future<void> _loadItemNames() async {
    final inclusions =
        (widget.combo['inclusions'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{};
    final ids = ((inclusions['menu_item_ids'] as List?) ?? const [])
        .cast<String>();
    if (ids.isEmpty) return;
    try {
      final rows = await Supabase.instance.client
          .from('menu_items_with_brand')
          .select('id, name, brand')
          .inFilter('id', ids);
      if (!mounted) return;
      setState(() {
        _itemRows = (rows as List)
            .map((r) => Map<String, dynamic>.from(r as Map))
            .toList();
      });
    } catch (_) {/* names just won't show; not blocking */}
  }

  void _addToBag() {
    final combo = widget.combo;
    final notifier = ref.read(cartProvider.notifier);
    notifier.addCombo(ComboLine.create(
      comboId: combo['id'] as String,
      name: (combo['name'] as String?) ?? 'Combo',
      unitPricePaise: (combo['price_paise'] as int?) ?? 0,
      quantity: 1,
      imageUrl: combo['cover_image_url'] as String?,
      includedItemNames:
          _itemRows.map((r) => (r['name'] as String?) ?? '').toList(),
    ));
    Navigator.of(context).pop();
    context.go('/club');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${combo['name']} added to your bag')),
    );
  }

  /// Place the order straight from the sheet (food-only combos OR
  /// after a session was created for with-session combos).
  Future<void> _placeOrder({required bool withSession}) async {
    final combo = widget.combo;
    final familyId = ref.read(currentFamilyIdProvider);
    if (familyId == null) return;
    if (withSession && _selectedChildId == null) return;

    setState(() {
      _busy = true;
      _errorText = null;
    });

    try {
      // Step 1 — for with-session combos, create the session first so
      // the kid has a valid pass to walk in with. The session hold goes
      // against the wallet at the regular session price; the combo line
      // covers the food + bundled price reconciliation at order_place.
      if (withSession) {
        final inclusions =
            (combo['inclusions'] as Map?)?.cast<String, dynamic>() ??
                const <String, dynamic>{};
        final sessionMinutes =
            inclusions['session_minutes'] as int? ?? 60;
        await Supabase.instance.client
            .rpc<Map<String, dynamic>>('session_create', params: {
          'p_venue_id': _venueId,
          'p_family_id': familyId,
          'p_child_id': _selectedChildId,
          'p_duration_minutes': sessionMinutes,
          'p_payment_method': 'wallet',
          'p_idempotency_key': const Uuid().v4(),
        });
      }

      // Step 2 — place the order for the food side of the combo.
      final result = await Supabase.instance.client
          .rpc<Map<String, dynamic>>('order_place', params: {
        'p_venue_id': _venueId,
        'p_family_id': familyId,
        'p_items': [
          {
            'type': 'combo',
            'combo_id': combo['id'],
            'quantity': 1,
          }
        ],
        'p_fulfillment_mode': 'dine_in',
        'p_payment_method': 'wallet',
        'p_combo_id': null,
        'p_idempotency_key': const Uuid().v4(),
        'p_customer_gstin': null,
      });
      final orderId = result['order_id'] as String?;

      if (!mounted) return;
      Navigator.of(context).pop();
      if (withSession) {
        // Active session view shows the new pending session.
        context.go('/home');
      } else if (orderId != null) {
        context.push('/club/order/$orderId');
      } else {
        context.go('/club');
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            withSession
                ? "${combo['name']} purchased — session pending, food on the way"
                : "Order placed — we'll prep it now",
          ),
        ),
      );
    } on PostgrestException catch (e) {
      debugPrint('[COMBO_PURCHASE] PostgrestException: code=${e.code} '
          'message=${e.message} details=${e.details} hint=${e.hint}');
      if (!mounted) return;
      setState(() {
        _busy = false;
        _errorText = e.message.contains('insufficient_balance')
            ? 'Wallet balance is short. Top up to continue.'
            : "Couldn't purchase combo: ${e.message}";
      });
    } catch (e) {
      debugPrint('[COMBO_PURCHASE] generic error: $e');
      if (!mounted) return;
      setState(() {
        _busy = false;
        _errorText = "Couldn't purchase combo: $e";
      });
    }
  }


  @override
  Widget build(BuildContext context) {
    final combo = widget.combo;
    final inclusions =
        (combo['inclusions'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{};
    final sessionMinutes = inclusions['session_minutes'] as int?;
    final hasSession = sessionMinutes != null;
    final price = (combo['price_paise'] as int?) ?? 0;
    final cover = combo['cover_image_url'] as String?;
    final name = (combo['name'] as String?) ?? '';
    final desc = inclusions['description'] as String?;

    final allChildren =
        ref.watch(familyChildrenProvider).valueOrNull ?? const [];
    final inSession = ref.watch(childrenWithActiveSessionProvider);
    final idleChildren = allChildren
        .where((c) => !inSession.contains(c['id'] as String))
        .toList();

    if (hasSession && _selectedChildId == null && idleChildren.length == 1) {
      _selectedChildId = idleChildren.first['id'] as String;
    }

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (_, controller) => Container(
        decoration: const BoxDecoration(
          color: AppColors.lightBackground,
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: AppColors.lightBorder,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            if (cover != null && cover.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: CachedNetworkImage(
                    imageUrl: cover,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => Container(
                      color: AppColors.gold.withValues(alpha: 0.20),
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 16),
            Text(name, style: AppTextStyles.h2(context)),
            if (desc != null && desc.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                desc,
                style: AppTextStyles.body(
                  context,
                  color: AppColors.lightTextSecondary,
                ),
              ),
            ],
            const SizedBox(height: 20),
            if (hasSession) ...[
              Text("Who's playing?",
                  style: AppTextStyles.bodyLarge(context)),
              const SizedBox(height: 8),
              if (idleChildren.isEmpty)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.gold.withValues(alpha: 0.10),
                    border: Border.all(
                        color: AppColors.gold.withValues(alpha: 0.40)),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'All your kids are already playing. '
                    'Wrap up a session first to use this combo.',
                    style: AppTextStyles.body(context),
                  ),
                )
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final c in idleChildren)
                      _ChildRadioTile(
                        child: c,
                        selected: _selectedChildId == c['id'],
                        onTap: () => setState(
                            () => _selectedChildId = c['id'] as String),
                      ),
                  ],
                ),
              const SizedBox(height: 20),
            ],
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.lightSurface,
                border: Border.all(color: AppColors.lightBorder),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (hasSession)
                    _LineRow(
                      icon: PhosphorIconsRegular.clock,
                      label: '$sessionMinutes-minute play session',
                    ),
                  for (final r in _itemRows)
                    _LineRow(
                      icon: r['brand'] == 'fit'
                          ? PhosphorIconsRegular.carrot
                          : PhosphorIconsRegular.coffee,
                      label: (r['name'] as String?) ?? '—',
                    ),
                  const Divider(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Total',
                          style: AppTextStyles.body(context).copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      Text(
                        Money.fromPaise(price),
                        style: AppTextStyles.h3(
                          context,
                          color: AppColors.navy,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (_errorText != null) ...[
              const SizedBox(height: 12),
              Text(
                _errorText!,
                style: AppTextStyles.body(
                  context,
                  color: AppColors.adminRed,
                ),
              ),
            ],
            const SizedBox(height: 20),
            // Primary: place order straight from the sheet. Bypasses the
            // /club cart for the high-intent combo path.
            FilledButton(
              onPressed: _busy
                  ? null
                  : hasSession
                      ? (idleChildren.isEmpty || _selectedChildId == null
                          ? null
                          : () => _placeOrder(withSession: true))
                      : () => _placeOrder(withSession: false),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.navy,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: _busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation(Colors.white),
                      ),
                    )
                  : Text(
                      'Place order · ${Money.fromPaise(price)}',
                      style: AppTextStyles.body(context).copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
            ),
            // 'Add to bag' is only valid for food-only combos. Session
            // combos require a kid pick before order_place creates the
            // session — putting them in the cart would skip that step
            // and the customer would pay for play they never receive.
            if (!hasSession) ...[
              const SizedBox(height: 10),
              OutlinedButton(
                onPressed: _busy ? null : _addToBag,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text('Add to bag instead'),
              ),
            ],
            const SizedBox(height: 4),
            TextButton(
              onPressed:
                  _busy ? null : () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChildRadioTile extends StatelessWidget {
  final Map<String, dynamic> child;
  final bool selected;
  final VoidCallback onTap;
  const _ChildRadioTile({
    required this.child,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final name = (child['name'] as String?) ?? '—';
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.lightSurface,
          border: Border.all(
            color: selected ? AppColors.navy : AppColors.lightBorder,
            width: selected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              color: selected ? AppColors.navy : AppColors.lightBorder,
            ),
            const SizedBox(width: 12),
            Text(name, style: AppTextStyles.body(context)),
          ],
        ),
      ),
    );
  }
}

class _LineRow extends StatelessWidget {
  final IconData icon;
  final String label;
  const _LineRow({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.navy),
          const SizedBox(width: 10),
          Expanded(child: Text(label, style: AppTextStyles.body(context))),
        ],
      ),
    );
  }
}
