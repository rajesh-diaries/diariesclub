import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/currency.dart';
import '../providers/admin_streams.dart';
import '../widgets/admin_app_bar.dart';
import '../widgets/admin_buttons.dart';

const _venueId = '00000000-0000-0000-0000-000000000001';

/// Module 2.8 — comprehensive venue_config editor. Sections are
/// expansion tiles so the page stays scannable. Each section has its
/// own Save button that fires admin_set_venue_config with a small
/// patch (server-side audit-logged + whitelisted).
class ConfigScreen extends ConsumerWidget {
  const ConfigScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(adminVenueConfigProvider(_venueId));

    return Scaffold(
      backgroundColor: AppColors.lightBackground,
      appBar: const AdminAppBar(title: 'Config'),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text("Couldn't load: $e")),
        data: (config) => _ConfigForm(
          config: config,
          onSaved: () => ref.invalidate(adminVenueConfigProvider(_venueId)),
        ),
      ),
    );
  }
}

class _ConfigForm extends StatefulWidget {
  final Map<String, dynamic> config;
  final VoidCallback onSaved;
  const _ConfigForm({required this.config, required this.onSaved});

  @override
  State<_ConfigForm> createState() => _ConfigFormState();
}

class _ConfigFormState extends State<_ConfigForm> {
  bool _busy = false;
  String? _errorText;

  Future<void> _save(Map<String, dynamic> patch) async {
    setState(() {
      _busy = true;
      _errorText = null;
    });
    try {
      await Supabase.instance.client.rpc<dynamic>(
        'admin_set_venue_config',
        params: {'p_venue_id': _venueId, 'p_patch': patch},
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Config saved.')),
      );
      widget.onSaved();
    } on PostgrestException catch (e) {
      if (!mounted) return;
      setState(() => _errorText = "Couldn't save: ${e.message}");
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorText = "Couldn't save: $e");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.config;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 920),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Each section saves independently. Changes are audit-logged.',
              style: AppTextStyles.body(
                context,
                color: AppColors.lightTextSecondary,
              ),
            ),
            const SizedBox(height: 16),

            _PricingSection(config: c, busy: _busy, save: _save),
            const SizedBox(height: 12),
            _GstSection(config: c, busy: _busy, save: _save),
            const SizedBox(height: 12),
            _TopupSection(config: c, busy: _busy, save: _save),
            const SizedBox(height: 12),
            _CashbackSection(config: c, busy: _busy, save: _save),
            const SizedBox(height: 12),
            _XpSection(config: c, busy: _busy, save: _save),
            const SizedBox(height: 12),
            // Visit milestones — parked. Config is saved to
            // venue_config.visit_milestones but no RPC reads it yet.
            // Re-enable the section here when the award flow is wired
            // (visit_count increment + threshold check + reward_xp +
            // reward_paise wallet credit + customer-facing display).
            // _MilestonesSection(config: c, busy: _busy, save: _save),
            // const SizedBox(height: 12),
            _BirthdaySection(config: c, busy: _busy, save: _save),
            const SizedBox(height: 12),
            _SessionTimingSection(config: c, busy: _busy, save: _save),
            const SizedBox(height: 12),
            _AppVersionSection(config: c, busy: _busy, save: _save),
            const SizedBox(height: 12),
            _ContactSection(config: c, busy: _busy, save: _save),
            const SizedBox(height: 12),
            _ClubTaglinesSection(config: c, busy: _busy, save: _save),
            const SizedBox(height: 12),
            _WorkshopsSection(config: c, busy: _busy, save: _save),
            const SizedBox(height: 12),
            _BirthdaysTabSection(config: c, busy: _busy, save: _save),
            const SizedBox(height: 12),
            _FeatureFlagsSection(config: c, busy: _busy, save: _save),

            if (_errorText != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.adminRed.withValues(alpha: 0.10),
                  border: Border.all(
                    color: AppColors.adminRed.withValues(alpha: 0.40),
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _errorText!,
                  style: AppTextStyles.body(context, color: AppColors.adminRed),
                ),
              ),
            ],

            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.lightBackground,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Out of scope (v1.1)',
                    style: AppTextStyles.caption(
                      context,
                      color: AppColors.lightTextSecondary,
                    ).copyWith(letterSpacing: 1, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Notification copy templates — needs sendNotification refactor before strings can be admin-edited. '
                    'Reactivation campaign defaults — paired with Session 13 cron + MSG91. '
                    'Two-person debit toggle is on the feature flags row but the worker pairing UI is out-of-scope.',
                    style: AppTextStyles.caption(
                      context,
                      color: AppColors.lightTextSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =====================================================================
// Section: Pricing.
// =====================================================================
class _PricingSection extends StatefulWidget {
  final Map<String, dynamic> config;
  final bool busy;
  final Future<void> Function(Map<String, dynamic>) save;
  const _PricingSection(
      {required this.config, required this.busy, required this.save});
  @override
  State<_PricingSection> createState() => _PricingSectionState();
}

class _PricingSectionState extends State<_PricingSection> {
  late final _oneHr = TextEditingController(
    text: ((widget.config['session_1hr_price_paise'] as int? ?? 0) ~/ 100)
        .toString(),
  );
  late final _twoHr = TextEditingController(
    text: ((widget.config['session_2hr_price_paise'] as int? ?? 0) ~/ 100)
        .toString(),
  );
  late final _ext = TextEditingController(
    text:
        ((widget.config['session_extension_per_hour_paise'] as int? ?? 0) ~/ 100)
            .toString(),
  );
  late final _extOptions = JsonbListEditor(
    initial: widget.config['session_extension_options'] as List? ?? [],
    fields: const [
      JsonbField('minutes', 'Minutes', isInt: true),
      JsonbField('label', 'Label'),
      JsonbField('price_paise', 'Price (paise)', isInt: true),
    ],
  );

  late final _slots = TextEditingController(
    text: jsonEncode(widget.config['pre_booking_slots_per_day'] ?? []),
  );

  @override
  void dispose() {
    _oneHr.dispose();
    _twoHr.dispose();
    _ext.dispose();
    _slots.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: 'Pricing',
      icon: PhosphorIconsRegular.currencyInr,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _RupeeField(label: '1-hour session', controller: _oneHr),
          _RupeeField(label: '2-hour session', controller: _twoHr),
          _RupeeField(label: 'Extension per hour', controller: _ext),
          const SizedBox(height: 12),
          Text('Extension quick options',
              style: AppTextStyles.body(context).copyWith(
                fontWeight: FontWeight.w700,
              )),
          const SizedBox(height: 8),
          _extOptions,
          const SizedBox(height: 12),
          Text('Pre-booking time slots (HH:MM array)',
              style: AppTextStyles.body(context).copyWith(
                fontWeight: FontWeight.w700,
              )),
          const SizedBox(height: 8),
          _JsonTextarea(
            controller: _slots,
            hint: '["10:00","11:00", ...]',
            minLines: 2,
          ),
          _SaveBar(
            busy: widget.busy,
            onSave: () async {
              List<dynamic> slots;
              try {
                slots = jsonDecode(_slots.text) as List<dynamic>;
              } catch (_) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Slots must be a JSON array')),
                );
                return;
              }
              await widget.save({
                'session_1hr_price_paise':
                    (int.tryParse(_oneHr.text) ?? 0) * 100,
                'session_2hr_price_paise':
                    (int.tryParse(_twoHr.text) ?? 0) * 100,
                'session_extension_per_hour_paise':
                    (int.tryParse(_ext.text) ?? 0) * 100,
                'session_extension_options': _extOptions.snapshot(),
                'pre_booking_slots_per_day': slots,
              });
            },
          ),
        ],
      ),
    );
  }
}

