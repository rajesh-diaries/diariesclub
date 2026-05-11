import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import '../../core/providers/auth_provider.dart';
import '../../core/providers/family_children_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/currency.dart';
import '../../core/widgets/error_screen.dart';
import '../../core/widgets/primary_button.dart';
import 'providers/birthday_packages_provider.dart';

const _venueId = '00000000-0000-0000-0000-000000000001';

/// Package detail + reserve interest screen — the conversion screen.
/// Layout: hero carousel → price bar → inclusions → not-included →
/// "how booking works" → preferences form → sticky CTA. Submits via
/// `birthday_reservation_create` RPC and routes to /birthday/status/:id
/// on success. No deposit; admin completes the deal offline.
class PackageDetailScreen extends ConsumerStatefulWidget {
  final String packageId;
  final String? triggeredBy;
  const PackageDetailScreen({
    super.key,
    required this.packageId,
    this.triggeredBy,
  });

  @override
  ConsumerState<PackageDetailScreen> createState() =>
      _PackageDetailScreenState();
}

class _PackageDetailScreenState extends ConsumerState<PackageDetailScreen> {
  String? _selectedChildId;
  DateTime? _slotDate;
  // 'morning' | 'evening'
  String _slot = 'morning';
  int _guestCount = 30;
  // Tracks whether the parent manually picked a date — if not, we
  // re-prefill when the child selection changes.
  bool _dateManuallyEdited = false;
  final _specialRequests = TextEditingController();
  bool _busy = false;
  String? _errorText;

  @override
  void dispose() {
    _specialRequests.dispose();
    super.dispose();
  }

  /// Compute the next occurrence of the kid's birthday (today or later).
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

