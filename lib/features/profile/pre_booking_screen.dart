import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../core/providers/auth_provider.dart';
import '../../core/providers/current_wallet_provider.dart';
import '../../core/providers/family_children_provider.dart';
import '../../core/providers/venue_config_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/currency.dart';
import '../../core/widgets/child_avatar.dart';
import '../../core/widgets/primary_button.dart';
import '../sessions/widgets/insufficient_balance_sheet.dart';

/// Single venue id for v1 (matches session_start_screen.dart).
const _venueId = '00000000-0000-0000-0000-000000000001';

/// Reserve a play slot up to 14 days ahead. Holds 50% of the session price
/// (configurable via venue_config.pre_booking_hold_percent). Time slots
/// come from venue_config.pre_booking_slots_per_day; capacity is trusted
/// to the RPC (no client-side capacity check for v1 — single venue, low
/// risk, comment marker for future capacity validation).
class PreBookingScreen extends ConsumerStatefulWidget {
  const PreBookingScreen({super.key});

  @override
  ConsumerState<PreBookingScreen> createState() => _PreBookingScreenState();
}

class _PreBookingScreenState extends ConsumerState<PreBookingScreen> {
  String? _selectedChildId;
  DateTime? _selectedDate;
  String? _selectedSlot;
  int _durationMinutes = 60;
  bool _busy = false;
  String? _errorText;

  int _holdPaise(int pricePaise, num holdPercent) =>
      (pricePaise * holdPercent / 100).round();

