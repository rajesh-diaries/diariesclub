import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../widgets/admin_buttons.dart';

const _bannerTypes = ['promo', 'info', 'urgent'];

/// Predefined deep-link targets. `null` = static/non-clickable banner.
final _routeOptions = <String?, String>{
  null: 'None — static image',
  '/club/cafe': 'Club · Cafe',
  '/club/fit': 'Club · FIT',
  '/club/combos': 'Club · Combos',
  '/club/birthdays': 'Club · Birthdays',
  '/club/workshops': 'Club · Workshops',
  '/club': 'Club · Default tab',
  '/birthday/packages': 'Birthday Packages',
  '/home/top-up': 'Top-up wallet',
};

class HomeBannerEditScreen extends ConsumerStatefulWidget {
  final String? bannerId;
  const HomeBannerEditScreen({super.key, this.bannerId});

  bool get isEditing => bannerId != null;

  @override
  ConsumerState<HomeBannerEditScreen> createState() => _HomeBannerEditScreenState();
}

class _HomeBannerEditScreenState extends ConsumerState<HomeBannerEditScreen> {
  final _titleCtrl = TextEditingController();
  final _altTextCtrl = TextEditingController();
  final _orderCtrl = TextEditingController(text: '0');
  final _customRouteCtrl = TextEditingController();