  void _selectChild(String? id, List<Map<String, dynamic>> children) {
    setState(() {
      _selectedChildId = id;
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

  Future<void> _submit({
    required Map<String, dynamic> package,
  }) async {
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

    final idem = const Uuid().v4();
    final dateOnly =
        '${_slotDate!.year.toString().padLeft(4, '0')}-'
        '${_slotDate!.month.toString().padLeft(2, '0')}-'
        '${_slotDate!.day.toString().padLeft(2, '0')}';

    try {
      final result = await Supabase.instance.client
          .rpc<Map<String, dynamic>>('birthday_inquiry_submit', params: {
        'p_venue_id': _venueId,
        'p_family_id': familyId,
        'p_child_id': _selectedChildId,
        'p_package_id': widget.packageId,
        'p_slot_date': dateOnly,
        'p_slot': _slot,
        'p_guest_count': _guestCount,
        'p_special_requests':
            _specialRequests.text.trim().isEmpty
                ? null
                : _specialRequests.text.trim(),
        'p_triggered_by': widget.triggeredBy ?? 'manual',
        'p_idempotency_key': idem,
      });

      final reservationId = result['reservation_id'] as String?;
      if (reservationId == null) {
        throw StateError('birthday_inquiry_submit returned no id');
      }
      if (!mounted) return;
      context.go('/birthday/status/$reservationId');
    } on PostgrestException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      if (e.message.contains('reservation_exists')) {
        _showExistingReservationSheet();
      } else if (e.message.contains('guest_count_below_min')) {
        final minG = package['min_guests'];
        setState(() => _errorText = minG != null
            ? 'This package needs at least $minG guests. Add more guests or pick a smaller package.'
            : 'Guest count is below the minimum.');
      } else if (e.message.contains('guest_count_above_max')) {
        final maxG = package['max_guests'];
        setState(() => _errorText = maxG != null
            ? 'This package fits up to $maxG guests. Reduce the count or pick a bigger package.'
            : 'Guest count exceeds the maximum.');
      } else if (e.message.contains('invalid_guest_count')) {
        setState(() => _errorText = 'Add an approximate guest count.');
      } else if (e.message.contains('invalid_slot')) {
        setState(() => _errorText = 'Pick Morning or Evening.');
      } else if (e.message.contains('invalid_slot_date')) {
        setState(() => _errorText = 'Pick a valid date.');
      } else if (e.message.contains('invalid_package')) {
        setState(() => _errorText = "This package isn't available right now.");
      } else {
        setState(() => _errorText = "Couldn't submit. Please try again.");
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _errorText = "Couldn't submit. Please try again.";
      });
    }
  }

  void _showExistingReservationSheet() {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetCtx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'You already have an active reservation',
                style: AppTextStyles.h3(sheetCtx),
              ),
              const SizedBox(height: 8),
              Text(
                'Only one active reservation per child per year. Cancel '
                "the existing one first if you'd like to switch packages.",
                style: AppTextStyles.body(
                  sheetCtx,
                  color: AppColors.lightTextSecondary,
                ),
              ),
              const SizedBox(height: 24),
              PrimaryButton(
                label: 'View existing reservation',
                onPressed: () {
                  Navigator.of(sheetCtx).pop();
                  context.go('/birthday');
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pkgAsync = ref.watch(birthdayPackageByIdProvider(widget.packageId));
    final children = ref.watch(familyChildrenProvider).valueOrNull ?? const [];

    if (_selectedChildId == null && children.isNotEmpty) {
      _selectedChildId = children.first['id'] as String?;
    }

    return Scaffold(
      appBar: AppBar(
        title: pkgAsync.maybeWhen(
          data: (p) => Text(p?['name'] as String? ?? 'Package'),
          orElse: () => const Text('Package'),
        ),
      ),
      body: pkgAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => FriendlyErrorScreen(
          code: 'E-PKG',
          userMessage: "Couldn't load this package",
          technicalDetails: e.toString(),
        ),
        data: (package) {
          if (package == null) {
            return const FriendlyErrorScreen(
              code: 'E-PKG-404',
              userMessage: "We couldn't find that package.",
            );
          }
          return _buildContent(package, children);
        },
      ),
    );
  }

  Widget _buildContent(
    Map<String, dynamic> package,
    List<Map<String, dynamic>> children,
  ) {
    final priceVeg = (package['price_per_pax_veg_paise'] as int?) ?? 0;
    final priceNonVeg = (package['price_per_pax_non_veg_paise'] as int?) ?? 0;
    final hallName = (package['hall_name'] as String?) ?? '';
    final minGuests = (package['min_guests'] as int?) ?? 0;
    final maxGuests = (package['max_guests'] as int?) ?? 200;

    final gallery = <String>[
      ...((package['gallery_image_urls'] as List?) ?? const [])
          .whereType<String>(),
    ];
    final cover = package['cover_image_url'] as String?;
    if (gallery.isEmpty && cover != null && cover.isNotEmpty) {
      gallery.add(cover);
    }

    // First-time landing — auto-pick first kid + prefill date.
    if (_selectedChildId == null && children.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _selectChild(children.first['id'] as String?, children);
      });
    }

