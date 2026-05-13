import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/providers/current_wallet_provider.dart';
import '../../core/providers/wallet_history_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/currency.dart';
import 'widgets/transaction_row.dart';

/// Full wallet history screen — paginated, filterable, grouped by date.
/// Filter pills update [walletHistoryFilterProvider]; the screen tracks
/// loaded pages locally and keeps appending until a short page comes back.
class WalletHistoryScreen extends ConsumerStatefulWidget {
  const WalletHistoryScreen({super.key});

  @override
  ConsumerState<WalletHistoryScreen> createState() =>
      _WalletHistoryScreenState();
}

class _WalletHistoryScreenState
    extends ConsumerState<WalletHistoryScreen> {
  final _scroll = ScrollController();
  final _loaded = <Map<String, dynamic>>[];
  int _page = 0;
  bool _exhausted = false;
  bool _loading = false;
  // When a page-fetch throws we surface a retry tile at the bottom of
  // the list instead of silently stalling pagination. Reset on _refresh
  // and after a successful retry.
  bool _pageError = false;

  @override
  void initState() {
    super.initState();
    _loadNext();
    _scroll.addListener(_maybeLoadMore);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadNext() async {
    if (_loading || _exhausted) return;
    setState(() {
      _loading = true;
      _pageError = false;
    });
    try {
      final rows =
          await ref.read(walletHistoryPageProvider(_page).future);
      if (!mounted) return;
      setState(() {
        _loaded.addAll(rows);
        _exhausted = rows.length < walletHistoryPageSize;
        _page++;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _pageError = true;
      });
    }
  }

  void _maybeLoadMore() {
    // Don't auto-retry when the last page errored — user has to tap the
    // retry tile so we don't quietly hammer a failing endpoint.
    if (_pageError) return;
    if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 200) {
      _loadNext();
    }
  }

  Future<void> _refresh() async {
    setState(() {
      _loaded.clear();
      _page = 0;
      _exhausted = false;
      _pageError = false;
    });
    // Invalidate any pages cached so far so the filter change is picked up.
    ref.invalidate(walletHistoryPageProvider);
    await _loadNext();
  }

  void _onFilterChanged(WalletHistoryFilter f) {
    ref.read(walletHistoryFilterProvider.notifier).state = f;
    _refresh();
  }

  void _showDetails(Map<String, dynamic> tx) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _TransactionDetailSheet(tx: tx),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(walletHistoryFilterProvider);
    final balance = ref.watch(walletBalancePaiseProvider);
    final wallet = ref.watch(currentWalletProvider).valueOrNull;
    final coinsLifetime = (wallet?['coins_lifetime'] as int?) ?? 0;

    final groups = _groupByDay(_loaded);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Wallet history'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: CustomScrollView(
            controller: _scroll,
            slivers: [
              SliverToBoxAdapter(
                child: _BalanceBanner(
                  balancePaise: balance ?? 0,
                  coinsLifetime: coinsLifetime,
                ),
              ),
              SliverToBoxAdapter(
                child: _FilterPills(
                  selected: filter,
                  onChanged: _onFilterChanged,
                ),
              ),
              if (_loaded.isEmpty && !_loading)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: _EmptyState(),
                )
              else
                for (final group in groups) ...[
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                      child: Text(
                        group.label,
                        style: AppTextStyles.caption(
                          context,
                          color: AppColors.lightTextSecondary,
                        ).copyWith(letterSpacing: 1.0),
                      ),
                    ),
                  ),
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (_, i) => TransactionRow(
                        tx: group.rows[i],
                        onTap: () => _showDetails(group.rows[i]),
                      ),
                      childCount: group.rows.length,
                    ),
                  ),
                ],
              if (_loading)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                )
              else if (_pageError)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            "Couldn't load more transactions.",
                            style: AppTextStyles.body(
                              context,
                              color: AppColors.lightTextSecondary,
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextButton(
                            onPressed: _loadNext,
                            child: const Text('Try again'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 32)),
            ],
          ),
        ),
      ),
    );
  }

  List<_DayGroup> _groupByDay(List<Map<String, dynamic>> rows) {
    final out = <_DayGroup>[];
    String? currentLabel;
    List<Map<String, dynamic>> bucket = [];
    for (final r in rows) {
      final iso = r['created_at'] as String?;
      if (iso == null) continue;
      final t = DateTime.tryParse(iso)?.toLocal();
      if (t == null) continue;
      final label = _labelFor(t);
      if (label != currentLabel) {
        if (bucket.isNotEmpty) out.add(_DayGroup(currentLabel!, bucket));
        currentLabel = label;
        bucket = [];
      }
      bucket.add(r);
    }
    if (bucket.isNotEmpty && currentLabel != null) {
      out.add(_DayGroup(currentLabel, bucket));
    }
    return out;
  }

  String _labelFor(DateTime t) {
    final today = DateTime.now();
    final d = DateTime(t.year, t.month, t.day);
    final today0 = DateTime(today.year, today.month, today.day);
    final diff = today0.difference(d).inDays;
    if (diff == 0) return 'TODAY';
    if (diff == 1) return 'YESTERDAY';
    if (diff < 7) return 'LAST 7 DAYS';
    if (diff < 30) return 'LAST 30 DAYS';
    return DateFormat('MMM yyyy').format(t).toUpperCase();
  }
}

