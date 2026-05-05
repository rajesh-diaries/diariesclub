import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../widgets/admin_app_bar.dart';

const _kondapurVenueId = '00000000-0000-0000-0000-000000000001';

const _routeOptions = <String, String>{
  '': '— None —',
  '/club/workshops': 'Workshops list',
  '/club': 'Club tab',
  '/birthday': 'Birthday discovery',
  '/home': 'Home',
};

class AnnouncementEditScreen extends ConsumerStatefulWidget {
  final String? id;
  const AnnouncementEditScreen({super.key, this.id});

  @override
  ConsumerState<AnnouncementEditScreen> createState() =>
      _AnnouncementEditScreenState();
}

class _AnnouncementEditScreenState
    extends ConsumerState<AnnouncementEditScreen> {
  final _titleCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();
  final _photoUrlCtrl = TextEditingController();
  final _ctaLabelCtrl = TextEditingController();

  String _type = 'general';
  String _ctaRoute = '';
  DateTime? _visibleFrom;
  DateTime? _visibleUntil;
  bool _isPublished = true;
  bool _isWorkshopSourced = false;

  bool _busy = false;
  bool _loading = true;
  String? _errorText;

  bool get _isEditing => widget.id != null;

  @override
  void initState() {
    super.initState();
    if (_isEditing) {
      _loadExisting();
    } else {
      _loading = false;
      _visibleFrom = DateTime.now();
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    _photoUrlCtrl.dispose();
    _ctaLabelCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadExisting() async {
    try {
      final row = await Supabase.instance.client
          .from('announcements')
          .select()
          .eq('id', widget.id!)
          .maybeSingle();
      if (!mounted) return;
      if (row == null) {
        setState(() {
          _loading = false;
          _errorText = 'Announcement not found.';
        });
        return;
      }
      setState(() {
        _titleCtrl.text = (row['title'] as String?) ?? '';
        _bodyCtrl.text = (row['body'] as String?) ?? '';
        _photoUrlCtrl.text = (row['photo_url'] as String?) ?? '';
        _ctaLabelCtrl.text = (row['cta_label'] as String?) ?? '';
        _type = (row['type'] as String?) ?? 'general';
        _ctaRoute = (row['cta_route'] as String?) ?? '';
        _visibleFrom =
            DateTime.tryParse((row['visible_from'] as String?) ?? '')?.toLocal();
        _visibleUntil =
            DateTime.tryParse((row['visible_until'] as String?) ?? '')?.toLocal();
        _isPublished = (row['is_published'] as bool?) ?? true;
        _isWorkshopSourced = row['source_workshop_id'] != null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorText = "Couldn't load announcement: $e";
      });
    }
  }

  Future<void> _submit() async {
    if (_titleCtrl.text.trim().isEmpty) {
      setState(() => _errorText = 'Title is required.');
      return;
    }
    if (_visibleUntil != null &&
        _visibleFrom != null &&
        _visibleUntil!.isBefore(_visibleFrom!)) {
      setState(() => _errorText = 'End time must be after start time.');
      return;
    }

    setState(() {
      _busy = true;
      _errorText = null;
    });

    final params = {
      'p_title': _titleCtrl.text.trim(),
      'p_body': _bodyCtrl.text.trim().isEmpty ? null : _bodyCtrl.text.trim(),
      'p_type': _type,
      'p_cta_label':
          _ctaLabelCtrl.text.trim().isEmpty ? null : _ctaLabelCtrl.text.trim(),
      'p_cta_route': _ctaRoute.isEmpty ? null : _ctaRoute,
      'p_photo_url':
          _photoUrlCtrl.text.trim().isEmpty ? null : _photoUrlCtrl.text.trim(),
      'p_visible_from': _visibleFrom?.toUtc().toIso8601String(),
      'p_visible_until': _visibleUntil?.toUtc().toIso8601String(),
      'p_is_published': _isPublished,
    };

    try {
      if (_isEditing) {
        await Supabase.instance.client.rpc<dynamic>(
          'admin_announcement_update',
          params: {'p_id': widget.id, ...params},
        );
      } else {
        await Supabase.instance.client.rpc<dynamic>(
          'admin_announcement_create',
          params: {'p_venue_id': _kondapurVenueId, ...params},
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_isEditing ? 'Saved' : 'Created'),
        ),
      );
      context.go('/admin/announcements');
    } on PostgrestException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _errorText = e.message.contains('not_admin')
            ? 'You are not authorised.'
            : e.message.contains('visible_until_before_from')
                ? 'End time must be after start time.'
                : e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _errorText = 'Could not save: $e';
      });
    }
  }

  Future<void> _pickFrom() async {
    final picked = await _pickDateTime(_visibleFrom ?? DateTime.now());
    if (picked != null) setState(() => _visibleFrom = picked);
  }

  Future<void> _pickUntil() async {
    final picked = await _pickDateTime(
      _visibleUntil ?? (_visibleFrom ?? DateTime.now()).add(const Duration(days: 7)),
    );
    if (picked != null) setState(() => _visibleUntil = picked);
  }

  Future<DateTime?> _pickDateTime(DateTime initial) async {
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
    );
    if (date == null || !mounted) return null;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null || !mounted) return null;
    return DateTime(
      date.year, date.month, date.day, time.hour, time.minute,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.lightBackground,
      appBar: AdminAppBar(
        title: _isEditing ? 'Edit announcement' : 'New announcement',
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_isWorkshopSourced)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: AppColors.navy.withValues(alpha: 0.06),
                          border: Border.all(
                            color: AppColors.navy.withValues(alpha: 0.30),
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              PhosphorIconsRegular.linkSimple,
                              size: 18,
                              color: AppColors.navy,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Auto-created from a workshop. Title/body editable; '
                                'CTA stays linked to /club/workshops.',
                                style: AppTextStyles.body(context),
                              ),
                            ),
                          ],
                        ),
                      ),
                    TextField(
                      controller: _titleCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Title',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _bodyCtrl,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Body (optional)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: _type,
                      decoration: const InputDecoration(
                        labelText: 'Type',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'workshop', child: Text('Workshop')),
                        DropdownMenuItem(value: 'promo', child: Text('Promo')),
                        DropdownMenuItem(value: 'event', child: Text('Event')),
                        DropdownMenuItem(value: 'general', child: Text('General')),
                        DropdownMenuItem(value: 'closure', child: Text('Closure')),
                      ],
                      onChanged: _busy
                          ? null
                          : (v) => setState(() => _type = v ?? 'general'),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _ctaLabelCtrl,
                            decoration: const InputDecoration(
                              labelText: 'CTA label (optional)',
                              hintText: 'e.g. Book your spot',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: _ctaRoute,
                            decoration: const InputDecoration(
                              labelText: 'CTA route',
                              border: OutlineInputBorder(),
                            ),
                            items: [
                              for (final e in _routeOptions.entries)
                                DropdownMenuItem(
                                  value: e.key,
                                  child: Text(e.value),
                                ),
                            ],
                            onChanged: _busy
                                ? null
                                : (v) => setState(() => _ctaRoute = v ?? ''),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _photoUrlCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Photo URL (optional)',
                        hintText: 'Public image URL',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(child: _dateTile('Visible from', _visibleFrom, _pickFrom)),
                        const SizedBox(width: 12),
                        Expanded(child: _dateTile('Visible until (optional)', _visibleUntil, _pickUntil)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      title: const Text('Published'),
                      value: _isPublished,
                      onChanged: _busy
                          ? null
                          : (v) => setState(() => _isPublished = v),
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
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => context.go('/admin/announcements'),
                          child: const Text('Cancel'),
                        ),
                        const SizedBox(width: 12),
                        FilledButton(
                          onPressed: _busy ? null : _submit,
                          child: _busy
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor:
                                        AlwaysStoppedAnimation(Colors.white),
                                  ),
                                )
                              : Text(_isEditing ? 'Save' : 'Create'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _dateTile(String label, DateTime? value, VoidCallback onTap) {
    return InkWell(
      onTap: _busy ? null : onTap,
      borderRadius: BorderRadius.circular(8),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
          suffixIcon: const Icon(PhosphorIconsRegular.calendar),
        ),
        child: Text(
          value == null
              ? 'Pick date & time'
              : DateFormat('MMM d, y · h:mm a').format(value),
        ),
      ),
    );
  }
}
