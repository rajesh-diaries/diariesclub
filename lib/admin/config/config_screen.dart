import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/currency.dart';
import '../providers/admin_streams.dart';
import '../widgets/admin_app_bar.dart';

const _venueId = '00000000-0000-0000-0000-000000000001';

/// Config editor (MVP cut). Three sections that actually change at
/// launch: Pricing, App Version Control, Churn / GST. Top-up offers JSON
/// and the deeper XP-economy editor ship in v1.1. Each Save fires
/// admin_set_venue_config which validates the patch against the
/// whitelisted keys server-side.
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
        data: (config) => _ConfigForm(config: config, onSaved: () {
          ref.invalidate(adminVenueConfigProvider(_venueId));
        }),
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
  late final _oneHr = TextEditingController(
    text: ((widget.config['session_1hr_price_paise'] as int? ?? 0) / 100)
        .toStringAsFixed(0),
  );
  late final _twoHr = TextEditingController(
    text: ((widget.config['session_2hr_price_paise'] as int? ?? 0) / 100)
        .toStringAsFixed(0),
  );
  late final _ext = TextEditingController(
    text:
        ((widget.config['session_extension_per_hour_paise'] as int? ?? 0) / 100)
            .toStringAsFixed(0),
  );
  late final _churn = TextEditingController(
    text: '${widget.config['churn_threshold_days'] ?? 60}',
  );
  late final _gst = TextEditingController(
    text: '${widget.config['gst_percent'] ?? 18}',
  );
  late final _walkinGst = TextEditingController(
    text: '${widget.config['walkin_food_gst_percent'] ?? 5}',
  );
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

  bool _busy = false;
  String? _errorText;

  @override
  void dispose() {
    _oneHr.dispose();
    _twoHr.dispose();
    _ext.dispose();
    _churn.dispose();
    _gst.dispose();
    _walkinGst.dispose();
    _iosMin.dispose();
    _iosLatest.dispose();
    _androidMin.dispose();
    _androidLatest.dispose();
    super.dispose();
  }

  Future<void> _save(Map<String, dynamic> patch) async {
    setState(() {
      _busy = true;
      _errorText = null;
    });
    try {
      await Supabase.instance.client
          .rpc<dynamic>('admin_set_venue_config', params: {
        'p_venue_id': _venueId,
        'p_patch': patch,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Config saved.')),
      );
      widget.onSaved();
    } on PostgrestException catch (e) {
      if (!mounted) return;
      setState(() => _errorText = "Couldn't save: ${e.message}");
    } catch (_) {
      if (!mounted) return;
      setState(() => _errorText = "Couldn't save.");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 800),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Section(
              title: 'Pricing',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _RupeeField(label: '1-hour session', controller: _oneHr),
                  _RupeeField(label: '2-hour session', controller: _twoHr),
                  _RupeeField(label: 'Extension per hour', controller: _ext),
                  _SaveBar(
                    busy: _busy,
                    onSave: () => _save({
                      'session_1hr_price_paise':
                          (int.tryParse(_oneHr.text) ?? 0) * 100,
                      'session_2hr_price_paise':
                          (int.tryParse(_twoHr.text) ?? 0) * 100,
                      'session_extension_per_hour_paise':
                          (int.tryParse(_ext.text) ?? 0) * 100,
                    }),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            _Section(
              title: 'GST',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
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
                    busy: _busy,
                    onSave: () => _save({
                      'gst_percent': double.tryParse(_gst.text) ?? 18,
                      'walkin_food_gst_percent':
                          double.tryParse(_walkinGst.text) ?? 5,
                    }),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            _Section(
              title: 'App version control',
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
                  _SaveBar(
                    busy: _busy,
                    onSave: () => _save({
                      'ios_min_supported_version': _iosMin.text.trim(),
                      'ios_latest_version': _iosLatest.text.trim(),
                      'android_min_supported_version': _androidMin.text.trim(),
                      'android_latest_version': _androidLatest.text.trim(),
                    }),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            _Section(
              title: 'Retention',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _NumField(
                    label: 'Churn threshold (days inactive)',
                    controller: _churn,
                    hint: '60',
                  ),
                  _SaveBar(
                    busy: _busy,
                    onSave: () => _save({
                      'churn_threshold_days': int.tryParse(_churn.text) ?? 60,
                    }),
                  ),
                ],
              ),
            ),
            if (_errorText != null) ...[
              const SizedBox(height: 16),
              Text(
                _errorText!,
                style:
                    AppTextStyles.caption(context, color: AppColors.adminRed),
              ),
            ],
            const SizedBox(height: 32),
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
                    'Top-up offers JSON, full XP economy thresholds, gift ladder, '
                    'reactivation campaign defaults, two-person debit toggle, '
                    'wall of legends settings.',
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

class _Section extends StatelessWidget {
  final String title;
  final Widget child;
  const _Section({required this.title, required this.child});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.lightSurface,
        border: Border.all(color: AppColors.lightBorder),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: AppTextStyles.h3(context)),
          const SizedBox(height: 16),
          child,
        ],
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

class _SaveBar extends StatelessWidget {
  final bool busy;
  final VoidCallback onSave;
  const _SaveBar({required this.busy, required this.onSave});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FilledButton(
            onPressed: busy ? null : onSave,
            child: busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(Colors.white),
                    ),
                  )
                : const Text('Save section'),
          ),
        ],
      ),
    );
  }
}