class _DayGroup {
  final String label;
  final List<Map<String, dynamic>> rows;
  _DayGroup(this.label, this.rows);
}

class _BalanceBanner extends StatelessWidget {
  final int balancePaise;
  final int coinsLifetime;
  const _BalanceBanner({
    required this.balancePaise,
    required this.coinsLifetime,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.navy, Color(0xFF2A4A8B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            Money.fromPaise(balancePaise),
            style: AppTextStyles.display(context, color: Colors.white),
          ),
          const SizedBox(height: 4),
          Text(
            'available',
            style: AppTextStyles.caption(context, color: Colors.white70),
          ),
          if (coinsLifetime > 0) ...[
            const SizedBox(height: 8),
            Text(
              '+$coinsLifetime Diaries Coins earned (lifetime)',
              style: AppTextStyles.caption(context, color: AppColors.gold),
            ),
          ],
        ],
      ),
    );
  }
}

class _FilterPills extends StatelessWidget {
  final WalletHistoryFilter selected;
  final ValueChanged<WalletHistoryFilter> onChanged;
  const _FilterPills({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          for (final f in WalletHistoryFilter.values)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: ChoiceChip(
                label: Text(f.label),
                selected: selected == f,
                onSelected: (v) {
                  if (v) onChanged(f);
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              PhosphorIconsRegular.wallet,
              size: 48,
              color: AppColors.lightTextSecondary,
            ),
            const SizedBox(height: 12),
            Text(
              'No transactions match this filter.',
              style: AppTextStyles.body(
                context,
                color: AppColors.lightTextSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
//  Transaction detail sheet — full timestamp, refs, idempotency_key.
// ---------------------------------------------------------------------------
class _TransactionDetailSheet extends StatelessWidget {
  final Map<String, dynamic> tx;
  const _TransactionDetailSheet({required this.tx});

  @override
  Widget build(BuildContext context) {
    final type = (tx['type'] as String?) ?? '';
    final amount = (tx['amount_paise'] as int?) ?? 0;
    final coins = (tx['coins_amount'] as int?) ?? 0;
    final balanceAfter = tx['balance_after_paise'] as int?;
    final paymentMethod = tx['payment_method'] as String?;
    final razorpayId = tx['razorpay_payment_id'] as String?;
    final referenceType = tx['reference_type'] as String?;
    final referenceId = tx['reference_id'] as String?;
    final idemKey = tx['idempotency_key'] as String?;
    final createdAt = tx['created_at'] as String?;

    final parsedCreatedAt =
        createdAt == null ? null : DateTime.tryParse(createdAt)?.toLocal();
    final iso = parsedCreatedAt == null ? '—' : parsedCreatedAt.toString();

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
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
            const SizedBox(height: 16),
            Text('Transaction', style: AppTextStyles.h2(context)),
            const SizedBox(height: 12),
            _kv(context, 'Type', type),
            _kv(
              context,
              'Amount',
              type == 'coins_credit' || type == 'coins_debit'
                  ? '${coins >= 0 ? '+' : ''}$coins coins'
                  : '${amount >= 0 ? '+' : ''}${Money.fromPaise(amount)}',
            ),
            if (balanceAfter != null)
              _kv(context, 'Balance after', Money.fromPaise(balanceAfter)),
            _kv(context, 'When', iso),
            if (paymentMethod != null)
              _kv(context, 'Payment method', paymentMethod),
            if (razorpayId != null)
              _kv(context, 'Razorpay payment', razorpayId),
            if (referenceType != null && referenceId != null)
              _kv(context, 'Reference', '$referenceType · $referenceId'),
            if (idemKey != null) _kv(context, 'Idempotency key', idemKey),
          ],
        ),
      ),
    );
  }

  Widget _kv(BuildContext context, String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              k,
              style: AppTextStyles.caption(
                context,
                color: AppColors.lightTextSecondary,
              ),
            ),
            const SizedBox(height: 2),
            SelectableText(v, style: AppTextStyles.body(context)),
          ],
        ),
      );
}
