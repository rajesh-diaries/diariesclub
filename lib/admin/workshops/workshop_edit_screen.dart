import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../widgets/admin_app_bar.dart';

const _kondapurVenueId = '00000000-0000-0000-0000-000000000001';

/// Create / edit workshop. Route param `id` is either 'new' or an existing
/// workshop UUID. On submit calls admin_workshop_create or
/// admin_workshop_update; both RPCs check admin perms server-side.
///
/// Photo flow: pick file (web XFile.readAsBytes() — same pattern as
/// BUG-006's child photo upload) → upload to workshop-photos bucket via
/// service-role through admin RPC's storage write (admin auth gates the
/// RPC; storage policy gates the bucket). For Module 2.2, simplest path:
/// upload directly via the admin's authenticated session (storage policy
/// allows authenticated SELECT; we add a service-role-only WRITE via
/// admin RPC if needed). Today we do client-side upload using
/// Supabase.storage with the admin's session — works because the
/// admin's RLS path allows them through.
class WorkshopEditScreen extends ConsumerStatefulWidget {
  final String? workshopId; // null = create
  const WorkshopEditScreen({super.key, this.workshopId});

  @override
  ConsumerState<WorkshopEditScreen> createState() =>
      _WorkshopEditScreenState();
}

class _WorkshopEditScreenState extends ConsumerState<WorkshopEditScreen> {
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _ageMinCtrl = TextEditingController();
  final _ageMaxCtrl = TextEditingController();
  final _capacityCtrl = TextEditingController();
  final _priceCtrl = TextEditingController(); // displayed in rupees
  final _xpCtrl = TextEditingController(text: '100');
  final _durationCtrl = TextEditingController(text: '60');

  DateTime? _scheduledAt;
  String? _primaryTrait;
  bool _isPublished = true;
  Uint8List? _photoBytes;
  String? _existingPhotoUrl;
  bool _busy = false;
  bool _loading = true;
  String? _errorText;

  bool get _isEditing => widget.workshopId != null;

  @override
  void initState() {
    super.initState();
    if (_isEditing) {
      _loadExisting();
    } else {
      _loading = false;
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _ageMinCtrl.dispose();
    _ageMaxCtrl.dispose();
    _capacityCtrl.dispose();
    _priceCtrl.dispose();
    _xpCtrl.dispose();
    _durationCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadExisting() async {
    try {
      final row = await Supabase.instance.client
          .from('workshops')
          .select()
          .eq('id', widget.workshopId!)
          .maybeSingle();
      if (!mounted) return;
      if (row == null) {
        setState(() {
          _loading = false;
          _errorText = 'Workshop not found.';
        });
        return;
      }
      setState(() {
        _titleCtrl.text = (row['title'] as String?) ?? '';
        _descCtrl.text = (row['description'] as String?) ?? '';
        _ageMinCtrl.text = (row['age_group_min'] as int?)?.toString() ?? '';
        _ageMaxCtrl.text = (row['age_group_max'] as int?)?.toString() ?? '';
        _capacityCtrl.text = (row['capacity'] as int?)?.toString() ?? '';
        _priceCtrl.text =
            ((row['price_paise'] as int?) ?? 0) ~/ 100 == 0
                ? ''
                : (((row['price_paise'] as int?) ?? 0) / 100).toStringAsFixed(0);
        _xpCtrl.text = (row['xp_award'] as int?)?.toString() ?? '100';
        _durationCtrl.text =
            (row['duration_minutes'] as int?)?.toString() ?? '60';
        final iso = row['scheduled_at'] as String?;
        _scheduledAt = iso != null ? DateTime.parse(iso).toLocal() : null;
        _primaryTrait = row['primary_trait'] as String?;
        _isPublished = (row['is_published'] as bool?) ?? true;
        _existingPhotoUrl = row['cover_image_url'] as String?;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorText = "Couldn't load workshop: $e";
      });
    }
  }

  Future<void> _pickPhoto() async {
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        maxHeight: 1600,
      );
      if (picked == null) return;
      final raw = await picked.readAsBytes();
      if (!mounted) return;
      setState(() => _photoBytes = raw);
    } catch (_) {
      if (!mounted) return;
      setState(() => _errorText = "Couldn't load that image.");
    }
  }

