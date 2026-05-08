import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/currency.dart';
import '../widgets/admin_app_bar.dart';
import '../widgets/admin_buttons.dart';

/// Customers list. Search calls admin_family_search RPC (admin-gated).
/// Click a row → /admin/customers/:id (detail screen). Impersonation
/// deferred to Session 13.
class CustomersScreen extends ConsumerStatefulWidget {
  const CustomersScreen({super.key});

  @override
  ConsumerState<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends ConsumerState<CustomersScreen> {
  final _ctrl = TextEditingController();
  bool _busy = false;
  bool _isDefaultList = false;
  List<Map<String, dynamic>> _results = const [];
  String? _errorText;

  @override
  void initState() {
    super.initState();
    // Auto-load recent customers on first paint so the screen isn't blank.
    // Empty p_query → admin_family_search returns recent families ordered
    // by last_visit DESC NULLS LAST (BUG-052, migration 0052).
    WidgetsBinding.instance.addPostFrameCallback((_) => _runQuery(''));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _search() => _runQuery(_ctrl.text.trim());

  Future<void> _runQuery(String q) async {
    setState(() {
      _busy = true;
      _errorText = null;
    });
    try {
      final raw = await Supabase.instance.client
          .rpc<dynamic>('admin_family_search', params: {
        'p_query': q,
        'p_limit': 50,
      });
      final body = Map<String, dynamic>.from(raw as Map);
      final results = (body['results'] as List)
          .map((r) => Map<String, dynamic>.from(r as Map))
          .toList();
      if (!mounted) return;
      setState(() {
        _results = results;
        _isDefaultList = body['is_default_list'] == true;
        _busy = false;
      });
    } on PostgrestException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _errorText = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _errorText = "Couldn't load customers.";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.lightBackground,
      appBar: const AdminAppBar(title: 'Customers'),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _ctrl,
                    onSubmitted: (_) => _search(),
                    decoration: const InputDecoration(
                      hintText: 'Phone, family name, or child name…',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                AdminPrimaryButton(
                  label: 'Search',
                  busy: _busy,
                  onPressed: _busy ? null : _search,
                ),
              ],
            ),
            if (_errorText != null) ...[
              const SizedBox(height: 12),
              Text(
                _errorText!,
                style:
                    AppTextStyles.caption(context, color: AppColors.adminRed),
              ),
            ],
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Text(
                    _busy
                        ? 'Loading…'
                        : _isDefaultList
                            ? 'Recent customers (${_results.length})'
                            : 'Search results (${_results.length})',
                    style: AppTextStyles.caption(
                      context,
                      color: AppColors.lightTextSecondary,
                    ).copyWith(
                      letterSpacing: 1.0,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (!_isDefaultList && !_busy) ...[
                    const Spacer(),
                    AdminSecondaryButton(
                      label: 'Clear',
                      ghost: true,
                      onPressed: () {
                        _ctrl.clear();
                        _runQuery('');
                      },
                    ),
                  ],
                ],
              ),
            ),
            Expanded(
              child: _busy
                  ? const Center(child: CircularProgressIndicator())
                  : _results.isEmpty
                  ? Center(
                      child: Text(
                        _isDefaultList
                            ? 'No customers yet.'
                            : 'No matches. Try a different phone or name fragment.',
                        style: AppTextStyles.body(
                          context,
                          color: AppColors.lightTextSecondary,
                        ),
                      ),
                    )
                  : Container(
                      decoration: BoxDecoration(
                        color: AppColors.lightSurface,
                        border: Border.all(color: AppColors.lightBorder),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: SingleChildScrollView(
                        child: DataTable(
                          columns: const [
                            DataColumn(label: Text('Phone')),
                            DataColumn(label: Text('Family')),
                            DataColumn(label: Text('Children')),
                            DataColumn(label: Text('Wallet')),
                            DataColumn(label: Text('Last visit')),
                            DataColumn(label: Text('')),
                          ],
                          rows: [
                            for (final r in _results)
                              DataRow(cells: [
                                DataCell(Text(
                                  (r['phone'] as String?) ?? '—',
                                  style: const TextStyle(fontFamily: 'monospace'),
                                )),
                                DataCell(Text((r['name'] as String?) ?? '—')),
                                DataCell(Text(
                                  ((r['children'] as List?) ?? const [])
                                      .map((c) => (c as Map)['name'])
                                      .join(', '),
                                )),
                                DataCell(Text(
                                  Money.fromPaise(
                                      (r['wallet_balance_paise'] as int?) ?? 0),
                                )),
                                DataCell(Text(
                                  _relative(r['last_visit'] as String?),
                                  style: AppTextStyles.caption(
                                    context,
                                    color: AppColors.lightTextSecondary,
                                  ),
                                )),
                                DataCell(AdminSecondaryButton(
                                  label: 'Open →',
                                  ghost: true,
                                  onPressed: () => context.go(
                                    '/admin/customers/${r['id']}',
                                    extra: r,
                                  ),
                                )),
                              ]),
                          ],
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  String _relative(String? iso) {
    if (iso == null) return 'Never';
    try {
      final delta = DateTime.now().difference(DateTime.parse(iso));
      if (delta.inDays > 0) return '${delta.inDays}d ago';
      if (delta.inHours > 0) return '${delta.inHours}h ago';
      return '${delta.inMinutes}m ago';
    } catch (_) {
      return iso;
    }
  }
}
