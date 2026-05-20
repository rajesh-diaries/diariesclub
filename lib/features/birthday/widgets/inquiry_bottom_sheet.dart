import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/family_children_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/venues.dart';
import '../../../core/widgets/primary_button.dart';
import '../providers/reservation_providers.dart';

const _venueId = Venues.kondapurId;

/// Inquiry form rendered as a modal bottom sheet on top of the packages
/// screen. Replaces the old `/birthday/reserve/:packageId` screen — same
/// fields, same submit RPC, but the parent never leaves the package
/// context they tapped from. Child + slot_date are pre-filled.
class InquiryBottomSheet extends ConsumerStatefulWidget {
  final Map<String, dynamic> package;
  final String? preselectedChildId;

  const InquiryBottomSheet({
    super.key,
    required this.package,
    this.preselectedChildId,
  });

  @override
  ConsumerState<InquiryBottomSheet> createState() =>
      _InquiryBottomSheetState();
}

class _InquiryBottomSheetState extends ConsumerState<InquiryBottomSheet> {
  String? _selectedChildId;
  DateTime? _slotDate;
  String _slot = 'morning';
  late int _guestCount;
  bool _dateManuallyEdited = false;
  bool _busy = false;
  String? _errorText;
  // Cached across retries so that a transient network blip after the
  // server completed doesn't strand the user — re-submit with the same
  // key returns the existing reservation as success (RPC short-circuits
  // on idempotency_key match).
  String? _idempotencyKey;

  @override
  void initState() {
    super.initState();
    final minG = (widget.package['min_guests'] as int?) ?? 25;
    _guestCount = minG > 0 ? minG : 25;
    _selectedChildId = widget.preselectedChildId;
  }

  /// Compute the next occurrence of the kid's birthday.
  DateTime _defaultDateForChild(Map<String, dynamic> child) {
    final dobStr = child['date_of_birth'] as String?;
    final today = DateUtils.dateOnly(DateTime.now());
    if (dobStr == null || dobStr.isEmpty) {
      return today.add(const Duration(days: 30));
    }
    final dob = DateTime.tryParse(dobStr);
    if (dob == null) return today.add(const Duration(days: 30));
    var candidate = DateTime(today.year, dob.month, dob.day);
    if (candidate.isBefore(today)) {
      candidate = DateTime(today.year + 1, dob.month, dob.day);
    }
    return candidate;
  }

  void _onChildPicked(String? id, List<Map<String, dynamic>> children) {
    setState(() {
      final isNewKid = id != _selectedChildId;
      _selectedChildId = id;
      if (isNewKid) _dateManuallyEdited = false;
      if (id != null && !_dateManuallyEdited) {
        final child = children.firstWhere(
          (c) => c['id'] == id,
          orElse: () => const <String, dynamic>{},
        );
        if (child.isNotEmpty) {
          _slotDate = _defaultDateForChild(child);
        }
      }
    });
  }

