import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../widgets/admin_app_bar.dart';
import '../widgets/admin_buttons.dart';

/// One editable row in the variants editor — a pair of controllers for
/// the title and body that we serialise back into the variants JSONB
/// array on save.
class _VariantEditor {
  final TextEditingController title;
  final TextEditingController body;
  _VariantEditor({String? title, String? body})
      : title = TextEditingController(text: title ?? ''),
        body = TextEditingController(text: body ?? '');

  Map<String, String> toJson() =>
      {'title': title.text.trim(), 'body': body.text.trim()};

  void dispose() {
    title.dispose();
    body.dispose();
  }
}

/// Admin editor for `notification_templates` rows (migration 0142).
///
/// Lists every push-notification type the system can fire, grouped by
/// category. Inline toggle to enable/disable a type system-wide; tap a
/// row to edit title / body / deep-link / timing offset.
///
/// Saves go through the `admin_update_notification_template` RPC which
/// stamps `updated_by` with the calling admin's id.
class NotificationTemplatesScreen extends ConsumerStatefulWidget {
  const NotificationTemplatesScreen({super.key});

  @override
  ConsumerState<NotificationTemplatesScreen> createState() =>
      _NotificationTemplatesScreenState();
}

final notificationTemplatesProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final rows = await Supabase.instance.client
      .from('notification_templates')
      .select()
      .order('category')
      .order('type');
  return (rows as List)
      .map((r) => Map<String, dynamic>.from(r as Map))
      .toList();
});

class _NotificationTemplatesScreenState
    extends ConsumerState<NotificationTemplatesScreen> {
  @override
  Widget build(BuildContext context) {
    final async = ref.watch(notificationTemplatesProvider);

    return Scaffold(
      appBar: const AdminAppBar(title: 'Notification Templates'),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Could not load templates: $e'),
          ),
        ),
        data: (rows) => _TemplateList(templates: rows),
      ),
    );
  }
}

class _TemplateList extends ConsumerWidget {
  final List<Map<String, dynamic>> templates;
  const _TemplateList({required this.templates});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final byCategory = <String, List<Map<String, dynamic>>>{};
    for (final t in templates) {
      final cat = (t['category'] as String?) ?? 'other';
      byCategory.putIfAbsent(cat, () => []).add(t);
    }
    final categoryOrder = const [
      'session',
      'hero',
      'birthday',
      'order',
      'wallet',
      'engagement',
      'workshop',
      'marketing',
      'other',
    ];

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(notificationTemplatesProvider),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _Header(total: templates.length),
          const SizedBox(height: 16),
          for (final cat in categoryOrder)
            if (byCategory[cat] != null) ...[
              _CategoryHeader(label: cat, count: byCategory[cat]!.length),
              for (final t in byCategory[cat]!)
                _TemplateRow(template: t),
              const SizedBox(height: 16),
            ],
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final int total;
  const _Header({required this.total});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.gold.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(PhosphorIconsFill.bellRinging, color: AppColors.gold),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$total notification types',
                  style: AppTextStyles.bodyLarge(context),
                ),
                const SizedBox(height: 4),
                Text(
                  'Toggle disables a type system-wide. Edits to title/body use {{variable}} placeholders that the sender fills at runtime. Disabled types skip insert entirely and do not push.',
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
    );
  }
}

