import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/currency.dart';
import '../providers/admin_auth_provider.dart';
import '../widgets/admin_app_bar.dart';
import '../widgets/admin_buttons.dart';

const _venueId = '00000000-0000-0000-0000-000000000001';

/// Customer detail. Loads family + wallet + recent sessions/orders/refunds
/// when the route is hit. Manual wallet adjust calls manual_wallet_adjust
/// (now is_admin gated).
class CustomerDetailScreen extends ConsumerStatefulWidget {
  final String familyId;
  final Map<String, dynamic>? preview;
  const CustomerDetailScreen({
    super.key,
    required this.familyId,
    this.preview,
  });

  @override
  ConsumerState<CustomerDetailScreen> createState() =>
      _CustomerDetailScreenState();
}

class _CustomerDetailScreenState extends ConsumerState<CustomerDetailScreen> {
  Map<String, dynamic>? _family;
  Map<String, dynamic>? _wallet;
  List<Map<String, dynamic>> _children = const [];
  List<Map<String, dynamic>> _sessions = const [];
  List<Map<String, dynamic>> _orders = const [];
  List<Map<String, dynamic>> _walletTxns = const [];
  bool _loading = true;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _errorText = null;
    });
    try {
      final family = await Supabase.instance.client
          .from('families')
          .select()
          .eq('id', widget.familyId)
          .single();
      final wallet = await Supabase.instance.client
          .from('wallets')
          .select()
          .eq('family_id', widget.familyId)
          .maybeSingle();
      final children = await Supabase.instance.client
          .from('children')
          .select()
          .eq('family_id', widget.familyId);
      final sessions = await Supabase.instance.client
          .from('sessions')
          .select()
          .eq('family_id', widget.familyId)
          .order('created_at', ascending: false)
          .limit(20);
      final orders = await Supabase.instance.client
          .from('orders')
          .select()
          .eq('family_id', widget.familyId)
          .order('created_at', ascending: false)
          .limit(20);
      final walletTxns = await Supabase.instance.client
          .from('wallet_transactions')
          .select()
          .eq('family_id', widget.familyId)
          .order('created_at', ascending: false)
          .limit(20);

      if (!mounted) return;
      setState(() {
        _family = Map<String, dynamic>.from(family);
        _wallet = wallet == null ? null : Map<String, dynamic>.from(wallet);
        _children = (children as List)
            .map((c) => Map<String, dynamic>.from(c as Map))
            .toList();
        _sessions = (sessions as List)
            .map((c) => Map<String, dynamic>.from(c as Map))
            .toList();
        _orders = (orders as List)
            .map((c) => Map<String, dynamic>.from(c as Map))
            .toList();
        _walletTxns = (walletTxns as List)
            .map((c) => Map<String, dynamic>.from(c as Map))
            .toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorText = "Couldn't load: $e";
      });
    }
  }

  Future<void> _manualAdjust() async {
    final result = await showDialog<({int paise, String reason})>(
      context: context,
      builder: (_) => const _ManualAdjustDialog(),
    );
    if (result == null) return;

    final adminId = ref.read(adminAuthUserIdProvider);
    if (adminId == null) return;

    try {
      await Supabase.instance.client
          .rpc<dynamic>('manual_wallet_adjust', params: {
        'p_family_id': widget.familyId,
        'p_amount_paise': result.paise,
        'p_reason': result.reason,
        'p_admin_id': adminId,
        'p_venue_id': _venueId,
        'p_idempotency_key': const Uuid().v4(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${result.paise > 0 ? 'Credited' : 'Debited'} ${Money.fromPaise(result.paise.abs())}.',
          ),
        ),
      );
      _load();
    } on PostgrestException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Couldn't adjust: ${e.message}")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.lightBackground,
      appBar: AdminAppBar(
        title: _family == null
            ? 'Customer'
            : (_family!['name'] as String? ?? 'Customer'),
        actions: [
          OutlinedButton.icon(
            onPressed: _family == null ? null : _manualAdjust,
            icon: const Icon(Icons.payments),
            label: const Text('Manual wallet adjust'),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _errorText != null
              ? Center(child: Text(_errorText!))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _FamilyCard(family: _family!, wallet: _wallet),
                      const SizedBox(height: 24),
                      _SectionHeader(text: 'Children (${_children.length})'),
                      _ChildrenTable(children: _children),
                      const SizedBox(height: 24),
                      const _SectionHeader(text: 'Wallet history'),
                      _WalletTable(rows: _walletTxns),
                      const SizedBox(height: 24),
                      _SectionHeader(text: 'Sessions (${_sessions.length})'),
                      _SessionsTable(rows: _sessions),
                      const SizedBox(height: 24),
                      _SectionHeader(text: 'Orders (${_orders.length})'),
                      _OrdersTable(rows: _orders),
                    ],
                  ),
                ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader({required this.text});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(text, style: AppTextStyles.h3(context)),
      );
}

