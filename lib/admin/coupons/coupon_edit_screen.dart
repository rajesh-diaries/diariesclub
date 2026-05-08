import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../widgets/admin_app_bar.dart';
import '../widgets/admin_buttons.dart';
import 'coupons_list_screen.dart';

class CouponEditScreen extends ConsumerStatefulWidget {
  final String? id;
  const CouponEditScreen({super.key, this.id});

  @override
  ConsumerState<CouponEditScreen> createState() => _CouponEditScreenState();
}

class _CouponEditScreenState extends ConsumerState<CouponEditScreen> {
  final _codeCtrl = TextEditingController();
  final _valueCtrl = TextEditingController();
  final _maxDiscountCtrl = TextEditingController();
  final _minOrderCtrl = TextEditingController();
  final _maxUsesCtrl = TextEditingController();
  final _maxPerFamilyCtrl = TextEditingController(text: '1');
  final _descriptionCtrl = TextEditingController();

  String _type = 'flat_off';
  DateTime? _validFrom;
  DateTime? _validUntil;
  bool _isActive = true;

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
      _validFrom = DateTime.now();
    }
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    _valueCtrl.dispose();
    _maxDiscountCtrl.dispose();
    _minOrderCtrl.dispose();
    _maxUsesCtrl.dispose();
    _maxPerFamilyCtrl.dispose();
    _descriptionCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadExisting() async {
    try {
      final row = await Supabase.instance.client
          .from('coupons')
          .select()
          .eq('id', widget.id!)
          .maybeSingle();
      if (!mounted) return;
      if (row == null) {
        setState(() {
          _loading = false;
          _errorText = 'Coupon not found.';
        });
        return;
      }
      setState(() {
        _codeCtrl.text = (row['code'] as String?) ?? '';
        _type = (row['type'] as String?) ?? 'flat_off';
        final value = row['value'] as int? ?? 0;
        _valueCtrl.text = _type == 'flat_off'
            ? (value / 100).toStringAsFixed(0) // paise → rupees for editing
            : value.toString();
        final cap = row['max_discount_paise'] as int?;
        _maxDiscountCtrl.text =
            cap == null ? '' : (cap / 100).toStringAsFixed(0);
        final minOrder = row['min_order_paise'] as int? ?? 0;
        _minOrderCtrl.text =
            minOrder == 0 ? '' : (minOrder / 100).toStringAsFixed(0);
        _maxUsesCtrl.text = (row['max_uses'] as int?)?.toString() ?? '';
        _maxPerFamilyCtrl.text = (row['max_per_family'] as int? ?? 1).toString();
        _descriptionCtrl.text = (row['description'] as String?) ?? '';
        _validFrom =
            DateTime.tryParse((row['valid_from'] as String?) ?? '')?.toLocal();
        _validUntil =
            DateTime.tryParse((row['valid_until'] as String?) ?? '')?.toLocal();
        _isActive = (row['is_active'] as bool?) ?? true;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorText = 'Error loading: $e';
      });
    }
  }

  Future<void> _save() async {
    final code = _codeCtrl.text.trim().toUpperCase();
    if (code.isEmpty) {
      setState(() => _errorText = 'Code is required.');
      return;
    }
    final rawValue = int.tryParse(_valueCtrl.text.trim());
    if (_type != 'free_session' && (rawValue == null || rawValue <= 0)) {
      setState(() => _errorText = _type == 'percent_off'
          ? 'Enter a percentage (1–100).'
          : 'Enter the discount in rupees.');
      return;
    }
    if (_type == 'percent_off' && (rawValue ?? 0) > 100) {
      setState(() => _errorText = 'Percent off cannot exceed 100.');
      return;
    }

    // Convert rupees → paise for flat_off and min_order; keep percent value as-is.
    final valueStored =
        _type == 'flat_off' ? (rawValue ?? 0) * 100 : (rawValue ?? 0);
    final maxDiscountRupees = int.tryParse(_maxDiscountCtrl.text.trim());
    final maxDiscountPaise =
        (_type == 'percent_off' && maxDiscountRupees != null && maxDiscountRupees > 0)
            ? maxDiscountRupees * 100
            : null;
    final minOrderRupees = int.tryParse(_minOrderCtrl.text.trim());
    final minOrderPaise =
        (minOrderRupees != null && minOrderRupees > 0) ? minOrderRupees * 100 : 0;
    final maxUses = int.tryParse(_maxUsesCtrl.text.trim());
    final maxPerFamily =
        int.tryParse(_maxPerFamilyCtrl.text.trim()) ?? 1;

    setState(() {
      _busy = true;
      _errorText = null;
    });

    try {
      final payload = <String, dynamic>{
        'code': code,
        'type': _type,
        'value': valueStored,
        'max_discount_paise': maxDiscountPaise,
        'min_order_paise': minOrderPaise,
        'max_uses': maxUses,
        'max_per_family': maxPerFamily,
        'valid_from': (_validFrom ?? DateTime.now()).toUtc().toIso8601String(),
        'valid_until': _validUntil?.toUtc().toIso8601String(),
        'is_active': _isActive,
        'description':
            _descriptionCtrl.text.trim().isEmpty ? null : _descriptionCtrl.text.trim(),
      };

      if (_isEditing) {
        await Supabase.instance.client
            .from('coupons')
            .update(payload)
            .eq('id', widget.id!);
      } else {
        await Supabase.instance.client.from('coupons').insert(payload);
      }
      if (!mounted) return;
      ref.invalidate(couponsAdminListProvider);
      context.go('/admin/coupons');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_isEditing ? 'Coupon updated.' : 'Coupon created.'),
        ),
      );
    } on PostgrestException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _errorText = e.message.contains('coupons_code_key')
            ? 'A coupon with that code already exists.'
            : 'Save failed: ${e.message}';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _errorText = 'Save failed: $e';
      });
    }
  }

  Future<void> _pickDate(bool isFrom) async {
    final initial = (isFrom ? _validFrom : _validUntil) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (isFrom) {
        _validFrom = picked;
      } else {
        _validUntil = picked;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.lightBackground,
      appBar: AdminAppBar(title: _isEditing ? 'Edit coupon' : 'New coupon'),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _Section(
                          title: 'Code',
                          child: TextField(
                            controller: _codeCtrl,
                            textCapitalization: TextCapitalization.characters,
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                RegExp(r'[A-Za-z0-9_-]'),
                              ),
                            ],
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              hintText: 'e.g. WELCOME50',
                            ),
                          ),
                        ),
                        _Section(
                          title: 'Type',
                          child: Column(
                            children: [
                              for (final t in const [
                                ('flat_off', 'Flat ₹ off',
                                    'A fixed rupee amount off the order.'),
                                ('percent_off', 'Percent off',
                                    'A % off, optionally capped to a max ₹ amount.'),
                                ('free_session', 'Free session',
                                    'Reduces the session price to ₹0.'),
                              ])
                                RadioListTile<String>(
                                  // ignore: deprecated_member_use
                                  value: t.$1,
                                  // ignore: deprecated_member_use
                                  groupValue: _type,
                                  // ignore: deprecated_member_use
                                  onChanged: (v) =>
                                      setState(() => _type = v ?? 'flat_off'),
                                  title: Text(t.$2),
                                  subtitle: Text(t.$3),
                                ),
                            ],
                          ),
                        ),
                        if (_type != 'free_session')
                          _Section(
                            title: _type == 'percent_off'
                                ? 'Percentage'
                                : 'Discount in ₹',
                            child: TextField(
                              controller: _valueCtrl,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              decoration: InputDecoration(
                                border: const OutlineInputBorder(),
                                hintText:
                                    _type == 'percent_off' ? '10' : '100',
                                suffixText:
                                    _type == 'percent_off' ? '%' : '₹',
                              ),
                            ),
                          ),
                        if (_type == 'percent_off')
                          _Section(
                            title: 'Max discount in ₹ (optional)',
                            child: TextField(
                              controller: _maxDiscountCtrl,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              decoration: const InputDecoration(
                                border: OutlineInputBorder(),
                                hintText: '500',
                                suffixText: '₹',
                                helperText:
                                    'Caps the discount on big-ticket orders.',
                              ),
                            ),
                          ),
                        _Section(
                          title: 'Minimum order ₹ (optional)',
                          child: TextField(
                            controller: _minOrderCtrl,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              hintText: '0',
                              suffixText: '₹',
                            ),
                          ),
                        ),
                        Row(
                          children: [
                            Expanded(
                              child: _Section(
                                title: 'Total uses (blank = unlimited)',
                                child: TextField(
                                  controller: _maxUsesCtrl,
                                  keyboardType: TextInputType.number,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly,
                                  ],
                                  decoration: const InputDecoration(
                                    border: OutlineInputBorder(),
                                    hintText: 'Leave blank for ∞',
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _Section(
                                title: 'Max per family',
                                child: TextField(
                                  controller: _maxPerFamilyCtrl,
                                  keyboardType: TextInputType.number,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly,
                                  ],
                                  decoration: const InputDecoration(
                                    border: OutlineInputBorder(),
                                    hintText: '1',
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            Expanded(
                              child: _Section(
                                title: 'Valid from',
                                child: _DateRow(
                                  date: _validFrom,
                                  onTap: () => _pickDate(true),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _Section(
                                title: 'Valid until (optional)',
                                child: _DateRow(
                                  date: _validUntil,
                                  onTap: () => _pickDate(false),
                                  onClear: _validUntil == null
                                      ? null
                                      : () =>
                                          setState(() => _validUntil = null),
                                ),
                              ),
                            ),
                          ],
                        ),
                        _Section(
                          title: 'Description (admin only)',
                          child: TextField(
                            controller: _descriptionCtrl,
                            maxLines: 2,
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              hintText: 'Internal note about this coupon',
                            ),
                          ),
                        ),
                        SwitchListTile(
                          value: _isActive,
                          onChanged: (v) => setState(() => _isActive = v),
                          title: const Text('Active'),
                          subtitle: const Text(
                            'Customers can redeem only when this is on.',
                          ),
                        ),
                        if (_errorText != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            _errorText!,
                            style: AppTextStyles.body(
                              context,
                              color: AppColors.adminRed,
                            ),
                          ),
                        ],
                        const SizedBox(height: 24),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            AdminSecondaryButton(
                              label: 'Cancel',
                              ghost: true,
                              onPressed: _busy
                                  ? null
                                  : () => context.go('/admin/coupons'),
                            ),
                            const SizedBox(width: 12),
                            AdminPrimaryButton(
                              label: _isEditing ? 'Save' : 'Create',
                              busy: _busy,
                              onPressed: _busy ? null : _save,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppTextStyles.caption(context)),
          const SizedBox(height: 6),
          child,
        ],
      ),
    );
  }
}

class _DateRow extends StatelessWidget {
  final DateTime? date;
  final VoidCallback onTap;
  final VoidCallback? onClear;
  const _DateRow({required this.date, required this.onTap, this.onClear});

  @override
  Widget build(BuildContext context) {
    final label = date == null ? 'Pick a date' : DateFormat('MMM d, y').format(date!);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.lightBorder),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Expanded(child: Text(label, style: AppTextStyles.body(context))),
              if (onClear != null)
                AdminIconButton(
                  icon: Icons.clear,
                  size: 18,
                  onPressed: onClear,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