// =====================================================================
// Section: GST.
// =====================================================================
class _GstSection extends StatefulWidget {
  final Map<String, dynamic> config;
  final bool busy;
  final Future<void> Function(Map<String, dynamic>) save;
  const _GstSection(
      {required this.config, required this.busy, required this.save});
  @override
  State<_GstSection> createState() => _GstSectionState();
}

class _GstSectionState extends State<_GstSection> {
  late final _gst = TextEditingController(
    text: '${widget.config['gst_percent'] ?? 18}',
  );
  late final _walkinGst = TextEditingController(
    text: '${widget.config['walkin_food_gst_percent'] ?? 5}',
  );

  @override
  void dispose() {
    _gst.dispose();
    _walkinGst.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: 'GST',
      icon: PhosphorIconsRegular.receipt,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.gold.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(PhosphorIconsRegular.warning,
                    size: 16, color: AppColors.gold),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Confirm any GST change with the CA before saving — '
                    'rates flow through every receipt.',
                    style: AppTextStyles.caption(context),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _NumField(
            label: 'GST percent (app + walk-in PLAY, inclusive)',
            controller: _gst,
            hint: 'e.g. 18',
          ),
          _NumField(
            label: 'Walk-in FOOD GST percent (exclusive, on top)',
            controller: _walkinGst,
            hint: 'e.g. 5',
          ),
          _SaveBar(
            busy: widget.busy,
            onSave: () => widget.save({
              'gst_percent': double.tryParse(_gst.text) ?? 18,
              'walkin_food_gst_percent':
                  double.tryParse(_walkinGst.text) ?? 5,
            }),
          ),
        ],
      ),
    );
  }
}

// =====================================================================
// Section: Topup offers.
// =====================================================================
class _TopupSection extends StatefulWidget {
  final Map<String, dynamic> config;
  final bool busy;
  final Future<void> Function(Map<String, dynamic>) save;
  const _TopupSection(
      {required this.config, required this.busy, required this.save});
  @override
  State<_TopupSection> createState() => _TopupSectionState();
}

class _TopupSectionState extends State<_TopupSection> {
  late final JsonbListEditor _editor = JsonbListEditor(
    initial: widget.config['topup_offers'] as List? ?? [],
    fields: const [
      JsonbField('amount_paise', 'Amount (paise)', isInt: true),
      JsonbField('bonus_paise', 'Bonus (paise)', isInt: true),
      JsonbField('label', 'Label'),
      JsonbField('badge', 'Badge'),
    ],
  );

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: 'Topup offers',
      icon: PhosphorIconsRegular.wallet,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Quick-pick amounts shown on the wallet topup sheet. '
            'Amounts and bonuses are stored in paise (₹1 = 100 paise).',
            style: AppTextStyles.caption(
              context,
              color: AppColors.lightTextSecondary,
            ),
          ),
          const SizedBox(height: 8),
          _editor,
          _SaveBar(
            busy: widget.busy,
            onSave: () => widget.save({'topup_offers': _editor.snapshot()}),
          ),
        ],
      ),
    );
  }
}

// =====================================================================
// Section: Cashback / referrals / reactivation.
// =====================================================================
class _CashbackSection extends StatefulWidget {
  final Map<String, dynamic> config;
  final bool busy;
  final Future<void> Function(Map<String, dynamic>) save;
  const _CashbackSection(
      {required this.config, required this.busy, required this.save});
  @override
  State<_CashbackSection> createState() => _CashbackSectionState();
}

class _CashbackSectionState extends State<_CashbackSection> {
  late final _cashback = TextEditingController(
    text: '${widget.config['cashback_percent'] ?? 0}',
  );
  late final _lowBal = TextEditingController(
    text:
        '${((widget.config['low_balance_threshold_paise'] as int? ?? 0) ~/ 100)}',
  );
  late final _reactivCredit = TextEditingController(
    text:
        '${((widget.config['reactivation_credit_paise'] as int? ?? 0) ~/ 100)}',
  );
  late final _reactivExpiry = TextEditingController(
    text: '${widget.config['reactivation_expiry_days'] ?? 30}',
  );
  late final _churn = TextEditingController(
    text: '${widget.config['churn_threshold_days'] ?? 60}',
  );
  late final _refGifter = TextEditingController(
    text:
        '${((widget.config['referral_gifter_credit_paise'] as int? ?? 0) ~/ 100)}',
  );
  late final _refNew = TextEditingController(
    text:
        '${((widget.config['referral_new_family_credit_paise'] as int? ?? 0) ~/ 100)}',
  );
  late final _refCap = TextEditingController(
    text:
        '${((widget.config['referral_monthly_cap_paise'] as int? ?? 0) ~/ 100)}',
  );

