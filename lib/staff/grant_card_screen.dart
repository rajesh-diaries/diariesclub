import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_text_styles.dart';
import 'providers/venue_streams_provider.dart';
import 'widgets/staff_pin_sheet.dart';

/// Staff path for granting a surprise hero card to a kid currently in
/// session at the venue. Two-step flow:
///   1. Pick a kid from the active sessions list.
///   2. Pick a surprise card (grouped by hero), optional reason note,
///      Grant. PIN sheet validates the actor before card_grant_surprise
///      RPC fires.
class GrantCardScreen extends ConsumerStatefulWidget {
  const GrantCardScreen({super.key});

  @override
  ConsumerState<GrantCardScreen> createState() => _GrantCardScreenState();
}

class _GrantCardScreenState extends ConsumerState<GrantCardScreen> {
  Map<String, dynamic>? _selectedSession;

  @override
  Widget build(BuildContext context) {
    final sessionsAsync = ref.watch(venueActiveSessionsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Grant a surprise card'),
      ),
      body: sessionsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text("Couldn't load sessions: $e")),
        data: (sessions) {
          final liveSessions =
              sessions.where((s) => s['status'] == 'active' || s['status'] == 'grace').toList();
          if (liveSessions.isEmpty) {
            return _EmptyState();
          }

          if (_selectedSession == null) {
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'Pick the kid you want to surprise',
                  style: AppTextStyles.bodyLarge(context),
                ),
                const SizedBox(height: 12),
                for (final s in liveSessions)
                  _SessionPickTile(
                    session: s,
                    onTap: () => setState(() => _selectedSession = s),
                  ),
              ],
            );
          }

          return _CardPicker(
            session: _selectedSession!,
            onCancel: () => setState(() => _selectedSession = null),
          );
        },
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                PhosphorIconsFill.smileyMelting,
                size: 64,
                color: AppColors.lightTextSecondary,
              ),
              const SizedBox(height: 16),
              Text(
                'No kids in session right now',
                style: AppTextStyles.h3(context),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Surprise cards can only be granted to kids currently '
                'playing at the venue.',
                style: AppTextStyles.body(
                  context,
                  color: AppColors.lightTextSecondary,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SessionPickTile extends StatelessWidget {
  final Map<String, dynamic> session;
  final VoidCallback onTap;
  const _SessionPickTile({required this.session, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final childName = (session['_child_name'] as String?) ??
        (session['child_id'] as String?)?.substring(0, 8) ??
        'Kid';
    final status = (session['status'] as String?) ?? 'active';
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.gold.withValues(alpha: 0.18),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: const Icon(PhosphorIconsFill.smiley,
              color: AppColors.navy, size: 20),
        ),
        title: Text(childName),
        subtitle: Text('Status: $status'),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

class _CardPicker extends ConsumerStatefulWidget {
  final Map<String, dynamic> session;
  final VoidCallback onCancel;
  const _CardPicker({required this.session, required this.onCancel});

  @override
  ConsumerState<_CardPicker> createState() => _CardPickerState();
}

class _CardPickerState extends ConsumerState<_CardPicker> {
  String? _selectedCardId;
  final _noteCtrl = TextEditingController();
  bool _busy = false;
  String? _error;
  List<Map<String, dynamic>> _cards = const [];
  bool _loading = true;

  static const _heroOrder = ['rafi', 'ellie', 'gerry', 'zena'];
  static const _heroLabels = {
    'rafi': 'Rafi · Brave',
    'ellie': 'Ellie · Kind',
    'gerry': 'Gerry · Curious',
    'zena': 'Zena · Creative',
  };

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
        _cards =
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
    final verified = await StaffPinSheet.show(
      context,
      actionLabel: 'Grant a surprise card',
    );
    if (verified == null || !mounted) return;
    final pinId = verified.staffId;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final res = await Supabase.instance.client
          .rpc<Map<String, dynamic>>('card_grant_surprise', params: {
        'p_child_id': widget.session['child_id'],
        'p_card_id': _selectedCardId,
        'p_staff_pin_id': pinId,
        'p_note':
            _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
      });
      if (!mounted) return;
      final newlyGranted = res['newly_granted'] == true;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            newlyGranted
                ? 'Granted "${res['card_name']}" — kid will see it pop in their atlas'
                : 'Kid already had that card',
          ),
        ),
      );
      // Reset back to session-list view for the next grant.
      Navigator.of(context).pop();
    } on PostgrestException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Grant failed: ${e.message}';
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
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final byHero = <String, List<Map<String, dynamic>>>{};
    for (final c in _cards) {
      byHero.putIfAbsent(c['hero'] as String, () => []).add(c);
    }

    return SafeArea(
      child: Column(
        children: [
          Material(
            color: AppColors.lightSurface,
            child: ListTile(
              leading: const Icon(PhosphorIconsRegular.arrowLeft),
              title: const Text('Back to kid list'),
              onTap: widget.onCancel,
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'Pick a surprise card',
                  style: AppTextStyles.bodyLarge(context),
                ),
                const SizedBox(height: 12),
                for (final hero in _heroOrder) ...[
                  if ((byHero[hero] ?? const []).isNotEmpty) ...[
                    Text(
                      _heroLabels[hero] ?? hero,
                      style: AppTextStyles.caption(context).copyWith(
                        letterSpacing: 1.0,
                        fontWeight: FontWeight.w800,
                        color: AppColors.lightTextSecondary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final c in byHero[hero]!)
                          _CardChip(
                            card: c,
                            selected: _selectedCardId == c['id'],
                            onTap: () => setState(
                                () => _selectedCardId = c['id'] as String),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],
                ],
                TextField(
                  controller: _noteCtrl,
                  minLines: 2,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Why? (optional, audit-only)',
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
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _busy ? null : _grant,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.navy,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation(Colors.white),
                          ),
                        )
                      : const Text('Grant card'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CardChip extends StatelessWidget {
  final Map<String, dynamic> card;
  final bool selected;
  final VoidCallback onTap;
  const _CardChip({
    required this.card,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final name = (card['name'] as String?) ?? '—';
    return Material(
      color: selected
          ? AppColors.gold.withValues(alpha: 0.20)
          : AppColors.lightSurface,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 180,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            border: Border.all(
              color: selected ? AppColors.gold : AppColors.lightBorder,
              width: selected ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            name,
            style: AppTextStyles.body(context).copyWith(
              fontWeight: FontWeight.w800,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }
}