    return Stack(
      children: [
        ListView(
          padding: const EdgeInsets.only(bottom: 120),
          children: [
            _Carousel(images: gallery),
            _PriceBar(
              priceVegPaise: priceVeg,
              priceNonVegPaise: priceNonVeg,
              hallName: hallName,
              minGuests: minGuests,
              maxGuests: maxGuests,
            ),
            const SizedBox(height: 16),
            const _SectionHeader(text: 'Menu'),
            _Inclusions(raw: package['inclusions']),
            const SizedBox(height: 16),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: _UniversalIncludesDetail(),
            ),
            const SizedBox(height: 16),
            const _SectionHeader(text: 'Not included'),
            const _NotIncluded(),
            const SizedBox(height: 16),
            // Module 2.7: customer can download admin-generated PDF if cached.
            if ((package['pdf_url'] as String?)?.isNotEmpty ?? false)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: OutlinedButton.icon(
                  icon: const Icon(PhosphorIconsRegular.filePdf),
                  label: const Text('Download menu PDF'),
                  onPressed: () =>
                      launchUrl(Uri.parse(package['pdf_url'] as String)),
                ),
              ),
            const SizedBox(height: 16),
            const _SectionHeader(text: 'How booking works'),
            const _HowItWorks(),
            const SizedBox(height: 16),
            const _SectionHeader(text: 'Your preferences'),
            _PreferencesForm(
              children: children,
              selectedChildId: _selectedChildId,
              onChildChanged: (v) => _selectChild(v, children),
              slotDate: _slotDate,
              onPickDate: () async {
                final today = DateUtils.dateOnly(DateTime.now());
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _slotDate ?? today.add(const Duration(days: 30)),
                  firstDate: today,
                  lastDate: today.add(const Duration(days: 365 * 2)),
                );
                if (picked != null) {
                  setState(() {
                    _slotDate = picked;
                    _dateManuallyEdited = true;
                  });
                }
              },
              slot: _slot,
              onSlotChanged: (v) => setState(() => _slot = v),
              guestCount: _guestCount,
              minGuests: minGuests,
              maxGuests: maxGuests,
              onGuestCountChanged: (v) => setState(() => _guestCount = v),
              specialRequests: _specialRequests,
            ),
            if (_errorText != null) ...[
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  _errorText!,
                  style: AppTextStyles.caption(
                    context,
                    color: AppColors.adminRed,
                  ),
                ),
              ),
            ],
          ],
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: _StickyCta(
            busy: _busy,
            onPressed: () => _submit(package: package),
          ),
        ),
      ],
    );
  }
}

class _Carousel extends StatefulWidget {
  final List<String> images;
  const _Carousel({required this.images});

  @override
  State<_Carousel> createState() => _CarouselState();
}

class _CarouselState extends State<_Carousel> {
  final _controller = PageController();
  int _index = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.images.isEmpty) {
      return Container(
        height: 220,
        color: AppColors.gold.withValues(alpha: 0.20),
        alignment: Alignment.center,
        child: const Icon(
          PhosphorIconsFill.cake,
          color: AppColors.gold,
          size: 64,
        ),
      );
    }
    return SizedBox(
      height: 240,
      child: Stack(
        children: [
          PageView.builder(
            controller: _controller,
            itemCount: widget.images.length,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (_, i) => CachedNetworkImage(
              imageUrl: widget.images[i],
              fit: BoxFit.cover,
              errorWidget: (_, __, ___) => Container(
                color: AppColors.gold.withValues(alpha: 0.20),
              ),
            ),
          ),
          if (widget.images.length > 1)
            Positioned(
              left: 0,
              right: 0,
              bottom: 12,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(widget.images.length, (i) {
                  final active = i == _index;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: active ? 18 : 6,
                    height: 6,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(
                      color: active
                          ? Colors.white
                          : Colors.white.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  );
                }),
              ),
            ),
        ],
      ),
    );
  }
}