  @override
  void dispose() {
    for (final c in [
      _cashback,
      _lowBal,
      _reactivCredit,
      _reactivExpiry,
      _churn,
      _refGifter,
      _refNew,
      _refCap,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: 'Cashback, referrals, reactivation',
      icon: PhosphorIconsRegular.gift,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _NumField(
            label: 'Cashback % on topups',
            controller: _cashback,
            hint: 'e.g. 5',
          ),
          _RupeeField(
            label: 'Low balance threshold',
            controller: _lowBal,
          ),
          const Divider(height: 24),
          _RupeeField(
            label: 'Reactivation credit',
            controller: _reactivCredit,
          ),
          _NumField(
            label: 'Reactivation expiry (days)',
            controller: _reactivExpiry,
            hint: '30',
          ),
          _NumField(
            label: 'Churn threshold (days inactive)',
            controller: _churn,
            hint: '60',
          ),
          const Divider(height: 24),
          _RupeeField(
            label: 'Referral — gifter credit',
            controller: _refGifter,
          ),
          _RupeeField(
            label: 'Referral — new family credit',
            controller: _refNew,
          ),
          _RupeeField(
            label: 'Referral — monthly cap per gifter',
            controller: _refCap,
          ),
          _SaveBar(
            busy: widget.busy,
            onSave: () => widget.save({
              'cashback_percent': double.tryParse(_cashback.text) ?? 0,
              'low_balance_threshold_paise':
                  (int.tryParse(_lowBal.text) ?? 0) * 100,
              'reactivation_credit_paise':
                  (int.tryParse(_reactivCredit.text) ?? 0) * 100,
              'reactivation_expiry_days':
                  int.tryParse(_reactivExpiry.text) ?? 30,
              'churn_threshold_days': int.tryParse(_churn.text) ?? 60,
              'referral_gifter_credit_paise':
                  (int.tryParse(_refGifter.text) ?? 0) * 100,
              'referral_new_family_credit_paise':
                  (int.tryParse(_refNew.text) ?? 0) * 100,
              'referral_monthly_cap_paise':
                  (int.tryParse(_refCap.text) ?? 0) * 100,
            }),
          ),
        ],
      ),
    );
  }
}

// =====================================================================
// Section: XP.
// =====================================================================
class _XpSection extends StatefulWidget {
  final Map<String, dynamic> config;
  final bool busy;
  final Future<void> Function(Map<String, dynamic>) save;
  const _XpSection(
      {required this.config, required this.busy, required this.save});
  @override
  State<_XpSection> createState() => _XpSectionState();
}

class _XpSectionState extends State<_XpSection> {
  static const _xpKeys = <String, String>{
    'xp_per_session_minute': 'XP per session minute',
    'xp_reflection_participation': 'XP — reflection participation',
    'xp_healthy_bite': 'XP — healthy bite',
    'xp_workshop_attendance': 'XP — workshop attendance',
    'xp_birthday_hosted': 'XP — birthday hosted',
    'xp_birthday_guest': 'XP — birthday guest',
    'xp_first_session': 'XP — first session bonus',
    'xp_streak_bonus': 'XP — streak bonus',
    'xp_referral_bonus_rafi': 'XP — referral bonus',
    'xp_birthday_bonus': 'XP — birthday bonus',
    'stage_imminent_xp_gap': 'Stage-imminent XP gap',
  };

  late final Map<String, TextEditingController> _ctrls = {
    for (final k in _xpKeys.keys)
      k: TextEditingController(text: '${widget.config[k] ?? 0}'),
  };

  late final _stages = TextEditingController(
    text: jsonEncode(widget.config['stage_thresholds_per_trait'] ?? [0, 50, 150, 350, 700]),
  );
  late final _levels = TextEditingController(
    text: jsonEncode(widget.config['level_thresholds'] ?? []),
  );

  // amount_key → trait_config_key. Rows that don't have a trait dropdown
  // (per_session_minute + reflection_participation) are customer-driven —
  // their split comes from moment taps, not a fixed trait.
  static const Map<String, String> _traitForAmount = {
    'xp_healthy_bite':        'xp_healthy_bite_trait',
    'xp_workshop_attendance': '',  // routed per-workshop, not via venue_config
    'xp_birthday_hosted':     'xp_birthday_hosted_trait',
    'xp_birthday_guest':      'xp_birthday_guest_trait',
    'xp_first_session':       'xp_first_session_trait',
    'xp_streak_bonus':        'xp_streak_bonus_trait',
    'xp_referral_bonus_rafi': 'xp_referral_bonus_trait',
    'xp_birthday_bonus':      'xp_birthday_bonus_trait',
  };

  late final Map<String, String> _traitValues = {
    for (final entry in _traitForAmount.entries)
      if (entry.value.isNotEmpty)
        entry.value: (widget.config[entry.value] as String?) ??
            _defaultTrait(entry.key),
  };

  static String _defaultTrait(String amountKey) => switch (amountKey) {
        'xp_healthy_bite' => 'ellie',
        'xp_birthday_hosted' => 'split',
        'xp_birthday_guest' => 'ellie',
        'xp_birthday_bonus' => 'split',
        'xp_first_session' => 'rafi',
        'xp_streak_bonus' => 'split',
        'xp_referral_bonus_rafi' => 'rafi',
        _ => 'rafi',
      };