  String _type = 'promo';
  String? _targetRoute;
  bool _useCustomRoute = false;
  DateTime? _visibleFrom;
  DateTime? _visibleUntil;
  bool _isActive = true;
  String? _imageUrl;
  bool _saving = false;
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    if (widget.isEditing) _loadExisting();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _altTextCtrl.dispose();
    _orderCtrl.dispose();
    _customRouteCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadExisting() async {
    try {
      final row = await Supabase.instance.client
          .from('home_banners')
          .select()
          .eq('id', widget.bannerId!)
          .single();

      _titleCtrl.text = row['title'] as String? ?? '';
      _altTextCtrl.text = row['alt_text'] as String? ?? '';
      _orderCtrl.text = (row['display_order'] as int? ?? 0).toString();
      _type = (row['type'] as String? ?? 'promo');
      _isActive = row['is_active'] as bool? ?? true;
      _imageUrl = row['image_url'] as String?;

      final route = row['target_route'] as String?;
      if (route != null && route.isNotEmpty) {
        if (_routeOptions.containsKey(route)) {
          _targetRoute = route;
        } else {
          _targetRoute = 'custom';
          _useCustomRoute = true;
          _customRouteCtrl.text = route;
        }
      }

      final from = row['visible_from'] as String?;
      final until = row['visible_until'] as String?;
      if (from != null) _visibleFrom = DateTime.tryParse(from);
      if (until != null) _visibleUntil = DateTime.tryParse(until);

      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load banner: $e')),
        );
      }
    }
  }

  Future<void> _pickAndUploadImage() async {
    setState(() => _uploading = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      final bytes = file.bytes;
      if (bytes == null || bytes.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not read file.')),
        );
        return;
      }

      final ext = (file.extension ?? 'png').toLowerCase();
      final filename = '${const Uuid().v4()}.$ext';

      await Supabase.instance.client.storage
          .from('home-banners')
          .uploadBinary(filename, bytes);

      final url = Supabase.instance.client.storage
          .from('home-banners')
          .getPublicUrl(filename);

      if (!mounted) return;
      setState(() => _imageUrl = url);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Upload failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _pickDateTime(bool isFrom) async {
    final initial = isFrom ? _visibleFrom : _visibleUntil;
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: initial ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 2),
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial ?? now),
    );
    if (time == null || !mounted) return;

    setState(() {
      final dt = DateTime(date.year, date.month, date.day, time.hour, time.minute);
      if (isFrom) {
        _visibleFrom = dt;
      } else {
        _visibleUntil = dt;
      }
    });
  }

  String? _resolveTargetRoute() {
    if (_useCustomRoute) {
      final custom = _customRouteCtrl.text.trim();
      return custom.isEmpty ? null : custom;
    }
    return _targetRoute;
  }

  Future<void> _submit() async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Admin label is required.')),
      );
      return;
    }
    if (_imageUrl == null || _imageUrl!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please upload a banner image.')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final route = _resolveTargetRoute();
      final payload = {
        'title': title,
        'image_url': _imageUrl,
        'type': _type,
        'target_route': route,
        'alt_text': _altTextCtrl.text.trim().isEmpty ? null : _altTextCtrl.text.trim(),
        'display_order': int.tryParse(_orderCtrl.text) ?? 0,
        'is_active': _isActive,
        'visible_from': _visibleFrom?.toUtc().toIso8601String(),
        'visible_until': _visibleUntil?.toUtc().toIso8601String(),
      };

      if (widget.isEditing) {
        await Supabase.instance.client
            .from('home_banners')
            .update(payload)
            .eq('id', widget.bannerId!);
      } else {
        await Supabase.instance.client.from('home_banners').insert(payload);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(widget.isEditing ? 'Banner updated.' : 'Banner created.'),
        ),
      );
      context.go('/admin/home-banners');
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete this banner?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.adminRed),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    try {
      await Supabase.instance.client
          .from('home_banners')
          .delete()
          .eq('id', widget.bannerId!);
      if (!mounted) return;
      context.go('/admin/home-banners');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Delete failed: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final route = _resolveTargetRoute();
    final typeColor = switch (_type) {
      'urgent' => AppColors.adminRed,
      'info' => AppColors.ellieBlue,
      _ => AppColors.gold,
    };

    return Scaffold(
      backgroundColor: AppColors.lightBackground,
      appBar: AppBar(
        backgroundColor: AppColors.lightBackground,
        elevation: 0,
        title: Text(widget.isEditing ? 'Edit Banner' : 'New Banner'),
        actions: [
          if (widget.isEditing)
            TextButton.icon(
              onPressed: _delete,
              icon: const Icon(Icons.delete_outline, color: AppColors.adminRed),
              label: const Text('Delete', style: TextStyle(color: AppColors.adminRed)),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Image preview / upload
              GestureDetector(
                onTap: _uploading ? null : _pickAndUploadImage,
                child: Container(
                  height: 160,
                  decoration: BoxDecoration(
                    color: AppColors.lightBorder,
                    borderRadius: BorderRadius.circular(12),
                    image: _imageUrl != null && _imageUrl!.isNotEmpty
                        ? DecorationImage(
                            image: NetworkImage(_imageUrl!),
                            fit: BoxFit.cover,
                          )
                        : null,
                  ),
                  alignment: Alignment.center,
                  child: _uploading
                      ? const CircularProgressIndicator()
                      : (_imageUrl == null || _imageUrl!.isEmpty
                          ? Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  PhosphorIconsRegular.uploadSimple,
                                  size: 40,
                                  color: AppColors.lightTextSecondary,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Tap to upload image',
                                  style: AppTextStyles.body(
                                    context,
                                    color: AppColors.lightTextSecondary,
                                  ),
                                ),
                              ],
                            )
                          : null),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Recommended: 1125 × 480 px (2.35:1). '
                'Max 2 MB. JPG or PNG. Text/CTA must be baked into the image.',
                style: AppTextStyles.caption(
                  context,
                  color: AppColors.lightTextSecondary,
                ),
              ),
              const SizedBox(height: 20),

              // Admin label
              TextField(
                controller: _titleCtrl,
                decoration: const InputDecoration(
                  labelText: 'Admin label *',
                  hintText: 'e.g. Mother\'s Day 2026',
                ),
              ),
              const SizedBox(height: 16),

              // Type
              InputDecorator(
                decoration: const InputDecoration(labelText: 'Banner type'),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _type,
                    isDense: true,
                    isExpanded: true,
                    items: _bannerTypes
                        .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                        .toList(),
                    onChanged: (v) => setState(() => _type = v ?? 'promo'),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Container(width: 12, height: 12, decoration: BoxDecoration(color: typeColor, shape: BoxShape.circle)),
                  const SizedBox(width: 8),
                  Text(
                    _type == 'promo'
                        ? 'Clickable offer route'
                        : _type == 'info'
                            ? 'Static greeting, no tap action'
                            : 'High-attention alert border',
                    style: AppTextStyles.caption(context, color: AppColors.lightTextSecondary),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Target route
              InputDecorator(
                decoration: const InputDecoration(labelText: 'Tap target'),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String?>(
                    value: _useCustomRoute ? 'custom' : _targetRoute,
                    isDense: true,
                    isExpanded: true,
                    items: [
                      ..._routeOptions.entries.map(
                        (e) => DropdownMenuItem(value: e.key, child: Text(e.value)),
                      ),
                      const DropdownMenuItem(value: 'custom', child: Text('Custom route')),
                    ],
                    onChanged: (v) => setState(() {
                      if (v == 'custom') {
                        _useCustomRoute = true;
                        _targetRoute = null;
                      } else {
                        _useCustomRoute = false;
                        _targetRoute = v;
                      }
                    }),
                  ),
                ),
              ),
              if (_useCustomRoute) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _customRouteCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Custom route',
                    hintText: 'e.g. /club/fit/builder/abc-123',
                  ),
                ),
              ],
              if (route == null || route.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'No target = banner is static (no tap).',
                    style: AppTextStyles.caption(context, color: AppColors.lightTextSecondary),
                  ),
                ),
              const SizedBox(height: 16),

              // Schedule
              Row(
                children: [
                  Expanded(
                    child: _DateTimeChip(
                      label: 'Visible from',
                      value: _visibleFrom,
                      onTap: () => _pickDateTime(true),
                      onClear: () => setState(() => _visibleFrom = null),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _DateTimeChip(
                      label: 'Visible until',
                      value: _visibleUntil,
                      onTap: () => _pickDateTime(false),
                      onClear: () => setState(() => _visibleUntil = null),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Alt text
              TextField(
                controller: _altTextCtrl,
                decoration: const InputDecoration(
                  labelText: 'Alt text (accessibility)',
                  hintText: 'Screen-reader description of the banner image',
                ),
              ),
              const SizedBox(height: 16),

              // Display order
              TextField(
                controller: _orderCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Display order',
                  hintText: '0 = first',
                ),
              ),
              const SizedBox(height: 16),

              // Active toggle
              SwitchListTile(
                title: const Text('Active'),
                subtitle: const Text('Show this banner in the carousel.'),
                value: _isActive,
                onChanged: (v) => setState(() => _isActive = v),
              ),
              const SizedBox(height: 32),

              // Mobile preview
              if (_imageUrl != null && _imageUrl!.isNotEmpty) ...[
                Text(
                  'Mobile preview',
                  style: AppTextStyles.body(context).copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Container(
                  height: 160,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    image: DecorationImage(
                      image: NetworkImage(_imageUrl!),
                      fit: BoxFit.cover,
                    ),
                    border: Border.all(color: AppColors.lightBorder),
                  ),
                  child: route == null || route.isEmpty
                      ? null
                      : Align(
                          alignment: Alignment.bottomCenter,
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'Taps to $route',
                              style: const TextStyle(color: Colors.white, fontSize: 12),
                            ),
                          ),
                        ),
                ),
                const SizedBox(height: 32),
              ],

              // Actions
              Row(
                children: [
                  Expanded(
                    child: AdminSecondaryButton(
                      onPressed: () => context.go('/admin/home-banners'),
                      label: 'Cancel',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: AdminPrimaryButton(
                      onPressed: _saving ? null : _submit,
                      label: _saving
                          ? 'Saving...'
                          : (widget.isEditing ? 'Save Changes' : 'Create Banner'),
                    ),
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

class _DateTimeChip extends StatelessWidget {
  final String label;
  final DateTime? value;
  final VoidCallback onTap;
  final VoidCallback onClear;

  const _DateTimeChip({
    required this.label,
    required this.value,
    required this.onTap,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final text = value == null
        ? 'Always'
        : '${value!.day.toString().padLeft(2, '0')}/${value!.month.toString().padLeft(2, '0')} '
            '${value!.hour.toString().padLeft(2, '0')}:${value!.minute.toString().padLeft(2, '0')}';
    return InputChip(
      label: Text('$label: $text'),
      onPressed: onTap,
      deleteIcon: value == null ? null : const Icon(Icons.clear, size: 18),
      onDeleted: value == null ? null : onClear,
      backgroundColor: AppColors.lightSurface,
      side: const BorderSide(color: AppColors.lightBorder),
    );
  }
}