class _PriceBar extends StatelessWidget {
  final int priceVegPaise;
  final int priceNonVegPaise;
  final String hallName;
  final int minGuests;
  final int maxGuests;
  const _PriceBar({
    required this.priceVegPaise,
    required this.priceNonVegPaise,
    required this.hallName,
    required this.minGuests,
    required this.maxGuests,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      color: AppColors.lightSurface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Veg ${Money.fromPaise(priceVegPaise)} · '
                      'Non-Veg ${Money.fromPaise(priceNonVegPaise)}',
                      style: AppTextStyles.h3(context, color: AppColors.gold),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Per pax · 18% GST extra',
                      style: AppTextStyles.caption(
                        context,
                        color: AppColors.lightTextSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (hallName.isNotEmpty) ...[
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      hallName,
                      style: AppTextStyles.body(context).copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      '$minGuests–$maxGuests guests',
                      style: AppTextStyles.caption(
                        context,
                        color: AppColors.lightTextSecondary,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader({required this.text});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Text(
        text,
        style: AppTextStyles.h3(context),
      ),
    );
  }
}

class _Inclusions extends StatelessWidget {
  // Accepts either:
  //   * List<String> — the new shape ([1 Welcome Drink, 2 Starters, ...])
  //   * Map<String, dynamic> — legacy shape (key:value pairs we humanise)
  final dynamic raw;
  const _Inclusions({required this.raw});

  @override
  Widget build(BuildContext context) {
    final lines = <String>[];
    if (raw is List) {
      for (final item in raw as List) {
        if (item == null) continue;
        final s = item.toString().trim();
        if (s.isNotEmpty) lines.add(s);
      }
    } else if (raw is Map) {
      (raw as Map).forEach((key, value) {
        if (value == null) return;
        final label = key.toString()
            .replaceAll('_', ' ')
            .split(' ')
            .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
            .join(' ');
        lines.add('$label: $value');
      });
    }
    if (lines.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Text(
          'Your team will share the full inclusions list on WhatsApp.',
          style: AppTextStyles.body(
            context,
            color: AppColors.lightTextSecondary,
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: LayoutBuilder(
        builder: (context, c) {
          final twoColumn = c.maxWidth >= 360;
          final colWidth = twoColumn ? (c.maxWidth - 12) / 2 : c.maxWidth;
          return Wrap(
            spacing: 12,
            runSpacing: 6,
            children: [
              for (final l in lines)
                SizedBox(
                  width: colWidth,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 3),
                        child: Icon(
                          PhosphorIconsFill.checkCircle,
                          size: 18,
                          color: AppColors.activeGreen,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(l, style: AppTextStyles.body(context)),
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// Universal venue benefits — every birthday package at Diaries Club
/// includes these regardless of tier. Hardcoded constant; promote to
/// venue_config later if it ever varies.
const _universalIncludesDetail = <(IconData, String)>[
  (Icons.access_time, '2.5 hours play'),
  (Icons.meeting_room, '3 hours hall'),
  (Icons.restaurant_menu, 'Food buffet'),
];

class _UniversalIncludesDetail extends StatelessWidget {
  const _UniversalIncludesDetail();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.lightBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.lightBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'ALL PACKAGES INCLUDE',
            style: AppTextStyles.caption(
              context, color: AppColors.lightTextSecondary,
            ).copyWith(letterSpacing: 0.8, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              for (final (icon, label) in _universalIncludesDetail)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 18, color: AppColors.navy),
                    const SizedBox(width: 6),
                    Text(label, style: AppTextStyles.body(context)),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _NotIncluded extends StatelessWidget {
  const _NotIncluded();

  @override
  Widget build(BuildContext context) {
    const lines = [
      'Return gifts',
      'Custom photographer',
      'Outside food',
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final l in lines)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  const Icon(
                    PhosphorIconsRegular.minusCircle,
                    size: 18,
                    color: AppColors.lightTextSecondary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    l,
                    style: AppTextStyles.body(
                      context,
                      color: AppColors.lightTextSecondary,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _HowItWorks extends StatelessWidget {
  const _HowItWorks();

  @override
  Widget build(BuildContext context) {
    const steps = [
      ('1', 'Tell us roughly when, and how many guests.'),
      ('2', "We'll WhatsApp you within 24 hours to lock the date."),
      ('3',
          'On confirmation, we collect a deposit offline (cash/UPI to our team).'),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final s in steps)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 26,
                    height: 26,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      color: AppColors.navy,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      s.$1,
                      style:
                          AppTextStyles.caption(context, color: Colors.white),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        s.$2,
                        style: AppTextStyles.body(context),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _PreferencesForm extends StatelessWidget {
  final List<Map<String, dynamic>> children;
  final String? selectedChildId;
  final ValueChanged<String?> onChildChanged;

  final DateTime? slotDate;
  final VoidCallback onPickDate;

  final String slot;
  final ValueChanged<String> onSlotChanged;

  final int guestCount;
  final int minGuests;
  final int maxGuests;
  final ValueChanged<int> onGuestCountChanged;

  final TextEditingController specialRequests;

  const _PreferencesForm({
    required this.children,
    required this.selectedChildId,
    required this.onChildChanged,
    required this.slotDate,
    required this.onPickDate,
    required this.slot,
    required this.onSlotChanged,
    required this.guestCount,
    required this.minGuests,
    required this.maxGuests,
    required this.onGuestCountChanged,
    required this.specialRequests,
  });

  static const _months = [
    'Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'
  ];

  String _formatDate(DateTime d) =>
      '${d.day} ${_months[d.month - 1]} ${d.year}';

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Whose birthday?',
            style: AppTextStyles.bodyLarge(context),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final c in children)
                ChoiceChip(
                  label: Text((c['name'] as String?) ?? '—'),
                  selected: selectedChildId == c['id'],
                  onSelected: (_) => onChildChanged(c['id'] as String?),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text('Date', style: AppTextStyles.bodyLarge(context)),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: onPickDate,
            icon: const Icon(PhosphorIconsRegular.calendar),
            label: Text(
              slotDate == null ? 'Pick a date' : _formatDate(slotDate!),
            ),
          ),
          const SizedBox(height: 16),
          Text('Slot', style: AppTextStyles.bodyLarge(context)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: const Text('Morning'),
                selected: slot == 'morning',
                onSelected: (_) => onSlotChanged('morning'),
              ),
              ChoiceChip(
                label: const Text('Evening'),
                selected: slot == 'evening',
                onSelected: (_) => onSlotChanged('evening'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _Stepper(
            label: 'Approximate guest count',
            value: guestCount,
            min: 1,
            max: maxGuests,
            onChanged: onGuestCountChanged,
          ),
          const SizedBox(height: 4),
          Text(
            'This package fits $minGuests–$maxGuests guests',
            style: AppTextStyles.caption(
              context,
              color: AppColors.lightTextSecondary,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Anything special? (optional)',
            style: AppTextStyles.bodyLarge(context),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: specialRequests,
            maxLength: 300,
            maxLines: 4,
            inputFormatters: [LengthLimitingTextInputFormatter(300)],
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText:
                  'Themes, dietary needs, decoration ideas, photographer…',
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.lightBackground,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.lightBorder),
            ),
            child: Text(
              'These packages are starting points. For better customization, '
              'our team will reach out within 4 hours to plan the details.',
              style: AppTextStyles.caption(
                context,
                color: AppColors.lightTextSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Stepper extends StatelessWidget {
  final String label;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;
  const _Stepper({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(label, style: AppTextStyles.bodyLarge(context)),
        ),
        IconButton(
          icon: const Icon(PhosphorIconsRegular.minusCircle),
          onPressed: value > min ? () => onChanged(value - 1) : null,
        ),
        SizedBox(
          width: 40,
          child: Center(
            child: Text(
              '$value',
              style: AppTextStyles.h3(context),
            ),
          ),
        ),
        IconButton(
          icon: const Icon(PhosphorIconsRegular.plusCircle),
          onPressed: value < max ? () => onChanged(value + 1) : null,
        ),
      ],
    );
  }
}

class _StickyCta extends StatelessWidget {
  final bool busy;
  final VoidCallback onPressed;
  const _StickyCta({required this.busy, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        12 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: const BoxDecoration(
        color: AppColors.lightSurface,
        border: Border(
          top: BorderSide(color: AppColors.lightBorder),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: double.infinity,
            child: PrimaryButton(
              label: 'Submit inquiry',
              loading: busy,
              onPressed: busy ? null : onPressed,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            "No payment in app — we'll reach out within 4 hours.",
            style: AppTextStyles.caption(
              context,
              color: AppColors.lightTextSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