  @override
  void dispose() {
    for (final c in _ctrls.values) {
      c.dispose();
    }
    _stages.dispose();
    _levels.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: 'XP economy',
      icon: PhosphorIconsRegular.lightning,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final entry in _xpKeys.entries) ...[
            _NumField(
              label: entry.value,
              controller: _ctrls[entry.key]!,
            ),
            if (_traitForAmount[entry.key]?.isNotEmpty ?? false)
              _TraitDropdown(
                value: _traitValues[_traitForAmount[entry.key]!] ?? 'rafi',
                onChanged: (v) => setState(
                  () => _traitValues[_traitForAmount[entry.key]!] = v,
                ),
              )
            else if (entry.key == 'xp_workshop_attendance')
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 12),
                child: Text(
                  'Trait is set per workshop in admin/workshops.',
                  style: AppTextStyles.caption(
                    context,
                    color: AppColors.lightTextSecondary,
                  ),
                ),
              ),
          ],
          const SizedBox(height: 12),
          Text('Stage thresholds per trait (5 ints)',
              style: AppTextStyles.body(context).copyWith(
                fontWeight: FontWeight.w700,
              )),
          const SizedBox(height: 8),
          _JsonTextarea(
            controller: _stages,
            hint: '[0,50,150,350,700]',
            minLines: 2,
          ),
          const SizedBox(height: 12),
          Text('Level thresholds (XP for each level)',
              style: AppTextStyles.body(context).copyWith(
                fontWeight: FontWeight.w700,
              )),
          const SizedBox(height: 8),
          _JsonTextarea(
            controller: _levels,
            hint: '[0,100,250,...]',
            minLines: 3,
          ),
          _SaveBar(
            busy: widget.busy,
            onSave: () async {
              List<dynamic> stages;
              List<dynamic> levels;
              try {
                stages = jsonDecode(_stages.text) as List<dynamic>;
                levels = jsonDecode(_levels.text) as List<dynamic>;
              } catch (_) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content:
                          Text('Stage/level thresholds must be JSON arrays')),
                );
                return;
              }
              if (stages.length != 5) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('Stage thresholds must be exactly 5 ints')),
                );
                return;
              }
              await widget.save({
                for (final k in _xpKeys.keys)
                  k: int.tryParse(_ctrls[k]!.text) ?? 0,
                ..._traitValues,
                'stage_thresholds_per_trait': stages,
                'level_thresholds': levels,
              });
            },
          ),
        ],
      ),
    );
  }
}

// =====================================================================
// Section: Visit milestones.
// =====================================================================
class _MilestonesSection extends StatefulWidget {
  final Map<String, dynamic> config;
  final bool busy;
  final Future<void> Function(Map<String, dynamic>) save;
  const _MilestonesSection(
      {required this.config, required this.busy, required this.save});
  @override
  State<_MilestonesSection> createState() => _MilestonesSectionState();
}

class _MilestonesSectionState extends State<_MilestonesSection> {
  late final JsonbListEditor _editor = JsonbListEditor(
    initial: widget.config['visit_milestones'] as List? ?? [],
    fields: const [
      JsonbField('visits', 'Visits', isInt: true),
      JsonbField('reward_xp', 'Reward XP', isInt: true),
      JsonbField('reward_paise', 'Reward (paise)', isInt: true),
    ],
  );

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: 'Visit milestones',
      icon: PhosphorIconsRegular.trophy,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Awarded as visit_count crosses each threshold. Sorted by '
            'visits ascending; reward_xp + reward_paise both fire on award.',
            style: AppTextStyles.caption(
              context,
              color: AppColors.lightTextSecondary,
            ),
          ),
          const SizedBox(height: 8),
          _editor,
          _SaveBar(
            busy: widget.busy,
            onSave: () => widget.save({
              'visit_milestones': _editor.snapshot(),
            }),
          ),
        ],
      ),
    );
  }
}

// =====================================================================
// Section: Birthday.
// =====================================================================
class _BirthdaySection extends StatefulWidget {
  final Map<String, dynamic> config;
  final bool busy;
  final Future<void> Function(Map<String, dynamic>) save;
  const _BirthdaySection(
      {required this.config, required this.busy, required this.save});
  @override
  State<_BirthdaySection> createState() => _BirthdaySectionState();
}

class _BirthdaySectionState extends State<_BirthdaySection> {
  late final _autocancel = TextEditingController(
    text: '${widget.config['birthday_reservation_autocancel_hours'] ?? 24}',
  );
  late final _homeCardThreshold = TextEditingController(
    text: '${widget.config['birthday_home_card_threshold_days'] ?? 28}',
  );
  late bool _bookingEnabled =
      (widget.config['birthday_booking_enabled'] as bool?) ?? true;

  late bool _wishEnabled =
      (widget.config['child_birthday_wish_enabled'] as bool?) ?? true;
  late final _wishTime = TextEditingController(
    text: (widget.config['child_birthday_wish_time'] as String?) ?? '08:00',
  );
  late final _wishCelebrating = TextEditingController(
    text:
        (widget.config['child_birthday_wish_copy_celebrating'] as String?) ?? '',
  );
  late final _wishDefault = TextEditingController(
    text: (widget.config['child_birthday_wish_copy_default'] as String?) ?? '',
  );

  @override
  void dispose() {
    _autocancel.dispose();
    _homeCardThreshold.dispose();
    _wishTime.dispose();
    _wishCelebrating.dispose();
    _wishDefault.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: 'Birthday',
      icon: PhosphorIconsRegular.cake,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('Birthday booking enabled'),
            value: _bookingEnabled,
            onChanged: (v) => setState(() => _bookingEnabled = v),
          ),
          _NumField(
            label: 'Reservation auto-cancel after (hours)',
            controller: _autocancel,
            hint: '24',
          ),
          _NumField(
            label: 'Home-card threshold (days before birthday)',
            controller: _homeCardThreshold,
            hint: '28',
          ),
          const Divider(height: 24),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('Child birthday wish push'),
            subtitle: const Text(
                'Sent to families on the child\'s birthday morning'),
            value: _wishEnabled,
            onChanged: (v) => setState(() => _wishEnabled = v),
          ),
          _TextField(
            label: 'Wish send time (HH:MM, IST)',
            controller: _wishTime,
            hint: '08:00',
          ),
          _TextField(
            label: 'Wish copy — celebrating with us',
            controller: _wishCelebrating,
            hint: 'See you at the venue today!',
          ),
          _TextField(
            label: 'Wish copy — default',
            controller: _wishDefault,
            hint: 'Happy birthday from Diaries Club!',
          ),
          _SaveBar(
            busy: widget.busy,
            onSave: () => widget.save({
              'birthday_booking_enabled': _bookingEnabled,
              'birthday_reservation_autocancel_hours':
                  int.tryParse(_autocancel.text) ?? 24,
              'birthday_home_card_threshold_days':
                  int.tryParse(_homeCardThreshold.text) ?? 28,
              'child_birthday_wish_enabled': _wishEnabled,
              'child_birthday_wish_time': _wishTime.text.trim(),
              'child_birthday_wish_copy_celebrating': _wishCelebrating.text,
              'child_birthday_wish_copy_default': _wishDefault.text,
            }),
          ),
        ],
      ),
    );
  }
}