  Future<void> _pickDate() async {
    final today = DateUtils.dateOnly(DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: _slotDate ?? today.add(const Duration(days: 30)),
      firstDate: today,
      lastDate: today.add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() {
        _slotDate = picked;
        _dateManuallyEdited = true;
      });
    }
  }

  Future<void> _submit() async {
    if (_selectedChildId == null) {
      setState(() => _errorText = 'Pick the birthday kid.');
      return;
    }
    if (_slotDate == null) {
      setState(() => _errorText = 'Pick a date.');
      return;
    }
    if (_guestCount <= 0) {
      setState(() => _errorText = 'Add an approximate guest count.');
      return;
    }

    final familyId = ref.read(currentFamilyIdProvider);
    if (familyId == null) return;

    setState(() {
      _busy = true;
      _errorText = null;
    });

    final dateOnly =
        '${_slotDate!.year.toString().padLeft(4, '0')}-'
        '${_slotDate!.month.toString().padLeft(2, '0')}-'
        '${_slotDate!.day.toString().padLeft(2, '0')}';

    _idempotencyKey ??= const Uuid().v4();

    try {
      final result = await Supabase.instance.client
          .rpc<Map<String, dynamic>>('birthday_inquiry_submit', params: {
        'p_venue_id': _venueId,
        'p_family_id': familyId,
        'p_child_id': _selectedChildId,
        'p_package_id': widget.package['id'],
        'p_slot_date': dateOnly,
        'p_slot': _slot,
        'p_guest_count': _guestCount,
        'p_special_requests': null,
        'p_triggered_by': 'packages_sheet',
        'p_idempotency_key': _idempotencyKey,
      });

      final reservationId = result['reservation_id'] as String?;
      if (reservationId == null) {
        throw StateError('birthday_inquiry_submit returned no id');
      }
      ref.invalidate(familyReservationsProvider);
      if (!mounted) return;
      Navigator.of(context).pop();
      context.go('/birthday/status/$reservationId');
    } on PostgrestException catch (e) {
      debugPrint('[INQUIRY] PostgrestException code=${e.code} '
          'message=${e.message} details=${e.details} hint=${e.hint}');
      // If the server says "you already have an open inquiry," surface
      // the existing one instead of dead-ending the user.
      if (e.message.contains('reservation_exists')) {
        await _recoverToExistingReservation();
        return;
      }
      if (!mounted) return;
      setState(() {
        _busy = false;
        _errorText = _mapErrorMessage(e.message);
      });
    } catch (e, st) {
      debugPrint('[INQUIRY] generic exception: $e\n$st');
      // Generic exception path covers the case where the server already
      // committed the reservation but the client never saw the response
      // (network blip, parsing edge case). Look up the active reservation
      // for this child; if found, navigate to it as if the submit succeeded.
      final recovered = await _recoverToExistingReservation();
      if (recovered) return;
      if (!mounted) return;
      setState(() {
        _busy = false;
        _errorText = "Couldn't submit: $e";
      });
    }
  }

  /// Look up the most-recent open reservation for the selected child and
  /// navigate to its status page. Returns true if recovery worked.
  Future<bool> _recoverToExistingReservation() async {
    if (_selectedChildId == null) return false;
    try {
      final rows = await Supabase.instance.client
          .from('birthday_reservations')
          .select('id')
          .eq('child_id', _selectedChildId!)
          .inFilter('status', const [
            'interested',
            'admin_contacted',
            'confirmed',
          ])
          .order('created_at', ascending: false)
          .limit(1);
      if (rows.isEmpty) return false;
      final id = (rows.first as Map)['id'] as String?;
      if (id == null) return false;
      ref.invalidate(familyReservationsProvider);
      if (!mounted) return true;
      Navigator.of(context).pop();
      context.go('/birthday/status/$id');
      return true;
    } catch (_) {
      return false;
    }
  }

  String _mapErrorMessage(String message) {
    final minG = widget.package['min_guests'];
    final maxG = widget.package['max_guests'];
    if (message.contains('reservation_exists')) {
      return 'You already have an open inquiry for this child. Cancel it first to start a new one.';
    }
    if (message.contains('guest_count_below_min')) {
      return minG != null
          ? 'This package needs at least $minG guests.'
          : 'Guest count is below the minimum.';
    }
    if (message.contains('guest_count_above_max')) {
      return maxG != null
          ? 'This package fits up to $maxG guests.'
          : 'Guest count exceeds the maximum.';
    }
    if (message.contains('invalid_slot_date')) return 'Pick a valid date.';
    if (message.contains('invalid_slot')) return 'Pick Morning or Evening.';
    if (message.contains('not_authorised')) {
      return 'Session expired — sign out and back in to continue.';
    }
    if (message.contains('invalid_package')) {
      return "This package isn't available right now.";
    }
    if (message.contains('invalid_guest_count')) {
      return 'Add an approximate guest count.';
    }
    // Surface the raw message so we can see the actual failure during
    // testing instead of a generic "try again". Trim verbose hints.
    return "Couldn't submit: $message";
  }

  @override
  Widget build(BuildContext context) {
    final children = ref.watch(familyChildrenProvider).valueOrNull ?? const [];
    final minG = (widget.package['min_guests'] as int?) ?? 25;
    final maxG = (widget.package['max_guests'] as int?) ?? 200;
    final pkgName = (widget.package['name'] as String?) ?? 'this package';

    return DraggableScrollableSheet(
      initialChildSize: 0.78,
      minChildSize: 0.55,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: SingleChildScrollView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Drag handle
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
                Text('Inquire about $pkgName',
                    style: AppTextStyles.h2(context)),
                const SizedBox(height: 20),

                if (children.length > 1) ...[
                  _SectionLabel('Whose birthday'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final c in children)
                        _ChildChip(
                          name: (c['name'] as String?) ?? 'Child',
                          selected: c['id'] == _selectedChildId,
                          onTap: () => _onChildPicked(
                            c['id'] as String?,
                            children,
                          ),
                        ),
                    ],
                  ),
                  // When preselectedChildId arrives via the widget arg,
                  // initState marks _selectedChildId without ever calling
                  // _onChildPicked — so the date pre-fill never fires.
                  // Trigger it here on first build once children are
                  // loaded and we know which kid is selected.
                  if (_selectedChildId != null &&
                      _slotDate == null &&
                      !_dateManuallyEdited)
                    Builder(
                      builder: (_) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (!mounted) return;
                          _onChildPicked(_selectedChildId, children);
                        });
                        return const SizedBox.shrink();
                      },
                    ),
                  const SizedBox(height: 20),
                ] else if (children.length == 1 && _selectedChildId == null) ...[
                  // Single child — auto-pick on first frame and skip the
                  // chip row entirely (no decision to make).
                  Builder(
                    builder: (_) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (!mounted) return;
                        _onChildPicked(children.first['id'] as String?, children);
                      });
                      return const SizedBox.shrink();
                    },
                  ),
                ],

                _SectionLabel('Date of celebration'),
                const SizedBox(height: 8),
                _RowButton(
                  icon: PhosphorIconsRegular.calendarBlank,
                  label: _slotDate == null
                      ? 'Pick a date'
                      : '${_slotDate!.day} ${_monthName(_slotDate!.month)} ${_slotDate!.year}',
                  onTap: _pickDate,
                  highlight: _slotDate != null,
                ),
                if (_selectedChildId != null && !_dateManuallyEdited) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Pre-filled from your child\'s date of birth. Tap to change.',
                    style: AppTextStyles.caption(
                      context,
                      color: AppColors.lightTextSecondary,
                    ),
                  ),
                ],
                const SizedBox(height: 20),

                _SectionLabel('Slot'),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _SlotChip(
                      label: 'Morning',
                      selected: _slot == 'morning',
                      onTap: () => setState(() => _slot = 'morning'),
                    ),
                    const SizedBox(width: 8),
                    _SlotChip(
                      label: 'Evening',
                      selected: _slot == 'evening',
                      onTap: () => setState(() => _slot = 'evening'),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                _SectionLabel('Approximate guest count'),
                const SizedBox(height: 8),
                _GuestStepper(
                  count: _guestCount,
                  min: minG,
                  max: maxG,
                  onChanged: (v) => setState(() => _guestCount = v),
                ),
                const SizedBox(height: 6),
                Text(
                  'Allowed range: $minG–$maxG guests for this package.',
                  style: AppTextStyles.caption(
                    context,
                    color: AppColors.lightTextSecondary,
                  ),
                ),

                if (_errorText != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _errorText!,
                    style: AppTextStyles.caption(
                      context,
                      color: AppColors.adminRed,
                    ),
                  ),
                ],

                const SizedBox(height: 24),
                PrimaryButton(
                  label: 'Submit inquiry',
                  onPressed: _busy ? null : _submit,
                  loading: _busy,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _monthName(int m) => const [
        '',
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec'
      ][m];
}

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel(this.label);
  @override
  Widget build(BuildContext context) =>
      Text(label, style: AppTextStyles.bodyLarge(context));
}

