import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/providers/current_family_provider.dart';
import '../../../core/providers/venue_config_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/phone.dart';
import '../../../core/widgets/primary_button.dart';

/// Edit family name. Phone is shown read-only with a "contact support"
/// link (opens WhatsApp via venue_config.whatsapp_support_phone). Email
/// is intentionally not collected — see docs/POLICY_INVENTORY.md §2.1.
class EditProfileSheet extends ConsumerStatefulWidget {
  final Map<String, dynamic> family;
  const EditProfileSheet({super.key, required this.family});

  @override
  ConsumerState<EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends ConsumerState<EditProfileSheet> {
  late final TextEditingController _nameController;
  bool _busy = false;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: (widget.family['name'] as String?) ?? '',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();

    if (name.isEmpty) {
      setState(() => _errorText = 'Family name is required.');
      return;
    }
    if (name.length > 80) {
      setState(() => _errorText = 'Family name is too long.');
      return;
    }

    setState(() {
      _busy = true;
      _errorText = null;
    });

    try {
      await Supabase.instance.client
          .rpc<Map<String, dynamic>>('family_update', params: {
        'p_name': name,
      });
      ref.invalidate(currentFamilyProvider);
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile updated')),
      );
    } on PostgrestException catch (e) {
      setState(() {
        _busy = false;
        _errorText = _mapError(e.message);
      });
    } catch (_) {
      setState(() {
        _busy = false;
        _errorText = "Couldn't save. Please try again.";
      });
    }
  }

  String _mapError(String msg) {
    if (msg.contains('invalid_name')) return 'Family name is required.';
    return "Couldn't save. Please try again.";
  }

  Future<void> _openSupportWhatsapp() async {
    final cfg = ref.read(venueConfigProvider).valueOrNull;
    final supportPhone = cfg?['whatsapp_support_phone'] as String?;
    if (supportPhone == null || supportPhone.isEmpty) return;
    final num = supportPhone.replaceAll(RegExp(r'[^\d]'), '');
    final text = Uri.encodeComponent(
      "Hi, I'd like to change the phone number on my Play Diaries account.",
    );
    await launchUrl(
      Uri.parse('https://wa.me/$num?text=$text'),
      mode: LaunchMode.externalApplication,
    );
  }

  @override
  Widget build(BuildContext context) {
    final phone = (widget.family['phone'] as String?) ?? '';

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        top: 12,
        left: 24,
        right: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.lightBorder,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Edit profile', style: AppTextStyles.h2(context)),
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _nameController,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: 'Family name',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            style: AppTextStyles.body(context),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.lightBackground,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Phone',
                  style: AppTextStyles.caption(
                    context,
                    color: AppColors.lightTextSecondary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  phone.isEmpty ? '—' : PhoneNormalizer.forDisplay(phone),
                  style: AppTextStyles.body(context),
                ),
                const SizedBox(height: 8),
                InkWell(
                  onTap: _openSupportWhatsapp,
                  child: Text(
                    'Contact support to change phone',
                    style: AppTextStyles.caption(
                      context,
                      color: AppColors.navy,
                    ).copyWith(decoration: TextDecoration.underline),
                  ),
                ),
              ],
            ),
          ),
          if (_errorText != null) ...[
            const SizedBox(height: 12),
            Text(
              _errorText!,
              style: AppTextStyles.caption(context, color: AppColors.adminRed),
            ),
          ],
          const SizedBox(height: 20),
          PrimaryButton(
            label: 'Save',
            onPressed: _busy ? null : _save,
            loading: _busy,
          ),
        ],
      ),
    );
  }
}
