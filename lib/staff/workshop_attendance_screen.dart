import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_text_styles.dart';
import 'widgets/staff_pin_sheet.dart';

/// Workshops list for the staff app. Two screens:
///
///   - `WorkshopAttendanceScreen` — pick a workshop to manage.
///   - `WorkshopRegistrationsScreen` — per-workshop registrations,
///     each with a "Mark attended" toggle. Calls
///     `staff_workshop_mark_attended` RPC (added in migration 0141),
///     which forwards to `workshop_attend` — XP credits to the kid via
///     the standard splitter and the customer's past_workshops_screen
///     flips "Missed" → "Attended" the next time they open it.
///
/// Tablet device auth is asserted inside the RPC; the staff PIN is
/// captured via `StaffPinSheet` before the actual mark.

class WorkshopAttendanceScreen extends ConsumerWidget {
  const WorkshopAttendanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_workshopsListProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Workshops'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              "Couldn't load workshops.\n$e",
              textAlign: TextAlign.center,
              style: AppTextStyles.body(context),
            ),
          ),
        ),
        data: (rows) {
          if (rows.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'No workshops scheduled.',
                  style: AppTextStyles.body(
                    context,
                    color: AppColors.lightTextSecondary,
                  ),
                ),
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(_workshopsListProvider),
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: rows.length,
              separatorBuilder: (_, __) =>
                  const Divider(height: 1, color: AppColors.lightBorder),
              itemBuilder: (_, i) {
                final w = rows[i];
                final scheduled = DateTime.tryParse(
                        (w['scheduled_at'] as String?) ?? '')
                    ?.toLocal();
                final label = scheduled == null
                    ? '—'
                    : DateFormat('EEE MMM d · h:mm a').format(scheduled);
                final capacity = (w['capacity'] as int?) ?? 0;
                final spotsLeft = (w['spots_remaining'] as int?) ?? 0;
                final filled = capacity - spotsLeft;
                return ListTile(
                  leading: const Icon(
                    PhosphorIconsRegular.graduationCap,
                    color: AppColors.navy,
                  ),
                  title: Text((w['title'] as String?) ?? '—',
                      style: AppTextStyles.body(context)),
                  subtitle: Text(
                    '$label · $filled/$capacity registered',
                    style: AppTextStyles.caption(
                      context,
                      color: AppColors.lightTextSecondary,
                    ),
                  ),
                  trailing: const Icon(Icons.chevron_right,
                      color: AppColors.lightTextSecondary),
                  onTap: () => context.push(
                    '/staff/workshops/${w['id']}/attendance',
                    extra: {'title': w['title']},
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

final _workshopsListProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final rows = await Supabase.instance.client
      .from('workshops')
      .select(
        'id, title, scheduled_at, capacity, spots_remaining',
      )
      .eq('is_published', true)
      .order('scheduled_at', ascending: false)
      .limit(50);
  return List<Map<String, dynamic>>.from(rows);
});

// ===========================================================================
//  Per-workshop registrations + mark attended
// ===========================================================================

class WorkshopRegistrationsScreen extends ConsumerWidget {
  final String workshopId;
  final String? title;
  const WorkshopRegistrationsScreen({
    super.key,
    required this.workshopId,
    this.title,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_registrationsProvider(workshopId));
    return Scaffold(
      appBar: AppBar(
        title: Text(title ?? 'Registrations'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              "Couldn't load registrations.\n$e",
              textAlign: TextAlign.center,
              style: AppTextStyles.body(context),
            ),
          ),
        ),
        data: (rows) {
          if (rows.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'No registrations for this workshop yet.',
                  style: AppTextStyles.body(
                    context,
                    color: AppColors.lightTextSecondary,
                  ),
                ),
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () async =>
                ref.invalidate(_registrationsProvider(workshopId)),
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: rows.length,
              separatorBuilder: (_, __) =>
                  const Divider(height: 1, color: AppColors.lightBorder),
              itemBuilder: (_, i) => _RegistrationRow(
                row: rows[i],
                onMarked: () =>
                    ref.invalidate(_registrationsProvider(workshopId)),
              ),
            ),
          );
        },
      ),
    );
  }
}

final _registrationsProvider = FutureProvider.family
    .autoDispose<List<Map<String, dynamic>>, String>((ref, workshopId) async {
  final rows = await Supabase.instance.client.rpc<dynamic>(
    'staff_workshop_list_registrations',
    params: {'p_workshop_id': workshopId},
  );
  return (rows as List)
      .map((r) => Map<String, dynamic>.from(r as Map))
      .toList();
});

class _RegistrationRow extends StatefulWidget {
  final Map<String, dynamic> row;
  final VoidCallback onMarked;
  const _RegistrationRow({required this.row, required this.onMarked});

  @override
  State<_RegistrationRow> createState() => _RegistrationRowState();
}

class _RegistrationRowState extends State<_RegistrationRow> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final r = widget.row;
    final attended = r['attended'] == true;
    final cancelled = r['cancelled_at'] != null;
    final name = (r['child_name'] as String?) ?? 'Kid';
    final dobStr = r['child_dob'] as String?;
    final dob = dobStr == null ? null : DateTime.tryParse(dobStr);
    final ageLabel = dob == null
        ? ''
        : '${(DateTime.now().difference(dob).inDays / 365).floor()}y';

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: (attended ? AppColors.activeGreen : AppColors.navy)
            .withValues(alpha: 0.15),
        child: Icon(
          attended
              ? PhosphorIconsFill.checkCircle
              : PhosphorIconsFill.smiley,
          color: attended ? AppColors.activeGreen : AppColors.navy,
        ),
      ),
      title: Text(
        '$name${ageLabel.isEmpty ? '' : ' · $ageLabel'}',
        style: AppTextStyles.body(context).copyWith(
          decoration: cancelled ? TextDecoration.lineThrough : null,
          color:
              cancelled ? AppColors.lightTextSecondary : null,
        ),
      ),
      subtitle: cancelled
          ? const Text('Cancelled')
          : Text(
              attended ? 'Attended · XP credited' : 'Not marked yet',
              style: AppTextStyles.caption(
                context,
                color: attended
                    ? AppColors.activeGreen
                    : AppColors.lightTextSecondary,
              ),
            ),
      trailing: cancelled
          ? null
          : attended
              ? const Icon(PhosphorIconsFill.checkCircle,
                  color: AppColors.activeGreen)
              : FilledButton(
                  onPressed: _busy ? null : _mark,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.navy,
                    foregroundColor: Colors.white,
                  ),
                  child: _busy
                      ? const SizedBox(
                          height: 14,
                          width: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation(Colors.white),
                          ),
                        )
                      : const Text('Mark attended'),
                ),
    );
  }

  Future<void> _mark() async {
    final staff = await StaffPinSheet.show(
      context,
      actionLabel: 'Mark workshop attendance',
    );
    if (staff == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await Supabase.instance.client.rpc<Map<String, dynamic>>(
        'staff_workshop_mark_attended',
        params: {
          'p_registration_id': widget.row['id'],
          'p_staff_pin_id': staff.staffId,
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.activeGreen,
          content: Text(
            '${widget.row['child_name'] ?? 'Kid'} marked attended — XP credited',
          ),
        ),
      );
      widget.onMarked();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not mark attended: $e')),
      );
      setState(() => _busy = false);
    }
  }
}