  Future<String?> _uploadPhotoIfNew() async {
    if (_photoBytes == null) return _existingPhotoUrl;
    final fileName = '${const Uuid().v4()}.jpg';
    final path = 'workshops/$fileName';
    await Supabase.instance.client.storage
        .from('workshop-photos')
        .uploadBinary(
          path,
          _photoBytes!,
          fileOptions: const FileOptions(
            contentType: 'image/jpeg',
            upsert: false,
          ),
        );
    final pub = Supabase.instance.client.storage
        .from('workshop-photos')
        .getPublicUrl(path);
    return pub;
  }

  String? _validate() {
    if (_titleCtrl.text.trim().isEmpty) return 'Title is required.';
    if (_scheduledAt == null) return 'Scheduled date is required.';
    if (!_isEditing && _scheduledAt!.isBefore(DateTime.now())) {
      return 'Scheduled date must be in the future.';
    }
    final cap = int.tryParse(_capacityCtrl.text.trim());
    if (cap == null || cap <= 0) return 'Capacity must be a positive number.';
    final dur = int.tryParse(_durationCtrl.text.trim());
    if (dur == null || dur <= 0) return 'Duration must be a positive number.';
    final price = int.tryParse(_priceCtrl.text.trim());
    if (price == null || price < 0) return 'Price must be a non-negative number.';
    return null;
  }

