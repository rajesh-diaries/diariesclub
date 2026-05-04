// ignore_for_file: deprecated_member_use
// ^ RadioListTile.groupValue/onChanged — see extend_session_sheet.dart.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../core/providers/auth_provider.dart';
import '../../core/providers/current_wallet_provider.dart';
import '../../core/providers/venue_config_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/currency.dart';
import '../../core/widgets/primary_button.dart';
import 'widgets/insufficient_balance_sheet.dart';

/// Single venue id for v1 (Hyderabad). Replace with venue resolution when
/// multi-venue arrives — same constant used by venueConfigProvider.
const _venueId = '00000000-0000-0000-0000-000000000001';

/// Step 1 of the session lifecycle: pick child (if multi), pick duration
/// (1hr / 2hr — prices from venue_config), pick payment method, then call
/// `session_create`. On success → /session/qr/:id.
class SessionStartScreen extends ConsumerStatefulWidget {
  const SessionStartScreen({super.key});

  @override
  ConsumerState<SessionStartScreen> createState() =>
      _SessionStartScreenState();
}

class _SessionStartScreenState extends ConsumerState<SessionStartScreen> {
  String? _selectedChildId;
  int? _selectedDurationMinutes;
  String _paymentMethod = 'wallet';
  bool _busy = false;
  String? _errorText;

  late final Future<List<Map<String, dynamic>>> _childrenFuture;

  @override
  void initState() {
    super.initState();
    _childrenFuture = _loadChildren();
  }

  Future<List<Map<String, dynamic>>> _loadChildren() async {
    final familyId = ref.read(currentFamilyIdProvider);
    if (familyId == null) return const [];
    final rows = await Supabase.instance.client
        .from('children')
        .select()
        .eq('family_id', familyId)
        .order('created_at', ascending: true);
    return (rows as List)
        .map((r) => Map<String, dynamic>.from(r as Map))
        .toList();
  }

  int _priceFor(int? duration, Map<String, dynamic>? cfg) {
    if (duration == null || cfg == null) return 0;
    return duration == 60
        ? (cfg['session_1hr_price_paise'] as int?) ?? 80000
        : (cfg['session_2hr_price_paise'] as int?) ?? 110000;
  }