  Future<void> _pickDate() async {
    final today = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? today,
      firstDate: today,
      lastDate: today.add(const Duration(days: 14)),
    );
    if (picked != null) setState(() => _selectedDate = picked);
  }

  Future<void> _submit({required int amountPaise, required int holdPaise}) async {
    final familyId = ref.read(currentFamilyIdProvider);
    if (familyId == null ||
        _selectedChildId == null ||
        _selectedDate == null ||
        _selectedSlot == null) {
      return;
    }

    final scheduled = _composeScheduledStart(_selectedDate!, _selectedSlot!);
    setState(() {
      _busy = true;
      _errorText = null;
    });

    try {
      final result = await Supabase.instance.client
          .rpc<Map<String, dynamic>>('pre_booking_create', params: {
        'p_venue_id': _venueId,
        'p_family_id': familyId,
        'p_child_id': _selectedChildId,
        'p_scheduled_start': scheduled.toUtc().toIso8601String(),
        'p_duration_minutes': _durationMinutes,
        'p_idempotency_key': const Uuid().v4(),
      });
      if (!mounted) return;
      // push (not pushReplacement) so the pre-book screen stays in the
      // stack underneath. Close/Done on the success screen pop cleanly
      // back to pre-book → user can navigate normally from there.
      // Previous pushReplacement orphaned this screen from GoRouter's
      // stack, causing context.go('/profile') to trigger an infinite
      // push/pop redirect loop.
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => _PreBookingSuccessScreen(
            scheduled: scheduled,
            durationMinutes: _durationMinutes,
            holdPaise: holdPaise,
            balancePaise: amountPaise - holdPaise,
            preBookingId: result['pre_booking_id'] as String?,
          ),
        ),
      );
      // After the success screen pops, return to /profile so the user
      // doesn't land back on the booking form.
      if (mounted) context.go('/profile');
    } on PostgrestException catch (e) {
      setState(() {
        _busy = false;
      });
      if (e.message.contains('insufficient_balance') && mounted) {
        showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => InsufficientBalanceSheet(
            requiredPaise: holdPaise,
            onSwitchToCash: () {}, // No cash path on pre-booking; UI dismisses.
          ),
        );
      } else {
        setState(() => _errorText = "Couldn't reserve. Please try again.");
      }
    } catch (_) {
      setState(() {
        _busy = false;
        _errorText = "Couldn't reserve. Please try again.";
      });
    }
  }

  /// "10:00" + Date → DateTime in local time. Mirrors the slot string
  /// stored on venue_config.pre_booking_slots_per_day.
  DateTime _composeScheduledStart(DateTime date, String hhmm) {
    final parts = hhmm.split(':');
    return DateTime(
      date.year,
      date.month,
      date.day,
      int.parse(parts[0]),
      int.parse(parts[1]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final children = ref.watch(familyChildrenProvider).valueOrNull ?? const [];
    final cfg = ref.watch(venueConfigProvider).valueOrNull ?? const {};
    final balance = ref.watch(walletBalancePaiseProvider) ?? 0;

    final price1hr = (cfg['session_1hr_price_paise'] as int?) ?? 80000;
    final price2hr = (cfg['session_2hr_price_paise'] as int?) ?? 110000;
    final holdPercent = (cfg['pre_booking_hold_percent'] as num?) ?? 50;
    final amountPaise = _durationMinutes == 60 ? price1hr : price2hr;
    final holdPaise = _holdPaise(amountPaise, holdPercent);
    final balanceDue = amountPaise - holdPaise;

    final slots =
        ((cfg['pre_booking_slots_per_day'] as List?) ?? const []).cast<String>();

    final canSubmit = !_busy &&
        _selectedChildId != null &&
        _selectedDate != null &&
        _selectedSlot != null;

    if (children.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Pre-book a session'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.pop(),
          ),
        ),
        body: const _NoChildrenState(),
      );
    }

    // Default-select the first child so the form has a sane starting point.
    _selectedChildId ??= children.first['id'] as String;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pre-book a session'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Reserve a play time in advance.',
                      style: AppTextStyles.body(context),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "We'll hold a slot with a "
                      "${holdPercent.toString().split('.').first}% deposit "
                      'from your wallet. The rest is paid when you check in.',
                      style: AppTextStyles.caption(
                        context,
                        color: AppColors.lightTextSecondary,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text("Who's playing?",
                        style: AppTextStyles.bodyLarge(context)),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 96,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: children.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 12),
                        itemBuilder: (_, i) {
                          final c = children[i];
                          final selected = _selectedChildId == c['id'];
                          return GestureDetector(
                            onTap: () => setState(
                                () => _selectedChildId = c['id'] as String),
                            child: Column(
                              children: [
                                Container(
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: selected
                                          ? AppColors.gold
                                          : AppColors.lightBorder,
                                      width: selected ? 3 : 1,
                                    ),
                                  ),
                                  padding: const EdgeInsets.all(2),
                                  child: ChildAvatar(
                                    name: (c['name'] as String?) ?? '',
                                    size: 56,
                                    photoPath: c['photo_url'] as String?,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                SizedBox(
                                  width: 70,
                                  child: Text(
                                    (c['name'] as String?) ?? '—',
                                    textAlign: TextAlign.center,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppTextStyles.caption(context),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text('Date',
                        style: AppTextStyles.bodyLarge(context)),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _pickDate,
                      icon: const Icon(PhosphorIconsRegular.calendarBlank),
                      label: Text(
                        _selectedDate == null
                            ? 'Pick a date'
                            : DateFormat('EEEE, dd MMM yyyy')
                                .format(_selectedDate!),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text('Time slot',
                        style: AppTextStyles.bodyLarge(context)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final s in slots)
                          ChoiceChip(
                            label: Text(s),
                            selected: _selectedSlot == s,
                            onSelected: (v) {
                              if (v) setState(() => _selectedSlot = s);
                            },
                          ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Text('Duration',
                        style: AppTextStyles.bodyLarge(context)),
                    const SizedBox(height: 8),
                    SegmentedButton<int>(
                      segments: const [
                        ButtonSegment(value: 60, label: Text('1 hour')),
                        ButtonSegment(value: 120, label: Text('2 hours')),
                      ],
                      selected: {_durationMinutes},
                      onSelectionChanged: (s) =>
                          setState(() => _durationMinutes = s.first),
                    ),
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.lightBackground,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          _PriceRow(label: 'Total', value: amountPaise),
                          _PriceRow(
                            label: 'Hold now (from wallet)',
                            value: holdPaise,
                            highlight: true,
                          ),
                          _PriceRow(
                            label: 'Pay at venue',
                            value: balanceDue,
                          ),
                        ],
                      ),
                    ),
                    if (balance < holdPaise) ...[
                      const SizedBox(height: 12),
                      Text(
                        'Wallet balance (${Money.fromPaise(balance)}) is less '
                        'than the deposit. Top up to continue.',
                        style: AppTextStyles.caption(
                          context,
                          color: AppColors.adminRed,
                        ),
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
            SafeArea(
              top: false,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: BoxDecoration(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  border: const Border(
                    top: BorderSide(color: AppColors.lightBorder),
                  ),
                ),
                child: SizedBox(
                  width: double.infinity,
                  child: PrimaryButton(
                    label: 'Hold this slot · ${Money.fromPaise(holdPaise)}',
                    loading: _busy,
                    onPressed: canSubmit
                        ? () => _submit(
                              amountPaise: amountPaise,
                              holdPaise: holdPaise,
                            )
                        : null,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PriceRow extends StatelessWidget {
  final String label;
  final int value;
  final bool highlight;
  const _PriceRow({
    required this.label,
    required this.value,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    final style = highlight
        ? AppTextStyles.bodyLarge(context, color: AppColors.navy)
        : AppTextStyles.body(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: style),
          Text(Money.fromPaise(value), style: style),
        ],
      ),
    );
  }
}

class _NoChildrenState extends StatelessWidget {
  const _NoChildrenState();
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              PhosphorIconsRegular.babyCarriage,
              size: 56,
              color: AppColors.lightTextSecondary,
            ),
            const SizedBox(height: 12),
            Text(
              'Add a child first',
              style: AppTextStyles.h3(context),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Pre-bookings are tied to a child. Add one in your family '
              'list, then come back here.',
              style: AppTextStyles.body(
                context,
                color: AppColors.lightTextSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => context.go('/profile/add-child'),
              child: const Text('Add a child'),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
//  Success screen — minimal confirmation, link back home.
// ---------------------------------------------------------------------------
class _PreBookingSuccessScreen extends StatelessWidget {
  final DateTime scheduled;
  final int durationMinutes;
  final int holdPaise;
  final int balancePaise;
  final String? preBookingId;
  const _PreBookingSuccessScreen({
    required this.scheduled,
    required this.durationMinutes,
    required this.holdPaise,
    required this.balancePaise,
    required this.preBookingId,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reserved'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 24),
              const Icon(
                PhosphorIconsFill.checkCircle,
                size: 64,
                color: AppColors.activeGreen,
              ),
              const SizedBox(height: 16),
              Text(
                'Slot reserved',
                style: AppTextStyles.h1(context),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                DateFormat('EEEE, dd MMM · h:mm a').format(scheduled),
                style: AppTextStyles.bodyLarge(context),
                textAlign: TextAlign.center,
              ),
              Text(
                durationMinutes == 60 ? '1 hour' : '$durationMinutes minutes',
                style: AppTextStyles.body(
                  context,
                  color: AppColors.lightTextSecondary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.lightBackground,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    _PriceRow(label: 'Held from wallet', value: holdPaise),
                    _PriceRow(label: 'Pay at venue', value: balancePaise),
                  ],
                ),
              ),
              const Spacer(),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Done'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