class _FamilyCard extends StatelessWidget {
  final Map<String, dynamic> family;
  final Map<String, dynamic>? wallet;
  const _FamilyCard({required this.family, required this.wallet});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.lightSurface,
        border: Border.all(color: AppColors.lightBorder),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  (family['name'] as String?) ?? '—',
                  style: AppTextStyles.h2(context),
                ),
                const SizedBox(height: 4),
                Text(
                  (family['phone'] as String?) ?? '—',
                  style: AppTextStyles.body(
                    context,
                    color: AppColors.lightTextSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    if (family['is_walk_in'] == true)
                      const _Tag(label: 'walk-in', color: AppColors.gold),
                    if (family['is_anonymised'] == true)
                      const _Tag(label: 'anonymised', color: AppColors.adminRed),
                    if (family['marketing_consent'] == true)
                      const _Tag(
                          label: 'marketing OK', color: AppColors.activeGreen),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 24),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'Wallet',
                style: AppTextStyles.caption(
                  context,
                  color: AppColors.lightTextSecondary,
                ),
              ),
              Text(
                Money.fromPaise((wallet?['balance_paise'] as int?) ?? 0),
                style: AppTextStyles.h1(context, color: AppColors.gold),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  final String label;
  final Color color;
  const _Tag({required this.label, required this.color});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Text(
        label,
        style: AppTextStyles.caption(context, color: color),
      ),
    );
  }
}

class _ChildrenTable extends StatelessWidget {
  final List<Map<String, dynamic>> children;
  const _ChildrenTable({required this.children});
  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const Text('No children registered.');
    return Container(
      decoration: BoxDecoration(
        color: AppColors.lightSurface,
        border: Border.all(color: AppColors.lightBorder),
        borderRadius: BorderRadius.circular(8),
      ),
      child: DataTable(
        columns: const [
          DataColumn(label: Text('Name')),
          DataColumn(label: Text('Date of birth')),
          DataColumn(label: Text('Hero')),
          DataColumn(label: Text('Level')),
          DataColumn(label: Text('Total XP')),
          DataColumn(label: Text('Surprise card')),
        ],
        rows: [
          for (final c in children)
            DataRow(cells: [
              DataCell(Text((c['name'] as String?) ?? '—')),
              DataCell(Text((c['date_of_birth'] as String?) ?? '—')),
              DataCell(Text((c['favourite_hero'] as String?) ?? '—')),
              DataCell(Text('${c['current_level'] ?? '—'}')),
              DataCell(Text('${c['total_xp'] ?? 0}')),
              DataCell(_GrantCardAction(child: c)),
            ]),
        ],
      ),
    );
  }
}

/// Per-child action that opens a sheet listing all surprise cards
/// across all 4 heroes. Admin picks one + optional note → grants via
/// admin_card_grant_surprise RPC.
class _GrantCardAction extends StatelessWidget {
  final Map<String, dynamic> child;
  const _GrantCardAction({required this.child});

  @override
  Widget build(BuildContext context) {
    return AdminSecondaryButton(
      label: 'Grant',
      icon: PhosphorIconsRegular.gift,
      onPressed: () => showDialog<void>(
        context: context,
        useRootNavigator: true,
        builder: (_) => _GrantSurpriseDialog(child: child),
      ),
    );
  }
}

class _GrantSurpriseDialog extends ConsumerStatefulWidget {
  final Map<String, dynamic> child;
  const _GrantSurpriseDialog({required this.child});

  @override
  ConsumerState<_GrantSurpriseDialog> createState() =>
      _GrantSurpriseDialogState();
}

