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
  String? _selectedChildId;
  String _payment = 'wallet';
  bool _busy = false;
  String? _errorText;

  Future<void> _register({
    required int pricePaise,
  }) async {
    final familyId = ref.read(currentFamilyIdProvider);
    if (familyId == null || _selectedChildId == null) return;
    setState(() {
      _busy = true;
      _errorText = null;
    });

    try {
      await Supabase.instance.client
          .rpc<Map<String, dynamic>>('workshop_register', params: {
        'p_workshop_id': widget.workshopId,
        'p_family_id': familyId,
        'p_child_id': _selectedChildId,
        'p_payment_method': _payment,
        'p_idempotency_key': const Uuid().v4(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: AppColors.activeGreen,
          content: Text('Registered. See you there!'),
        ),
      );
      context.pop();
    } on PostgrestException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      if (e.message.contains('workshop_full')) {
        setState(() => _errorText =
            'Sorry, that just filled up. Try another?');
      } else if (e.message.contains('insufficient_balance')) {
        showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => InsufficientBalanceSheet(
            requiredPaise: pricePaise,
            onSwitchToCash: () {
              if (!mounted) return;
              setState(() => _payment = 'cash');
            },
          ),
        );
      } else {
        setState(() => _errorText = "Couldn't register. Please try again.");
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _errorText = "Couldn't register. Please try again.";
      });
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

        if (children.isNotEmpty && _selectedChildId == null) {
          _selectedChildId = children.first['id'] as String;
        }

        final price = (workshop['price_paise'] as int?) ?? 0;
        final spots = (workshop['spots_remaining'] as int?) ?? 0;
        final capacity = (workshop['capacity'] as int?) ?? 0;
        final isFull = spots == 0;
        final isLow = spots > 0 && spots <= 3;
        final alreadyRegistered = myRegs.any(
          (r) => r['workshop_id'] == widget.workshopId,
        );

        return Scaffold(
          appBar: AppBar(
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => context.pop(),
            ),
            actions: [
              if (alreadyRegistered)
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
                        'Registered',
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
                              const SizedBox(height: 20),
                              _AvailabilityRow(
                                isFull: isFull,
                                isLow: isLow,
                                spots: spots,
                                capacity: capacity,
                              ),
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
                                  'WHO IS COMING?',
                                  style: AppTextStyles.caption(
                                    context,
                                    color: AppColors.lightTextSecondary,
                                  ).copyWith(letterSpacing: 1.0),
                                ),
                                const SizedBox(height: 8),
                                _ChildPicker(
                                  children: children,
                                  selectedId: _selectedChildId,
                                  onSelect: (id) =>
                                      setState(() => _selectedChildId = id),
                                ),
                              ],
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
                                subtitle: balance < price
                                    ? const Text(
                                        'Not enough balance',
                                        style:
                                            TextStyle(color: AppColors.adminRed),
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
                        label: alreadyRegistered
                            ? "You're already registered"
                            : isFull
                                ? 'Workshop full'
                                : 'Register · ${Money.fromPaise(price)}',
                        loading: _busy,
                        onPressed: alreadyRegistered ||
                                isFull ||
                                children.isEmpty ||
                                _busy
                            ? null
                            : () => _register(pricePaise: price),
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
    final color = isFull
        ? AppColors.adminRed
        : isLow
            ? AppColors.warningYellow
            : AppColors.lightTextSecondary;
    final label = isFull
        ? 'Workshop full'
        : '$spots of $capacity spots remaining';
    return Row(
      children: [
        Icon(PhosphorIconsRegular.users, color: color, size: 18),
        const SizedBox(width: 8),
        Text(label, style: AppTextStyles.body(context, color: color)),
      ],
    );
  }
}

class _ChildPicker extends StatelessWidget {
  final List<Map<String, dynamic>> children;
  final String? selectedId;
  final ValueChanged<String> onSelect;
  const _ChildPicker({
    required this.children,
    required this.selectedId,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 96,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: children.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (_, i) {
          final c = children[i];
          final id = c['id'] as String;
          final name = (c['name'] as String?) ?? '';
          final selected = id == selectedId;
          return GestureDetector(
            onTap: () => onSelect(id),
            child: Column(
              children: [
                Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: selected ? AppColors.gold : AppColors.lightBorder,
                      width: selected ? 3 : 1,
                    ),
                  ),
                  padding: const EdgeInsets.all(2),
                  child: ChildAvatar(
                    name: name,
                    size: 56,
                    photoPath: c['photo_url'] as String?,
                  ),
                ),
                const SizedBox(height: 4),
                SizedBox(
                  width: 70,
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
        },
      ),
    );
  }
}