// =====================================================================
// Section: Session timing.
// =====================================================================
class _SessionTimingSection extends StatefulWidget {
  final Map<String, dynamic> config;
  final bool busy;
  final Future<void> Function(Map<String, dynamic>) save;
  const _SessionTimingSection(
      {required this.config, required this.busy, required this.save});
  @override
  State<_SessionTimingSection> createState() => _SessionTimingSectionState();
}

class _SessionTimingSectionState extends State<_SessionTimingSection> {
  static const _intKeys = <String, String>{
    'session_grace_period_minutes': 'Grace period (mins)',
    'session_grace_max_minutes': 'Grace max (mins)',
    'session_extend_nudge_after_minutes': 'Extend nudge after (mins)',
    'session_force_close_after_grace_minutes':
        'Force-close after grace (mins)',
    'session_pre_scan_timeout_minutes': 'Pre-scan timeout (mins)',
    'qr_validity_minutes': 'QR validity (mins)',
    'otp_validity_minutes': 'OTP validity (mins)',
    'reflection_window_hours': 'Reflection window (hours)',
    'pre_booking_grace_minutes': 'Pre-booking grace (mins)',
    'max_sessions_per_family_per_day': 'Max sessions per family per day',
  };

  late final Map<String, TextEditingController> _ctrls = {
    for (final k in _intKeys.keys)
      k: TextEditingController(text: '${widget.config[k] ?? 0}'),
  };

  late final _holdPercent = TextEditingController(
    text: '${widget.config['pre_booking_hold_percent'] ?? 0}',
  );

  @override
  void dispose() {
    for (final c in _ctrls.values) {
      c.dispose();
    }
    _holdPercent.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: 'Session timing',
      icon: PhosphorIconsRegular.timer,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final e in _intKeys.entries)
            _NumField(label: e.value, controller: _ctrls[e.key]!),
          _NumField(
            label: 'Pre-booking hold percent (e.g. 20)',
            controller: _holdPercent,
          ),
          _SaveBar(
            busy: widget.busy,
            onSave: () => widget.save({
              for (final k in _intKeys.keys)
                k: int.tryParse(_ctrls[k]!.text) ?? 0,
              'pre_booking_hold_percent':
                  double.tryParse(_holdPercent.text) ?? 0,
            }),
          ),
        ],
      ),
    );
  }
}

// =====================================================================
// Section: App version.
// =====================================================================
class _AppVersionSection extends StatefulWidget {
  final Map<String, dynamic> config;
  final bool busy;
  final Future<void> Function(Map<String, dynamic>) save;
  const _AppVersionSection(
      {required this.config, required this.busy, required this.save});
  @override
  State<_AppVersionSection> createState() => _AppVersionSectionState();
}

class _AppVersionSectionState extends State<_AppVersionSection> {
  late final _iosMin = TextEditingController(
    text: (widget.config['ios_min_supported_version'] as String?) ?? '',
  );
  late final _iosLatest = TextEditingController(
    text: (widget.config['ios_latest_version'] as String?) ?? '',
  );
  late final _androidMin = TextEditingController(
    text: (widget.config['android_min_supported_version'] as String?) ?? '',
  );
  late final _androidLatest = TextEditingController(
    text: (widget.config['android_latest_version'] as String?) ?? '',
  );
  late final _forceMsg = TextEditingController(
    text: (widget.config['force_update_message'] as String?) ?? '',
  );

  @override
  void dispose() {
    _iosMin.dispose();
    _iosLatest.dispose();
    _androidMin.dispose();
    _androidLatest.dispose();
    _forceMsg.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: 'App version control',
      icon: PhosphorIconsRegular.deviceMobile,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: _TextField(
                  label: 'iOS min',
                  controller: _iosMin,
                  hint: '1.0.0',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _TextField(
                  label: 'iOS latest',
                  controller: _iosLatest,
                  hint: '1.0.5',
                ),
              ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: _TextField(
                  label: 'Android min',
                  controller: _androidMin,
                  hint: '1.0.0',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _TextField(
                  label: 'Android latest',
                  controller: _androidLatest,
                  hint: '1.0.5',
                ),
              ),
            ],
          ),
          _TextField(
            label: 'Force-update message (shown when below min)',
            controller: _forceMsg,
            hint: 'Please update Diaries Club to keep things smooth.',
          ),
          _SaveBar(
            busy: widget.busy,
            onSave: () => widget.save({
              'ios_min_supported_version': _iosMin.text.trim(),
              'ios_latest_version': _iosLatest.text.trim(),
              'android_min_supported_version': _androidMin.text.trim(),
              'android_latest_version': _androidLatest.text.trim(),
              'force_update_message': _forceMsg.text,
            }),
          ),
        ],
      ),
    );
  }
}

// =====================================================================
// Section: Contact / URLs.
// =====================================================================
class _ContactSection extends StatefulWidget {
  final Map<String, dynamic> config;
  final bool busy;
  final Future<void> Function(Map<String, dynamic>) save;
  const _ContactSection(
      {required this.config, required this.busy, required this.save});
  @override
  State<_ContactSection> createState() => _ContactSectionState();
}

class _ContactSectionState extends State<_ContactSection> {
  static const _keys = <String, String>{
    'whatsapp_support_phone': 'WhatsApp support phone',
    'venue_phone': 'Venue phone',
    'venue_email': 'Venue email',
    'venue_address': 'Venue address',
    'venue_maps_url': 'Maps URL',
    'privacy_policy_url': 'Privacy policy URL',
    'terms_of_service_url': 'Terms of service URL',
    'refund_policy_url': 'Refund policy URL',
    'marketing_site_url': 'Marketing site URL',
  };

