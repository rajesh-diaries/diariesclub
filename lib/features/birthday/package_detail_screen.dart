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
  String? _preferredMonth;
  String? _preferredWindow;
  int _numKids = 15;
  int _numAdults = 10;
  final _specialRequests = TextEditingController();
  bool _busy = false;
  String? _errorText;

  static const _windowOptions = <(String, String)>[
    ('weekend_morning', 'Weekend morning'),
    ('weekend_afternoon', 'Weekend afternoon'),
    ('weekend_evening', 'Weekend evening'),
    ('weekday_evening', 'Weekday evening'),
  ];

  @override
  void dispose() {
    _specialRequests.dispose();
    super.dispose();
  }

  List<String> _monthOptions() {
    final now = DateTime.now();
    return List.generate(12, (i) {
      final d = DateTime(now.year, now.month + i, 1);
      const months = [
        'January', 'February', 'March', 'April', 'May', 'June',
        'July', 'August', 'September', 'October', 'November', 'December',
      ];
      return '${months[d.month - 1]} ${d.year}';
    });
  }

  Future<void> _submit({
    required Map<String, dynamic> package,
  }) async {
    if (_selectedChildId == null) {
      setState(() => _errorText = 'Pick a child for this birthday.');
      return;
    }
    if (_preferredMonth == null) {
      setState(() => _errorText = 'Pick a rough month.');
      return;
    }
    if (_preferredWindow == null) {
      setState(() => _errorText = 'Pick a rough time of day.');
      return;
    }

    final familyId = ref.read(currentFamilyIdProvider);
    if (familyId == null) return;

    setState(() {
      _busy = true;
      _errorText = null;
    });

    final idem = const Uuid().v4();

    try {
      final result = await Supabase.instance.client
          .rpc<Map<String, dynamic>>('birthday_reservation_create', params: {
        'p_venue_id': _venueId,
        'p_family_id': familyId,
        'p_child_id': _selectedChildId,
        'p_package_id': widget.packageId,
        'p_preferred_month': _preferredMonth,
        'p_preferred_window': _preferredWindow,
        'p_num_kids': _numKids,
        'p_num_adults': _numAdults,
        'p_special_requests':
            _specialRequests.text.trim().isEmpty
                ? null
                : _specialRequests.text.trim(),
        'p_triggered_by': widget.triggeredBy ?? 'manual',
        'p_idempotency_key': idem,
      });

      final reservationId = result['reservation_id'] as String?;
      if (reservationId == null) {
        throw StateError('birthday_reservation_create returned no id');
      }
      if (!mounted) return;
      context.go('/birthday/status/$reservationId');
    } on PostgrestException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      if (e.message.contains('reservation_exists')) {
        _showExistingReservationSheet();
      } else if (e.message.contains('invalid_kids')) {
        setState(() => _errorText =
            'Too many kids for this package (max ${package['max_kids']}).');
      } else if (e.message.contains('invalid_adults')) {
        setState(() => _errorText =
            'Too many adults for this package (max ${package['max_adults']}).');
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
    final price = (package['price_paise'] as int?) ?? 0;
    final maxKids = (package['max_kids'] as int?) ?? 30;
    final maxAdults = (package['max_adults'] as int?) ?? 30;

    final gallery = <String>[
      ...((package['gallery_image_urls'] as List?) ?? const [])
          .whereType<String>(),
    ];
    final cover = package['cover_image_url'] as String?;
    if (gallery.isEmpty && cover != null && cover.isNotEmpty) {
      gallery.add(cover);
    }

    return Stack(
      children: [
        ListView(
          padding: const EdgeInsets.only(bottom: 120),
          children: [
            _Carousel(images: gallery),
            _PriceBar(
              pricePaise: price,
              maxKids: maxKids,
              maxAdults: maxAdults,
            ),
            const SizedBox(height: 16),
            const _SectionHeader(text: "What's included"),
            _Inclusions(
              json: (package['inclusions'] as Map?)?.cast<String, dynamic>() ??
                  const {},
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
              onChildChanged: (v) => setState(() => _selectedChildId = v),
              preferredMonth: _preferredMonth,
              monthOptions: _monthOptions(),
              onMonthChanged: (v) => setState(() => _preferredMonth = v),
              preferredWindow: _preferredWindow,
              windowOptions: _windowOptions,
              onWindowChanged: (v) => setState(() => _preferredWindow = v),
              numKids: _numKids,
              maxKids: maxKids,
              onKidsChanged: (v) => setState(() => _numKids = v),
              numAdults: _numAdults,
              maxAdults: maxAdults,
              onAdultsChanged: (v) => setState(() => _numAdults = v),
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
  final int pricePaise;
  final int maxKids;
  final int maxAdults;
  const _PriceBar({
    required this.pricePaise,
    required this.maxKids,
    required this.maxAdults,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      color: AppColors.lightSurface,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                Money.fromPaise(pricePaise),
                style: AppTextStyles.h1(context, color: AppColors.gold),
              ),
              Text(
                'All-inclusive · No surprises',
                style: AppTextStyles.caption(
                  context,
                  color: AppColors.lightTextSecondary,
                ),
              ),
            ],
          ),
          const Spacer(),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'Up to $maxKids kids',
                style: AppTextStyles.body(context),
              ),
              Text(
                '$maxAdults adults',
                style: AppTextStyles.caption(
                  context,
                  color: AppColors.lightTextSecondary,
                ),
              ),
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
  final Map<String, dynamic> json;
  const _Inclusions({required this.json});

  @override
  Widget build(BuildContext context) {
    final lines = <String>[];
    json.forEach((key, value) {
      if (value == null) return;
      final label = key
          .replaceAll('_', ' ')
          .split(' ')
          .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
          .join(' ');
      lines.add('$label: $value');
    });
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final l in lines)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
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

  final String? preferredMonth;
  final List<String> monthOptions;
  final ValueChanged<String?> onMonthChanged;

  final String? preferredWindow;
  final List<(String, String)> windowOptions;
  final ValueChanged<String?> onWindowChanged;

  final int numKids;
  final int maxKids;
  final ValueChanged<int> onKidsChanged;

  final int numAdults;
  final int maxAdults;
  final ValueChanged<int> onAdultsChanged;

  final TextEditingController specialRequests;

  const _PreferencesForm({
    required this.children,
    required this.selectedChildId,
    required this.onChildChanged,
    required this.preferredMonth,
    required this.monthOptions,
    required this.onMonthChanged,
    required this.preferredWindow,
    required this.windowOptions,
    required this.onWindowChanged,
    required this.numKids,
    required this.maxKids,
    required this.onKidsChanged,
    required this.numAdults,
    required this.maxAdults,
    required this.onAdultsChanged,
    required this.specialRequests,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (children.length > 1) ...[
            Text(
              'For which child?',
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
          ],
          Text('Roughly when?', style: AppTextStyles.bodyLarge(context)),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: preferredMonth,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
            ),
            hint: const Text('Pick a month'),
            items: [
              for (final m in monthOptions)
                DropdownMenuItem(value: m, child: Text(m)),
            ],
            onChanged: onMonthChanged,
          ),
          const SizedBox(height: 16),
          Text('Time of day?', style: AppTextStyles.bodyLarge(context)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final w in windowOptions)
                ChoiceChip(
                  label: Text(w.$2),
                  selected: preferredWindow == w.$1,
                  onSelected: (_) => onWindowChanged(w.$1),
                ),
            ],
          ),
          const SizedBox(height: 16),
          _Stepper(
            label: 'Number of kids',
            value: numKids,
            min: 1,
            max: maxKids,
            onChanged: onKidsChanged,
          ),
          const SizedBox(height: 12),
          _Stepper(
            label: 'Number of adults',
            value: numAdults,
            min: 0,
            max: maxAdults,
            onChanged: onAdultsChanged,
          ),
          const SizedBox(height: 16),
          Text(
            'Anything special? (optional)',
            style: AppTextStyles.bodyLarge(context),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: specialRequests,
            maxLength: 200,
            maxLines: 3,
            inputFormatters: [LengthLimitingTextInputFormatter(200)],
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'Allergies, themes, surprises…',
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
              label: 'Reserve interest',
              loading: busy,
              onPressed: busy ? null : onPressed,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            "No payment yet — we'll WhatsApp you within 24 hours.",
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