  Future<void> _submit() async {
    final err = _validate();
    if (err != null) {
      setState(() => _errorText = err);
      return;
    }
    setState(() {
      _busy = true;
      _errorText = null;
    });
    try {
      final photoUrl = await _uploadPhotoIfNew();
      final pricePaise = (int.parse(_priceCtrl.text.trim())) * 100;
      final params = {
        'p_title': _titleCtrl.text.trim(),
        'p_description': _descCtrl.text.trim().isEmpty
            ? null
            : _descCtrl.text.trim(),
        'p_scheduled_at': _scheduledAt!.toUtc().toIso8601String(),
        'p_duration_minutes': int.parse(_durationCtrl.text.trim()),
        'p_age_group_min': int.tryParse(_ageMinCtrl.text.trim()),
        'p_age_group_max': int.tryParse(_ageMaxCtrl.text.trim()),
        'p_capacity': int.parse(_capacityCtrl.text.trim()),
        'p_price_paise': pricePaise,
        'p_primary_trait': _primaryTrait,
        'p_xp_award': int.tryParse(_xpCtrl.text.trim()) ?? 100,
        'p_cover_image_url': photoUrl,
        'p_is_published': _isPublished,
      };

      if (_isEditing) {
        await Supabase.instance.client.rpc<dynamic>(
          'admin_workshop_update',
          params: {'p_workshop_id': widget.workshopId, ...params},
        );
      } else {
        await Supabase.instance.client.rpc<dynamic>(
          'admin_workshop_create',
          params: {
            'p_venue_id': _kondapurVenueId,
            'p_idempotency_key': const Uuid().v4(),
            ...params,
          },
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isEditing ? 'Workshop updated' : 'Workshop created',
          ),
        ),
      );
      context.go('/admin/workshops');
    } on PostgrestException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _errorText = _mapError(e.message);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _errorText = 'Could not save: $e';
      });
    }
  }

  String _mapError(String raw) {
    if (raw.contains('not_admin')) return 'You are not authorised.';
    if (raw.contains('scheduled_at_in_past')) {
      return 'Scheduled date must be in the future.';
    }
    if (raw.contains('capacity_below_registrations')) {
      return "Capacity can't drop below already-registered count.";
    }
    if (raw.contains('invalid_')) return 'One of the fields is invalid.';
    return raw;
  }

  Future<void> _pickDateTime() async {
    final initialDate = _scheduledAt ?? DateTime.now().add(const Duration(days: 1));
    final date = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initialDate),
    );
    if (time == null || !mounted) return;
    setState(() {
      _scheduledAt = DateTime(
        date.year, date.month, date.day, time.hour, time.minute,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.lightBackground,
      appBar: AdminAppBar(
        title: _isEditing ? 'Edit workshop' : 'New workshop',
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
                    _photoPicker(),
                    const SizedBox(height: 16),
                    _field('Title', _titleCtrl, hint: 'e.g. Hero Drawing Lab'),
                    const SizedBox(height: 12),
                    _field(
                      'Description',
                      _descCtrl,
                      hint: 'Optional, 1-2 sentences',
                      maxLines: 3,
                    ),
                    const SizedBox(height: 12),
                    _scheduledTile(),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _field(
                            'Duration (min)',
                            _durationCtrl,
                            keyboardType: TextInputType.number,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _field(
                            'Capacity',
                            _capacityCtrl,
                            keyboardType: TextInputType.number,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _field(
                            'Age min',
                            _ageMinCtrl,
                            keyboardType: TextInputType.number,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _field(
                            'Age max',
                            _ageMaxCtrl,
                            keyboardType: TextInputType.number,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _field(
                            'Price (₹)',
                            _priceCtrl,
                            keyboardType: TextInputType.number,
                            hint: '0 for free',
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _field(
                            'XP award',
                            _xpCtrl,
                            keyboardType: TextInputType.number,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _traitPicker(),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      title: const Text('Published'),
                      subtitle: Text(
                        _isPublished
                            ? 'Visible to customers; saving fans out push to opted-in families.'
                            : 'Hidden from customers; no push will be sent.',
                        style: AppTextStyles.caption(
                          context,
                          color: AppColors.lightTextSecondary,
                        ),
                      ),
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
                              : () => context.go('/admin/workshops'),
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

  Widget _field(
    String label,
    TextEditingController ctrl, {
    String? hint,
    int maxLines = 1,
    TextInputType? keyboardType,
  }) {
    return TextField(
      controller: ctrl,
      keyboardType: keyboardType,
      maxLines: maxLines,
      inputFormatters: keyboardType == TextInputType.number
          ? [FilteringTextInputFormatter.digitsOnly]
          : null,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
    );
  }

  Widget _scheduledTile() {
    return InkWell(
      onTap: _busy ? null : _pickDateTime,
      borderRadius: BorderRadius.circular(8),
      child: InputDecorator(
        decoration: const InputDecoration(
          labelText: 'Scheduled at',
          border: OutlineInputBorder(),
          isDense: true,
          suffixIcon: Icon(PhosphorIconsRegular.calendar),
        ),
        child: Text(
          _scheduledAt == null
              ? 'Pick date & time'
              : DateFormat('EEE MMM d, y · h:mm a').format(_scheduledAt!),
        ),
      ),
    );
  }

  Widget _traitPicker() {
    const options = [
      ('rafi', 'Rafi (courage)'),
      ('ellie', 'Ellie (kindness)'),
      ('gerry', 'Gerry (curiosity)'),
      ('zena', 'Zena (creativity)'),
    ];
    return DropdownButtonFormField<String>(
      initialValue: _primaryTrait,
      decoration: const InputDecoration(
        labelText: 'Primary trait (optional)',
        border: OutlineInputBorder(),
        isDense: true,
      ),
      items: [
        const DropdownMenuItem(value: null, child: Text('— None —')),
        for (final o in options)
          DropdownMenuItem(value: o.$1, child: Text(o.$2)),
      ],
      onChanged: _busy ? null : (v) => setState(() => _primaryTrait = v),
    );
  }

  Widget _photoPicker() {
    final hasNew = _photoBytes != null;
    final hasExisting = _existingPhotoUrl != null && _existingPhotoUrl!.isNotEmpty;
    return InkWell(
      onTap: _busy ? null : _pickPhoto,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: 200,
        decoration: BoxDecoration(
          color: AppColors.lightSurface,
          border: Border.all(color: AppColors.lightBorder),
          borderRadius: BorderRadius.circular(8),
          image: hasNew
              ? DecorationImage(
                  image: MemoryImage(_photoBytes!),
                  fit: BoxFit.cover,
                )
              : hasExisting
                  ? DecorationImage(
                      image: NetworkImage(_existingPhotoUrl!),
                      fit: BoxFit.cover,
                    )
                  : null,
        ),
        child: hasNew || hasExisting
            ? Align(
                alignment: Alignment.bottomRight,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      hasNew ? 'New photo' : 'Tap to change',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ),
              )
            : Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      PhosphorIconsRegular.image,
                      size: 36,
                      color: AppColors.lightTextSecondary,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Tap to add cover photo',
                      style: AppTextStyles.caption(
                        context,
                        color: AppColors.lightTextSecondary,
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