  late final Map<String, TextEditingController> _ctrls = {
    for (final k in _keys.keys)
      k: TextEditingController(
          text: (widget.config[k] as String?) ?? ''),
  };

  @override
  void dispose() {
    for (final c in _ctrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: 'Contact + legal URLs',
      icon: PhosphorIconsRegular.mapPin,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final e in _keys.entries)
            _TextField(label: e.value, controller: _ctrls[e.key]!),
          _SaveBar(
            busy: widget.busy,
            onSave: () => widget.save({
              for (final k in _keys.keys) k: _ctrls[k]!.text.trim(),
            }),
          ),
        ],
      ),
    );
  }
}

// =====================================================================
// Section: Club taglines (Coffee Diaries / FIT Diaries / Workshops).
// Customer-visible subtitle copy on each Club tab. Empty strings hide
// the row in the app.
// =====================================================================
class _ClubTaglinesSection extends StatefulWidget {
  final Map<String, dynamic> config;
  final bool busy;
  final Future<void> Function(Map<String, dynamic>) save;
  const _ClubTaglinesSection(
      {required this.config, required this.busy, required this.save});
  @override
  State<_ClubTaglinesSection> createState() => _ClubTaglinesSectionState();
}

class _ClubTaglinesSectionState extends State<_ClubTaglinesSection> {
  static const _keys = <String, String>{
    'coffee_diaries_tagline': 'Coffee Diaries tagline',
    'fit_diaries_tagline':    'FIT Diaries tagline',
    'workshops_tagline':      'Workshops tagline',
  };

  late final Map<String, TextEditingController> _ctrls = {
    for (final k in _keys.keys)
      k: TextEditingController(
          text: (widget.config[k] as String?) ?? ''),
  };

  @override
  void dispose() {
    for (final c in _ctrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: 'Club taglines',
      icon: PhosphorIconsRegular.textT,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final e in _keys.entries)
            _TextField(label: e.value, controller: _ctrls[e.key]!),
          _SaveBar(
            busy: widget.busy,
            onSave: () => widget.save({
              for (final k in _keys.keys) k: _ctrls[k]!.text.trim(),
            }),
          ),
        ],
      ),
    );
  }
}

// =====================================================================
// Section: Workshops lifecycle knobs.
//   - workshop_reminder_minutes_before: how far ahead of scheduled_at the
//     'Starting soon' push fires. Default 30. workshop-lifecycle-cron
//     reads this every minute; change applies on the next tick.
// =====================================================================
class _WorkshopsSection extends StatefulWidget {
  final Map<String, dynamic> config;
  final bool busy;
  final Future<void> Function(Map<String, dynamic>) save;
  const _WorkshopsSection(
      {required this.config, required this.busy, required this.save});
  @override
  State<_WorkshopsSection> createState() => _WorkshopsSectionState();
}

class _WorkshopsSectionState extends State<_WorkshopsSection> {
  late final TextEditingController _reminderLead = TextEditingController(
    text: ((widget.config['workshop_reminder_minutes_before'] as int?) ?? 30)
        .toString(),
  );

  @override
  void dispose() {
    _reminderLead.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: 'Workshops',
      icon: PhosphorIconsRegular.palette,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _NumField(
            label: 'Reminder lead time (mins before start)',
            controller: _reminderLead,
          ),
          _SaveBar(
            busy: widget.busy,
            onSave: () => widget.save({
              'workshop_reminder_minutes_before':
                  int.tryParse(_reminderLead.text) ?? 30,
            }),
          ),
        ],
      ),
    );
  }
}

// =====================================================================
// Section: Birthdays tab (Club > Birthdays).
//   - celebrations + happy_kids: integer counters surfaced as social proof
//   - testimonials: ordered list of {quote, author} cards. Founder pastes
//     real Google-review quotes; the customer tab renders whatever exists.
// =====================================================================
class _BirthdaysTabSection extends StatefulWidget {
  final Map<String, dynamic> config;
  final bool busy;
  final Future<void> Function(Map<String, dynamic>) save;
  const _BirthdaysTabSection(
      {required this.config, required this.busy, required this.save});
  @override
  State<_BirthdaysTabSection> createState() => _BirthdaysTabSectionState();
}

class _BirthdaysTabSectionState extends State<_BirthdaysTabSection> {
  late final TextEditingController _celebrations = TextEditingController(
      text: ((widget.config['birthday_celebrations_count'] as int?) ?? 0)
          .toString());
  late final TextEditingController _kids = TextEditingController(
      text: ((widget.config['birthday_happy_kids_count'] as int?) ?? 0)
          .toString());
  // Brochure PDF: storage URL of the single shared birthday brochure.
  // Uploaded via the button below — admin doesn't see the URL string.
  late String _brochureUrl =
      (widget.config['birthday_brochure_url'] as String?) ?? '';
  bool _uploadingBrochure = false;
  late final List<_TestimonialDraft> _testimonials = _seedTestimonials();

  List<_TestimonialDraft> _seedTestimonials() {
    final raw = widget.config['birthday_testimonials'];
    if (raw is! List) return [];
    return raw
        .whereType<Map<String, dynamic>>()
        .map((m) => _TestimonialDraft(
              quote: (m['quote'] as String?) ?? '',
              author: (m['author'] as String?) ?? '',
            ))
        .toList();
  }

  @override
  void dispose() {
    _celebrations.dispose();
    _kids.dispose();
    for (final t in _testimonials) {
      t.dispose();
    }
    super.dispose();
  }