class _ChildChip extends StatelessWidget {
  final String name;
  final bool selected;
  final VoidCallback onTap;
  const _ChildChip({
    required this.name,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(100),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppColors.navy : Colors.white,
          border: Border.all(
            color: selected ? AppColors.navy : AppColors.lightBorder,
          ),
          borderRadius: BorderRadius.circular(100),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selected) ...[
              const Icon(Icons.check, size: 16, color: Colors.white),
              const SizedBox(width: 6),
            ],
            Text(
              name,
              style: AppTextStyles.body(
                context,
                color: selected ? Colors.white : AppColors.lightTextPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SlotChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _SlotChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? AppColors.navy : Colors.white,
            border: Border.all(
              color: selected ? AppColors.navy : AppColors.lightBorder,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            label,
            style: AppTextStyles.body(
              context,
              color: selected ? Colors.white : AppColors.lightTextPrimary,
            ),
          ),
        ),
      ),
    );
  }
}

class _RowButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool highlight;
  const _RowButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(
            color: highlight ? AppColors.navy : AppColors.lightBorder,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: AppColors.navy),
            const SizedBox(width: 12),
            Text(label, style: AppTextStyles.body(context)),
          ],
        ),
      ),
    );
  }
}

class _GuestStepper extends StatelessWidget {
  final int count;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;
  const _GuestStepper({
    required this.count,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.lightBorder),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.remove),
            onPressed: count > min ? () => onChanged(count - 5) : null,
          ),
          Expanded(
            child: Center(
              child: Text(
                '$count',
                style: AppTextStyles.h3(context),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: count < max ? () => onChanged(count + 5) : null,
          ),
        ],
      ),
    );
  }
}