class _GrantSurpriseDialogState
    extends ConsumerState<_GrantSurpriseDialog> {
  String? _selectedCardId;
  final _noteCtrl = TextEditingController();
  bool _busy = false;
  String? _error;
  List<Map<String, dynamic>> _surpriseCards = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadCards();
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCards() async {
    try {
      final rows = await Supabase.instance.client
          .from('hero_card_definitions')
          .select('id, name, hero, image_url, description')
          .eq('unlock_method', 'surprise')
          .eq('is_active', true)
          .order('hero')
          .order('name');
      if (!mounted) return;
      setState(() {
        _surpriseCards =
            (rows as List).map((r) => Map<String, dynamic>.from(r as Map)).toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load cards: $e';
        _loading = false;
      });
    }
  }

  Future<void> _grant() async {
    if (_selectedCardId == null) {
      setState(() => _error = 'Pick a card first.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final res = await Supabase.instance.client
          .rpc<Map<String, dynamic>>('admin_card_grant_surprise', params: {
        'p_child_id': widget.child['id'],
        'p_card_id': _selectedCardId,
        'p_note':
            _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
      });
      if (!mounted) return;
      Navigator.of(context).pop();
      final newlyGranted = res['newly_granted'] == true;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            newlyGranted
                ? '${widget.child['name']} just received "${res['card_name']}"'
                : '${widget.child['name']} already had that card',
          ),
        ),
      );
    } on PostgrestException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message.contains('not_a_surprise_card')
            ? "That card isn't a surprise card."
            : 'Grant failed: ${e.message}';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Grant failed: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final childName = (widget.child['name'] as String?) ?? 'this kid';
    return AlertDialog(
      title: Text('Grant a surprise card to $childName'),
      content: ConstrainedBox(
        constraints:
            const BoxConstraints(minWidth: 480, maxWidth: 560, maxHeight: 540),
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Pick from the surprise cards admin has set up. '
                    'Re-grants are silent (the kid already has it).',
                    style: AppTextStyles.caption(
                      context,
                      color: AppColors.lightTextSecondary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: SingleChildScrollView(
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final c in _surpriseCards)
                            _SurpriseCardChip(
                              card: c,
                              selected: _selectedCardId == c['id'],
                              onTap: () => setState(
                                  () => _selectedCardId = c['id'] as String),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _noteCtrl,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Why this card? (optional, audit-only)',
                      border: OutlineInputBorder(),
                      hintText: 'e.g. cheered up another kid in the corner',
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(_error!,
                        style: AppTextStyles.caption(
                          context,
                          color: AppColors.adminRed,
                        )),
                  ],
                ],
              ),
      ),
      actions: [
        AdminSecondaryButton(
          label: 'Cancel',
          ghost: true,
          onPressed:
              _busy ? null : () => Navigator.of(context).pop(),
        ),
        const SizedBox(width: 8),
        AdminPrimaryButton(
          label: 'Grant card',
          busy: _busy,
          onPressed: _busy ? null : _grant,
        ),
      ],
    );
  }
}

class _SurpriseCardChip extends StatelessWidget {
  final Map<String, dynamic> card;
  final bool selected;
  final VoidCallback onTap;
  const _SurpriseCardChip({
    required this.card,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final name = (card['name'] as String?) ?? '—';
    final hero = (card['hero'] as String?) ?? '—';
    return Material(
      color: selected
          ? AppColors.gold.withValues(alpha: 0.20)
          : AppColors.lightSurface,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 200,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            border: Border.all(
              color: selected ? AppColors.gold : AppColors.lightBorder,
              width: selected ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name,
                  style: AppTextStyles.body(context).copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Text(hero,
                  style: AppTextStyles.caption(
                    context,
                    color: AppColors.lightTextSecondary,
                  )),
            ],
          ),
        ),
      ),
    );
  }
}

class _WalletTable extends StatelessWidget {
  final List<Map<String, dynamic>> rows;
  const _WalletTable({required this.rows});
  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const Text('No wallet activity.');
    return Container(
      decoration: BoxDecoration(
        color: AppColors.lightSurface,
        border: Border.all(color: AppColors.lightBorder),
        borderRadius: BorderRadius.circular(8),
      ),
      child: DataTable(
        columns: const [
          DataColumn(label: Text('When')),
          DataColumn(label: Text('Type')),
          DataColumn(label: Text('Amount')),
          DataColumn(label: Text('Balance after')),
          DataColumn(label: Text('Method')),
        ],
        rows: [
          for (final r in rows)
            DataRow(cells: [
              DataCell(Text(_short(r['created_at'] as String?))),
              DataCell(Text((r['type'] as String?) ?? '—')),
              DataCell(Text(
                _signed((r['amount_paise'] as int?) ?? 0),
                style: TextStyle(
                  color: ((r['amount_paise'] as int?) ?? 0) < 0
                      ? AppColors.adminRed
                      : AppColors.activeGreen,
                ),
              )),
              DataCell(Text(
                Money.fromPaise((r['balance_after_paise'] as int?) ?? 0),
              )),
              DataCell(Text((r['payment_method'] as String?) ?? '—')),
            ]),
        ],
      ),
    );
  }

  String _signed(int paise) =>
      '${paise >= 0 ? '+' : ''}${Money.fromPaise(paise.abs())}';

  String _short(String? iso) {
    if (iso == null) return '—';
    try {
      final dt = DateTime.parse(iso).toLocal();
      return '${dt.month}/${dt.day} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso;
    }
  }
}