  /// Pick a PDF from the admin's machine, upload to Supabase Storage
  /// (`package-pdfs` bucket — reused from the now-removed per-package PDF
  /// flow), then auto-save the resulting public URL into
  /// venue_config.birthday_brochure_url. No URL paste step.
  Future<void> _uploadBrochure() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't read that file.")),
      );
      return;
    }

    setState(() => _uploadingBrochure = true);
    try {
      final path =
          'birthday-brochure/${DateTime.now().millisecondsSinceEpoch}.pdf';
      await Supabase.instance.client.storage.from('package-pdfs').uploadBinary(
            path,
            bytes,
            fileOptions: const FileOptions(contentType: 'application/pdf'),
          );
      final publicUrl = Supabase.instance.client.storage
          .from('package-pdfs')
          .getPublicUrl(path);

      // Save just this key so we don't fight with un-saved edits in
      // celebrations/kids/testimonials.
      await widget.save({'birthday_brochure_url': publicUrl});

      if (!mounted) return;
      setState(() {
        _brochureUrl = publicUrl;
        _uploadingBrochure = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Brochure uploaded.')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _uploadingBrochure = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Couldn't upload: $e")),
      );
    }
  }

  void _addTestimonial() {
    setState(() => _testimonials.add(_TestimonialDraft.empty()));
  }

  void _removeTestimonial(int i) {
    setState(() {
      _testimonials[i].dispose();
      _testimonials.removeAt(i);
    });
  }

  Map<String, dynamic> _buildPatch() {
    final list = _testimonials
        .where((t) => t.quoteCtrl.text.trim().isNotEmpty)
        .map((t) => {
              'quote': t.quoteCtrl.text.trim(),
              'author': t.authorCtrl.text.trim(),
            })
        .toList();
    return {
      'birthday_celebrations_count':
          int.tryParse(_celebrations.text.trim()) ?? 0,
      'birthday_happy_kids_count':
          int.tryParse(_kids.text.trim()) ?? 0,
      // birthday_brochure_url is saved by _uploadBrochure() the moment a
      // PDF is picked, so it's intentionally not in this patch.
      'birthday_testimonials': list,
    };
  }

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: 'Birthdays tab (Club > Birthdays)',
      icon: PhosphorIconsRegular.cake,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _TextField(label: 'Celebrations count', controller: _celebrations),
          _TextField(label: 'Happy kids count', controller: _kids),
          const SizedBox(height: 12),
          // Brochure PDF row — upload only, no URL pasting. Shows current
          // state + Open link if a PDF is on file.
          Row(
            children: [
              Icon(
                _brochureUrl.isEmpty
                    ? PhosphorIconsRegular.warningCircle
                    : PhosphorIconsFill.filePdf,
                color: _brochureUrl.isEmpty
                    ? AppColors.lightTextSecondary
                    : AppColors.activeGreen,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _brochureUrl.isEmpty
                      ? 'Shared birthday brochure — no PDF yet'
                      : 'Brochure uploaded',
                  style: AppTextStyles.body(context).copyWith(
                    color: _brochureUrl.isEmpty
                        ? AppColors.lightTextSecondary
                        : AppColors.lightTextPrimary,
                  ),
                ),
              ),
              if (_brochureUrl.isNotEmpty)
                TextButton.icon(
                  icon: const Icon(PhosphorIconsRegular.arrowSquareOut,
                      size: 14),
                  label: const Text('Open'),
                  onPressed: () => launchUrl(Uri.parse(_brochureUrl)),
                ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                icon: Icon(
                  _brochureUrl.isEmpty
                      ? PhosphorIconsRegular.upload
                      : PhosphorIconsRegular.arrowsClockwise,
                  size: 14,
                ),
                label: Text(_brochureUrl.isEmpty ? 'Upload PDF' : 'Replace'),
                onPressed: _uploadingBrochure ? null : _uploadBrochure,
              ),
            ],
          ),
          if (_uploadingBrochure) ...[
            const SizedBox(height: 8),
            const LinearProgressIndicator(minHeight: 2),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text('Testimonials',
                    style: AppTextStyles.bodyLarge(context)),
              ),
              TextButton.icon(
                onPressed: widget.busy ? null : _addTestimonial,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add'),
              ),
            ],
          ),
          if (_testimonials.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'No testimonials yet. Paste a quote from Google reviews and a parent name.',
                style: AppTextStyles.caption(
                  context,
                  color: AppColors.lightTextSecondary,
                ),
              ),
            ),
          for (var i = 0; i < _testimonials.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 6, 4, 8),
                decoration: BoxDecoration(
                  color: AppColors.lightSurface,
                  border: Border.all(color: AppColors.lightBorder),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text('#${i + 1}',
                              style: AppTextStyles.caption(
                                context,
                                color: AppColors.lightTextSecondary,
                              )),
                        ),
                        IconButton(
                          tooltip: 'Remove',
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: widget.busy
                              ? null
                              : () => _removeTestimonial(i),
                        ),
                      ],
                    ),
                    _TextField(
                      label: 'Quote',
                      controller: _testimonials[i].quoteCtrl,
                    ),
                    _TextField(
                      label: 'Author / parent name',
                      controller: _testimonials[i].authorCtrl,
                    ),
                  ],
                ),
              ),
            ),
          _SaveBar(
            busy: widget.busy,
            onSave: () => widget.save(_buildPatch()),
          ),
        ],
      ),
    );
  }
}

class _TestimonialDraft {
  final TextEditingController quoteCtrl;
  final TextEditingController authorCtrl;
  _TestimonialDraft({required String quote, required String author})
      : quoteCtrl = TextEditingController(text: quote),
        authorCtrl = TextEditingController(text: author);
  _TestimonialDraft.empty()
      : quoteCtrl = TextEditingController(),
        authorCtrl = TextEditingController();
  void dispose() {
    quoteCtrl.dispose();
    authorCtrl.dispose();
  }
}

// =====================================================================
// Section: Feature flags.
// =====================================================================
class _FeatureFlagsSection extends StatefulWidget {
  final Map<String, dynamic> config;
  final bool busy;
  final Future<void> Function(Map<String, dynamic>) save;
  const _FeatureFlagsSection(
      {required this.config, required this.busy, required this.save});
  @override
  State<_FeatureFlagsSection> createState() => _FeatureFlagsSectionState();
}

class _FeatureFlagsSectionState extends State<_FeatureFlagsSection> {
  static const _keys = <String, String>{
    'birthday_booking_enabled': 'Birthday booking',
    'workshops_enabled': 'Workshops',
    'healthy_bite_enabled': 'Healthy bite reflection',
    'wall_of_legends_enabled': 'Wall of legends',
    'wall_of_legends_anonymise': 'Wall of legends — anonymise',
    'marketing_opt_in_default': 'Marketing opt-in default',
    'require_two_person_for_debit': 'Require two-person for debit',
  };