  Future<void> _start() async {
    if (_selectedDurationMinutes == null) return;
    final cfg = ref.read(venueConfigProvider).valueOrNull;
    final amount = _priceFor(_selectedDurationMinutes, cfg);

    setState(() {
      _busy = true;
      _errorText = null;
    });
    final idem = const Uuid().v4();
    final familyId = ref.read(currentFamilyIdProvider);
    if (familyId == null) {
      setState(() => _busy = false);
      return;
    }

    try {
      final result = await Supabase.instance.client
          .rpc<Map<String, dynamic>>('session_create', params: {
        'p_venue_id': _venueId,
        'p_family_id': familyId,
        'p_child_id': _selectedChildId,
        'p_duration_minutes': _selectedDurationMinutes,
        'p_payment_method': _paymentMethod,
        'p_idempotency_key': idem,
      });
      final sessionId = result['session_id'] as String?;
      if (sessionId == null) {
        throw StateError('session_create did not return session_id');
      }
      if (!mounted) return;
      context.go('/session/qr/$sessionId');
    } on PostgrestException catch (e) {
      if (e.message.contains('insufficient_balance')) {
        if (!mounted) return;
        setState(() => _busy = false);
        showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => InsufficientBalanceSheet(
            requiredPaise: amount,
            onSwitchToCash: () {
              if (!mounted) return;
              setState(() => _paymentMethod = 'cash');
            },
          ),
        );
        return;
      }
      setState(() {
        _busy = false;
        _errorText = "Couldn't start session. Please try again.";
      });
    } catch (_) {
      setState(() {
        _busy = false;
        _errorText = "Couldn't start session. Please try again.";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cfg = ref.watch(venueConfigProvider).valueOrNull;
    final balance = ref.watch(walletBalancePaiseProvider) ?? 0;

    final price1hr = (cfg?['session_1hr_price_paise'] as int?) ?? 80000;
    final price2hr = (cfg?['session_2hr_price_paise'] as int?) ?? 110000;
    final selectedAmount = _priceFor(_selectedDurationMinutes, cfg);
    final walletEnough = balance >= selectedAmount;

    final canSubmit = !_busy &&
        _selectedDurationMinutes != null &&
        // child must be selected if there are multiple children — handled below
        // by gating on the form completion, not here.
        _selectedChildId != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Start a session'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _childrenFuture,
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final children = snap.data!;
          // Auto-select if there's only one.
          if (children.length == 1 && _selectedChildId == null) {
            _selectedChildId = children.first['id'] as String;
          }

          return SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (children.length > 1) ...[
                          Text('Who\'s playing?',
                              style: AppTextStyles.bodyLarge(context)),
                          const SizedBox(height: 12),
                          SizedBox(
                            height: 110,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: children.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(width: 12),
                              itemBuilder: (_, i) {
                                final c = children[i];
                                final selected =
                                    _selectedChildId == c['id'];
                                return _ChildAvatar(
                                  name: c['name'] as String? ?? '—',
                                  photoUrl: c['photo_url'] as String?,
                                  selected: selected,
                                  onTap: () => setState(() =>
                                      _selectedChildId =
                                          c['id'] as String),
                                );
                              },
                            ),
                          ),
                          const SizedBox(height: 24),
                        ],
                        Text('How long?',
                            style: AppTextStyles.bodyLarge(context)),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _DurationCard(
                                title: '1 hour',
                                tagline: 'Quick play',
                                pricePaise: price1hr,
                                selected: _selectedDurationMinutes == 60,
                                onTap: () => setState(
                                    () => _selectedDurationMinutes = 60),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _DurationCard(
                                title: '2 hours',
                                tagline: 'Best value',
                                pricePaise: price2hr,
                                selected: _selectedDurationMinutes == 120,
                                onTap: () => setState(
                                    () => _selectedDurationMinutes = 120),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        Text('Pay with',
                            style: AppTextStyles.bodyLarge(context)),
                        const SizedBox(height: 4),
                        RadioListTile<String>(
                          value: 'wallet',
                          groupValue: _paymentMethod,
                          title: Text(
                              'Diaries Wallet (${Money.fromPaise(balance)})'),
                          subtitle: !walletEnough &&
                                  _selectedDurationMinutes != null
                              ? const Text(
                                  'Not enough balance',
                                  style: TextStyle(color: AppColors.adminRed),
                                )
                              : null,
                          onChanged: (v) =>
                              setState(() => _paymentMethod = v ?? 'wallet'),
                        ),
                        RadioListTile<String>(
                          value: 'cash',
                          groupValue: _paymentMethod,
                          title: const Text('Cash at venue'),
                          subtitle: const Text(
                            'Pay our team when you check in',
                          ),
                          onChanged: (v) =>
                              setState(() => _paymentMethod = v ?? 'cash'),
                        ),
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
                _StickyCta(
                  label: _selectedDurationMinutes == null
                      ? 'Pick a duration'
                      : _paymentMethod == 'wallet'
                          ? 'Pay ${Money.fromPaise(selectedAmount)} from wallet'
                          : 'Continue with cash',
                  onPressed: canSubmit ? _start : null,
                  loading: _busy,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ChildAvatar extends StatelessWidget {
  final String name;
  final String? photoUrl;
  final bool selected;
  final VoidCallback onTap;
  const _ChildAvatar({
    required this.name,
    required this.photoUrl,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: selected ? AppColors.gold : AppColors.lightBorder,
                width: selected ? 3 : 1,
              ),
              image: photoUrl != null && photoUrl!.isNotEmpty
                  ? DecorationImage(
                      image: NetworkImage(photoUrl!),
                      fit: BoxFit.cover,
                    )
                  : null,
              color: AppColors.gold.withValues(alpha: 0.18),
            ),
            child: photoUrl == null || photoUrl!.isEmpty
                ? const Icon(
                    PhosphorIconsFill.smiley,
                    color: AppColors.navy,
                    size: 30,
                  )
                : null,
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: 78,
            child: Text(
              name,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.caption(context),
            ),
          ),
        ],
      ),
    );
  }
}

class _DurationCard extends StatelessWidget {
  final String title;
  final String tagline;
  final int pricePaise;
  final bool selected;
  final VoidCallback onTap;
  const _DurationCard({
    required this.title,
    required this.tagline,
    required this.pricePaise,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.gold.withValues(alpha: 0.18)
              : AppColors.lightSurface,
          border: Border.all(
            color: selected ? AppColors.gold : AppColors.lightBorder,
            width: selected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: AppTextStyles.h3(context)),
            const SizedBox(height: 4),
            Text(
              Money.fromPaise(pricePaise),
              style: AppTextStyles.h2(context, color: AppColors.navy),
            ),
            const SizedBox(height: 4),
            Text(
              tagline,
              style: AppTextStyles.caption(
                context,
                color: AppColors.lightTextSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StickyCta extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  const _StickyCta({
    required this.label,
    required this.onPressed,
    required this.loading,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          border: const Border(
            top: BorderSide(color: AppColors.lightBorder),
          ),
        ),
        child: SizedBox(
          width: double.infinity,
          child: PrimaryButton(
            label: label,
            onPressed: onPressed,
            loading: loading,
          ),
        ),
      ),
    );
  }
}