class _SessionsTable extends StatelessWidget {
  final List<Map<String, dynamic>> rows;
  const _SessionsTable({required this.rows});
  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const Text('No sessions.');
    return Container(
      decoration: BoxDecoration(
        color: AppColors.lightSurface,
        border: Border.all(color: AppColors.lightBorder),
        borderRadius: BorderRadius.circular(8),
      ),
      child: DataTable(
        columns: const [
          DataColumn(label: Text('Started')),
          DataColumn(label: Text('Duration')),
          DataColumn(label: Text('Amount')),
          DataColumn(label: Text('Method')),
          DataColumn(label: Text('Status')),
        ],
        rows: [
          for (final r in rows)
            DataRow(cells: [
              DataCell(Text(_short(r['started_at'] as String?))),
              DataCell(Text('${r['duration_minutes']}m')),
              DataCell(Text(
                Money.fromPaise((r['amount_paise'] as int?) ?? 0),
              )),
              DataCell(Text((r['payment_method'] as String?) ?? '—')),
              DataCell(Text((r['status'] as String?) ?? '—')),
            ]),
        ],
      ),
    );
  }

  String _short(String? iso) {
    if (iso == null) return '—';
    try {
      final dt = DateTime.parse(iso).toLocal();
      return '${dt.month}/${dt.day} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso;
    }
  }
}

class _OrdersTable extends StatelessWidget {
  final List<Map<String, dynamic>> rows;
  const _OrdersTable({required this.rows});
  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const Text('No orders.');
    return Container(
      decoration: BoxDecoration(
        color: AppColors.lightSurface,
        border: Border.all(color: AppColors.lightBorder),
        borderRadius: BorderRadius.circular(8),
      ),
      child: DataTable(
        columns: const [
          DataColumn(label: Text('Created')),
          DataColumn(label: Text('Total')),
          DataColumn(label: Text('Status')),
          DataColumn(label: Text('Method')),
        ],
        rows: [
          for (final r in rows)
            DataRow(cells: [
              DataCell(Text(_short(r['created_at'] as String?))),
              DataCell(Text(
                Money.fromPaise((r['total_paise'] as int?) ?? 0),
              )),
              DataCell(Text((r['status'] as String?) ?? '—')),
              DataCell(Text((r['payment_method'] as String?) ?? '—')),
            ]),
        ],
      ),
    );
  }

  String _short(String? iso) {
    if (iso == null) return '—';
    try {
      final dt = DateTime.parse(iso).toLocal();
      return '${dt.month}/${dt.day} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso;
    }
  }
}

class _ManualAdjustDialog extends StatefulWidget {
  const _ManualAdjustDialog();
  @override
  State<_ManualAdjustDialog> createState() => _ManualAdjustDialogState();
}

class _ManualAdjustDialogState extends State<_ManualAdjustDialog> {
  final _amount = TextEditingController();
  final _reason = TextEditingController();
  bool _isCredit = true;

  @override
  void dispose() {
    _amount.dispose();
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Manual wallet adjust'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: true, label: Text('Credit (+)')),
                ButtonSegment(value: false, label: Text('Debit (–)')),
              ],
              selected: {_isCredit},
              onSelectionChanged: (s) => setState(() => _isCredit = s.first),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _amount,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                prefixText: '₹ ',
                labelText: 'Amount',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _reason,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Reason (required)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _isCredit
                  ? 'Credits go straight to wallet.'
                  : 'Debits respect require_two_person_for_debit; alone-admin debits will fail if the toggle is on.',
              style: AppTextStyles.caption(
                context,
                color: AppColors.lightTextSecondary,
              ),
            ),
          ],
        ),
      ),
      actions: [
        AdminSecondaryButton(
          label: 'Cancel',
          ghost: true,
          onPressed: () => Navigator.of(context).pop(),
        ),
        const SizedBox(width: 8),
        AdminPrimaryButton(
          label: 'Apply',
          onPressed: () {
            final rupees = int.tryParse(_amount.text) ?? 0;
            final reason = _reason.text.trim();
            if (rupees <= 0 || reason.isEmpty) return;
            final paise = (rupees * 100) * (_isCredit ? 1 : -1);
            Navigator.of(context).pop((paise: paise, reason: reason));
          },
        ),
      ],
    );
  }
}
