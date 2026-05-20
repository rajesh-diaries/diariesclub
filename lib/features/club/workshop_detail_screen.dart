// ignore_for_file: deprecated_member_use
// ^ RadioListTile.groupValue/onChanged — see extend_session_sheet.dart.

import 'package:cached_network_image/cached_network_image.dart';
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
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/currency.dart';
import '../../core/widgets/child_avatar.dart';
import '../../core/widgets/error_screen.dart';
import '../../core/widgets/primary_button.dart';
import '../sessions/widgets/insufficient_balance_sheet.dart';
import 'providers/workshops_provider.dart';
import 'widgets/trait_pill.dart';

/// Full detail for a single workshop. Hero image, copy, "what to expect"
/// (placeholder), trait pill, child picker, sticky register button. Calls
/// `workshop_register` RPC; concurrent fills surface as workshop_full
/// errors with a friendly retry.
class WorkshopDetailScreen extends ConsumerStatefulWidget {
  final String workshopId;
  const WorkshopDetailScreen({super.key, required this.workshopId});

  @override
  ConsumerState<WorkshopDetailScreen> createState() =>
      _WorkshopDetailScreenState();
}

class _WorkshopDetailScreenState
    extends ConsumerState<WorkshopDetailScreen> {
  // Set of child IDs the parent picked in this visit. Multi-select so a
  // parent with two kids can register both at once; on a second visit
  // already-registered kids are filtered out before this set is built.
  final Set<String> _selectedChildIds = <String>{};
  String _payment = 'wallet';
  bool _busy = false;
  String? _errorText;
  // Once we've auto-seeded the selection from the eligible-kids list we
  // stop doing it on every rebuild — otherwise toggles get undone.
  bool _autoSeedDone = false;

  Future<bool> _confirmRegister({
    required String workshopTitle,
    required int pricePaise,
    required List<String> childNames,
  }) async {
    final totalPaise = pricePaise * childNames.length;
    final who = _joinNames(childNames);
    final priceLine = childNames.length == 1
        ? Money.fromPaise(pricePaise)
        : '${Money.fromPaise(totalPaise)} (${childNames.length} × ${Money.fromPaise(pricePaise)})';
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Register for this workshop?'),
        content: Text(
          '$who will be registered for "$workshopTitle". '
          '$priceLine will be deducted from your '
          '${_payment == 'wallet' ? 'wallet' : 'cash payment at venue'}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Yes, register'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  String _joinNames(List<String> names) {
    if (names.length == 1) return names.first;
    if (names.length == 2) return '${names[0]} and ${names[1]}';
    return '${names.sublist(0, names.length - 1).join(', ')} and ${names.last}';
  }

  Future<void> _showSuccessSheet({
    required String workshopTitle,
    required List<String> childNames,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
          24, 28, 24, 24 + MediaQuery.of(ctx).padding.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                color: AppColors.activeGreen,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_rounded,
                  color: Colors.white, size: 36),
            ),
            const SizedBox(height: 16),
            Text("You're in!", style: AppTextStyles.h2(context)),
            const SizedBox(height: 8),
            Text(
              '${_joinNames(childNames)} '
              '${childNames.length == 1 ? 'is' : 'are'} registered for '
              '"$workshopTitle". '
              "We'll send a reminder before it starts.",
              textAlign: TextAlign.center,
              style: AppTextStyles.body(
                context,
                color: AppColors.lightTextSecondary,
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: PrimaryButton(
                label: 'Done',
                onPressed: () => Navigator.of(ctx).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _register({
    required int pricePaise,
    required String workshopTitle,
    required List<Map<String, dynamic>> selectedKids,
  }) async {
    final familyId = ref.read(currentFamilyIdProvider);
    if (familyId == null || selectedKids.isEmpty) return;

    final childNames = selectedKids
        .map((c) => (c['name'] as String?) ?? 'your kid')
        .toList();

    final confirmed = await _confirmRegister(
      workshopTitle: workshopTitle,
      pricePaise: pricePaise,
      childNames: childNames,
    );
    if (!confirmed || !mounted) return;

    setState(() {
      _busy = true;
      _errorText = null;
    });

    final registeredNames = <String>[];
    String? error;
    bool insufficient = false;

    // Register kids sequentially. Each call gets its own idempotency_key
    // so a retry on a network blip won't double-book the same kid.
    for (final kid in selectedKids) {
      try {
        await Supabase.instance.client
            .rpc<Map<String, dynamic>>('workshop_register', params: {
          'p_workshop_id': widget.workshopId,
          'p_family_id': familyId,
          'p_child_id': kid['id'],
          'p_payment_method': _payment,
          'p_idempotency_key': const Uuid().v4(),
        });
        registeredNames.add((kid['name'] as String?) ?? 'your kid');
      } on PostgrestException catch (e) {
        if (e.message.contains('workshop_full')) {
          error = 'Sorry, that just filled up. Try another?';
        } else if (e.message.contains('workshop_registration_closed')) {
          error = "Registrations are closed — this workshop has already started.";
        } else if (e.message.contains('insufficient_balance')) {
          insufficient = true;
        } else if (e.message.contains('already_registered')) {
          // Server-side dedup; treat as if it succeeded silently.
          registeredNames.add((kid['name'] as String?) ?? 'your kid');
          continue;
        } else {
          error = "Couldn't register. Please try again.";
        }
        break; // stop the loop on any error
      } catch (_) {
        error = "Couldn't register. Please try again.";
        break;
      }
    }

    if (!mounted) return;
    ref.invalidate(myWorkshopRegistrationsProvider);
    ref.invalidate(workshopByIdProvider(widget.workshopId));

    if (registeredNames.isNotEmpty) {
      await _showSuccessSheet(
        workshopTitle: workshopTitle,
        childNames: registeredNames,
      );
      if (!mounted) return;
      // If everyone we wanted got in and no leftover error, leave the
      // detail screen. If we stopped mid-loop, stay so the parent sees
      // the error and can retry the remaining kids.
      if (error == null && !insufficient) {
        context.pop();
        return;
      }
    }

    setState(() {
      _busy = false;
      _selectedChildIds.removeWhere(
        (id) => registeredNames.contains(
          selectedKids.firstWhere((k) => k['id'] == id,
              orElse: () => const {})['name'],
        ),
      );
      if (error != null) _errorText = error;
    });

    if (insufficient) {
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => InsufficientBalanceSheet(
          requiredPaise:
              pricePaise * (selectedKids.length - registeredNames.length),
          onSwitchToCash: () {
            if (!mounted) return;
            setState(() => _payment = 'cash');
          },
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(workshopByIdProvider(widget.workshopId));
    final children = ref.watch(familyChildrenProvider).valueOrNull ?? const [];
    final balance = ref.watch(walletBalancePaiseProvider) ?? 0;
    final myRegs =
        ref.watch(myWorkshopRegistrationsProvider).valueOrNull ?? const [];

    return async.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        body: FriendlyErrorScreen(
          code: 'E-WSP',
          userMessage: "Couldn't load workshop",
          technicalDetails: e.toString(),
        ),
      ),
      data: (workshop) {
        if (workshop == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text("This workshop doesn't exist."),
              ),
            ),
          );
        }

        final price = (workshop['price_paise'] as int?) ?? 0;
        final spots = (workshop['spots_remaining'] as int?) ?? 0;
        final capacity = (workshop['capacity'] as int?) ?? 0;
        final isFull = spots == 0;
        final isLow = spots > 0 && spots <= 3;
        // Server-side cutoff: registrations close 10 min after the
        // workshop's scheduled start time. Mirror that in the UI so the
        // Register button disables (and shows why) before the user
        // submits.
        final scheduledLocal = DateTime.tryParse(
          (workshop['scheduled_at'] as String?) ?? '',
        )?.toLocal();
        final isClosedForReg = scheduledLocal != null &&
            DateTime.now().isAfter(
              scheduledLocal.add(const Duration(minutes: 10)),
            );

        // child_ids in this family already registered for *this* workshop.
        // Surfaces a "Registered" pill on those avatars and prevents the
        // parent from selecting them again.
        final registeredChildIds = myRegs
            .where((r) => r['workshop_id'] == widget.workshopId)
            .map((r) => r['child_id'] as String?)
            .whereType<String>()
            .toSet();
        final eligibleChildren = children
            .where((c) => !registeredChildIds.contains(c['id'] as String))
            .toList();
        final anyRegistered = registeredChildIds.isNotEmpty;
        final allChildrenRegistered =
            children.isNotEmpty && eligibleChildren.isEmpty;

        // Auto-seed selection once: if every eligible kid is unregistered
        // and the parent hasn't picked yet, pre-select all eligibles when
        // there's a single kid, or leave empty when there are multiple
        // so the parent makes an explicit choice.
        if (!_autoSeedDone && eligibleChildren.isNotEmpty) {
          _autoSeedDone = true;
          if (eligibleChildren.length == 1) {
            _selectedChildIds.add(eligibleChildren.first['id'] as String);
          }
        }

        return Scaffold(
          appBar: AppBar(
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => context.pop(),
            ),
            actions: [
              if (anyRegistered)
                Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.activeGreen.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(100),
                      ),
                      child: Text(
                        children.length > 1
                            ? '${registeredChildIds.length}/${children.length} registered'
                            : 'Registered',
                        style: AppTextStyles.caption(
                          context,
                          color: AppColors.activeGreen,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          body: SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _Hero(workshop: workshop),
                        Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                (workshop['title'] as String?) ?? '',
                                style: AppTextStyles.h2(context),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                _meta(workshop),
                                style: AppTextStyles.caption(
                                  context,
                                  color: AppColors.lightTextSecondary,
                                ),
                              ),
                              if ((workshop['description'] as String?)
                                          ?.isNotEmpty ==
                                      true) ...[
                                const SizedBox(height: 16),
                                Text(
                                  workshop['description'] as String,
                                  style: AppTextStyles.body(context),
                                ),
                              ],
                              if (!allChildrenRegistered) ...[
                                const SizedBox(height: 20),
                                _AvailabilityRow(
                                  isFull: isFull,
                                  isLow: isLow,
                                  spots: spots,
                                  capacity: capacity,
                                ),
                              ],
                              const SizedBox(height: 20),
                              if (children.isEmpty)
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: AppColors.warningYellow
                                        .withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    'Add a child in your profile before registering.',
                                    style: AppTextStyles.caption(
                                      context,
                                      color: AppColors.lightTextPrimary,
                                    ),
                                  ),
                                )
                              else ...[
                                Text(
                                  children.length > 1
                                      ? 'WHO IS COMING? (TAP TO SELECT)'
                                      : 'WHO IS COMING?',
                                  style: AppTextStyles.caption(
                                    context,
                                    color: AppColors.lightTextSecondary,
                                  ).copyWith(letterSpacing: 1.0),
                                ),
                                const SizedBox(height: 8),
                                _ChildPicker(
                                  children: children,
                                  selectedIds: _selectedChildIds,
                                  registeredIds: registeredChildIds,
                                  onToggle: (id) => setState(() {
                                    if (_selectedChildIds.contains(id)) {
                                      _selectedChildIds.remove(id);
                                    } else {
                                      _selectedChildIds.add(id);
                                    }
                                  }),
                                ),
                                if (allChildrenRegistered) ...[
                                  const SizedBox(height: 12),
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: AppColors.activeGreen
                                          .withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      'All your kids are already registered for this workshop.',
                                      style: AppTextStyles.caption(
                                        context,
                                        color: AppColors.lightTextPrimary,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                              if (!allChildrenRegistered) ...[
                                const SizedBox(height: 20),
                                Text(
                                  'PAYMENT',
                                  style: AppTextStyles.caption(
                                    context,
                                    color: AppColors.lightTextSecondary,
                                  ).copyWith(letterSpacing: 1.0),
                                ),
                                RadioListTile<String>(
                                  value: 'wallet',
                                  groupValue: _payment,
                                  title: Text(
                                    'Wallet (${Money.fromPaise(balance)})',
                                  ),
                                  subtitle: balance <
                                          (price *
                                              (_selectedChildIds.isEmpty
                                                  ? 1
                                                  : _selectedChildIds.length))
                                      ? const Text(
                                          'Not enough balance',
                                          style: TextStyle(
                                              color: AppColors.adminRed),
                                        )
                                      : null,
                                  onChanged: (v) =>
                                      setState(() => _payment = v ?? 'wallet'),
                                ),
                                RadioListTile<String>(
                                  value: 'cash',
                                  groupValue: _payment,
                                  title: const Text('Pay at venue'),
                                  onChanged: (v) =>
                                      setState(() => _payment = v ?? 'cash'),
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
                      ],
                    ),
                  ),
                ),
                SafeArea(
                  top: false,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).scaffoldBackgroundColor,
                      border: const Border(
                        top: BorderSide(color: AppColors.lightBorder),
                      ),
                    ),
                    child: SizedBox(
                      width: double.infinity,
                      child: PrimaryButton(
                        label: () {
                          if (allChildrenRegistered) {
                            return 'All kids registered';
                          }
                          if (isClosedForReg) {
                            return 'Registrations closed';
                          }
                          if (isFull) return 'Workshop full';
                          if (children.isEmpty) return 'Add a kid first';
                          final n = _selectedChildIds.length;
                          if (n == 0) {
                            return eligibleChildren.length > 1
                                ? 'Select a kid to register'
                                : 'Register · ${Money.fromPaise(price)}';
                          }
                          final total = price * n;
                          return n > 1
                              ? 'Register $n kids · ${Money.fromPaise(total)}'
                              : 'Register · ${Money.fromPaise(price)}';
                        }(),
                        loading: _busy,
                        onPressed: allChildrenRegistered ||
                                isClosedForReg ||
                                isFull ||
                                children.isEmpty ||
                                _selectedChildIds.isEmpty ||
                                _busy
                            ? null
                            : () {
                                final picked = eligibleChildren
                                    .where((c) => _selectedChildIds
                                        .contains(c['id'] as String))
                                    .toList();
                                if (picked.isEmpty) return;
                                _register(
                                  pricePaise: price,
                                  workshopTitle:
                                      (workshop['title'] as String?) ?? 'this workshop',
                                  selectedKids: picked,
                                );
                              },
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _meta(Map<String, dynamic> w) {
    final scheduledStr = w['scheduled_at'] as String?;
    final scheduled =
        scheduledStr == null ? null : DateTime.tryParse(scheduledStr)?.toLocal();
    final ageMin = w['age_group_min'] as int?;
    final ageMax = w['age_group_max'] as int?;
    final duration = (w['duration_minutes'] as int?) ?? 0;
    return [
      if (scheduled != null)
        DateFormat('EEEE MMM d · h:mm a').format(scheduled)
      else
        'Date TBA',
      if (ageMin != null && ageMax != null) 'Ages $ageMin–$ageMax',
      '$duration min',
    ].join(' · ');
  }
}

class _Hero extends StatelessWidget {
  final Map<String, dynamic> workshop;
  const _Hero({required this.workshop});

  @override
  Widget build(BuildContext context) {
    final cover = workshop['cover_image_url'] as String?;
    final trait = workshop['primary_trait'] as String?;
    return SizedBox(
      height: 220,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (cover != null && cover.isNotEmpty)
            CachedNetworkImage(
              imageUrl: cover,
              fit: BoxFit.cover,
              errorWidget: (_, __, ___) =>
                  Container(color: AppColors.gold.withValues(alpha: 0.20)),
            )
          else
            Container(color: AppColors.gold.withValues(alpha: 0.20)),
          if (trait != null)
            Positioned(
              top: 16,
              right: 16,
              child: TraitPill(trait: trait, light: true),
            ),
        ],
      ),
    );
  }
}

class _AvailabilityRow extends StatelessWidget {
  final bool isFull;
  final bool isLow;
  final int spots;
  final int capacity;
  const _AvailabilityRow({
    required this.isFull,
    required this.isLow,
    required this.spots,
    required this.capacity,
  });

  @override
  Widget build(BuildContext context) {
    // "X of Y spots remaining" hidden per founder request — looked empty
    // on barely-booked workshops. Workshop-full state stays so customers
    // don't tap Register on a sold-out slot.
    if (!isFull) return const SizedBox.shrink();
    return Row(
      children: [
        const Icon(PhosphorIconsRegular.users,
            color: AppColors.adminRed, size: 18),
        const SizedBox(width: 8),
        Text(
          'Workshop full',
          style: AppTextStyles.body(context, color: AppColors.adminRed),
        ),
      ],
    );
  }
}

class _ChildPicker extends StatelessWidget {
  final List<Map<String, dynamic>> children;
  final Set<String> selectedIds;
  final Set<String> registeredIds;
  final ValueChanged<String> onToggle;
  const _ChildPicker({
    required this.children,
    required this.selectedIds,
    required this.registeredIds,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 112,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: children.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (_, i) {
          final c = children[i];
          final id = c['id'] as String;
          final name = (c['name'] as String?) ?? '';
          final isRegistered = registeredIds.contains(id);
          final selected = selectedIds.contains(id);
          return GestureDetector(
            onTap: isRegistered ? null : () => onToggle(id),
            child: Opacity(
              opacity: isRegistered ? 0.55 : 1.0,
              child: Column(
                children: [
                  Stack(
                    clipBehavior: Clip.none,
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
                          name: name,
                          size: 56,
                        ),
                      ),
                      if (selected)
                        Positioned(
                          right: -2,
                          bottom: -2,
                          child: Container(
                            width: 22,
                            height: 22,
                            decoration: const BoxDecoration(
                              color: AppColors.gold,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.check_rounded,
                              color: Colors.white,
                              size: 14,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  SizedBox(
                    width: 76,
                    child: Text(
                      name,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.caption(context),
                    ),
                  ),
                  if (isRegistered)
                    Text(
                      'Registered',
                      style: AppTextStyles.caption(
                        context,
                        color: AppColors.activeGreen,
                      ).copyWith(fontSize: 10),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