class _CategoryHeader extends StatelessWidget {
  final String label;
  final int count;
  const _CategoryHeader({required this.label, required this.count});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 8, left: 4),
      child: Row(
        children: [
          Text(
            label.toUpperCase(),
            style: AppTextStyles.caption(context).copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              color: AppColors.lightTextSecondary,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '· $count',
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

class _TemplateRow extends ConsumerWidget {
  final Map<String, dynamic> template;
  const _TemplateRow({required this.template});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final type = template['type'] as String;
    final enabled = template['enabled'] as bool? ?? true;
    final title = template['title'] as String? ?? '';
    final body = template['body'] as String? ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: enabled ? Colors.white : Colors.grey.shade100,
        border: Border.all(color: AppColors.lightBorder),
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: () => _openEditor(context, ref, template),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            type,
                            style: AppTextStyles.caption(context).copyWith(
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.w600,
                              color: AppColors.coffeeBrown,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.body(context),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      body,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.caption(
                        context,
                        color: AppColors.lightTextSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Switch(
                value: enabled,
                activeThumbColor: AppColors.activeGreen,
                onChanged: (v) async {
                  await _toggleEnabled(context, ref, type, v);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _toggleEnabled(
    BuildContext context,
    WidgetRef ref,
    String type,
    bool enabled,
  ) async {
    try {
      await Supabase.instance.client.rpc<Map<String, dynamic>>(
        'admin_update_notification_template',
        params: {'p_type': type, 'p_enabled': enabled},
      );
      ref.invalidate(notificationTemplatesProvider);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Save failed: $e')),
      );
    }
  }

  void _openEditor(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic> template,
  ) {
    showDialog<void>(
      context: context,
      builder: (_) => _TemplateEditDialog(template: template),
    ).then((_) => ref.invalidate(notificationTemplatesProvider));
  }
}

class _TemplateEditDialog extends ConsumerStatefulWidget {
  final Map<String, dynamic> template;
  const _TemplateEditDialog({required this.template});

  @override
  ConsumerState<_TemplateEditDialog> createState() =>
      _TemplateEditDialogState();
}

class _VariantCard extends StatelessWidget {
  final int index;
  final _VariantEditor editor;
  final VoidCallback onDelete;
  const _VariantCard({
    required this.index,
    required this.editor,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 12),
      decoration: BoxDecoration(
        color: AppColors.gold.withValues(alpha: 0.04),
        border: Border.all(color: AppColors.lightBorder),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '#${index + 1}',
                style: AppTextStyles.caption(context).copyWith(
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w700,
                  color: AppColors.lightTextSecondary,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 20),
                tooltip: 'Delete this variant',
                onPressed: onDelete,
                visualDensity: VisualDensity.compact,
                color: AppColors.adminRed,
              ),
            ],
          ),
          TextField(
            controller: editor.title,
            decoration: const InputDecoration(
              labelText: 'Title',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            style: AppTextStyles.body(context),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: editor.body,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Body',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            style: AppTextStyles.body(context),
          ),
        ],
      ),
    );
  }
}

class _TemplateEditDialogState extends ConsumerState<_TemplateEditDialog> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _bodyCtrl;
  late final TextEditingController _deepLinkCtrl;
  late final TextEditingController _timingCtrl;
  late bool _enabled;
  final List<_VariantEditor> _variants = [];
  bool _busy = false;
  String? _err;

  @override
  void initState() {
    super.initState();
    _titleCtrl =
        TextEditingController(text: widget.template['title'] as String? ?? '');
    _bodyCtrl =
        TextEditingController(text: widget.template['body'] as String? ?? '');
    _deepLinkCtrl = TextEditingController(
      text: widget.template['deep_link_template'] as String? ?? '',
    );
    _timingCtrl = TextEditingController(
      text: widget.template['timing_offset_minutes']?.toString() ?? '',
    );
    _enabled = widget.template['enabled'] as bool? ?? true;

    final raw = widget.template['variants'];
    if (raw is List) {
      for (final v in raw) {
        if (v is Map) {
          _variants.add(_VariantEditor(
            title: v['title'] as String?,
            body: v['body'] as String?,
          ));
        }
      }
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    _deepLinkCtrl.dispose();
    _timingCtrl.dispose();
    for (final v in _variants) {
      v.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    final cleaned = _variants
        .map((v) => v.toJson())
        .where((m) => m['title']!.isNotEmpty && m['body']!.isNotEmpty)
        .toList();

    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      await Supabase.instance.client.rpc<Map<String, dynamic>>(
        'admin_update_notification_template',
        params: {
          'p_type': widget.template['type'],
          'p_enabled': _enabled,
          'p_title': _titleCtrl.text,
          'p_body': _bodyCtrl.text,
          'p_deep_link_template':
              _deepLinkCtrl.text.isEmpty ? null : _deepLinkCtrl.text,
          'p_timing_offset_minutes':
              _timingCtrl.text.trim().isEmpty
                  ? null
                  : int.tryParse(_timingCtrl.text.trim()),
          // Always send the variants list, even when empty — that way an
          // admin who deletes every variant clears the column.
          'p_variants': cleaned,
        },
      );
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _err = e.toString();
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final type = widget.template['type'] as String;
    final category = widget.template['category'] as String? ?? '';
    final variables = (widget.template['variables'] as List?)?.cast<String>() ??
        const <String>[];
    final description = widget.template['description'] as String? ?? '';
    final prefKey = widget.template['preference_key'] as String? ?? '';
    final hasTiming = widget.template['timing_offset_minutes'] != null ||
        type == 'hydration_nudge' ||
        type == 'healthy_bite_earned' ||
        type == 'extend_nudge';

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 720),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(type, style: AppTextStyles.h3(context)),
                        const SizedBox(height: 2),
                        Text(
                          '$category · gated by preference: $prefKey',
                          style: AppTextStyles.caption(
                            context,
                            color: AppColors.lightTextSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              if (description.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  description,
                  style: AppTextStyles.caption(context),
                ),
              ],
              const Divider(height: 24),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Switch(
                            value: _enabled,
                            activeThumbColor: AppColors.activeGreen,
                            onChanged: (v) => setState(() => _enabled = v),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _enabled
                                ? 'Enabled — type will fire normally'
                                : 'Disabled — admin kill-switch (no push for any user)',
                            style: AppTextStyles.body(context),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _titleCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Title',
                          border: OutlineInputBorder(),
                        ),
                        style: AppTextStyles.body(context),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _bodyCtrl,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          labelText: 'Body',
                          border: OutlineInputBorder(),
                        ),
                        style: AppTextStyles.body(context),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _deepLinkCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Deep link (route, e.g. /home)',
                          border: OutlineInputBorder(),
                        ),
                        style: AppTextStyles.body(context),
                      ),
                      if (hasTiming) ...[
                        const SizedBox(height: 12),
                        TextField(
                          controller: _timingCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText:
                                'Timing offset (minutes after session start)',
                            border: OutlineInputBorder(),
                            helperText:
                                'Used only for time-driven types (hydration_nudge, healthy_bite_earned). Leave empty for event-triggered.',
                          ),
                          style: AppTextStyles.body(context),
                        ),
                      ],
                      const SizedBox(height: 16),
                      if (variables.isNotEmpty) ...[
                        Text(
                          'Supported variables',
                          style: AppTextStyles.bodyLarge(context),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Use these inside title or body as {{variable}}. They are filled at send time.',
                          style: AppTextStyles.caption(
                            context,
                            color: AppColors.lightTextSecondary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final v in variables)
                              Chip(
                                label: Text(
                                  '{{$v}}',
                                  style: const TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 12,
                                  ),
                                ),
                                backgroundColor:
                                    AppColors.gold.withValues(alpha: 0.10),
                                side: BorderSide.none,
                              ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Message variants (${_variants.length})',
                                  style: AppTextStyles.bodyLarge(context),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Each push picks a random variant. Leave empty to always use the Title + Body above. Delete a card to drop that variant.',
                                  style: AppTextStyles.caption(
                                    context,
                                    color: AppColors.lightTextSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          TextButton.icon(
                            icon: const Icon(Icons.add),
                            label: const Text('Add variant'),
                            onPressed: () => setState(() => _variants.add(_VariantEditor())),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      for (var i = 0; i < _variants.length; i++)
                        _VariantCard(
                          index: i,
                          editor: _variants[i],
                          onDelete: () => setState(() {
                            _variants.removeAt(i).dispose();
                          }),
                        ),
                      if (_err != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _err!,
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
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _busy ? null : () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  AdminPrimaryButton(
                    label: 'Save',
                    onPressed: _busy ? null : _save,
                    busy: _busy,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