  late final Map<String, bool> _values = {
    for (final k in _keys.keys)
      k: (widget.config[k] as bool?) ?? false,
  };

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: 'Feature flags',
      icon: PhosphorIconsRegular.toggleRight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final e in _keys.entries)
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: Text(e.value),
              value: _values[e.key]!,
              onChanged: (v) => setState(() => _values[e.key] = v),
            ),
          _SaveBar(
            busy: widget.busy,
            onSave: () => widget.save(_values),
          ),
        ],
      ),
    );
  }
}

// =====================================================================
// Generic helpers.
// =====================================================================
class _Section extends StatelessWidget {
  final String title;
  final IconData? icon;
  final Widget child;
  const _Section({required this.title, required this.child, this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.lightSurface,
        border: Border.all(color: AppColors.lightBorder),
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(
          dividerColor: Colors.transparent,
        ),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          title: Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18, color: AppColors.lightTextSecondary),
                const SizedBox(width: 8),
              ],
              Text(title, style: AppTextStyles.h3(context)),
            ],
          ),
          children: [child],
        ),
      ),
    );
  }
}

class _RupeeField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  const _RupeeField({required this.label, required this.controller});
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final paise = (int.tryParse(controller.text) ?? 0) * 100;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Expanded(
                flex: 2,
                child: Text(label, style: AppTextStyles.body(context)),
              ),
              Expanded(
                flex: 3,
                child: TextField(
                  controller: controller,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    prefixText: '₹ ',
                    isDense: true,
                    border: const OutlineInputBorder(),
                    helperText: '= ${Money.fromPaise(paise)}',
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Dropdown used beneath each admin-defined XP earner to pick which
/// character the XP routes to. 4 traits + a "split equally" option.
class _TraitDropdown extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;
  const _TraitDropdown({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, top: 2, bottom: 14),
      child: Row(
        children: [
          Text(
            'Goes to:',
            style: AppTextStyles.caption(
              context,
              color: AppColors.lightTextSecondary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: DropdownButtonFormField<String>(
              initialValue: value,
              isDense: true,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 12, vertical: 8,
                ),
              ),
              items: const [
                DropdownMenuItem(value: 'rafi',  child: Text('🛡  Rafi the Brave')),
                DropdownMenuItem(value: 'ellie', child: Text('❤️  Ellie the Kind')),
                DropdownMenuItem(value: 'gerry', child: Text('🔍  Gerry the Curious')),
                DropdownMenuItem(value: 'zena',  child: Text('🎨  Zena the Creative')),
                DropdownMenuItem(value: 'split', child: Text('⚖  Split equally across all 4')),
              ],
              onChanged: (v) {
                if (v != null) onChanged(v);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _NumField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String? hint;
  const _NumField({required this.label, required this.controller, this.hint});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(label, style: AppTextStyles.body(context)),
          ),
          Expanded(
            flex: 3,
            child: TextField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                isDense: true,
                hintText: hint,
                border: const OutlineInputBorder(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TextField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String? hint;
  const _TextField({required this.label, required this.controller, this.hint});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          isDense: true,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }
}

class _JsonTextarea extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final int minLines;
  const _JsonTextarea({
    required this.controller,
    required this.hint,
    this.minLines = 3,
  });
  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      minLines: minLines,
      maxLines: 8,
      style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
      decoration: InputDecoration(
        hintText: hint,
        isDense: true,
        border: const OutlineInputBorder(),
      ),
    );
  }
}

class _SaveBar extends StatelessWidget {
  final bool busy;
  final VoidCallback onSave;
  const _SaveBar({required this.busy, required this.onSave});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          AdminPrimaryButton(
            label: 'Save section',
            busy: busy,
            onPressed: busy ? null : onSave,
          ),
        ],
      ),
    );
  }
}

// =====================================================================
// JSONB list editor — for topup_offers, visit_milestones,
// session_extension_options.
// =====================================================================
class JsonbField {
  final String key;
  final String label;
  final bool isInt;
  const JsonbField(this.key, this.label, {this.isInt = false});
}

/// Mutable shared state for the editor — parent constructs once and
/// reads snapshot() at save time. Widget instances get recreated on
/// rebuild, so we hold the data on this controller-style object.
class JsonbListEditor extends StatefulWidget {
  final List<dynamic> initial;
  final List<JsonbField> fields;
  final List<Map<String, dynamic>> _rows;

  JsonbListEditor({required this.initial, required this.fields, super.key})
      : _rows = [
          for (final r in initial)
            if (r is Map) Map<String, dynamic>.from(r),
        ];

  List<Map<String, dynamic>> snapshot() => List.from(_rows);

  @override
  State<JsonbListEditor> createState() => _JsonbListEditorState();
}

class _JsonbListEditorState extends State<JsonbListEditor> {
  void _addRow() {
    setState(() => widget._rows
        .add({for (final f in widget.fields) f.key: f.isInt ? 0 : ''}));
  }

  void _remove(int i) => setState(() => widget._rows.removeAt(i));

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < widget._rows.length; i++)
          Padding(
            key: ObjectKey(widget._rows[i]),
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                for (final f in widget.fields)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: TextFormField(
                        initialValue: '${widget._rows[i][f.key] ?? ''}',
                        keyboardType: f.isInt
                            ? TextInputType.number
                            : TextInputType.text,
                        inputFormatters: f.isInt
                            ? [FilteringTextInputFormatter.digitsOnly]
                            : null,
                        decoration: InputDecoration(
                          labelText: f.label,
                          isDense: true,
                          border: const OutlineInputBorder(),
                        ),
                        onChanged: (v) => widget._rows[i][f.key] = f.isInt
                            ? (int.tryParse(v) ?? 0)
                            : v,
                      ),
                    ),
                  ),
                AdminIconButton(
                  icon: PhosphorIconsRegular.trash,
                  size: 16,
                  color: AppColors.adminRed,
                  tooltip: 'Remove',
                  onPressed: () => _remove(i),
                ),
              ],
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: AdminSecondaryButton(
            icon: PhosphorIconsRegular.plus,
            label: 'Add row',
            onPressed: _addRow,
          ),
        ),
      ],
    );
  }
}
